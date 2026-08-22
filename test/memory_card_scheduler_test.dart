import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/memory_card.dart';
import 'package:lynai/models/memory_card_review_log.dart';
import 'package:lynai/services/memory_card_scheduler.dart';

void main() {
  group('MemoryCardScheduler', () {
    final now = DateTime(2026, 8, 16, 12);
    const config = MemoryCardSchedulerConfig(fuzzEnabled: false);

    test('new card graduates with good rating after 1 day', () {
      final result = MemoryCardScheduler.schedule(
        status: MemoryCardStatus.newCard,
        now: now,
        rating: MemoryCardRating.good,
        intervalDays: 0,
        easeFactor: MemoryCardScheduler.defaultEaseFactor,
        repetitions: 0,
        lapses: 0,
        config: config,
      );
      expect(result.status, MemoryCardStatus.review);
      expect(result.intervalDays, 1);
      expect(result.repetitions, 1);
      expect(result.dueAt, now.add(const Duration(days: 1)));
    });

    test('new card easy rating graduates after 4 days and raises ease', () {
      final result = MemoryCardScheduler.schedule(
        status: MemoryCardStatus.newCard,
        now: now,
        rating: MemoryCardRating.easy,
        intervalDays: 0,
        easeFactor: MemoryCardScheduler.defaultEaseFactor,
        repetitions: 0,
        lapses: 0,
        config: config,
      );
      expect(result.status, MemoryCardStatus.review);
      expect(result.intervalDays, 4);
      expect(result.easeFactor, closeTo(2.65, 0.001));
    });

    test('again rating puts new card into first learning step', () {
      final result = MemoryCardScheduler.schedule(
        status: MemoryCardStatus.newCard,
        now: now,
        rating: MemoryCardRating.again,
        intervalDays: 0,
        easeFactor: MemoryCardScheduler.defaultEaseFactor,
        repetitions: 0,
        lapses: 0,
        config: config,
      );
      expect(result.status, MemoryCardStatus.learning);
      expect(result.intervalDays, 0);
      expect(result.dueAt, now.add(const Duration(minutes: 1)));
      expect(result.remainingSteps, config.learningSteps.length);
      expect(result.lapses, 0);
    });

    test('learning card advances through learning steps with good', () {
      final first = MemoryCardScheduler.schedule(
        status: MemoryCardStatus.newCard,
        now: now,
        rating: MemoryCardRating.again,
        intervalDays: 0,
        easeFactor: 2.5,
        repetitions: 0,
        lapses: 0,
        config: config,
      );
      final second = MemoryCardScheduler.schedule(
        status: first.status,
        now: first.dueAt,
        rating: MemoryCardRating.good,
        intervalDays: first.intervalDays,
        easeFactor: first.easeFactor,
        repetitions: first.repetitions,
        lapses: first.lapses,
        remainingSteps: first.remainingSteps,
        config: config,
      );
      expect(second.status, MemoryCardStatus.learning);
      expect(second.dueAt, first.dueAt.add(const Duration(minutes: 10)));
      expect(second.remainingSteps, 1);

      final graduated = MemoryCardScheduler.schedule(
        status: second.status,
        now: second.dueAt,
        rating: MemoryCardRating.good,
        intervalDays: second.intervalDays,
        easeFactor: second.easeFactor,
        repetitions: second.repetitions,
        lapses: second.lapses,
        remainingSteps: second.remainingSteps,
        config: config,
      );
      expect(graduated.status, MemoryCardStatus.review);
      expect(graduated.intervalDays, 1);
      expect(graduated.repetitions, 1);
    });

    test('hard rating keeps learning card on current step', () {
      final first = MemoryCardScheduler.schedule(
        status: MemoryCardStatus.newCard,
        now: now,
        rating: MemoryCardRating.again,
        intervalDays: 0,
        easeFactor: 2.5,
        repetitions: 0,
        lapses: 0,
        config: config,
      );
      final hard = MemoryCardScheduler.schedule(
        status: first.status,
        now: first.dueAt,
        rating: MemoryCardRating.hard,
        intervalDays: first.intervalDays,
        easeFactor: first.easeFactor,
        repetitions: first.repetitions,
        lapses: first.lapses,
        remainingSteps: first.remainingSteps,
        config: config,
      );
      expect(hard.status, MemoryCardStatus.learning);
      expect(hard.dueAt, first.dueAt.add(const Duration(minutes: 1)));
      expect(hard.remainingSteps, first.remainingSteps);
    });

    test('failing a review card enters relearning and lowers ease', () {
      final result = MemoryCardScheduler.schedule(
        status: MemoryCardStatus.review,
        now: now,
        rating: MemoryCardRating.again,
        intervalDays: 10,
        easeFactor: 2.5,
        repetitions: 3,
        lapses: 1,
        config: config,
      );
      expect(result.status, MemoryCardStatus.relearning);
      expect(result.dueAt, now.add(const Duration(minutes: 10)));
      expect(result.lapses, 2);
      expect(result.repetitions, 0);
      expect(result.easeFactor, closeTo(2.3, 0.001));
      expect(result.intervalDays, 1);
    });

    test('relearning good returns card to review with lapse interval', () {
      final failed = MemoryCardScheduler.schedule(
        status: MemoryCardStatus.review,
        now: now,
        rating: MemoryCardRating.again,
        intervalDays: 10,
        easeFactor: 2.5,
        repetitions: 3,
        lapses: 1,
        config: config,
      );
      final relearned = MemoryCardScheduler.schedule(
        status: failed.status,
        now: failed.dueAt,
        rating: MemoryCardRating.good,
        intervalDays: failed.intervalDays,
        easeFactor: failed.easeFactor,
        repetitions: failed.repetitions,
        lapses: failed.lapses,
        remainingSteps: failed.remainingSteps,
        config: config,
      );
      expect(relearned.status, MemoryCardStatus.review);
      expect(relearned.intervalDays, 1);
      expect(relearned.repetitions, 1);
    });

    test('relearning again repeats relearning step without extra lapse', () {
      final failed = MemoryCardScheduler.schedule(
        status: MemoryCardStatus.review,
        now: now,
        rating: MemoryCardRating.again,
        intervalDays: 10,
        easeFactor: 2.5,
        repetitions: 3,
        lapses: 1,
        config: config,
      );
      final repeated = MemoryCardScheduler.schedule(
        status: failed.status,
        now: failed.dueAt,
        rating: MemoryCardRating.again,
        intervalDays: failed.intervalDays,
        easeFactor: failed.easeFactor,
        repetitions: failed.repetitions,
        lapses: failed.lapses,
        remainingSteps: failed.remainingSteps,
        config: config,
      );
      expect(repeated.status, MemoryCardStatus.relearning);
      expect(repeated.dueAt, failed.dueAt.add(const Duration(minutes: 10)));
      expect(repeated.lapses, 2);
      expect(repeated.remainingSteps, config.relearningSteps.length);
    });

    test(
      'review hard rating expands interval by hard multiplier and lowers ease',
      () {
        final result = MemoryCardScheduler.schedule(
          status: MemoryCardStatus.review,
          now: now,
          rating: MemoryCardRating.hard,
          intervalDays: 10,
          easeFactor: 2.5,
          repetitions: 3,
          lapses: 0,
          config: config,
        );
        expect(result.status, MemoryCardStatus.review);
        expect(result.intervalDays, 12);
        expect(result.repetitions, 4);
        expect(result.easeFactor, closeTo(2.35, 0.001));
      },
    );

    test('review good rating expands interval by ease factor', () {
      final result = MemoryCardScheduler.schedule(
        status: MemoryCardStatus.review,
        now: now,
        rating: MemoryCardRating.good,
        intervalDays: 10,
        easeFactor: 2.5,
        repetitions: 3,
        lapses: 0,
        config: config,
      );
      expect(result.status, MemoryCardStatus.review);
      expect(result.intervalDays, 25);
      expect(result.repetitions, 4);
    });

    test('review easy rating expands interval and caps ease at 3.5', () {
      final result = MemoryCardScheduler.schedule(
        status: MemoryCardStatus.review,
        now: now,
        rating: MemoryCardRating.easy,
        intervalDays: 10,
        easeFactor: 3.4,
        repetitions: 3,
        lapses: 0,
        config: config,
      );
      expect(result.intervalDays, 44);
      expect(result.easeFactor, closeTo(3.5, 0.001));
    });

    test('maximum review interval is enforced', () {
      final result = MemoryCardScheduler.schedule(
        status: MemoryCardStatus.review,
        now: now,
        rating: MemoryCardRating.good,
        intervalDays: 30000,
        easeFactor: 3.5,
        repetitions: 3,
        lapses: 0,
        config: const MemoryCardSchedulerConfig(
          fuzzEnabled: false,
          maximumIntervalDays: 365,
        ),
      );
      expect(result.intervalDays, 365);
    });

    test('leech threshold marks review failure', () {
      final result = MemoryCardScheduler.schedule(
        status: MemoryCardStatus.review,
        now: now,
        rating: MemoryCardRating.again,
        intervalDays: 10,
        easeFactor: 2.5,
        repetitions: 3,
        lapses: 7,
        config: const MemoryCardSchedulerConfig(
          fuzzEnabled: false,
          leechThreshold: 8,
        ),
      );
      expect(result.lapses, 8);
      expect(result.leeched, isTrue);
    });
  });
}
