import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sync_change.dart';
import '../services/backend_client.dart';
import '../services/storage_v2_service.dart';
import '../services/sync_service.dart';

/// 数据同步状态管理。
///
/// 通过 [BackendClient] 连接后端，执行增量同步：
/// - 启动/登录时自动 download + apply
/// - 数据变化时 30 秒防抖后自动 upload
/// - 登出前 flush upload
/// - 设置页提供手动同步按钮
///
/// Drift 按行 upsert/delete 方法和 Provider 操作队列是后续阶段的工作，
/// 当前 SyncProvider 先搭好框架，通过 [recordChange] 接收变更记录。
class SyncProvider extends ChangeNotifier {
  static const _lastSeqKey = 'lynai_sync_last_seq';

  final BackendClient? _backend;
  RemoteSyncService? _service;

  int _lastSeq = 0;
  bool _syncing = false;
  String? _error;
  DateTime? _lastSyncAt;
  Timer? _debounceTimer;
  final List<SyncChangeRecord> _pendingChanges = [];

  /// 创建同步 Provider。
  SyncProvider({BackendClient? backend}) : _backend = backend;

  RemoteSyncService? get _syncService {
    if (_backend != null && _backend.isConnected) {
      return _service ??= RemoteSyncService(_backend);
    }
    return null;
  }

  /// 是否正在同步。
  bool get syncing => _syncing;

  /// 最近一次同步错误。
  String? get error => _error;

  /// 上次同步时间。
  DateTime? get lastSyncAt => _lastSyncAt;

  /// 当前是否可以同步（后端已连接且已登录）。
  bool get canSync =>
      _backend != null &&
      _backend.isConnected &&
      (_backend.accessToken ?? '').isNotEmpty;

  /// 从 SharedPreferences 恢复上次同步 seq。
  Future<void> loadLastSeq() async {
    final prefs = await SharedPreferences.getInstance();
    _lastSeq = prefs.getInt(_lastSeqKey) ?? 0;
  }

  /// 启动/登录时自动下载增量并 apply。
  Future<void> autoDownload() async {
    final svc = _syncService;
    if (svc == null || !canSync) return;
    await _doSync(() async {
      final result = await svc.getChanges(since: _lastSeq);
      if (result.changes.isNotEmpty) {
        await _applyChanges(result.changes);
      }
      _lastSeq = result.latestSeq;
      _lastSyncAt = DateTime.now();
      await _saveLastSeq();
    });
  }

  /// 记录一条变更（由 Provider 在数据变化时调用）。
  /// 30 秒防抖后自动 upload。
  void recordChange(SyncChangeRecord change) {
    _pendingChanges.add(change);
    _scheduleDebouncedUpload();
  }

  /// 记录多条变更。
  void recordChanges(List<SyncChangeRecord> changes) {
    _pendingChanges.addAll(changes);
    _scheduleDebouncedUpload();
  }

  void _scheduleDebouncedUpload() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 30), _debouncedUpload);
  }

  Future<void> _debouncedUpload() async {
    final svc = _syncService;
    if (svc == null || !canSync || _pendingChanges.isEmpty) return;

    await _doSync(() async {
      // 上传前先检查服务端是否有新变更（其他设备可能已上传）。
      // 状态检查也放在 _doSync 内，避免自动上传失败时丢失 error 状态。
      final status = await svc.getStatus();
      if (status.lastSeq > _lastSeq) {
        final result = await svc.getChanges(since: _lastSeq);
        if (result.changes.isNotEmpty) {
          await _applyChanges(result.changes);
        }
        _lastSeq = result.latestSeq;
        await _saveLastSeq();
      }

      final changes = List.of(_pendingChanges);
      _pendingChanges.clear();
      final SyncUploadResult result;
      try {
        result = await svc.uploadChanges(changes);
      } catch (_) {
        _pendingChanges.insertAll(0, changes);
        rethrow;
      }
      _lastSeq = result.latestSeq;
      _lastSyncAt = DateTime.now();
      await _saveLastSeq();
    });
  }

  /// 登出前/生命周期暂停时 flush 待上传的变更。
  Future<void> flushUpload() async {
    _debounceTimer?.cancel();
    if (_pendingChanges.isEmpty) return;
    await _debouncedUpload();
  }

  /// 手动同步（设置页按钮触发）。
  Future<void> manualSync() async {
    final svc = _syncService;
    if (svc == null || !canSync) return;

    await _doSync(() async {
      // 先下载
      final result = await svc.getChanges(since: _lastSeq);
      if (result.changes.isNotEmpty) {
        await _applyChanges(result.changes);
      }
      _lastSeq = result.latestSeq;

      // 再上传待发变更
      if (_pendingChanges.isNotEmpty) {
        final changes = List.of(_pendingChanges);
        _pendingChanges.clear();
        final SyncUploadResult uploadResult;
        try {
          uploadResult = await svc.uploadChanges(changes);
        } catch (_) {
          _pendingChanges.insertAll(0, changes);
          rethrow;
        }
        _lastSeq = uploadResult.latestSeq;
      }

      _lastSyncAt = DateTime.now();
      await _saveLastSeq();
    });
  }

  Future<void> _doSync(Future<void> Function() action) async {
    _syncing = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      _error = e.toString();
      debugPrint('同步失败: $e');
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Apply 下载的变更到本地 Drift。
  ///
  /// 逐条根据 table + op 执行 upsert 或 delete，通过
  /// [StorageV2Database.batchIncremental] 在一个事务内完成。
  Future<void> _applyChanges(List<SyncChange> changes) async {
    if (changes.isEmpty) return;
    final ops = <({String table, String op, Map<String, dynamic>? data})>[];
    for (final change in changes) {
      if (change.op == 'delete') {
        ops.add((
          table: change.table,
          op: 'delete',
          data: {'id': change.recordId},
        ));
      } else if (change.op == 'upsert' && change.data != null) {
        ops.add((table: change.table, op: 'upsert', data: change.data));
      }
    }
    if (ops.isEmpty) return;
    final db = await StorageV2Service().storageDatabase();
    await db.batchIncremental(ops);
  }

  Future<void> _saveLastSeq() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSeqKey, _lastSeq);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
