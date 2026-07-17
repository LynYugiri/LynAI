import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/sync_change.dart';
import '../services/backend_client.dart';
import '../services/device_identity_service.dart';
import '../services/device_registration_service.dart';
import '../services/plugin_sync_validation.dart';
import '../services/storage_v2_database.dart';
import '../services/storage_v2_service.dart';
import '../services/sync_service.dart';

abstract class SyncStorage {
  Future<void> activateScope(String scope, String deviceId);
  Future<void> deactivateScope(String scope);
  Future<int> since(String scope);
  Future<List<SyncOutboxEntry>> loadOutbox(String scope);
  Future<List<SyncConflictEntry>> loadConflicts(String scope);
  Future<void> resolveConflict(
    String scope,
    int seq,
    SyncConflictResolution resolution,
  );
  Future<bool> acknowledgeOutbox(String scope, List<SyncOutboxEntry> entries);
  Future<void> applyRemoteChanges(
    String scope,
    List<SyncRemoteOperation> ops,
    int nextSince,
  );
  Future<void> updateSince(String scope, int since);
  Future<List<SyncResourceBlob>> resourceBlobsForOutbox(
    List<SyncOutboxEntry> entries,
  );
  Future<bool> hasResourceBlob(String sha256);
  Future<void> installResourceBlob(String sha256, List<int> bytes);
  Map<String, dynamic> normalizeRemoteResource(Map<String, dynamic> data);
  Future<bool> hasNoteBlob(String sha256);
  Future<void> installNoteBlob(String sha256, List<int> bytes);
}

class SyncResourceBlob {
  final String sha256;
  final List<int> bytes;

  const SyncResourceBlob({required this.sha256, required this.bytes});
}

class StorageV2SyncStorage implements SyncStorage {
  StorageV2SyncStorage(this._storage);

  final StorageV2Service _storage;

  @override
  Future<void> activateScope(String scope, String deviceId) =>
      _storage.activateSyncScope(scope, deviceId: deviceId);

  @override
  Future<void> deactivateScope(String scope) =>
      _storage.deactivateSyncScope(scope);

  @override
  Future<int> since(String scope) => _storage.syncSince(scope);

  @override
  Future<List<SyncOutboxEntry>> loadOutbox(String scope) =>
      _storage.loadSyncOutbox(scope);

  @override
  Future<List<SyncConflictEntry>> loadConflicts(String scope) =>
      _storage.loadSyncConflicts(scope);

  @override
  Future<void> resolveConflict(
    String scope,
    int seq,
    SyncConflictResolution resolution,
  ) => _storage.resolveSyncConflict(scope, seq, resolution);

  @override
  Future<bool> acknowledgeOutbox(String scope, List<SyncOutboxEntry> entries) =>
      _storage.acknowledgeSyncOutbox(scope, entries);

  @override
  Future<void> applyRemoteChanges(
    String scope,
    List<SyncRemoteOperation> ops,
    int nextSince,
  ) => _storage.applyRemoteChanges(scope, ops, nextSince);

  @override
  Future<void> updateSince(String scope, int since) =>
      _storage.updateSyncSince(scope, since);

  @override
  Future<List<SyncResourceBlob>> resourceBlobsForOutbox(
    List<SyncOutboxEntry> entries,
  ) async {
    final resourceIds = <String>{};
    final snapshotResourceIds = <String>{};
    final hashes = <String>{};
    final noteHashes = <String>{};
    for (final entry in entries) {
      if (entry.op != 'upsert') continue;
      if (entry.table == 'note_revisions') {
        final hash = entry.data?['contentHash'] as String?;
        if (hash != null) noteHashes.add(hash);
        continue;
      }
      if (entry.table == 'message_attachments') {
        final id = entry.data?['resourceId'] as String?;
        if (id != null && id.isNotEmpty) resourceIds.add(id);
      } else if (entry.table == 'resources' &&
          _isSyncedResourceRole(entry.data?['role'])) {
        snapshotResourceIds.add(entry.recordId);
        final hash = entry.data?['sha256'] as String?;
        if (entry.data?['missing'] != true && hash != null) hashes.add(hash);
      }
    }
    resourceIds.removeAll(snapshotResourceIds);
    final blobs = <SyncResourceBlob>[];
    for (final id in resourceIds) {
      final resource = await _storage.findResourceById(id);
      final hash = resource?.sha256Hash;
      if (resource == null ||
          !_isSyncedResourceRole(resource.role) ||
          resource.missing ||
          hash == null) {
        continue;
      }
      hashes.add(hash);
    }
    for (final hash in hashes) {
      blobs.add(
        SyncResourceBlob(
          sha256: hash,
          bytes: await _storage.readResourceBlob(hash),
        ),
      );
    }
    for (final hash in noteHashes) {
      blobs.add(
        SyncResourceBlob(
          sha256: hash,
          bytes: await _storage.readNoteBlob(hash),
        ),
      );
    }
    return blobs;
  }

