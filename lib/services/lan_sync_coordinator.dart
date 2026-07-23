import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/lan_pairing_payload.dart';
import '../models/lan_peer.dart';
import '../models/model_config.dart';
import '../models/sync_change.dart';
import '../repositories/lan_peer_repository.dart';
import 'device_identity_service.dart';
import 'lan_mdns_service.dart';
import 'lan_pairing_payload_codec.dart';
import 'lan_peer_proof_service.dart';
import 'plugin_sync_validation.dart';
import 'lan_secure_transport.dart';
import 'lan_secret_transfer_service.dart';
import 'lan_sync_storage.dart';
import 'lan_tls_certificate_service.dart';

typedef LanPairingConfirmation =
    Future<bool> Function(String displayName, String fingerprint);
typedef LanModelReader = List<ModelConfig> Function();

class LanPairingResult {
  const LanPairingResult({required this.synced, this.syncError});

  final bool synced;
  final Object? syncError;
}

class LanSyncCoordinator {
  LanSyncCoordinator({
    required this.identityService,
    required this.peerRepository,
    required this.certificateService,
    required this.mdnsService,
    required this.syncStorage,
    required this.secretTransferService,
    required this.confirmPairing,
    required this.readModels,
    this.beforeRemoteApply,
    this.onRemoteApplied,
    LanPairingPayloadCodec? payloadCodec,
  }) : payloadCodec = payloadCodec ?? LanPairingPayloadCodec(),
       proofService = LanPeerProofService(identityService);

  final DeviceIdentityService identityService;
  final LanPeerRepository peerRepository;
  final LanTlsCertificateService certificateService;
  final LanMdnsService mdnsService;
  final LanSyncStorage syncStorage;
  // The coordinator owns this per-instance transfer service and closes it.
  final LanSecretTransferService secretTransferService;
  LanPairingConfirmation confirmPairing;
  final LanModelReader readModels;
  final Future<void> Function()? beforeRemoteApply;
  final Future<void> Function()? onRemoteApplied;
  final LanPairingPayloadCodec payloadCodec;
  final LanPeerProofService proofService;

  SecureServerSocket? _server;
  StreamSubscription<SecureSocket>? _serverSubscription;
  String _displayName = 'LynAI device';
  int _activeConnections = 0;
  Future<void> _syncQueue = Future.value();
  Future<int>? _hostStart;
  Future<void>? _closeFuture;

  static const _maxConnections = 8;
  static const _maxChanges = 1000;
  static const _maxBlobDescriptors = 512;
  static const _maxSessionBytes = 128 * 1024 * 1024;
  static const _authDeadline = Duration(seconds: 10);
  static const _sessionDeadline = Duration(minutes: 2);

  static bool admitsConnection(
    String? selectedProtocol,
    int activeConnections,
  ) => selectedProtocol == 'lynai-lan/1' && activeConnections < _maxConnections;

  Future<int> startHost({String? displayName}) {
    _displayName = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : _displayName;
    if (_server != null) return Future.value(_server!.port);
    return _hostStart ??= _startHost().whenComplete(() => _hostStart = null);
  }

  Future<int> _startHost() async {
    final identity = await identityService.initialize();
    await syncStorage.activate(identity.deviceId);
    final material = await certificateService.loadOrCreate();
    SecureServerSocket? server;
    StreamSubscription<SecureSocket>? subscription;
    try {
      server = await SecureServerSocket.bind(
        InternetAddress.anyIPv4,
        0,
        material.serverContext(),
        shared: true,
      );
      subscription = server.listen(
        (socket) => unawaited(_accept(socket)),
        onError: (_) {},
      );
      await mdnsService.advertise(
        displayName: _displayName,
        deviceId: identity.deviceId,
        port: server.port,
        protocolVersion: LanPairingPayloadCodec.protocolVersion,
      );
      _server = server;
      _serverSubscription = subscription;
      return server.port;
    } catch (_) {
      await subscription?.cancel();
      await server?.close();
      rethrow;
    }
  }

  Future<String> createPairingPayload({
    Duration validity = const Duration(minutes: 3),
  }) async {
    final port = await startHost();
    final now = DateTime.now().toUtc();
    final nonce = proofService.randomNonce();
    final session = LanPairingSession(
      nonce: nonce,
      createdAt: now,
      expiresAt: now.add(validity),
    );
    await peerRepository.savePairingSession(session);
    final material = await certificateService.loadOrCreate();
    return payloadCodec.create(
      identityService: identityService,
      spkiSha256: material.spkiSha256,
      certificateExpiresAt: material.expiresAt,
      nonce: nonce,
      addresses: await _localAddresses(),
      port: port,
      expiresAt: session.expiresAt,
    );
  }

