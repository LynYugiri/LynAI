import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/models/plugin.dart';
import 'package:lynai/services/api_message_builder.dart';

Conversation _conv({
  List<Message>? messages,
  String systemPrompt = '',
  bool agentEnabled = false,
}) {
  return Conversation(
    id: 'c1',
    title: 't',
    messages: messages ?? const [],
    modelId: 'm1',
    settings: ConversationSettings(
      modelId: 'm1',
      systemPrompt: systemPrompt,
      agentEnabled: agentEnabled,
    ),
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

Message _msg(
  String id,
  String role,
  String content, {
  String? modelContextContent,
}) {
  return Message(
    id: id,
    role: role,
    content: content,
    modelContextContent: modelContextContent,
    timestamp: DateTime(2026, 1, 1),
  );
}

void main() {
  test('prepends system message with user prompt when provided', () {
    final messages = buildApiMessages(
      _conv(messages: [_msg('u1', 'user', '你好')], systemPrompt: '你是助手'),
      const [],
    );
    expect(messages.first, {
      'role': 'system',
      'content': '你是助手',
    });
  });

  test('system parts order: prompt, tool prompt, time, annotation', () {
    final messages = buildApiMessages(
      _conv(
        messages: [_msg('u1', 'user', '你好')],
        systemPrompt: 'P',
        agentEnabled: true,
      ),
      const [],
      enableTools: true,
      annotationPrompt: 'A',
    );
    final system = messages.first['content'] as String;
    expect(system.startsWith('P\n\n'), isTrue);
    expect(system, contains('当前设备本地时间'));
    expect(system, endsWith('\n\nA'));
  });

  test('skips empty assistant messages', () {
    final messages = buildApiMessages(
      _conv(messages: [
        _msg('u1', 'user', 'hi'),
        _msg('a1', 'assistant', ''),
        _msg('a2', 'assistant', 'ok'),
      ]),
      const [],
    );
    final roles = messages.map((m) => m['role']).toList();
    expect(roles, ['user', 'assistant']);
  });

  test('adds empty reasoning_content to assistant messages', () {
    final messages = buildApiMessages(
      _conv(messages: [_msg('a1', 'assistant', 'ok')]),
      const [],
    );
    expect(messages.single['reasoning_content'], '');
    expect(messages.single.containsKey('reasoning_content'), isTrue);
  });

  test('prefers modelContextContent over content', () {
    final messages = buildApiMessages(
      _conv(
        messages: [_msg('u1', 'user', '原文', modelContextContent: '上下文版')],
      ),
      const [],
    );
    expect(messages.single['content'], '上下文版');
  });

  test('lastUserContentOverride replaces the last user message only', () {
    final messages = buildApiMessages(
      _conv(messages: [
        _msg('u1', 'user', '第一句'),
        _msg('a1', 'assistant', '回复'),
        _msg('u2', 'user', '第二句'),
      ]),
      const [],
      lastUserContentOverride: '重试内容',
    );
    expect(messages.map((m) => m['content']), [
      '第一句',
      '回复',
      '重试内容',
    ]);
  });

  test('extraSystemPrompt is appended into the tool prompt block', () {
    final messages = buildApiMessages(
      _conv(
        messages: [_msg('u1', 'user', 'hi')],
        agentEnabled: true,
      ),
      const [],
      enableTools: true,
      extraSystemPrompt: '悬浮授权提示',
    );
    final system = messages.first['content'] as String;
    expect(system, contains('\n\n悬浮授权提示'));
  });

  test('agent prompt only present when agentEnabled and enableTools', () {
    final enabled = buildApiMessages(
      _conv(
        messages: [_msg('u1', 'user', 'hi')],
        agentEnabled: true,
      ),
      const [],
      enableTools: true,
    );
    expect(enabled.first['content'], contains('工具'));

    final disabled = buildApiMessages(
      _conv(
        messages: [_msg('u1', 'user', 'hi')],
        agentEnabled: true,
      ),
      const [],
      enableTools: false,
    );
    expect(disabled.first['content'], isNot(contains('工具')));
  });

  test('accepts plugin list for skill summary without crashing', () {
    const plugins = <InstalledPlugin>[];
    final messages = buildApiMessages(
      _conv(
        messages: [_msg('u1', 'user', 'hi')],
        agentEnabled: true,
      ),
      plugins,
      enableTools: true,
    );
    expect(messages.first['content'], isNotEmpty);
  });
}
