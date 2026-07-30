import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/knowledge_base.dart';
import 'package:lynai/models/knowledge_category.dart';
import 'package:lynai/models/knowledge_entry.dart';
import 'package:lynai/models/knowledge_explanation.dart';
import 'package:lynai/models/knowledge_source.dart';
import 'package:lynai/pages/feature_page.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/knowledge_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/repositories/knowledge_repository.dart';
import 'package:provider/provider.dart';

import 'support/memory_repositories.dart';

void main() {
  testWidgets('knowledge page has no user default settings controls', (
    tester,
  ) async {
    final provider = await _knowledgeProvider(withSecondaryDefaultBase: true);
    await _pumpKnowledge(tester, provider, size: const Size(500, 800));

    expect(find.byTooltip('默认设置'), findsNothing);
    expect(find.text('设为默认'), findsNothing);
  });

  testWidgets('compact base selector follows an externally removed base', (
    tester,
  ) async {
    final provider = await _knowledgeProvider(withSecondaryDefaultBase: true);
    await _pumpKnowledge(tester, provider, size: const Size(500, 800));

    await provider.replaceAll(
      knowledgeBases: provider.knowledgeBases
          .where((base) => base.id == 'base')
          .toList(),
      categories: provider.categories
          .where((category) => category.knowledgeBaseId == 'base')
          .toList(),
      entries: provider.entries
          .where((entry) => entry.knowledgeBaseId == 'base')
          .toList(),
      sources: const [],
      explanations: const [],
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final dropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(dropdown.initialValue, 'base');
    expect(find.text('Markdown 条目'), findsOneWidget);
  });

  testWidgets('duplicate alias validation keeps category form open', (
    tester,
  ) async {
    final provider = await _knowledgeProvider();
    await _pumpKnowledge(tester, provider);

    await tester.tap(find.byTooltip('管理类别'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建类别'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '名称'), '重复类别');
    await tester.enterText(find.widgetWithText(TextField, 'alias'), 'person');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();

    expect(find.text('alias 已被其他类别使用'), findsOneWidget);
    expect(find.text('新建类别'), findsOneWidget);
    expect(provider.categories, hasLength(3));
  });

  testWidgets('compact detail has explicit return to entry list', (
    tester,
  ) async {
    final provider = await _knowledgeProvider();
    await _pumpKnowledge(tester, provider, size: const Size(500, 800));

    await tester.tap(find.text('Markdown 条目'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回条目列表'), findsOneWidget);
    expect(find.text('来源'), findsOneWidget);

    await tester.tap(find.byTooltip('返回条目列表'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回条目列表'), findsNothing);
    expect(find.text('搜索标题或内容'), findsOneWidget);
  });

  testWidgets('compact system back returns to entry list', (tester) async {
    final provider = await _knowledgeProvider();
    await _pumpKnowledge(tester, provider, size: const Size(500, 800));

    await tester.tap(find.text('Markdown 条目'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回条目列表'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回条目列表'), findsNothing);
    expect(find.text('搜索标题或内容'), findsOneWidget);
  });

  testWidgets('deleting the filtered category clears the filter', (
    tester,
  ) async {
    final provider = await _knowledgeProvider();
    await _pumpKnowledge(tester, provider, size: const Size(1200, 800));
    await _selectPersonFilter(tester);

    await tester.tap(find.byTooltip('管理类别'));
    await tester.pumpAndSettle();
    final personTile = find.widgetWithText(ListTile, '人物');
    await tester.tap(
      find.descendant(of: personTile, matching: find.byTooltip('删除')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '完成'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_categoryDropdown(tester).value, isNull);
    expect(find.text('Markdown 条目'), findsWidgets);
  });

  testWidgets('externally removing the filtered category clears the filter', (
    tester,
  ) async {
    final provider = await _knowledgeProvider();
    await _pumpKnowledge(tester, provider, size: const Size(1200, 800));
    await _selectPersonFilter(tester);

    final now = DateTime(2026, 7, 30);
    await provider.replaceAll(
      knowledgeBases: provider.knowledgeBases,
      categories: provider.categories
          .where((category) => category.id != 'person')
          .toList(),
      entries: [
        provider.entries.single.copyWith(categoryId: null, updatedAt: now),
      ],
      sources: provider.sources,
      explanations: provider.explanations,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_categoryDropdown(tester).value, isNull);
    expect(find.text('Markdown 条目'), findsWidgets);
  });

  testWidgets('entry editor updates title and enabled state', (tester) async {
    final provider = await _knowledgeProvider();
    await _pumpKnowledge(tester, provider, size: const Size(1200, 800));

    await tester.tap(find.byTooltip('编辑条目'));
    await tester.pumpAndSettle();
    final titleField = find.widgetWithText(TextField, '标题');
    await tester.enterText(titleField, '编辑后的条目');
    await tester.tap(find.widgetWithText(SwitchListTile, '启用'));
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(provider.entries.single.title, '编辑后的条目');
    expect(provider.entries.single.enabled, isFalse);
    expect(find.text('编辑后的条目'), findsWidgets);
  });

  testWidgets('entry selection keeps details without selected card styling', (
    tester,
  ) async {
    final provider = await _knowledgeProvider();
    await _pumpKnowledge(tester, provider, size: const Size(1200, 800));

    await tester.tap(find.text('Markdown 条目').first);
    await tester.pumpAndSettle();

    final tile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Markdown 条目').first,
        matching: find.byType(ListTile),
      ),
    );
    expect(tile.selected, isFalse);
    expect(find.text('来源'), findsOneWidget);
  });
}

Future<KnowledgeProvider> _knowledgeProvider({
  bool withSecondaryDefaultBase = false,
}) async {
  final provider = KnowledgeProvider(repository: _MemoryKnowledgeRepository());
  final now = DateTime(2026, 7, 29);
  await provider.replaceAll(
    knowledgeBases: [
      KnowledgeBase(
        id: 'base',
        name: '主知识库',
        description: '测试知识库',
        enabled: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
      if (withSecondaryDefaultBase)
        KnowledgeBase(
          id: 'default-base',
          name: '默认知识库',
          description: '非首项知识库',
          enabled: true,
          sortOrder: 1,
          createdAt: now,
          updatedAt: now,
        ),
    ],
    categories: [
      KnowledgeCategory(
        id: 'person',
        knowledgeBaseId: 'base',
        name: '人物',
        alias: 'person',
        annotationRule: '标注人物名称',
        autoAnnotate: true,
        enabled: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
      if (withSecondaryDefaultBase)
        KnowledgeCategory(
          id: 'default-category',
          knowledgeBaseId: 'default-base',
          name: '默认类别',
          alias: 'default-category',
          autoAnnotate: true,
          enabled: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      KnowledgeCategory(
        id: 'disabled',
        knowledgeBaseId: 'base',
        name: '停用类别',
        alias: 'disabled',
        autoAnnotate: true,
        enabled: false,
        sortOrder: 1,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    entries: [
      KnowledgeEntry(
        id: 'entry',
        knowledgeBaseId: 'base',
        categoryId: 'person',
        title: 'Markdown 条目',
        content: r'**正文** 和 $x^2$',
        enabled: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
      if (withSecondaryDefaultBase)
        KnowledgeEntry(
          id: 'default-entry',
          knowledgeBaseId: 'default-base',
          categoryId: 'default-category',
          title: '默认知识库条目',
          content: '默认内容',
          enabled: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
    ],
    sources: const [],
    explanations: const [],
  );
  return provider;
}

Future<void> _pumpKnowledge(
  WidgetTester tester,
  KnowledgeProvider knowledge, {
  Size size = const Size(800, 800),
  void Function(bool Function() handler)? onBackHandlerChanged,
}) async {
  final settings = memorySettingsProvider();
  bool Function()? backHandler;
  await settings.replaceSettings(
    settings.settings.copyWith(lastFeature: 'knowledge'),
  );
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: knowledge),
        ChangeNotifierProvider(create: (_) => ModelConfigProvider()),
        ChangeNotifierProvider(create: (_) => FeatureProvider()),
        ChangeNotifierProvider(create: (_) => PluginProvider()),
      ],
      child: MaterialApp(
        home: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) backHandler?.call();
          },
          child: FeaturePage(
            onConversationTap: (_) {},
            onBackHandlerChanged: (handler) {
              backHandler = handler;
              onBackHandlerChanged?.call(handler);
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _selectPersonFilter(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButton<String?>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('人物').last);
  await tester.pumpAndSettle();
  expect(_categoryDropdown(tester).value, 'person');
}

DropdownButton<String?> _categoryDropdown(WidgetTester tester) => tester
    .widget<DropdownButton<String?>>(find.byType(DropdownButton<String?>));

final class _MemoryKnowledgeRepository extends KnowledgeRepository {
  @override
  Future<KnowledgeLoadResult> load() async => const KnowledgeLoadResult(
    bases: [],
    categories: [],
    entries: [],
    sources: [],
    explanations: [],
  );

  @override
  Future<void> replace(KnowledgeLoadResult value) async {}

  @override
  Future<void> saveChanges({
    Iterable<KnowledgeBase> upsertBases = const [],
    Iterable<String> deleteBaseIds = const [],
    Iterable<KnowledgeCategory> upsertCategories = const [],
    Iterable<String> deleteCategoryIds = const [],
    Iterable<KnowledgeEntry> upsertEntries = const [],
    Iterable<String> deleteEntryIds = const [],
    Iterable<KnowledgeSource> upsertSources = const [],
    Iterable<String> deleteSourceIds = const [],
    Iterable<KnowledgeExplanation> upsertExplanations = const [],
    Iterable<String> deleteExplanationIds = const [],
  }) async {}
}
