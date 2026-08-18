import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/pages/plugin_studio_page.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/repositories/plugin_repository.dart';
import 'package:lynai/services/plugin_scaffold_service.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory root;
  late PluginProvider provider;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lynai_studio_');
    provider = PluginProvider(repository: PluginRepository(rootOverride: root));
    await provider.createPlugin(
      id: 'studio-plugin',
      name: 'Studio 插件',
      version: '0.1.0',
      author: '',
      description: '',
      kind: PluginScaffoldKind.luaTool,
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('Studio 渲染文件树与能力清单', (tester) async {
    // 宽屏进入两栏布局，右侧检查器用非懒加载 Column 渲染全部卡片，便于断言。
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // 文件树/恢复点依赖异步文件 I/O，在 testWidgets 的 FakeAsync 下不会完成，
    // 因此只做一次 pump 并断言同步可用的内容，避免 pumpAndSettle 因进度动画挂起。
    await tester.pumpWidget(
      ChangeNotifierProvider<PluginProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: PluginStudioPage(pluginId: 'studio-plugin'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Studio 插件 · 插件工坊'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('能力速览'), findsOneWidget);
    // luaTool 模板声明了一个 hello 工具。
    expect(find.text('工具 (tools) · 1'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
  });
}
