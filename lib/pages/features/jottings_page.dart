import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/jotting.dart';
import '../../models/local_date.dart';
import '../../providers/jotting_provider.dart';
import 'feature_shared.dart';
import 'jotting_detail_page.dart';

export 'jotting_detail_page.dart';

/// 随记列表页。
///
/// 以时间序列分组展示随记，支持关键词/正则、标签和日期范围过滤；
/// 选中后切换为 [JottingDetail]。
class JottingsPage extends StatefulWidget {
  final GlobalKey<JottingDetailState> detailKey;
  final String? selectedJottingId;
  final bool editing;
  final ValueChanged<String> onSelect;
  final ValueChanged<bool> onEditingChanged;
  final VoidCallback onBack;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onNewJotting;

  const JottingsPage({
    super.key,
    required this.detailKey,
    required this.selectedJottingId,
    required this.editing,
    required this.onSelect,
    required this.onEditingChanged,
    required this.onBack,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onNewJotting,
  });

  @override
  State<JottingsPage> createState() => _JottingsPageState();
}

enum _DateRange { all, today, last7Days, last30Days, custom }

class _JottingsPageState extends State<JottingsPage> {
  _DateRange _dateRange = _DateRange.all;
  LocalDate? _customStart;
  LocalDate? _customEnd;
  final Set<String> _selectedTags = {};

  @override
  Widget build(BuildContext context) {
    if (widget.selectedJottingId != null || widget.editing) {
      return JottingDetail(
        key: widget.detailKey,
        jottingId: widget.selectedJottingId,
        editing: widget.editing,
        onEditingChanged: widget.onEditingChanged,
        onSaved: widget.onSelect,
        onDeleted: widget.onBack,
      );
    }

    final provider = context.watch<JottingProvider>();
    final jottings = provider.jottings;
    if (jottings.isEmpty && _selectedTags.isEmpty) {
      return Column(
        children: [
          _searchBox(),
          Expanded(
            child: _emptyState(
              provider.jottings.isEmpty
                  ? '暂无随记'
                  : '没有符合过滤条件的随记',
            ),
          ),
        ],
      );
    }

    final query = widget.searchQuery.trim();
    final matcher = FeatureSearchMatcher.fromSearchSyntax(query);
    final visible = _visibleJottings(provider, matcher);
    final grouped = _groupByDate(visible);

    return Column(
      children: [
        _searchBox(),
        _filterBar(provider),
        if (matcher.hasError)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '正则表达式无效',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.redAccent),
              ),
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: const [
                    ListTile(
                      leading: Icon(Icons.search_off),
                      title: Text('未找到匹配的随记'),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 88),
                  itemCount: grouped.length,
                  itemBuilder: (context, index) {
                    final entry = grouped[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _dateHeader(entry.$1),
                        for (final item in entry.$2) _jottingCard(item),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _emptyState(String subtitle) {
    return FeatureEmptyState(
      icon: Icons.edit_note,
      title: '暂无随记',
      subtitle: subtitle == '暂无随记'
          ? '点击右上角 + 记录此刻的想法，支持 Markdown 和 LaTeX 渲染。'
          : subtitle,
    );
  }

  Widget _searchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: TextField(
        controller: widget.searchController,
        decoration: InputDecoration(
          hintText: '搜索随记内容或标签，支持 re:正则 或 /正则/i',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: widget.searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    widget.searchController.clear();
                    widget.onSearchChanged('');
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onChanged: widget.onSearchChanged,
      ),
    );
  }

  Widget _filterBar(JottingProvider provider) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final entry in [
            (_DateRange.all, '全部时间'),
            (_DateRange.today, '今天'),
            (_DateRange.last7Days, '近 7 天'),
            (_DateRange.last30Days, '近 30 天'),
            (_DateRange.custom, '自定义'),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(entry.$2),
                selected: _dateRange == entry.$1,
                onSelected: (_) => _selectDateRange(entry.$1),
              ),
            ),
          for (final tag in provider.tagCounts())
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text('#$tag'),
                selected: _selectedTags.contains(tag),
                onSelected: (selected) => setState(() {
                  selected
                      ? _selectedTags.add(tag)
                      : _selectedTags.remove(tag);
                }),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _selectDateRange(_DateRange range) async {
    if (range == _DateRange.custom) {
      final now = LocalDate.fromDateTime(DateTime.now());
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 1, 12, 31),
        initialDateRange: _customStart == null || _customEnd == null
            ? null
            : DateTimeRange(
                start: _customStart!.atStartOfDay(),
                end: _customEnd!.atStartOfDay(),
              ),
      );
      if (picked == null) return;
      setState(() {
        _dateRange = range;
        _customStart = LocalDate.fromDateTime(picked.start);
        _customEnd = LocalDate.fromDateTime(picked.end);
      });
      return;
    }
    setState(() {
      _dateRange = range;
      _customStart = null;
      _customEnd = null;
    });
  }

  List<Jotting> _visibleJottings(
    JottingProvider provider,
    FeatureSearchMatcher matcher,
  ) {
    final (start, end) = _dateRangeBounds();
    return provider
        .search(
          JottingSearchFilter(
            tags: _selectedTags.toList(),
            dateFrom: start,
            dateTo: end,
          ),
        )
        .where((item) {
          if (!matcher.isEmpty) {
            final tagsText = item.tags.join(' ');
            if (!matcher.matches(item.content) && !matcher.matches(tagsText)) {
              return false;
            }
          }
          return true;
        })
        .toList();
  }

  (LocalDate?, LocalDate?) _dateRangeBounds() {
    final today = LocalDate.fromDateTime(DateTime.now());
    switch (_dateRange) {
      case _DateRange.all:
        return (null, null);
      case _DateRange.today:
        return (today, today);
      case _DateRange.last7Days:
        return (today.addDays(-6), today);
      case _DateRange.last30Days:
        return (today.addDays(-29), today);
      case _DateRange.custom:
        return (_customStart, _customEnd);
    }
  }

  List<(String, List<Jotting>)> _groupByDate(List<Jotting> items) {
    final groups = <LocalDate, List<Jotting>>{};
    for (final item in items) {
      final date = LocalDate.fromDateTime(item.createdAt.toLocal());
      (groups[date] ??= []).add(item);
    }
    final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    final today = LocalDate.fromDateTime(DateTime.now());
    final yesterday = today.addDays(-1);
    return [
      for (final date in dates)
        (
          switch (date) {
            _ when date == today => '今天 · $date',
            _ when date == yesterday => '昨天 · $date',
            _ => date.toString(),
          },
          groups[date]!,
        ),
    ];
  }

  Widget _dateHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _jottingCard(Jotting item) {
    final scheme = Theme.of(context).colorScheme;
    final local = item.createdAt.toLocal();
    final time = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    final firstLine = item.content
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onSelect(item.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      firstLine.isEmpty ? '(无文字)' : firstLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    time,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '操作',
                    onSelected: (value) => _menuAction(value, item),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.content.replaceAll(RegExp(r'\s+'), ' ').trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (item.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in item.tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '#$tag',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _menuAction(String value, Jotting item) async {
    if (value == 'edit') {
      widget.onSelect(item.id);
      widget.onEditingChanged(true);
      return;
    }
    if (value == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除随记'),
          content: const Text('删除后将移入回收站，可稍后恢复。确定删除这条随记吗？'),
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
      if (confirmed != true || !mounted) return;
      await context.read<JottingProvider>().delete(item.id);
    }
  }
}
