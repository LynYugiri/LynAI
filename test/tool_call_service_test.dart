import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_runtime.dart';
import 'package:lynai/models/agent_trace.dart';
import 'package:lynai/models/agent_user_interaction.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/models/plugin.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/repositories/plugin_repository.dart';
import 'package:lynai/services/device_control_service.dart';
import 'package:lynai/services/agent_cancellation.dart';
import 'package:lynai/services/agent_loop_runtime.dart';
import 'package:lynai/services/agent_protocol_codec.dart';
import 'package:lynai/services/agent_tool_registry.dart';
import 'package:lynai/services/agent_user_interaction_broker.dart';
import 'package:lynai/services/bounded_outbound_http_client.dart';
import 'package:lynai/services/floating_chat_session_controller.dart';
import 'package:lynai/services/lynai_call_identity.dart';
import 'package:lynai/services/lynai_function_service.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';
import 'package:lynai/services/lynai_permission_service.dart';
import 'package:lynai/services/outbound_network_policy.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';
import 'package:lynai/services/tool_call_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_path_provider.dart';
import 'support/memory_repositories.dart';

const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionTimeout = const Duration(seconds: 5);
    return client;
  }
}

class _FakeDeviceBackend implements DeviceControlBackend {
  @override
  Future<Map<String, dynamic>> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
    return {
      'ok': true,
      'result': {'text': '当前页面文本', 'packageName': 'com.example'},
    };
  }
}

