import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/memory_card.dart';
import '../../models/memory_card_deck.dart';
import '../../models/memory_card_review_log.dart';
import '../../providers/memory_card_provider.dart';
import '../../services/memory_card_scheduler.dart';
import '../../widgets/latex_renderer.dart';

/// 全屏复习页。
///
/// 以牌组到期卡为会话队列；失败的学习/重学卡会在到期后重新插入队列，
/// 支持四档评分、撤销、快捷键和完成统计。
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

class _QueueItem {
  const _QueueItem({required this.card, required this.readyAt});

  final MemoryCard card;
  final DateTime readyAt;
}

class _MemoryCardStudyPageState extends State<MemoryCardStudyPage> {
  late final List<_QueueItem> _mainQueue = [
    for (final card in widget.cards)
      _QueueItem(card: card, readyAt: card.dueAt ?? DateTime.now()),
  ];
  final List<_QueueItem> _reinsertions = [];
  int _mainIndex = 0;
  _QueueItem? _current;
  DateTime? _waitingUntil;
  Timer? _waitTimer;

  bool _showBack = false;
  int _reviewedCount = 0;
  final Map<MemoryCardRating, int> _ratingCounts = {
    MemoryCardRating.again: 0,
    MemoryCardRating.hard: 0,
    MemoryCardRating.good: 0,
    MemoryCardRating.easy: 0,
  };
  MemoryCard? _lastReviewedCard;
  MemoryCardRating? _lastRating;

  @override
  void initState() {
    super.initState();
    _advance();
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    super.dispose();
  }

