import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/memory_card.dart';
import 'package:lynai/models/memory_card_deck.dart';
import 'package:lynai/models/memory_card_review_log.dart';
import 'package:lynai/providers/memory_card_provider.dart';
import 'package:lynai/repositories/memory_card_repository.dart';

class _FakeMemoryCardRepository extends MemoryCardRepository {
  MemoryCardLoadResult snapshot = const MemoryCardLoadResult(
    decks: [],
    cards: [],
    reviewLogs: [],
  );
  int saveChangesCalls = 0;

  @override
  Future<MemoryCardLoadResult> load() async => snapshot;

  @override
  Future<void> saveChanges({
    Iterable<MemoryCardDeck> upsertDecks = const [],
    Iterable<String> deleteDeckIds = const [],
    Iterable<MemoryCard> upsertCards = const [],
    Iterable<String> deleteCardIds = const [],
    Iterable<MemoryCardReviewLog> upsertReviewLogs = const [],
    Iterable<String> deleteReviewLogIds = const [],
  }) async {
    saveChangesCalls++;
  }

  @override
  Future<void> replace(MemoryCardLoadResult value) async {
    snapshot = value;
  }
}

MemoryCard _card({
  required String id,
  required String deckId,
  required MemoryCardStatus status,
  DateTime? dueAt,
  double intervalDays = 0,
  double easeFactor = 2.5,
  int repetitions = 0,
  int lapses = 0,
  int remainingSteps = 0,
  int sortOrder = 0,
  String front = '',
}) => MemoryCard(
  id: id,
  deckId: deckId,
  front: front.isEmpty ? 'front-$id' : front,
  back: 'back-$id',
  sourceKind: MemoryCardSourceKind.manual,
  status: status,
  dueAt: dueAt,
  intervalDays: intervalDays,
  easeFactor: easeFactor,
  repetitions: repetitions,
  lapses: lapses,
  remainingSteps: remainingSteps,
  reviewCount: 0,
  lastReviewedAt: null,
  enabled: true,
  sortOrder: sortOrder,
  createdAt: DateTime.utc(2026, 8, 16),
  updatedAt: DateTime.utc(2026, 8, 16),
);

void main() {
  test('studyPlan 按学习、复习、新卡顺序出卡并应用每日限额', () async {
    final repository = _FakeMemoryCardRepository();
    final provider = MemoryCardProvider(repository: repository);
    final deckId = await provider.addDeck(name: '测试', newPerDayLimit: 1);
    final now = DateTime(2026, 8, 16, 12);
    await provider.addCards([
      _card(
        id: 'new-1',
        deckId: deckId,
        status: MemoryCardStatus.newCard,
        sortOrder: 0,
      ),
      _card(
        id: 'new-2',
        deckId: deckId,
        status: MemoryCardStatus.newCard,
        sortOrder: 1,
      ),
      _card(
        id: 'learn-1',
        deckId: deckId,
        status: MemoryCardStatus.learning,
        dueAt: now.subtract(const Duration(minutes: 1)),
      ),
      _card(
        id: 'review-1',
        deckId: deckId,
        status: MemoryCardStatus.review,
        dueAt: now.subtract(const Duration(days: 1)),
      ),
    ]);

    final plan = provider.studyPlan(deckId, now: now);

    expect(plan.cards.map((card) => card.id).toList(), [
      'learn-1',
      'review-1',
      'new-1',
    ]);
    expect(plan.counts.newCards, 1);
    expect(plan.counts.learningCards, 1);
    expect(plan.counts.reviewCards, 1);
  });

  test('review 返回 outcome 并写入 remainingSteps 与卡片快照', () async {
    final repository = _FakeMemoryCardRepository();
    final provider = MemoryCardProvider(repository: repository);
    final deckId = await provider.addDeck(name: '测试');
    await provider.addCards([
      _card(id: 'card-1', deckId: deckId, status: MemoryCardStatus.newCard),
    ]);
    final card = provider.cardById('card-1')!;
    final now = DateTime(2026, 8, 16, 12);

    final outcome = await provider.review(
      card,
      MemoryCardRating.again,
      now: now,
    );

    expect(outcome, isNotNull);
    expect(outcome!.card.status, MemoryCardStatus.learning);
    expect(outcome.card.remainingSteps, 2);
    expect(outcome.log.cardStateBefore, isNotNull);
    expect(provider.reviewLogs, hasLength(1));
  });

  test('undoLastReview 恢复卡片并删除复习记录', () async {
    final repository = _FakeMemoryCardRepository();
    final provider = MemoryCardProvider(repository: repository);
    final deckId = await provider.addDeck(name: '测试');
    await provider.addCards([
      _card(
        id: 'card-1',
        deckId: deckId,
        status: MemoryCardStatus.review,
        dueAt: DateTime.utc(2026, 8, 16),
        intervalDays: 10,
        easeFactor: 2.5,
        repetitions: 3,
        lapses: 1,
      ),
    ]);
    final card = provider.cardById('card-1')!;
    await provider.review(
      card,
      MemoryCardRating.good,
      now: DateTime(2026, 8, 16, 12),
    );
    expect(provider.reviewLogs, hasLength(1));

    final restored = await provider.undoLastReview(deckId);

    expect(restored, isTrue);
    expect(provider.reviewLogs, isEmpty);
    final current = provider.cardById('card-1')!;
    expect(current.status, MemoryCardStatus.review);
    expect(current.intervalDays, 10);
    expect(current.repetitions, 3);
    expect(current.lapses, 1);
  });

  test('addCards 跳过重复并返回实际写入数量', () async {
    final repository = _FakeMemoryCardRepository();
    final provider = MemoryCardProvider(repository: repository);
    final deckId = await provider.addDeck(name: '测试');

    final first = await provider.addCards([
      _card(id: 'card-1', deckId: deckId, status: MemoryCardStatus.newCard),
    ]);
    final second = await provider.addCards([
      _card(id: 'card-2', deckId: deckId, status: MemoryCardStatus.newCard),
      _card(id: 'card-1', deckId: deckId, status: MemoryCardStatus.newCard),
    ]);

    expect(first, 1);
    expect(second, 1);
    expect(provider.cardsForDeck(deckId), hasLength(2));
    expect(provider.cardsForDeck(deckId).map((card) => card.sortOrder), [0, 1]);
  });
}
