import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/models/agent_user_interaction.dart';
import 'package:lynai/models/knowledge_base.dart';
import 'package:lynai/models/knowledge_category.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/knowledge_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/repositories/knowledge_repository.dart';
import 'package:lynai/services/api_service.dart';
import 'package:lynai/services/floating_chat_session_controller.dart';
import 'package:lynai/services/agent_user_interaction_broker.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/services/tool_call_service.dart';

import '../support/memory_repositories.dart';

class _FakeApiService extends ApiService {
  final List<StreamController<StreamChunk>> streams = [];
  final List<List<Map<String, dynamic>>> requestMessages = [];
  int requests = 0;

  @override
  Stream<StreamChunk> sendStreamRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
    List<Map<String, dynamic>> tools = const [],
    Object? toolChoice,
  }) {
    requests++;
    requestMessages.add(messages);
    final controller = StreamController<StreamChunk>.broadcast();
    streams.add(controller);
    return controller.stream;
  }

  @override
  Future<ChatResponse> sendChatRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
    List<Map<String, dynamic>> tools = const [],
    Object? toolChoice,
  }) async => const ChatResponse(content: 'title');
}

class _AskUserApiService extends ApiService {
  int requests = 0;

  @override
  Stream<StreamChunk> sendStreamRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
    List<Map<String, dynamic>> tools = const [],
    Object? toolChoice,
  }) async* {
    requests++;
    if (requests == 1) {
      yield StreamChunk(
        toolCalls: [
          ChatToolCall(
            id: 'ask-1',
            name: 'ask_user',
            arguments: {
              'kind': 'singleChoice',
              'prompt': 'Choose',
              'choices': [
                {'id': 'a', 'label': 'A'},
              ],
            },
          ),
        ],
        isDone: true,
      );
      return;
    }
    yield const StreamChunk(content: 'continued', isDone: true);
  }
}

