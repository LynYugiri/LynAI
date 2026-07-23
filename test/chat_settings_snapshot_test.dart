import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/models/system_prompt.dart';
import 'package:lynai/pages/chat_page.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/services/api_service.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/tool_call_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_repositories.dart';

class _RepeatingToolApi extends ApiService {
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
    yield StreamChunk(content: 'working $requests');
    yield StreamChunk(
      toolCalls: [
        ChatToolCall(
          id: 'call_$requests',
          name: 'get_current_time',
          arguments: const {},
        ),
      ],
      isDone: true,
    );
  }
}

class _CapturingApi extends ApiService {
  List<Map<String, dynamic>>? messages;

  @override
  Stream<StreamChunk> sendStreamRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
    List<Map<String, dynamic>> tools = const [],
    Object? toolChoice,
  }) async* {
    this.messages = messages;
    yield StreamChunk(content: 'reply', isDone: true);
  }
}

void main() {
  testWidgets(
    'loading historical conversation does not change global settings',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final conversations = memoryConversationProvider();
      final settings = memorySettingsProvider();
      await settings.replaceSettings(
        AppSettings.defaults().copyWith(
          systemPrompt: 'global prompt',
          imageRecognitionPrompt: 'global image prompt',
          lastChatModelId: 'global-model',
        ),
      );
      final before = settings.settings.toJson();
      final conversationId = conversations.createConversation(
        ConversationSettings(
          modelId: 'historical-model',
          systemPrompt: 'historical prompt',
          imageRecognitionPrompt: 'historical image prompt',
          imageRecognitionEnabled: true,
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: conversations),
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider(create: (_) => FeatureProvider()),
            ChangeNotifierProvider(create: (_) => TaskProvider()),
            ChangeNotifierProvider(create: (_) => CalendarProvider()),
            ChangeNotifierProvider(create: (_) => ModelConfigProvider()),
            ChangeNotifierProvider(create: (_) => PluginProvider()),
            ChangeNotifierProvider(create: (_) => BackendClient()),
          ],
          child: MaterialApp(home: ChatPage(conversationId: conversationId)),
        ),
      );
      await tester.pump();

      expect(settings.settings.toJson(), before);
      await tester.pump(const Duration(milliseconds: 500));
      await conversations.flushPendingSaves();
    },
  );

  testWidgets('historical API messages use the conversation prompt snapshot', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = _CapturingApi();
    final conversations = memoryConversationProvider();
    final settings = memorySettingsProvider();
    await settings.replaceSettings(
      AppSettings.defaults().copyWith(
        systemPrompt: 'current global prompt',
        selectedSystemPromptId: 'prompt-1',
        systemPrompts: [
          SystemPrompt(
            id: 'prompt-1',
            title: 'Current',
            content: 'current global prompt',
          ),
        ],
      ),
    );
    final models = memoryModelConfigProvider()
      ..addModel(
        ModelConfig(
          id: 'm1',
          name: 'test',
          endpoint: 'https://example.test',
          apiKey: '',
          modelName: 'model',
          apiType: 'openai',
          priority: 0,
        ),
      );
    final conversationId = conversations.createConversation(
      ConversationSettings(
        modelId: 'm1',
        selectedSystemPromptId: 'prompt-1',
        systemPrompt: 'historical snapshot prompt',
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: conversations),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: models),
          ChangeNotifierProvider(create: (_) => FeatureProvider()),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
          ChangeNotifierProvider(create: (_) => CalendarProvider()),
          ChangeNotifierProvider(create: (_) => PluginProvider()),
          ChangeNotifierProvider(create: (_) => BackendClient()),
        ],
        child: MaterialApp(
          home: ChatPage(conversationId: conversationId, api: api),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'continue');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    for (var i = 0; i < 20 && api.messages == null; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(api.messages, isNotNull);
    expect(api.messages!.first['role'], 'system');
    expect(
      api.messages!.first['content'],
      startsWith('historical snapshot prompt'),
    );
    expect(
      api.messages!.first['content'],
      isNot(contains('current global prompt')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await conversations.flushPendingSaves();
  });

  testWidgets('main Agent stops consecutive tool calls at the shared limit', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = _RepeatingToolApi();
    final conversations = memoryConversationProvider();
    final settings = memorySettingsProvider();
    final models = memoryModelConfigProvider()
      ..addModel(
        ModelConfig(
          id: 'm1',
          name: 'test',
          endpoint: 'https://example.test',
          apiKey: '',
          modelName: 'model',
          apiType: 'openai',
          priority: 0,
        ),
      );
    final conversationId = conversations.createConversation(
      ConversationSettings(modelId: 'm1'),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: conversations),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: models),
          ChangeNotifierProvider(create: (_) => FeatureProvider()),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
          ChangeNotifierProvider(create: (_) => CalendarProvider()),
          ChangeNotifierProvider(create: (_) => PluginProvider()),
          ChangeNotifierProvider(create: (_) => BackendClient()),
        ],
        child: MaterialApp(
          home: ChatPage(conversationId: conversationId, api: api),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'run tools');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));

    for (
      var i = 0;
      i < 100 && api.requests <= ToolCallService.maxToolRounds;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(api.requests, ToolCallService.maxToolRounds + 1);
    expect(
      conversations.getConversation(conversationId)!.messages.last.content,
      allOf(contains('working 13'), contains('12 轮上限')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await conversations.flushPendingSaves();
  });
}
