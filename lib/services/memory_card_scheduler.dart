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
    this.remainingSteps = 0,
    this.leeched = false,
  });

  final MemoryCardStatus status;
  final DateTime dueAt;

  /// 复习状态的间隔天数；学习/重学状态下表示离开当前阶段后使用的天数。
  final double intervalDays;
  final double easeFactor;
  final int repetitions;
  final int lapses;
  final int remainingSteps;

  /// 是否达到 leech 阈值（供上层提示或停用卡片）。
  final bool leeched;
}

/// 记忆卡片调度参数。
final class MemoryCardSchedulerConfig {
  const MemoryCardSchedulerConfig({
    this.learningSteps = const [Duration(minutes: 1), Duration(minutes: 10)],
    this.relearningSteps = const [Duration(minutes: 10)],
    this.graduatingGoodIntervalDays = 1,
    this.graduatingEasyIntervalDays = 4,
    this.initialEaseFactor = 2.5,
    this.minEaseFactor = 1.3,
    this.maxEaseFactor = 3.5,
    this.hardMultiplier = 1.2,
    this.easyMultiplier = 1.3,
    this.lapseMultiplier = 0.0,
    this.maximumIntervalDays = 36500,
    this.leechThreshold = 0,
    this.fuzzEnabled = true,
  });

  final List<Duration> learningSteps;
  final List<Duration> relearningSteps;
  final double graduatingGoodIntervalDays;
  final double graduatingEasyIntervalDays;
  final double initialEaseFactor;
  final double minEaseFactor;
  final double maxEaseFactor;
  final double hardMultiplier;
  final double easyMultiplier;
  final double lapseMultiplier;
  final double maximumIntervalDays;
  final int leechThreshold;
  final bool fuzzEnabled;
}

/// 纯函数实现的简化 SM-2 间隔重复调度器。
///
/// 四档评分：忘记(again) / 困难(hard) / 良好(good) / 简单(easy)。
/// 学习阶段使用 [MemoryCardSchedulerConfig.learningSteps] 逐步推进；
/// 复习卡失败进入 relearning，重学完成后再回到复习队列。
abstract final class MemoryCardScheduler {
  static const double defaultEaseFactor = 2.5;
  static const double minEaseFactor = 1.3;
  static const double maxEaseFactor = 3.5;

  static MemoryCardSchedule schedule({
    required MemoryCardStatus status,
    required DateTime now,
    required MemoryCardRating rating,
    required double intervalDays,
    required double easeFactor,
    required int repetitions,
    required int lapses,
    int remainingSteps = 0,
    int? fuzzSeed,
    MemoryCardSchedulerConfig config = const MemoryCardSchedulerConfig(),
  }) {
    final ease = _clampEase(
      easeFactor,
      config.minEaseFactor,
      config.maxEaseFactor,
    );
    switch (rating) {
      case MemoryCardRating.again:
        return _answerAgain(
          status,
          now,
          intervalDays,
          ease,
          repetitions,
          lapses,
          remainingSteps,
          config,
        );
      case MemoryCardRating.hard:
        return _answerHard(
          status,
          now,
          intervalDays,
          ease,
          repetitions,
          lapses,
          remainingSteps,
          fuzzSeed,
          config,
        );
      case MemoryCardRating.good:
        return _answerGood(
          status,
          now,
          intervalDays,
          ease,
          repetitions,
          lapses,
          remainingSteps,
          fuzzSeed,
          config,
        );
      case MemoryCardRating.easy:
        return _answerEasy(
          status,
          now,
          intervalDays,
          ease,
          repetitions,
          lapses,
          remainingSteps,
          fuzzSeed,
          config,
        );
    }
  }

  // ─── 各评分实现 ───

