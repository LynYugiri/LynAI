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
    final result = <String, LanSyncBlob>{
      for (final blob in await _syncStorage.resourceBlobsForOutbox(entries))
        blob.sha256: LanSyncBlob(
          bytes: blob.bytes,
          kind: noteHashes.contains(blob.sha256) ? 'note' : 'resource',
        ),
    };
    for (final entry in entries.where(
      (entry) => pluginLanTables.contains(entry.table) && entry.op == 'upsert',
    )) {
      final hash = entry.data?['sha256'] as String?;
      if (hash == null || result.containsKey(hash)) continue;
      result[hash] = LanSyncBlob(
        bytes: await readPluginBlob(hash),
        kind: 'plugin',
      );
    }
    return result;
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
  }

  static const ordinaryLanTables = <String>{
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
    ...pluginLanTables,
  };

  static const pluginLanTables = <String>{
    'plugin_files',
    'plugin_settings',
    'plugin_config',
  };
}

class LanSyncBlob {
  const LanSyncBlob({required this.bytes, required this.kind});

  final List<int> bytes;
  final String kind;
}
