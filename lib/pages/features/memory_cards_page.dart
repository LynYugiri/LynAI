import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/memory_card.dart';
import '../../models/memory_card_deck.dart';
import '../../providers/memory_card_provider.dart';
import 'memory_card_generation_dialog.dart';
import 'memory_card_study_page.dart';

enum _CardFilter { all, newCards, due }

/// 记忆卡片页。
///
/// 左侧为牌组列表，右侧为当前牌组的卡片列表；支持手动新增/编辑/删除，
/// 从知识库生成卡片以及开始一轮复习。
class MemoryCardsPage extends StatefulWidget {
  const MemoryCardsPage({super.key});

  @override
  State<MemoryCardsPage> createState() => _MemoryCardsPageState();
}

class _MemoryCardsPageState extends State<MemoryCardsPage> {
  String? _selectedDeckId;
  _CardFilter _filter = _CardFilter.all;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MemoryCardProvider>();
    final decks = provider.decks;
    final deck = _resolveDeck(provider, decks);
    final cards = _visibleCards(provider, deck);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            children: [
              SizedBox(
                width: 270,
                child: _deckPane(provider, decks, deck),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _cardPane(provider, deck, cards),
              ),
            ],
          );
        }
        return Column(
          children: [
            if (decks.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: DropdownButtonFormField<String>(
                  initialValue: deck?.id,
                  decoration: const InputDecoration(
                    labelText: '牌组',
                    isDense: true,
                  ),
                  items: [
                    for (final item in decks)
                      DropdownMenuItem(
                        value: item.id,
                        child: Text(item.name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedDeckId = value);
                    }
                  },
                ),
              ),
            Expanded(
              child: _cardPane(provider, deck, cards),
            ),
          ],
        );
      },
    );
  }

  MemoryCardDeck? _resolveDeck(
    MemoryCardProvider provider,
    List<MemoryCardDeck> decks,
  ) {
    final selected = _selectedDeckId;
    if (selected != null) {
      final value = provider.deckById(selected);
      if (value != null) return value;
    }
    return decks.isEmpty ? null : decks.first;
  }

  List<MemoryCard> _visibleCards(
    MemoryCardProvider provider,
    MemoryCardDeck? deck,
  ) {
    if (deck == null) return const [];
    final query = _searchController.text.trim().toLowerCase();
    final now = DateTime.now();
    return provider.cardsForDeck(deck.id).where((card) {
      if (query.isNotEmpty &&
          !card.front.toLowerCase().contains(query) &&
          !card.back.toLowerCase().contains(query)) {
        return false;
      }
      return switch (_filter) {
        _CardFilter.all => true,
        _CardFilter.newCards => card.status == MemoryCardStatus.newCard,
        _CardFilter.due => card.isDueAt(now),
      };
    }).toList();
  }

  Widget _deckPane(
    MemoryCardProvider provider,
    List<MemoryCardDeck> decks,
    MemoryCardDeck? selected,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '牌组',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: '新建牌组',
                icon: const Icon(Icons.add),
                onPressed: () => _createDeck(provider),
              ),
            ],
          ),
        ),
        Expanded(
          child: decks.isEmpty
              ? const Center(child: Text('暂无牌组'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  itemCount: decks.length,
                  itemBuilder: (context, index) {
                    final deck = decks[index];
                    final selectedDeck = deck.id == selected?.id;
                    final due = provider.dueCount(deck.id);
                    return ListTile(
                      selected: selectedDeck,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      title: Text(
                        deck.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('今日到期 $due 张'),
                      trailing: PopupMenuButton<String>(
                        tooltip: '牌组操作',
                        onSelected: (value) {
                          if (value == 'rename') _renameDeck(provider, deck);
                          if (value == 'delete') _deleteDeck(provider, deck);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'rename',
                            child: Text('重命名'),
                          ),
                          PopupMenuItem(value: 'delete', child: Text('删除')),
                        ],
                      ),
                      onTap: () => setState(() {
                        _selectedDeckId = deck.id;
                      }),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _cardPane(
    MemoryCardProvider provider,
    MemoryCardDeck? deck,
    List<MemoryCard> cards,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '搜索正面或反面',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                tooltip: '新建卡片',
                onPressed: deck == null ? null : () => _addCard(provider, deck),
                icon: const Icon(Icons.add),
              ),
              const SizedBox(width: 8),
              SegmentedButton<_CardFilter>(
                segments: const [
                  ButtonSegment(
                    value: _CardFilter.all,
                    label: Text('全部'),
                  ),
                  ButtonSegment(
                    value: _CardFilter.newCards,
                    label: Text('新卡'),
                  ),
                  ButtonSegment(
                    value: _CardFilter.due,
                    label: Text('到期'),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (value) =>
                    setState(() => _filter = value.first),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: deck == null
                    ? null
                    : () => _openGenerator(provider, deck),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('AI 生成卡片'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: deck == null
                    ? null
                    : () => _startStudy(provider, deck),
                icon: const Icon(Icons.school_outlined),
                label: const Text('开始复习'),
              ),
              const Spacer(),
              Text(
                deck == null ? '' : '共 ${cards.length} 张',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Expanded(
          child: deck == null
              ? const Center(child: Text('请先创建一个牌组'))
              : cards.isEmpty
              ? const Center(child: Text('没有符合条件的卡片'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                  itemCount: cards.length,
                  itemBuilder: (context, index) {
                    final card = cards[index];
                    return _cardTile(provider, card);
                  },
                ),
        ),
      ],
    );
  }

  Widget _cardTile(MemoryCardProvider provider, MemoryCard card) {
    final scheme = Theme.of(context).colorScheme;
    final due = card.isDueAt(DateTime.now());
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          radius: 4,
          backgroundColor: card.status == MemoryCardStatus.newCard
              ? scheme.primary
              : due
              ? scheme.tertiary
              : scheme.outlineVariant,
        ),
        title: Text(
          card.front,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          card.back,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          tooltip: '卡片操作',
          onSelected: (value) {
            if (value == 'edit') _editCard(provider, card);
            if (value == 'delete') provider.deleteCard(card.id);
            if (value == 'toggle') provider.setCardEnabled(card.id, !card.enabled);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('编辑')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(card.enabled ? '停用' : '启用'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
        onTap: () => _editCard(provider, card),
      ),
    );
  }

  // ─── 操作 ───

  Future<void> _createDeck(MemoryCardProvider provider) async {
    final name = await _promptText(title: '新建牌组', label: '牌组名');
    if (name == null || name.trim().isEmpty) return;
    final id = await provider.addDeck(name: name.trim());
    if (!mounted) return;
    setState(() {
      _selectedDeckId = id;
    });
  }

  Future<void> _renameDeck(
    MemoryCardProvider provider,
    MemoryCardDeck deck,
  ) async {
    final name = await _promptText(title: '重命名牌组', label: '牌组名', initial: deck.name);
    if (name == null || name.trim().isEmpty) return;
    await provider.updateDeck(deck.copyWith(name: name.trim()));
  }

  Future<void> _deleteDeck(
    MemoryCardProvider provider,
    MemoryCardDeck deck,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除牌组'),
        content: Text('确定删除「${deck.name}」及其所有卡片吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await provider.deleteDeck(deck.id);
      if (!mounted) return;
      setState(() {
        if (_selectedDeckId == deck.id) _selectedDeckId = null;
      });
    } on ArgumentError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _editCard(MemoryCardProvider provider, MemoryCard card) async {
    final result = await showDialog<({String front, String back, String hint})>(
      context: context,
      builder: (ctx) => _CardEditorDialog(
        title: '编辑卡片',
        front: card.front,
        back: card.back,
        hint: card.hint ?? '',
      ),
    );
    if (result == null) return;
    if (result.front.trim().isEmpty || result.back.trim().isEmpty) return;
    await provider.updateCard(
      card.copyWith(
        front: result.front.trim(),
        back: result.back.trim(),
        hint: result.hint.trim().isEmpty ? null : result.hint.trim(),
      ),
    );
  }

  Future<void> _addCard(MemoryCardProvider provider, MemoryCardDeck deck) async {
    final result = await showDialog<({String front, String back, String hint})>(
      context: context,
      builder: (ctx) => const _CardEditorDialog(title: '新建卡片'),
    );
    if (result == null) return;
    if (result.front.trim().isEmpty || result.back.trim().isEmpty) return;
    await provider.addCard(
      deckId: deck.id,
      front: result.front.trim(),
      back: result.back.trim(),
      hint: result.hint.trim().isEmpty ? null : result.hint.trim(),
    );
  }

  Future<void> _openGenerator(
    MemoryCardProvider provider,
    MemoryCardDeck deck,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => MemoryCardGenerationDialog(
        targetDeckId: deck.id,
      ),
    );
  }

  Future<void> _startStudy(
    MemoryCardProvider provider,
    MemoryCardDeck deck,
  ) async {
    final due = provider.dueCards(deck.id);
    if (due.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有到期卡片')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemoryCardStudyPage(deck: deck, cards: due),
      ),
    );
  }

  Future<String?> _promptText({
    required String title,
    required String label,
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}

class _CardEditorDialog extends StatefulWidget {
  const _CardEditorDialog({
    required this.title,
    this.front = '',
    this.back = '',
    this.hint = '',
  });

  final String title;
  final String front;
  final String back;
  final String hint;

  @override
  State<_CardEditorDialog> createState() => _CardEditorDialogState();
}

class _CardEditorDialogState extends State<_CardEditorDialog> {
  late final TextEditingController _front = TextEditingController(
    text: widget.front,
  );
  late final TextEditingController _back = TextEditingController(
    text: widget.back,
  );
  late final TextEditingController _hint = TextEditingController(
    text: widget.hint,
  );

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    _hint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _front,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '正面（问题/提示）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _back,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '反面（答案）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _hint,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '提示（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            (front: _front.text, back: _back.text, hint: _hint.text),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