  @override
  Future<bool> hasResourceBlob(String sha256) =>
      _storage.hasResourceBlob(sha256);

  @override
  Future<void> installResourceBlob(String sha256, List<int> bytes) =>
      _storage.installResourceBlob(sha256, bytes);

  @override
  Map<String, dynamic> normalizeRemoteResource(Map<String, dynamic> data) =>
      _storage.normalizeRemoteResource(data);

  @override
  Future<bool> hasNoteBlob(String sha256) => _storage.hasNoteBlob(sha256);

  @override
  Future<void> installNoteBlob(String sha256, List<int> bytes) =>
      _storage.installNoteBlob(sha256, bytes);

  static bool _isMessageResourceRole(Object? role) =>
      role == 'message_attachment' || role == 'message_image';

  static bool _isSyncedResourceRole(Object? role) =>
      _isMessageResourceRole(role) || role == 'background';
}

class SyncProvider extends ChangeNotifier {
  SyncProvider({
    BackendClient? backend,
    SyncService? service,
    SyncStorage? storage,
    Future<void> Function()? beforeRemoteApply,
    Future<void> Function()? onRemoteApplied,
    DeviceIdentityService? identity,
    DeviceRegistrationService? registration,
    Future<List<int>> Function(String hash)? readPluginBlob,
    Future<bool> Function(String hash)? hasPluginBlob,
    Future<void> Function(String hash, List<int> bytes)? installPluginBlob,
    Future<bool> Function(String changeId)? shouldApplyRemoteChange,
    Future<void> Function(Iterable<String> changeIds)? remoteChangesApplied,
  }) : _backend = backend,
       _injectedService = service,
       _storage = storage ?? StorageV2SyncStorage(StorageV2Service()),
       _beforeRemoteApply = beforeRemoteApply,
       _onRemoteApplied = onRemoteApplied,
       _identity = identity,
       _registration = registration,
       _readPluginBlob = readPluginBlob,
       _hasPluginBlob = hasPluginBlob,
       _installPluginBlob = installPluginBlob,
       _shouldApplyRemoteChange = shouldApplyRemoteChange,
       _remoteChangesApplied = remoteChangesApplied;

  final BackendClient? _backend;
  final SyncService? _injectedService;
  final SyncStorage _storage;
  final Future<void> Function()? _beforeRemoteApply;
  final Future<void> Function()? _onRemoteApplied;
  final DeviceIdentityService? _identity;
  final DeviceRegistrationService? _registration;
  final Future<List<int>> Function(String hash)? _readPluginBlob;
  final Future<bool> Function(String hash)? _hasPluginBlob;
  final Future<void> Function(String hash, List<int> bytes)? _installPluginBlob;
  final Future<bool> Function(String changeId)? _shouldApplyRemoteChange;
  final Future<void> Function(Iterable<String> changeIds)?
  _remoteChangesApplied;
  RemoteSyncService? _remoteService;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  String? _scope;
  bool _syncing = false;
  String? _error;
  DateTime? _lastSyncAt;
  List<SyncConflictEntry> _conflicts = const [];

  SyncService? get _service {
    if (_injectedService != null) return _injectedService;
    final backend = _backend;
    if (backend == null || !backend.isConnected) return null;
    final identity = _identity;
    final registration = _registration;
    if (identity == null || registration == null) return null;
    return _remoteService ??= RemoteSyncService(
      backend,
      identity: identity,
      registration: registration,
    );
  }

  bool get syncing => _syncing;
  String? get error => _error;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get scope => _scope;
  List<SyncConflictEntry> get conflicts => _conflicts;

  bool get canSync {
    if (_scope == null || _service == null) return false;
    if (_injectedService != null && _backend == null) return true;
    return (_backend?.accessToken ?? '').isNotEmpty;
  }

