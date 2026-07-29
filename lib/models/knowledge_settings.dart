final class KnowledgeSettings {
  const KnowledgeSettings({
    this.defaultKnowledgeBaseId,
    this.defaultCategoryId,
    required this.updatedAt,
  });

  final String? defaultKnowledgeBaseId;
  final String? defaultCategoryId;
  final DateTime updatedAt;

  factory KnowledgeSettings.fromJson(Map<String, dynamic> json) =>
      KnowledgeSettings(
        defaultKnowledgeBaseId: json['defaultKnowledgeBaseId'] as String?,
        defaultCategoryId: json['defaultCategoryId'] as String?,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
    if (defaultKnowledgeBaseId != null)
      'defaultKnowledgeBaseId': defaultKnowledgeBaseId,
    if (defaultCategoryId != null) 'defaultCategoryId': defaultCategoryId,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  KnowledgeSettings copyWith({
    String? defaultKnowledgeBaseId,
    String? defaultCategoryId,
    DateTime? updatedAt,
  }) => KnowledgeSettings(
    defaultKnowledgeBaseId:
        defaultKnowledgeBaseId ?? this.defaultKnowledgeBaseId,
    defaultCategoryId: defaultCategoryId ?? this.defaultCategoryId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
