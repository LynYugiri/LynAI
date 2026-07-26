import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/lan_peer.dart';
import '../models/sync_data_selection.dart';
import '../repositories/lan_peer_repository.dart';
import '../services/lan_mdns_service.dart';
import '../services/lan_device_profile_service.dart';
import '../services/lan_sync_coordinator.dart';
import '../services/lan_secret_transfer_service.dart';
import '../services/storage_v2_database.dart';

typedef LanHostingOperation = Future<void> Function();

class LanHostingLifecycle {
  LanHostingLifecycle({
    required LanHostingOperation start,
    required LanHostingOperation stop,
    required LanHostingOperation close,
    void Function(bool hosting)? onHostingChanged,
  }) : _start = start,
       _stop = stop,
       _close = close,
       _onHostingChanged = onHostingChanged;

  final LanHostingOperation _start;
  final LanHostingOperation _stop;
  final LanHostingOperation _close;
  final void Function(bool hosting)? _onHostingChanged;

  Future<void> _queue = Future.value();
  Future<void>? _closeFuture;
  bool _ready = false;
  bool _desired = false;
  bool _hosting = false;
  bool _closed = false;

  bool get ready => _ready;
  bool get desired => _desired;
  bool get hosting => _hosting;

  Future<void> markReady() {
    if (_closed) return Future.value();
    _ready = true;
    return _scheduleReconcile();
  }

  Future<void> setDesired(bool desired) {
    if (_closed) return Future.value();
    _desired = desired;
    return _scheduleReconcile();
  }

