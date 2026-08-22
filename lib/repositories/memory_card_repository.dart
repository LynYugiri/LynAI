import 'package:flutter/foundation.dart';

import '../models/memory_card.dart';
import '../models/memory_card_deck.dart';
import '../models/memory_card_review_log.dart';
import '../services/storage_v2_service.dart';

/// 从持久化层一次性读取的记忆卡片数据快照。
final class MemoryCardLoadResult {
  const MemoryCardLoadResult({
    required this.decks,
    required this.cards,
    required this.reviewLogs,
  });

  final List<MemoryCardDeck> decks;
  final List<MemoryCard> cards;
  final List<MemoryCardReviewLog> reviewLogs;
}

/// 负责记忆卡片数据与 storage_v2 行存储之间的转换。
class MemoryCardRepository {
  MemoryCardRepository({StorageV2Service? storageV2})
    : _storageV2 = storageV2 ?? StorageV2Service();

  static const fileName = 'memory_cards.json';
  final StorageV2Service _storageV2;

  /// 读取记忆卡片数据。
  ///
  /// 缺失或为 null 的顶层集合按空列表处理；存在但不是列表时抛出
  /// [FormatException]。列表内类型错误或无法解析的记录会被跳过。
  /// 加载时会过滤重复 ID、悬空卡片与悬空复习记录，避免上层拿到
  /// 引用不完整的快照。
  Future<MemoryCardLoadResult> load() async {
    final data = await _storageV2.loadDataFile(fileName);
    final decks = _uniqueById(
      _decode(data['decks'], MemoryCardDeck.fromJson, '记忆卡片牌组'),
      (item) => item.id,
      '记忆卡片牌组',
    );
    final deckIds = {for (final deck in decks) deck.id};
    final cards = _uniqueById(
      _decode(data['cards'], MemoryCard.fromJson, '记忆卡片').where((card) {
        if (deckIds.contains(card.deckId)) return true;
        debugPrint('跳过悬空记忆卡片 ${card.id}: 牌组 ${card.deckId} 不存在');
        return false;
      }),
      (card) => card.id,
      '记忆卡片',
    );
    final cardIds = {for (final card in cards) card.id};
    final reviewLogs = _uniqueById(
      _decode(
        data['reviewLogs'],
        MemoryCardReviewLog.fromJson,
        '记忆卡片复习记录',
      ).where((log) {
        if (deckIds.contains(log.deckId) && cardIds.contains(log.cardId)) {
          return true;
        }
        debugPrint('跳过悬空记忆卡片复习记录 ${log.id}');
        return false;
      }),
      (log) => log.id,
      '记忆卡片复习记录',
    );
    return MemoryCardLoadResult(
      decks: decks,
      cards: cards,
      reviewLogs: reviewLogs,
    );
  }

  /// 使用完整快照替换当前记忆卡片数据。
  Future<void> replace(MemoryCardLoadResult value) =>
      _storageV2.writeDataFile(fileName, {
        'decks': value.decks.map((item) => item.toJson()).toList(),
        'cards': value.cards.map((item) => item.toJson()).toList(),
        'reviewLogs': value.reviewLogs.map((item) => item.toJson()).toList(),
      });

  /// 原子应用记忆卡片行的增量新增、更新与删除。
  Future<void> saveChanges({
    Iterable<MemoryCardDeck> upsertDecks = const [],
    Iterable<String> deleteDeckIds = const [],
    Iterable<MemoryCard> upsertCards = const [],
    Iterable<String> deleteCardIds = const [],
    Iterable<MemoryCardReviewLog> upsertReviewLogs = const [],
    Iterable<String> deleteReviewLogIds = const [],
  }) async {
    final operations = [
      for (final id in deleteReviewLogIds)
        (
          table: 'memory_card_review_logs',
          op: 'delete',
          data: {'id': id},
          change: null,
        ),
      for (final id in deleteCardIds)
        (table: 'memory_cards', op: 'delete', data: {'id': id}, change: null),
      for (final id in deleteDeckIds)
        (
          table: 'memory_card_decks',
          op: 'delete',
          data: {'id': id},
          change: null,
        ),
      for (final item in upsertDecks)
        (
          table: 'memory_card_decks',
          op: 'upsert',
          data: item.toJson(),
          change: null,
        ),
      for (final item in upsertCards)
        (
          table: 'memory_cards',
          op: 'upsert',
          data: item.toJson(),
          change: null,
        ),
      for (final item in upsertReviewLogs)
        (
          table: 'memory_card_review_logs',
          op: 'upsert',
          data: item.toJson(),
          change: null,
        ),
    ];
    await _storageV2.applyLocalRowChanges(operations);
  }
}

List<T> _decode<T>(
  Object? raw,
  T Function(Map<String, dynamic>) parser,
  String label,
) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw FormatException('$label集合必须是列表');
  }
  final values = <T>[];
  for (final item in raw) {
    try {
      if (item is Map) values.add(parser(Map<String, dynamic>.from(item)));
    } catch (error) {
      debugPrint('跳过损坏的$label: $error');
    }
  }
  return values;
}

List<T> _uniqueById<T>(
  Iterable<T> values,
  String Function(T) idOf,
  String label,
) {
  final seen = <String>{};
  final result = <T>[];
  for (final value in values) {
    final id = idOf(value);
    if (id.isEmpty || !seen.add(id)) {
      debugPrint('跳过重复或空 ID 的$label: $id');
      continue;
    }
    result.add(value);
  }
  return result;
}