  Future<LanPairingResult> pair(String encodedPayload) async {
    final payload = await payloadCodec.decodeAndVerify(encodedPayload);
    final identity = await identityService.initialize();
    await syncStorage.activate(identity.deviceId);
    await runOutboundAttempts(
      payload.addresses,
      connect: (address) async => LanSecureTransport(
        await _connectPinned(address, payload.port, payload),
      ),
      run: (transport) => _pairAsClient(transport, payload),
      close: (transport) => transport.close(),
      failureMessage: 'unable to connect to pairing host',
    );
    final peer = await peerRepository.peer(payload.deviceId);
    if (peer == null || peer.revoked) {
      throw StateError('paired peer was not persisted');
    }
    try {
      await runOutboundAttempts(
        payload.addresses,
        connect: (address) async => LanSecureTransport(
          await _connectPinned(
            address,
            payload.port,
            null,
            expectedSpki: peer.spkiSha256,
          ),
        ),
        run: (transport) async {
          await _rememberCurrentCertificate(peer.deviceId, transport.socket);
          await _serializeSync(() => _syncAsClient(transport, peer));
        },
        close: (transport) => transport.close(),
        failureMessage: 'initial sync after pairing failed',
      );
      return const LanPairingResult(synced: true);
    } catch (error) {
      return LanPairingResult(synced: false, syncError: error);
    }
  }

  Future<void> syncPeer(LanDiscoveredPeer discovered) async {
    final peer = await peerRepository.peer(discovered.deviceId);
    if (peer == null || peer.revoked) throw StateError('peer is not trusted');
    await runOutboundAttempts(
      discovered.addresses,
      connect: (address) async => LanSecureTransport(
        await _connectPinned(
          address,
          discovered.port,
          null,
          expectedSpki: peer.spkiSha256,
        ),
      ),
      run: (transport) async {
        await _rememberCurrentCertificate(peer.deviceId, transport.socket);
        await _serializeSync(() => _syncAsClient(transport, peer));
      },
      close: (transport) => transport.close(),
      failureMessage: 'unable to sync trusted peer',
    );
  }

  Future<String> requestSecretTransfer(
    LanDiscoveredPeer discovered, {
    required String direction,
  }) async {
    final peer = await _trustedDiscoveredPeer(discovered);
    final transferId = secretTransferService.createTransferId();
    secretTransferService.authorize(
      peerDeviceId: peer.deviceId,
      transferId: transferId,
      direction: direction,
    );
    await _runSecretTransfer(discovered, peer, transferId, direction);
    return transferId;
  }

  Future<void> completeSecretTransfer(
    LanDiscoveredPeer discovered, {
    required String transferId,
    required String direction,
  }) async {
    final peer = await _trustedDiscoveredPeer(discovered);
    await _runSecretTransfer(discovered, peer, transferId, direction);
  }

  Future<LanPeer> _trustedDiscoveredPeer(LanDiscoveredPeer discovered) async {
    final peer = await peerRepository.peer(discovered.deviceId);
    if (peer == null || peer.revoked) throw StateError('peer is not trusted');
    return peer;
  }

  Future<void> _runSecretTransfer(
    LanDiscoveredPeer discovered,
    LanPeer peer,
    String transferId,
    String direction,
  ) async {
    if (!const {'send', 'receive'}.contains(direction)) {
      throw const FormatException('invalid secret-transfer direction');
    }
    await runOutboundAttempts(
      discovered.addresses,
      connect: (address) async => LanSecureTransport(
        await _connectPinned(
          address,
          discovered.port,
          null,
          expectedSpki: peer.spkiSha256,
        ),
      ),
      run: (transport) async {
        await _rememberCurrentCertificate(peer.deviceId, transport.socket);
        await _secretAsClient(transport, peer, transferId, direction);
      },
      close: (transport) => transport.close(),
      failureMessage: 'unable to transfer secrets to trusted peer',
    );
  }

  static Future<void> runOutboundAttempts<T>(
    Iterable<String> addresses, {
    required Future<T> Function(String address) connect,
    required Future<void> Function(T connection) run,
    required Future<void> Function(T connection) close,
    required String failureMessage,
  }) async {
    Object? lastError;
    for (final address in addresses) {
      T? connection;
      var succeeded = false;
      try {
        final established = await connect(address);
        connection = established;
        await run(established);
        succeeded = true;
      } catch (error) {
        lastError = error;
      } finally {
        if (connection != null) {
          try {
            await close(connection);
          } catch (error) {
            lastError = error;
            succeeded = false;
          }
        }
      }
      if (succeeded) return;
    }
    throw StateError('$failureMessage: $lastError');
  }

  Future<SecureSocket> _connectPinned(
    String address,
    int port,
    LanPairingPayload? payload, {
    String? expectedSpki,
  }) async {
    late SecureSocket socket;
    final expected = expectedSpki ?? payload!.spkiSha256;
    socket = await SecureSocket.connect(
      address,
      port,
      context: SecurityContext(withTrustedRoots: false)
        ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3,
      supportedProtocols: const ['lynai-lan/1'],
      onBadCertificate: (certificate) {
        final actual = certificateService.spkiSha256FromCertificateDer(
          certificate.der,
        );
        return actual == expected;
      },
      timeout: const Duration(seconds: 8),
    );
    if (socket.selectedProtocol != 'lynai-lan/1') {
      await socket.close();
      throw StateError('LAN ALPN negotiation failed');
    }
    final certificate = socket.peerCertificate;
    if (certificate == null ||
        !certificateService.certificateIsValidAt(
          certificate.der,
          DateTime.now(),
        ) ||
        certificateService.spkiSha256FromCertificateDer(certificate.der) !=
            expected) {
      await socket.close();
      throw StateError('LAN certificate SPKI mismatch');
    }
    return socket;
  }

