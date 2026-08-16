const _memoryCardDeckUnset = Object();

/// 记忆卡片牌组：一组用于间隔重复学习的卡片。
final class MemoryCardDeck {
  const MemoryCardDeck({
    required this.id,
    required this.name,
    this.description,
    required this.newPerDayLimit,
    required this.reviewPerDayLimit,
    required this.enabled,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? description;
  final int newPerDayLimit;
  final int reviewPerDayLimit;
  final bool enabled;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory MemoryCardDeck.fromJson(Map<String, dynamic> json) => MemoryCardDeck(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    newPerDayLimit: (json['newPerDayLimit'] as num?)?.toInt() ?? 20,
    reviewPerDayLimit: (json['reviewPerDayLimit'] as num?)?.toInt() ?? 200,
    enabled: json['enabled'] as bool? ?? true,
    sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    'newPerDayLimit': newPerDayLimit,
    'reviewPerDayLimit': reviewPerDayLimit,
    'enabled': enabled,
    'sortOrder': sortOrder,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  MemoryCardDeck copyWith({
    String? id,
    String? name,
    Object? description = _memoryCardDeckUnset,
    int? newPerDayLimit,
    int? reviewPerDayLimit,
    bool? enabled,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => MemoryCardDeck(
    id: id ?? this.id,
    name: name ?? this.name,
    description: identical(description, _memoryCardDeckUnset)
        ? this.description
        : description as String?,
    newPerDayLimit: newPerDayLimit ?? this.newPerDayLimit,
    reviewPerDayLimit: reviewPerDayLimit ?? this.reviewPerDayLimit,
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