class _MemoryKnowledgeRepository extends KnowledgeRepository {
  @override
  Future<void> replace(KnowledgeLoadResult value) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'persists the runtime final response while drafts remain caller-owned',
    () async {
      final api = _FakeApiService();
      final conversations = memoryConversationProvider();
      final models = memoryModelConfigProvider();
      models.addModel(_model());
      final controller = FloatingChatSessionController(
        settings: memorySettingsProvider(),
        conversations: conversations,
        models: models,
        features: FeatureProvider(),
        knowledge: KnowledgeProvider(),
        tasks: TaskProvider(),
        calendar: CalendarProvider(),
        plugins: PluginProvider(),
        api: api,
      );
      try {
        await controller.send('hello');
        await _waitFor(() => api.streams.isNotEmpty);
        api.streams.single.add(const StreamChunk(reasoningContent: 'thinking'));
        api.streams.single.add(const StreamChunk(content: 'answer'));
        await _waitFor(() => controller.stateJson()['draft'] == 'answer');
        api.streams.single.add(const StreamChunk(isDone: true));
        await _waitFor(() => !controller.isStreaming);

        final conversation = conversations.getConversation(
          controller.conversationId!,
        )!;
        expect(conversation.messages.last.content, 'answer');
        expect(conversation.messages.last.thinkingContent, 'thinking');
        expect(controller.stateJson()['draft'], '');
      } finally {
        await controller.dispose();
        for (final stream in api.streams) {
          await stream.close();
        }
      }
    },
  );

  test(
    'freezes annotation instructions into the single system message',
    () async {
      final api = _FakeApiService();
      final conversations = memoryConversationProvider();
      final models = memoryModelConfigProvider()..addModel(_model());
      final knowledge = KnowledgeProvider(
        repository: _MemoryKnowledgeRepository(),
      );
      final now = DateTime(2026);
      await knowledge.replaceAll(
        knowledgeBases: [
          KnowledgeBase(
            id: 'base',
            name: 'Base',
            enabled: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
          ),
          KnowledgeBase(
            id: 'disabled-base',
            name: 'Disabled base',
            enabled: false,
            sortOrder: 1,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        categories: [
          KnowledgeCategory(
            id: 'person-id',
            knowledgeBaseId: 'base',
            name: '人物',
            alias: 'person',
            annotationRule: '标注人物名',
            colorValue: 0xFF7C3AED,
            autoAnnotate: true,
            isDefault: true,
            enabled: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
          ),
          KnowledgeCategory(
            id: 'zero-color-id',
            knowledgeBaseId: 'base',
            name: '零颜色',
            alias: 'zero_color',
            colorValue: 0,
            autoAnnotate: true,
            isDefault: false,
            enabled: true,
            sortOrder: 1,
            createdAt: now,
            updatedAt: now,
          ),
          KnowledgeCategory(
            id: 'manual-id',
            knowledgeBaseId: 'base',
            name: '手动',
            alias: 'manual',
            autoAnnotate: false,
            isDefault: false,
            enabled: true,
            sortOrder: 2,
            createdAt: now,
            updatedAt: now,
          ),
          KnowledgeCategory(
            id: 'disabled-id',
            knowledgeBaseId: 'base',
            name: '禁用',
            alias: 'disabled',
            autoAnnotate: true,
            isDefault: false,
            enabled: false,
            sortOrder: 3,
            createdAt: now,
            updatedAt: now,
          ),
          KnowledgeCategory(
            id: 'disabled-base-id',
            knowledgeBaseId: 'disabled-base',
            name: '禁用知识库',
            alias: 'disabled_base',
            autoAnnotate: true,
            isDefault: false,
            enabled: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        entries: const [],
        sources: const [],
        explanations: const [],
      );
      final controller = FloatingChatSessionController(
        settings: memorySettingsProvider(),
        conversations: conversations,
        models: models,
        features: FeatureProvider(),
        knowledge: knowledge,
        tasks: TaskProvider(),
        calendar: CalendarProvider(),
        plugins: PluginProvider(),
        api: api,
      );
      try {
        await controller.send('hello');
        await _waitFor(() => api.requestMessages.isNotEmpty);

        final systemMessages = api.requestMessages.single
            .where((message) => message['role'] == 'system')
            .toList();
        expect(systemMessages, hasLength(1));
        expect(systemMessages.single['content'], contains('[[category:text]]'));
        expect(systemMessages.single['content'], contains('person'));
        expect(controller.stateJson()['defaultKnowledgeCategory'], 'person-id');
        final categories =
            controller.stateJson()['knowledgeCategories']
                as Map<String, dynamic>;
        expect(categories.keys, {
          'person-id',
          'person',
          'zero-color-id',
          'zero_color',
        });
        expect(categories['person'], {
          'id': 'person-id',
          'colorValue': 0xFF7C3AED,
        });
        expect(categories['person-id'], categories['person']);
        expect(categories['zero_color'], {
          'id': 'zero-color-id',
          'colorValue': 0,
        });
        expect(categories, isNot(contains('人物')));
        expect(categories, isNot(contains('manual')));
        expect(categories, isNot(contains('disabled')));
        expect(categories, isNot(contains('disabled_base')));
      } finally {
        controller.stop();
        await controller.dispose();
        for (final stream in api.streams) {
          await stream.close();
        }
      }
    },
  );

  test('stop ignores model events that arrive after cancellation', () async {
    final api = _FakeApiService();
    final conversations = memoryConversationProvider();
    final models = memoryModelConfigProvider();
    models.addModel(_model());
    final controller = FloatingChatSessionController(
      settings: memorySettingsProvider(),
      conversations: conversations,
      models: models,
      features: FeatureProvider(),
      knowledge: KnowledgeProvider(),
      tasks: TaskProvider(),
      calendar: CalendarProvider(),
      plugins: PluginProvider(),
      api: api,
    );
    try {
      await controller.send('hello');
      await _waitFor(() => api.streams.isNotEmpty);
      api.streams.single.add(const StreamChunk(content: 'partial'));
      await _waitFor(() => controller.stateJson()['draft'] == 'partial');

      controller.stop();
      api.streams.single.add(const StreamChunk(content: 'late'));
      api.streams.single.add(const StreamChunk(isDone: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final conversation = conversations.getConversation(
        controller.conversationId!,
      )!;
      expect(controller.isStreaming, isFalse);
      await _waitFor(
        () => conversation.messages.last.content == 'partial\n\n---\n已停止生成',
      );
      expect(conversation.messages.last.content, 'partial\n\n---\n已停止生成');
      expect(controller.stateJson()['draft'], 'partial');
    } finally {
      await controller.dispose();
      for (final stream in api.streams) {
        await stream.close();
      }
    }
  });

  test('projects broker pending state and accepts a scoped answer', () async {
    final broker = AgentUserInteractionBroker();
    final controller = FloatingChatSessionController(
      settings: memorySettingsProvider(),
      conversations: memoryConversationProvider(),
      models: memoryModelConfigProvider(),
      features: FeatureProvider(),
      knowledge: KnowledgeProvider(),
      tasks: TaskProvider(),
      calendar: CalendarProvider(),
      plugins: PluginProvider(),
      userInteractionBroker: broker,
    );
    try {
      final resultFuture = broker.ask(
        surface: AgentUserInteractionSurface.floatingAssistant,
        identity: const AgentUserInteractionIdentity(
          runId: 'run',
          turnId: 'turn',
          toolCallId: 'call',
          toolName: 'ask_user',
        ),
        question: AgentUserQuestion(
          kind: AgentUserQuestionKind.singleChoice,
          prompt: 'Choose',
          choices: const [AgentUserChoice(id: 'a', label: 'A')],
        ),
      );
      final pending = controller.stateJson()['pendingUserInteraction'] as Map;

      expect(pending['identity']['toolCallId'], 'call');
      expect(
        controller.answerUserInteraction(
          requestId: pending['id'] as String,
          answer: AgentUserAnswer.singleChoice('a'),
        ),
        AgentUserInteractionResponseStatus.accepted,
      );
      expect((await resultFuture).answer!.choiceIds, ['a']);
      expect(controller.stateJson()['pendingUserInteraction'], isNull);
    } finally {
      await controller.dispose();
      broker.dispose();
    }
  });

  test('stop clears only floating pending interactions', () async {
    final broker = AgentUserInteractionBroker();
    final controller = FloatingChatSessionController(
      settings: memorySettingsProvider(),
      conversations: memoryConversationProvider(),
      models: memoryModelConfigProvider(),
      features: FeatureProvider(),
      knowledge: KnowledgeProvider(),
      tasks: TaskProvider(),
      calendar: CalendarProvider(),
      plugins: PluginProvider(),
      userInteractionBroker: broker,
    );
    try {
      final floating = broker.ask(
        surface: AgentUserInteractionSurface.floatingAssistant,
        identity: const AgentUserInteractionIdentity(
          runId: 'floating-run',
          turnId: 'floating-turn',
          toolCallId: 'floating-call',
          toolName: 'ask_user',
        ),
        question: AgentUserQuestion(
          kind: AgentUserQuestionKind.confirm,
          prompt: 'Floating?',
        ),
      );
      final main = broker.ask(
        surface: AgentUserInteractionSurface.mainChat,
        identity: const AgentUserInteractionIdentity(
          runId: 'main-run',
          turnId: 'main-turn',
          toolCallId: 'main-call',
          toolName: 'ask_user',
        ),
        question: AgentUserQuestion(
          kind: AgentUserQuestionKind.confirm,
          prompt: 'Main?',
        ),
      );

      controller.stop();

      expect((await floating).outcome, AgentUserInteractionOutcome.cancelled);
      expect(
        broker.pendingFor(AgentUserInteractionSurface.floatingAssistant),
        isNull,
      );
      final mainRequest = broker.pendingFor(
        AgentUserInteractionSurface.mainChat,
      );
      expect(mainRequest, isNotNull);
      broker.cancel(
        surface: AgentUserInteractionSurface.mainChat,
        requestId: mainRequest!.id,
      );
      await main;
    } finally {
      await controller.dispose();
      broker.dispose();
    }
  });

  test('ask_user answer continues the floating Agent run end to end', () async {
    final api = _AskUserApiService();
    final settings = memorySettingsProvider();
    await settings.replaceSettings(
      AppSettings.defaults().copyWith(
        agentEnabledByDefault: true,
        agentGrantedPermissions: const [LynAIPermissions.networkAccess],
      ),
    );
    final conversations = memoryConversationProvider();
    final models = memoryModelConfigProvider()..addModel(_model());
    final controller = FloatingChatSessionController(
      settings: settings,
      conversations: conversations,
      models: models,
      features: FeatureProvider(),
      knowledge: KnowledgeProvider(),
      tasks: TaskProvider(),
      calendar: CalendarProvider(),
      plugins: PluginProvider(),
      api: api,
    );
    try {
      await controller.send('hello');
      await _waitFor(
        () => controller.stateJson()['pendingUserInteraction'] != null,
      );
      final pending =
          controller.stateJson()['pendingUserInteraction']
              as Map<String, dynamic>;
      expect(
        controller.answerUserInteraction(
          requestId: pending['id'] as String,
          answer: AgentUserAnswer.singleChoice('a'),
        ),
        AgentUserInteractionResponseStatus.accepted,
      );
      await _waitFor(() => !controller.isStreaming);

      final conversation = conversations.getConversation(
        controller.conversationId!,
      )!;
      expect(conversation.settings.agentEnabled, isTrue);
      expect(conversation.settings.agentGrantedPermissions, const [
        LynAIPermissions.networkAccess,
      ]);
      expect(conversation.messages.last.content, 'continued');
      expect(api.requests, 2);
    } finally {
      await controller.dispose();
    }
  });
}

ModelConfig _model() {
  return ModelConfig(
    id: 'model',
    name: 'Model',
    endpoint: 'https://example.com',
    apiKey: 'key',
    modelName: 'test-model',
    apiType: 'openai',
    priority: 0,
    extraParams: const {'supportsNativeTools': true, 'supportsThinking': true},
  );
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
