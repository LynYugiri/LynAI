import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/memory_card.dart';
import 'package:lynai/models/memory_card_review_log.dart';
import 'package:lynai/services/memory_card_scheduler.dart';

void main() {
  group('MemoryCardScheduler', () {
    final now = DateTime(2026, 8, 16, 12);

    test('new card graduates with good rating after 1 day', () {
      final result = MemoryCardScheduler.schedule(
        status: MemoryCardStatus.newCard,
        now: now,
        rating: MemoryCardRating.good,
        intervalDays: 0,
        easeFactor: MemoryCardScheduler.defaultEaseFactor,
        repetitions: 0,
        lapses: 0,
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
      );
      expect(result.status, MemoryCardStatus.review);
      expect(result.intervalDays, 4);
      expect(result.easeFactor, closeTo(2.65, 0.001));
    });

    test('again rating keeps card in learning for 10 minutes', () {
      final result = MemoryCardScheduler.schedule(
        status: MemoryCardStatus.newCard,
        now: now,
        rating: MemoryCardRating.again,
        intervalDays: 0,
        easeFactor: MemoryCardScheduler.defaultEaseFactor,
        repetitions: 0,
        lapses: 0,
      );
      expect(result.status, MemoryCardStatus.learning);
      expect(result.intervalDays, 0);
      expect(result.dueAt, now.add(const Duration(minutes: 10)));
      expect(result.lapses, 0);
    });

    test('failing a review card increments lapses and lowers ease', () {
      final result = MemoryCardScheduler.schedule(
        status: MemoryCardStatus.review,
        now: now,
        rating: MemoryCardRating.again,
        intervalDays: 10,
        easeFactor: 2.5,
        repetitions: 3,
        lapses: 1,
      );
      expect(result.status, MemoryCardStatus.learning);
      expect(result.lapses, 2);
      expect(result.repetitions, 0);
      expect(result.easeFactor, closeTo(2.3, 0.001));
    });

    test('review good rating expands interval by ease factor', () {
      final result = MemoryCardScheduler.schedule(
        status: MemoryCardStatus.review,
        now: now,
        rating: MemoryCardRating.good,
        intervalDays: 10,
        easeFactor: 2.5,
        repetitions: 3,
        lapses: 0,
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
      );
      expect(result.intervalDays, 44);
      expect(result.easeFactor, closeTo(3.5, 0.001));
    });
  });
}
