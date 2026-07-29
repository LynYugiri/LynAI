import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models/lan_pairing_payload.dart';
import '../models/lan_peer.dart';
import '../models/model_config.dart';
import '../models/sync_change.dart';
import '../models/sync_data_selection.dart';
import '../repositories/lan_peer_repository.dart';
import 'device_identity_service.dart';
import 'lan_mdns_service.dart';
import 'lan_pairing_payload_codec.dart';
import 'lan_peer_proof_service.dart';
import 'plugin_sync_validation.dart';
import 'lan_secure_transport.dart';
import 'lan_secret_transfer_service.dart';
import 'lan_sync_storage.dart';
import 'remote_apply_coordinator.dart';
import 'lan_tls_certificate_service.dart';
import 'storage_v2_database.dart';

typedef LanPairingConfirmation =
    Future<LanPairingDecision> Function(LanPairingConfirmationRequest request);
typedef LanPolicyConfirmation =
    Future<SyncDataSelection?> Function(
      String displayName,
      SyncDataSelection proposedSelection,
      SyncDataSelection currentSelection,
    );
typedef LanModelReader = List<ModelConfig> Function();

class LanPairingConfirmationRequest {
  const LanPairingConfirmationRequest({
    required this.displayName,
    required this.fingerprint,
    required this.proposedSelection,
    required this.responding,
  });

  final String displayName;
  final String fingerprint;
  final SyncDataSelection proposedSelection;
  final bool responding;
}

class LanPairingDecision {
  const LanPairingDecision({required this.approved, required this.selection});

  const LanPairingDecision.rejected()
    : approved = false,
      selection = SyncDataSelection.defaults;

  final bool approved;
  final SyncDataSelection selection;
}

class LanPairingResult {
  const LanPairingResult({required this.peer, required this.discoveredPeer});