  Future<void> _pairAsClient(
    LanSecureTransport transport,
    LanPairingPayload payload,
  ) async {
    final sessionId = _sessionId();
    transport.bindSession(
      sessionId: sessionId,
      purpose: 'pairing',
      localRole: 'initiator',
      remoteRole: 'responder',
    );
    final identity = await identityService.initialize();
    final localNonce = proofService.randomNonce();
    await transport.send('pair-hello', {
      'pairingNonce': payload.nonce,
      'nonce': localNonce,
      'deviceId': identity.deviceId,
      'publicKey': base64UrlEncode(identity.publicKey).replaceAll('=', ''),
    });
    final challenge = await transport
        .receive(expectedTypes: const {'pair-challenge'})
        .timeout(_authDeadline);
    final remoteNonce = challenge.body['nonce'] as String;
    final hostProof = LanPeerProof.fromJson(
      Map<String, dynamic>.from(challenge.body['proof'] as Map),
    );
    if (!await proofService.verify(
      hostProof,
      expectedSessionId: sessionId,
      expectedLocalNonce: remoteNonce,
      expectedRemoteNonce: localNonce,
      expectedPurpose: 'pairing',
      expectedSignerRole: 'responder',
      initiatorDeviceId: identity.deviceId,
      initiatorPublicKey: identity.publicKey,
      responderDeviceId: payload.deviceId,
      responderPublicKey: payload.publicKey,
      expectedDeviceId: payload.deviceId,
      expectedPublicKey: payload.publicKey,
    )) {
      throw StateError('invalid host device proof');
    }
    final approved = await confirmPairing(
      challenge.body['displayName'] as String? ?? 'LynAI device',
      proofService.sas(
        sessionId: sessionId,
        purpose: 'pairing',
        initiatorDeviceId: identity.deviceId,
        initiatorPublicKey: identity.publicKey,
        initiatorNonce: localNonce,
        responderDeviceId: payload.deviceId,
        responderPublicKey: payload.publicKey,
        responderNonce: remoteNonce,
      ),
    );
    if (!approved) throw StateError('pairing was not confirmed');
    final proof = await proofService.create(
      sessionId: sessionId,
      localNonce: localNonce,
      remoteNonce: remoteNonce,
      purpose: 'pairing',
      signerRole: 'initiator',
      initiatorDeviceId: identity.deviceId,
      responderDeviceId: payload.deviceId,
      initiatorPublicKey: identity.publicKey,
      responderPublicKey: payload.publicKey,
    );
    final binding = await certificateService.createBinding(payload.nonce);
    await transport.send('pair-proof', {
      'proof': proof.toJson(),
      'binding': binding.toJson(),
    });
    final result = await transport
        .receive(expectedTypes: const {'pair-ok'})
        .timeout(_authDeadline);
    transport.markAuthenticated();
    await peerRepository.trustPeer(
      LanPeer(
        deviceId: payload.deviceId,
        publicKey: payload.publicKey,
        spkiSha256: payload.spkiSha256,
        displayName: result.body['displayName'] as String? ?? 'LynAI device',
        trustedAt: DateTime.now().toUtc(),
        certificateExpiresAt: payload.certificateExpiresAt,
      ),
    );
  }

  Future<void> _accept(SecureSocket socket) async {
    if (!admitsConnection(socket.selectedProtocol, _activeConnections)) {
      await socket.close();
      return;
    }
    _activeConnections++;
    LanSecureTransport? transport;
    try {
      transport = LanSecureTransport(socket);
      final first = await transport
          .receive(
            expectedTypes: const {'pair-hello', 'sync-hello', 'secret-hello'},
            expectedPurposes: const {'pairing', 'sync', 'secret-transfer'},
          )
          .timeout(_authDeadline);
      if (first.type == 'pair-hello') {
        await _pairAsHost(transport, first);
      } else if (first.type == 'sync-hello') {
        await _syncAsHost(transport, first);
      } else if (first.type == 'secret-hello') {
        await _secretAsHost(transport, first);
      } else {
        throw StateError('unsupported LAN session');
      }
    } finally {
      await closeAndReleaseConnection(
        close: () => transport?.close() ?? socket.close(),
        release: () => _activeConnections--,
      );
    }
  }

  static Future<void> closeAndReleaseConnection({
    required Future<void> Function() close,
    required void Function() release,
  }) async {
    try {
      await close();
    } finally {
      release();
    }
  }