  Future<void> bindScope(String userId) {
    return _enqueue(() async {
      final normalizedUserId = userId.trim();
      final backendUrl = DeviceIdentityService.backendOrigin(
        _backend?.backendUrl ?? 'injected',
      );
      final effectiveBackend = backendUrl.isEmpty && _injectedService != null
          ? 'injected'
          : backendUrl;
      if (normalizedUserId.isEmpty || effectiveBackend.isEmpty) return;
      final identityScope = effectiveBackend == 'injected'
          ? DeviceIdentityService.lanScope
          : DeviceIdentityService.accountScope(
              effectiveBackend,
              normalizedUserId,
            );
      final deviceId =
          (await _identity?.initialize(scope: identityScope))?.deviceId ??
          'injected';
      final nextScope = '$effectiveBackend|$normalizedUserId';
      final previous = _scope;
      if (previous == nextScope) return;
      await _beforeRemoteApply?.call();
      if (previous != null) await _storage.deactivateScope(previous);
      await _storage.activateScope(nextScope, deviceId);
      _scope = nextScope;
      _conflicts = await _storage.loadConflicts(nextScope);
    });
  }

  Future<void> unbind() {
    return _enqueue(() async {
      final current = _scope;
      if (current == null) return;
      await _beforeRemoteApply?.call();
      await _storage.deactivateScope(current);
      _scope = null;
      _conflicts = const [];
    });
  }

  Future<void> autoDownload() => _enqueue(_syncDownloadThenUpload);

  Future<void> manualSync() => _enqueue(_syncDownloadThenUpload);

  Future<void> flushUpload() => _enqueue(_uploadOutbox);

  Future<void> _syncDownloadThenUpload() async {
    if (!canSync) return;
    final limits = (await _service!.getStatus()).limits;
    await _downloadPages(limits);
    final uploaded = await _uploadOutbox(limits);
    if (uploaded) await _downloadPages(limits);
    _lastSyncAt = DateTime.now();
  }

  Future<void> _downloadPages(SyncLimits limits) async {
    final service = _service;
    final currentScope = _scope;
    if (service == null || currentScope == null || !canSync) return;
    var cursor = await _storage.since(currentScope);
    var appliedRemote = false;
    var flushedLocalSaves = false;
    while (true) {
      final page = await service.getChanges(
        since: cursor,
        limit: limits.maxChangesPageSize,
      );
      final next = page.nextSince;
      if ((page.hasMore || page.changes.isNotEmpty) && next <= cursor) {
        throw StateError('同步分页未前进: since=$cursor nextSince=$next');
      }
      final ops = await _prepareRemoteOperations(service, page.changes);
      if (ops.isNotEmpty && !flushedLocalSaves) {
        await _beforeRemoteApply?.call();
        flushedLocalSaves = true;
      }
      if (ops.isEmpty) {
        await _storage.updateSince(currentScope, next);
      } else {
        await _storage.applyRemoteChanges(currentScope, ops, next);
        await _remoteChangesApplied?.call(
          ops.map((op) => op.change?.changeId).whereType<String>(),
        );
        appliedRemote = true;
      }
      cursor = next;
      if (!page.hasMore) break;
    }
    if (appliedRemote) await _onRemoteApplied?.call();
    _conflicts = await _storage.loadConflicts(currentScope);
  }

  Future<void> resolveConflict(int seq, SyncConflictResolution resolution) {
    return _enqueue(() async {
      final currentScope = _scope;
      if (currentScope == null) return;
      await _storage.resolveConflict(currentScope, seq, resolution);
      _conflicts = await _storage.loadConflicts(currentScope);
      await _onRemoteApplied?.call();
    });
  }

