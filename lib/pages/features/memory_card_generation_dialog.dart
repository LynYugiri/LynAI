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
///
/// 生成规则固定为：**每个已选条目生成 1 张卡片**，卡片通过
/// [GeneratedMemoryCard.sourceEntryId] 与来源条目一一对应。
class MemoryCardGenerationDialog extends StatefulWidget {
  const MemoryCardGenerationDialog({super.key, required this.targetDeckId});

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
  final _extraPrompt = TextEditingController();
  bool _generating = false;
  int _generationSerial = 0;
  int _batchDone = 0;
  int? _batchTotal;
  String? _error;
  List<GeneratedMemoryCard> _previewCards = const [];
  List<KnowledgeEntry> _generationEntries = const [];
  MemoryCardGenerationResult? _lastResult;
  final Set<int> _previewSelected = {};

  @override
  void dispose() {
    _extraPrompt.dispose();
    _generationSerial++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MemoryCardProvider>();
    final knowledge = context.watch<KnowledgeProvider>();
    final base = _resolveBase(knowledge, knowledge.knowledgeBases);
    final selectedCount = _visibleEntries(
      knowledge,
      base,
    ).where((entry) => _selectedEntryIds.contains(entry.id)).length;

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
                      _generationEntries = const [];
                      _lastResult = null;
                      _error = null;
                    }),
              child: const Text('返回选择'),
            ),
        ],
      ),
      content: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth < 520
              ? constraints.maxWidth
              : 760.0;
          final height = constraints.maxHeight < 560
              ? constraints.maxHeight
              : 620.0;
          return SizedBox(
            width: width,
            height: height,
            child: _previewCards.isEmpty
                ? _selectView(context)
                : _previewView(),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () {
            _generationSerial++;
            Navigator.pop(context);
          },
          child: const Text('取消'),
        ),
        if (_previewCards.isEmpty)
          FilledButton.icon(
            onPressed: _generating || selectedCount == 0 ? null : _generate,
            icon: const Icon(Icons.auto_awesome),
            label: Text(
              _generating
                  ? _batchTotal == null
                        ? '生成中…'
                        : '生成中 $_batchDone/$_batchTotal…'
                  : '开始生成',
            ),
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
                key: ValueKey('knowledge-base-${base?.id}'),
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
                key: ValueKey('knowledge-category-${base?.id}-${category?.id}'),
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
            '已选 ${_selectedEntryIds.length} / ${entries.length} 条'
            ' · 将生成 ${_selectedEntryIds.length} 张',
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
                        entry.content.replaceAll(RegExp(r'\s+'), ' ').trim(),
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
    final knowledge = context.watch<KnowledgeProvider>();
    final base = _resolveBase(knowledge, knowledge.knowledgeBases);
    final selectedCount = _visibleEntries(
      knowledge,
      base,
    ).where((entry) => _selectedEntryIds.contains(entry.id)).length;
    final decks = memoryCards.decks;
    final targetDeck = memoryCards.deckById(widget.targetDeckId);
    final deck = _resolveTargetDeck(memoryCards, targetDeck);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('target-deck-${deck?.id}'),
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
            IconButton(
              tooltip: '新建牌组',
              onPressed: _generating
                  ? null
                  : () => _createDeckAndSelect(memoryCards),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '已选 $selectedCount 条 · 将生成 $selectedCount 张',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
        ),
      ],
    );
  }

  Widget _previewView() {
    final result = _lastResult;
    final missingCount = result?.missingEntryIds.length ?? 0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '已生成 ${_previewCards.length} 张'
                  ' · 覆盖 ${result?.coveredEntryIds.length ?? _previewCards.length}'
                  '/${_generationEntries.length} 条',
                ),
              ),
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
        if (missingCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '有 $missingCount 个条目未生成卡片：'
              '${result!.missingEntryIds.map(_titleForEntry).join('、')}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (result != null && result.warnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              result.warnings.join('；'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
                          hint: card.hint ?? '',
                          onFrontChanged: (value) => _updatePreview(
                            index,
                            card.copyWith(front: value),
                          ),
                          onBackChanged: (value) =>
                              _updatePreview(index, card.copyWith(back: value)),
                          onHintChanged: (value) =>
                              _updatePreview(index, card.copyWith(hint: value)),
                        ),
                      ),
                      IconButton(
                        tooltip: '移除此卡片',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _removePreview(index),
                        icon: const Icon(Icons.delete_outline),
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

  String _titleForEntry(String entryId) {
    for (final entry in _generationEntries) {
      if (entry.id == entryId) return entry.title;
    }
    return entryId;
  }

  void _updatePreview(int index, GeneratedMemoryCard card) {
    final updated = List<GeneratedMemoryCard>.of(_previewCards);
    updated[index] = card;
    setState(() => _previewCards = updated);
  }

  void _removePreview(int index) {
    if (index < 0 || index >= _previewCards.length) return;
    setState(() {
      final updated = List<GeneratedMemoryCard>.of(_previewCards)
        ..removeAt(index);
      final remapped = _previewSelected
          .map((selected) {
            if (selected < index) return selected;
            if (selected > index) return selected - 1;
            return -1;
          })
          .where((selected) => selected >= 0)
          .toSet();
      _previewCards = updated;
      _previewSelected
        ..clear()
        ..addAll(remapped);
    });
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
    return entries.where((entry) => entry.categoryId == _categoryId).toList();
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
    final entries = _visibleEntries(
      knowledge,
      base,
    ).where((entry) => _selectedEntryIds.contains(entry.id)).toList();
    if (entries.isEmpty) {
      setState(() => _error = '请至少选择一条知识条目');
      return;
    }
    final serial = ++_generationSerial;
    setState(() {
      _generating = true;
      _error = null;
      _batchDone = 0;
      _batchTotal = null;
    });
    try {
      final service = MemoryCardGenerationService(
        api: ApiService(backend: context.read<BackendClient>()),
        modelConfigs: context.read<ModelConfigProvider>(),
        settings: context.read<SettingsProvider>(),
        plugins: context.read<PluginProvider>(),
      );
      final result = await service.generate(
        entries: entries,
        extraPrompt: _extraPrompt.text.trim(),
        onBatchProgress: (done, total) {
          if (!mounted || serial != _generationSerial) return;
          setState(() {
            _batchDone = done;
            _batchTotal = total;
          });
        },
        isCancelled: () => !mounted || serial != _generationSerial,
      );
      if (!mounted || serial != _generationSerial) return;
      setState(() {
        _lastResult = result;
        _generationEntries = List.of(entries);
        _previewCards = result.cards;
        _previewSelected
          ..clear()
          ..addAll(result.cards.asMap().keys);
        _generating = false;
        _batchDone = 0;
        _batchTotal = null;
      });
    } catch (error) {
      if (!mounted || serial != _generationSerial) return;
      setState(() {
        _generating = false;
        _batchDone = 0;
        _batchTotal = null;
        _error = '$error';
      });
    }
  }

  Future<void> _save(MemoryCardProvider provider) async {
    final knowledge = context.read<KnowledgeProvider>();
    final base = _resolveBase(knowledge, knowledge.knowledgeBases);
    final selectedDeck = _resolveTargetDeck(
      provider,
      provider.deckById(widget.targetDeckId),
    );
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
          sourceEntryId: preview.sourceEntryId,
          sourceBaseId: base?.id,
          status: MemoryCardStatus.newCard,
          dueAt: null,
          intervalDays: 0,
          easeFactor: 2.5,
          repetitions: 0,
          lapses: 0,
          reviewCount: 0,
          lastReviewedAt: null,
          enabled: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    if (cards.isEmpty) {
      setState(() => _error = '请至少勾选一张有效卡片');
      return;
    }
    final added = await provider.addCards(cards);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (added < cards.length) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('已保存 $added 张，跳过 ${cards.length - added} 张重复卡片'),
        ),
      );
    } else {
      messenger.showSnackBar(SnackBar(content: Text('已保存 $added 张记忆卡片')));
    }
    Navigator.pop(context);
  }

  Future<void> _createDeckAndSelect(MemoryCardProvider provider) async {
    final name = await _promptText(title: '新建牌组', label: '牌组名');
    if (name == null || name.trim().isEmpty) return;
    final id = await provider.addDeck(name: name.trim());
    if (!mounted) return;
    setState(() => _selectedDeckId = id);
  }

  Future<String?> _promptText({
    required String title,
    required String label,
  }) async {
    final controller = TextEditingController();
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

class _GeneratedCardEditor extends StatefulWidget {
  const _GeneratedCardEditor({
    super.key,
    required this.front,
    required this.back,
    required this.hint,
    required this.onFrontChanged,
    required this.onBackChanged,
    required this.onHintChanged,
  });

  final String front;
  final String back;
  final String hint;
  final ValueChanged<String> onFrontChanged;
  final ValueChanged<String> onBackChanged;
  final ValueChanged<String> onHintChanged;

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
    return Column(
      children: [
        TextField(
          controller: _front,
          maxLines: 2,
          decoration: const InputDecoration(labelText: '正面', isDense: true),
          onChanged: widget.onFrontChanged,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _back,
          maxLines: 3,
          decoration: const InputDecoration(labelText: '反面', isDense: true),
          onChanged: widget.onBackChanged,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _hint,
          maxLines: 1,
          decoration: const InputDecoration(labelText: '提示（可选）', isDense: true),
          onChanged: widget.onHintChanged,
        ),
      ],
    );
  }
}
