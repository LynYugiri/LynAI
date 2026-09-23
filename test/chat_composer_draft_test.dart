import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/composer_reference.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/pages/chat_page.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/jotting_provider.dart';
import 'package:lynai/providers/knowledge_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/composer_draft_service.dart';
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
    storageRoot = await Directory.systemTemp.createTemp(
      'lynai_composer_draft_',
    );
    storage = StorageV2Service(rootDirectory: storageRoot);
    await StorageV2UpgradeService(storageV2: storage).ensureReady();
  });

  tearDown(() async {
    await storage.close();
    await storageRoot.delete(recursive: true);
  });

  testWidgets('各对话的输入内容互相独立', (tester) async {
    final drafts = ComposerDraftService();
    final conversations = memoryConversationProvider(drafts: drafts);
    _addConversation(conversations, '甲会话');
    _addConversation(conversations, '乙会话');
    await _pumpChat(tester, storage, conversations, drafts);

    // 还没创建对话时输入的内容属于「新对话」槽位。
    await tester.enterText(_composer(), '新对话的草稿');
    await tester.pump();

    await _selectConversation(tester, '甲会话');
    expect(_composerText(tester), '');

    await tester.enterText(_composer(), '甲的内容');
    await tester.pump();
    await _selectConversation(tester, '乙会话');
    expect(_composerText(tester), '');

    await tester.enterText(_composer(), '乙的内容');
    await tester.pump();
    await _selectConversation(tester, '甲会话');
    expect(_composerText(tester), '甲的内容');

    await _selectConversation(tester, '乙会话');
    expect(_composerText(tester), '乙的内容');

    // 新建对话回到「新对话」槽位，最开始那段内容还在。
    await tester.tap(find.byTooltip('新建对话'));
    await tester.pumpAndSettle();
    expect(_composerText(tester), '新对话的草稿');

    // 切走再切回同一个对话，草稿不串位也不丢。
    await _selectConversation(tester, '乙会话');
    expect(_composerText(tester), '乙的内容');
    await _finish(tester, conversations, drafts);
  });

  testWidgets('切换对话时引用 Chip 一起暂存与恢复', (tester) async {
    final drafts = ComposerDraftService();
    final conversations = memoryConversationProvider(drafts: drafts);
    final first = _addConversation(conversations, '甲会话');
    _addConversation(conversations, '乙会话');
    await _pumpChat(tester, storage, conversations, drafts);
    await drafts.ensureLoaded();

    const reference = ComposerReference(
      localId: 'ref-1',
      type: ComposerReferenceType.note,
      id: 'note-1',
      title: '笔记一',
    );
    drafts.saveDraft(first, const [
      ComposerTextSegment('看下 '),
      ComposerReferenceSegment(reference),
    ]);

    await _selectConversation(tester, '乙会话');
    expect(_composerText(tester), '');
    await _selectConversation(tester, '甲会话');
    expect(_composerText(tester), '看下 ${String.fromCharCode(0xE000)}');
    await _finish(tester, conversations, drafts);
  });

  testWidgets('进程重启后重新打开对话仍能恢复草稿', (tester) async {
    final before = ComposerDraftService();
    final conversations = memoryConversationProvider(drafts: before);
    _addConversation(conversations, '甲会话');
    _addConversation(conversations, '乙会话');
    await _pumpChat(tester, storage, conversations, before);

    await _selectConversation(tester, '甲会话');
    await tester.enterText(_composer(), '重启后还要在');
    await tester.pump();
    await before.flush();
    await _finish(tester, conversations, before);

    // 模拟重启：新的草稿服务从同一份存储里读回内容。
    final after = ComposerDraftService();
    await _pumpChat(tester, storage, conversations, after);
    await _selectConversation(tester, '甲会话');
    expect(_composerText(tester), '重启后还要在');
    await _finish(tester, conversations, after);
  });

  testWidgets('删除对话会同时删除它的草稿', (tester) async {
    final drafts = ComposerDraftService();
    await drafts.ensureLoaded();
    final conversations = memoryConversationProvider(drafts: drafts);
    final cid = _addConversation(conversations, '甲会话');
    drafts.saveDraft(cid, const [ComposerTextSegment('跟着对话一起走')]);

    await conversations.deleteConversation(cid);

    expect(drafts.draftFor(cid), isEmpty);
    await drafts.flush();
    await conversations.flushPendingSaves();
  });
}

String _addConversation(ConversationProvider conversations, String title) {
  return conversations.createConversationWithMessages(
    ConversationSettings(modelId: ''),
    messages: [
      (
        role: 'user',
        content: title,
        images: const <MessageImage>[],
        composerSegments: const <ComposerSegment>[],
      ),
    ],
  );
}

Finder _composer() => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == '输入消息...',
);

String _composerText(WidgetTester tester) =>
    tester.widget<TextField>(_composer()).controller!.text;

Future<void> _pumpChat(
  WidgetTester tester,
  StorageV2Service storage,
  ConversationProvider conversations,
  ComposerDraftService drafts,
) async {
  await tester.binding.setSurfaceSize(const Size(500, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: conversations),
        ChangeNotifierProvider.value(value: memorySettingsProvider()),
        ChangeNotifierProvider.value(value: memoryWorkspaceProvider()),
        ChangeNotifierProvider.value(value: memoryModelConfigProvider()),
        ChangeNotifierProvider(create: (_) => FeatureProvider()),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
        ChangeNotifierProvider(create: (_) => CalendarProvider()),
        ChangeNotifierProvider(create: (_) => PluginProvider()),
        ChangeNotifierProvider(create: (_) => KnowledgeProvider()),
        ChangeNotifierProvider(create: (_) => JottingProvider()),
        ChangeNotifierProvider.value(value: memoryRoleMemoryProvider()),
        ChangeNotifierProvider(create: (_) => BackendClient()),
        Provider<ComposerDraftService>.value(value: drafts),
        Provider.value(value: storage),
      ],
      child: const MaterialApp(home: ChatPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectConversation(WidgetTester tester, String title) async {
  await tester.tap(find.byTooltip('历史记录'));
  await tester.pumpAndSettle();
  // 标题同时出现在抽屉条目和消息气泡里，只在抽屉内点击。
  await tester.tap(
    find.descendant(of: find.byType(Drawer), matching: find.text(title)).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _finish(
  WidgetTester tester,
  ConversationProvider conversations,
  ComposerDraftService drafts,
) async {
  // 草稿写盘是防抖的，收尾时显式落盘，避免测试结束时还留着计时器。
  await drafts.flush();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 500));
  await conversations.flushPendingSaves();
}
