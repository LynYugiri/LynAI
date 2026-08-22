import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/conversation_plugin_artifact.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/repositories/plugin_repository.dart';
import 'package:lynai/services/plugin_scaffold_service.dart';
import 'package:lynai/widgets/plugin_draft_card.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory root;
  late PluginProvider provider;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lynai_draft_card_');
    provider = PluginProvider(repository: PluginRepository(rootOverride: root));
    await provider.createPlugin(
      id: 'card-plugin',
      name: '卡片插件',
      version: '0.1.0',
      author: '',
      description: '',
      kind: PluginScaffoldKind.blank,
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('渲染草稿状态、文件与动作按钮', (tester) async {
    var openedStudio = false;
    var continued = false;
    await tester.pumpWidget(
      ChangeNotifierProvider<PluginProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: PluginDraftCard(
              artifact: ConversationPluginArtifact(
                pluginId: 'card-plugin',
                assistantMessageId: 'a1',
                createdAt: DateTime(2026, 1, 1),
                writtenFiles: const ['plugin.json', 'main.lua'],
              ),
              onOpenStudio: () => openedStudio = true,
              onContinueEdit: () => continued = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('卡片插件'), findsOneWidget);
    expect(find.textContaining('card-plugin · v0.1.0'), findsOneWidget);
    expect(find.text('plugin.json'), findsOneWidget);
    expect(find.text('main.lua'), findsOneWidget);

    await tester.tap(find.text('打开插件工坊'));
    await tester.tap(find.text('继续完善'));
    expect(openedStudio, isTrue);
    expect(continued, isTrue);
  });

  testWidgets('插件删除后显示删除提示且禁用工坊按钮', (tester) async {
    await tester.runAsync(() => provider.deletePlugin('card-plugin'));
    await tester.pumpWidget(
      ChangeNotifierProvider<PluginProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: PluginDraftCard(
              artifact: ConversationPluginArtifact(
                pluginId: 'card-plugin',
                createdAt: DateTime(2026, 1, 1),
              ),
              onOpenStudio: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('插件已不在本地'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('打开插件工坊'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });
}