  Future<void> _pairAsHost(LanSecureTransport transport, LanFrame hello) async {
    final pairingNonce = hello.body['pairingNonce'] as String;
    final remoteNonce = hello.body['nonce'] as String;
    final remoteDeviceId = hello.body['deviceId'] as String;
    final remotePublicKey = base64Url.decode(
      base64Url.normalize(hello.body['publicKey'] as String),
    );
    if (DeviceIdentityService.deviceIdForPublicKey(remotePublicKey) !=
        remoteDeviceId) {
      throw StateError('invalid pairing initiator identity');
    }
    final identity = await identityService.initialize();
    final localNonce = proofService.randomNonce();
    final proof = await proofService.create(
      sessionId: hello.sessionId,
      localNonce: localNonce,
      remoteNonce: remoteNonce,
      purpose: 'pairing',
      signerRole: 'responder',
      initiatorDeviceId: remoteDeviceId,
      responderDeviceId: identity.deviceId,
      initiatorPublicKey: remotePublicKey,
      responderPublicKey: identity.publicKey,
    );
    await transport.send('pair-challenge', {
      'nonce': localNonce,
      'proof': proof.toJson(),
      'displayName': _displayName,
    });
    final response = await transport
        .receive(expectedTypes: const {'pair-proof'})
        .timeout(_authDeadline);
    final remoteProof = LanPeerProof.fromJson(
      Map<String, dynamic>.from(response.body['proof'] as Map),
    );
    final binding = LanTlsBinding.fromJson(
      Map<String, dynamic>.from(response.body['binding'] as Map),
    );
    if (!await proofService.verify(
          remoteProof,
          expectedSessionId: hello.sessionId,
          expectedLocalNonce: remoteNonce,
          expectedRemoteNonce: localNonce,
          expectedPurpose: 'pairing',
          expectedSignerRole: 'initiator',
          initiatorDeviceId: remoteDeviceId,
          initiatorPublicKey: remotePublicKey,
          responderDeviceId: identity.deviceId,
          responderPublicKey: identity.publicKey,
        ) ||
        !await payloadCodec.verifyBinding(binding) ||
        binding.deviceId != remoteProof.deviceId ||
        binding.pairingNonce != pairingNonce ||
        !binding.certificateExpiresAt.toUtc().isAfter(DateTime.now().toUtc())) {
      throw StateError('invalid pairing peer proof');
    }
    final approved = await confirmPairing(
      'LynAI device',
      proofService.sas(
        sessionId: hello.sessionId,
        purpose: 'pairing',
        initiatorDeviceId: remoteDeviceId,
        initiatorPublicKey: remotePublicKey,
        initiatorNonce: remoteNonce,
        responderDeviceId: identity.deviceId,
        responderPublicKey: identity.publicKey,
        responderNonce: localNonce,
      ),
    );
    if (!approved ||
        !await peerRepository.consumePairingNonce(
          pairingNonce,
          remoteProof.deviceId,
        )) {
      throw StateError('pairing nonce rejected');
    }
    await peerRepository.trustPeer(
      LanPeer(
        deviceId: remoteProof.deviceId,
        publicKey: remoteProof.publicKey,
        spkiSha256: binding.spkiSha256,
        displayName: 'LynAI device',
        trustedAt: DateTime.now().toUtc(),
        certificateExpiresAt: binding.certificateExpiresAt,
      ),
    );
    transport.markAuthenticated();
    await transport.send('pair-ok', {'displayName': _displayName});
  }

  Future<void> _syncAsClient(LanSecureTransport transport, LanPeer peer) async {
    final sessionId = _sessionId();
    transport.bindSession(
      sessionId: sessionId,
      purpose: 'sync',
      localRole: 'initiator',
      remoteRole: 'responder',
    );
    final identity = await identityService.initialize();
    final localNonce = proofService.randomNonce();
    await transport.send('sync-hello', {
      'deviceId': identity.deviceId,
      'nonce': localNonce,
    });
    final challenge = await transport
        .receive(expectedTypes: const {'sync-challenge'})
        .timeout(_authDeadline);
    final remoteNonce = challenge.body['nonce'] as String;
    final remoteProof = LanPeerProof.fromJson(
      Map<String, dynamic>.from(challenge.body['proof'] as Map),
    );
    if (!await proofService.verify(
      remoteProof,
      expectedSessionId: sessionId,
      expectedLocalNonce: remoteNonce,
      expectedRemoteNonce: localNonce,
      expectedPurpose: 'sync',
      expectedSignerRole: 'responder',
      initiatorDeviceId: identity.deviceId,
      initiatorPublicKey: identity.publicKey,
      responderDeviceId: peer.deviceId,
      responderPublicKey: peer.publicKey,
      expectedDeviceId: peer.deviceId,
      expectedPublicKey: peer.publicKey,
    )) {
      throw StateError('trusted peer proof failed');
    }
    await transport.send('sync-proof', {
      'proof': (await proofService.create(
        sessionId: sessionId,
        localNonce: localNonce,
        remoteNonce: remoteNonce,
        purpose: 'sync',
        signerRole: 'initiator',
        initiatorDeviceId: identity.deviceId,
        responderDeviceId: peer.deviceId,
        initiatorPublicKey: identity.publicKey,
        responderPublicKey: peer.publicKey,
      )).toJson(),
    });
    final ready = await transport
        .receive(expectedTypes: const {'sync-ready'})
        .timeout(_authDeadline);
    if (ready.body.isNotEmpty) throw StateError('invalid sync-ready frame');
    transport.markAuthenticated();
    await _exchange(
      transport,
      peer.deviceId,
      initiator: true,
    ).timeout(_sessionDeadline);
  }

