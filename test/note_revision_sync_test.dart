import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/sync_change.dart';
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

SyncRemoteOperation _remote(
  String table,
  String id,
  Map<String, dynamic> data,
) => (
  table: table,
  op: 'upsert',
  data: data,
  change: SyncChange(
    seq: 1,
    changeId: sha256
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