Future<StorageV2Service> _readyStorageV2(Directory root) async {
  final storage = StorageV2Service(rootDirectory: root);
  await StorageV2UpgradeService(storageV2: storage).ensureReady();
  return storage;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Directory? pathProviderRoot;

  setUp(() async {
    pathProviderRoot = await installFakePathProvider(
      'lynai_tool_path_provider_test_',
      temporaryDirectoryName: 'temp',
    );
  });

  tearDown(() async {
    final root = pathProviderRoot;
    pathProviderRoot = null;
    await deleteFakePathProviderRoot(root);
  });

  test(
    'list_notes requires query before returning full note contents',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_tool_list_notes_test_',
      );
      try {
        final storage = await _readyStorageV2(root);
        final features = FeatureProvider(storageV2: storage);
        await features.load();
        await features.addNoteWithContent('secret', 'private body');
        final service = ToolCallService(
          features,
          agentIdentity: const LynAICallIdentity(type: LynAICallerType.system),
        );

        final blocked = await service.execute(
          const ChatToolCall(
            id: 'list-all-content',
            name: 'list_notes',
            arguments: {'includeContent': true},
          ),
          const [],
        );
        final allowed = await service.execute(
          const ChatToolCall(
            id: 'list-filtered-content',
            name: 'list_notes',
            arguments: {'query': 'secret', 'includeContent': true},
          ),
          const [],
        );

        expect(blocked['ok'], isFalse);
        expect(allowed['ok'], isTrue);
        expect(allowed['notes'], hasLength(1));
        expect(allowed['notes'].single['content'], 'private body');
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('save_note_page moves note pages', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_tool_page_move_test_',
    );
    try {
      final storage = await _readyStorageV2(root);
      final features = FeatureProvider(storageV2: storage);
      await features.load();
      final noteId = await features.addNoteWithContent('note', 'body');
      final service = ToolCallService(
        features,
        agentIdentity: const LynAICallIdentity(type: LynAICallerType.system),
      );
      final secondPage = await features.addNotePage(noteId, 'second');
      expect(secondPage, isNotNull);
      final initialPageIds = features
          .notePages(noteId)
          .map((page) => page.id)
          .toList();
      expect(initialPageIds, hasLength(2));
      expect(initialPageIds.first, isNot(secondPage));
      expect(initialPageIds.last, secondPage);

      final result = await service.execute(
        ChatToolCall(
          id: 'move-page',
          name: 'save_note_page',
          arguments: {'id': noteId, 'pageId': secondPage, 'move': 'up'},
        ),
        const [],
      );

      expect(result['ok'], isTrue);
      final movedPageIds = (result['pages'] as List)
          .map((page) => page['id'] as String)
          .toList();
      expect(movedPageIds, hasLength(2));
      expect(movedPageIds.first, secondPage);
      expect(movedPageIds.last, isNot(secondPage));
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'Agent tools expose notes and plugin calls according to permissions',
    () {
      final baseTools = ToolCallService.openAITools(const [], true, const []);
      final baseNames = baseTools
          .map((tool) => tool['function']?['name'])
          .whereType<String>()
          .toSet();

      expect(baseNames, contains('add_agent_note'));
      expect(baseNames, contains('create_plan'));
      expect(baseNames, contains('update_plan'));
      expect(baseNames, contains('read_agent_memory'));
      expect(baseNames, contains('update_agent_memory'));
      expect(baseNames, contains('list_plugin_functions'));
      expect(baseNames, contains('list_plugin_skills'));
      expect(baseNames, contains('load_plugin_skill'));
      expect(baseNames, isNot(contains('save_plugin_skill')));
      expect(baseNames, contains('run_subagent'));
      expect(baseNames, isNot(contains('call_plugin_function')));

      final grantedTools = ToolCallService.openAITools(const [], true, const [
        LynAICapabilities.pluginCallFunction,
        LynAIPermissions.pluginSkillFilesWrite,
      ]);
      final grantedNames = grantedTools
          .map((tool) => tool['function']?['name'])
          .whereType<String>()
          .toSet();
      expect(grantedNames, contains('call_plugin_function'));
      expect(grantedNames, contains('save_plugin_skill'));
    },
  );

  test('web_fetch is exposed as a regular built-in tool', () {
    final tools = ToolCallService.openAITools();
    final webFetch = tools
        .map((tool) => tool['function'])
        .whereType<Map>()
        .firstWhere((function) => function['name'] == 'web_fetch');

    expect(webFetch['description'], contains('GET'));
    expect(webFetch['parameters'], isA<Map>());
    expect((webFetch['parameters'] as Map)['required'], contains('url'));
  });

  test('foundation catalog has exactly four logical names', () {
    final service = ToolCallService(
      FeatureProvider(),
      permissionSnapshot: AgentPermissionSnapshot(
        permissions: const [
          LynAIPermissions.networkAccess,
          LynAIPermissions.storageRead,
        ],
      ),
    );
    final snapshot = service.createRunSnapshot(
      agentEnabled: true,
      imageGenerationEnabled: false,
    );
    final foundation = snapshot.tools.registrations
        .map((registration) => registration.descriptor.name)
        .where(
          const {
            'ask_user',
            'web_search',
            'read_attachment',
            'resource',
            'resource_metadata',
            'resource_search',
            'resource_read_text',
            'resource_recognize',
          }.contains,
        )
        .toSet();

    expect(foundation, {
      'ask_user',
      'web_search',
      'read_attachment',
      'resource',
    });
    final resource = snapshot.tools['resource']!;
    expect(resource.descriptor.parameters['required'], contains('operation'));
    final webProperties =
        snapshot.tools['web_search']!.descriptor.parameters['properties']
            as Map<String, dynamic>;
    expect(webProperties, isNot(contains('route')));
    expect(webProperties, isNot(contains('provider')));
  });

  test(
    'ask_user run cancellation removes only its exact broker request',
    () async {
      final broker = AgentUserInteractionBroker();
      final service = ToolCallService(
        FeatureProvider(),
        userInteractionBroker: broker,
      );
      final snapshot = service.createRunSnapshot(
        agentEnabled: true,
        imageGenerationEnabled: false,
      );
      final cancellation = AgentCancellationSource();
      final execution = service.executeCapturedBatch(
        snapshot,
        [
          AgentToolInvocation(
            id: 'ask-cancelled',
            name: 'ask_user',
            arguments: const {'kind': 'confirm', 'prompt': 'Continue?'},
          ),
        ],
        identity: const AgentTurnIdentity(
          runId: 'run-cancelled',
          turnId: 'turn-cancelled',
          turnIndex: 0,
        ),
        cancellationToken: cancellation.token,
      );
      for (var i = 0; i < 100; i++) {
        if (broker.pendingFor(AgentUserInteractionSurface.mainChat) != null) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(
        broker.pendingFor(AgentUserInteractionSurface.mainChat),
        isNotNull,
      );

      cancellation.cancel();
      await execution;

      expect(broker.pendingFor(AgentUserInteractionSurface.mainChat), isNull);
      final next = broker.ask(
        surface: AgentUserInteractionSurface.mainChat,
        identity: const AgentUserInteractionIdentity(
          runId: 'next-run',
          turnId: 'next-turn',
          toolCallId: 'next-call',
          toolName: 'ask_user',
        ),
        question: AgentUserQuestion(
          kind: AgentUserQuestionKind.confirm,
          prompt: 'Next?',
        ),
      );
      final nextRequest = broker.pendingFor(
        AgentUserInteractionSurface.mainChat,
      )!;
      broker.cancel(
        surface: AgentUserInteractionSurface.mainChat,
        requestId: nextRequest.id,
      );
      await next;
      broker.dispose();
    },
  );

  test('canonical organizer tools and legacy aliases are exposed', () {
    final tools = ToolCallService.openAITools();
    final names = tools
        .map((tool) => tool['function']?['name'])
        .whereType<String>()
        .toSet();

    expect(
      names,
      containsAll(const [
        'list_tasks',
        'create_task',
        'update_task',
        'delete_task',
        'list_task_lists',
        'create_task_list',
        'update_task_list',
        'delete_task_list',
        'list_calendar_events',
        'create_calendar_event',
        'update_calendar_event',
        'delete_calendar_event',
        'list_anniversaries',
        'create_anniversary',
        'update_anniversary',
        'delete_anniversary',
        'list_schedules',
        'create_schedule',
        'update_schedule',
        'list_todo_lists',
      ]),
    );
    expect(ToolCallService.nativeSystemPrompt, contains('YYYY-MM-DD'));
    expect(ToolCallService.nativeSystemPrompt, contains('只调用一次 create_task'));
    expect(ToolCallService.nativeSystemPrompt, contains('list_task_lists'));
    for (final name in const [
      'create_task',
      'update_task',
      'create_calendar_event',
      'update_calendar_event',
      'create_anniversary',
      'update_anniversary',
    ]) {
      final function = tools
          .map((tool) => tool['function'])
          .whereType<Map>()
          .firstWhere((value) => value['name'] == name);
      final properties = (function['parameters'] as Map)['properties'] as Map;
      final reminders = properties['reminders'] as Map;
      final items = reminders['items'] as Map;
      expect(reminders['type'], 'array');
      expect(items['required'], containsAll(['anchor', 'offsetMinutes']));
      expect(items['required'], isNot(contains('id')));
      expect(
        ((items['properties'] as Map)['anchor'] as Map)['enum'],
        containsAll([
          'eventStart',
          'taskPlanned',
          'taskDue',
          'anniversaryDate',
        ]),
      );
      expect(
        (((items['properties'] as Map)['dateOnlyTime'] as Map)['pattern']),
        isNotEmpty,
      );
    }
  });

  test(
    'canonical task CRUD and schedule task alias share TaskProvider',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_canonical_task_',
      );
      try {
        final storage = await _readyStorageV2(root);
        final features = FeatureProvider(storageV2: storage);
        final tasks = TaskProvider(storageV2: storage);
        final calendar = CalendarProvider(storageV2: storage);
        await Future.wait([features.load(), tasks.load(), calendar.load()]);
        final service = ToolCallService(
          features,
          tasks: tasks,
          calendar: calendar,
          agentIdentity: const LynAICallIdentity(type: LynAICallerType.system),
        );

        final created = await service.execute(
          const ChatToolCall(
            id: 'canonical-task',
            name: 'create_task',
            arguments: {
              'title': '提交报告',
              'plannedDate': '2026-07-23',
              'plannedTime': '09:30',
            },
          ),
          const [],
        );
        final compatibility = await service.execute(
          const ChatToolCall(
            id: 'legacy-task',
            name: 'create_schedule',
            arguments: {
              'kind': 'task',
              'title': '准备材料',
              'start': '2026-07-24T10:15:00',
            },
          ),
          const [],
        );

        expect(created['ok'], isTrue);
        expect(compatibility['ok'], isTrue);
        expect(tasks.tasks, hasLength(2));
        expect(calendar.events, isEmpty);
        expect((compatibility['schedule'] as Map), isNot(contains('end')));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'canonical organizer permissions reuse todos and schedules grants',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = memorySettingsProvider();
      await settings.replaceSettings(
        AppSettings.defaults().copyWith(agentGrantedPermissions: const []),
      );
      final service = LynAIFunctionService();
      final deniedTask = await service.execute(
        const LynAIFunctionCall(name: 'tasks.list', arguments: {}),
        LynAIFunctionContext(
          identity: const LynAICallIdentity(type: LynAICallerType.agentLua),
          tasks: TaskProvider(),
          settings: settings,
        ),
      );
      final deniedCalendar = await service.execute(
        const LynAIFunctionCall(name: 'calendar.list', arguments: {}),
        LynAIFunctionContext(
          identity: const LynAICallIdentity(type: LynAICallerType.agentLua),
          calendar: CalendarProvider(),
          settings: settings,
        ),
      );

      expect(deniedTask['error'], contains(LynAIPermissions.todosRead));
      expect(deniedCalendar['error'], contains(LynAIPermissions.schedulesRead));
    },
  );

  test('Agent semantic delete variants fail closed before mutation', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_semantic_delete_',
    );
    try {
      final storage = await _readyStorageV2(root);
      final features = FeatureProvider(storageV2: storage);
      final tasks = TaskProvider(storageV2: storage);
      await Future.wait([features.load(), tasks.load()]);
      final noteId = await features.addNoteWithContent('note', 'body');
      final pageId = await features.addNotePage(noteId, 'second');
      final folderId = await features.addNoteFolder('folder');
      final listId = await tasks.addList('list');
      final firstItemId = await tasks.addTask(title: 'first', listId: listId);
      final secondItemId = await tasks.addTask(title: 'second', listId: listId);
      final service = LynAIFunctionService();
      final context = LynAIFunctionContext(
        identity: const LynAICallIdentity(type: LynAICallerType.agent),
        agentPermissionSnapshot: AgentPermissionSnapshot(
          permissions: const [
            LynAIPermissions.notesWrite,
            LynAIPermissions.todosWrite,
          ],
        ),
        features: features,
        tasks: tasks,
      );

      for (final call in [
        LynAIFunctionCall(
          name: 'notes.pages.save',
          arguments: {'id': noteId, 'pageId': pageId, 'delete': true},
        ),
        LynAIFunctionCall(
          name: 'notes.folders.save',
          arguments: {'id': folderId, 'delete': true},
        ),
        LynAIFunctionCall(
          name: 'todos.saveItem',
          arguments: {'listId': listId, 'itemId': firstItemId, 'delete': true},
        ),
        LynAIFunctionCall(
          name: 'todos.saveList',
          arguments: {
            'id': listId,
            'items': [
              {'id': firstItemId, 'text': 'first'},
            ],
          },
        ),
      ]) {
        final result = await service.execute(call, context);
        expect(result['ok'], isFalse, reason: call.name);
        expect(result['error'].toString(), contains('删除操作'));
      }

      expect(
        features.notePages(noteId).map((page) => page.id),
        contains(pageId),
      );
      expect(features.getNoteFolder(folderId), isNotNull);
      expect(tasks.taskById(firstItemId), isNotNull);
      expect(tasks.taskById(secondItemId), isNotNull);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('http.fetch uses bounded SSRF policy', () async {
    final result = await LynAIFunctionService().execute(
      const LynAIFunctionCall(
        name: 'http.fetch',
        arguments: {'url': 'http://127.0.0.1/private'},
      ),
      LynAIFunctionContext(
        identity: const LynAICallIdentity(type: LynAICallerType.agent),
        agentPermissionSnapshot: AgentPermissionSnapshot(
          permissions: const [LynAIPermissions.networkAccess],
        ),
        outboundHttpClient: BoundedOutboundHttpClient(
          policy: OutboundNetworkPolicy(
            allowedHttpOrigins: const {'http://127.0.0.1'},
          ),
        ),
      ),
    );

    expect(result['ok'], isFalse);
    expect(result['error'].toString(), contains('默认仅允许 HTTPS'));
  });

  test(
    'http.fetch plaintext opt-in is explicit and still policy bounded',
    () async {
      final result = await LynAIFunctionService().execute(
        const LynAIFunctionCall(
          name: 'http.fetch',
          arguments: {'url': 'http://127.0.0.1/private'},
        ),
        LynAIFunctionContext(
          identity: const LynAICallIdentity(type: LynAICallerType.agent),
          agentPermissionSnapshot: AgentPermissionSnapshot(
            permissions: const [LynAIPermissions.networkAccess],
          ),
          outboundHttpClient: BoundedOutboundHttpClient(
            policy: OutboundNetworkPolicy(
              allowedHttpOrigins: const {'http://127.0.0.1'},
            ),
          ),
          allowPlaintextHttpFetch: true,
        ),
      );

      expect(result['ok'], isFalse);
      expect(result['error'].toString(), contains('privateHost'));
    },
  );

  test('call identity children preserve Agent correlation', () {
    const identity = LynAICallIdentity(
      type: LynAICallerType.agent,
      conversationId: 'conversation',
      runId: 'run',
      turnId: 'turn',
      toolCallId: 'outer-call',
    );

    final child = identity.child(
      type: LynAICallerType.agentLua,
      toolCallId: 'inner-call',
      toolName: 'notes.list',
    );

    expect(child.conversationId, 'conversation');
    expect(child.runId, 'run');
    expect(child.turnId, 'turn');
    expect(child.toolCallId, 'inner-call');
    expect(child.toolName, 'notes.list');
    expect(child.parent, same(identity));
  });

  test(
    'model-reachable direct dispatch fails closed without explicit trusted identity',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = memorySettingsProvider();
      await settings.replaceSettings(
        AppSettings.defaults().copyWith(agentGrantedPermissions: const []),
      );
      final conversations = memoryConversationProvider();
      final cid = conversations.createConversation(
        ConversationSettings(modelId: 'm1', agentEnabled: true),
      );
      final features = FeatureProvider();
      const call = ChatToolCall(
        id: 'list-notes',
        name: 'list_notes',
        arguments: {},
      );

      final agentResult = await ToolCallService(
        features,
        settings: settings,
        conversations: conversations,
        conversationId: cid,
        agentIdentity: const LynAICallIdentity(
          type: LynAICallerType.agent,
          conversationId: 'correlated-conversation',
          runId: 'run-1',
          turnId: 'turn-1',
        ),
      ).execute(call, const []);
      final ordinaryResult = await ToolCallService(
        features,
        settings: settings,
        agentIdentity: const LynAICallIdentity(type: LynAICallerType.system),
      ).execute(call, const []);
      final agentOpenApp =
          await ToolCallService(
            features,
            settings: settings,
            conversations: conversations,
            conversationId: cid,
          ).execute(
            const ChatToolCall(
              id: 'open-app',
              name: 'open_app',
              arguments: {'packageName': 'com.example.app'},
            ),
            const [],
          );

      expect(agentResult['ok'], isFalse);
      expect(
        agentResult['error'].toString(),
        contains(LynAIPermissions.notesRead),
      );
      expect(ordinaryResult['ok'], isTrue);
      final missingIdentity = await ToolCallService(
        features,
        settings: settings,
      ).execute(call, const []);
      expect(missingIdentity['ok'], isFalse);
      expect(
        missingIdentity['error'].toString(),
        contains(LynAIPermissions.notesRead),
      );
      expect(agentOpenApp['ok'], isFalse);
      expect(
        agentOpenApp['error'].toString(),
        contains(LynAIPermissions.deviceControl),
      );
    },
  );

  test('invalid core tool arguments are blocked before dispatch', () async {
    final result = await ToolCallService(FeatureProvider()).execute(
      const ChatToolCall(
        id: 'bad-open-app',
        name: 'open_app',
        arguments: {'packageName': 42},
      ),
      const [],
    );

    expect(result['ok'], isFalse);
    expect(result['error'].toString(), contains(r'$.packageName'));
    expect(result['error'].toString(), contains('expected string'));
  });

  test('compatibility execution maps structured external failures', () async {
    final registry = AgentToolRegistry();
    registry.register(
      AgentToolDescriptor(
        name: 'external_failure',
        description: 'fails',
        source: AgentToolSource.mcp,
        sideEffect: AgentToolSideEffect.external,
        concurrency: AgentToolConcurrency.parallelSafe,
      ),
      (invocation, token) async => throw StateError('remote detail'),
    );

    final results =
        await ToolCallService(
          FeatureProvider(),
          externalToolRegistry: registry,
        ).executeSequentialCompatibility(
          [AgentToolInvocation(id: 'failure', name: 'external_failure')],
          const [],
          identity: const AgentTurnIdentity(
            runId: 'run',
            turnId: 'turn',
            turnIndex: 0,
          ),
          cancellationToken: AgentCancellationSource().token,
        );

    expect(results.single.status, AgentToolResultStatus.failure);
    expect(results.single.errorCode, 'tool_execution_failed');
    expect(results.single.errorMessage, contains('remote detail'));
    expect(results.single.value.toString(), contains('remote detail'));
    final payload = jsonDecode(
      const AgentProtocolCodec().toolResultMessage(results.single)['content']
          as String,
    );
    expect(payload['error'], contains('remote detail'));
  });

  test(
    'compatibility cancellation reaches external handler and ignores late result',
    () async {
      final registry = AgentToolRegistry();
      final started = Completer<void>();
      final release = Completer<Object?>();
      AgentCancellationToken? receivedToken;
      registry.register(
        AgentToolDescriptor(
          name: 'slow_external',
          description: 'slow',
          source: AgentToolSource.mcp,
          sideEffect: AgentToolSideEffect.external,
          concurrency: AgentToolConcurrency.parallelSafe,
        ),
        (invocation, token) {
          receivedToken = token;
          started.complete();
          return release.future;
        },
      );
      final service = ToolCallService(
        FeatureProvider(),
        externalToolRegistry: registry,
      );
      var modelTurns = 0;
      final handle = const AgentLoopRuntime().start(
        messages: const [],
        maxToolRounds: 2,
        model: (request) async* {
          modelTurns++;
          yield AgentModelToolCalls([
            AgentToolInvocation(id: 'slow', name: 'slow_external'),
          ]);
          yield const AgentModelStreamCompleted();
        },
        executeTools: (calls, identity, cancellationToken) =>
            service.executeSequentialCompatibility(
              calls,
              const [],
              identity: identity,
              cancellationToken: cancellationToken,
            ),
      );

      await started.future;
      handle.cancel();
      final result = await handle.result.timeout(const Duration(seconds: 1));
      expect(receivedToken?.isCancellationRequested, isTrue);
      expect(result.status, AgentRunStatus.cancelled);
      release.complete({'late': true});
      await Future<void>.delayed(Duration.zero);
      expect(modelTurns, 1);
    },
  );

  test(
    'run snapshot is permission-filtered and resolves live MCP handler',
    () async {
      final registry = AgentToolRegistry();
      registry.register(
        AgentToolDescriptor(
          name: 'mcp_snapshot_lookup',
          description: 'Snapshot MCP',
          source: AgentToolSource.mcp,
          sideEffect: AgentToolSideEffect.external,
          concurrency: AgentToolConcurrency.parallelSafe,
        ),
        (invocation, cancellationToken) async => {'version': 1},
      );
      final service = ToolCallService(
        FeatureProvider(),
        externalToolRegistry: registry,
        externalToolSnapshot: registry.snapshot(),
        permissionSnapshot: AgentPermissionSnapshot(
          permissions: const [LynAIPermissions.networkAccess],
        ),
      );
      final snapshot = service.createRunSnapshot(
        agentEnabled: false,
        imageGenerationEnabled: false,
      );
      registry.register(
        AgentToolDescriptor(
          name: 'mcp_snapshot_lookup',
          description: 'Replacement MCP',
          source: AgentToolSource.mcp,
          sideEffect: AgentToolSideEffect.external,
          concurrency: AgentToolConcurrency.parallelSafe,
        ),
        (invocation, cancellationToken) async => {'version': 2},
      );
      final cancellation = AgentCancellationSource();
      final results = await service.executeCapturedBatch(
        snapshot,
        [AgentToolInvocation(id: 'mcp', name: 'mcp_snapshot_lookup')],
        identity: const AgentTurnIdentity(
          runId: 'run',
          turnId: 'turn',
          turnIndex: 0,
        ),
        cancellationToken: cancellation.token,
      );

      expect(snapshot.tools['web_search'], isNotNull);
      expect(snapshot.tools['list_notes'], isNull);
      expect(snapshot.tools['mcp_snapshot_lookup'], isNotNull);
      expect((results.single.value as Map)['version'], 2);
    },
  );

  test('get_current_screen is exposed only for floating screen context', () {
    final regularTools = ToolCallService.openAITools();
    final floatingTools = ToolCallService.openAITools(
      const [],
      false,
      const [],
      false,
      true,
    );

    String toolName(Map<String, dynamic> tool) {
      return (tool['function'] as Map)['name'] as String;
    }

    expect(regularTools.map(toolName), isNot(contains('get_current_screen')));
    expect(floatingTools.map(toolName), contains('get_current_screen'));
  });

  test(
    'get_current_screen execution requires floating authorization',
    () async {
      DeviceControlService.instance.setBackendForTesting(_FakeDeviceBackend());
      try {
        final denied = await ToolCallService(FeatureProvider()).execute(
          const ChatToolCall(
            id: 'screen-denied',
            name: 'get_current_screen',
            arguments: {},
          ),
          const [],
        );
        final allowed =
            await ToolCallService(
              FeatureProvider(),
              allowScreenContextTool: true,
            ).execute(
              const ChatToolCall(
                id: 'screen-allowed',
                name: 'get_current_screen',
                arguments: {},
              ),
              const [],
            );

        expect(denied['ok'], isFalse);
        expect(denied['error'], contains('未允许'));
        expect(allowed['ok'], isTrue);
        expect((allowed['result'] as Map)['text'], '当前页面文本');
      } finally {
        DeviceControlService.instance.setBackendForTesting(null);
      }
    },
  );

  test('floating chat respects disabled screen context mode', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.replaceSettings(
      AppSettings.defaults().copyWith(
        floatingAssistant: const FloatingAssistantSettings(
          allowScreenContext: true,
          screenContextMode: FloatingAssistantSettings.screenContextDisabled,
        ),
      ),
    );
    final controller = FloatingChatSessionController(
      settings: settings,
      conversations: ConversationProvider(),
      models: ModelConfigProvider(),
      features: FeatureProvider(),
      tasks: TaskProvider(),
      calendar: CalendarProvider(),
      plugins: PluginProvider(),
    );
    try {
      expect(controller.screenContextToolAllowed, isFalse);
      expect(controller.stateJson()['screenContextEnabled'], isFalse);
    } finally {
      await controller.dispose();
    }
  });

  test('web_fetch rejects non-http URLs', () async {
    final service = ToolCallService(FeatureProvider());
    final result = await service.execute(
      const ChatToolCall(
        id: 'fetch-file',
        name: 'web_fetch',
        arguments: {'url': 'file:///etc/passwd'},
      ),
      const [],
    );

    expect(result['ok'], isFalse);
    expect(result['error'], contains('http/https'));
  });

  test('web_fetch fetches and truncates response body', () async {
    HttpServer? server;
    await HttpOverrides.runZoned(() async {
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final methods = <String>[];
        server!.listen((request) async {
          methods.add(request.method);
          request.response.headers.contentType = ContentType.text;
          request.response.write('abcdef');
          await request.response.close();
        });

        final service = ToolCallService(
          FeatureProvider(),
          agentIdentity: const LynAICallIdentity(type: LynAICallerType.system),
          outboundHttpClient: BoundedOutboundHttpClient(
            policy: OutboundNetworkPolicy(
              allowedHttpOrigins: {'http://127.0.0.1:${server!.port}'},
              allowPrivateNetwork: true,
            ),
          ),
          allowPlaintextHttpFetch: true,
        );
        final result = await service.execute(
          ChatToolCall(
            id: 'fetch-local',
            name: 'web_fetch',
            arguments: {
              'url': 'http://${server!.address.host}:${server!.port}/page',
              'maxChars': 4,
            },
          ),
          const [],
        );

        expect(result['ok'], isTrue);
        expect(result['status'], 200);
        expect(result['body'], 'abcd');
        expect(result['bodyLength'], 6);
        expect(result['truncated'], isTrue);
        expect(result['contentType'], contains('text/plain'));
        expect(methods, ['GET']);
      } finally {
        await server?.close(force: true);
      }
    }, createHttpClient: _RealHttpOverrides().createHttpClient);
  });

  test('modelVisibleToolResult strips nested binary payloads', () {
    final visible =
        ToolCallService.modelVisibleToolResult({
              'ok': true,
              'result': {
                'text': 'OCR text',
                'image': {
                  'mimeType': 'image/png',
                  'dataBase64': _tinyPngBase64,
                },
                'items': [
                  {'content': 'vision result', 'base64': 'secret'},
                  {'content': 'image result', 'b64_json': 'secret'},
                  {'content': 'upper result', 'ImageBase64': 'secret'},
                ],
              },
            })
            as Map;

    expect(visible['binaryContentOmitted'], isTrue);
    final result = visible['result'] as Map;
    expect(result['text'], 'OCR text');
    expect((result['image'] as Map), isNot(contains('dataBase64')));
    expect(((result['items'] as List).first as Map), isNot(contains('base64')));
    expect(((result['items'] as List)[1] as Map), isNot(contains('b64_json')));
    expect(
      ((result['items'] as List)[2] as Map),
      isNot(contains('ImageBase64')),
    );
  });

  test('read-only device queries use screen-read permission', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = memorySettingsProvider();
    await settings.replaceSettings(
      AppSettings.defaults().copyWith(
        agentGrantedPermissions: const [LynAIPermissions.deviceScreenRead],
      ),
    );
    final service = LynAIFunctionService();
    final context = LynAIFunctionContext(
      identity: const LynAICallIdentity(type: LynAICallerType.agentLua),
      settings: settings,
    );

    final query = await service.execute(
      const LynAIFunctionCall(name: 'device.node.find', arguments: {}),
      context,
    );
    final action = await service.execute(
      const LynAIFunctionCall(name: 'device.inputText', arguments: {}),
      context,
    );

    expect(query['ok'], isFalse);
    expect(query['error'].toString(), isNot(contains('未授权')));
    expect(action['ok'], isFalse);
    expect(
      action['error'].toString(),
      contains(LynAIPermissions.deviceControl),
    );
  });

  test('execute_lua tool describes async multi-step device scripts', () {
    final tools = ToolCallService.openAITools(const [], true, const [
      LynAICapabilities.luaExecute,
    ]);
    final executeLua = tools
        .map((tool) => tool['function'])
        .whereType<Map>()
        .firstWhere((function) => function['name'] == 'execute_lua');
    final description = executeLua['description'] as String;

    expect(description, contains('异步线性执行'));
    expect(description, contains('agent.plan.update'));
    expect(description, contains('agent.memory.update'));
    expect(description, contains('一次 execute_lua'));
    expect(description, contains('agent.note.add'));
    expect(description, contains('device.waitForNode'));
    expect(description, contains('model.ocr'));
    expect(description, contains('model.recognizeFile'));
    expect(description, contains('model.generateImage'));
  });

  test('image generation tool is appended last when enabled', () {
    final tools = ToolCallService.openAITools(const [], false, const [], true);
    final names = tools
        .map((tool) => tool['function'])
        .whereType<Map>()
        .map((function) => function['name'])
        .toList();

    expect(names.last, 'generate_image');
  });

  test('model recognition functions require dedicated permissions', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = memorySettingsProvider();
    await settings.replaceSettings(
      AppSettings.defaults().copyWith(agentGrantedPermissions: const []),
    );
    final result = await LynAIFunctionService().execute(
      const LynAIFunctionCall(
        name: 'model.ocr',
        arguments: {'imageBase64': 'AA=='},
      ),
      LynAIFunctionContext(
        identity: const LynAICallIdentity(type: LynAICallerType.agentLua),
        settings: settings,
      ),
    );

    expect(result['ok'], isFalse);
    expect(result['error'], contains(LynAIPermissions.modelOcr));
  });

  test('settings migration preserves disabled model permissions', () {
    final settings = AppSettings.fromJson({
      'themeColor': 0xFF2196F3,
      'baseThemeColor': 0xFF2196F3,
      'agentGrantedPermissions': const [LynAIPermissions.notesRead],
    });

    expect(
      settings.agentGrantedPermissions,
      contains(LynAIPermissions.notesRead),
    );
    expect(
      settings.agentGrantedPermissions,
      isNot(contains(LynAIPermissions.deviceControl)),
    );
    expect(
      settings.agentGrantedPermissions,
      isNot(contains(LynAIPermissions.modelChat)),
    );
    expect(
      settings.agentGrantedPermissions,
      isNot(contains(LynAIPermissions.modelOcr)),
    );
    expect(
      settings.agentGrantedPermissions,
      isNot(contains(LynAIPermissions.modelGenerateImage)),
    );
  });

  test(
    'permission service separates Agent defaults and plugin webview grants',
    () {
      const service = LynAIPermissionService();
      expect(
        service.canUsePermission(
          identity: const LynAICallIdentity(type: LynAICallerType.agentLua),
          permission: LynAIPermissions.notesRead,
        ),
        isTrue,
      );
      final manifest = PluginManifest.fromJson({
        'id': 'webview_perm_plugin',
        'name': 'WebView Permission Plugin',
        'entry': 'main.lua',
        'permissions': ['notes:read'],
      });
      final plugin = InstalledPlugin(
        manifest: manifest,
        path: '/tmp/webview_perm_plugin',
        enabled: true,
        grantedPermissions: const [],
        enabledFeaturePages: const [],
      );
      expect(
        service.canUsePermission(
          identity: const LynAICallIdentity(
            type: LynAICallerType.pluginWebview,
            pluginId: 'webview_perm_plugin',
          ),
          permission: LynAIPermissions.notesRead,
          plugin: plugin,
        ),
        isFalse,
      );
    },
  );

  test('add_agent_note appends assistant trace without permissions', () async {
    SharedPreferences.setMockInitialValues({});
    final conversations = memoryConversationProvider();
    final cid = conversations.createConversation(
      ConversationSettings(modelId: 'm1', agentEnabled: true),
    );
    conversations.addMessage(cid, 'user', 'do work');
    conversations.addMessage(cid, 'assistant', '', save: false);
    final service = ToolCallService(
      FeatureProvider(),
      conversations: conversations,
      conversationId: cid,
    );

    final result = await service.execute(
      const ChatToolCall(
        id: 'note',
        name: 'add_agent_note',
        arguments: {'content': '我先查看可用插件。'},
      ),
      const [],
    );

    expect(result['ok'], isTrue);
    expect(result['result'], {'noted': true});
    final trace = conversations.getConversation(cid)!.messages.last.agentTrace;
    expect(trace?.events, hasLength(1));
    expect(trace?.events.single.content, '我先查看可用插件。');
  });

  test('Agent memory tools persist conversation working memory', () async {
    SharedPreferences.setMockInitialValues({});
    final conversations = memoryConversationProvider();
    final cid = conversations.createConversation(
      ConversationSettings(modelId: 'm1', agentEnabled: true),
    );
    conversations.addMessage(cid, 'user', 'reply qq');
    conversations.addMessage(cid, 'assistant', '', save: false);
    final service = ToolCallService(
      FeatureProvider(),
      conversations: conversations,
      conversationId: cid,
    );

    final updated = await service.execute(
      const ChatToolCall(
        id: 'memory-update',
        name: 'update_agent_memory',
        arguments: {
          'goal': '回复 QQ 消息',
          'entries': [
            {'kind': 'fact', 'content': '目标联系人是 foo'},
          ],
        },
      ),
      const [],
    );
    final read = await service.execute(
      const ChatToolCall(
        id: 'memory-read',
        name: 'read_agent_memory',
        arguments: {},
      ),
      const [],
    );

    expect(updated['ok'], isTrue);
    expect(read['ok'], isTrue);
    final memory = conversations.getConversation(cid)!.agentWorkingMemory!;
    expect(memory.goal, '回复 QQ 消息');
    expect(memory.entries.single.content, '目标联系人是 foo');
    expect(
      conversations
          .getConversation(cid)!
          .messages
          .last
          .agentTrace
          ?.events
          .where((event) => event.type == AgentTraceEvent.memoryUpdate),
      isNotEmpty,
    );
  });

  test('generated images append to latest assistant message', () async {
    SharedPreferences.setMockInitialValues({});
    final conversations = memoryConversationProvider();
    final cid = conversations.createConversation(
      ConversationSettings(modelId: 'm1'),
    );
    conversations.addMessage(cid, 'user', 'draw a cat');
    conversations.addMessage(cid, 'assistant', 'working', save: false);

    conversations.appendImagesToLastAssistantMessage(cid, const [
      MessageImage(path: '/tmp/generated.png', name: 'generated.png', size: 12),
    ]);

    final message = conversations.getConversation(cid)!.messages.last;
    expect(message.role, 'assistant');
    expect(message.images, hasLength(1));
    expect(message.images.single.name, 'generated.png');
  });

  test('execute_lua ignores arbitrary generated image payloads', () async {
    SharedPreferences.setMockInitialValues({});
    final imageFile = File('${Directory.systemTemp.path}/lynai_generated.png');
    await imageFile.writeAsBytes(base64Decode(_tinyPngBase64));
    try {
      final conversations = memoryConversationProvider();
      final cid = conversations.createConversation(
        ConversationSettings(
          modelId: 'chat-1',
          agentEnabled: true,
          agentGrantedPermissions: const [LynAIPermissions.luaExecute],
        ),
      );
      conversations.addMessage(cid, 'user', 'draw a cat');
      conversations.addMessage(cid, 'assistant', '', save: false);
      final settings = memorySettingsProvider();
      await settings.replaceSettings(
        AppSettings.defaults().copyWith(
          agentGrantedPermissions: const [LynAIPermissions.luaExecute],
        ),
      );
      final service = ToolCallService(
        FeatureProvider(),
        settings: settings,
        conversations: conversations,
        conversationId: cid,
        agentIdentity: const LynAICallIdentity(
          type: LynAICallerType.agent,
          runId: 'run-lua-image',
          turnId: 'turn-lua-image',
        ),
        permissionSnapshot: AgentPermissionSnapshot(
          permissions: const [LynAIPermissions.luaExecute],
        ),
      );

      final result = await service.execute(
        ChatToolCall(
          id: 'lua-image',
          name: 'execute_lua',
          arguments: {
            'purpose': 'generate image',
            'code':
                '''
return {
  ok = true,
  generatedImages = {
    {
      path = "${imageFile.path}",
      name = "generated_image.png",
      size = 12,
      mimeType = "image/png"
    }
  }
}
''',
          },
        ),
        const [],
        cancellationToken: AgentCancellationSource().token,
      );

      expect(result['ok'], isTrue);
      final message = conversations.getConversation(cid)!.messages.last;
      expect(message.images, isEmpty);
    } finally {
      if (await imageFile.exists()) await imageFile.delete();
    }
  });

  test('Agent tools use structured success and error payloads', () async {
    SharedPreferences.setMockInitialValues({});
    final conversations = memoryConversationProvider();
    final disabledCid = conversations.createConversation(
      ConversationSettings(modelId: 'm1'),
    );
    final disabledService = ToolCallService(
      FeatureProvider(),
      conversations: conversations,
      conversationId: disabledCid,
    );

    final disabled = await disabledService.execute(
      const ChatToolCall(
        id: 'functions-disabled',
        name: 'list_plugin_functions',
        arguments: {},
      ),
      const [],
    );

    expect(disabled['ok'], isFalse);
    expect(disabled['error'], isA<Map>());
    expect((disabled['error'] as Map)['code'], 'agent_disabled');

    final cid = conversations.createConversation(
      ConversationSettings(modelId: 'm1', agentEnabled: true),
    );
    conversations.addMessage(cid, 'user', 'list functions');
    conversations.addMessage(cid, 'assistant', '', save: false);
    final service = ToolCallService(
      FeatureProvider(),
      conversations: conversations,
      conversationId: cid,
    );

    final listed = await service.execute(
      const ChatToolCall(
        id: 'functions',
        name: 'list_plugin_functions',
        arguments: {},
      ),
      const [],
    );

    expect(listed['ok'], isTrue);
    expect(listed['result'], isA<Map>());
    expect((listed['result'] as Map)['functions'], isA<List>());
  });

  test(
    'Agent can list and load plugin skills without extra permission',
    () async {
      SharedPreferences.setMockInitialValues({});
      final source = await Directory.systemTemp.createTemp(
        'lynai_skill_source_',
      );
      final installRoot = await Directory.systemTemp.createTemp(
        'lynai_skill_root_',
      );
      try {
        await Directory('${source.path}/skills').create();
        await File('${source.path}/plugin.json').writeAsString(
          jsonEncode({
            'id': 'skill-plugin',
            'name': 'Skill Plugin',
            'entry': 'main.lua',
            'skills': [
              {
                'name': 'weather__inner',
                'title': 'Weather Inner',
                'description': 'Use for weather planning.',
                'whenToUse': 'weather plans',
                'tags': ['weather'],
              },
            ],
          }),
        );
        await File('${source.path}/main.lua').writeAsString('return {}');
        await File(
          '${source.path}/skills/weather__inner.md',
        ).writeAsString('# Weather\n\nUse the weather tool.');
        final plugins = PluginProvider(
          repository: PluginRepository(rootOverride: installRoot),
        );
        await plugins.importDirectory(source.path);
        await plugins.setEnabled('skill-plugin', true);
        final conversations = memoryConversationProvider();
        final cid = conversations.createConversation(
          ConversationSettings(modelId: 'm1', agentEnabled: true),
        );
        conversations.addMessage(cid, 'user', 'load skill');
        conversations.addMessage(cid, 'assistant', '', save: false);
        final service = ToolCallService(
          FeatureProvider(),
          plugins: plugins,
          conversations: conversations,
          conversationId: cid,
        );

        final listed = await service.execute(
          const ChatToolCall(
            id: 'skills',
            name: 'list_plugin_skills',
            arguments: {},
          ),
          const [],
        );
        expect(listed['ok'], isTrue);
        final skills = ((listed['result'] as Map)['skills'] as List)
            .cast<Map>();
        expect(skills.single['qualifiedName'], 'skill-plugin__weather__inner');
        expect(
          ToolCallService.pluginSkillDisplayName(plugins.plugins, {
            'qualifiedName': 'skill-plugin__weather__inner',
          }),
          'Weather Inner',
        );

        final loaded = await service.execute(
          const ChatToolCall(
            id: 'load-skill',
            name: 'load_plugin_skill',
            arguments: {'qualifiedName': 'skill-plugin__weather__inner'},
          ),
          const [],
        );
        expect(loaded['ok'], isTrue);
        final result = loaded['result'] as Map;
        expect(result['name'], 'weather__inner');
        expect(result['content'], contains('Use the weather tool'));
      } finally {
        await source.delete(recursive: true);
        await installRoot.delete(recursive: true);
      }
    },
  );

  test('tool round limit message preserves existing assistant text', () {
    expect(ToolCallService.maxToolRounds, 12);
    expect(
      ToolCallService.toolRoundLimitMessage('partial answer'),
      allOf(contains('partial answer'), contains('12 轮上限')),
    );
  });

  test('Subagent stops consecutive tool calls at the shared limit', () async {
    SharedPreferences.setMockInitialValues({});
    await HttpOverrides.runZoned(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      unawaited(() async {
        await for (final request in server) {
          requests++;
          await utf8.decoder.bind(request).join();
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': 'working $requests',
                    'tool_calls': [
                      {
                        'id': 'call_$requests',
                        'type': 'function',
                        'function': {
                          'name': 'get_current_time',
                          'arguments': '{}',
                        },
                      },
                    ],
                  },
                },
              ],
            }),
          );
          await request.response.close();
        }
      }());

      try {
        final conversations = memoryConversationProvider();
        final cid = conversations.createConversation(
          ConversationSettings(modelId: 'm1', agentEnabled: true),
        );
        conversations.addMessage(cid, 'assistant', '', save: false);
        final models = memoryModelConfigProvider()
          ..addModel(
            ModelConfig(
              id: 'm1',
              name: 'test',
              endpoint: 'http://${server.address.host}:${server.port}',
              apiKey: '',
              modelName: 'model',
              apiType: 'openai',
              priority: 0,
            ),
          );
        final service = ToolCallService(
          FeatureProvider(),
          modelConfigs: models,
          conversations: conversations,
          conversationId: cid,
        );

        final result = await service.execute(
          const ChatToolCall(
            id: 'subagent',
            name: 'run_subagent',
            arguments: {'task': 'keep calling tools'},
          ),
          const [],
        );

        expect(result['ok'], isFalse);
        expect((result['error'] as Map)['code'], 'tool_round_limit_reached');
        expect(requests, ToolCallService.maxToolRounds + 1);
      } finally {
        await server.close(force: true);
      }
    }, createHttpClient: _RealHttpOverrides().createHttpClient);
  });
}
