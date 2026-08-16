import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/memory_card.dart';
import '../../models/memory_card_deck.dart';
import '../../models/memory_card_review_log.dart';
import '../../providers/memory_card_provider.dart';
import '../../services/memory_card_scheduler.dart';
import '../../widgets/latex_renderer.dart';

/// 全屏复习页。
///
/// 展示到期卡片，用户自评后调用 [MemoryCardProvider.review] 调度下一次复习。
class MemoryCardStudyPage extends StatefulWidget {
  const MemoryCardStudyPage({
    super.key,
    required this.deck,
    required this.cards,
  });

  final MemoryCardDeck deck;
  final List<MemoryCard> cards;

  @override
  State<MemoryCardStudyPage> createState() => _MemoryCardStudyPageState();
}

class _MemoryCardStudyPageState extends State<MemoryCardStudyPage> {
  late final List<MemoryCard> _queue = List.of(widget.cards);
  int _index = 0;
  bool _showBack = false;
  int _reviewedCount = 0;

  @override
  Widget build(BuildContext context) {
    final card = _index < _queue.length ? _queue[_index] : null;
    return Scaffold(
      appBar: AppBar(
        title: Text('复习 · ${widget.deck.name}'),
        actions: [
          if (card != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text('${_index + 1} / ${_queue.length}'),
              ),
            ),
        ],
      ),
      body: card == null
          ? _summary(context)
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Card(
                            elevation: 0,
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: _showBack
                                  ? MarkdownWithLatex(content: card.back)
                                  : MarkdownWithLatex(content: card.front),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!_showBack)
                        FilledButton.icon(
                          onPressed: () => setState(() => _showBack = true),
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('显示答案'),
                        )
                      else
                        _ratingButtons(context, card),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _ratingButtons(BuildContext context, MemoryCard card) {
    final provider = context.read<MemoryCardProvider>();
    final now = DateTime.now();
    final again = MemoryCardScheduler.schedule(
      status: card.status,
      now: now,
      rating: MemoryCardRating.again,
      intervalDays: card.intervalDays,
      easeFactor: card.easeFactor,
      repetitions: card.repetitions,
      lapses: card.lapses,
    );
    final good = MemoryCardScheduler.schedule(
      status: card.status,
      now: now,
      rating: MemoryCardRating.good,
      intervalDays: card.intervalDays,
      easeFactor: card.easeFactor,
      repetitions: card.repetitions,
      lapses: card.lapses,
    );
    final easy = MemoryCardScheduler.schedule(
      status: card.status,
      now: now,
      rating: MemoryCardRating.easy,
      intervalDays: card.intervalDays,
      easeFactor: card.easeFactor,
      repetitions: card.repetitions,
      lapses: card.lapses,
    );

    Future<void> rate(MemoryCardRating rating) async {
      await provider.review(card, rating, now: now);
      if (!mounted) return;
      setState(() {
        _reviewedCount++;
        _index++;
        _showBack = false;
      });
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ratingButton(
          label: '忘记',
          preview: _previewText(again.dueAt),
          color: Theme.of(context).colorScheme.error,
          onPressed: () => rate(MemoryCardRating.again),
        ),
        _ratingButton(
          label: '良好',
          preview: _previewText(good.dueAt),
          color: Theme.of(context).colorScheme.primary,
          onPressed: () => rate(MemoryCardRating.good),
        ),
        _ratingButton(
          label: '简单',
          preview: _previewText(easy.dueAt),
          color: Theme.of(context).colorScheme.tertiary,
          onPressed: () => rate(MemoryCardRating.easy),
        ),
      ],
    );
  }

  Widget _ratingButton({
    required String label,
    required String preview,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.85),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: onPressed,
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(preview, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  String _previewText(DateTime dueAt) {
    final diff = dueAt.difference(DateTime.now());
    if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 59)} 分钟后';
    if (diff.inHours < 24) return '${diff.inHours} 小时后';
    return '${diff.inDays} 天后';
  }

  Widget _summary(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.celebration_outlined, size: 64),
          const SizedBox(height: 16),
          Text(
            '本轮完成',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text('已复习 $_reviewedCount 张卡片'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }
}
