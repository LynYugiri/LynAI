import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/model_catalog.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/pages/chat_page.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/jotting_provider.dart';
import 'package:lynai/providers/knowledge_provider.dart';
import 'package:lynai/providers/memory_card_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/services/api_service.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_repositories.dart';

/// 思考强度只影响请求组装，这里只要拿到一次请求即可。
class _CapturingApi extends ApiService {
  int requests = 0;
  String? lastEffort;

  @override
  Stream<StreamChunk> sendStreamRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
    String? reasoningEffort,
    List<Map<String, dynamic>> tools = const [],
    Object? toolChoice,
  }) async* {
    requests++;
    lastEffort = config.resolveReasoningEffort(reasoningEffort);
    yield StreamChunk(content: 'reply', isDone: true);
  }
}

ModelCatalogHint _effortHint() {
  return ModelCatalogHint(
    providerId: 'openai',
    modelId: 'gpt-4o',
    supportsThinking: true,
    supportsTools: true,
    reasoningOptions: const [
      ModelCatalogReasoningOption(
        kind: ModelCatalogReasoningKind.effort,
        values: ['low', 'medium', 'high'],
      ),
    ],
  );
}

ModelConfigProvider _modelsWithCatalogEffort() {
  return memoryModelConfigProvider()
    ..addModel(
      ModelConfig(
        id: 'm1',
        name: 'OpenAI',
        endpoint: 'https://api.openai.com/v1',
        apiKey: '',
        modelName: 'gpt-4o',
        apiType: 'openai',
        priority: 0,
        models: [
          ModelEntry(name: 'gpt-4o', enabled: true, catalog: _effortHint()),
        ],
      ),
    );
}

void main() {
  late Directory storageRoot;
  late StorageV2Service storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storageRoot = await Directory.systemTemp.createTemp('lynai_effort_ui_');
    storage = StorageV2Service(rootDirectory: storageRoot);
    await StorageV2UpgradeService(storageV2: storage).ensureReady();
  });

  tearDown(() async {
    await storage.close();
    await storageRoot.delete(recursive: true);
  });

  Future<void> pumpChat(
    WidgetTester tester, {
    required ConversationProvider conversations,
    required ModelConfigProvider models,
    required _CapturingApi api,
    String? conversationId,
  }) async {
    await tester.binding.setSurfaceSize(const Size(500, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: conversations),
          ChangeNotifierProvider.value(value: memorySettingsProvider()),
          ChangeNotifierProvider.value(value: memoryWorkspaceProvider()),
          ChangeNotifierProvider.value(value: models),
          ChangeNotifierProvider(create: (_) => FeatureProvider()),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
          ChangeNotifierProvider(create: (_) => CalendarProvider()),
          ChangeNotifierProvider(create: (_) => PluginProvider()),
          ChangeNotifierProvider(create: (_) => KnowledgeProvider()),
          ChangeNotifierProvider(create: (_) => MemoryCardProvider()),
          ChangeNotifierProvider(create: (_) => JottingProvider()),
          ChangeNotifierProvider.value(value: memoryRoleMemoryProvider()),
          ChangeNotifierProvider(create: (_) => BackendClient()),
          Provider.value(value: storage),
        ],
        child: MaterialApp(
          home: ChatPage(conversationId: conversationId, api: api),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 思考按钮（一个控件同时表达开关与强度，提示气泡是「思考：关/默认/档位」）。
  Finder thinkingButton() => find.byWidgetPredicate(
    (widget) => widget is Tooltip && (widget.message ?? '').startsWith('思考：'),
  );

  Future<void> selectEffort(WidgetTester tester, String value) async {
    await tester.tap(thinkingButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text(value).last);
    await tester.pumpAndSettle();
  }

  testWidgets('新对话里选的思考强度会写进随后创建的对话', (tester) async {
    final api = _CapturingApi();
    final models = _modelsWithCatalogEffort();
    final conversations = memoryConversationProvider();
    await pumpChat(
      tester,
      conversations: conversations,
      models: models,
      api: api,
    );

    // 目录给了 effort 取值时列表里出现档位。
    expect(thinkingButton(), findsOneWidget);
    await selectEffort(tester, 'high');
    expect(find.byTooltip('思考：high'), findsOneWidget);

    // 发送后才会创建对话：新对话必须带上刚选的强度。
    await tester.enterText(find.byType(TextField).first, '你好');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    for (var i = 0; i < 20 && api.requests == 0; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(conversations.conversations, hasLength(1));
    expect(conversations.conversations.single.settings.reasoningEffort, 'high');
    expect(api.lastEffort, 'high');
    await tester.pump(const Duration(milliseconds: 500));
    await conversations.flushPendingSaves();
  });

  testWidgets('切换对话会重新载入各自的思考强度', (tester) async {
    final api = _CapturingApi();
    final models = _modelsWithCatalogEffort();
    final conversations = memoryConversationProvider();
    final withEffort = conversations.createConversation(
      ConversationSettings(modelId: 'm1', reasoningEffort: 'low'),
    );
    final withoutEffort = conversations.createConversation(
      ConversationSettings(modelId: 'm1'),
    );

    await pumpChat(
      tester,
      conversations: conversations,
      models: models,
      api: api,
      conversationId: withEffort,
    );
    expect(find.byTooltip('思考：low'), findsOneWidget);

    await pumpChat(
      tester,
      conversations: conversations,
      models: models,
      api: api,
      conversationId: withoutEffort,
    );
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('思考：默认'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await conversations.flushPendingSaves();
  });
}
