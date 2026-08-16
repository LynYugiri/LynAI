import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/memory_card.dart';
import 'package:lynai/models/memory_card_deck.dart';
import 'package:lynai/models/memory_card_review_log.dart';

void main() {
  test('memory card model JSON roundtrip preserves scheduling fields', () {
    final now = DateTime.utc(2026, 8, 16, 12);
    final card = MemoryCard(
      id: 'card-1',
      deckId: 'deck-1',
      front: '什么是 2+2？',
      back: r'$4$',
      hint: '基础算术',
      sourceKind: MemoryCardSourceKind.knowledge,
      sourceEntryId: 'entry-1',
      sourceBaseId: 'base-1',
      status: MemoryCardStatus.review,
      dueAt: now.add(const Duration(days: 3)),
      intervalDays: 3,
      easeFactor: 2.5,
      repetitions: 2,
      lapses: 0,
      reviewCount: 2,
      lastReviewedAt: now,
      enabled: true,
      sortOrder: 1,
      createdAt: now,
      updatedAt: now,
    );
    final restored = MemoryCard.fromJson(card.toJson());
    expect(restored.id, card.id);
    expect(restored.front, card.front);
    expect(restored.back, card.back);
    expect(restored.sourceKind, MemoryCardSourceKind.knowledge);
    expect(restored.status, MemoryCardStatus.review);
    expect(restored.intervalDays, 3);
    expect(restored.easeFactor, 2.5);
    expect(restored.isDueAt(now.add(const Duration(days: 3))), isTrue);
    expect(restored.isDueAt(now.add(const Duration(days: 2))), isFalse);
  });

  test('memory card deck JSON roundtrip', () {
    final now = DateTime.utc(2026, 8, 16);
    final deck = MemoryCardDeck(
      id: 'deck-1',
      name: '默认牌组',
      description: '测试',
      newPerDayLimit: 10,
      reviewPerDayLimit: 100,
      enabled: true,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    );
    final restored = MemoryCardDeck.fromJson(deck.toJson());
    expect(restored.newPerDayLimit, 10);
    expect(restored.reviewPerDayLimit, 100);
    expect(restored.description, '测试');
  });

  test('review log JSON roundtrip', () {
    final now = DateTime.utc(2026, 8, 16);
    final log = MemoryCardReviewLog(
      id: 'log-1',
      cardId: 'card-1',
      deckId: 'deck-1',
      reviewedAt: now,
      rating: MemoryCardRating.good,
      statusBefore: MemoryCardStatus.newCard,
      statusAfter: MemoryCardStatus.review,
      intervalDaysBefore: 0,
      intervalDaysAfter: 1,
      easeBefore: 2.5,
      easeAfter: 2.5,
    );
    final restored = MemoryCardReviewLog.fromJson(log.toJson());
    expect(restored.rating, MemoryCardRating.good);
    expect(restored.statusBefore, MemoryCardStatus.newCard);
    expect(restored.statusAfter, MemoryCardStatus.review);
  });
}