  Future<void> _syncAsHost(LanSecureTransport transport, LanFrame hello) async {
    final deviceId = hello.body['deviceId'] as String;
    final peer = await peerRepository.peer(deviceId);
    if (peer == null || peer.revoked) {
      throw StateError('unknown or revoked peer');
    }
    final remoteNonce = hello.body['nonce'] as String;
    final localNonce = proofService.randomNonce();
    final identity = await identityService.initialize();
    await transport.send('sync-challenge', {
      'nonce': localNonce,
      'proof': (await proofService.create(
        sessionId: hello.sessionId,
        localNonce: localNonce,
        remoteNonce: remoteNonce,
        purpose: 'sync',
        signerRole: 'responder',
        initiatorDeviceId: peer.deviceId,
        responderDeviceId: identity.deviceId,
        initiatorPublicKey: peer.publicKey,
        responderPublicKey: identity.publicKey,
      )).toJson(),
    });
    final response = await transport
        .receive(expectedTypes: const {'sync-proof'})
        .timeout(_authDeadline);
    final proof = LanPeerProof.fromJson(
      Map<String, dynamic>.from(response.body['proof'] as Map),
    );
    if (!await proofService.verify(
      proof,
      expectedSessionId: hello.sessionId,
      expectedLocalNonce: remoteNonce,
      expectedRemoteNonce: localNonce,
      expectedPurpose: 'sync',
      expectedSignerRole: 'initiator',
      initiatorDeviceId: peer.deviceId,
      initiatorPublicKey: peer.publicKey,
      responderDeviceId: identity.deviceId,
      responderPublicKey: identity.publicKey,
      expectedDeviceId: peer.deviceId,
      expectedPublicKey: peer.publicKey,
    )) {
      throw StateError('trusted peer proof failed');
    }
    transport.markAuthenticated();
    await transport.send('sync-ready', const {});
    await _serializeSync(
      () => _exchange(
        transport,
        peer.deviceId,
        initiator: false,
      ).timeout(_sessionDeadline),
    );
  }

  Future<void> _secretAsClient(
    LanSecureTransport transport,
    LanPeer peer,
    String transferId,
    String direction,
  ) async {
    if (!const {'send', 'receive'}.contains(direction)) {
      throw const FormatException('invalid secret-transfer direction');
    }
    final sessionId = _sessionId();
    transport.bindSession(
      sessionId: sessionId,
      purpose: 'secret-transfer',
      localRole: 'initiator',
      remoteRole: 'responder',
    );
    final identity = await identityService.initialize();
    final localNonce = proofService.randomNonce();
    await transport.send('secret-hello', {
      'deviceId': identity.deviceId,
      'nonce': localNonce,
      'transferId': transferId,
      'direction': direction,
    });
    final challenge = await transport
        .receive(expectedTypes: const {'secret-challenge'})
        .timeout(_authDeadline);
    _requireExactKeys(challenge.body, const {'nonce', 'proof'});
    final remoteNonce = challenge.body['nonce'] as String;
    final remoteProof = LanPeerProof.fromJson(
      Map<String, dynamic>.from(challenge.body['proof'] as Map),
    );
    if (!await proofService.verify(
      remoteProof,
      expectedSessionId: sessionId,
      expectedLocalNonce: remoteNonce,
      expectedRemoteNonce: localNonce,
      expectedPurpose: 'secret-transfer:$transferId:$direction',
      expectedSignerRole: 'responder',
      initiatorDeviceId: identity.deviceId,
      initiatorPublicKey: identity.publicKey,
      responderDeviceId: peer.deviceId,
      responderPublicKey: peer.publicKey,
      expectedDeviceId: peer.deviceId,
      expectedPublicKey: peer.publicKey,
    )) {
      throw StateError('trusted peer secret-transfer proof failed');
    }
    await transport.send('secret-proof', {
      'proof': (await proofService.create(
        sessionId: sessionId,
        localNonce: localNonce,
        remoteNonce: remoteNonce,
        purpose: 'secret-transfer:$transferId:$direction',
        signerRole: 'initiator',
        initiatorDeviceId: identity.deviceId,
        responderDeviceId: peer.deviceId,
        initiatorPublicKey: identity.publicKey,
        responderPublicKey: peer.publicKey,
      )).toJson(),
    });
    final status = await transport.receive(
      expectedTypes: const {'secret-pending', 'secret-ready'},
    );
    if (status.type == 'secret-pending') {
      return;
    }
    transport.markAuthenticated();
    if (!secretTransferService.consumeAuthorization(
      peerDeviceId: peer.deviceId,
      transferId: transferId,
      direction: direction,
    )) {
      throw StateError('local secret-transfer authorization missing');
    }
    if (direction == 'send') {
      await transport.send(
        'secret-payload',
        await secretTransferService.exportPayload(readModels()),
      );
      await transport.receive(expectedTypes: const {'secret-ok'});
    } else {
      final payload = await transport.receive(
        expectedTypes: const {'secret-payload'},
      );
      await secretTransferService.importPayload(payload.body);
      await transport.send('secret-ok', const {});
    }
  }

