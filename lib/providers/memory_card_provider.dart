import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/memory_card.dart';
import '../models/memory_card_deck.dart';
import '../models/memory_card_review_log.dart';
import '../repositories/memory_card_repository.dart';
import '../services/memory_card_scheduler.dart';
import '../services/storage_v2_service.dart';
import 'serialized_save_queue.dart';

/// 管理记忆卡片牌组、卡片与复习记录的内存状态和串行持久化。
class MemoryCardProvider extends ChangeNotifier with SerializedSaveQueue {
  static const builtInDefaultDeckId = 'builtin-default-memory-card-deck';
  static const builtInDefaultDeckName = '默认牌组';

  MemoryCardProvider({
    StorageV2Service? storageV2,
    MemoryCardRepository? repository,
  }) : _repository = repository ?? MemoryCardRepository(storageV2: storageV2);

  final MemoryCardRepository _repository;
  final _uuid = const Uuid();
  List<MemoryCardDeck> _decks = [];
  List<MemoryCard> _cards = [];
  List<MemoryCardReviewLog> _reviewLogs = [];
  int _mutationGeneration = 0;

  List<MemoryCardDeck> get decks => List.unmodifiable(_decks);
  List<MemoryCard> get cards => List.unmodifiable(_cards);
  List<MemoryCardReviewLog> get reviewLogs => List.unmodifiable(_reviewLogs);

  MemoryCardDeck? deckById(String id) =>
      _first(_decks, (item) => item.id == id);
  MemoryCard? cardById(String id) =>
      _first(_cards, (item) => item.id == id);

  List<MemoryCard> cardsForDeck(String deckId) => List.unmodifiable(
    _cards.where((item) => item.deckId == deckId),
  );

  List<MemoryCardReviewLog> reviewLogsForDeck(String deckId) =>
      List.unmodifiable(
        _reviewLogs.where((item) => item.deckId == deckId),
      );

  Future<void> load() async {
    final generation = _mutationGeneration;
    await flushPendingSaves();
    final result = await _repository.load();
    if (generation != _mutationGeneration) return;
    _decks = List.of(result.decks)..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final deckIds = _decks.map((deck) => deck.id).toSet();
    _cards = result.cards
        .where((card) => deckIds.contains(card.deckId))
        .toList();
    final cardIds = _cards.map((card) => card.id).toSet();
    _reviewLogs = result.reviewLogs
        .where(
          (log) => deckIds.contains(log.deckId) && cardIds.contains(log.cardId),
        )
        .toList();
    final createdDefault = _ensureDefaultDeckInMemory();
    notifyListeners();
    if (createdDefault) {
      final replacement = _snapshot();
      await _queueSave(() => _repository.replace(replacement));
    }
  }

  Future<void> replaceAll({
    required List<MemoryCardDeck> decks,
    required List<MemoryCard> cards,
    required List<MemoryCardReviewLog> reviewLogs,
  }) async {
    _mutationGeneration++;
    _decks = List.of(decks)..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final deckIds = _decks.map((deck) => deck.id).toSet();
    _cards = cards.where((card) => deckIds.contains(card.deckId)).toList();
    final cardIds = _cards.map((card) => card.id).toSet();
    _reviewLogs = reviewLogs
        .where(
          (log) => deckIds.contains(log.deckId) && cardIds.contains(log.cardId),
        )
        .toList();
    _ensureDefaultDeckInMemory();
    final replacement = _snapshot();
    notifyListeners();
    await _queueSave(() => _repository.replace(replacement));
  }

  // ─── 牌组 ───

  Future<String> addDeck({
    required String name,
    String? description,
    int newPerDayLimit = 20,
    int reviewPerDayLimit = 200,
  }) async {
    final now = DateTime.now();
    final item = MemoryCardDeck(
      id: _uuid.v4(),
      name: name,
      description: description,
      newPerDayLimit: newPerDayLimit,
      reviewPerDayLimit: reviewPerDayLimit,
      enabled: true,
      sortOrder: _decks.length,
      createdAt: now,
      updatedAt: now,
    );
    _decks.add(item);
    notifyListeners();
    await _queueSave(() => _repository.saveChanges(upsertDecks: [item]));
    return item.id;
  }

