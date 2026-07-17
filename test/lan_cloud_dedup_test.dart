import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/sync_change.dart';
import 'package:lynai/providers/sync_provider.dart';
import 'package:lynai/repositories/lan_peer_repository.dart';
import 'package:lynai/services/secret_store.dart';
import 'package:lynai/services/storage_v2_database.dart';
import 'package:lynai/services/sync_service.dart';

void main() {
  test(
    'duplicate change delivered by LAN then cloud is applied once',
    () async {
      final dedup = LanPeerRepository(secretStore: InMemorySecretStore());
      expect(await dedup.markChangeApplied('shared-change'), isTrue);
      final storage = MemorySyncStorage();
      final service = _OneChangeService();
      final provider = SyncProvider(
        service: service,
        storage: storage,
        shouldApplyRemoteChange: (changeId) async =>
            !await dedup.hasAppliedChange(changeId),
      );
      await provider.bindScope('user-a');
      await provider.manualSync();
      expect(storage.appliedRemoteOperations, isEmpty);
    },
  );
}

class MemorySyncStorage implements SyncStorage {
  final List<SyncRemoteOperation> appliedRemoteOperations = [];
  int _since = 0;

  @override
  Future<void> activateScope(String scope, String deviceId) async {}
  @override
  Future<void> deactivateScope(String scope) async {}
  @override
  Future<int> since(String scope) async => _since;
  @override
  Future<List<SyncOutboxEntry>> loadOutbox(String scope) async => const [];
  @override
  Future<List<SyncConflictEntry>> loadConflicts(String scope) async => const [];
  @override
  Future<void> resolveConflict(
    String scope,
    int seq,
    SyncConflictResolution resolution,
  ) async {}
  @override
  Future<bool> acknowledgeOutbox(
    String scope,
    List<SyncOutboxEntry> entries,
  ) async => false;
  @override
  Future<void> applyRemoteChanges(
    String scope,
    List<SyncRemoteOperation> ops,
    int nextSince,
  ) async {
    appliedRemoteOperations.addAll(ops);
    _since = nextSince;
  }

  @override
  Future<void> updateSince(String scope, int since) async => _since = since;
  @override
  Future<List<SyncResourceBlob>> resourceBlobsForOutbox(
    List<SyncOutboxEntry> entries,
  ) async => const [];
  @override
  Future<bool> hasResourceBlob(String sha256) async => true;
  @override
  Future<void> installResourceBlob(String sha256, List<int> bytes) async {}
  @override
  Map<String, dynamic> normalizeRemoteResource(Map<String, dynamic> data) =>
      data;
  @override
  Future<bool> hasNoteBlob(String sha256) async => true;
  @override
  Future<void> installNoteBlob(String sha256, List<int> bytes) async {}
}

class _OneChangeService implements SyncService {
  @override
  Future<SyncDownloadResult> getChanges({
    required int since,
    int limit = 500,
  }) async {
    return SyncDownloadResult(
      changes: [
        SyncChange(
          seq: 1,
          changeId: 'shared-change',
          deviceId: 'peer',
          clientCreatedAt: DateTime.utc(2030),
          table: 'todo_lists',
          op: 'upsert',
          recordId: 'list-a',
          data: {
            'id': 'list-a',
            'title': 'A',
            'createdAt': DateTime.utc(2030).toIso8601String(),
            'updatedAt': DateTime.utc(2030).toIso8601String(),
          },
        ),
      ],
      latestSeq: 1,
      hasMore: false,
      nextSince: 1,
    );
  }

  @override
  Future<SyncStatus> getStatus() async =>
      const SyncStatus(lastSeq: 1, blobCount: 0);
  @override
  Future<List<BlobInfo>> listBlobs({int limit = 1000}) async => const [];
  @override
  Future<SyncUploadResult> uploadChanges(
    List<SyncChangeRecord> changes,
  ) async => const SyncUploadResult(latestSeq: 1);
  @override
  Future<void> uploadBlob(String sha256, List<int> bytes) async {}
  @override
  Future<List<int>> downloadBlob(String sha256) async => const [];
}
