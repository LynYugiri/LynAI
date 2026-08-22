import 'memory_card.dart';

/// 记忆卡片复习评分。
enum MemoryCardRating {
  again('again'),
  hard('hard'),
  good('good'),
  easy('easy');

  const MemoryCardRating(this.wire);

  final String wire;

  static MemoryCardRating fromWire(String? wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return MemoryCardRating.good;
  }
}

/// 每次复习评分的完整记录，用于统计与排障。
final class MemoryCardReviewLog {
  const MemoryCardReviewLog({
    required this.id,
    required this.cardId,
    required this.deckId,
    required this.reviewedAt,
    required this.rating,
    required this.statusBefore,
    required this.statusAfter,
    required this.intervalDaysBefore,
    required this.intervalDaysAfter,
    required this.easeBefore,
    required this.easeAfter,
    this.cardStateBefore,
  });

  final String id;
  final String cardId;
  final String deckId;
  final DateTime reviewedAt;
  final MemoryCardRating rating;
  final MemoryCardStatus statusBefore;
  final MemoryCardStatus statusAfter;
  final double intervalDaysBefore;
  final double intervalDaysAfter;
  final double easeBefore;
  final double easeAfter;

  /// 评分前的完整卡片快照，撤销复习时用于精确回滚。
  final Map<String, dynamic>? cardStateBefore;

  factory MemoryCardReviewLog.fromJson(
    Map<String, dynamic> json,
  ) => MemoryCardReviewLog(
    id: json['id'] as String,
    cardId: json['cardId'] as String,
    deckId: json['deckId'] as String,
    reviewedAt: DateTime.parse(json['reviewedAt'] as String),
    rating: MemoryCardRating.fromWire(json['rating'] as String?),
    statusBefore: MemoryCardStatus.fromWire(json['statusBefore'] as String?),
    statusAfter: MemoryCardStatus.fromWire(json['statusAfter'] as String?),
    intervalDaysBefore: (json['intervalDaysBefore'] as num?)?.toDouble() ?? 0,
    intervalDaysAfter: (json['intervalDaysAfter'] as num?)?.toDouble() ?? 0,
    easeBefore: (json['easeBefore'] as num?)?.toDouble() ?? 2.5,
    easeAfter: (json['easeAfter'] as num?)?.toDouble() ?? 2.5,
    cardStateBefore: json['cardStateBefore'] is Map
        ? Map<String, dynamic>.from(json['cardStateBefore'] as Map)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'cardId': cardId,
    'deckId': deckId,
    'reviewedAt': reviewedAt.toUtc().toIso8601String(),
    'rating': rating.wire,
    'statusBefore': statusBefore.wire,
    'statusAfter': statusAfter.wire,
    'intervalDaysBefore': intervalDaysBefore,
    'intervalDaysAfter': intervalDaysAfter,
    'easeBefore': easeBefore,
    'easeAfter': easeAfter,
    if (cardStateBefore != null) 'cardStateBefore': cardStateBefore,
  };
}
