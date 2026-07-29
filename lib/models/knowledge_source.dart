final class KnowledgeSource {
  const KnowledgeSource({
    required this.id,
    required this.knowledgeBaseId,
    required this.entryId,
    required this.title,
    this.url,
    this.note,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String knowledgeBaseId;
  final String entryId;
  final String title;
  final String? url;
  final String? note;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory KnowledgeSource.fromJson(Map<String, dynamic> json) =>
      KnowledgeSource(
        id: json['id'] as String,
        knowledgeBaseId: json['knowledgeBaseId'] as String,
        entryId: json['entryId'] as String,
        title: json['title'] as String? ?? '',
        url: json['url'] as String?,
        note: json['note'] as String?,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'knowledgeBaseId': knowledgeBaseId,
    'entryId': entryId,
    'title': title,
    if (url != null) 'url': url,
    if (note != null) 'note': note,
    'sortOrder': sortOrder,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  KnowledgeSource copyWith({
    String? id,
    String? knowledgeBaseId,
    String? entryId,
    String? title,
    String? url,
    String? note,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => KnowledgeSource(
    id: id ?? this.id,
    knowledgeBaseId: knowledgeBaseId ?? this.knowledgeBaseId,
    entryId: entryId ?? this.entryId,
    title: title ?? this.title,
    url: url ?? this.url,
    note: note ?? this.note,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
