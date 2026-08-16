import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/knowledge_base.dart';
import '../../models/knowledge_category.dart';
import '../../models/knowledge_entry.dart';
import '../../models/memory_card.dart';
import '../../models/memory_card_deck.dart';
import '../../providers/knowledge_provider.dart';
import '../../providers/memory_card_provider.dart';
import '../../providers/model_config_provider.dart';
import '../../providers/plugin_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/api_service.dart';
import '../../services/backend_client.dart';
import '../../services/memory_card_generation_service.dart';

/// 从知识库内容生成记忆卡片的对话框。
///
/// 第一步选择知识库与条目（支持全选/反选/勾选），第二步生成并预览，
/// 确认后写入 [MemoryCardProvider]。
class MemoryCardGenerationDialog extends StatefulWidget {
  const MemoryCardGenerationDialog({
    super.key,
    required this.targetDeckId,
  });

  final String targetDeckId;

  @override
  State<MemoryCardGenerationDialog> createState() =>
      _MemoryCardGenerationDialogState();
}

class _MemoryCardGenerationDialogState
    extends State<MemoryCardGenerationDialog> {
  final _uuid = const Uuid();
  String? _selectedBaseId;
  String? _categoryId;
  String _search = '';
  final Set<String> _selectedEntryIds = {};
  String? _selectedDeckId;
  final _newDeckName = TextEditingController();
  int _cardCount = MemoryCardGenerationService.defaultTargetCount;
  final _extraPrompt = TextEditingController();
  bool _generating = false;
  String? _error;
  List<GeneratedMemoryCard> _previewCards = const [];
  final Set<int> _previewSelected = {};

  @override
  void dispose() {
    _newDeckName.dispose();
    _extraPrompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MemoryCardProvider>();
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('AI 生成记忆卡片')),
          if (_previewCards.isNotEmpty)
            TextButton(
              onPressed: _generating
                  ? null
                  : () => setState(() {
                      _previewCards = const [];
                      _previewSelected.clear();
                      _error = null;
                    }),
              child: const Text('返回选择'),
            ),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: 620,
        child: _previewCards.isEmpty ? _selectView(context) : _previewView(),
      ),
      actions: [
        TextButton(
          onPressed: _generating ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        if (_previewCards.isEmpty)
          FilledButton.icon(
            onPressed: _generating ? null : _generate,
            icon: const Icon(Icons.auto_awesome),
            label: Text(_generating ? '生成中…' : '开始生成'),
          )
        else
          FilledButton.icon(
            onPressed: _generating ? null : () => _save(provider),
            icon: const Icon(Icons.save_outlined),
            label: Text('保存 ${_previewSelected.length} 张'),
          ),
      ],
    );
  }

  Widget _selectView(BuildContext context) {
    final knowledge = context.watch<KnowledgeProvider>();
    final bases = knowledge.knowledgeBases;
    final base = _resolveBase(knowledge, bases);
    final categories = base == null
        ? const <KnowledgeCategory>[]
        : knowledge.categoriesForBase(base.id);
    final category = _resolveCategory(knowledge, categories);
    final entries = _visibleEntries(knowledge, base);
    final filtered = entries.where((entry) {
      final query = _search.trim().toLowerCase();
      if (query.isEmpty) return true;
      return entry.title.toLowerCase().contains(query) ||
          entry.content.toLowerCase().contains(query);
    }).toList();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: base?.id,
                decoration: const InputDecoration(
                  labelText: '知识库',
                  isDense: true,
                ),
                items: [
                  for (final item in bases)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text(item.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _selectedBaseId = value;
                  _categoryId = null;
                  _selectedEntryIds.clear();
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: category?.id,
                decoration: const InputDecoration(
                  labelText: '类别（可选）',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('全部类别'),
                  ),
                  for (final item in categories)
                    DropdownMenuItem<String?>(
                      value: item.id,
                      child: Text(item.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _categoryId = value;
                  _selectedEntryIds.clear();
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '搜索标题或正文',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _search = value),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                for (final entry in filtered) {
                  _selectedEntryIds.add(entry.id);
                }
              }),
              child: const Text('全选'),
            ),
            TextButton(
              onPressed: () => setState(() {
                for (final entry in filtered) {
                  if (!_selectedEntryIds.add(entry.id)) {
                    _selectedEntryIds.remove(entry.id);
                  }
                }
              }),
              child: const Text('反选'),
            ),
            TextButton(
              onPressed: () => setState(() => _selectedEntryIds.clear()),
              child: const Text('清除'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '已选 ${_selectedEntryIds.length} / ${entries.length} 条',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: base == null
              ? const Center(child: Text('暂无知识库'))
              : filtered.isEmpty
              ? const Center(child: Text('没有匹配的条目'))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final entry = filtered[index];
                    final selected = _selectedEntryIds.contains(entry.id);
                    return CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: selected,
                      title: Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        entry.content
                            .replaceAll(RegExp(r'\s+'), ' ')
                            .trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _selectedEntryIds.add(entry.id);
                        } else {
                          _selectedEntryIds.remove(entry.id);
                        }
                      }),
                    );
                  },
                ),
        ),
        const Divider(),
        _generationOptions(context),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _generationOptions(BuildContext context) {
    final memoryCards = context.watch<MemoryCardProvider>();
    final decks = memoryCards.decks;
    final targetDeck = memoryCards.deckById(widget.targetDeckId);
    final deck = _resolveTargetDeck(memoryCards, targetDeck);
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: deck?.id,
            decoration: const InputDecoration(
              labelText: '目标牌组',
              isDense: true,
            ),
            items: [
              for (final item in decks)
                DropdownMenuItem(
                  value: item.id,
                  child: Text(item.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) => setState(() => _selectedDeckId = value),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<int>(
            initialValue: _cardCount,
            decoration: const InputDecoration(
              labelText: '卡片数量',
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 10, child: Text('10 张')),
              DropdownMenuItem(value: 20, child: Text('20 张')),
              DropdownMenuItem(value: 30, child: Text('30 张')),
              DropdownMenuItem(value: 50, child: Text('50 张')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _cardCount = value);
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _extraPrompt,
            decoration: const InputDecoration(
              labelText: '补充要求（可选）',
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _previewView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Text('预览生成结果，可编辑后勾选保存'),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  if (_previewSelected.length == _previewCards.length) {
                    _previewSelected.clear();
                  } else {
                    _previewSelected
                      ..clear()
                      ..addAll(_previewCards.asMap().keys);
                  }
                }),
                child: Text(
                  _previewSelected.length == _previewCards.length
                      ? '取消全选'
                      : '全选',
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _previewCards.length,
            itemBuilder: (context, index) {
              final card = _previewCards[index];
              final selected = _previewSelected.contains(index);
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: selected,
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            _previewSelected.add(index);
                          } else {
                            _previewSelected.remove(index);
                          }
                        }),
                      ),
                      Expanded(
                        child: _GeneratedCardEditor(
                          key: ValueKey('generated-card-$index'),
                          front: card.front,
                          back: card.back,
                          onFrontChanged: (value) => _updatePreview(
                            index,
                            card.copyWithFront(value),
                          ),
                          onBackChanged: (value) => _updatePreview(
                            index,
                            card.copyWithBack(value),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _updatePreview(int index, GeneratedMemoryCard card) {
    final updated = List<GeneratedMemoryCard>.of(_previewCards);
    updated[index] = card;
    setState(() => _previewCards = updated);
  }

  // ─── 数据解析 ───

  KnowledgeBase? _resolveBase(
    KnowledgeProvider provider,
    List<KnowledgeBase> bases,
  ) {
    final selected = _selectedBaseId;
    if (selected != null) {
      final value = provider.knowledgeBaseById(selected);
      if (value != null) return value;
    }
    return bases.isEmpty ? null : bases.first;
  }

  KnowledgeCategory? _resolveCategory(
    KnowledgeProvider provider,
    List<KnowledgeCategory> categories,
  ) {
    final selected = _categoryId;
    if (selected == null) return null;
    return provider.categoryById(selected);
  }

  List<KnowledgeEntry> _visibleEntries(
    KnowledgeProvider provider,
    KnowledgeBase? base,
  ) {
    if (base == null) return const [];
    final entries = provider.entriesForBase(base.id);
    if (_categoryId == null) return entries;
    return entries
        .where((entry) => entry.categoryId == _categoryId)
        .toList();
  }

  MemoryCardDeck? _resolveTargetDeck(
    MemoryCardProvider provider,
    MemoryCardDeck? target,
  ) {
    final selected = _selectedDeckId;
    if (selected != null) {
      return provider.deckById(selected);
    }
    return target ?? (provider.decks.isEmpty ? null : provider.decks.first);
  }

  // ─── 生成与保存 ───

  Future<void> _generate() async {
    final knowledge = context.read<KnowledgeProvider>();
    final base = _resolveBase(knowledge, knowledge.knowledgeBases);
    if (base == null) {
      setState(() => _error = '请先选择知识库');
      return;
    }
    final entries = _visibleEntries(knowledge, base)
        .where((entry) => _selectedEntryIds.contains(entry.id))
        .toList();
    if (entries.isEmpty) {
      setState(() => _error = '请至少选择一条知识条目');
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final service = MemoryCardGenerationService(
        api: ApiService(backend: context.read<BackendClient>()),
        modelConfigs: context.read<ModelConfigProvider>(),
        settings: context.read<SettingsProvider>(),
        plugins: context.read<PluginProvider>(),
      );
      final cards = await service.generate(
        entries: entries,
        targetCount: _cardCount,
        extraPrompt: _extraPrompt.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _previewCards = cards;
        _previewSelected
          ..clear()
          ..addAll(cards.asMap().keys);
        _generating = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = '$error';
      });
    }
  }

  Future<void> _save(MemoryCardProvider provider) async {
    final knowledge = context.read<KnowledgeProvider>();
    final base = _resolveBase(knowledge, knowledge.knowledgeBases);
    final selectedDeck = _resolveTargetDeck(provider, provider.deckById(widget.targetDeckId));
    if (selectedDeck == null) {
      setState(() => _error = '请选择目标牌组');
      return;
    }
    final cards = <MemoryCard>[];
    final now = DateTime.now();
    for (final index in _previewSelected.toList()..sort()) {
      if (index < 0 || index >= _previewCards.length) continue;
      final preview = _previewCards[index];
      if (preview.front.trim().isEmpty || preview.back.trim().isEmpty) {
        continue;
      }
      cards.add(
        MemoryCard(
          id: _uuid.v4(),
          deckId: selectedDeck.id,
          front: preview.front.trim(),
          back: preview.back.trim(),
          hint: preview.hint,
          sourceKind: MemoryCardSourceKind.knowledge,
          sourceBaseId: _selectedBaseId ?? base?.id,
          status: MemoryCardStatus.newCard,
          dueAt: null,
          intervalDays: 0,
          easeFactor: 2.5,
          repetitions: 0,
          lapses: 0,
          reviewCount: 0,
          lastReviewedAt: null,
          enabled: true,
          sortOrder: provider.cardsForDeck(selectedDeck.id).length + cards.length,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    if (cards.isEmpty) {
      setState(() => _error = '请至少勾选一张有效卡片');
      return;
    }
    await provider.addCards(cards);
    if (!mounted) return;
    Navigator.pop(context);
  }
}

class _GeneratedCardEditor extends StatefulWidget {
  const _GeneratedCardEditor({
    super.key,
    required this.front,
    required this.back,
    required this.onFrontChanged,
    required this.onBackChanged,
  });

  final String front;
  final String back;
  final ValueChanged<String> onFrontChanged;
  final ValueChanged<String> onBackChanged;

  @override
  State<_GeneratedCardEditor> createState() => _GeneratedCardEditorState();
}

class _GeneratedCardEditorState extends State<_GeneratedCardEditor> {
  late final TextEditingController _front = TextEditingController(
    text: widget.front,
  );
  late final TextEditingController _back = TextEditingController(
    text: widget.back,
  );

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _front,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: '正面',
            isDense: true,
          ),
          onChanged: widget.onFrontChanged,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _back,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '反面',
            isDense: true,
          ),
          onChanged: widget.onBackChanged,
        ),
      ],
    );
  }
}

extension on GeneratedMemoryCard {
  GeneratedMemoryCard copyWithFront(String value) =>
      GeneratedMemoryCard(front: value, back: back, hint: hint);
  GeneratedMemoryCard copyWithBack(String value) =>
      GeneratedMemoryCard(front: front, back: value, hint: hint);
}
