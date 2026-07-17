import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/models/roleplay.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/roleplay_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/repositories/conversation_repository.dart';
import 'package:lynai/repositories/feature_repository.dart';
import 'package:lynai/repositories/model_config_repository.dart';
import 'package:lynai/repositories/roleplay_repository.dart';
import 'package:lynai/repositories/settings_repository.dart';
import 'package:lynai/services/storage_v2_service.dart';

void main() {
  test(
    'top-level load failures preserve provider memory and propagate',
    () async {
      final conversationRepository = _ConversationRepository();
      final conversations = ConversationProvider(
        repository: conversationRepository,
      );
      conversations.createConversation(ConversationSettings(modelId: 'model'));
      final conversationCount = conversations.conversations.length;
      conversationRepository.failLoad = true;
      await expectLater(conversations.loadConversations(), throwsStateError);
      expect(conversations.conversations, hasLength(conversationCount));

      final settingsRepository = _SettingsRepository();
      final settings = SettingsProvider(repository: settingsRepository);
      settings.setLastFeature('notes');
      settingsRepository.failLoad = true;
      await expectLater(settings.loadSettings(), throwsStateError);
      expect(settings.settings.lastFeature, 'notes');

      final modelRepository = _ModelRepository();
      final models = ModelConfigProvider(repository: modelRepository);
      models.addModel(_model('model'));
      modelRepository.failLoad = true;
      await expectLater(models.loadModels(), throwsStateError);
      expect(models.models.single.id, 'model');

      final roleplayRepository = _RoleplayRepository();
      final roleplay = RoleplayProvider(repository: roleplayRepository);
      roleplay.createScenario(
        title: 'scenario',
        scenario: 'body',
        director: const RoleplayDirector(),
        defaultPlayer: const RoleplayParticipant(
          id: 'player',
          name: 'Player',
          systemPrompt: '',
        ),
        defaultParticipants: const [],
      );
      roleplayRepository.failLoad = true;
      await expectLater(roleplay.loadSessions(), throwsStateError);
      expect(roleplay.scenarios.single.title, 'scenario');

      final featureRepository = _FeatureRepository();
      final features = FeatureProvider(repository: featureRepository);
      await features.addTodoList('todo');
      featureRepository.failLoad = true;
      await expectLater(features.load(), throwsStateError);
      expect(features.todoLists.single.title, 'todo');
    },
  );

  test('failed saves are observable without poisoning later saves', () async {
    final settingsRepository = _SettingsRepository()..remainingSaveFailures = 1;
    final settings = SettingsProvider(repository: settingsRepository);

    settings.setLastFeature('first');
    await expectLater(settings.flushPendingSaves(), throwsStateError);

    settings.setLastFeature('second');
    await settings.flushPendingSaves();
    expect(settingsRepository.savedSettings?.lastFeature, 'second');
  });

  test('feature flush waits for the real notes metadata write', () async {
    final repository = _FeatureRepository();
    final provider = FeatureProvider(repository: repository);
    await provider.load();

    final write = provider.addNoteWithContent('note', 'body');
    await repository.saveStarted.future;
    var flushed = false;
    final flush = provider.flushPendingSaves().then((_) => flushed = true);
    await Future<void>.delayed(Duration.zero);
    expect(flushed, isFalse);

    repository.allowSave.complete();
    await write;
    await flush;
    expect(flushed, isTrue);
  });

  test('existing page tombstones survive ordinary feature saves', () async {
    final root = await Directory.systemTemp.createTemp('lynai_tombstones_');
    final storage = StorageV2Service(rootDirectory: root);
    try {
      await Directory('${root.path}/storage_v2').create(recursive: true);
      await storage.writeManifest({
        'type': 'lynai.storage_v2',
        'schemaVersion': StorageV2Service.currentLayoutVersion,
      });
      final now = DateTime.utc(2026, 7, 17).toIso8601String();
      await storage.writeNotesData({
        'folders': const [],
        'notes': const [],
        'pages': const [],
        'revisions': const [],
        'pageHeads': const [],
        'pageTombstones': [
          {
            'id': 'page:revision',
            'pageId': 'page',
            'revisionId': 'revision',
            'createdAt': now,
          },
        ],
        'pageConflicts': const [],
        'editProposals': const [],
        'editBlocks': const [],
      });

      final provider = FeatureProvider(storageV2: storage);
      await provider.load();
      await provider.addNoteWithContent('note', 'body');
      await provider.flushPendingSaves();

      final data = await storage.loadNotesData();
      expect(
        data['pageTombstones'],
        contains(containsPair('id', 'page:revision')),
      );
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test(
    'feature load hides tombstoned revisions, heads, and conflicts',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_tombstone_load_',
      );
      final storage = StorageV2Service(rootDirectory: root);
      try {
        await Directory(
          '${root.path}/storage_v2/notes/n',
        ).create(recursive: true);
        await storage.writeManifest({
          'type': 'lynai.storage_v2',
          'schemaVersion': StorageV2Service.currentLayoutVersion,
        });
        await File(
          '${root.path}/storage_v2/notes/n/page.md',
        ).writeAsString('body');
        const createdAt = '2026-07-17T00:00:00.000Z';
        await storage.writeNotesData({
          'folders': const [],
          'notes': const [
            {
              'id': 'n',
              'title': 'Note',
              'currentPageId': 'p',
              'currentRevisionId': 'r',
              'createdAt': createdAt,
              'updatedAt': createdAt,
              'wrap': true,
            },
          ],
          'pages': const [
            {
              'id': 'p',
              'noteId': 'n',
              'title': 'Page',
              'fileName': 'page.md',
              'relativePath': 'notes/n/page.md',
              'currentRevisionId': 'r',
              'createdAt': createdAt,
              'updatedAt': createdAt,
            },
          ],
          'revisions': const [
            {
              'id': 'r',
              'noteId': 'n',
              'pageId': 'p',
              'parentIds': [],
              'authorDeviceId': 'device',
              'contentHash': '',
              'createdAt': createdAt,
            },
          ],
          'pageHeads': const [
            {
              'id': 'p',
              'pageId': 'p',
              'headIds': ['r', 'other'],
              'selectedHeadId': 'r',
            },
          ],
          'pageTombstones': const [
            {
              'id': 'p:r',
              'pageId': 'p',
              'revisionId': 'r',
              'createdAt': createdAt,
            },
          ],
          'pageConflicts': const [
            {
              'pageId': 'p',
              'headIds': ['r', 'other'],
              'localHeadId': 'r',
              'incomingHeadId': 'other',
              'createdAt': createdAt,
            },
          ],
          'editProposals': const [],
          'editBlocks': const [],
        });

        final provider = FeatureProvider(storageV2: storage);
        await provider.load();

        expect(provider.noteRevisions, isEmpty);
        expect(provider.notePageHeads('p'), isNull);
        expect(provider.notePageConflict('p'), isNull);
      } finally {
        await storage.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );
}

ModelConfig _model(String id) => ModelConfig(
  id: id,
  name: id,
  endpoint: 'https://example.com',
  apiKey: '',
  modelName: 'test',
  apiType: 'openai',
  priority: 0,
);

class _ConversationRepository implements ConversationRepository {
  bool failLoad = false;

  @override
  Future<ConversationLoadResult> load() async {
    if (failLoad) throw StateError('load failed');
    return const ConversationLoadResult(
      conversations: [],
      usingStorageV2: true,
    );
  }

  @override
  Future<void> save(
    List<Conversation> conversations, {
    required bool usingStorageV2,
  }) async {}
}

class _SettingsRepository implements SettingsRepository {
  bool failLoad = false;
  int remainingSaveFailures = 0;
  AppSettings? savedSettings;

  @override
  Future<SettingsLoadResult> load(AppSettings fallback) async {
    if (failLoad) throw StateError('load failed');
    return SettingsLoadResult(settings: fallback, usingStorageV2: true);
  }

  @override
  Future<void> save(
    AppSettings settings, {
    required bool usingStorageV2,
  }) async {
    if (remainingSaveFailures > 0) {
      remainingSaveFailures--;
      throw StateError('save failed');
    }
    savedSettings = settings;
  }
}

class _ModelRepository implements ModelConfigRepository {
  bool failLoad = false;

  @override
  Future<ModelConfigLoadResult> load() async {
    if (failLoad) throw StateError('load failed');
    return const ModelConfigLoadResult(models: [], usingStorageV2: true);
  }

  @override
  Future<void> save(
    List<ModelConfig> models, {
    required bool usingStorageV2,
  }) async {}
}

class _RoleplayRepository implements RoleplayRepository {
  bool failLoad = false;

  @override
  Future<RoleplayLoadResult> load() async {
    if (failLoad) throw StateError('load failed');
    return const RoleplayLoadResult(
      scenarios: [],
      threads: [],
      usingStorageV2: true,
    );
  }

  @override
  Future<void> save({
    required List<RoleplayScenario> scenarios,
    required List<RoleplayThread> threads,
    required bool usingStorageV2,
  }) async {}
}

class _FeatureRepository implements FeatureRepository {
  bool failLoad = false;
  final Completer<void> saveStarted = Completer<void>();
  final Completer<void> allowSave = Completer<void>();

  @override
  Future<FeatureLoadResult> load() async {
    if (failLoad) throw StateError('load failed');
    return const FeatureLoadResult(
      schedules: [],
      notes: [],
      noteFolders: [],
      noteRevisions: [],
      noteEditProposals: [],
      todoLists: [],
      pagesByNoteId: {},
      activePageIds: {},
      revisionContents: {},
      pageHeads: {},
      pageTombstones: [],
      pageConflicts: {},
      usingStorageV2: true,
    );
  }

  @override
  Future<bool> isStorageV2Active() async => true;

  @override
  Future<String> storeNoteBlob(String content) async => 'hash';

  @override
  Future<void> writeNotePage(StorageV2NotePage page, String content) async {}

  @override
  Future<void> saveStorageV2NotesData(Map<String, dynamic> data) async {
    if (!saveStarted.isCompleted) saveStarted.complete();
    await allowSave.future;
  }

  @override
  Future<void> saveTodoLists(
    List<dynamic> lists, {
    required bool usingStorageV2,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
