const _memoryCardUnset = Object();

/// 记忆卡片复习状态。
enum MemoryCardStatus {
  newCard('new'),
  learning('learning'),
  review('review'),
  relearning('relearning');

  const MemoryCardStatus(this.wire);

  final String wire;

  static MemoryCardStatus fromWire(String? wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return MemoryCardStatus.newCard;
  }
}

/// 记忆卡片来源类型。
enum MemoryCardSourceKind {
  manual('manual'),
  knowledge('knowledge'),
  chat('chat');

  const MemoryCardSourceKind(this.wire);

  final String wire;

  static MemoryCardSourceKind fromWire(String? wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return MemoryCardSourceKind.manual;
  }
}

/// 一张正反面记忆卡片。
final class MemoryCard {
  const MemoryCard({
    required this.id,
    required this.deckId,
    required this.front,
    required this.back,
    this.hint,
    required this.sourceKind,
    this.sourceEntryId,
    this.sourceBaseId,
    required this.status,
    this.dueAt,
    required this.intervalDays,
    required this.easeFactor,
    required this.repetitions,
    required this.lapses,
    required this.reviewCount,
    this.lastReviewedAt,
    required this.enabled,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String deckId;
  final String front;
  final String back;
  final String? hint;
  final MemoryCardSourceKind sourceKind;
  final String? sourceEntryId;
  final String? sourceBaseId;
  final MemoryCardStatus status;
  final DateTime? dueAt;
  final double intervalDays;
  final double easeFactor;
  final int repetitions;
  final int lapses;
  final int reviewCount;
  final DateTime? lastReviewedAt;
  final bool enabled;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory MemoryCard.fromJson(Map<String, dynamic> json) => MemoryCard(
    id: json['id'] as String,
    deckId: json['deckId'] as String,
    front: json['front'] as String,
    back: json['back'] as String? ?? '',
    hint: json['hint'] as String?,
    sourceKind: MemoryCardSourceKind.fromWire(json['sourceKind'] as String?),
    sourceEntryId: json['sourceEntryId'] as String?,
    sourceBaseId: json['sourceBaseId'] as String?,
    status: MemoryCardStatus.fromWire(json['status'] as String?),
    dueAt: json['dueAt'] == null
        ? null
        : DateTime.parse(json['dueAt'] as String),
    intervalDays: (json['intervalDays'] as num?)?.toDouble() ?? 0,
    easeFactor: (json['easeFactor'] as num?)?.toDouble() ?? 2.5,
    repetitions: (json['repetitions'] as num?)?.toInt() ?? 0,
    lapses: (json['lapses'] as num?)?.toInt() ?? 0,
    reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
    lastReviewedAt: json['lastReviewedAt'] == null
        ? null
        : DateTime.parse(json['lastReviewedAt'] as String),
    enabled: json['enabled'] as bool? ?? true,
    sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'deckId': deckId,
    'front': front,
    'back': back,
    if (hint != null) 'hint': hint,
    'sourceKind': sourceKind.wire,
    if (sourceEntryId != null) 'sourceEntryId': sourceEntryId,
    if (sourceBaseId != null) 'sourceBaseId': sourceBaseId,
    'status': status.wire,
    if (dueAt != null) 'dueAt': dueAt!.toUtc().toIso8601String(),
    'intervalDays': intervalDays,
    'easeFactor': easeFactor,
    'repetitions': repetitions,
    'lapses': lapses,
    'reviewCount': reviewCount,
    if (lastReviewedAt != null)
      'lastReviewedAt': lastReviewedAt!.toUtc().toIso8601String(),
    'enabled': enabled,
    'sortOrder': sortOrder,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  bool isDueAt(DateTime now) {
    if (!enabled) return false;
    final due = dueAt;
    if (due == null) return true;
    return !due.isAfter(now);
  }

  MemoryCard copyWith({
    String? id,
    String? deckId,
    String? front,
    String? back,
    Object? hint = _memoryCardUnset,
    MemoryCardSourceKind? sourceKind,
    Object? sourceEntryId = _memoryCardUnset,
    Object? sourceBaseId = _memoryCardUnset,
    MemoryCardStatus? status,
    Object? dueAt = _memoryCardUnset,
    double? intervalDays,
    double? easeFactor,
    int? repetitions,
    int? lapses,
    int? reviewCount,
    Object? lastReviewedAt = _memoryCardUnset,
    bool? enabled,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => MemoryCard(
    id: id ?? this.id,
    deckId: deckId ?? this.deckId,
    front: front ?? this.front,
    back: back ?? this.back,
    hint: identical(hint, _memoryCardUnset) ? this.hint : hint as String?,
    sourceKind: sourceKind ?? this.sourceKind,
    sourceEntryId: identical(sourceEntryId, _memoryCardUnset)
        ? this.sourceEntryId
        : sourceEntryId as String?,
    sourceBaseId: identical(sourceBaseId, _memoryCardUnset)
        ? this.sourceBaseId
        : sourceBaseId as String?,
    status: status ?? this.status,
    dueAt: identical(dueAt, _memoryCardUnset) ? this.dueAt : dueAt as DateTime?,
    intervalDays: intervalDays ?? this.intervalDays,
    easeFactor: easeFactor ?? this.easeFactor,
    repetitions: repetitions ?? this.repetitions,
    lapses: lapses ?? this.lapses,
    reviewCount: reviewCount ?? this.reviewCount,
    lastReviewedAt: identical(lastReviewedAt, _memoryCardUnset)
        ? this.lastReviewedAt
        : lastReviewedAt as DateTime?,
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
