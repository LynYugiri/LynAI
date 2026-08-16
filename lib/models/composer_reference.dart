import 'dart:convert';

/// 类型化引用的资源类型。
enum ComposerReferenceType {
  note('note'),
  notePage('note_page'),
  task('task'),
  taskList('task_list'),
  knowledgeBase('knowledge_base'),
  knowledgeEntry('knowledge_entry'),
  pluginResource('plugin_resource'),
  pluginSkill('plugin_skill');

  const ComposerReferenceType(this.wire);

  /// 编码到 `<lynai_ref type="...">` 中的类型名。
  final String wire;

  static ComposerReferenceType? fromWire(String? wire) {
    for (final type in values) {
      if (type.wire == wire) return type;
    }
    return null;
  }
}

/// 一个类型化引用。
///
/// [title]/[subtitle] 仅用于本地显示，模型侧只接收 [type] 与 [id]（及必要的
/// 稳定限定字段 [qualifiers]），不接收标题、副标题或正文。
class ComposerReference {
  /// 编辑器内部的绑定 ID，非资源 ID。
  final String localId;

  final ComposerReferenceType type;

  /// 资源的稳定 ID。
  final String id;

  /// 本地显示标题。
  final String title;

  /// 本地显示副标题（如笔记开头、待办状态）。
  final String? subtitle;

  /// 额外的稳定身份字段（如 noteId、pluginId）。
  final Map<String, String> qualifiers;

  const ComposerReference({
    required this.localId,
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
    this.qualifiers = const {},
  });

  Map<String, dynamic> toJson() => {
    'localId': localId,
    'type': type.wire,
    'id': id,
    'title': title,
    if (subtitle != null) 'subtitle': subtitle,
    if (qualifiers.isNotEmpty) 'qualifiers': qualifiers,
  };

  factory ComposerReference.fromJson(Map<String, dynamic> json) {
    return ComposerReference(
      localId: json['localId'] as String? ?? '',
      type: ComposerReferenceType.fromWire(json['type'] as String?) ??
          ComposerReferenceType.note,
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String?,
      qualifiers: (json['qualifiers'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    );
  }
}

/// 引用编解码器：唯一负责生成与解析 `<lynai_ref .../>` 文本。
class ComposerReferenceCodec {
  /// 生成发送给模型的类型化引用文本，只含 type/id 与稳定限定字段。
  static String encode(ComposerReference reference) {
    final buffer = StringBuffer()
      ..write('<lynai_ref type="')
      ..write(reference.type.wire)
      ..write('" id="')
      ..write(_escape(reference.id))
      ..write('"');
    for (final entry in reference.qualifiers.entries) {
      buffer
        ..write(' ')
        ..write(entry.key)
        ..write('="')
        ..write(_escape(entry.value))
        ..write('"');
    }
    buffer.write('/>');
    return buffer.toString();
  }

  /// 严格解析单个 `<lynai_ref .../>`，失败返回 null。
  static ComposerReference? decode(String token) {
    final trimmed = token.trim();
    if (!trimmed.startsWith('<lynai_ref ') || !trimmed.endsWith('/>')) {
      return null;
    }
    final body = trimmed.substring('<lynai_ref '.length, trimmed.length - 2);
    final attributes = <String, String>{};
    final pattern = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]*)"');
    for (final match in pattern.allMatches(body)) {
      attributes[match.group(1)!] = _unescape(match.group(2)!);
    }
    final type = ComposerReferenceType.fromWire(attributes['type']);
    final id = attributes['id'];
    if (type == null || id == null || id.isEmpty) return null;
    final qualifiers = Map<String, String>.from(attributes)
      ..remove('type')
      ..remove('id');
    return ComposerReference(
      localId: '',
      type: type,
      id: id,
      title: '',
      qualifiers: qualifiers,
    );
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _unescape(String value) => value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&');
}

/// 编辑器内容片段：文本或引用 chip。
sealed class ComposerSegment {
  const ComposerSegment();
}

class ComposerTextSegment extends ComposerSegment {
  final String text;
  const ComposerTextSegment(this.text);
}

class ComposerReferenceSegment extends ComposerSegment {
  final ComposerReference reference;
  const ComposerReferenceSegment(this.reference);
}

/// 将片段列表序列化为 JSON，用于消息持久化（Phase 9）。
String encodeComposerSegments(List<ComposerSegment> segments) => jsonEncode(
  segments
      .map(
        (segment) => switch (segment) {
          ComposerTextSegment(:final text) => {'t': 'text', 'v': text},
          ComposerReferenceSegment(:final reference) => {
            't': 'ref',
            'v': reference.toJson(),
          },
        },
      )
      .toList(),
);

/// 从 JSON 恢复片段列表。
List<ComposerSegment> decodeComposerSegments(String json) {
  final raw = jsonDecode(json);
  if (raw is! List) return const [];
  final segments = <ComposerSegment>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final kind = item['t'];
    if (kind == 'text') {
      segments.add(ComposerTextSegment(item['v']?.toString() ?? ''));
    } else if (kind == 'ref' && item['v'] is Map) {
      segments.add(
        ComposerReferenceSegment(
          ComposerReference.fromJson(Map<String, dynamic>.from(item['v'] as Map)),
        ),
      );
    }
  }
  return segments;
}
