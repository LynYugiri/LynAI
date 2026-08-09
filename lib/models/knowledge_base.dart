/// 一个可独立启停和排序的知识库。
final class KnowledgeBase {
  const KnowledgeBase({
    required this.id,
    required this.name,
    this.description,
    required this.enabled,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? description;
  final bool enabled;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory KnowledgeBase.fromJson(Map<String, dynamic> json) => KnowledgeBase(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    enabled: json['enabled'] as bool? ?? true,
    sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    'enabled': enabled,
    'sortOrder': sortOrder,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  KnowledgeBase copyWith({
    String? id,
    String? name,
    String? description,
    bool? enabled,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => KnowledgeBase(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