  Future<void> updateDeck(MemoryCardDeck value) async {
    final index = _decks.indexWhere((item) => item.id == value.id);
    if (index < 0) return;
    final current = _decks[index];
    final updated = value.copyWith(
      sortOrder: current.sortOrder,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    _decks[index] = updated;
    notifyListeners();
    await _queueSave(() => _repository.saveChanges(upsertDecks: [updated]));
  }

  Future<void> deleteDeck(String id) async {
    if (id == builtInDefaultDeckId) {
      throw ArgumentError.value(id, 'id', '内置默认牌组不可删除');
    }
    final index = _decks.indexWhere((item) => item.id == id);
    if (index < 0) return;
    _decks.removeAt(index);
    final cardIds = _cards
        .where((item) => item.deckId == id)
        .map((item) => item.id)
        .toList();
    final reviewLogIds = _reviewLogs
        .where((item) => item.deckId == id)
        .map((item) => item.id)
        .toList();
    _reviewLogs.removeWhere((item) => item.deckId == id);
    _cards.removeWhere((item) => item.deckId == id);
    notifyListeners();
    await _queueSave(
      () => _repository.saveChanges(
        deleteReviewLogIds: reviewLogIds,
        deleteCardIds: cardIds,
        deleteDeckIds: [id],
      ),
    );
  }

  // ─── 卡片 ───

  Future<String> addCard({
    required String deckId,
    required String front,
    required String back,
    String? hint,
    MemoryCardSourceKind sourceKind = MemoryCardSourceKind.manual,
    String? sourceEntryId,
    String? sourceBaseId,
  }) async {
    final deck = deckById(deckId);
    if (deck == null) throw StateError('牌组不存在或已删除');
    final now = DateTime.now();
    final item = MemoryCard(
      id: _uuid.v4(),
      deckId: deckId,
      front: front,
      back: back,
      hint: hint,
      sourceKind: sourceKind,
      sourceEntryId: sourceEntryId,
      sourceBaseId: sourceBaseId,
      status: MemoryCardStatus.newCard,
      dueAt: null,
      intervalDays: 0,
      easeFactor: MemoryCardScheduler.defaultEaseFactor,
      repetitions: 0,
      lapses: 0,
      reviewCount: 0,
      lastReviewedAt: null,
      enabled: true,
      sortOrder: cardsForDeck(deckId).length,
      createdAt: now,
      updatedAt: now,
    );
    _cards.add(item);
    notifyListeners();
    await _queueSave(() => _repository.saveChanges(upsertCards: [item]));
    return item.id;
  }

  Future<void> addCards(
    Iterable<MemoryCard> items,
  ) async {
    final now = DateTime.now();
    final normalized = <MemoryCard>[];
    final seen = <String>{
      for (final card in _cards)
        '${card.deckId}\u0000${card.front.trim()}\u0000${card.back.trim()}',
    };
    for (final item in items) {
      if (item.front.trim().isEmpty || item.back.trim().isEmpty) continue;
      if (!seen.add(
        '${item.deckId}\u0000${item.front.trim()}\u0000${item.back.trim()}',
      )) {
        continue;
      }
      final deck = deckById(item.deckId);
      if (deck == null) continue;
      normalized.add(
        item.copyWith(
          sortOrder: cardsForDeck(item.deckId).length + normalized.length,
          createdAt: item.createdAt.isBefore(now) ? item.createdAt : now,
          updatedAt: now,
        ),
      );
    }
    if (normalized.isEmpty) return;
    _cards.addAll(normalized);
    notifyListeners();
    await _queueSave(
      () => _repository.saveChanges(upsertCards: List.of(normalized)),
    );
  }

  Future<String> ensureDeckByName(String name) async {
    final existing = _first(
      _decks,
      (item) => item.name.trim().toLowerCase() == name.trim().toLowerCase(),
    );
    if (existing != null) return existing.id;
    return addDeck(name: name.trim());
  }

  Future<void> updateCard(MemoryCard value) async {
    final index = _cards.indexWhere((item) => item.id == value.id);
    if (index < 0) return;
    final current = _cards[index];
    final updated = value.copyWith(
      sortOrder: current.sortOrder,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    _cards[index] = updated;
    notifyListeners();
    await _queueSave(() => _repository.saveChanges(upsertCards: [updated]));
  }

  Future<void> deleteCard(String id) async {
    final index = _cards.indexWhere((item) => item.id == id);
    if (index < 0) return;
    _cards.removeAt(index);
    final reviewLogIds = _reviewLogs
        .where((item) => item.cardId == id)
        .map((item) => item.id)
        .toList();
    _reviewLogs.removeWhere((item) => item.cardId == id);
    notifyListeners();
    await _queueSave(
      () => _repository.saveChanges(
        deleteReviewLogIds: reviewLogIds,
        deleteCardIds: [id],
      ),
    );
  }

  Future<void> setCardEnabled(String id, bool enabled) async {
    final card = cardById(id);
    if (card == null) return;
    await updateCard(card.copyWith(enabled: enabled));
  }

  // ─── 复习 ───

  int newStudiedToday(String deckId, {DateTime? now}) {
    final effectiveNow = now ?? DateTime.now();
    final localDayStart = DateTime(
      effectiveNow.year,
      effectiveNow.month,
      effectiveNow.day,
    );
    return _reviewLogs
        .where(
          (log) =>
              log.deckId == deckId &&
              log.statusBefore == MemoryCardStatus.newCard &&
              !log.reviewedAt.isBefore(localDayStart) &&
              log.reviewedAt.isBefore(
                localDayStart.add(const Duration(days: 1)),
              ),
        )
        .length;
  }

  /// 获取牌组当前应复习的卡片，受每日新卡与复习上限约束。
  List<MemoryCard> dueCards(String deckId, {DateTime? now}) {
    final deck = deckById(deckId);
    if (deck == null || !deck.enabled) return const [];
    final effectiveNow = now ?? DateTime.now();
    final due = cardsForDeck(deckId).where((card) {
      if (!card.isDueAt(effectiveNow)) return false;
      return true;
    }).toList(growable: false);

    final newCards = due
        .where((card) => card.status == MemoryCardStatus.newCard)
        .toList()
      ..sort((a, b) {
        final order = a.sortOrder.compareTo(b.sortOrder);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    final reviewCards = due
        .where((card) => card.status != MemoryCardStatus.newCard)
        .toList()
      ..sort((a, b) {
        final aDue = a.dueAt ?? a.updatedAt;
        final bDue = b.dueAt ?? b.updatedAt;
        final order = aDue.compareTo(bDue);
        return order != 0 ? order : a.id.compareTo(b.id);
      });

    final availableNew = (deck.newPerDayLimit -
            newStudiedToday(deckId, now: effectiveNow))
        .clamp(0, deck.newPerDayLimit)
        .toInt();
    final selectedNew = newCards.take(availableNew);
    final selectedReviews = reviewCards.take(deck.reviewPerDayLimit);
    return List.unmodifiable([...selectedNew, ...selectedReviews]);
  }

  int dueCount(String deckId, {DateTime? now}) {
    final deck = deckById(deckId);
    if (deck == null || !deck.enabled) return 0;
    final effectiveNow = now ?? DateTime.now();
    final newLimit = (deck.newPerDayLimit -
            newStudiedToday(deckId, now: effectiveNow))
        .clamp(0, deck.newPerDayLimit)
        .toInt();
    final due = cardsForDeck(deckId).where((card) => card.isDueAt(effectiveNow));
    final newCount = due
        .where((card) => card.status == MemoryCardStatus.newCard)
        .length;
    final reviewCount = due.length - newCount;
    final reviewLimit = reviewCount > deck.reviewPerDayLimit
        ? deck.reviewPerDayLimit
        : reviewCount;
    return (newCount > newLimit ? newLimit : newCount) + reviewLimit;
  }

  Future<void> review(
    MemoryCard card,
    MemoryCardRating rating, {
    DateTime? now,
  }) async {
    final index = _cards.indexWhere((item) => item.id == card.id);
    if (index < 0) return;
    final current = _cards[index];
    if (!current.enabled) return;
    final effectiveNow = now ?? DateTime.now();
    final schedule = MemoryCardScheduler.schedule(
      status: current.status,
      now: effectiveNow,
      rating: rating,
      intervalDays: current.intervalDays,
      easeFactor: current.easeFactor,
      repetitions: current.repetitions,
      lapses: current.lapses,
    );
    final updated = current.copyWith(
      status: schedule.status,
      dueAt: schedule.dueAt,
      intervalDays: schedule.intervalDays,
      easeFactor: schedule.easeFactor,
      repetitions: schedule.repetitions,
      lapses: schedule.lapses,
      reviewCount: current.reviewCount + 1,
      lastReviewedAt: effectiveNow,
      updatedAt: effectiveNow,
    );
    final log = MemoryCardReviewLog(
      id: _uuid.v4(),
      cardId: current.id,
      deckId: current.deckId,
      reviewedAt: effectiveNow,
      rating: rating,
      statusBefore: current.status,
      statusAfter: updated.status,
      intervalDaysBefore: current.intervalDays,
      intervalDaysAfter: updated.intervalDays,
      easeBefore: current.easeFactor,
      easeAfter: updated.easeFactor,
    );
    _cards[index] = updated;
    _reviewLogs.add(log);
    notifyListeners();
    await _queueSave(
      () => _repository.saveChanges(
        upsertCards: [updated],
        upsertReviewLogs: [log],
      ),
    );
  }

  // ─── 内部 ───

  MemoryCardLoadResult _snapshot() => MemoryCardLoadResult(
    decks: List.of(_decks),
    cards: List.of(_cards),
    reviewLogs: List.of(_reviewLogs),
  );

  bool _ensureDefaultDeckInMemory() {
    if (deckById(builtInDefaultDeckId) != null) return false;
    final now = DateTime.now();
    _decks.add(
      MemoryCardDeck(
        id: builtInDefaultDeckId,
        name: builtInDefaultDeckName,
        description: 'AI 生成或手动创建的记忆卡片默认存放牌组',
        newPerDayLimit: 20,
        reviewPerDayLimit: 200,
        enabled: true,
        sortOrder: _decks.length,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return true;
  }

  Future<void> _queueSave(Future<void> Function() save) {
    return enqueueSave(save);
  }
}

T? _first<T>(Iterable<T> values, bool Function(T) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}
