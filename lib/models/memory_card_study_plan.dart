import 'memory_card.dart';

/// 一个牌组按队列拆分的到期卡片数量。
final class MemoryCardCounts {
  const MemoryCardCounts({
    required this.newCards,
    required this.learningCards,
    required this.reviewCards,
  });

  final int newCards;
  final int learningCards;
  final int reviewCards;

  int get total => newCards + learningCards + reviewCards;
}

/// 一个牌组本次学习会话的卡片计划。
///
/// 学习/重学卡最优先，其次是到期复习卡，最后按每日限额补充新卡。
final class MemoryCardStudyPlan {
  const MemoryCardStudyPlan({
    required this.newCards,
    required this.learningCards,
    required this.reviewCards,
    required this.counts,
  });

  final List<MemoryCard> newCards;
  final List<MemoryCard> learningCards;
  final List<MemoryCard> reviewCards;
  final MemoryCardCounts counts;

  /// 实际出卡顺序：学习/重学 → 复习 → 新卡。
  List<MemoryCard> get cards =>
      List.unmodifiable([...learningCards, ...reviewCards, ...newCards]);
}
