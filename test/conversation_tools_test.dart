import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lynai/models/agent_runtime.dart';
import 'package:lynai/models/composer_reference.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/services/agent_cancellation.dart';
import 'package:lynai/services/api_message_builder.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';
import 'package:lynai/services/tool_call_service.dart';

import 'support/memory_repositories.dart';

/// 建一个带两条消息与一条引用池记录的对话。
(String conversationId, ConversationProvider provider) _seedConversation() {
  final conversations = memoryConversationProvider();
  final id = conversations.createConversationWithMessages(
    ConversationSettings(modelId: 'model-1'),
    messages: [
      (
        role: 'user',
        content: '第一问：发布计划',
        images: const <MessageImage>[],
        composerSegments: const <ComposerSegment>[],
      ),
      (
        role: 'assistant',
        content: '第一答：先做回归测试',
        images: const <MessageImage>[],
        composerSegments: const <ComposerSegment>[],
      ),
      (
        role: 'user',
        content: '第二问：继续',
        images: const <MessageImage>[],
        composerSegments: const <ComposerSegment>[],
      ),
    ],
  );
  conversations.rememberComposerReferences(id, const [
    ComposerReference(
      localId: 'r1',
      type: ComposerReferenceType.note,
      id: 'note-1',
      title: '项目规划',
    ),
    ComposerReference(
      localId: 'r2',
      type: ComposerReferenceType.note,
      id: 'folder-7',
      title: '工作',
      scope: ComposerReferenceScope.folder,
    ),
  ]);
  return (id, conversations);
}

ToolCallService _service(
  ConversationProvider conversations,
  String conversationId, {
  bool allowConversationRead = true,
}) => ToolCallService(
  FeatureProvider(),
  conversations: conversations,
  conversationId: conversationId,
  permissionSnapshot: AgentPermissionSnapshot(
    permissions: [
      if (allowConversationRead) LynAIPermissions.conversationsRead,
    ],
  ),
);

