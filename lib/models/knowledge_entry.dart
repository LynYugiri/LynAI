const _knowledgeUnset = Object();

/// 知识库中的正文条目，可选择归入同库类别。
final class KnowledgeEntry {
  const KnowledgeEntry({
    required this.id,
    required this.knowledgeBaseId,
    this.categoryId,
    required this.title,
    required this.content,
    required this.enabled,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String knowledgeBaseId;
  final String? categoryId;
  final String title;
  final String content;
  final bool enabled;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory KnowledgeEntry.fromJson(Map<String, dynamic> json) => KnowledgeEntry(
    id: json['id'] as String,
    knowledgeBaseId: json['knowledgeBaseId'] as String,
    categoryId: json['categoryId'] as String?,
    title: json['title'] as String,
    content: json['content'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? true,
    sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'knowledgeBaseId': knowledgeBaseId,
    if (categoryId != null) 'categoryId': categoryId,
    'title': title,
    'content': content,
    'enabled': enabled,
    'sortOrder': sortOrder,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  KnowledgeEntry copyWith({
    String? id,
    String? knowledgeBaseId,
    Object? categoryId = _knowledgeUnset,
    String? title,
    String? content,
    bool? enabled,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => KnowledgeEntry(
    id: id ?? this.id,
    knowledgeBaseId: knowledgeBaseId ?? this.knowledgeBaseId,
    categoryId: identical(categoryId, _knowledgeUnset)
        ? this.categoryId
        : categoryId as String?,
    title: title ?? this.title,
    content: content ?? this.content,
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