  static MemoryCardSchedule _answerAgain(
    MemoryCardStatus status,
    DateTime now,
    double intervalDays,
    double ease,
    int repetitions,
    int lapses,
    int remainingSteps,
    MemoryCardSchedulerConfig config,
  ) {
    if (status == MemoryCardStatus.review) {
      final nextLapses = lapses + 1;
      return MemoryCardSchedule(
        status: MemoryCardStatus.relearning,
        dueAt: now.add(_firstStep(config.relearningSteps)),
        intervalDays: _lapseInterval(intervalDays, config),
        easeFactor: _clampEase(
          ease - 0.20,
          config.minEaseFactor,
          config.maxEaseFactor,
        ),
        repetitions: 0,
        lapses: nextLapses,
        remainingSteps: config.relearningSteps.length,
        leeched: _withLeechCheck(nextLapses, config),
      );
    }

    final isRelearning = status == MemoryCardStatus.relearning;
    return MemoryCardSchedule(
      status: isRelearning
          ? MemoryCardStatus.relearning
          : MemoryCardStatus.learning,
      dueAt: now.add(
        _firstStep(
          isRelearning ? config.relearningSteps : config.learningSteps,
        ),
      ),
      intervalDays: isRelearning ? intervalDays : 0,
      easeFactor: ease,
      repetitions: 0,
      lapses: lapses,
      remainingSteps: isRelearning
          ? config.relearningSteps.length
          : config.learningSteps.length,
    );
  }

  static MemoryCardSchedule _answerHard(
    MemoryCardStatus status,
    DateTime now,
    double intervalDays,
    double ease,
    int repetitions,
    int lapses,
    int remainingSteps,
    int? fuzzSeed,
    MemoryCardSchedulerConfig config,
  ) {
    switch (status) {
      case MemoryCardStatus.review:
        final nextInterval = _cappedInterval(
          _fuzzInterval(
            _positiveInterval(intervalDays) * config.hardMultiplier,
            fuzzSeed,
            config,
          ),
          config,
        );
        return MemoryCardSchedule(
          status: MemoryCardStatus.review,
          dueAt: _dueAfterDays(now, nextInterval),
          intervalDays: nextInterval,
          easeFactor: _clampEase(
            ease - 0.15,
            config.minEaseFactor,
            config.maxEaseFactor,
          ),
          repetitions: repetitions + 1,
          lapses: lapses,
        );
      case MemoryCardStatus.newCard:
        return _answerGood(
          status,
          now,
          intervalDays,
          ease,
          repetitions,
          lapses,
          remainingSteps,
          fuzzSeed,
          config,
        );
      case MemoryCardStatus.learning:
      case MemoryCardStatus.relearning:
        final steps = status == MemoryCardStatus.learning
            ? config.learningSteps
            : config.relearningSteps;
        final index = _stepIndex(steps, remainingSteps);
        final step = steps.isEmpty ? const Duration(minutes: 10) : steps[index];
        return MemoryCardSchedule(
          status: status,
          dueAt: now.add(step),
          intervalDays: intervalDays,
          easeFactor: ease,
          repetitions: repetitions,
          lapses: lapses,
          remainingSteps: remainingSteps,
        );
    }
  }

  static MemoryCardSchedule _answerGood(
    MemoryCardStatus status,
    DateTime now,
    double intervalDays,
    double ease,
    int repetitions,
    int lapses,
    int remainingSteps,
    int? fuzzSeed,
    MemoryCardSchedulerConfig config,
  ) {
    switch (status) {
      case MemoryCardStatus.review:
        final nextInterval = _cappedInterval(
          _fuzzInterval(
            _positiveInterval(intervalDays) * ease,
            fuzzSeed,
            config,
          ),
          config,
        );
        return MemoryCardSchedule(
          status: MemoryCardStatus.review,
          dueAt: _dueAfterDays(now, nextInterval),
          intervalDays: nextInterval,
          easeFactor: ease,
          repetitions: repetitions + 1,
          lapses: lapses,
        );
      case MemoryCardStatus.newCard:
        return _graduate(
          now,
          config.graduatingGoodIntervalDays,
          ease,
          repetitions + 1,
          lapses,
        );
      case MemoryCardStatus.learning:
        final steps = config.learningSteps;
        final index = _stepIndex(steps, remainingSteps);
        if (index + 1 < steps.length) {
          return MemoryCardSchedule(
            status: MemoryCardStatus.learning,
            dueAt: now.add(steps[index + 1]),
            intervalDays: 0,
            easeFactor: ease,
            repetitions: repetitions,
            lapses: lapses,
            remainingSteps: steps.length - (index + 1),
          );
        }
        return _graduate(
          now,
          config.graduatingGoodIntervalDays,
          ease,
          repetitions + 1,
          lapses,
        );
      case MemoryCardStatus.relearning:
        return MemoryCardSchedule(
          status: MemoryCardStatus.review,
          dueAt: _dueAfterDays(now, _positiveInterval(intervalDays)),
          intervalDays: _positiveInterval(intervalDays),
          easeFactor: ease,
          repetitions: repetitions + 1,
          lapses: lapses,
        );
    }
  }