Future<AgentToolResult> _run(
  ToolCallService service,
  AgentToolRunSnapshot snapshot,
  String name, [
  Map<String, dynamic> arguments = const {},
]) {
  return service
      .executeCapturedBatch(
        snapshot,
        [AgentToolInvocation(id: 'call-$name', name: name, arguments: arguments)],
        identity: const AgentTurnIdentity(
          runId: 'run',
          turnId: 'turn',
          turnIndex: 0,
        ),
        cancellationToken: AgentCancellationSource().token,
      )
      .then((results) => results.single);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('read_conversation 注册要求 conversations:read 权限', () {
    final (id, conversations) = _seedConversation();

    final denied = _service(
      conversations,
      id,
      allowConversationRead: false,
    ).createRunSnapshot(agentEnabled: true, imageGenerationEnabled: false);
    final allowed = _service(
      conversations,
      id,
    ).createRunSnapshot(agentEnabled: true, imageGenerationEnabled: false);

    expect(denied.tools['read_conversation'], isNull);
    final registration = allowed.tools['read_conversation'];
    expect(registration, isNotNull);
    expect(registration!.descriptor.sideEffect, AgentToolSideEffect.read);
    expect(registration.spec.semantics.operation, AgentToolOperation.read);
    expect(registration.spec.permissionRequirements.permissions, [
      LynAIPermissions.conversationsRead,
    ]);
    expect(
      registration.descriptor.parameters['required'],
      contains('conversationId'),
    );
  });

  test('未注入 ConversationProvider 时不注册对话工具', () {
    final snapshot = ToolCallService(
      FeatureProvider(),
      permissionSnapshot: AgentPermissionSnapshot(
        permissions: const [LynAIPermissions.conversationsRead],
      ),
    ).createRunSnapshot(agentEnabled: true, imageGenerationEnabled: false);
    expect(snapshot.tools['read_conversation'], isNull);
    expect(snapshot.tools['list_conversation_references'], isNull);
  });

  test('read_conversation 按 id 返回有界正文', () async {
    final (id, conversations) = _seedConversation();
    final service = _service(conversations, id);
    final snapshot = service.createRunSnapshot(
      agentEnabled: true,
      imageGenerationEnabled: false,
    );

    final result = await _run(service, snapshot, 'read_conversation', {
      'conversationId': id,
      'limit': 2,
    });

    expect(result.status, AgentToolResultStatus.success);
    final payload = result.value as Map<String, dynamic>;
    expect(payload['ok'], isTrue);
    final conversation = payload['conversation'] as Map<String, dynamic>;
    expect(conversation['id'], id);
    expect(conversation['messageCount'], 3);
    // limit=2 只返回最近两条，最新一条排在最后。
    expect(conversation['returnedCount'], 2);
    final messages = (conversation['messages'] as List).cast<Map>();
    expect(messages.map((message) => message['content']), [
      '第一答：先做回归测试',
      '第二问：继续',
    ]);
  });

  test('read_conversation 对未知 id 如实报错', () async {
    final (id, conversations) = _seedConversation();
    final service = _service(conversations, id);
    final snapshot = service.createRunSnapshot(
      agentEnabled: true,
      imageGenerationEnabled: false,
    );

    final result = await _run(service, snapshot, 'read_conversation', {
      'conversationId': 'missing',
    });
    final payload = result.value as Map<String, dynamic>;
    expect(payload['ok'], isFalse);
    expect(payload['error'].toString(), contains('missing'));
  });

  test('list_conversation_references 只返回身份与范围，不返回正文', () async {
    final (id, conversations) = _seedConversation();
    final service = _service(conversations, id);
    final snapshot = service.createRunSnapshot(
      agentEnabled: true,
      imageGenerationEnabled: false,
    );

    final result = await _run(service, snapshot, 'list_conversation_references');
    expect(result.status, AgentToolResultStatus.success);
    final payload = result.value as Map<String, dynamic>;
    expect(payload['ok'], isTrue);
    expect(payload['count'], 2);
    final references = (payload['references'] as List).cast<Map>();
    final note = references.firstWhere((item) => item['id'] == 'note-1');
    expect(note['type'], 'note');
    expect(note['scope'], 'entity');
    expect(note['title'], '项目规划');
    final folder = references.firstWhere((item) => item['id'] == 'folder-7');
    // 文件夹层级必须显式标注，避免模型把文件夹当成单个实体去读。
    expect(folder['scope'], 'folder');
  });

  test('引用池工具不需要额外权限，但引用池为空时返回空清单', () async {
    final conversations = memoryConversationProvider();
    final id = conversations.createConversationWithMessages(
      ConversationSettings(modelId: 'model-1'),
      messages: [
        (
          role: 'user',
          content: '只有一条',
          images: const <MessageImage>[],
          composerSegments: const <ComposerSegment>[],
        ),
      ],
    );
    final service = ToolCallService(
      FeatureProvider(),
      conversations: conversations,
      conversationId: id,
      permissionSnapshot: AgentPermissionSnapshot(permissions: const []),
    );
    final snapshot = service.createRunSnapshot(
      agentEnabled: true,
      imageGenerationEnabled: false,
    );
    expect(snapshot.tools['list_conversation_references'], isNotNull);
    expect(snapshot.tools['read_conversation'], isNull);

    final result = await _run(service, snapshot, 'list_conversation_references');
    final payload = result.value as Map<String, dynamic>;
    expect(payload['count'], 0);
    expect(payload['references'], isEmpty);
  });

  test('系统提示词只在 read_conversation 可用时才提它', () {
    // 提示词与工具快照必须同源：没授权就不能指向一个不存在的工具。
    expect(
      ToolCallService.nativeSystemPromptFor(webSearchConfigured: false),
      isNot(contains('read_conversation')),
    );
    expect(
      ToolCallService.nativeSystemPromptFor(
        webSearchConfigured: false,
        conversationsReadAvailable: true,
      ),
      contains('read_conversation'),
    );
  });

  test('read_conversation 参数在派发前按 schema 校验', () async {
    final (id, conversations) = _seedConversation();
    final service = _service(conversations, id);
    final snapshot = service.createRunSnapshot(
      agentEnabled: true,
      imageGenerationEnabled: false,
    );

    // conversationId 必须是字符串：坏参数要在派发前被 schema 拦下，而不是带着
    // 它进入执行路径（这个工具此前不在派发期校验清单里）。
    final result = await _run(service, snapshot, 'read_conversation', {
      'conversationId': 42,
    });
    expect(result.status, isNot(AgentToolResultStatus.success));
    expect(result.errorMessage, contains(r'$.conversationId'));
  });

  test('buildApiMessages 按可用性决定是否提 read_conversation', () {    final conversation = Conversation(
      id: 'conv-1',
      title: '标题',
      messages: [
        Message(
          id: 'm0',
          role: 'user',
          content: '看看之前聊了什么',
          timestamp: DateTime(2026, 3, 1),
        ),
      ],
      modelId: 'model-1',
      createdAt: DateTime(2026, 3, 1),
      updatedAt: DateTime(2026, 3, 1),
    );

    String systemText({required bool conversationsReadAvailable}) => buildApiMessages(
      conversation,
      const [],
      enableTools: true,
      conversationsReadAvailable: conversationsReadAvailable,
    )
        .where((message) => message['role'] == 'system')
        .map((message) => message['content'].toString())
        .join('\n');

    expect(systemText(conversationsReadAvailable: false), isNot(contains('read_conversation')));
    expect(systemText(conversationsReadAvailable: true), contains('read_conversation'));
  });
}
