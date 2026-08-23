/// 把 OpenAI 风格消息列表转换成 BlueLM Demo 使用的本地 prompt。
///
/// Demo 模板：
/// ```text
/// [|Human|]:...
/// [|AI|]:...
/// ```
/// 本地 SDK 只接收单个字符串，因此多轮历史按顺序完整展开，最后保证以
/// `[|AI|]:` 结尾让模型开始生成。
library;

String buildLocalBlueLmPrompt(List<Map<String, dynamic>> messages) {
  final systems = <String>[];
  final turns = <String>[];

  for (final message in messages) {
    final role = message['role']?.toString() ?? '';
    final content = _flattenContent(message['content']);
    if (content.isEmpty && role != 'user') continue;
    switch (role) {
      case 'system':
        if (content.isNotEmpty) systems.add(content);
      case 'user':
        var userText = content;
        if (systems.isNotEmpty && !_systemConsumed(turns)) {
          userText = '${systems.join('\n\n')}\n\n$content';
        }
        turns.add('[|Human|]:$userText');
      case 'assistant':
        turns.add('[|AI|]:$content');
      case 'tool':
        turns.add('[|Tool|]:$content');
    }
  }

  final prompt = turns.join('\n');
  if (turns.isEmpty) {
    return '[|Human|]:\n[|AI|]:';
  }
  final lastRole = _lastRole(messages);
  if (lastRole == 'assistant') return prompt;
  return '$prompt\n[|AI|]:';
}

bool _systemConsumed(List<String> turns) {
  return turns.any((turn) => turn.startsWith('[|Human|]:'));
}

String? _lastRole(List<Map<String, dynamic>> messages) {
  for (final message in messages.reversed) {
    final role = message['role']?.toString() ?? '';
    if (role == 'user' || role == 'assistant' || role == 'tool') return role;
  }
  return null;
}

String _flattenContent(Object? content) {
  if (content == null) return '';
  if (content is String) return content.trim();
  if (content is! List) return content.toString().trim();
  final parts = <String>[];
  for (final part in content) {
    if (part is! Map) {
      final text = part.toString().trim();
      if (text.isNotEmpty) parts.add(text);
      continue;
    }
    final type = part['type']?.toString();
    switch (type) {
      case 'text':
        final text = part['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) parts.add(text);
      case 'input_file':
        final name = part['name']?.toString() ?? '附件';
        parts.add('[附件: $name]');
      case 'image_url':
        final url = part['image_url']?.toString() ?? '';
        if (url.isNotEmpty) parts.add('[图片: $url]');
      default:
        final text = part['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) parts.add(text);
    }
  }
  return parts.join('\n');
}
