import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/lan_peer.dart';
import '../repositories/lan_peer_repository.dart';
import '../services/lan_mdns_service.dart';
import '../services/lan_sync_coordinator.dart';
import '../services/lan_secret_transfer_service.dart';

class LanSyncProvider extends ChangeNotifier {
  LanSyncProvider({
    required LanSyncCoordinator coordinator,
    required LanPeerRepository peerRepository,
    required LanMdnsService mdnsService,
  }) : _coordinator = coordinator,
       _peerRepository = peerRepository,
       _mdnsService = mdnsService {
    _discoverySubscription = _mdnsService.peers.listen((peers) {
      _discoveredPeers = peers;
      notifyListeners();
    });
    _secretRequestSubscription = _coordinator.secretTransferService.requests
        .listen((requests) {
          _secretRequests = requests;
          notifyListeners();
        });
  }

  final LanSyncCoordinator _coordinator;
  final LanPeerRepository _peerRepository;
  final LanMdnsService _mdnsService;
  StreamSubscription<List<LanDiscoveredPeer>>? _discoverySubscription;
  StreamSubscription<List<LanSecretTransferRequest>>?
  _secretRequestSubscription;

  List<LanPeer> _peers = const [];
  List<LanDiscoveredPeer> _discoveredPeers = const [];
  bool _busy = false;
  bool _hosting = false;
  String? _error;
  String? _notice;
  DateTime? _lastSyncAt;
  List<LanSecretTransferRequest> _secretRequests = const [];

  List<LanPeer> get peers => _peers;
  List<LanDiscoveredPeer> get discoveredPeers => _discoveredPeers;
  bool get busy => _busy;
  bool get hosting => _hosting;
  String? get error => _error;
  String? get notice => _notice;
  DateTime? get lastSyncAt => _lastSyncAt;
  List<LanSecretTransferRequest> get secretRequests => _secretRequests;

  set confirmPairing(LanPairingConfirmation confirmation) {
    _coordinator.confirmPairing = confirmation;
  }

  Future<void> initialize() async {
    _peers = await _peerRepository.loadPeers();
    notifyListeners();
  }

  Future<String?> showPairingQr() => _runResult(() async {
    await _coordinator.startHost();
    _hosting = true;
    return _coordinator.createPairingPayload();
  });

  Future<void> startDiscovery() => _run(() async {
    if (!await _ensureLanPermission()) return;
    await _mdnsService.discover();
  });

  Future<void> pair(String payload) => _run(() async {
    final result = await _coordinator.pair(payload);
    await initialize();
    if (result.synced) {
      _lastSyncAt = DateTime.now();
      _notice = '配对成功，已完成首次双向同步。';
    } else {
      _notice = '配对成功，但首次同步失败，可稍后在已发现设备中重试：${result.syncError}';
    }
  });

  Future<void> sync(LanDiscoveredPeer peer) => _run(() async {
    if (!await _ensureLanPermission()) return;
    await _coordinator.syncPeer(peer);
    _lastSyncAt = DateTime.now();
  });

  Future<void> requestSecretTransfer(
    LanDiscoveredPeer peer, {
    required String direction,
  }) => _run(() async {
    if (!await _ensureLanPermission()) return;
    await _coordinator.requestSecretTransfer(peer, direction: direction);
  });

  Future<void> approveSecretTransfer(LanSecretTransferRequest request) =>
      _run(() async {
        final peer = _discoveredPeers
            .where((item) => item.deviceId == request.peerDeviceId)
            .firstOrNull;
        if (peer == null) {
          throw StateError('请求设备当前不可发现，请让对方保持局域网托管后重试。');
        }
        _coordinator.secretTransferService.authorize(
          peerDeviceId: request.peerDeviceId,
          transferId: request.transferId,
          direction: request.direction,
        );
        await _coordinator.completeSecretTransfer(
          peer,
          transferId: request.transferId,
          direction: request.direction,
        );
      });

  void rejectSecretTransfer(LanSecretTransferRequest request) {
    _coordinator.secretTransferService.reject(request);
  }

  Future<bool> _ensureLanPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    final status = await Permission.nearbyWifiDevices.request();
    if (status.isGranted) return true;
    _error = status.isPermanentlyDenied
        ? '附近设备权限已被永久拒绝，请在系统设置中启用后重试。'
        : '未授予附近设备权限，无法发现或连接局域网设备。';
    return false;
  }

  Future<void> revoke(String deviceId) => _run(() async {
    await _peerRepository.revokePeer(deviceId);
    await initialize();
  });

  Future<void> _run(Future<void> Function() action) async {
    _busy = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _error = '$error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<T?> _runResult<T>(Future<T> Function() action) async {
    T? result;
    await _run(() async => result = await action());
    return result;
  }

  @override
  void dispose() {
    unawaited(_discoverySubscription?.cancel());
    unawaited(_secretRequestSubscription?.cancel());
    unawaited(_coordinator.stopHost());
    super.dispose();
  }
}
