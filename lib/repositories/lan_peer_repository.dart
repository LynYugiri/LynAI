import 'dart:async';
import 'dart:convert';

import '../models/lan_peer.dart';
import '../services/secret_store.dart';

class LanPeerRepository {
  LanPeerRepository({required SecretStore secretStore})
    : _secretStore = secretStore;

  static const _peersKey = 'lan.peers.v1';
  static const _sessionsKey = 'lan.pairing_sessions.v1';
  static const _appliedChangesKey = 'lan.applied_changes.v1';
  static const _peerAcksKey = 'lan.peer_acks.v1';

  final SecretStore _secretStore;
  Future<void> _queue = Future.value();

  Future<List<LanPeer>> loadPeers() async {
    final values = await _readList(_peersKey);
    return values
        .whereType<Map>()
        .map((item) => LanPeer.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> trustPeer(LanPeer peer) => _mutate(() async {
    final peers = await loadPeers();
    final index = peers.indexWhere((item) => item.deviceId == peer.deviceId);
    if (index < 0) {
      peers.add(peer);
    } else {
      peers[index] = peer;
    }
    await _writeList(_peersKey, peers.map((item) => item.toJson()).toList());
  });

  Future<void> revokePeer(String deviceId, {DateTime? now}) => _mutate(
    () async {
      final peers = await loadPeers();
      final index = peers.indexWhere((item) => item.deviceId == deviceId);
      if (index < 0) return;
      peers[index] = peers[index].copyWith(
        revokedAt: (now ?? DateTime.now()).toUtc(),
      );
      await _writeList(_peersKey, peers.map((item) => item.toJson()).toList());
    },
  );

  Future<LanPeer?> peer(String deviceId) async {
    for (final peer in await loadPeers()) {
      if (peer.deviceId == deviceId) return peer;
    }
    return null;
  }

  Future<void> updateCertificateExpiry(
    String deviceId,
    DateTime certificateExpiresAt,
  ) => _mutate(() async {
    final peers = await loadPeers();
    final index = peers.indexWhere((item) => item.deviceId == deviceId);
    if (index < 0) return;
    peers[index] = peers[index].copyWith(
      certificateExpiresAt: certificateExpiresAt.toUtc(),
      lastSeenAt: DateTime.now().toUtc(),
    );
    await _writeList(_peersKey, peers.map((item) => item.toJson()).toList());
  });

  Future<void> savePairingSession(LanPairingSession session) =>
      _mutate(() async {
        final sessions = await _sessions();
        sessions[session.nonce] = session;
        await _saveSessions(sessions);
      });

  Future<bool> consumePairingNonce(
    String nonce,
    String deviceId, {
    DateTime? now,
  }) => _mutateResult(() async {
    final clock = (now ?? DateTime.now()).toUtc();
    final sessions = await _sessions();
    final session = sessions[nonce];
    if (session == null ||
        session.consumed ||
        !session.expiresAt.isAfter(clock)) {
      return false;
    }
    sessions[nonce] = LanPairingSession(
      nonce: session.nonce,
      createdAt: session.createdAt,
      expiresAt: session.expiresAt,
      consumedAt: clock,
      consumedByDeviceId: deviceId,
    );
    await _saveSessions(sessions);
    return true;
  });

  Future<bool> markChangeApplied(String changeId) => _mutateResult(() async {
    final values = (await _readList(_appliedChangesKey)).cast<String>().toSet();
    if (!values.add(changeId)) return false;
    final bounded = values.length <= 10000
        ? values.toList()
        : values.skip(values.length - 10000).toList();
    await _writeList(_appliedChangesKey, bounded);
    return true;
  });

  Future<bool> hasAppliedChange(String changeId) async =>
      (await _readList(_appliedChangesKey)).cast<String>().contains(changeId);

  Future<Set<String>> acknowledgedChangeIds(String peerDeviceId) async {
    final raw = await _readMap(_peerAcksKey);
    return (raw[peerDeviceId] as List? ?? const []).cast<String>().toSet();
  }

  Future<void> acknowledgeChanges(String peerDeviceId, Iterable<String> ids) =>
      _mutate(() async {
        final raw = await _readMap(_peerAcksKey);
        final values =
            (raw[peerDeviceId] as List? ?? const []).cast<String>().toSet()
              ..addAll(ids);
        raw[peerDeviceId] = values.length <= 10000
            ? values.toList()
            : values.skip(values.length - 10000).toList();
        await _secretStore.write(_peerAcksKey, jsonEncode(raw));
      });

  Future<Map<String, LanPairingSession>> _sessions() async => {
    for (final item in await _readList(_sessionsKey))
      if (item is Map)
        LanPairingSession.fromJson(Map<String, dynamic>.from(item)).nonce:
            LanPairingSession.fromJson(Map<String, dynamic>.from(item)),
  };

  Future<void> _saveSessions(Map<String, LanPairingSession> sessions) =>
      _writeList(
        _sessionsKey,
        sessions.values.map((item) => item.toJson()).toList(),
      );

  Future<List<dynamic>> _readList(String key) async {
    final value = await _secretStore.read(key);
    if (value == null || value.isEmpty) return [];
    final decoded = jsonDecode(value);
    if (decoded is! List) throw StateError('corrupt LAN repository value');
    return decoded;
  }

  Future<Map<String, dynamic>> _readMap(String key) async {
    final value = await _secretStore.read(key);
    if (value == null || value.isEmpty) return {};
    final decoded = jsonDecode(value);
    if (decoded is! Map) throw StateError('corrupt LAN repository value');
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> _writeList(String key, List<dynamic> value) =>
      _secretStore.write(key, jsonEncode(value));

  Future<void> _mutate(Future<void> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.catchError((_) {});
    return result;
  }

  Future<T> _mutateResult<T>(Future<T> Function() action) {
    late T value;
    final result = _queue.then((_) async => value = await action());
    _queue = result.then<void>((_) {}).catchError((_) {});
    return result.then((_) => value);
  }
}
