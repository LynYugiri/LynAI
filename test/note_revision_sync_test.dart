import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/sync_change.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/services/storage_v2_database.dart';
import 'package:lynai/services/storage_v2_service.dart';

void main() {
  late Directory root;
  late StorageV2Service storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lynai_note_dag_');
    storage = StorageV2Service(rootDirectory: root);
    await Directory('${root.path}/storage_v2').create(recursive: true);
    await storage.writeManifest({
      'type': 'lynai.storage_v2',
      'schemaVersion': StorageV2Service.currentLayoutVersion,
    });
  });

  tearDown(() async {
    await storage.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'duplicate immutable revision is idempotent and collision fails',
    () async {
      final database = await storage.storageDatabase();
      final content = 'hello';
      final hash = await storage.storeNoteBlob(content);
      final base = [
        _remote('notes', 'n', _note()),
        _remote('note_pages', 'p', _page()),
        _remote('note_revisions', 'r', _revision(hash)),
      ];
      await database.batchIncremental(
        base,
        remote: true,
        scope: 's',
        nextSince: 1,
      );
      await database.batchIncremental(
        [_remote('note_revisions', 'r', _revision(hash))],
        remote: true,
        scope: 's',
        nextSince: 2,
      );
      await expectLater(
        database.batchIncremental(
          [
            _remote(
              'note_revisions',
              'r',
              _revision(List.filled(64, 'b').join()),
            ),
          ],
          remote: true,
          scope: 's',
          nextSince: 3,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'head union fast-forwards descendants and materialization recovers',
    () async {
      final database = await storage.storageDatabase();
      final oneHash = await storage.storeNoteBlob('one');
      final twoHash = await storage.storeNoteBlob('two');
      await database.batchIncremental(
        [
          _remote('notes', 'n', _note()),
          _remote('note_pages', 'p', _page()),
          _remote('note_revisions', 'r1', _revision(oneHash, id: 'r1')),
          _remote(
            'note_revisions',
            'r2',
            _revision(twoHash, id: 'r2', parents: ['r1']),
          ),
          _remote('note_page_heads', 'p', {
            'id': 'p',
            'pageId': 'p',
            'headIds': ['r1'],
            'selectedHeadId': 'r1',
          }),
          _remote('note_page_heads', 'p', {
            'id': 'p',
            'pageId': 'p',
            'headIds': ['r2'],
            'selectedHeadId': 'r2',
          }),
        ],
        remote: true,
        scope: 's',
        nextSince: 1,
      );
      final pageFile = File('${root.path}/storage_v2/notes/n/page.md');
      await pageFile.parent.create(recursive: true);
      await pageFile.writeAsString('damaged', flush: true);

      await storage.recoverNoteMaterialization();

      final data = await storage.loadNotesData();
      expect((data['pageHeads'] as List).single['headIds'], ['r2']);
      expect(await pageFile.readAsString(), 'two');
    },
  );

  test(
    'revision then tombstone removes revision, heads, and conflict',
    () async {
      final database = await storage.storageDatabase();
      final hash = await storage.storeNoteBlob('one');
      await database.batchIncremental(
        [
          _remote('notes', 'n', _note()),
          _remote('note_pages', 'p', _page()),
          _remote('note_revisions', 'r', _revision(hash)),
          _remote('note_page_heads', 'p', {
            'id': 'p',
            'pageId': 'p',
            'headIds': ['r'],
            'selectedHeadId': 'r',
          }),
        ],
        remote: true,
        scope: 's',
        nextSince: 1,
      );
      await storage.writeNotesData({
        ...await storage.loadNotesData(),
        'pageConflicts': [
          {
            'pageId': 'p',
            'headIds': ['r', 'other'],
            'localHeadId': 'r',
            'incomingHeadId': 'other',
            'createdAt': '2026-07-16T00:00:00.000Z',
          },
        ],
      });

      await database.batchIncremental(
        [_remote('note_page_tombstones', 'p:r', _tombstone('r'))],
        remote: true,
        scope: 's',
        nextSince: 2,
      );

      final data = await storage.loadNotesData();
      expect(data['revisions'], isEmpty);
      expect(data['pageHeads'], isEmpty);
      expect(data['pageConflicts'], isEmpty);
    },
  );

  test('tombstone then revision does not resurrect revision', () async {
    final database = await storage.storageDatabase();
    final hash = await storage.storeNoteBlob('one');
    await database.batchIncremental(
      [
        _remote('notes', 'n', _note()),
        _remote('note_pages', 'p', _page()),
        _remote('note_page_tombstones', 'p:r', _tombstone('r')),
      ],
      remote: true,
      scope: 's',
      nextSince: 1,
    );

    await database.batchIncremental(
      [
        _remote('note_revisions', 'r', _revision(hash)),
        _remote('note_page_heads', 'p', {
          'id': 'p',
          'pageId': 'p',
          'headIds': ['r'],
          'selectedHeadId': 'r',
        }),
      ],
      remote: true,
      scope: 's',
      nextSince: 2,
    );

    final data = await storage.loadNotesData();
    expect(data['revisions'], isEmpty);
    expect(data['pageHeads'], isEmpty);
  });

  test(
    'page tombstone suppresses known and later concurrent revisions',
    () async {
      final database = await storage.storageDatabase();
      final oneHash = await storage.storeNoteBlob('one');
      final twoHash = await storage.storeNoteBlob('two');
      await database.batchIncremental(
        [
          _remote('notes', 'n', _note()),
          _remote('note_pages', 'p', _page()),
          _remote('note_revisions', 'r1', _revision(oneHash, id: 'r1')),
          _remote('note_page_tombstones', 'p:*', _tombstone('*')),
        ],
        remote: true,
        scope: 's',
        nextSince: 1,
      );

      await database.batchIncremental(
        [
          _remote('note_revisions', 'r2', _revision(twoHash, id: 'r2')),
          _remote('note_page_heads', 'p', {
            'id': 'p',
            'pageId': 'p',
            'headIds': ['r2'],
            'selectedHeadId': 'r2',
          }),
        ],
        remote: true,
        scope: 's',
        nextSince: 2,
      );

      final data = await storage.loadNotesData();
      expect(data['revisions'], isEmpty);
      expect(data['pageHeads'], isEmpty);
    },
  );

  test(
    'revision branch deletion creates tombstones that block peer revival',
    () async {
      const scope = 'server|note-revision-test';
      final peerRoot = await Directory.systemTemp.createTemp(
        'lynai_note_dag_peer_',
      );
      final peer = await _readyStorage(peerRoot);
      try {
        final provider = FeatureProvider(storageV2: storage);
        await provider.load();
        final noteId = await provider.addNoteWithContent('Note', 'root');
        final rootId = provider.getNote(noteId)!.currentRevisionId!;
        final main = await provider.saveNoteContent(noteId, 'main');
        final branch = await provider.restoreNoteRevision(noteId, rootId);
        final branchChild = await provider.saveNoteContent(
          noteId,
          'branch child',
        );
        await provider.restoreNoteRevision(noteId, main!.id);

        await storage.activateSyncScope(scope, deviceId: 'device-a');
        await _syncOutbox(storage, peer, scope);

        expect(
          await provider.deleteNoteBranchesFromRevision(noteId, rootId),
          2,
        );
        final deletion = await storage.loadSyncOutbox(scope);
        final tombstoneIds = deletion
            .where(
              (entry) =>
                  entry.table == 'note_page_tombstones' && entry.op == 'upsert',
            )
            .map((entry) => entry.recordId)
            .toSet();
        final pageId = provider.activeNotePage(noteId)!.id;
        expect(tombstoneIds, {
          '$pageId:${branch!.id}',
          '$pageId:${branchChild!.id}',
        });
        await _syncOutbox(storage, peer, scope);

        var peerData = await peer.loadNotesData();
        expect(
          (peerData['revisions'] as List).map((item) => item['id']),
          isNot(contains(branch.id)),
        );
        expect(
          (peerData['revisions'] as List).map((item) => item['id']),
          isNot(contains(branchChild.id)),
        );

        final staleBranch = branch.toJson();
        await peer.applyRemoteChanges(scope, [
          _remote(
            'note_revisions',
            branch.id,
            staleBranch,
            seq: 100,
            changeId: 'stale-${branch.id}',
          ),
        ], 100);
        peerData = await peer.loadNotesData();
        expect(
          (peerData['revisions'] as List).map((item) => item['id']),
          isNot(contains(branch.id)),
        );
      } finally {
        await peer.close();
        if (await peerRoot.exists()) await peerRoot.delete(recursive: true);
      }
    },
  );

  test(
    'page restore deletes tombstones before restoring peer revision and head',
    () async {
      const scope = 'server|note-page-restore-test';
      final peerRoot = await Directory.systemTemp.createTemp(
        'lynai_note_restore_peer_',
      );
      final peer = await _readyStorage(peerRoot);
      try {
        final provider = FeatureProvider(storageV2: storage);
        await provider.load();
        final noteId = await provider.addNoteWithContent('Note', 'first');
        final restoredPageId = (await provider.addNotePage(noteId, 'second'))!;
        final restoredRevision = await provider.saveNoteContent(
          noteId,
          'second page',
        );
        final restoredPage = provider.activeNotePage(noteId)!;
        final restorePayload = <String, dynamic>{
          'page': restoredPage.toJson(),
          'content': 'second page',
          'revisions': [restoredRevision!.toJson()],
          'editProposals': const [],
        };

        await storage.activateSyncScope(scope, deviceId: 'device-a');
        await _syncOutbox(storage, peer, scope);
        expect(await provider.deleteNotePage(noteId, restoredPageId), isTrue);
        await _syncOutbox(storage, peer, scope);

        var peerData = await peer.loadNotesData();
        expect(
          (peerData['pageTombstones'] as List).map((item) => item['id']),
          contains('$restoredPageId:*'),
        );
        expect(
          (peerData['revisions'] as List).map((item) => item['id']),
          isNot(contains(restoredRevision.id)),
        );

        await provider.restoreNotePagePayload(restorePayload);
        final restoreEntries = await storage.loadSyncOutbox(scope);
        final tombstoneDeletes = restoreEntries
            .where(
              (entry) =>
                  entry.table == 'note_page_tombstones' && entry.op == 'delete',
            )
            .toList();
        expect(
          tombstoneDeletes.map((entry) => entry.recordId),
          contains('$restoredPageId:*'),
        );
        final firstRevisionOrHead = restoreEntries.indexWhere(
          (entry) =>
              entry.table == 'note_revisions' ||
              entry.table == 'note_page_heads',
        );
        expect(firstRevisionOrHead, greaterThan(tombstoneDeletes.length - 1));
        expect(
          restoreEntries
              .take(firstRevisionOrHead)
              .where((entry) => entry.table == 'note_page_tombstones')
              .every((entry) => entry.op == 'delete'),
          isTrue,
        );

        await _syncOutbox(storage, peer, scope, reverseApplyOrder: true);
        peerData = await peer.loadNotesData();
        expect(
          (peerData['pageTombstones'] as List).map((item) => item['id']),
          isNot(contains('$restoredPageId:*')),
        );
        expect(
          (peerData['revisions'] as List).map((item) => item['id']),
          contains(restoredRevision.id),
        );
        final restoredHead = (peerData['pageHeads'] as List).singleWhere(
          (item) => item['pageId'] == restoredPageId,
        );
        expect(restoredHead['headIds'], contains(restoredRevision.id));
        expect(restoredHead['selectedHeadId'], restoredRevision.id);
      } finally {
        await peer.close();
        if (await peerRoot.exists()) await peerRoot.delete(recursive: true);
      }
    },
  );
}

Future<StorageV2Service> _readyStorage(Directory root) async {
  final storage = StorageV2Service(rootDirectory: root);
  await Directory('${root.path}/storage_v2').create(recursive: true);
  await storage.writeManifest({
    'type': 'lynai.storage_v2',
    'schemaVersion': StorageV2Service.currentLayoutVersion,
  });
  return storage;
}

Future<void> _syncOutbox(
  StorageV2Service source,
  StorageV2Service target,
  String scope, {
  bool reverseApplyOrder = false,
}) async {
  final entries = await source.loadSyncOutbox(scope);
  if (entries.isEmpty) return;
  final operations = entries.indexed.map((entry) {
    final value = entry.$2;
    return (
      table: value.table,
      op: value.op,
      data: value.op == 'delete'
          ? <String, dynamic>{'id': value.recordId}
          : value.data,
      change: SyncChange(
        seq: entry.$1 + 1,
        changeId: value.changeId,
        deviceId: value.deviceId,
        clientCreatedAt: value.clientCreatedAt,
        table: value.table,
        op: value.op,
        recordId: value.recordId,
        data: value.data,
      ),
    );
  }).toList();
  await target.applyRemoteChanges(
    scope,
    reverseApplyOrder ? operations.reversed.toList() : operations,
    0,
  );
  await source.acknowledgeSyncOutbox(scope, entries);
}

Map<String, dynamic> _note() => {
  'id': 'n',
  'title': 'Note',
  'currentPageId': 'p',
  'createdAt': '2026-07-16T00:00:00.000Z',
  'updatedAt': '2026-07-16T00:00:00.000Z',
  'wrap': true,
  'sortOrder': 0,
};

Map<String, dynamic> _page() => {
  'id': 'p',
  'noteId': 'n',
  'title': 'Page',
  'fileName': 'page.md',
  'relativePath': 'notes/n/page.md',
  'sortOrder': 0,
  'createdAt': '2026-07-16T00:00:00.000Z',
  'updatedAt': '2026-07-16T00:00:00.000Z',
};

Map<String, dynamic> _revision(
  String hash, {
  String id = 'r',
  List<String> parents = const [],
}) => {
  'id': id,
  'noteId': 'n',
  'pageId': 'p',
  'parentIds': parents,
  'authorDeviceId': 'device',
  'contentHash': hash,
  'createdAt': '2026-07-16T00:00:00.000Z',
};

Map<String, dynamic> _tombstone(String revisionId) => {
  'id': 'p:$revisionId',
  'pageId': 'p',
  'revisionId': revisionId,
  'createdAt': '2026-07-16T00:00:00.000Z',
};

SyncRemoteOperation _remote(
  String table,
  String id,
  Map<String, dynamic> data, {
  int seq = 1,
  String? changeId,
}) => (
  table: table,
  op: 'upsert',
  data: data,
  change: SyncChange(
    seq: seq,
    changeId:
        changeId ??
        sha256
            .convert(utf8.encode('$table:$id:${jsonEncode(data)}'))
            .toString(),
    deviceId: 'device',
    clientCreatedAt: DateTime.utc(2026, 7, 16),
    table: table,
    op: 'upsert',
    recordId: id,
    data: data,
  ),
);
