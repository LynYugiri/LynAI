import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/services/api_service.dart';
import 'package:lynai/services/floating_chat_session_controller.dart';

import '../support/memory_repositories.dart';

class _FakeApiService extends ApiService {
  final List<StreamController<StreamChunk>> streams = [];
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
      expect(conversation.messages.last.content, '已停止生成');
      expect(controller.stateJson()['draft'], 'partial');
    } finally {
      await controller.dispose();
      for (final stream in api.streams) {
        await stream.close();
      }
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
