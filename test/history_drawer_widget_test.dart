import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/chat_role.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/pages/chat/history_drawer.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:provider/provider.dart';

import 'support/memory_repositories.dart';

void main() {
  Conversation makeConversation(String id, String title) {
    return Conversation(
      id: id,
      title: title,
      messages: [
        Message(
          id: 'm1',
          role: 'user',
          content: '你好',
          timestamp: DateTime(2026),
        ),
      ],
      modelId: 'm1',
      roleId: ChatRole.defaultId,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  Future<void> pumpDrawer(
    WidgetTester tester, {
    required ConversationProvider conversations,
    required SettingsProvider settings,
    Set<String> collapsed = const {},
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: conversations),
            ChangeNotifierProvider.value(value: settings),
          ],
          child: Scaffold(
            body: HistoryDrawer(
              onSelect: (_) {},
              scrollController: ScrollController(),
              collapsedRoleIds: collapsed,
              onToggleRole: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders conversations grouped under the current role', (tester) async {
    final conversations = memoryConversationProvider();
    final settings = memorySettingsProvider();
    await conversations.loadConversations();
    await conversations.replaceConversations([makeConversation('c1', '关于天气')]);
    await pumpDrawer(tester, conversations: conversations, settings: settings);
    await tester.pump();

    expect(find.text('历史对话'), findsOneWidget);
    expect(find.text('关于天气'), findsOneWidget);
    expect(find.text('默认'), findsWidgets);
  });

  testWidgets('collapsed role hides its conversations', (tester) async {
    final conversations = memoryConversationProvider();
    final settings = memorySettingsProvider();
    await conversations.loadConversations();
    await conversations.replaceConversations([makeConversation('c1', '被折叠的对话')]);
    await pumpDrawer(
      tester,
      conversations: conversations,
      settings: settings,
      collapsed: {ChatRole.defaultId},
    );
    await tester.pump();

    expect(find.text('被折叠的对话'), findsNothing);
    expect(find.byKey(const ValueKey('history-role-toggle-${ChatRole.defaultId}')), findsOneWidget);
  });

  testWidgets('search filters conversations by title', (tester) async {
    final conversations = memoryConversationProvider();
    final settings = memorySettingsProvider();
    await conversations.loadConversations();
    await conversations.replaceConversations([
      makeConversation('c1', '天气话题'),
      makeConversation('c2', '食谱话题'),
    ]);
    await pumpDrawer(tester, conversations: conversations, settings: settings);
    await tester.pump();

    await tester.enterText(find.byType(TextField), '天气');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('天气话题', findRichText: true), findsOneWidget);
    expect(find.text('食谱话题', findRichText: true), findsNothing);
  });

  testWidgets('empty state shows when no conversations exist', (tester) async {
    final conversations = memoryConversationProvider();
    final settings = memorySettingsProvider();
    await conversations.loadConversations();
    await pumpDrawer(tester, conversations: conversations, settings: settings);
    await tester.pump();

    expect(find.text('暂无历史对话'), findsOneWidget);
  });
}
