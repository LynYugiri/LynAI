/// 随记引用类型。
enum JottingReferenceType {
  note('note'),
  task('task'),
  knowledgeEntry('knowledge_entry');

  const JottingReferenceType(this.wire);

  final String wire;

  static JottingReferenceType fromWire(String? wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return JottingReferenceType.note;
  }
}

/// 随记中的结构化引用卡片。
///
/// 保存目标身份和展示快照；目标内容之后被删除时，卡片仍能显示已失效。
class JottingReference {
  const JottingReference({
    required this.type,
    required this.id,
    required this.title,
    this.snippet = '',
  });

  final JottingReferenceType type;
  final String id;
  final String title;
  final String snippet;

  factory JottingReference.fromJson(Map<String, dynamic> json) {
    return JottingReference(
      type: JottingReferenceType.fromWire(json['type'] as String?),
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.wire,
    'id': id,
    'title': title,
    if (snippet.isNotEmpty) 'snippet': snippet,
  };
}

/// 随记数据模型。
///
/// 随记是时间序列上的轻量记录：没有标题和分页，只有正文、标签、引用卡片
/// 和时间戳。正文按 Markdown 原文保存，渲染时复用 [MarkdownWithLatex]。
class Jotting {
  const Jotting({
    required this.id,
    required this.content,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    this.references = const [],
  });

  final String id;

  /// 正文，Markdown 原文，保存前应 [String.trim]。
  final String content;

  /// 归一化标签：去重、小写、单个标签不超过 [maxTagLength] 字符。
  final List<String> tags;

  /// 结构化引用卡片。
  final List<JottingReference> references;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// 单个标签最大长度。
  static const maxTagLength = 32;

  /// 每条随记最多可保存的标签数。
  static const maxTagCount = 20;

  /// 每条随记最多可保存的引用卡片数。
  static const maxReferenceCount = 30;

  /// 归一化标签列表：trim、小写、去重、丢弃空标签，并执行长度/数量约束。
  static List<String> normalizeTags(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in values) {
      final tag = raw.trim().toLowerCase();
      if (tag.isEmpty || tag.length > maxTagLength || !seen.add(tag)) {
        continue;
      }
      result.add(tag);
      if (result.length >= maxTagCount) break;
    }
    return List.unmodifiable(result);
  }

  factory Jotting.fromJson(Map<String, dynamic> json) {
    return Jotting(
      id: json['id'] as String,
      content: json['content'] as String? ?? '',
      tags: normalizeTags(_tagsFromJson(json['tags'])),
      references: _referencesFromJson(json['references']),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  static List<String> _tagsFromJson(Object? raw) {
    if (raw is! List) return const [];
    return raw.map((item) => item.toString()).toList(growable: false);
  }

  static List<JottingReference> _referencesFromJson(Object? raw) {
    if (raw is! List) return const [];
    final result = <JottingReference>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final reference = JottingReference.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (reference.id.isEmpty) continue;
      result.add(reference);
      if (result.length >= maxReferenceCount) break;
    }
    return List.unmodifiable(result);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'tags': tags,
    if (references.isNotEmpty)
      'references': references.map((item) => item.toJson()).toList(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  Jotting copyWith({
    String? id,
    String? content,
    List<String>? tags,
    List<JottingReference>? references,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Jotting(
      id: id ?? this.id,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      references: references ?? this.references,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
