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
  Future<List<SyncOutboxEntry>> loadOutbox(
    String scope, {
    int? limit,
    int offset = 0,
  });
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
  Future<List<SyncBlobDescriptor>> resourceBlobDescriptorsForOutbox(
    List<SyncOutboxEntry> entries,
  ) async => [
    for (final blob in await resourceBlobsForOutbox(entries))
      SyncBlobDescriptor(
        sha256: blob.sha256,
        readBytes: () async => blob.bytes,
      ),
  ];
  Future<bool> hasResourceBlob(String sha256);
  Future<void> installResourceBlob(String sha256, List<int> bytes);
  Map<String, dynamic> normalizeRemoteResource(Map<String, dynamic> data);
  Future<bool> hasNoteBlob(String sha256);
  Future<void> installNoteBlob(String sha256, List<int> bytes);
  Future<void> materializeNotes();
}

class _PreparedUploadEntry {
  final SyncOutboxEntry entry;
  final SyncChangeRecord record;
  final int recordBytes;
  final int dataBytes;

  const _PreparedUploadEntry({
    required this.entry,
    required this.record,
    required this.recordBytes,
    required this.dataBytes,
  });

  String get rowKey => '${entry.table}\u0000${entry.recordId}';
}

class SyncApplySummary {
  const SyncApplySummary({required this.scope, required this.changedTables});

  final String scope;
  final Set<String> changedTables;
}

class SyncResourceBlob {
  final String sha256;
  final List<int> bytes;

  const SyncResourceBlob({required this.sha256, required this.bytes});
}

class SyncBlobDescriptor {
  final String sha256;
  final Future<List<int>> Function() readBytes;