  final LanPeer peer;
  final LanDiscoveredPeer discoveredPeer;
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
    required this.confirmPolicyProposal,
    required this.readModels,
    this.beforeLocalSnapshot,
    this.beforeRemoteApply,
    this.onRemoteApplied,
    RemoteApplyCoordinator? remoteApplyCoordinator,
    LanPairingPayloadCodec? payloadCodec,
  }) : remoteApplyCoordinator =
           remoteApplyCoordinator ?? RemoteApplyCoordinator(),
       payloadCodec = payloadCodec ?? LanPairingPayloadCodec(),
       proofService = LanPeerProofService(identityService);

  final DeviceIdentityService identityService;
  final LanPeerRepository peerRepository;
  final LanTlsCertificateService certificateService;
  final LanMdnsService mdnsService;
  final LanSyncStorage syncStorage;
  // The coordinator owns this per-instance transfer service and closes it.
  final LanSecretTransferService secretTransferService;
  LanPairingConfirmation confirmPairing;
  LanPolicyConfirmation confirmPolicyProposal;
  final LanModelReader readModels;
  final Future<void> Function()? beforeLocalSnapshot;
  final Future<void> Function()? beforeRemoteApply;
  final Future<void> Function()? onRemoteApplied;
  final RemoteApplyCoordinator remoteApplyCoordinator;
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
    await peerRepository.migrateLegacyTransportState();
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
        (socket) => unawaited(_accept(socket).catchError((_) {})),
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

  Future<LanPairingResult> pair(
    String encodedPayload, {
    SyncDataSelection proposedSelection = SyncDataSelection.defaults,
  }) async {
    final payload = await payloadCodec.decodeAndVerify(encodedPayload);
    final identity = await identityService.initialize();
    await syncStorage.activate(identity.deviceId);
    await peerRepository.migrateLegacyTransportState();
    await runOutboundAttempts(
      payload.addresses,
      connect: (address) async => LanSecureTransport(
        await _connectPinned(address, payload.port, payload),
      ),
      run: (transport) => _pairAsClient(transport, payload, proposedSelection),
      close: (transport) => transport.close(),
      failureMessage: 'unable to connect to pairing host',
    );
    final peer = await peerRepository.peer(payload.deviceId);
    if (peer == null || peer.revoked) {
      throw StateError('paired peer was not persisted');
    }
    return LanPairingResult(
      peer: peer,
      discoveredPeer: LanDiscoveredPeer(
        deviceId: payload.deviceId,
        displayName: peer.displayName,
        addresses: payload.addresses,
        port: payload.port,
        protocolVersion: payload.version,
      ),
    );
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

  Future<List<SyncConflictEntry>> loadConflicts() =>
      syncStorage.loadConflicts();

  Future<void> resolveConflict(int seq, SyncConflictResolution resolution) =>
      remoteApplyCoordinator.run(() async {
        await syncStorage.resolveConflict(seq, resolution);
        await onRemoteApplied?.call();
      });

  Future<SyncDataSelection> proposeSyncSelection(
    LanDiscoveredPeer discovered,
    SyncDataSelection proposedSelection,
  ) async {
    final peer = await _trustedDiscoveredPeer(discovered);
    if (!peer.syncSelection.isSubsetOf(proposedSelection)) {
      throw StateError('policy proposal cannot restore locally disabled data');
    }
    late SyncDataSelection accepted;
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
        accepted = await _policyAsClient(transport, peer, proposedSelection);
      },
      close: (transport) => transport.close(),
      failureMessage: 'unable to update LAN sync policy',
    );
    return accepted;
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
    SyncDataSelection proposedSelection,
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
      'displayName': _displayName,
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
    final decision = await confirmPairing(
      LanPairingConfirmationRequest(
        displayName: challenge.body['displayName'] as String? ?? 'LynAI device',
        fingerprint: proofService.sas(
          sessionId: sessionId,
          purpose: 'pairing',
          initiatorDeviceId: identity.deviceId,
          initiatorPublicKey: identity.publicKey,
          initiatorNonce: localNonce,
          responderDeviceId: payload.deviceId,
          responderPublicKey: payload.publicKey,
          responderNonce: remoteNonce,
        ),
        proposedSelection: proposedSelection,
        responding: false,
      ),
    );
    if (!decision.approved ||
        !decision.selection.isSubsetOf(proposedSelection)) {
      throw StateError('pairing was not confirmed');
    }
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
      'selection': decision.selection.toJson(),
    });
    final result = await transport
        .receive(expectedTypes: const {'pair-ok'})
        .timeout(_authDeadline);
    _requireExactKeys(result.body, const {'displayName', 'selection'});
    transport.markAuthenticated();
    final selection = _selectionFromWire(result.body['selection']);
    if (!selection.isSubsetOf(decision.selection)) {
      throw StateError('pairing host returned an invalid sync selection');
    }
    await peerRepository.trustPeer(
      LanPeer(
        deviceId: payload.deviceId,
        publicKey: payload.publicKey,
        spkiSha256: payload.spkiSha256,
        displayName: result.body['displayName'] as String? ?? 'LynAI device',
        trustedAt: DateTime.now().toUtc(),
        certificateExpiresAt: payload.certificateExpiresAt,
        syncSelection: selection,
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
            expectedTypes: const {
              'pair-hello',
              'sync-hello',
              'policy-hello',
              'secret-hello',
            },
            expectedPurposes: const {
              'pairing',
              'sync',
              'policy',
              'secret-transfer',
            },
          )
          .timeout(_authDeadline);
      if (first.type == 'pair-hello') {
        await _pairAsHost(transport, first);
      } else if (first.type == 'sync-hello') {
        await _syncAsHost(transport, first);
      } else if (first.type == 'policy-hello') {
        await _policyAsHost(transport, first);
      } else if (first.type == 'secret-hello') {
        await _secretAsHost(transport, first);
      } else {
        throw StateError('unsupported LAN session');
      }
    } catch (_) {
      // A malformed or interrupted incoming session is isolated to its socket.
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
    final remoteDisplayName =
        (hello.body['displayName'] as String? ?? 'LynAI device').trim();
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
    _requireExactKeys(response.body, const {'proof', 'binding', 'selection'});
    final remoteProof = LanPeerProof.fromJson(
      Map<String, dynamic>.from(response.body['proof'] as Map),
    );
    final binding = LanTlsBinding.fromJson(
      Map<String, dynamic>.from(response.body['binding'] as Map),
    );
    final proposedSelection = _selectionFromWire(response.body['selection']);
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
    final decision = await confirmPairing(
      LanPairingConfirmationRequest(
        displayName: remoteDisplayName.isEmpty
            ? 'LynAI device'
            : remoteDisplayName,
        fingerprint: proofService.sas(
          sessionId: hello.sessionId,
          purpose: 'pairing',
          initiatorDeviceId: remoteDeviceId,
          initiatorPublicKey: remotePublicKey,
          initiatorNonce: remoteNonce,
          responderDeviceId: identity.deviceId,
          responderPublicKey: identity.publicKey,
          responderNonce: localNonce,
        ),
        proposedSelection: proposedSelection,
        responding: true,
      ),
    );
    if (!decision.approved ||
        !decision.selection.isSubsetOf(proposedSelection) ||
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
        displayName: remoteDisplayName.isEmpty
            ? 'LynAI device'
            : remoteDisplayName,
        trustedAt: DateTime.now().toUtc(),
        certificateExpiresAt: binding.certificateExpiresAt,
        syncSelection: decision.selection,
      ),
    );
    transport.markAuthenticated();
    await transport.send('pair-ok', {
      'displayName': _displayName,
      'selection': decision.selection.toJson(),
    });
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
      'selection': peer.syncSelection.toJson(),
    });
    final challenge = await transport
        .receive(expectedTypes: const {'sync-challenge'})
        .timeout(_authDeadline);
    _requireExactKeys(challenge.body, const {'nonce', 'proof', 'selection'});
    final remoteNonce = challenge.body['nonce'] as String;
    final remoteProof = LanPeerProof.fromJson(
      Map<String, dynamic>.from(challenge.body['proof'] as Map),
    );
    final remoteSelection = _selectionFromWire(challenge.body['selection']);
    final effectiveSelection = peer.syncSelection.intersect(remoteSelection);
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
    _requireExactKeys(ready.body, const {'selection'});
    if (!_selectionFromWire(
      ready.body['selection'],
    ).hasSameCategories(effectiveSelection)) {
      throw StateError('LAN sync selection changed during authentication');
    }
    transport.markAuthenticated();
    if (!effectiveSelection.hasSameCategories(peer.syncSelection)) {
      await peerRepository.updateSyncSelection(
        peer.deviceId,
        effectiveSelection,
      );
    }
    await _exchange(
      transport,
      peer.deviceId,
      effectiveSelection,
      initiator: true,
    ).timeout(_sessionDeadline);
  }

  Future<void> _syncAsHost(LanSecureTransport transport, LanFrame hello) async {
    _requireExactKeys(hello.body, const {'deviceId', 'nonce', 'selection'});
    final deviceId = hello.body['deviceId'] as String;
    var peer = await peerRepository.peer(deviceId);
    if (peer == null || peer.revoked) {
      throw StateError('unknown or revoked peer');
    }
    var trustedPeer = peer;
    final remoteSelection = _selectionFromWire(hello.body['selection']);
    final effectiveSelection = trustedPeer.syncSelection.intersect(
      remoteSelection,
    );
    if (!effectiveSelection.hasSameCategories(trustedPeer.syncSelection)) {
      trustedPeer = trustedPeer.copyWith(syncSelection: effectiveSelection);
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
        initiatorDeviceId: trustedPeer.deviceId,
        responderDeviceId: identity.deviceId,
        initiatorPublicKey: trustedPeer.publicKey,
        responderPublicKey: identity.publicKey,
      )).toJson(),
      'selection': trustedPeer.syncSelection.toJson(),
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
      initiatorDeviceId: trustedPeer.deviceId,
      initiatorPublicKey: trustedPeer.publicKey,
      responderDeviceId: identity.deviceId,
      responderPublicKey: identity.publicKey,
      expectedDeviceId: trustedPeer.deviceId,
      expectedPublicKey: trustedPeer.publicKey,
    )) {
      throw StateError('trusted peer proof failed');
    }
    if (!effectiveSelection.hasSameCategories(peer.syncSelection)) {
      await peerRepository.updateSyncSelection(
        trustedPeer.deviceId,
        effectiveSelection,
      );
    }
    transport.markAuthenticated();
    await transport.send('sync-ready', {
      'selection': trustedPeer.syncSelection.toJson(),
    });
    await _serializeSync(
      () => _exchange(
        transport,
        trustedPeer.deviceId,
        trustedPeer.syncSelection,
        initiator: false,
      ).timeout(_sessionDeadline),
    );
  }

  Future<SyncDataSelection> _policyAsClient(
    LanSecureTransport transport,
    LanPeer peer,
    SyncDataSelection proposedSelection,
  ) async {
    final sessionId = _sessionId();
    transport.bindSession(
      sessionId: sessionId,
      purpose: 'policy',
      localRole: 'initiator',
      remoteRole: 'responder',
    );
    final identity = await identityService.initialize();
    final localNonce = proofService.randomNonce();
    await transport.send('policy-hello', {
      'deviceId': identity.deviceId,
      'nonce': localNonce,
    });
    final challenge = await transport
        .receive(expectedTypes: const {'policy-challenge'})
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
      expectedPurpose: 'policy',
      expectedSignerRole: 'responder',
      initiatorDeviceId: identity.deviceId,
      initiatorPublicKey: identity.publicKey,
      responderDeviceId: peer.deviceId,
      responderPublicKey: peer.publicKey,
      expectedDeviceId: peer.deviceId,
      expectedPublicKey: peer.publicKey,
    )) {
      throw StateError('trusted peer policy proof failed');
    }
    await transport.send('policy-proof', {
      'proof': (await proofService.create(
        sessionId: sessionId,
        localNonce: localNonce,
        remoteNonce: remoteNonce,
        purpose: 'policy',
        signerRole: 'initiator',
        initiatorDeviceId: identity.deviceId,
        responderDeviceId: peer.deviceId,
        initiatorPublicKey: identity.publicKey,
        responderPublicKey: peer.publicKey,
      )).toJson(),
    });
    final ready = await transport
        .receive(expectedTypes: const {'policy-ready'})
        .timeout(_authDeadline);
    if (ready.body.isNotEmpty) throw StateError('invalid policy-ready frame');
    transport.markAuthenticated();
    await transport.send('policy-proposal', {
      'selection': proposedSelection.toJson(),
    });
    final result = await transport.receive(
      expectedTypes: const {'policy-result'},
    );
    _requireExactKeys(result.body, const {'selection'});
    final accepted = _selectionFromWire(result.body['selection']);
    if (!accepted.isSubsetOf(proposedSelection)) {
      throw StateError('peer accepted categories outside the proposal');
    }
    return accepted;
  }

  Future<void> _policyAsHost(
    LanSecureTransport transport,
    LanFrame hello,
  ) async {
    _requireExactKeys(hello.body, const {'deviceId', 'nonce'});
    final deviceId = hello.body['deviceId'] as String;
    final peer = await peerRepository.peer(deviceId);
    if (peer == null || peer.revoked) {
      throw StateError('unknown or revoked peer');
    }
    final remoteNonce = hello.body['nonce'] as String;
    final localNonce = proofService.randomNonce();
    final identity = await identityService.initialize();
    await transport.send('policy-challenge', {
      'nonce': localNonce,
      'proof': (await proofService.create(
        sessionId: hello.sessionId,
        localNonce: localNonce,
        remoteNonce: remoteNonce,
        purpose: 'policy',
        signerRole: 'responder',
        initiatorDeviceId: peer.deviceId,
        responderDeviceId: identity.deviceId,
        initiatorPublicKey: peer.publicKey,
        responderPublicKey: identity.publicKey,
      )).toJson(),
    });
    final response = await transport
        .receive(expectedTypes: const {'policy-proof'})
        .timeout(_authDeadline);
    final proof = LanPeerProof.fromJson(
      Map<String, dynamic>.from(response.body['proof'] as Map),
    );
    if (!await proofService.verify(
      proof,
      expectedSessionId: hello.sessionId,
      expectedLocalNonce: remoteNonce,
      expectedRemoteNonce: localNonce,
      expectedPurpose: 'policy',
      expectedSignerRole: 'initiator',
      initiatorDeviceId: peer.deviceId,
      initiatorPublicKey: peer.publicKey,
      responderDeviceId: identity.deviceId,
      responderPublicKey: identity.publicKey,
      expectedDeviceId: peer.deviceId,
      expectedPublicKey: peer.publicKey,
    )) {
      throw StateError('trusted peer policy proof failed');
    }
    transport.markAuthenticated();
    await transport.send('policy-ready', const {});
    final proposal = await transport.receive(
      expectedTypes: const {'policy-proposal'},
    );
    _requireExactKeys(proposal.body, const {'selection'});
    final proposed = _selectionFromWire(proposal.body['selection']);
    final current = peer.syncSelection;
    SyncDataSelection? accepted;
    if (proposed.isSubsetOf(current)) {
      accepted = proposed;
    } else {
      accepted = await confirmPolicyProposal(
        peer.displayName,
        proposed,
        current,
      );
    }
    if (accepted == null || !accepted.isSubsetOf(proposed)) {
      accepted = current.intersect(proposed);
    } else {
      accepted = accepted.union(current.intersect(proposed));
    }
    await peerRepository.updateSyncSelection(peer.deviceId, accepted);
    await transport.send('policy-result', {'selection': accepted.toJson()});
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
    String peerDeviceId,
    SyncDataSelection selection, {
    required bool initiator,
  }) async {
    await beforeLocalSnapshot?.call();
    if (initiator) {
      await _sendChanges(transport, peerDeviceId, selection);
      await _receiveChanges(transport, peerDeviceId, selection);
    } else {
      await _receiveChanges(transport, peerDeviceId, selection);
      await _sendChanges(transport, peerDeviceId, selection);
    }
  }

  Future<void> _sendChanges(
    LanSecureTransport transport,
    String peerDeviceId,
    SyncDataSelection selection,
  ) async {
    final entries = await syncStorage.changesForPeer(peerDeviceId, selection);
    for (final batch in lanSyncBatches(entries, _maxChanges)) {
      var offset = 0;
      while (offset < batch.length) {
        var end = batch.length;
        late List<dynamic> page;
        late Map<String, LanSyncBlob> blobs;
        while (true) {
          page = batch.sublist(offset, end);
          blobs = await syncStorage.blobsForChanges(page.cast(), selection);
          final totalBytes = blobs.values.fold<int>(
            0,
            (total, blob) => total + blob.size,
          );
          final manifestBody = _manifestBody(page, blobs, more: true);
          if (blobs.length <= _maxBlobDescriptors &&
              totalBytes <= _maxSessionBytes &&
              LanSecureTransport.bodySize(manifestBody) <=
                  LanSecureTransport.defaultMaxBodyBytes &&
              LanSecureTransport.frameSize(
                    type: 'manifest',
                    sessionId: transport.sessionId,
                    counter: transport.nextSentCounter,
                    purpose: 'sync',
                    role: transport.localRole,
                    body: manifestBody,
                  ) <=
                  LanSecureTransport.defaultMaxFrameBytes) {
            break;
          }
          if (end - offset == 1) {
            throw StateError('LAN change exceeds page limits');
          }
          end = offset + ((end - offset) ~/ 2);
        }
        await _sendChangePage(transport, peerDeviceId, page, blobs, more: true);
        offset = end;
      }
    }
    await _sendChangePage(
      transport,
      peerDeviceId,
      const [],
      const {},
      more: false,
    );
  }

  Future<void> _sendChangePage(
    LanSecureTransport transport,
    String peerDeviceId,
    List<dynamic> entries,
    Map<String, LanSyncBlob> blobs, {
    required bool more,
  }) async {
    await transport.send('manifest', _manifestBody(entries, blobs, more: more));
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
        'size': blob.size,
        'kind': blob.kind,
      });
      var index = 0;
      var sentBytes = 0;
      final digestSink = _DigestSink();
      final digestInput = sha256.startChunkedConversion(digestSink);
      await for (final chunk in syncStorage.readBlobChunks(
        hash,
        blob,
        LanSecureTransport.blobChunkBytes,
      )) {
        if (chunk.length > LanSecureTransport.blobChunkBytes ||
            sentBytes + chunk.length > blob.size) {
          throw StateError('LAN blob changed while being sent');
        }
        digestInput.add(chunk);
        sentBytes += chunk.length;
        await transport.send('blob-chunk', {
          'sha256': hash,
          'index': index++,
          'bytes': base64Encode(chunk),
        });
      }
      digestInput.close();
      if (sentBytes != blob.size || digestSink.value.toString() != hash) {
        throw StateError('LAN blob changed while being sent');
      }
      await transport.send('blob-end', {'sha256': hash, 'chunks': index});
    }
    await transport.send('changes-end', const {});
    final ack = await transport.receive(expectedTypes: const {'ack'});
    _requireExactKeys(ack.body, const {'changeIds'});
    final sentIds = entries.map((entry) => entry.changeId as String).toList();
    final acknowledgedIds = (ack.body['changeIds'] as List? ?? const [])
        .cast<String>();
    validateExactAcknowledgement(sentIds, acknowledgedIds);
    await syncStorage.acknowledgePeer(
      peerDeviceId,
      entries.cast<SyncOutboxEntry>(),
    );
  }

  Map<String, dynamic> _manifestBody(
    List<dynamic> entries,
    Map<String, LanSyncBlob> blobs, {
    required bool more,
  }) => {
    'changes': entries.map(_entryJson).toList(),
    'blobs': [
      for (final entry in blobs.entries)
        {
          'sha256': entry.key,
          'size': entry.value.size,
          'kind': entry.value.kind,
        },
    ],
    'more': more,
  };

  Future<void> _receiveChanges(
    LanSecureTransport transport,
    String peerDeviceId,
    SyncDataSelection selection,
  ) async {
    while (true) {
      final more = await _receiveChangePage(transport, peerDeviceId, selection);
      if (!more) return;
    }
  }

  Future<bool> _receiveChangePage(
    LanSecureTransport transport,
    String peerDeviceId,
    SyncDataSelection selection,
  ) async {
    final manifest = await transport.receive(expectedTypes: const {'manifest'});
    _requireExactKeys(manifest.body, const {'changes', 'blobs', 'more'});
    final rawChanges = manifest.body['changes'];
    final rawBlobs = manifest.body['blobs'];
    final more = manifest.body['more'];
    if (rawChanges is! List ||
        rawBlobs is! List ||
        more is! bool ||
        rawChanges.length > _maxChanges ||
        rawBlobs.length > _maxBlobDescriptors) {
      throw StateError('LAN manifest exceeds limits');
    }
    final changes = rawChanges
        .whereType<Map>()
        .map((item) => parseLanChange(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    if (changes.length != rawChanges.length) {
      throw StateError('invalid LAN change manifest');
    }
    _validateChanges(changes);
    for (final change in changes) {
      final selectionData = await syncStorage.selectionDataForChange(change);
      if (!SyncDataRegistry.allowsChange(
        selection,
        change.table,
        selectionData,
      )) {
        throw StateError('LAN peer sent a change outside the agreed policy');
      }
    }
    final referencedHashes = await syncStorage.expectedBlobHashes(changes);
    final pluginBlobSizes = <String, int>{};
    for (final change in changes) {
      if (change.op != 'upsert') continue;
      final hash = change.data?['sha256'] as String?;
      if (LanSyncStorage.pluginLanTables.contains(change.table)) {
        final size = change.data?['size'] as int?;
        if (hash != null && size != null) pluginBlobSizes[hash] = size;
      }
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
          !referencedHashes.contains(hash) ||
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
    final requestedSet = requested.toSet();
    final received = <String>{};
    final stagedFiles = <String, File>{};
    final temporaryDirectory = requested.isEmpty
        ? null
        : await Directory.systemTemp.createTemp('lynai_lan_blob_');
    String? activeHash;
    int? activeSize;
    var activeChunk = 0;
    var activeBytes = 0;
    RandomAccessFile? activeFile;
    File? activeTemporary;
    _DigestSink? activeDigestSink;
    ByteConversionSink? activeDigestInput;
    try {
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
              !requestedSet.contains(hash) ||
              received.contains(hash) ||
              frame.body['kind'] != kinds[hash] ||
              frame.body['size'] != sizes[hash]) {
            throw StateError('unsolicited or duplicate LAN blob');
          }
          activeHash = hash;
          activeSize = frame.body['size'] as int;
          activeChunk = 0;
          activeBytes = 0;
          activeDigestSink = _DigestSink();
          activeDigestInput = sha256.startChunkedConversion(activeDigestSink);
          activeTemporary = File('${temporaryDirectory!.path}/$hash');
          activeFile = await activeTemporary.open(mode: FileMode.write);
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
              activeBytes + chunk.length > activeSize!) {
            throw StateError('LAN blob chunk exceeds declared size');
          }
          activeDigestInput!.add(chunk);
          await activeFile!.writeFrom(chunk);
          activeBytes += chunk.length;
          activeChunk++;
          continue;
        }
        _requireExactKeys(frame.body, const {'sha256', 'chunks'});
        if (frame.body['sha256'] != activeHash ||
            frame.body['chunks'] != activeChunk) {
          throw StateError('invalid LAN blob terminator');
        }
        activeDigestInput!.close();
        activeDigestInput = null;
        await activeFile!.close();
        activeFile = null;
        if (activeBytes != activeSize ||
            activeDigestSink!.value.toString() != activeHash) {
          throw StateError('LAN blob SHA-256 mismatch');
        }
        received.add(activeHash!);
        stagedFiles[activeHash] = activeTemporary!;
        activeHash = null;
        activeSize = null;
        activeTemporary = null;
        activeDigestSink = null;
      }
      if (received.length != requested.length) {
        throw StateError(
          'LAN transfer ended before all requested blobs arrived',
        );
      }
      await remoteApplyCoordinator.run(() async {
        for (final hash in requested) {
          await syncStorage.installBlob(
            hash,
            kinds[hash]!,
            await stagedFiles[hash]!.readAsBytes(),
          );
        }
        if (changes.isNotEmpty) {
          await beforeRemoteApply?.call();
          await syncStorage.apply(peerDeviceId, changes);
          await onRemoteApplied?.call();
        }
      });
    } finally {
      activeDigestInput?.close();
      await activeFile?.close();
      if (temporaryDirectory != null && await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    }
    await transport.send('ack', {
      'changeIds': changes.map((change) => change.changeId).toList(),
    });
    return more;
  }

  Map<String, dynamic> _entryJson(dynamic entry) => {
    'changeId': entry.changeId,
    'deviceId': entry.deviceId,
    'clientCreatedAt': entry.clientCreatedAt.toUtc().toIso8601String(),
    'table': entry.table,
    'op': entry.op,
    'recordId': entry.recordId,
    if (entry.data != null) 'data': entry.data,
    if (entry.lineage != null) 'lineage': entry.lineage,
  };

  static SyncChange parseLanChange(Map<String, dynamic> json) {
    const required = {
      'changeId',
      'deviceId',
      'clientCreatedAt',
      'table',
      'op',
      'recordId',
    };
    const allowed = {...required, 'data', 'lineage'};
    if (!json.keys.toSet().containsAll(required) ||
        json.keys.any((key) => !allowed.contains(key))) {
      throw StateError('unexpected LAN change fields');
    }
    final changeId = json['changeId'];
    final deviceId = json['deviceId'];
    final createdAt = json['clientCreatedAt'];
    final table = json['table'];
    final op = json['op'];
    final recordId = json['recordId'];
    final lineage = json['lineage'];
    if (changeId is! String ||
        deviceId is! String ||
        createdAt is! String ||
        table is! String ||
        op is! String ||
        recordId is! String ||
        (lineage != null && lineage is! String)) {
      throw StateError('invalid LAN change fields');
    }
    final parsedCreatedAt = DateTime.tryParse(createdAt);
    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : null;
    if (parsedCreatedAt == null ||
        (op == 'upsert' && data?['id'] != recordId) ||
        (op == 'delete' && json.containsKey('data'))) {
      throw StateError('invalid LAN change payload');
    }
    return SyncChange(
      seq: _syntheticSequence(changeId),
      changeId: changeId,
      deviceId: deviceId,
      clientCreatedAt: parsedCreatedAt,
      table: table,
      op: op,
      recordId: recordId,
      data: data,
      lineage: lineage as String?,
    );
  }

  static int _syntheticSequence(String changeId) {
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
      if (change.op == 'upsert' && change.data?['id'] != change.recordId) {
        throw StateError('LAN change data.id does not match recordId');
      }
      if (change.op == 'delete' && change.data != null) {
        throw StateError('LAN delete must not contain data');
      }
      validatePluginSyncChange(change);
    }
  }

  void _requireExactKeys(Map<String, dynamic> value, Set<String> keys) {
    if (value.length != keys.length || !value.keys.toSet().containsAll(keys)) {
      throw StateError('unexpected LAN payload fields');
    }
  }

  static void validateExactAcknowledgement(
    List<String> sentIds,
    List<String> acknowledgedIds,
  ) {
    if (acknowledgedIds.toSet().length != acknowledgedIds.length ||
        sentIds.length != acknowledgedIds.length ||
        !sentIds.toSet().containsAll(acknowledgedIds)) {
      throw StateError('LAN acknowledgement does not match the sent page');
    }
  }

  SyncDataSelection _selectionFromWire(Object? value) {
    if (value is! List ||
        value.any((item) => item is! String) ||
        value.toSet().length != value.length) {
      throw StateError('invalid LAN sync selection');
    }
    final names = SyncDataCategory.values.map((item) => item.name).toSet();
    if (!value.cast<String>().every(names.contains)) {
      throw StateError('invalid LAN sync selection');
    }
    return SyncDataSelection.fromJson(value);
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

class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value => _value ?? (throw StateError('digest is not complete'));

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}
