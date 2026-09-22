import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/composer_reference.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';
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

/// 只吐一段正文、永不结束的假 API，用来把页面固定在“生成中”状态。
class _HangingStreamApi extends ApiService {
  final List<List<Map<String, dynamic>>> requests = [];
  final List<StreamController<StreamChunk>> controllers = [];

  @override
  Stream<StreamChunk> sendStreamRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
    List<Map<String, dynamic>> tools = const [],
    Object? toolChoice,
  }) {
    requests.add(messages);
    final controller = StreamController<StreamChunk>();
    controllers.add(controller);
    controller.add(StreamChunk(content: '被打断的回复 ${requests.length}'));
    return controller.stream;
  }
}

void main() {
  group('branchConversationTitle', () {
    test('第一层分支加（1）前缀', () {
      expect(branchConversationTitle('新对话 3'), '（1）新对话 3');
    });

    test('再分支把序号加一', () {
      expect(branchConversationTitle('（1）新对话 3'), '（2）新对话 3');
      expect(branchConversationTitle('（9）标题'), '（10）标题');
    });

    test('序号后的空格不参与标题', () {
      expect(branchConversationTitle('（1） 标题'), '（2）标题');
    });

    test('不是数字的括号按普通文本处理', () {
      expect(branchConversationTitle('（草稿）标题'), '（1）（草稿）标题');
    });
  });

  group('branchCopyEnd', () {
    final messages = [
      _message('u1', 'user', '第一条'),
      _message('a1', 'assistant', '回复一'),
      _message('u2', 'user', '第二条'),
      _message('a2', 'assistant', '回复二'),
    ];

    test('用户消息分支只用它的前缀', () {
      expect(branchCopyEnd(messages, 'u2', includeMessage: false), 2);
    });

    test('助手消息分支包含该条回复', () {
      expect(branchCopyEnd(messages, 'a1', includeMessage: true), 2);
      expect(branchCopyEnd(messages, 'a2', includeMessage: true), 4);
    });

    test('分支点本身是第一条时前缀为空', () {
      expect(branchCopyEnd(messages, 'u1', includeMessage: false), 0);
    });

    test('结尾的空助手占位不进分支', () {
      final withPlaceholder = [
        _message('u1', 'user', '第一条'),
        _message('a1', 'assistant', ''),
        _message('u2', 'user', '第二条'),
      ];
      expect(branchCopyEnd(withPlaceholder, 'u2', includeMessage: false), 1);
    });

    test('找不到消息时返回 -1', () {
      expect(branchCopyEnd(messages, 'missing', includeMessage: true), -1);
    });
  });

  group('对话页消息操作', () {
    late Directory storageRoot;
    late StorageV2Service storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storageRoot = await Directory.systemTemp.createTemp(
        'lynai_chat_actions_',
      );
      storage = StorageV2Service(rootDirectory: storageRoot);
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
    });

    tearDown(() async {
      await storage.close();
      await storageRoot.delete(recursive: true);
    });

    testWidgets('用户消息在气泡下方带复制/编辑/撤回/分支并靠右对齐', (tester) async {
      final conversations = memoryConversationProvider();
      final cid = _seedConversation(conversations);
      await _pumpChat(tester, storage, conversations, cid);

      expect(find.byTooltip('复制'), findsNWidgets(4));
      expect(find.byTooltip('编辑'), findsNWidgets(2));
      expect(find.byTooltip('撤回'), findsNWidgets(2));
      expect(find.byTooltip('分支'), findsNWidgets(4));
      expect(find.byTooltip('分享'), findsNWidgets(2));
      expect(find.byTooltip('重新生成'), findsOneWidget);
      // 旧版贴在气泡右下角的裸铅笔图标已经移除。
      expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));

      final bubbleBottom = tester
          .getBottomLeft(find.text('看下 @笔记一', findRichText: true).first)
          .dy;
      final actionsTop = tester.getTopLeft(find.byTooltip('撤回').first).dy;
      expect(actionsTop, greaterThanOrEqualTo(bubbleBottom));

      final screenCenter =
          tester.view.physicalSize.width / tester.view.devicePixelRatio / 2;
      expect(
        tester.getCenter(find.byTooltip('撤回').first).dx,
        greaterThan(screenCenter),
      );
      expect(
        tester.getCenter(find.byTooltip('分享').first).dx,
        lessThan(screenCenter),
      );

      await _finish(tester, conversations);
    });

    testWidgets('撤回截断后续消息、回填输入框，撤销可完整还原', (tester) async {
      final conversations = memoryConversationProvider();
      final cid = _seedConversation(conversations);
      await _pumpChat(tester, storage, conversations, cid);

      // 撤回前输入框里已经有用户正在编辑的内容。
      await tester.enterText(_composer(), '正在输入');
      await tester.pump();

      await tester.tap(find.byTooltip('撤回').at(1));
      await tester.pump();

      final withdrawn = conversations.getConversation(cid)!;
      expect(withdrawn.messages.map((m) => m.content), ['看下 @笔记一', '回复一']);
      expect(_composerText(tester), '第二条');
      expect(find.text('已撤回，内容回到输入框'), findsOneWidget);

      // 等 SnackBar 入场动画结束，否则操作按钮还在屏幕外。
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('撤销'));
      await tester.pump();

      final restored = conversations.getConversation(cid)!;
      expect(restored.messages.map((m) => m.content), [
        '看下 @笔记一',
        '回复一',
        '第二条',
        '回复二',
      ]);
      expect(_composerText(tester), '正在输入');

      await _finish(tester, conversations);
    });

    testWidgets('助手消息分支复制上下文到该回复为止且不发送', (tester) async {
      final conversations = memoryConversationProvider();
      final cid = _seedConversation(conversations);
      await _pumpChat(tester, storage, conversations, cid);

      // 分支按钮顺序：用户一、助手一、用户二、助手二。
      await tester.tap(find.byTooltip('分支').at(1));
      await tester.pump();

      expect(conversations.conversations, hasLength(2));
      final branch = conversations.conversations.first;
      expect(branch.id, isNot(cid));
      expect(branch.title, '（1）看下 @笔记一');
      expect(branch.messages.map((m) => m.content), ['看下 @笔记一', '回复一']);
      expect(branch.messages.first.content, '看下 @笔记一');
      expect(branch.messages.first.modelContextContent, '模型上下文一');
      // 引用 Chip 片段必须跟着进分支，否则恢复出来的气泡会丢掉引用。
      expect(branch.messages.first.composerSegments, hasLength(2));
      expect(
        branch.messages.first.composerSegments.last,
        isA<ComposerReferenceSegment>(),
      );
      expect(_composerText(tester), '');

      // 源对话不受影响。
      expect(conversations.getConversation(cid)!.messages, hasLength(4));

      await _finish(tester, conversations);
    });

    testWidgets('再分支时标题序号加一', (tester) async {
      final conversations = memoryConversationProvider();
      final cid = _seedConversation(conversations);
      conversations.updateConversationTitle(cid, '（1）看下 @笔记一');
      await _pumpChat(tester, storage, conversations, cid);

      await tester.tap(find.byTooltip('分支').at(1));
      await tester.pump();

      expect(conversations.conversations.first.title, '（2）看下 @笔记一');

      await _finish(tester, conversations);
    });

    testWidgets('生成中编辑并发送会先停流再重发，且保留被打断的回复', (tester) async {
      final api = _HangingStreamApi();
      final conversations = memoryConversationProvider();
      final models = memoryModelConfigProvider()
        ..addModel(
          ModelConfig(
            id: 'm1',
            name: 'test',
            endpoint: 'https://example.test',
            apiKey: '',
            modelName: 'model',
            apiType: 'openai',
            priority: 0,
          ),
        );
      final cid = conversations.createConversation(
        ConversationSettings(modelId: 'm1'),
      );
      await _pumpChat(
        tester,
        storage,
        conversations,
        cid,
        api: api,
        models: models,
      );

      await tester.enterText(_composer(), '第一次提问');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      for (var i = 0; i < 40 && api.requests.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(api.requests, hasLength(1));

      // 生成还没结束时点「编辑」改正文再发送。
      await tester.tap(find.byTooltip('编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(_editDialogField(), '改过的提问');
      await tester.tap(find.text('发送'));
      for (var i = 0; i < 80 && api.requests.length < 2; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(api.requests, hasLength(2));
      final second = api.requests.last;
      expect(second.where((m) => m['role'] == 'user').last['content'], '改过的提问');
      expect(second.any((m) => m['content'] == '第一次提问'), isFalse);
      // 被打断的那轮回复作为旧版本留在重试历史里，可以切回去。
      expect(find.text('2/2'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pump();
      expect(
        conversations.getConversation(cid)!.messages.last.content,
        contains('被打断的回复 1'),
      );

      // 收尾：关掉假流让 runtime 结束在飞的 turn，否则会留下 pending timer。
      await _closeStreams(api);
      await tester.pump(const Duration(milliseconds: 50));
      await _finish(tester, conversations);
    });

    testWidgets('历史消息的编辑入口改用不再包含撤回的弹窗', (tester) async {
      final conversations = memoryConversationProvider();
      final cid = _seedConversation(conversations);
      await _pumpChat(tester, storage, conversations, cid);

      await tester.tap(find.byTooltip('编辑').first);
      await tester.pumpAndSettle();

      expect(find.text('编辑消息'), findsOneWidget);
      expect(find.text('开始新对话'), findsOneWidget);
      expect(find.text('撤回并删除后续'), findsNothing);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(conversations.getConversation(cid)!.messages, hasLength(4));

      await _finish(tester, conversations);
    });
  });
}

Message _message(String id, String role, String content) => Message(
  id: id,
  role: role,
  content: content,
  timestamp: DateTime.utc(2026),
);

/// 种子对话：两条用户消息 + 两条助手回复，首条带引用 Chip 和模型上下文。
String _seedConversation(ConversationProvider conversations) {
  const reference = ComposerReference(
    localId: 'ref-1',
    type: ComposerReferenceType.note,
    id: 'note-1',
    title: '笔记一',
  );
  return conversations.createConversationWithMessages(
    ConversationSettings(modelId: 'model'),
    messages: [
      (
        role: 'user',
        content: '看下 @笔记一',
        images: const <MessageImage>[],
        composerSegments: const <ComposerSegment>[
          ComposerTextSegment('看下 '),
          ComposerReferenceSegment(reference),
        ],
      ),
      (
        role: 'assistant',
        content: '回复一',
        images: const <MessageImage>[],
        composerSegments: const <ComposerSegment>[],
      ),
      (
        role: 'user',
        content: '第二条',
        images: const <MessageImage>[],
        composerSegments: const <ComposerSegment>[],
      ),
      (
        role: 'assistant',
        content: '回复二',
        images: const <MessageImage>[],
        composerSegments: const <ComposerSegment>[],
      ),
    ],
    modelContextByIndex: const {0: '模型上下文一'},
  );
}

Finder _composer() => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == '输入消息...',
);

String _composerText(WidgetTester tester) =>
    tester.widget<TextField>(_composer()).controller!.text;

Finder _editDialogField() => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == '编辑消息内容...',
);

Future<void> _pumpChat(
  WidgetTester tester,
  StorageV2Service storage,
  ConversationProvider conversations,
  String conversationId, {
  ApiService? api,
  ModelConfigProvider? models,
}) async {
  await tester.binding.setSurfaceSize(const Size(500, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: conversations),
        ChangeNotifierProvider.value(value: memorySettingsProvider()),
        ChangeNotifierProvider.value(value: memoryWorkspaceProvider()),
        ChangeNotifierProvider.value(
          value: models ?? memoryModelConfigProvider(),
        ),
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
}

Future<void> _closeStreams(_HangingStreamApi api) async {
  for (final controller in api.controllers) {
    await controller.close();
  }
}

Future<void> _finish(
  WidgetTester tester,
  ConversationProvider conversations,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 500));
  await conversations.flushPendingSaves();
}