  Future<void> _secretAsHost(
    LanSecureTransport transport,
    LanFrame hello,
  ) async {
    _requireExactKeys(hello.body, const {
      'deviceId',
      'nonce',
      'transferId',
      'direction',
    });
    final deviceId = hello.body['deviceId'] as String;
    final transferId = hello.body['transferId'] as String;
    final initiatorDirection = hello.body['direction'] as String;
    if (!const {'send', 'receive'}.contains(initiatorDirection)) {
      throw const FormatException('invalid secret-transfer direction');
    }
    final localDirection = initiatorDirection == 'send' ? 'receive' : 'send';
    final peer = await peerRepository.peer(deviceId);
    if (peer == null || peer.revoked) {
      throw StateError('unknown or revoked peer');
    }
    final remoteNonce = hello.body['nonce'] as String;
    final localNonce = proofService.randomNonce();
    final identity = await identityService.initialize();
    final purpose = 'secret-transfer:$transferId:$initiatorDirection';
    await transport.send('secret-challenge', {
      'nonce': localNonce,
      'proof': (await proofService.create(
        sessionId: hello.sessionId,
        localNonce: localNonce,
        remoteNonce: remoteNonce,
        purpose: purpose,
        signerRole: 'responder',
        initiatorDeviceId: peer.deviceId,
        responderDeviceId: identity.deviceId,
        initiatorPublicKey: peer.publicKey,
        responderPublicKey: identity.publicKey,
      )).toJson(),
    });
    final response = await transport
        .receive(expectedTypes: const {'secret-proof'})
        .timeout(_authDeadline);
    final proof = LanPeerProof.fromJson(
      Map<String, dynamic>.from(response.body['proof'] as Map),
    );
    if (!await proofService.verify(
      proof,
      expectedSessionId: hello.sessionId,
      expectedLocalNonce: remoteNonce,
      expectedRemoteNonce: localNonce,
      expectedPurpose: purpose,
      expectedSignerRole: 'initiator',
      initiatorDeviceId: peer.deviceId,
      initiatorPublicKey: peer.publicKey,
      responderDeviceId: identity.deviceId,
      responderPublicKey: identity.publicKey,
      expectedDeviceId: peer.deviceId,
      expectedPublicKey: peer.publicKey,
    )) {
      throw StateError('trusted peer secret-transfer proof failed');
    }
    if (!secretTransferService.hasAuthorization(
      peerDeviceId: peer.deviceId,
      transferId: transferId,
      direction: localDirection,
    )) {
      secretTransferService.addRequest(
        peerDeviceId: peer.deviceId,
        transferId: transferId,
        direction: localDirection,
      );
      await transport.send('secret-pending', const {});
      return;
    }
    if (!secretTransferService.consumeAuthorization(
      peerDeviceId: peer.deviceId,
      transferId: transferId,
      direction: localDirection,
    )) {
      throw StateError('remote secret-transfer authorization expired');
    }
    transport.markAuthenticated();
    await transport.send('secret-ready', const {});
    if (localDirection == 'receive') {
      final payload = await transport.receive(
        expectedTypes: const {'secret-payload'},
      );
      await secretTransferService.importPayload(payload.body);
      await transport.send('secret-ok', const {});
    } else {
      await transport.send(
        'secret-payload',
        await secretTransferService.exportPayload(readModels()),
      );
      await transport.receive(expectedTypes: const {'secret-ok'});
    }
  }

  Future<void> _exchange(
    LanSecureTransport transport,
    String peerDeviceId, {
    required bool initiator,
  }) async {
    if (initiator) {
      await _sendChanges(transport, peerDeviceId);
      await _receiveChanges(transport, peerDeviceId);
    } else {
      await _receiveChanges(transport, peerDeviceId);
      await _sendChanges(transport, peerDeviceId);
    }
  }