  Future<bool> _uploadOutbox([SyncLimits? advertisedLimits]) async {
    final service = _service;
    final currentScope = _scope;
    if (service == null || currentScope == null || !canSync) return false;
    final snapshot = await _storage.loadOutbox(currentScope);
    if (snapshot.isEmpty) return false;
    final limits = advertisedLimits ?? (await service.getStatus()).limits;
    final uploadable = snapshot
        .where((entry) {
          final data = entry.data;
          if (data != null &&
              utf8.encode(jsonEncode(data)).length >
                  limits.maxChangeDataBytes) {
            return false;
          }
          return _uploadBodyBytes([_recordForEntry(entry)]) <=
              limits.maxChangesRequestBytes;
        })
        .toList(growable: false);
    if (uploadable.isEmpty) {
      throw StateError(
        'all pending sync changes exceed advertised per-change limits',
      );
    }
    final blobs = await _storage.resourceBlobsForOutbox(uploadable);
    final pluginHashes = uploadable
        .where(
          (entry) => entry.op == 'upsert' && entry.table.startsWith('plugin_'),
        )
        .map((entry) => entry.data?['sha256'] as String?)
        .whereType<String>()
        .toSet();
    final allBlobs = <SyncResourceBlob>[
      ...blobs,
      for (final hash in pluginHashes)
        if (_readPluginBlob != null)
          SyncResourceBlob(sha256: hash, bytes: await _readPluginBlob(hash)),
    ];
    if (allBlobs.isNotEmpty) {
      final remoteHashes = (await service.listBlobs(
        limit: limits.maxBlobsPageSize,
      )).map((blob) => blob.sha256).toSet();
      for (final blob in allBlobs) {
        if (blob.bytes.length > limits.maxBlobBytes) {
          throw StateError(
            'sync blob ${blob.sha256} exceeds ${limits.maxBlobBytes} bytes',
          );
        }
        if (remoteHashes.add(blob.sha256)) {
          await service.uploadBlob(blob.sha256, blob.bytes);
        }
      }
    }
    for (final batch in _uploadBatches(uploadable, limits)) {
      final result = await service.uploadChanges(
        batch.map(_recordForEntry).toList(growable: false),
      );
      final acknowledgements = result.acknowledgements;
      if (acknowledgements != null) {
        final ackKeys = {
          for (final ack in acknowledgements)
            '${ack.changeId}:${ack.mutationVersion}',
        };
        final expected = {
          for (final entry in batch)
            '${entry.changeId}:${entry.mutationVersion}',
        };
        if (ackKeys.length != expected.length ||
            !ackKeys.containsAll(expected)) {
          throw StateError('sync server did not ACK the exact uploaded batch');
        }
      }
      final appliedConflict = await _storage.acknowledgeOutbox(
        currentScope,
        batch,
      );
      if (appliedConflict) await _onRemoteApplied?.call();
    }
    if (uploadable.length != snapshot.length) {
      throw StateError(
        '${snapshot.length - uploadable.length} pending sync change(s) exceed '
        'advertised per-change limits',
      );
    }
    return true;
  }

