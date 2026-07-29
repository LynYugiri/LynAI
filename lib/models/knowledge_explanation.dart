final class KnowledgeExplanation {
  const KnowledgeExplanation({
    required this.id,
    required this.knowledgeBaseId,
    required this.entryId,
    required this.title,
    required this.content,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String knowledgeBaseId;
  final String entryId;
  final String title;
  final String content;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory KnowledgeExplanation.fromJson(Map<String, dynamic> json) =>
      KnowledgeExplanation(
        id: json['id'] as String,
        knowledgeBaseId: json['knowledgeBaseId'] as String,
        entryId: json['entryId'] as String,
        title: json['title'] as String? ?? '',
        content: json['content'] as String? ?? '',
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'knowledgeBaseId': knowledgeBaseId,
    'entryId': entryId,
    'title': title,
    'content': content,
    'sortOrder': sortOrder,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  KnowledgeExplanation copyWith({
    String? id,
    String? knowledgeBaseId,
    String? entryId,
    String? title,
    String? content,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => KnowledgeExplanation(
    id: id ?? this.id,
    knowledgeBaseId: knowledgeBaseId ?? this.knowledgeBaseId,
    entryId: entryId ?? this.entryId,
    title: title ?? this.title,
    content: content ?? this.content,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
