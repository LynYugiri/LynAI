import '../models/memory_card.dart';
import '../models/memory_card_review_log.dart';

/// 一次评分后的卡片调度状态。
final class MemoryCardSchedule {
  const MemoryCardSchedule({
    required this.status,
    required this.dueAt,
    required this.intervalDays,
    required this.easeFactor,
    required this.repetitions,
    required this.lapses,
  });

  final MemoryCardStatus status;
  final DateTime dueAt;
  final double intervalDays;
  final double easeFactor;
  final int repetitions;
  final int lapses;
}

/// 纯函数实现的简化 SM-2 间隔重复调度器。
///
/// 三档评分：忘记(again) / 良好(good) / 简单(easy)。
/// 学习阶段：忘记 10 分钟后重来，良好 1 天毕业，简单 4 天毕业。
/// 复习阶段：良好按 ease 倍率扩展，简单额外乘 1.3 并提高 ease。
abstract final class MemoryCardScheduler {
  static const double defaultEaseFactor = 2.5;
  static const double minEaseFactor = 1.3;
  static const double maxEaseFactor = 3.5;
  static const Duration relearningStep = Duration(minutes: 10);

  static MemoryCardSchedule schedule({
    required MemoryCardStatus status,
    required DateTime now,
    required MemoryCardRating rating,
    required double intervalDays,
    required double easeFactor,
    required int repetitions,
    required int lapses,
  }) {
    final ease = _clampEase(easeFactor);
    switch (rating) {
      case MemoryCardRating.again:
        final failed = status == MemoryCardStatus.review;
        return MemoryCardSchedule(
          status: MemoryCardStatus.learning,
          dueAt: now.add(relearningStep),
          intervalDays: 0,
          easeFactor: status == MemoryCardStatus.review
              ? _clampEase(ease - 0.20)
              : ease,
          repetitions: 0,
          lapses: failed ? lapses + 1 : lapses,
        );
      case MemoryCardRating.good:
        if (status == MemoryCardStatus.review) {
          final nextInterval = _goodReviewInterval(intervalDays, ease);
          return MemoryCardSchedule(
            status: MemoryCardStatus.review,
            dueAt: _dueAfterDays(now, nextInterval),
            intervalDays: nextInterval,
            easeFactor: ease,
            repetitions: repetitions + 1,
            lapses: lapses,
          );
        }
        return MemoryCardSchedule(
          status: MemoryCardStatus.review,
          dueAt: _dueAfterDays(now, 1),
          intervalDays: 1,
          easeFactor: ease,
          repetitions: 1,
          lapses: lapses,
        );
      case MemoryCardRating.easy:
        final nextEase = _clampEase(ease + 0.15);
        if (status == MemoryCardStatus.review) {
          final nextInterval = _easyReviewInterval(intervalDays, ease);
          return MemoryCardSchedule(
            status: MemoryCardStatus.review,
            dueAt: _dueAfterDays(now, nextInterval),
            intervalDays: nextInterval,
            easeFactor: nextEase,
            repetitions: repetitions + 1,
            lapses: lapses,
          );
        }
        return MemoryCardSchedule(
          status: MemoryCardStatus.review,
          dueAt: _dueAfterDays(now, 4),
          intervalDays: 4,
          easeFactor: nextEase,
          repetitions: 1,
          lapses: lapses,
        );
    }
  }

  static double _goodReviewInterval(double intervalDays, double ease) {
    final interval = (intervalDays <= 0 ? 1 : intervalDays) * ease;
    return interval < 1 ? 1 : interval.roundToDouble();
  }

  static double _easyReviewInterval(double intervalDays, double ease) {
    final interval = (intervalDays <= 0 ? 1 : intervalDays) * ease * 1.3;
    return interval < 1 ? 1 : interval.roundToDouble();
  }

  static DateTime _dueAfterDays(DateTime now, double days) {
    return now.add(Duration(days: days.round()));
  }

  static double _clampEase(double value) {
    if (value < minEaseFactor) return minEaseFactor;
    if (value > maxEaseFactor) return maxEaseFactor;
    return value;
  }
}