  Future<void> _sendChanges(
    LanSecureTransport transport,
    String peerDeviceId,
  ) async {
    final acknowledged = await peerRepository.acknowledgedChangeIds(
      peerDeviceId,
    );
    final entries = await syncStorage.changesForPeer(acknowledged);
    final blobs = await syncStorage.blobsForChanges(entries);
    if (entries.length > _maxChanges || blobs.length > _maxBlobDescriptors) {
      throw StateError('LAN transfer exceeds descriptor limits');
    }
    final totalBytes = blobs.values.fold<int>(
      0,
      (total, blob) => total + blob.bytes.length,
    );
    if (totalBytes > _maxSessionBytes) {
      throw StateError('LAN transfer exceeds byte limit');
    }
    await transport.send('manifest', {
      'changes': entries.map(_entryJson).toList(),
      'blobs': [
        for (final entry in blobs.entries)
          {
            'sha256': entry.key,
            'size': entry.value.bytes.length,
            'kind': entry.value.kind,
          },
      ],
    });
    final request = await transport.receive(
      expectedTypes: const {'blob-request'},
    );
    final requested = (request.body['hashes'] as List? ?? const [])
        .cast<String>();
    if (requested.length > _maxBlobDescriptors ||
        requested.toSet().length != requested.length) {
      throw StateError('invalid LAN blob request');
    }
    for (final hash in requested) {
      final blob = blobs[hash];
      if (blob == null) throw StateError('LAN requested undeclared blob');
      await transport.send('blob-start', {
        'sha256': hash,
        'size': blob.bytes.length,
        'kind': blob.kind,
      });
      var index = 0;
      for (final range in LanSecureTransport.blobChunkRanges(
        blob.bytes.length,
      )) {
        await transport.send('blob-chunk', {
          'sha256': hash,
          'index': index++,
          'bytes': base64Encode(blob.bytes.sublist(range.$1, range.$2)),
        });
      }
      await transport.send('blob-end', {'sha256': hash, 'chunks': index});
    }
    await transport.send('changes-end', const {});
    final ack = await transport.receive(expectedTypes: const {'ack'});
    await peerRepository.acknowledgeChanges(
      peerDeviceId,
      (ack.body['changeIds'] as List? ?? const []).cast<String>(),
    );
  }

