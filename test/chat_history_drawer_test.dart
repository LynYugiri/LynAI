import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/chat_role.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/pages/chat_page.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/knowledge_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_repositories.dart';

void main() {
  late Directory storageRoot;
  late StorageV2Service storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storageRoot = await Directory.systemTemp.createTemp('lynai_chat_history_');
    storage = StorageV2Service(rootDirectory: storageRoot);
    await StorageV2UpgradeService(storageV2: storage).ensureReady();
  });

  tearDown(() async {
    await storage.close();
    await storageRoot.delete(recursive: true);
  });

  testWidgets('history drawer restores its scroll offset after reopening', (
    tester,
  ) async {
    final conversations = memoryConversationProvider();
    final settings = memorySettingsProvider();
    _addConversations(conversations, roleId: ChatRole.defaultId, count: 40);
    await _pumpChat(tester, storage, conversations, settings);

    await _openHistory(tester);
    final list = _historyList();
    await tester.drag(list, const Offset(0, -900));
    await tester.pump();
    final before = _historyPosition(tester).pixels;
    expect(before, greaterThan(0));

    Scaffold.of(tester.element(list)).closeDrawer();
    await tester.pumpAndSettle();
    await _openHistory(tester);

    expect(_historyPosition(tester).pixels, closeTo(before, 1));
    await _finish(tester, conversations);
  });

  testWidgets('selecting history preserves the drawer scroll offset', (
    tester,
  ) async {
    final conversations = memoryConversationProvider();
    final settings = memorySettingsProvider();
    _addConversations(conversations, roleId: ChatRole.defaultId, count: 40);
    await _pumpChat(tester, storage, conversations, settings);

    await _openHistory(tester);
    final list = _historyList();
    await tester.drag(list, const Offset(0, -900));
    await tester.pump();
    final before = _historyPosition(tester).pixels;
    expect(before, greaterThan(0));

    final visibleConversation = find
        .descendant(of: list, matching: find.byType(ListTile))
        .evaluate()
        .map((element) => element.widget)
        .whereType<ListTile>()
        .firstWhere((tile) => tile.onTap != null);
    visibleConversation.onTap!();
    await tester.pumpAndSettle();
    await _openHistory(tester);

    expect(_historyPosition(tester).pixels, closeTo(before, 1));
    await _finish(tester, conversations);
  });

  testWidgets('role headers collapse without changing the current role', (
    tester,
  ) async {
    const otherRole = ChatRole(id: 'role-a', name: '角色 A', systemPrompt: 'A');
    final conversations = memoryConversationProvider();
    final settings = memorySettingsProvider();
    await settings.replaceSettings(
      AppSettings.defaults().copyWith(
        roles: [ChatRole.defaultRole(), otherRole],
        currentRoleId: ChatRole.defaultId,
      ),
    );
    _addConversations(
      conversations,
      roleId: ChatRole.defaultId,
      count: 2,
      prefix: '默认历史',
    );
    _addConversations(
      conversations,
      roleId: otherRole.id,
      count: 2,
      prefix: '角色历史',
    );
    await _pumpChat(tester, storage, conversations, settings);
    await _openHistory(tester);

    await tester.tap(find.byKey(const ValueKey('history-role-header-default')));
    await tester.pump();
    expect(find.textContaining('默认历史'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('history-role-header-role-a')));
    await tester.pump();
    expect(find.textContaining('角色历史'), findsNothing);
    expect(settings.settings.currentRoleId, ChatRole.defaultId);

    await tester.tap(find.byKey(const ValueKey('history-role-header-default')));
    await tester.pump();
    expect(find.textContaining('默认历史'), findsWidgets);
    await _finish(tester, conversations);
  });

  testWidgets('search temporarily expands a collapsed role', (tester) async {
    const otherRole = ChatRole(id: 'role-a', name: '角色 A', systemPrompt: 'A');
    final conversations = memoryConversationProvider();
    final settings = memorySettingsProvider();
    await settings.replaceSettings(
      AppSettings.defaults().copyWith(
        roles: [ChatRole.defaultRole(), otherRole],
        currentRoleId: ChatRole.defaultId,
      ),
    );
    _addConversations(
      conversations,
      roleId: otherRole.id,
      count: 1,
      prefix: '独特搜索词',
    );
    await _pumpChat(tester, storage, conversations, settings);
    await _openHistory(tester);

    await tester.tap(find.byKey(const ValueKey('history-role-header-role-a')));
    await tester.pump();
    expect(find.textContaining('独特搜索词'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '独特搜索词');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('独特搜索词'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('独特搜索词'), findsNothing);
    await _finish(tester, conversations);
  });
}

void _addConversations(
  ConversationProvider conversations, {
  required String roleId,
  required int count,
  String prefix = '历史记录',
}) {
  for (var index = count - 1; index >= 0; index--) {
    conversations.createConversationWithMessages(
      ConversationSettings(modelId: ''),
      roleId: roleId,
      messages: [
        (role: 'user', content: '$prefix $index', images: <MessageImage>[]),
      ],
    );
  }
}

Future<void> _pumpChat(
  WidgetTester tester,
  StorageV2Service storage,
  ConversationProvider conversations,
  SettingsProvider settings,
) async {
  await tester.binding.setSurfaceSize(const Size(500, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: conversations),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: memoryModelConfigProvider()),
        ChangeNotifierProvider(create: (_) => FeatureProvider()),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
        ChangeNotifierProvider(create: (_) => CalendarProvider()),
        ChangeNotifierProvider(create: (_) => PluginProvider()),
        ChangeNotifierProvider(create: (_) => KnowledgeProvider()),
        ChangeNotifierProvider(create: (_) => BackendClient()),
        Provider.value(value: storage),
      ],
      child: const MaterialApp(home: ChatPage()),
    ),
  );
  await tester.pump();
}

Future<void> _openHistory(WidgetTester tester) async {
  await tester.tap(find.byTooltip('历史记录'));
  await tester.pumpAndSettle();
  await tester.pump();
}

Finder _historyList() {
  return find.descendant(
    of: find.byType(Drawer),
    matching: find.byType(ListView),
  );
}

ScrollPosition _historyPosition(WidgetTester tester) {
  return tester
      .state<ScrollableState>(
        find.descendant(of: _historyList(), matching: find.byType(Scrollable)),
      )
      .position;
}

Future<void> _finish(
  WidgetTester tester,
  ConversationProvider conversations,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 500));
  await conversations.flushPendingSaves();
}