  const SyncBlobDescriptor({required this.sha256, required this.readBytes});
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
  Future<List<SyncOutboxEntry>> loadOutbox(
    String scope, {
    int? limit,
    int offset = 0,
  }) => _storage.loadSyncOutbox(scope, limit: limit, offset: offset);

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
    final descriptors = await resourceBlobDescriptorsForOutbox(entries);
    final blobs = <SyncResourceBlob>[];
    for (final descriptor in descriptors) {
      blobs.add(
        SyncResourceBlob(
          sha256: descriptor.sha256,
          bytes: await descriptor.readBytes(),
        ),
      );
    }
    return blobs;
  }

  @override
  Future<List<SyncBlobDescriptor>> resourceBlobDescriptorsForOutbox(
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
    final blobs = <SyncBlobDescriptor>[];
    for (final resource in await _storage.findResourcesByIds(resourceIds)) {
      final hash = resource.sha256Hash;
      if (!_isSyncedResourceRole(resource.role) ||
          resource.missing ||
          hash == null) {
        continue;
      }
      hashes.add(hash);
    }
    for (final hash in hashes) {
      blobs.add(
        SyncBlobDescriptor(
          sha256: hash,
          readBytes: () => _storage.readResourceBlob(hash),
        ),
      );
    }
    for (final hash in noteHashes) {
      blobs.add(
        SyncBlobDescriptor(
          sha256: hash,
          readBytes: () => _storage.readNoteBlob(hash),
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

  @override
  Future<void> materializeNotes() => _storage.recoverNoteMaterialization();

  static bool _isMessageResourceRole(Object? role) =>
      role == 'message_attachment' || role == 'message_image';

  static bool _isSyncedResourceRole(Object? role) =>
      _isMessageResourceRole(role) || role == 'background';
}

class SyncProvider extends ChangeNotifier {
  static const _outboxWindowSize = 256;

  SyncProvider({
    BackendClient? backend,
    SyncService? service,
    SyncStorage? storage,
    Future<void> Function(SyncApplySummary summary)? beforeRemoteApply,
    Future<void> Function(SyncApplySummary summary)? onRemoteApplied,
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
       _remoteChangesApplied = remoteChangesApplied,
       _backendScope = backend?.backendScope ?? '' {
    _backend?.addListener(_handleBackendChanged);
  }

  final BackendClient? _backend;
  final SyncService? _injectedService;
  final SyncStorage _storage;
  final Future<void> Function(SyncApplySummary summary)? _beforeRemoteApply;
  final Future<void> Function(SyncApplySummary summary)? _onRemoteApplied;
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
  String _backendScope;
  int _generation = 0;

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
    final generation = ++_generation;
    return _enqueue(() async {
      if (!_isCurrent(generation)) return;
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
      if (!_isCurrent(generation)) return;
      final nextScope = '$effectiveBackend|$normalizedUserId';
      final previous = _scope;
      if (previous == nextScope) return;
      await _beforeRemoteApply?.call(
        SyncApplySummary(scope: nextScope, changedTables: const {}),
      );
      if (!_isCurrent(generation)) return;
      if (previous != null) await _storage.deactivateScope(previous);
      if (!_isCurrent(generation)) return;
      await _storage.activateScope(nextScope, deviceId);
      if (!_isCurrent(generation)) return;
      _scope = nextScope;
      _conflicts = await _storage.loadConflicts(nextScope);
    });
  }

  Future<void> unbind() {
    final generation = ++_generation;
    return _enqueue(() async {
      if (!_isCurrent(generation)) return;
      final current = _scope;
      if (current == null) return;
      await _beforeRemoteApply?.call(
        SyncApplySummary(scope: current, changedTables: const {}),
      );
      if (!_isCurrent(generation)) return;
      await _storage.deactivateScope(current);
      if (!_isCurrent(generation)) return;
      _scope = null;
      _conflicts = const [];
    });
  }

  Future<void> autoDownload() {
    final generation = _generation;
    return _enqueue(() => _syncDownloadThenUpload(generation));
  }

  Future<void> manualSync() {
    final generation = _generation;
    return _enqueue(() => _syncDownloadThenUpload(generation));
  }

  Future<void> flushUpload() {
    final generation = _generation;
    return _enqueue(() => _flushUpload(generation));
  }

  Future<void> _syncDownloadThenUpload(int generation) async {
    if (!_isCurrent(generation) || !canSync) return;
    final currentScope = _scope;
    if (currentScope == null) return;
    final limits = (await _service!.getStatus()).limits;
    if (!_isCurrentScope(generation, currentScope)) return;
    final changedTables = <String>{};
    final flushedTables = <String>{};
    changedTables.addAll(
      await _downloadPages(limits, generation, flushedTables),
    );
    if (!_isCurrentScope(generation, currentScope)) return;
    final uploaded = await _uploadOutbox(
      advertisedLimits: limits,
      generation: generation,
      changedTables: changedTables,
    );
    if (uploaded && _isCurrentScope(generation, currentScope)) {
      changedTables.addAll(
        await _downloadPages(limits, generation, flushedTables),
      );
    }
    if (!_isCurrentScope(generation, currentScope)) return;
    await _finishRemoteApply(currentScope, changedTables, generation);
    if (!_isCurrentScope(generation, currentScope)) return;
    _lastSyncAt = DateTime.now();
  }

  Future<Set<String>> _downloadPages(
    SyncLimits limits,
    int generation,
    Set<String> flushedTables,
  ) async {
    final service = _service;
    final currentScope = _scope;
    if (service == null ||
        currentScope == null ||
        !_isCurrent(generation) ||
        !canSync) {
      return const {};
    }
    var cursor = await _storage.since(currentScope);
    if (!_isCurrentScope(generation, currentScope)) return const {};
    final changedTables = <String>{};
    while (true) {
      final page = await service.getChanges(
        since: cursor,
        limit: limits.maxChangesPageSize,
      );
      if (!_isCurrentScope(generation, currentScope)) return const {};
      _validateRemotePage(cursor, page);
      final next = page.nextSince;
      final ops = await _prepareRemoteOperations(service, page.changes);
      if (!_isCurrentScope(generation, currentScope)) return const {};
      final pageTables = ops.map((op) => op.table).toSet();
      final unflushedTables = pageTables.difference(flushedTables);
      if (unflushedTables.isNotEmpty) {
        await _beforeRemoteApply?.call(
          SyncApplySummary(scope: currentScope, changedTables: unflushedTables),
        );
        if (!_isCurrentScope(generation, currentScope)) return const {};
        flushedTables.addAll(unflushedTables);
      }
      if (ops.isEmpty) {
        await _storage.updateSince(currentScope, next);
      } else {
        await _storage.applyRemoteChanges(currentScope, ops, next);
        if (!_isCurrentScope(generation, currentScope)) return const {};
        await _remoteChangesApplied?.call(
          ops.map((op) => op.change?.changeId).whereType<String>(),
        );
        changedTables.addAll(pageTables);
      }
      if (!_isCurrentScope(generation, currentScope)) return const {};
      cursor = next;
      if (!page.hasMore) break;
    }
    _conflicts = await _storage.loadConflicts(currentScope);
    return changedTables;
  }

  Future<void> _flushUpload(int generation) async {
    final currentScope = _scope;
    if (currentScope == null || !_isCurrent(generation)) return;
    final changedTables = <String>{};
    await _uploadOutbox(generation: generation, changedTables: changedTables);
    if (!_isCurrentScope(generation, currentScope)) return;
    await _finishRemoteApply(currentScope, changedTables, generation);
  }

  Future<void> _finishRemoteApply(
    String scope,
    Set<String> changedTables,
    int generation,
  ) async {
    if (changedTables.isEmpty) return;
    if (_noteTables.any(changedTables.contains)) {
      await _storage.materializeNotes();
      if (!_isCurrentScope(generation, scope)) return;
    }
    await _onRemoteApplied?.call(
      SyncApplySummary(scope: scope, changedTables: changedTables),
    );
  }

  Future<void> resolveConflict(int seq, SyncConflictResolution resolution) {
    final generation = _generation;
    return _enqueue(() async {
      final currentScope = _scope;
      if (currentScope == null || !_isCurrent(generation)) return;
      String? table;
      for (final conflict in _conflicts) {
        if (conflict.seq == seq) {
          table = conflict.table;
          break;
        }
      }
      await _storage.resolveConflict(currentScope, seq, resolution);
      if (!_isCurrentScope(generation, currentScope)) return;
      _conflicts = await _storage.loadConflicts(currentScope);
      if (table != null) {
        if (_noteTables.contains(table)) await _storage.materializeNotes();
        await _onRemoteApplied?.call(
          SyncApplySummary(scope: currentScope, changedTables: {table}),
        );
      }
    });
  }

  Future<bool> _uploadOutbox({
    SyncLimits? advertisedLimits,
    required int generation,
    required Set<String> changedTables,
  }) async {
    final service = _service;
    final currentScope = _scope;
    if (service == null ||
        currentScope == null ||
        !_isCurrent(generation) ||
        !canSync) {
      return false;
    }
    final limits = advertisedLimits ?? (await service.getStatus()).limits;
    if (!_isCurrentScope(generation, currentScope)) return false;
    var uploaded = false;
    var offset = 0;
    final oversizedRows = <String>{};
    while (true) {
      final snapshot = await _storage.loadOutbox(
        currentScope,
        limit: _outboxWindowSize,
        offset: offset,
      );
      if (!_isCurrentScope(generation, currentScope)) return false;
      if (snapshot.isEmpty) break;
      final uploadable = <_PreparedUploadEntry>[];
      for (final entry in snapshot) {
        final prepared = _prepareUploadEntry(entry);
        if (prepared.dataBytes > limits.maxChangeDataBytes ||
            _singleUploadBodyBytes(prepared.recordBytes) >
                limits.maxChangesRequestBytes) {
          oversizedRows.add(prepared.rowKey);
        } else {
          uploadable.add(prepared);
          oversizedRows.remove(prepared.rowKey);
        }
      }
      if (uploadable.isEmpty) {
        offset += snapshot.length;
        continue;
      }
      await _uploadBlobs(service, uploadable, limits, currentScope, generation);
      if (!_isCurrentScope(generation, currentScope)) return false;
      for (final batch in _uploadBatches(uploadable, limits)) {
        final entries = batch.map((item) => item.entry).toList(growable: false);
        final result = await service.uploadChanges(
          batch.map((item) => item.record).toList(growable: false),
        );
        if (!_isCurrentScope(generation, currentScope)) return false;
        _validateAcknowledgements(result, entries);
        final appliedConflict = await _storage.acknowledgeOutbox(
          currentScope,
          entries,
        );
        if (!_isCurrentScope(generation, currentScope)) return false;
        if (appliedConflict) {
          changedTables.addAll(entries.map((entry) => entry.table));
        }
        oversizedRows.removeAll(entries.map(_outboxRowKey));
        uploaded = true;
      }
      offset = 0;
    }
    if (oversizedRows.isNotEmpty) {
      throw StateError(
        '${oversizedRows.length} pending sync change(s) exceed '
        'advertised per-change limits',
      );
    }
    return uploaded;
  }

  Future<void> _uploadBlobs(
    SyncService service,
    List<_PreparedUploadEntry> uploadable,
    SyncLimits limits,
    String currentScope,
    int generation,
  ) async {
    final entries = uploadable
        .map((item) => item.entry)
        .toList(growable: false);
    final descriptors = await _storage.resourceBlobDescriptorsForOutbox(
      entries,
    );
    final readPluginBlob = _readPluginBlob;
    if (readPluginBlob != null) {
      for (final entry in entries) {
        if (entry.op != 'upsert' || !entry.table.startsWith('plugin_')) {
          continue;
        }
        final hash = entry.data?['sha256'] as String?;
        if (hash != null) {
          descriptors.add(
            SyncBlobDescriptor(
              sha256: hash,
              readBytes: () => readPluginBlob(hash),
            ),
          );
        }
      }
    }
    if (descriptors.isEmpty) return;
    final byHash = <String, SyncBlobDescriptor>{
      for (final descriptor in descriptors) descriptor.sha256: descriptor,
    };
    final wantedHashes = byHash.keys.toSet();
    final remoteHashes = <String>{};
    for (final blob in await service.listBlobs(
      limit: limits.maxBlobsPageSize,
    )) {
      if (wantedHashes.contains(blob.sha256)) remoteHashes.add(blob.sha256);
    }
    if (!_isCurrentScope(generation, currentScope)) return;
    for (final descriptor in byHash.values) {
      if (remoteHashes.contains(descriptor.sha256)) continue;
      final bytes = await descriptor.readBytes();
      if (bytes.length > limits.maxBlobBytes) {
        throw StateError(
          'sync blob ${descriptor.sha256} exceeds ${limits.maxBlobBytes} bytes',
        );
      }
      await service.uploadBlob(descriptor.sha256, bytes);
      if (!_isCurrentScope(generation, currentScope)) return;
    }
  }

  List<List<_PreparedUploadEntry>> _uploadBatches(
    List<_PreparedUploadEntry> entries,
    SyncLimits limits,
  ) {
    final batches = <List<_PreparedUploadEntry>>[];
    var current = <_PreparedUploadEntry>[];
    var currentBytes = _emptyUploadBodyBytes;
    for (final entry in entries) {
      final candidateBytes =
          currentBytes + entry.recordBytes + (current.isEmpty ? 0 : 1);
      if (candidateBytes > limits.maxChangesRequestBytes ||
          current.length == limits.maxChangesPerRequest) {
        batches.add(current);
        current = <_PreparedUploadEntry>[];
        currentBytes = _emptyUploadBodyBytes;
      }
      current.add(entry);
      currentBytes += entry.recordBytes + (current.length == 1 ? 0 : 1);
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  int get _emptyUploadBodyBytes => utf8
      .encode(
        jsonEncode({
          'requestId': RemoteSyncService.requestIdForChanges(const []),
          'changes': const [],
        }),
      )
      .length;

  int _singleUploadBodyBytes(int recordBytes) =>
      _emptyUploadBodyBytes + recordBytes;

  _PreparedUploadEntry _prepareUploadEntry(SyncOutboxEntry entry) {
    final record = _recordForEntry(entry);
    return _PreparedUploadEntry(
      entry: entry,
      record: record,
      recordBytes: utf8.encode(jsonEncode(record.toJson())).length,
      dataBytes: entry.data == null
          ? 0
          : utf8.encode(jsonEncode(entry.data)).length,
    );
  }

  void _validateAcknowledgements(
    SyncUploadResult result,
    List<SyncOutboxEntry> entries,
  ) {
    final acknowledgements = result.acknowledgements;
    if (result.legacyWholeBatchAcknowledgement) {
      if (acknowledgements != null) {
        throw StateError('sync server returned mixed legacy and exact ACKs');
      }
      return;
    }
    if (acknowledgements == null) {
      throw StateError('sync server returned a malformed ACK');
    }
    final ackKeys = {
      for (final ack in acknowledgements)
        '${ack.changeId}:${ack.mutationVersion}',
    };
    final expected = {
      for (final entry in entries) '${entry.changeId}:${entry.mutationVersion}',
    };
    if (ackKeys.length != expected.length || !ackKeys.containsAll(expected)) {
      throw StateError('sync server did not ACK the exact uploaded batch');
    }
  }

  String _outboxRowKey(SyncOutboxEntry entry) =>
      '${entry.table}\u0000${entry.recordId}';

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
      int priority(SyncChange change) {
        if (change.table == 'note_page_tombstones') {
          return change.op == 'delete' ? 2 : 6;
        }
        return switch (change.table) {
          'note_folders' => 0,
          'notes' => 1,
          'note_pages' => 3,
          'note_revisions' => 4,
          'note_page_heads' => 5,
          'resources' => 7,
          _ => 10,
        };
      }

      final byTable = priority(a).compareTo(priority(b));
      return byTable != 0 ? byTable : a.seq.compareTo(b.seq);
    });
    return _operations(prepared);
  }

  void _validateRemotePage(int since, SyncDownloadResult page) {
    if (page.nextSince < since) {
      throw StateError('同步分页游标倒退: since=$since nextSince=${page.nextSince}');
    }
    var previousSeq = since;
    final changeIds = <String>{};
    for (final change in page.changes) {
      if (change.seq <= previousSeq) {
        throw StateError('远端 change seq 必须大于 since 且页内严格递增: ${change.seq}');
      }
      if (!changeIds.add(change.changeId)) {
        throw StateError('远端 changeId 页内重复: ${change.changeId}');
      }
      _validateRemoteChange(change);
      previousSeq = change.seq;
    }
    if (page.nextSince < previousSeq) {
      throw StateError(
        '同步分页未前进，nextSince 未覆盖最大 seq: '
        '${page.nextSince} < $previousSeq',
      );
    }
    if (page.hasMore && page.nextSince <= since) {
      throw StateError('同步分页未前进: since=$since nextSince=${page.nextSince}');
    }
  }

  void _validateRemoteChange(SyncChange change) {
    const tables = {
      'resources',
      'conversations',
      'messages',
      'message_attachments',
      'tasks',
      'task_lists',
      'task_list_entries',
      'calendar_events',
      'anniversaries',
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
    if (change.seq <= 0) {
      throw StateError('remote sync seq must be positive');
    }
    if (change.changeId.isEmpty) {
      throw StateError('remote sync changeId is empty');
    }
    if (change.deviceId.isEmpty) {
      throw StateError('remote sync deviceId is empty');
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

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  bool _isCurrentScope(int generation, String scope) =>
      _isCurrent(generation) && _scope == scope;

  void _handleBackendChanged() {
    final scope = _backend?.backendScope ?? '';
    if (scope == _backendScope) return;
    _backendScope = scope;
    _remoteService = null;
    _generation++;
  }

  static const _noteTables = {
    'note_folders',
    'notes',
    'note_pages',
    'note_revisions',
    'note_page_heads',
    'note_page_tombstones',
  };

  @override
  void dispose() {
    _disposed = true;
    _backend?.removeListener(_handleBackendChanged);
    super.dispose();
  }
}
