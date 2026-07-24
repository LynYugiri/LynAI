import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/backup_models.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/roleplay_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/services/backup_service.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';
import 'package:lynai/repositories/plugin_repository.dart';

import 'support/memory_repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('schema 1-4 backup migration', () {
    for (final schemaVersion in [1, 2, 3, 4]) {
      test(
        'schema $schemaVersion normalizes historical business data',
        () async {
          final root = await Directory.systemTemp.createTemp('legacy_backup_');
          final storage = StorageV2Service(rootDirectory: root);
          await StorageV2UpgradeService(storageV2: storage).ensureReady();
          final pluginRepository = PluginRepository(
            rootOverride: Directory('${root.path}/plugins'),
          );
          final service = _service(
            storage: storage,
            pluginRepository: pluginRepository,
          );
          try {
            await service.featureProvider.load();
            final archive = await service.readZipBytes(
              _legacyZip(schemaVersion: schemaVersion),
            );

            expect(archive.data.modelConfigs, hasLength(1));
            expect(archive.data.modelConfigs!.single.apiKey, isEmpty);
            expect(archive.warnings, contains(contains('明文 API key 已丢弃')));
            expect(
              jsonEncode(archive.data.appSettings?.toJson()),
              isNot(contains('syncCursor')),
            );
            expect(archive.data.conversations, hasLength(1));
            expect(
              archive.data.conversations!.single.messages.single.content,
              'hello',
            );
            expect(archive.data.notes, hasLength(1));
            expect(archive.data.tasks, isNotEmpty);
            expect(archive.data.taskLists, hasLength(1));
            expect(archive.data.calendarEvents, hasLength(1));
            expect(
              archive.availableSections,
              containsAll({
                BackupSection.settings,
                BackupSection.conversations,
                BackupSection.notes,
                BackupSection.tasks,
                BackupSection.calendar,
              }),
            );
            expect(
              service
                  .preview(archive, BackupSelection.fromData(archive.data))
                  .sections,
              isNotEmpty,
            );

            await service.importArchive(
              archive,
              ImportPlan(
                selection: BackupSelection.fromData(archive.data),
                mode: ImportMode.replaceSection,
              ),
            );
            expect(service.modelConfigProvider.models.single.apiKey, isEmpty);
            expect(
              service.conversationProvider.conversations.single.id,
              'conversation',
            );
            expect(service.taskProvider.tasks, isNotEmpty);
            expect(service.calendarProvider.events.single.id, 'schedule');

            if (schemaVersion >= 3) {
              expect(archive.data.notePages, hasLength(1));
              expect(archive.data.notePageContents, {'page': '# page'});
              expect(archive.data.roleplaySessions, hasLength(1));
              expect(archive.data.roleplayThreads, hasLength(1));
              expect(
                archive.data.roleplayThreads!.single.scenarioId,
                schemaVersion == 3 ? 'legacy-scenario-session' : 'scenario',
              );
            } else {
              expect(archive.data.roleplaySessions, isNull);
            }
            if (schemaVersion == 4) {
              expect(archive.data.plugins, isEmpty);
              expect(archive.warnings, contains(contains('可执行文件和关联设置不恢复')));
            }
          } finally {
            await storage.close();
            await root.delete(recursive: true);
          }
        },
      );
    }

    test('legacy ambiguous conversation shape fails closed', () async {
      await expectLater(
        _service().readZipBytes(
          _zip({
            'manifest.json': _manifest(3, {
              'conversations': {
                'enabled': true,
                'files': ['conversations.json'],
              },
            }),
            'conversations.json': {
              'conversations': <Object>[],
              'messages': <Object>[],
            },
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('legacy internal and secret files remain rejected', () async {
      for (final path in [
        'app.db',
        'sync/state.json',
        'secrets/api_keys.json',
        'device_identity.json',
        'device_private_key.json',
        'account_token.json',
      ]) {
        await expectLater(
          _service().readZipBytes(
            _zip({'manifest.json': _manifest(1, const {}), path: 'secret'}),
          ),
          throwsA(isA<FormatException>()),
          reason: path,
        );
      }
    });
  });
}

BackupService _service({
  StorageV2Service? storage,
  PluginRepository? pluginRepository,
}) => BackupService(
  settingsProvider: storage == null
      ? SettingsProvider(repository: MemorySettingsRepository())
      : SettingsProvider(storageV2: storage),
  modelConfigProvider: storage == null
      ? memoryModelConfigProvider()
      : ModelConfigProvider(storageV2: storage),
  conversationProvider: storage == null
      ? memoryConversationProvider()
      : ConversationProvider(storageV2: storage),
  featureProvider: FeatureProvider(storageV2: storage),
  roleplayProvider: storage == null
      ? memoryRoleplayProvider()
      : RoleplayProvider(storageV2: storage),
  pluginProvider: pluginRepository == null
      ? null
      : PluginProvider(repository: pluginRepository),
  pluginRepository: pluginRepository,
  taskProvider: TaskProvider(storageV2: storage),
  calendarProvider: CalendarProvider(storageV2: storage),
  storageV2: storage,
  appVersionLoader: () async => 'test',
);

List<int> _legacyZip({required int schemaVersion}) {
  const at = '2026-01-02T03:04:05.000Z';
  final flat = schemaVersion >= 3;
  final files = <String, Object>{
    'settings.json': {
      'appSettings': {
        'themeColor': 0xff123456,
        'baseThemeColor': 0xff123456,
        'systemPrompt': 'legacy prompt',
        'storageV2': {'syncCursor': 'must-not-restore'},
      },
    },
    'model_configs.json': {
      'models': [
        ModelConfig(
          id: 'model',
          name: 'Legacy',
          endpoint: 'https://example.com/v1',
          apiKey: '',
          modelName: 'legacy-model',
          apiType: 'openai',
          priority: 0,
        ).toJson()..['apiKey'] = 'plaintext-secret',
      ],
    },
    'conversations.json': flat
        ? {
            'conversations': [
              {
                'id': 'conversation',
                'title': 'Legacy conversation',
                'modelId': 'model',
                'createdAt': at,
                'updatedAt': at,
              },
            ],
            'messages': [
              {
                'id': 'message',
                'conversationId': 'conversation',
                'role': 'user',
                'content': 'hello',
                'timestamp': at,
                'sortOrder': 0,
              },
            ],
            'messageAttachments': <Object>[],
          }
        : {
            'conversations': [
              {
                'id': 'conversation',
                'title': 'Legacy conversation',
                'modelId': 'model',
                'messages': [
                  {
                    'id': 'message',
                    'role': 'user',
                    'content': 'hello',
                    'timestamp': at,
                  },
                ],
                'createdAt': at,
                'updatedAt': at,
              },
            ],
          },
    'notes/folders.json': {
      'folders': [
        {'id': 'folder', 'title': 'Folder', 'createdAt': at, 'updatedAt': at},
      ],
    },
    'notes/notes.json': {
      'notes': [
        {
          'id': 'note',
          'title': 'Legacy note',
          'content': 'body',
          'folderId': 'folder',
          'createdAt': at,
          'updatedAt': at,
        },
      ],
    },
    'notes/revisions.json': {'revisions': <Object>[]},
    'schedules.json': {
      'schedules': [
        {
          'id': 'schedule',
          'title': 'Calendar event',
          'start': at,
          'end': '2026-01-02T04:04:05.000Z',
        },
        {
          'id': 'scheduled-task',
          'title': 'Scheduled task',
          'start': at,
          'end': at,
          'kind': 'task',
        },
      ],
    },
    'todo_lists.json': flat
        ? {
            'todoLists': [
              {'id': 'list', 'title': 'List', 'createdAt': at, 'updatedAt': at},
            ],
            'todoItems': [
              {'id': 'todo', 'listId': 'list', 'text': 'Todo', 'done': false},
            ],
          }
        : {
            'todoLists': [
              {
                'id': 'list',
                'title': 'List',
                'items': [
                  {'id': 'todo', 'text': 'Todo', 'done': false},
                ],
                'createdAt': at,
                'updatedAt': at,
              },
            ],
          },
  };
  if (schemaVersion >= 3) {
    files.addAll({
      'notes/pages.json': {
        'pages': [
          {
            'id': 'page',
            'noteId': 'note',
            'title': 'Page',
            'fileName': 'page.md',
            'relativePath': 'notes/note/page.md',
            'contentPath': 'notes/page_contents/page.md',
            'sortOrder': 0,
            'createdAt': at,
            'updatedAt': at,
          },
        ],
      },
      'notes/page_contents/page.md': '# page',
      'roleplay_sessions.json': {
        'sessions': [
          {
            'id': 'session',
            'title': 'Legacy roleplay',
            'scenario': 'A room',
            'director': {'modelId': 'model'},
            'participants': [
              {
                'id': 'player',
                'name': 'Me',
                'systemPrompt': '',
                'isPlayer': true,
              },
              {
                'id': 'character',
                'name': 'Guide',
                'systemPrompt': 'Guide the player',
                'modelId': 'model',
              },
            ],
            'playerParticipantId': 'player',
            'messages': [
              {
                'id': 'roleplay-message',
                'speakerId': 'player',
                'speakerName': 'Me',
                'content': 'Begin',
                'kind': 'player',
                'timestamp': at,
              },
            ],
            'createdAt': at,
            'updatedAt': at,
          },
        ],
      },
    });
  }
  if (schemaVersion == 4) {
    files.remove('roleplay_sessions.json');
    files.addAll({
      'roleplay_scenarios.json': {
        'scenarios': [
          {
            'id': 'scenario',
            'title': 'Scenario',
            'scenario': 'A room',
            'director': {'modelId': 'model'},
            'defaultPlayer': {
              'id': 'player',
              'name': 'Me',
              'systemPrompt': '',
              'isPlayer': true,
            },
            'defaultParticipants': <Object>[],
            'createdAt': at,
            'updatedAt': at,
          },
        ],
      },
      'roleplay_threads.json': {
        'threads': [
          {
            'id': 'thread',
            'scenarioId': 'scenario',
            'title': 'Thread',
            'scenarioTitle': 'Scenario',
            'scenario': 'A room',
            'participants': [
              {
                'id': 'player',
                'name': 'Me',
                'systemPrompt': '',
                'isPlayer': true,
              },
            ],
            'playerParticipantId': 'player',
            'createdAt': at,
            'updatedAt': at,
          },
        ],
      },
      'plugins/installed_plugins.json': {
        'plugins': [
          {
            'plugin': {
              'manifest': {
                'id': 'legacy-plugin',
                'name': 'Legacy plugin',
                'version': '1',
                'entry': 'main.lua',
              },
              'path': '/old/device/plugin',
              'enabled': true,
            },
            'settings': {'enabled': true},
            'storage': {'value': 1},
            'files': [
              {
                'path': 'main.lua',
                'archivePath': 'plugins/installed/legacy-plugin/main.lua',
              },
            ],
          },
        ],
      },
      'plugins/installed/legacy-plugin/main.lua': 'return true',
    });
  }

  final sectionFiles = <String, List<String>>{};
  void section(String name, List<String> paths) {
    sectionFiles[name] = paths.where(files.containsKey).toList();
  }

  section('settings', ['settings.json', 'model_configs.json']);
  section('conversations', ['conversations.json']);
  section('notes', [
    'notes/folders.json',
    'notes/notes.json',
    'notes/revisions.json',
    'notes/pages.json',
    'notes/page_contents/page.md',
  ]);
  section('schedules', ['schedules.json']);
  section('todoLists', ['todo_lists.json']);
  if (schemaVersion >= 3) {
    section('roleplay', [
      'roleplay_sessions.json',
      'roleplay_scenarios.json',
      'roleplay_threads.json',
    ]);
  }
  if (schemaVersion == 4) {
    section('plugins', [
      'plugins/installed_plugins.json',
      'plugins/installed/legacy-plugin/main.lua',
    ]);
  }
  files['manifest.json'] = _manifest(schemaVersion, {
    for (final entry in sectionFiles.entries)
      entry.key: {'enabled': true, 'files': entry.value},
  });
  return _zip(files);
}

Map<String, dynamic> _manifest(
  int schemaVersion,
  Map<String, dynamic> sections,
) => {
  'type': 'lynai.backup',
  'schemaVersion': schemaVersion,
  'appVersion': 'historical',
  'createdAt': '2026-01-02T03:04:05.000Z',
  'format': 'zip',
  'sections': sections,
};

List<int> _zip(Map<String, Object> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = entry.value is String
        ? utf8.encode(entry.value as String)
        : utf8.encode(jsonEncode(entry.value));
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive);
}