  Future<void> _receiveChanges(
    LanSecureTransport transport,
    String peerDeviceId,
  ) async {
    final manifest = await transport.receive(expectedTypes: const {'manifest'});
    _requireExactKeys(manifest.body, const {'changes', 'blobs'});
    final rawChanges = manifest.body['changes'];
    final rawBlobs = manifest.body['blobs'];
    if (rawChanges is! List ||
        rawBlobs is! List ||
        rawChanges.length > _maxChanges ||
        rawBlobs.length > _maxBlobDescriptors) {
      throw StateError('LAN manifest exceeds limits');
    }
    final changes = rawChanges
        .whereType<Map>()
        .map((item) => _changeFromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    if (changes.length != rawChanges.length) {
      throw StateError('invalid LAN change manifest');
    }
    _validateChanges(changes);
    final pluginBlobSizes = <String, int>{};
    for (final change in changes) {
      if (change.op != 'upsert' ||
          !LanSyncStorage.pluginLanTables.contains(change.table)) {
        continue;
      }
      final hash = change.data?['sha256'] as String?;
      final size = change.data?['size'] as int?;
      if (hash != null && size != null) pluginBlobSizes[hash] = size;
    }
    final requested = <String>[];
    final kinds = <String, String>{};
    final sizes = <String, int>{};
    var declaredBytes = 0;
    for (final blob in rawBlobs.whereType<Map>()) {
      _requireExactKeys(Map<String, dynamic>.from(blob), const {
        'sha256',
        'size',
        'kind',
      });
      final hash = blob['sha256'] as String;
      final kind = blob['kind'] as String? ?? 'resource';
      final size = (blob['size'] as num).toInt();
      if (!_validHash(hash) ||
          !const {'note', 'resource', 'plugin'}.contains(kind) ||
          size < 0 ||
          size > 64 * 1024 * 1024 ||
          sizes.containsKey(hash) ||
          (pluginBlobSizes.containsKey(hash) &&
              (kind != 'plugin' || pluginBlobSizes[hash] != size))) {
        throw StateError('invalid LAN blob descriptor');
      }
      declaredBytes += size;
      if (declaredBytes > _maxSessionBytes) {
        throw StateError('LAN session byte limit exceeded');
      }
      kinds[hash] = kind;
      sizes[hash] = size;
      if (!await syncStorage.hasBlob(hash, kind)) requested.add(hash);
    }
    if (!sizes.keys.toSet().containsAll(pluginBlobSizes.keys)) {
      throw StateError('LAN plugin metadata references an undeclared blob');
    }
    await transport.send('blob-request', {'hashes': requested});
    final staged = <String, List<int>>{};
    String? activeHash;
    int? activeSize;
    var activeChunk = 0;
    BytesBuilder? activeBytes;
    while (true) {
      final frame = await transport.receive(
        expectedTypes: const {
          'blob-start',
          'blob-chunk',
          'blob-end',
          'changes-end',
        },
      );
      if (frame.type == 'changes-end') {
        if (activeHash != null) throw StateError('incomplete LAN blob');
        break;
      }
      if (frame.type == 'blob-start') {
        _requireExactKeys(frame.body, const {'sha256', 'size', 'kind'});
        final hash = frame.body['sha256'] as String;
        if (activeHash != null ||
            !requested.contains(hash) ||
            staged.containsKey(hash) ||
            frame.body['kind'] != kinds[hash] ||
            frame.body['size'] != sizes[hash]) {
          throw StateError('unsolicited or duplicate LAN blob');
        }
        activeHash = hash;
        activeSize = frame.body['size'] as int;
        activeChunk = 0;
        activeBytes = BytesBuilder(copy: false);
        continue;
      }
      if (frame.type == 'blob-chunk') {
        _requireExactKeys(frame.body, const {'sha256', 'index', 'bytes'});
        if (frame.body['sha256'] != activeHash ||
            frame.body['index'] != activeChunk) {
          throw StateError('invalid LAN blob chunk sequence');
        }
        final chunk = base64Decode(frame.body['bytes'] as String);
        if (chunk.length > LanSecureTransport.blobChunkBytes ||
            activeBytes!.length + chunk.length > activeSize!) {
          throw StateError('LAN blob chunk exceeds declared size');
        }
        activeBytes.add(chunk);
        activeChunk++;
        continue;
      }
      _requireExactKeys(frame.body, const {'sha256', 'chunks'});
      if (frame.body['sha256'] != activeHash ||
          frame.body['chunks'] != activeChunk) {
        throw StateError('invalid LAN blob terminator');
      }
      final bytes = activeBytes!.takeBytes();
      if (bytes.length != activeSize ||
          sha256.convert(bytes).toString() != activeHash) {
        throw StateError('LAN blob SHA-256 mismatch');
      }
      staged[activeHash!] = bytes;
      activeHash = null;
      activeSize = null;
      activeBytes = null;
    }
    if (staged.length != requested.length) {
      throw StateError('LAN transfer ended before all requested blobs arrived');
    }
    if (changes.isNotEmpty) {
      await beforeRemoteApply?.call();
      for (final entry in staged.entries) {
        await syncStorage.installBlob(
          entry.key,
          kinds[entry.key]!,
          entry.value,
        );
      }
      await syncStorage.apply(changes);
      await onRemoteApplied?.call();
    }
    await transport.send('ack', {
      'changeIds': changes.map((change) => change.changeId).toList(),
    });
  }

  Map<String, dynamic> _entryJson(dynamic entry) => {
    'changeId': entry.changeId,
    'deviceId': entry.deviceId,
    'clientCreatedAt': entry.clientCreatedAt.toUtc().toIso8601String(),
    'table': entry.table,
    'op': entry.op,
    'recordId': entry.recordId,
    if (entry.data != null) 'data': entry.data,
  };

  SyncChange _changeFromJson(Map<String, dynamic> json) => SyncChange(
    seq: _syntheticSequence(json['changeId'] as String),
    changeId: json['changeId'] as String,
    deviceId: json['deviceId'] as String,
    clientCreatedAt: DateTime.parse(json['clientCreatedAt'] as String),
    table: json['table'] as String,
    op: json['op'] as String,
    recordId: json['recordId'] as String,
    data: json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : null,
  );

  int _syntheticSequence(String changeId) {
    final bytes = sha256.convert(utf8.encode(changeId)).bytes;
    var value = 0;
    for (var index = 0; index < 7; index++) {
      value = (value << 8) | bytes[index];
    }
    return value;
  }

  Future<void> _rememberCurrentCertificate(
    String deviceId,
    SecureSocket socket,
  ) async {
    final certificate = socket.peerCertificate;
    if (certificate == null) return;
    await peerRepository.updateCertificateExpiry(
      deviceId,
      certificateService.certificateExpiresAt(certificate.der),
    );
  }

  Future<List<String>> _localAddresses() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    return {
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (LanPairingPayloadCodec.isAllowedLanAddress(address.address))
            address.address,
    }.take(8).toList(growable: false);
  }

  String _sessionId() {
    final random = Random.secure();
    return base64UrlEncode(
      List<int>.generate(18, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
  }

  Future<T> _serializeSync<T>(Future<T> Function() action) {
    late T value;
    final result = _syncQueue.then((_) async => value = await action());
    _syncQueue = result.then<void>((_) {}).catchError((_) {});
    return result.then((_) => value);
  }

  void _validateChanges(List<SyncChange> changes) {
    final ids = <String>{};
    for (final change in changes) {
      if (!ids.add(change.changeId) ||
          change.changeId.length > 128 ||
          change.recordId.isEmpty ||
          change.recordId.length > 512 ||
          !const {'upsert', 'delete'}.contains(change.op) ||
          !LanSyncStorage.ordinaryLanTables.contains(change.table)) {
        throw StateError('invalid LAN change manifest');
      }
      validatePluginSyncChange(change);
    }
  }

  void _requireExactKeys(Map<String, dynamic> value, Set<String> keys) {
    if (value.length != keys.length || !value.keys.toSet().containsAll(keys)) {
      throw StateError('unexpected LAN payload fields');
    }
  }

  bool _validHash(String value) => RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

  Future<void> stopHost() async {
    try {
      await _hostStart;
    } catch (_) {}
    await mdnsService.stopAdvertising();
    await _serverSubscription?.cancel();
    _serverSubscription = null;
    await _server?.close();
    _server = null;
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    await stopHost();
    await secretTransferService.close();
  }
}
