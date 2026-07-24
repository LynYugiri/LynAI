import 'dart:io';

import '../models/sync_change.dart';
import '../providers/sync_provider.dart';
import 'plugin_sync_validation.dart';
import 'storage_v2_database.dart';
import 'storage_v2_service.dart';

class LanSyncStorage {
  LanSyncStorage({
    required StorageV2Service storage,
    required this.readPluginBlob,
    required this.hasPluginBlob,
    required this.installPluginBlob,
  }) : _storage = storage,
       _syncStorage = StorageV2SyncStorage(storage);

  static const scope = 'lan:v1';

  final StorageV2Service _storage;
  final StorageV2SyncStorage _syncStorage;
  final Future<List<int>> Function(String hash) readPluginBlob;
  final Future<bool> Function(String hash) hasPluginBlob;
  final Future<void> Function(String hash, List<int> bytes) installPluginBlob;

  Future<void> activate(String deviceId) =>
      _storage.activateSyncScope(scope, deviceId: deviceId);

  Future<List<SyncOutboxEntry>> changesForPeer(
    Set<String> acknowledgedChangeIds,
  ) async => (await _storage.loadSyncOutbox(scope))
      .where(
        (entry) =>
            ordinaryLanTables.contains(entry.table) &&
            !acknowledgedChangeIds.contains(entry.changeId),
      )
      .toList(growable: false);

  Future<Map<String, LanSyncBlob>> blobsForChanges(
    List<SyncOutboxEntry> entries,
  ) async {
    final noteHashes = entries
        .where((entry) => entry.table == 'note_revisions')
        .map((entry) => entry.data?['contentHash'] as String?)
        .whereType<String>()
        .toSet();
    final resourceHashes = <String>{};
    final snapshotResourceIds = <String>{};
    final resourceIds = <String>{};
    for (final entry in entries) {
      if (entry.op != 'upsert') continue;
      if (entry.table == 'message_attachments') {
        final id = entry.data?['resourceId'] as String?;
        if (id != null && id.isNotEmpty) resourceIds.add(id);
      } else if (entry.table == 'resources' &&
          _isSyncedResourceRole(entry.data?['role'])) {
        snapshotResourceIds.add(entry.recordId);
        final hash = entry.data?['sha256'] as String?;
        if (entry.data?['missing'] != true && hash != null) {
          resourceHashes.add(hash);
        }
      }
    }
    resourceIds.removeAll(snapshotResourceIds);
    for (final id in resourceIds) {
      final resource = await _storage.findResourceById(id);
      final hash = resource?.sha256Hash;
      if (resource != null &&
          _isSyncedResourceRole(resource.role) &&
          !resource.missing &&
          hash != null) {
        resourceHashes.add(hash);
      }
    }
    final result = <String, LanSyncBlob>{};
    for (final hash in resourceHashes) {
      final file = await _blobFile(hash, 'resource');
      result[hash] = LanSyncBlob(size: await file.length(), kind: 'resource');
    }
    for (final hash in noteHashes) {
      final file = await _blobFile(hash, 'note');
      result[hash] = LanSyncBlob(size: await file.length(), kind: 'note');
    }
    for (final entry in entries.where(
      (entry) => pluginLanTables.contains(entry.table) && entry.op == 'upsert',
    )) {
      final hash = entry.data?['sha256'] as String?;
      if (hash == null || result.containsKey(hash)) continue;
      final size = entry.data?['size'];
      if (size is! int || size < 0) {
        throw StateError('LAN plugin blob is missing its size');
      }
      result[hash] = LanSyncBlob(size: size, kind: 'plugin');
    }
    return result;
  }

  Future<Set<String>> expectedBlobHashes(List<SyncChange> changes) async {
    final hashes = <String>{};
    final resourceIds = <String>{};
    for (final change in changes) {
      if (change.op != 'upsert') continue;
      final contentHash = change.data?['contentHash'] as String?;
      final hash = change.data?['sha256'] as String?;
      final resourceId = change.data?['resourceId'] as String?;
      if (contentHash != null) hashes.add(contentHash);
      if (hash != null) hashes.add(hash);
      if (resourceId != null && resourceId.isNotEmpty) {
        resourceIds.add(resourceId);
      }
    }
    for (final resource in await _storage.findResourcesByIds(resourceIds)) {
      final hash = resource.sha256Hash;
      if (_isSyncedResourceRole(resource.role) &&
          !resource.missing &&
          hash != null) {
        hashes.add(hash);
      }
    }
    return hashes;
  }

  Stream<List<int>> readBlobChunks(
    String hash,
    LanSyncBlob blob,
    int chunkBytes,
  ) async* {
    if (chunkBytes <= 0) throw ArgumentError.value(chunkBytes, 'chunkBytes');
    if (blob.kind == 'plugin') {
      final bytes = await readPluginBlob(hash);
      for (var offset = 0; offset < bytes.length; offset += chunkBytes) {
        final end = offset + chunkBytes < bytes.length
            ? offset + chunkBytes
            : bytes.length;
        yield bytes.getRange(offset, end).toList(growable: false);
      }
      return;
    }
    final file = await _blobFile(hash, blob.kind);
    final input = await file.open();
    try {
      while (true) {
        final chunk = await input.read(chunkBytes);
        if (chunk.isEmpty) break;
        yield chunk;
      }
    } finally {
      await input.close();
    }
  }

  Future<bool> hasBlob(String hash, String kind) => switch (kind) {
    'note' => _syncStorage.hasNoteBlob(hash),
    'plugin' => hasPluginBlob(hash),
    _ => _syncStorage.hasResourceBlob(hash),
  };

  Future<void> installBlob(String hash, String kind, List<int> bytes) =>
      switch (kind) {
        'note' => _syncStorage.installNoteBlob(hash, bytes),
        'plugin' => installPluginBlob(hash, bytes),
        _ => _syncStorage.installResourceBlob(hash, bytes),
      };

  Future<File> _blobFile(String hash, String kind) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw ArgumentError('Invalid LAN blob SHA-256: $hash');
    }
    final root = await _storage.storageRoot();
    final directory = kind == 'note' ? 'notes/blobs' : 'assets/blobs';
    return File('${root.path}/$directory/${hash.substring(0, 2)}/$hash');
  }

  static bool _isSyncedResourceRole(Object? role) =>
      role == 'message_attachment' ||
      role == 'message_image' ||
      role == 'background';

  Future<void> apply(List<SyncChange> changes) async {
    final normalized = <SyncRemoteOperation>[];
    for (final change in changes) {
      validatePluginSyncChange(change);
      var data = change.op == 'delete'
          ? <String, dynamic>{'id': change.recordId}
          : change.data;
      if (change.table == 'resources' && data != null) {
        data = _syncStorage.normalizeRemoteResource(data);
      }
      normalized.add((
        table: change.table,
        op: change.op,
        data: data,
        change: change,
      ));
    }
    await _storage.applyRemoteChanges(
      scope,
      normalized,
      0,
      appliedSource: 'lan',
    );
    if (changes.any((change) => _noteTables.contains(change.table))) {
      await _storage.recoverNoteMaterialization();
    }
  }

  static const ordinaryLanTables = <String>{
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
    ...pluginLanTables,
  };

  static const pluginLanTables = <String>{
    'plugin_files',
    'plugin_settings',
    'plugin_config',
  };

  static const _noteTables = <String>{
    'note_folders',
    'notes',
    'note_pages',
    'note_revisions',
    'note_page_heads',
    'note_page_tombstones',
  };
}

class LanSyncBlob {
  const LanSyncBlob({required this.size, required this.kind});

  final int size;
  final String kind;
}
