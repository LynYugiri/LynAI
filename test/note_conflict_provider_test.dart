import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/merge_models.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/services/storage_v2_service.dart';

void main() {
  late Directory root;
  late StorageV2Service storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lynai_note_conflict_');
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
    'loaded content-hash revision remains readable after normalization',
    () async {
      final provider = FeatureProvider(storageV2: storage);
      await provider.load();
      final noteId = await provider.addNoteWithContent('note', 'blob body');
      final revisionId = provider.getNote(noteId)!.currentRevisionId!;

      final reloaded = FeatureProvider(storageV2: storage);
      await reloaded.load();

      expect(
        reloaded.getNoteContentAtRevision(noteId, revisionId),
        'blob body',
      );
    },
  );

  test('missing content-hash blob is explicit instead of empty text', () async {
    await _writeConflictData(storage, missingIncomingBlob: true);
    final provider = FeatureProvider(storageV2: storage);

    await provider.load();

    expect(provider.getNote('n'), isNotNull);
    expect(
      () => provider.getNoteContentAtRevision('n', 'incoming'),
      throwsA(isA<StateError>()),
    );
  });

  test('conflict sides persist and merge commit is stale-head safe', () async {
    await _writeConflictData(storage);
    var provider = FeatureProvider(storageV2: storage);
    await provider.load();
    final conflict = provider.notePageConflict('p')!;
    final session = provider.loadNotePageMergeSession('n', 'p')!;

    expect(conflict.localHeadId, session.localHeadId);
    expect(conflict.incomingHeadId, session.incomingHeadId);
    await provider.flushPendingSaves();

    provider = FeatureProvider(storageV2: storage);
    await provider.load();
    final persisted = provider.notePageConflict('p')!;
    expect(persisted.localHeadId, conflict.localHeadId);
    expect(persisted.incomingHeadId, conflict.incomingHeadId);

    final stale = NotePageMergeSession(
      noteId: session.noteId,
      pageId: session.pageId,
      expectedHeadIds: {...session.expectedHeadIds, 'new-head'},
      localHeadId: session.localHeadId,
      incomingHeadId: session.incomingHeadId,
      baseRevisionId: session.baseRevisionId,
      localContent: session.localContent,
      incomingContent: session.incomingContent,
      baseContent: session.baseContent,
      initialResult: session.initialResult,
    );
    expect(
      (await provider.commitNotePageMerge(stale, 'merged')).status,
      NotePageMergeCommitStatus.staleHeads,
    );

    final result = await provider.commitNotePageMerge(
      provider.loadNotePageMergeSession('n', 'p')!,
      'resolved',
    );
    expect(result.status, NotePageMergeCommitStatus.committed);
    final revision = provider.getNoteRevision(result.revisionId!)!;
    expect(revision.parentIds, [conflict.localHeadId, conflict.incomingHeadId]);
    expect(provider.getNote('n')!.content, 'resolved');
  });

  test(
    'more than two heads remain reachable through pairwise merges',
    () async {
      await _writeConflictData(storage, includeThirdHead: true);
      final provider = FeatureProvider(storageV2: storage);
      await provider.load();
      final session = provider.loadNotePageMergeSession('n', 'p')!;

      await provider.commitNotePageMerge(session, 'resolved pair');

      final reachable = <String>{};
      final pending = provider.notePageHeads('p')!.headIds.toList();
      while (pending.isNotEmpty) {
        final id = pending.removeLast();
        if (!reachable.add(id)) continue;
        pending.addAll(provider.getNoteRevision(id)?.parentIds ?? const []);
      }
      expect(reachable, containsAll(<String>['local', 'incoming', 'third']));
    },
  );
}

Future<void> _writeConflictData(
  StorageV2Service storage, {
  bool missingIncomingBlob = false,
  bool includeThirdHead = false,
}) async {
  final baseHash = await storage.storeNoteBlob('base');
  final localHash = await storage.storeNoteBlob('local');
  final incomingHash = missingIncomingBlob
      ? 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      : await storage.storeNoteBlob('incoming');
  final thirdHash = includeThirdHead
      ? await storage.storeNoteBlob('third')
      : null;
  final now = DateTime.utc(2026, 7, 17).toIso8601String();
  final heads = ['local', 'incoming', if (includeThirdHead) 'third'];
  await storage.writeNotesData({
    'folders': const [],
    'notes': [
      {
        'id': 'n',
        'title': 'Note',
        'currentPageId': 'p',
        'currentRevisionId': 'local',
        'createdAt': now,
        'updatedAt': now,
        'wrap': true,
        'sortOrder': 0,
      },
    ],
    'pages': [
      {
        'id': 'p',
        'noteId': 'n',
        'title': 'Page',
        'fileName': 'page.md',
        'relativePath': 'notes/n/page.md',
        'currentRevisionId': 'local',
        'sortOrder': 0,
        'createdAt': now,
        'updatedAt': now,
      },
    ],
    'revisions': [
      _revision('base', baseHash, const [], now),
      _revision('local', localHash, const ['base'], now),
      _revision('incoming', incomingHash, const ['base'], now),
      if (includeThirdHead) _revision('third', thirdHash!, const ['base'], now),
    ],
    'pageHeads': [
      {
        'id': 'p',
        'pageId': 'p',
        'headIds': heads,
        'selectedHeadId': 'local',
        'updatedAt': now,
      },
    ],
    'pageTombstones': const [],
    'pageConflicts': const [],
    'editProposals': const [],
    'editBlocks': const [],
  });
  final page = StorageV2NotePage(
    id: 'p',
    noteId: 'n',
    title: 'Page',
    fileName: 'page.md',
    relativePath: 'notes/n/page.md',
    currentRevisionId: 'local',
    sortOrder: 0,
    createdAt: DateTime.parse(now),
    updatedAt: DateTime.parse(now),
  );
  await storage.writeNotePage(page, 'local');
}

Map<String, dynamic> _revision(
  String id,
  String hash,
  List<String> parents,
  String createdAt,
) => {
  'id': id,
  'noteId': 'n',
  'pageId': 'p',
  'parentIds': parents,
  'authorDeviceId': 'device',
  'contentHash': hash,
  'createdAt': createdAt,
};
