import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:lynai/models/jotting.dart';
import 'package:lynai/pages/feature_page.dart';
import 'package:lynai/pages/features/jotting_detail_page.dart';
import 'package:lynai/pages/features/jottings_page.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/jotting_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/repositories/jotting_repository.dart';
import 'package:lynai/widgets/latex_renderer.dart';

import 'support/memory_repositories.dart';

void main() {
  testWidgets('随记页无新建加号且显示顶部编写入口', (tester) async {
    final settings = memorySettingsProvider();
    await settings.replaceSettings(
      settings.settings.copyWith(lastFeature: 'jottings'),
    );
    final jottings = _provider(_MemoryJottingRepository());

    await _withPhoneSurface(tester, () async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: jottings),
            ChangeNotifierProvider(create: (_) => FeatureProvider()),
            ChangeNotifierProvider(create: (_) => PluginProvider()),
          ],
          child: MaterialApp(home: FeaturePage(onConversationTap: (_) {})),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.text('记下此刻的想法…'), findsOneWidget);
      expect(find.textContaining('点击右上角 +'), findsNothing);
    });
  });

  testWidgets('时间线卡片只渲染一次 Markdown 正文', (tester) async {
    final repository = _MemoryJottingRepository();
    final provider = _provider(repository);
    await provider.add(
      '# 今日随记\n\n这是正文内容',
      tags: ['灵感'],
      createdAt: DateTime(2026, 8, 17, 9, 42),
    );
    final searchController = TextEditingController();
    addTearDown(searchController.dispose);

    await _withPhoneSurface(tester, () async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: JottingsPage(
                searchController: searchController,
                searchQuery: '',
                onSearchChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MarkdownWithLatex), findsOneWidget);
      expect(find.text('今日随记', findRichText: true), findsOneWidget);
      expect(find.text('这是正文内容', findRichText: true), findsOneWidget);
      expect(find.textContaining('# 今日随记'), findsNothing);
      expect(find.text('#灵感'), findsOneWidget);
    });
  });

  testWidgets('顶部编写入口打开全屏编辑器且取消返回时间线', (tester) async {
    final provider = _provider(_MemoryJottingRepository());

    await _withPhoneSurface(tester, () async {
      await tester.pumpWidget(_JottingsHarness(provider: provider));
      await tester.pumpAndSettle();

      await tester.tap(find.text('记下此刻的想法…'));
      await tester.pumpAndSettle();

      expect(find.text('新随记'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '完成'), findsOneWidget);
      expect(find.byTooltip('插入笔记'), findsOneWidget);

      await tester.tap(find.byTooltip('取消新建'));
      await tester.pumpAndSettle();

      expect(find.text('记下此刻的想法…'), findsOneWidget);
      expect(find.text('随记不存在或已删除'), findsNothing);
    });
  });

  testWidgets('保存失败保留编辑内容并留在编辑器', (tester) async {
    final repository = _MemoryJottingRepository()
      ..saveError = StateError('disk');
    final provider = _provider(repository);

    await _withPhoneSurface(tester, () async {
      await tester.pumpWidget(_JottingsHarness(provider: provider));
      await tester.pumpAndSettle();

      await tester.tap(find.text('记下此刻的想法…'));
      await tester.pumpAndSettle();
      final contentField = find.byKey(const ValueKey('jotting-editor-content'));
      await tester.enterText(contentField, '保存失败也不能丢失');
      await tester.tap(find.widgetWithText(FilledButton, '完成'));
      await tester.pumpAndSettle();

      expect(find.textContaining('保存失败，已保留编辑内容'), findsOneWidget);
      expect(find.text('新随记'), findsOneWidget);
      expect(
        tester.widget<TextField>(contentField).controller?.text,
        '保存失败也不能丢失',
      );
      expect(provider.jottings, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('新建保存成功后返回时间线并显示新卡片', (tester) async {
    final provider = _provider(_MemoryJottingRepository());

    await _withPhoneSurface(tester, () async {
      await tester.pumpWidget(_JottingsHarness(provider: provider));
      await tester.pumpAndSettle();

      await tester.tap(find.text('记下此刻的想法…'));
      await tester.pumpAndSettle();
      final contentField = find.byKey(const ValueKey('jotting-editor-content'));
      await tester.enterText(contentField, '第一条本地随记');
      await tester.tap(find.widgetWithText(FilledButton, '完成'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.text('第一条本地随记', findRichText: true), findsOneWidget);
      expect(find.text('新随记'), findsNothing);
      expect(provider.jottings.single.content, '第一条本地随记');
    });
  });

  testWidgets('详情页只保留一个顶部编辑入口', (tester) async {
    final provider = _provider(_MemoryJottingRepository());
    final id = await provider.add(
      '详情内容',
      tags: const ['生活'],
      createdAt: DateTime(2026, 8, 17, 9),
    );
    final item = provider.byId(id)!;

    await _withPhoneSurface(tester, () async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: JottingDetail(jotting: item, onEdit: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('编辑随记'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '编辑'), findsNothing);
      expect(find.byType(MarkdownWithLatex), findsOneWidget);
    });
  });
}

JottingProvider _provider(_MemoryJottingRepository repository) {
  return JottingProvider(
    repository: repository,
    recycleBinRepository: MemoryRecycleBinRepository(),
  );
}

Future<void> _withPhoneSurface(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  await tester.binding.setSurfaceSize(const Size(430, 860));
  try {
    await body();
  } finally {
    await tester.binding.setSurfaceSize(null);
  }
}

class _JottingsHarness extends StatefulWidget {
  const _JottingsHarness({required this.provider});

  final JottingProvider provider;

  @override
  State<_JottingsHarness> createState() => _JottingsHarnessState();
}

class _JottingsHarnessState extends State<_JottingsHarness> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.provider,
      child: MaterialApp(
        home: Scaffold(
          body: JottingsPage(
            searchController: _searchController,
            searchQuery: _searchQuery,
            onSearchChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
      ),
    );
  }
}

class _MemoryJottingRepository implements JottingRepository {
  List<Jotting> items = [];
  Object? saveError;

  @override
  Future<JottingLoadResult> load() async {
    return JottingLoadResult(jottings: List.unmodifiable(items));
  }

  @override
  Future<void> replace(JottingLoadResult value) async {
    if (saveError case final error?) throw error;
    items = List.of(value.jottings);
  }
}