  List<List<SyncOutboxEntry>> _uploadBatches(
    List<SyncOutboxEntry> entries,
    SyncLimits limits,
  ) {
    final batches = <List<SyncOutboxEntry>>[];
    var current = <SyncOutboxEntry>[];
    var currentRecords = <SyncChangeRecord>[];
    for (final entry in entries) {
      final record = _recordForEntry(entry);
      final candidateRecords = [...currentRecords, record];
      if (_uploadBodyBytes(candidateRecords) > limits.maxChangesRequestBytes) {
        if (current.isEmpty) {
          throw StateError(
            'single sync change exceeds ${limits.maxChangesRequestBytes} UTF-8 body bytes',
          );
        }
        batches.add(current);
        current = [entry];
        currentRecords = [record];
        if (_uploadBodyBytes(currentRecords) > limits.maxChangesRequestBytes) {
          throw StateError(
            'single sync change exceeds ${limits.maxChangesRequestBytes} UTF-8 body bytes',
          );
        }
      } else {
        current.add(entry);
        currentRecords = candidateRecords;
      }
      if (current.length == limits.maxChangesPerRequest) {
        batches.add(current);
        current = <SyncOutboxEntry>[];
        currentRecords = <SyncChangeRecord>[];
      }
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  int _uploadBodyBytes(List<SyncChangeRecord> records) {
    final requestId = RemoteSyncService.requestIdForChanges(records);
    return utf8
        .encode(
          jsonEncode({
            'requestId': requestId,
            'changes': records.map((record) => record.toJson()).toList(),
          }),
        )
        .length;
  }

  SyncChangeRecord _recordForEntry(SyncOutboxEntry entry) => SyncChangeRecord(
    table: entry.table,
    op: entry.op,
    recordId: entry.recordId,
    data: entry.data,
    changeId: entry.changeId,
    deviceId: entry.deviceId,
    clientCreatedAt: entry.clientCreatedAt,
    mutationVersion: entry.mutationVersion,
  );

  List<SyncRemoteOperation> _operations(List<SyncChange> changes) {
    return changes
        .map(
          (change) => (
            table: change.table,
            op: change.op,
            data: change.op == 'delete'
                ? <String, dynamic>{'id': change.recordId}
                : change.data,
            change: change,
          ),
        )
        .toList(growable: false);
  }

  Future<List<SyncRemoteOperation>> _prepareRemoteOperations(
    SyncService service,
    List<SyncChange> changes,
  ) async {
    final prepared = <SyncChange>[];
    for (final change in changes) {
      _validateRemoteChange(change);
      final shouldApply = _shouldApplyRemoteChange;
      if (shouldApply != null && !await shouldApply(change.changeId)) continue;
      if (change.table == 'note_revisions' && change.op == 'upsert') {
        final hash = change.data?['contentHash'] as String?;
        if (hash == null) throw StateError('远端笔记修订缺少 contentHash');
        if (!await _storage.hasNoteBlob(hash)) {
          await _storage.installNoteBlob(
            hash,
            await service.downloadBlob(hash),
          );
        }
        prepared.add(change);
        continue;
      }
      if (change.table.startsWith('plugin_') && change.op == 'upsert') {
        final hash = change.data?['sha256'] as String?;
        if (hash != null &&
            _hasPluginBlob != null &&
            _installPluginBlob != null &&
            !await _hasPluginBlob(hash)) {
          await _installPluginBlob(hash, await service.downloadBlob(hash));
        }
        prepared.add(change);
        continue;
      }
      if (change.table != 'resources' ||
          change.op != 'upsert' ||
          change.data == null) {
        prepared.add(change);
        continue;
      }
      if (!StorageV2SyncStorage._isMessageResourceRole(change.data!['role'])) {
        if (change.data!['role'] != 'background') continue;
      }
      final data = _storage.normalizeRemoteResource(change.data!);
      final hash = data['sha256'] as String?;
      if (data['missing'] != true && hash != null) {
        if (!await _storage.hasResourceBlob(hash)) {
          await _storage.installResourceBlob(
            hash,
            await service.downloadBlob(hash),
          );
        }
      }
      prepared.add(
        SyncChange(
          seq: change.seq,
          changeId: change.changeId,
          deviceId: change.deviceId,
          clientCreatedAt: change.clientCreatedAt,
          table: change.table,
          op: change.op,
          recordId: change.recordId,
          data: data,
          createdAt: change.createdAt,
        ),
      );
    }
    prepared.sort((a, b) {
      const order = {
        'note_folders': 0,
        'notes': 1,
        'note_pages': 2,
        'note_revisions': 3,
        'note_page_heads': 4,
        'note_page_tombstones': 5,
        'resources': 6,
      };
      final byTable = (order[a.table] ?? 10).compareTo(order[b.table] ?? 10);
      return byTable != 0 ? byTable : a.seq.compareTo(b.seq);
    });
    return _operations(prepared);
  }

  void _validateRemoteChange(SyncChange change) {
    const tables = {
      'resources',
      'conversations',
      'messages',
      'message_attachments',
      'schedules',
      'todo_lists',
      'todo_items',
      'roleplay_scenarios',
      'roleplay_threads',
      'recycle_bin',
      'note_folders',
      'notes',
      'note_pages',
      'note_revisions',
      'note_page_heads',
      'note_page_tombstones',
      'shared_settings',
      'synced_model_configs',
      'plugin_files',
      'plugin_settings',
      'plugin_config',
    };
    if (!tables.contains(change.table)) {
      throw StateError('unsupported remote sync table: ${change.table}');
    }
    if (change.op != 'upsert' && change.op != 'delete') {
      throw StateError('unsupported remote sync operation: ${change.op}');
    }
    if (change.recordId.isEmpty) {
      throw StateError('remote sync recordId is empty');
    }
    if (change.op == 'upsert') {
      final dataId = change.data?['id'];
      if (dataId != change.recordId) {
        throw StateError(
          'remote sync data.id does not match recordId: ${change.recordId}',
        );
      }
      if (change.table.startsWith('plugin_')) {
        validatePluginSyncChange(change);
      }
    }
  }

  Future<void> _enqueue(Future<void> Function() action) {
    if (_disposed) return Future.value();
    final result = _queue.then((_) => _run(action));
    _queue = result.catchError((_) {});
    return result;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_disposed) return;
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
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
