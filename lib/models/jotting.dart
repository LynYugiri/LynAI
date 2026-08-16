/// 随记数据模型。
///
/// 随记是时间序列上的轻量记录：没有标题和分页，只有正文、标签和时间戳。
/// 正文按 Markdown 原文保存，渲染时复用 [MarkdownWithLatex]。
class Jotting {
  const Jotting({
    required this.id,
    required this.content,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// 正文，Markdown 原文，保存前应 [String.trim]。
  final String content;

  /// 归一化标签：去重、小写、单个标签不超过 [maxTagLength] 字符。
  final List<String> tags;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// 单个标签最大长度。
  static const maxTagLength = 32;

  /// 每条随记最多可保存的标签数。
  static const maxTagCount = 20;

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
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  static List<String> _tagsFromJson(Object? raw) {
    if (raw is! List) return const [];
    return raw.map((item) => item.toString()).toList(growable: false);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'tags': tags,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  Jotting copyWith({
    String? id,
    String? content,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Jotting(
      id: id ?? this.id,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