  Future<void> restart() {
    if (_closed) return Future.value();
    final operation = _queue.then((_) async {
      if (_hosting) {
        await _stop();
        _setHosting(false);
      }
      await _reconcile();
    });
    _queue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _scheduleReconcile() {
    final operation = _queue.then((_) => _reconcile());
    _queue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _reconcile() async {
    while (true) {
      final shouldHost = _ready && _desired && !_closed;
      if (_hosting == shouldHost) return;
      if (shouldHost) {
        await _start();
        _setHosting(true);
      } else {
        await _stop();
        _setHosting(false);
      }
    }
  }

  void _setHosting(bool value) {
    _hosting = value;
    _onHostingChanged?.call(value);
  }

  Future<void> close() => _closeFuture ??= _closeLifecycle();

  Future<void> _closeLifecycle() async {
    _desired = false;
    _closed = true;
    try {
      await _queue;
      await _reconcile();
    } finally {
      await _close();
    }
  }
}

class LanSyncProvider extends ChangeNotifier {
  LanSyncProvider({
    required LanSyncCoordinator coordinator,
    required LanPeerRepository peerRepository,
    required LanMdnsService mdnsService,
    required LanDeviceProfileService deviceProfileService,
  }) : _coordinator = coordinator,
       _peerRepository = peerRepository,
       _mdnsService = mdnsService,
       _deviceProfileService = deviceProfileService {
    _hostingLifecycle = LanHostingLifecycle(
      start: () async {
        _deviceName = await _deviceProfileService.displayName();
        await _coordinator.startHost(displayName: _deviceName);
      },
      stop: _coordinator.stopHost,
      close: _coordinator.close,
      onHostingChanged: (_) {
        if (!_disposed) notifyListeners();
      },
    );
    _discoverySubscription = _mdnsService.peers.listen((peers) {
      if (_disposed) return;
      _discoveredPeers = peers;
      notifyListeners();
    });
    _secretRequestSubscription = _coordinator.secretTransferService.requests
        .listen((requests) {
          if (_disposed) return;
          _secretRequests = requests;
          notifyListeners();
        });
  }

  // This provider owns the coordinator created for it in main.dart.
  final LanSyncCoordinator _coordinator;
  final LanPeerRepository _peerRepository;
  final LanMdnsService _mdnsService;
  final LanDeviceProfileService _deviceProfileService;
  late final LanHostingLifecycle _hostingLifecycle;
  StreamSubscription<List<LanDiscoveredPeer>>? _discoverySubscription;
  StreamSubscription<List<LanSecretTransferRequest>>?
  _secretRequestSubscription;

  List<LanPeer> _peers = const [];
  List<LanDiscoveredPeer> _discoveredPeers = const [];
  bool _busy = false;
  String? _error;
  String? _notice;
  DateTime? _lastSyncAt;
  List<LanSecretTransferRequest> _secretRequests = const [];
  bool _disposed = false;
  String _deviceName = '';
  List<SyncConflictEntry> _conflicts = const [];

  List<LanPeer> get peers => _peers;
  List<LanDiscoveredPeer> get discoveredPeers => _discoveredPeers;
  bool get busy => _busy;
  bool get hosting => _hostingLifecycle.hosting;
  bool get hostingDesired => _hostingLifecycle.desired;
  bool get runtimeReady => _hostingLifecycle.ready;
  String? get error => _error;
  String? get notice => _notice;
  DateTime? get lastSyncAt => _lastSyncAt;
  List<LanSecretTransferRequest> get secretRequests => _secretRequests;
  String get deviceName => _deviceName;
  List<SyncConflictEntry> get conflicts => _conflicts;

  set confirmPairing(LanPairingConfirmation confirmation) {
    _coordinator.confirmPairing = confirmation;
  }

  set confirmPolicyProposal(LanPolicyConfirmation confirmation) {
    _coordinator.confirmPolicyProposal = confirmation;
  }

  Future<void> initialize() async {
    _deviceName = await _deviceProfileService.displayName();
    _peers = await _peerRepository.loadPeers();
    _conflicts = await _coordinator.loadConflicts();
    if (!_disposed) notifyListeners();
  }

  Future<String?> showPairingQr() => _runResult(() async {
    await resumeHosting();
    if (!hosting) throw StateError('LAN runtime is not ready');
    return _coordinator.createPairingPayload();
  });

  Future<void> markRuntimeReady() => _runHosting(_hostingLifecycle.markReady);

  Future<void> setHostingDesired(bool desired) =>
      _runHosting(() => _hostingLifecycle.setDesired(desired));

  Future<void> resumeHosting() => setHostingDesired(true);

  Future<void> pauseHosting() => setHostingDesired(false);

  Future<void> updateDeviceName(String value) => _run(() async {
    _deviceName = await _deviceProfileService.updateDisplayName(value);
    if (hosting) await _hostingLifecycle.restart();
  });

  Future<void> startDiscovery() => _run(() async {
    if (!await _ensureLanPermission()) return;
    final identity = await _coordinator.identityService.initialize();
    await _mdnsService.discover(localDeviceId: identity.deviceId);
  });

  Future<LanPairingResult?> pair(
    String payload, {
    SyncDataSelection proposedSelection = SyncDataSelection.defaults,
  }) => _runResult(() async {
    final result = await _coordinator.pair(
      payload,
      proposedSelection: proposedSelection,
    );
    await initialize();
    _notice = '配对成功。可立即同步，也可稍后从已发现设备发起。';
    return result;
  });

  Future<void> sync(LanDiscoveredPeer peer) => _run(() async {
    if (!await _ensureLanPermission()) return;
    await _coordinator.syncPeer(peer);
    _lastSyncAt = DateTime.now();
    _conflicts = await _coordinator.loadConflicts();
  });

  Future<void> resolveConflict(int seq, SyncConflictResolution resolution) =>
      _run(() async {
        await _coordinator.resolveConflict(seq, resolution);
        _conflicts = await _coordinator.loadConflicts();
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

  Future<void> updateSyncSelection(
    LanPeer peer,
    SyncDataSelection proposedSelection,
  ) => _run(() async {
    final reduced = peer.syncSelection.intersect(proposedSelection);
    await _peerRepository.updateSyncSelection(peer.deviceId, reduced);
    await initialize();
    if (proposedSelection.isSubsetOf(peer.syncSelection)) {
      _notice = '同步范围已缩减。';
      return;
    }
    final discovered = _discoveredPeers
        .where((item) => item.deviceId == peer.deviceId)
        .firstOrNull;
    if (discovered == null) {
      _notice = '缩减已生效；新增类别可在设备可发现后重试并由对方确认。';
      return;
    }
    final accepted = await _coordinator.proposeSyncSelection(
      discovered,
      proposedSelection,
    );
    await _peerRepository.updateSyncSelection(peer.deviceId, accepted);
    await initialize();
    _notice = accepted.hasSameCategories(proposedSelection)
        ? '双方已同意新的同步范围。'
        : '对方仅接受了部分新增类别。';
  });

  Future<void> _run(Future<void> Function() action) async {
    if (_disposed) return;
    _busy = true;
    _error = null;
    _notice = null;
    if (!_disposed) notifyListeners();
    try {
      await action();
    } catch (error) {
      _error = '$error';
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _runHosting(Future<void> Function() action) async {
    if (_disposed) return;
    _error = null;
    try {
      await action();
    } catch (error) {
      _error = '$error';
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  Future<T?> _runResult<T>(Future<T> Function() action) async {
    T? result;
    await _run(() async => result = await action());
    return result;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_discoverySubscription?.cancel());
    unawaited(_secretRequestSubscription?.cancel());
    unawaited(_hostingLifecycle.close());
    super.dispose();
  }
}
