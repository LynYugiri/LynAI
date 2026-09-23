import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/composer_draft.dart';
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
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';
import 'package:provider/provider.dart';

import 'support/memory_repositories.dart';

void main() {
  late Directory storageRoot;
  late StorageV2Service storage;

  setUp(() async {
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
    final conversations = memoryConversationProvider();
    _addConversation(conversations, '甲会话');
    _addConversation(conversations, '乙会话');
    await _pumpChat(tester, storage, conversations);

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
    await _finish(tester, conversations);
  });

  testWidgets('切换对话时引用 Chip 一起暂存与恢复', (tester) async {
    final conversations = memoryConversationProvider();
    final first = _addConversation(conversations, '甲会话');
    _addConversation(conversations, '乙会话');
    await _pumpChat(tester, storage, conversations);

    const reference = ComposerReference(
      localId: 'ref-1',
      type: ComposerReferenceType.note,
      id: 'note-1',
      title: '笔记一',
    );
    conversations.saveComposerDraft(
      first,
      const ComposerDraft(
        segments: [
          ComposerTextSegment('看下 '),
          ComposerReferenceSegment(reference),
        ],
      ),
    );

    await _selectConversation(tester, '乙会话');
    expect(_composerText(tester), '');
    await _selectConversation(tester, '甲会话');
    expect(_composerText(tester), '看下 ${String.fromCharCode(0xE000)}');
    await _finish(tester, conversations);
  });

  testWidgets('暂存附件随对话切换一起搬运', (tester) async {
    final conversations = memoryConversationProvider();
    final attachment = File('${storageRoot.path}/notes.txt')
      ..writeAsStringSync('附件内容');
    final first = _addConversation(
      conversations,
      '甲会话',
      images: [
        MessageImage(
          path: attachment.path,
          name: 'notes.txt',
          size: attachment.lengthSync(),
          mimeType: 'text/plain',
        ),
      ],
    );
    _addConversation(conversations, '乙会话');
    await _pumpChat(tester, storage, conversations);

    // 撤回把这条消息的正文和附件一起回填输入框。
    await _selectConversation(tester, '甲会话');
    await tester.tap(find.byTooltip('撤回'));
    await tester.pumpAndSettle();
    expect(find.text('notes.txt'), findsOneWidget);

    await _selectConversation(tester, '乙会话');
    expect(_composerText(tester), '');
    expect(find.text('notes.txt'), findsNothing);

    await _selectConversation(tester, '甲会话');
    expect(find.text('notes.txt'), findsOneWidget);
    expect(
      conversations.composerDraftFor(first).attachments.single.name,
      'notes.txt',
    );
    await _finish(tester, conversations);
  });

  testWidgets('附件文件缺失时保留占位而不是丢掉草稿条目', (tester) async {
    final conversations = memoryConversationProvider();
    final missing = _addConversation(conversations, '甲会话');
    _addConversation(conversations, '乙会话');
    await _pumpChat(tester, storage, conversations);
    conversations.saveComposerDraft(
      missing,
      const ComposerDraft(
        attachments: [
          ComposerDraftAttachment(
            name: 'missing.png',
            size: 1,
            mimeType: 'image/png',
          ),
        ],
      ),
    );

    await _selectConversation(tester, '甲会话');
    // 远端草稿的附件可能还没下载完，这里只提示缺失，不能把条目删掉。
    expect(find.text('missing.png'), findsOneWidget);
    expect(conversations.composerDraftFor(missing).attachments, hasLength(1));
    await _finish(tester, conversations);
  });

  testWidgets('进程重启后重新打开对话仍能恢复草稿', (tester) async {
    final conversationRepository = MemoryConversationRepository();
    final drafts = MemoryComposerDraftRepository();
    final conversations = ConversationProvider(
      repository: conversationRepository,
      recycleBinRepository: MemoryRecycleBinRepository(),
      composerDraftRepository: drafts,
    );
    _addConversation(conversations, '甲会话');
    _addConversation(conversations, '乙会话');
    await _pumpChat(tester, storage, conversations);

    await _selectConversation(tester, '甲会话');
    await tester.enterText(_composer(), '重启后还要在');
    await tester.pump();
    await _finish(tester, conversations);

    // 模拟重启：新 Provider 从同一份持久化数据里读回草稿。
    final restarted = ConversationProvider(
      repository: conversationRepository,
      recycleBinRepository: MemoryRecycleBinRepository(),
      composerDraftRepository: drafts,
    );
    await restarted.loadConversations();
    await _pumpChat(tester, storage, restarted);
    await _selectConversation(tester, '甲会话');
    expect(_composerText(tester), '重启后还要在');
    await _finish(tester, restarted);
  });

  testWidgets('删除对话会把草稿一起放进回收站并可恢复', (tester) async {
    final recycleBin = MemoryRecycleBinRepository();
    final conversations = ConversationProvider(
      repository: MemoryConversationRepository(),
      recycleBinRepository: recycleBin,
      composerDraftRepository: MemoryComposerDraftRepository(),
    );
    final cid = _addConversation(conversations, '甲会话');
    conversations.saveComposerDraft(
      cid,
      const ComposerDraft(segments: [ComposerTextSegment('跟着对话一起走')]),
    );
    await conversations.flushPendingSaves();
    await tester.pumpWidget(const SizedBox.shrink());

    await conversations.deleteConversation(cid);
    expect(conversations.composerDraftFor(cid).isEmpty, isTrue);

    final item = (await recycleBin.load()).single;
    expect((item.payload['composerDraft'] as Map)['segments'], isNotEmpty);

    await conversations.restoreConversation(
      Conversation.fromJson(
        Map<String, dynamic>.from(item.payload['conversation'] as Map),
      ),
      draft: ComposerDraft.fromJson(
        Map<String, dynamic>.from(item.payload['composerDraft'] as Map),
      ),
    );
    final restored = conversations.composerDraftFor(cid);
    expect(
      restored.segments.whereType<ComposerTextSegment>().single.text,
      '跟着对话一起走',
    );
  });
}

String _addConversation(
  ConversationProvider conversations,
  String title, {
  List<MessageImage> images = const <MessageImage>[],
}) {
  return conversations.createConversationWithMessages(
    ConversationSettings(modelId: 'model'),
    messages: [
      (
        role: 'user',
        content: title,
        images: images,
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
) async {
  await conversations.flushPendingSaves();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 500));
  await conversations.flushPendingSaves();
}
