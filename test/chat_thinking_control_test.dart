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
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_repositories.dart';

ModelCatalogHint _hint({
  required String providerId,
  List<ModelCatalogReasoningOption> options = const [],
  bool reasoning = true,
}) {
  return ModelCatalogHint(
    providerId: providerId,
    modelId: 'model',
    contextWindow: 128000,
    supportsVision: true,
    supportsTools: true,
    supportsThinking: reasoning,
    reasoningOptions: options,
  );
}

const _effortOption = ModelCatalogReasoningOption(
  kind: ModelCatalogReasoningKind.effort,
  values: ['low', 'medium', 'high'],
);

const _budgetOnlyOption = ModelCatalogReasoningOption(
  kind: ModelCatalogReasoningKind.budgetTokens,
  minBudgetTokens: 1024,
);

void main() {
  late Directory storageRoot;
  late StorageV2Service storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storageRoot = await Directory.systemTemp.createTemp('lynai_thinking_');
    storage = StorageV2Service(rootDirectory: storageRoot);
    await StorageV2UpgradeService(storageV2: storage).ensureReady();
  });

  tearDown(() async {
    await storage.close();
    await storageRoot.delete(recursive: true);
  });

  Future<(ConversationProvider, ModelConfigProvider, String)> pumpChat(
    WidgetTester tester, {
    required String apiType,
    required ModelCatalogHint hint,
  }) async {
    await tester.binding.setSurfaceSize(const Size(500, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final conversations = memoryConversationProvider();
    final models = memoryModelConfigProvider()
      ..addModel(
        ModelConfig(
          id: 'm1',
          name: 'test',
          endpoint: apiType == 'anthropic'
              ? 'https://api.anthropic.com'
              : 'https://api.openai.com/v1',
          apiKey: 'key',
          modelName: 'model',
          apiType: apiType,
          priority: 0,
          models: [
            ModelEntry(name: 'model', enabled: true, catalog: hint),
          ],
        ),
      );
    final conversationId = conversations.createConversation(
      ConversationSettings(modelId: 'm1'),
    );
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
          home: ChatPage(conversationId: conversationId),
        ),
      ),
    );
    await tester.pump();
    return (conversations, models, conversationId);
  }

  Future<void> finish(WidgetTester tester, ConversationProvider c) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
    await c.flushPendingSaves();
  }

  testWidgets('思考按钮点开列表可选 关 / 默认 / 强度档位', (tester) async {
    final (conversations, _, cid) = await pumpChat(
      tester,
      apiType: 'openai',
      hint: _hint(providerId: 'openai', options: const [_effortOption]),
    );

    // 默认状态：开启思考但不指定强度。
    expect(find.byTooltip('思考：默认'), findsOneWidget);

    await tester.tap(find.byTooltip('思考：默认'));
    await tester.pumpAndSettle();
    expect(find.text('关'), findsOneWidget);
    expect(find.text('默认'), findsOneWidget);
    for (final value in ['low', 'medium', 'high']) {
      expect(find.text(value), findsOneWidget);
    }

    await tester.tap(find.text('medium'));
    await tester.pumpAndSettle();
    var settings = conversations.getConversation(cid)!.settings;
    expect(settings.thinking, isTrue);
    expect(settings.reasoningEffort, 'medium');
    expect(find.byTooltip('思考：medium'), findsOneWidget);

    await tester.tap(find.byTooltip('思考：medium'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关'));
    await tester.pumpAndSettle();
    settings = conversations.getConversation(cid)!.settings;
    expect(settings.thinking, isFalse);
    expect(settings.reasoningEffort, isNull);
    expect(find.byTooltip('思考：关'), findsOneWidget);

    await finish(tester, conversations);
  });

  testWidgets('预算型模型（目录只给 budget_tokens）也提供档位并标注预算', (tester) async {
    final (conversations, _, _) = await pumpChat(
      tester,
      apiType: 'anthropic',
      hint: _hint(providerId: 'anthropic', options: const [_budgetOnlyOption]),
    );

    await tester.tap(find.byTooltip('思考：默认'));
    await tester.pumpAndSettle();
    expect(find.text('low'), findsOneWidget);
    expect(find.text('medium'), findsOneWidget);
    expect(find.text('high'), findsOneWidget);
    expect(find.text('思考预算约 8k token'), findsOneWidget);

    await finish(tester, conversations);
  });

  testWidgets('只有 toggle 的模型不给档位，只保留 关 / 默认', (tester) async {
    final (conversations, _, _) = await pumpChat(
      tester,
      apiType: 'openai',
      hint: _hint(
        providerId: 'openai',
        options: const [
          ModelCatalogReasoningOption(kind: ModelCatalogReasoningKind.toggle),
        ],
      ),
    );

    await tester.tap(find.byTooltip('思考：默认'));
    await tester.pumpAndSettle();
    expect(find.text('关'), findsOneWidget);
    expect(find.text('默认'), findsOneWidget);
    expect(find.text('low'), findsNothing);

    await finish(tester, conversations);
  });

  testWidgets('OpenAI 兼容的预算型模型不做档位猜测', (tester) async {
    final (conversations, models, _) = await pumpChat(
      tester,
      apiType: 'openai',
      hint: _hint(providerId: 'siliconflow', options: const [_budgetOnlyOption]),
    );

    expect(models.models.single.effectiveReasoningEffortValues, isEmpty);
    await tester.tap(find.byTooltip('思考：默认'));
    await tester.pumpAndSettle();
    expect(find.text('low'), findsNothing);

    await finish(tester, conversations);
  });
}