  void _advance() {
    _waitTimer?.cancel();
    final now = DateTime.now();
    _QueueItem? next;
    while (_reinsertions.isNotEmpty &&
        !_reinsertions.first.readyAt.isAfter(now)) {
      next = _reinsertions.removeAt(0);
      break;
    }
    next ??= _mainIndex < _mainQueue.length ? _mainQueue[_mainIndex++] : null;

    if (next != null) {
      setState(() {
        _current = next;
        _waitingUntil = null;
        _showBack = false;
      });
      return;
    }
    if (_reinsertions.isNotEmpty) {
      final waitUntil = _reinsertions.first.readyAt;
      final delay = waitUntil.difference(DateTime.now());
      setState(() {
        _current = null;
        _waitingUntil = waitUntil;
      });
      _waitTimer = Timer(delay.isNegative ? Duration.zero : delay, _advance);
      return;
    }
    setState(() {
      _current = null;
      _waitingUntil = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MemoryCardProvider>();
    final counts = provider.counts(widget.deck.id);
    final card = _current?.card;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1): () =>
            _rate(provider, MemoryCardRating.again),
        const SingleActivator(LogicalKeyboardKey.digit2): () =>
            _rate(provider, MemoryCardRating.hard),
        const SingleActivator(LogicalKeyboardKey.digit3): () =>
            _rate(provider, MemoryCardRating.good),
        const SingleActivator(LogicalKeyboardKey.digit4): () =>
            _rate(provider, MemoryCardRating.easy),
        const SingleActivator(LogicalKeyboardKey.space): () => _space(provider),
        const SingleActivator(LogicalKeyboardKey.keyU): () => _undo(provider),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text('复习 · ${widget.deck.name}'),
            actions: [
              Center(
                child: Text(
                  '新 ${counts.newCards} · 学 ${counts.learningCards}'
                  ' · 复 ${counts.reviewCards}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: '撤销 (U)',
                onPressed: _lastReviewedCard == null
                    ? null
                    : () => _undo(provider),
                icon: const Icon(Icons.undo),
              ),
              if (card != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(child: Text('已复习 $_reviewedCount')),
                ),
            ],
          ),
          body: card == null
              ? _waitingUntil != null
                    ? _waiting(context)
                    : _summary(context)
              : _cardView(context, provider, card),
        ),
      ),
    );
  }

  Widget _cardView(
    BuildContext context,
    MemoryCardProvider provider,
    MemoryCard card,
  ) {
    return Center(
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
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _showBack
                                ? MarkdownWithLatex(
                                    key: const ValueKey('back'),
                                    content: card.back,
                                  )
                                : MarkdownWithLatex(
                                    key: const ValueKey('front'),
                                    content: card.front,
                                  ),
                          ),
                          if (_showBack && card.hint != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                '提示：${card.hint}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
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
                _ratingButtons(context, provider, card),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ratingButtons(
    BuildContext context,
    MemoryCardProvider provider,
    MemoryCard card,
  ) {
    final now = DateTime.now();
    final showHard = card.status == MemoryCardStatus.review;
    final ratings = showHard
        ? const [
            MemoryCardRating.again,
            MemoryCardRating.hard,
            MemoryCardRating.good,
            MemoryCardRating.easy,
          ]
        : const [
            MemoryCardRating.again,
            MemoryCardRating.good,
            MemoryCardRating.easy,
          ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final rating in ratings)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _ratingButton(
                label: _ratingLabel(rating),
                preview: _previewText(_schedule(card, rating, now).dueAt, now),
                color: _ratingColor(context, rating),
                onPressed: () => _rate(provider, rating),
              ),
            ),
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
    return FilledButton(
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
    );
  }

  Widget _waiting(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.hourglass_bottom, size: 64),
          const SizedBox(height: 16),
          const Text('学习中的卡片尚未到期'),
          const SizedBox(height: 8),
          Text(
            '下一张将在 ${_previewText(_waitingUntil!, DateTime.now())} 后出现',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final total = _reviewedCount;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.celebration_outlined, size: 64),
          const SizedBox(height: 16),
          Text('本轮完成', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('已复习 $total 张卡片'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              for (final rating in MemoryCardRating.values)
                if (_ratingCounts[rating]! > 0)
                  Chip(
                    label: Text(
                      '${_ratingLabel(rating)} ${_ratingCounts[rating]}',
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }

  MemoryCardSchedule _schedule(
    MemoryCard card,
    MemoryCardRating rating,
    DateTime now,
  ) {
    return MemoryCardScheduler.schedule(
      status: card.status,
      now: now,
      rating: rating,
      intervalDays: card.intervalDays,
      easeFactor: card.easeFactor,
      repetitions: card.repetitions,
      lapses: card.lapses,
      remainingSteps: card.remainingSteps,
      fuzzSeed: card.id.hashCode + card.reviewCount,
    );
  }

  Future<void> _rate(
    MemoryCardProvider provider,
    MemoryCardRating rating,
  ) async {
    final card = _current?.card;
    if (card == null || !_showBack) return;
    if (rating == MemoryCardRating.hard &&
        card.status != MemoryCardStatus.review) {
      return;
    }
    final outcome = await provider.review(card, rating);
    if (!mounted) return;
    if (outcome == null) {
      _advance();
      return;
    }
    setState(() {
      _reviewedCount++;
      _ratingCounts[rating] = _ratingCounts[rating]! + 1;
      _lastReviewedCard = card;
      _lastRating = rating;
    });
    if (outcome.shouldReinsertInSession) {
      _reinsertions.add(
        _QueueItem(card: outcome.card, readyAt: outcome.card.dueAt!),
      );
      _reinsertions.sort((a, b) => a.readyAt.compareTo(b.readyAt));
    }
    _advance();
  }

  Future<void> _undo(MemoryCardProvider provider) async {
    final card = _lastReviewedCard;
    final rating = _lastRating;
    if (card == null || rating == null) return;
    final restored = await provider.undoLastReview(widget.deck.id);
    if (!mounted || !restored) return;
    setState(() {
      _reinsertions.removeWhere((item) => item.card.id == card.id);
      _current = _QueueItem(card: card, readyAt: DateTime.now());
      _showBack = false;
      _waitingUntil = null;
      if (_reviewedCount > 0) _reviewedCount--;
      if (_ratingCounts[rating]! > 0) {
        _ratingCounts[rating] = _ratingCounts[rating]! - 1;
      }
      _lastReviewedCard = null;
      _lastRating = null;
    });
    _waitTimer?.cancel();
  }

  void _space(MemoryCardProvider provider) {
    final card = _current?.card;
    if (card == null) return;
    if (!_showBack) {
      setState(() => _showBack = true);
    } else {
      _rate(provider, MemoryCardRating.good);
    }
  }

  String _ratingLabel(MemoryCardRating rating) => switch (rating) {
    MemoryCardRating.again => '忘记',
    MemoryCardRating.hard => '困难',
    MemoryCardRating.good => '良好',
    MemoryCardRating.easy => '简单',
  };

  Color _ratingColor(BuildContext context, MemoryCardRating rating) =>
      switch (rating) {
        MemoryCardRating.again => Theme.of(context).colorScheme.error,
        MemoryCardRating.hard => Colors.orange.shade700,
        MemoryCardRating.good => Theme.of(context).colorScheme.primary,
        MemoryCardRating.easy => Theme.of(context).colorScheme.tertiary,
      };

  String _previewText(DateTime dueAt, DateTime now) {
    final diff = dueAt.difference(now);
    if (diff.isNegative || diff.inSeconds < 60) return '不足 1 分钟';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟后';
    if (diff.inHours < 24) return '${diff.inHours} 小时后';
    return '${diff.inDays} 天后';
  }
}