  static MemoryCardSchedule _answerEasy(
    MemoryCardStatus status,
    DateTime now,
    double intervalDays,
    double ease,
    int repetitions,
    int lapses,
    int remainingSteps,
    int? fuzzSeed,
    MemoryCardSchedulerConfig config,
  ) {
    final nextEase = _clampEase(
      ease + 0.15,
      config.minEaseFactor,
      config.maxEaseFactor,
    );
    switch (status) {
      case MemoryCardStatus.review:
        final nextInterval = _cappedInterval(
          _fuzzInterval(
            _positiveInterval(intervalDays) * ease * config.easyMultiplier,
            fuzzSeed,
            config,
          ),
          config,
        );
        return MemoryCardSchedule(
          status: MemoryCardStatus.review,
          dueAt: _dueAfterDays(now, nextInterval),
          intervalDays: nextInterval,
          easeFactor: nextEase,
          repetitions: repetitions + 1,
          lapses: lapses,
        );
      case MemoryCardStatus.newCard:
        return _graduate(
          now,
          config.graduatingEasyIntervalDays,
          nextEase,
          repetitions + 1,
          lapses,
        );
      case MemoryCardStatus.learning:
        return _graduate(
          now,
          config.graduatingEasyIntervalDays,
          nextEase,
          repetitions + 1,
          lapses,
        );
      case MemoryCardStatus.relearning:
        final nextInterval = _cappedInterval(
          _positiveInterval(intervalDays) * config.easyMultiplier,
          config,
        );
        return MemoryCardSchedule(
          status: MemoryCardStatus.review,
          dueAt: _dueAfterDays(now, nextInterval),
          intervalDays: nextInterval,
          easeFactor: nextEase,
          repetitions: repetitions + 1,
          lapses: lapses,
        );
    }
  }

  // ─── 辅助函数 ───

  static MemoryCardSchedule _graduate(
    DateTime now,
    double intervalDays,
    double ease,
    int repetitions,
    int lapses,
  ) => MemoryCardSchedule(
    status: MemoryCardStatus.review,
    dueAt: _dueAfterDays(now, intervalDays),
    intervalDays: intervalDays,
    easeFactor: ease,
    repetitions: repetitions,
    lapses: lapses,
  );

  static double _lapseInterval(
    double currentIntervalDays,
    MemoryCardSchedulerConfig config,
  ) {
    if (config.lapseMultiplier <= 0) return 1;
    return _cappedInterval(
      _positiveInterval(currentIntervalDays) * config.lapseMultiplier,
      config,
    );
  }

  static double _positiveInterval(double intervalDays) =>
      intervalDays <= 0 ? 1 : intervalDays;

  static double _cappedInterval(
    double intervalDays,
    MemoryCardSchedulerConfig config,
  ) => intervalDays
      .roundToDouble()
      .clamp(1.0, config.maximumIntervalDays)
      .toDouble();

  static double _fuzzInterval(
    double intervalDays,
    int? fuzzSeed,
    MemoryCardSchedulerConfig config,
  ) {
    if (!config.fuzzEnabled || fuzzSeed == null) return intervalDays;
    final normalized = (fuzzSeed.abs() % 100) / 100;
    return intervalDays * (0.95 + normalized * 0.1);
  }

  static DateTime _dueAfterDays(DateTime now, double days) {
    return now.add(Duration(days: days.round()));
  }

  static Duration _firstStep(List<Duration> steps) {
    if (steps.isEmpty) return const Duration(minutes: 10);
    return steps.first;
  }

  static int _stepIndex(List<Duration> steps, int remainingSteps) {
    if (steps.isEmpty) return 0;
    final total = steps.length;
    return (total - remainingSteps).clamp(0, total - 1);
  }

  static double _clampEase(double value, double minEase, double maxEase) {
    if (value < minEase) return minEase;
    if (value > maxEase) return maxEase;
    return value;
  }

  static bool _withLeechCheck(int lapses, MemoryCardSchedulerConfig config) {
    return config.leechThreshold > 0 && lapses >= config.leechThreshold;
  }
}
