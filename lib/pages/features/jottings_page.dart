import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/jotting.dart';
import '../../models/local_date.dart';
import '../../providers/jotting_provider.dart';
import '../../services/storage_v2_service.dart';
import '../../widgets/latex_renderer.dart';
import 'feature_shared.dart';
import 'jotting_detail_page.dart';
import 'jotting_editor_page.dart';

export 'jotting_editor_page.dart';

/// Local-first jotting timeline.
///
/// Creation lives inside the timeline rather than behind an add button. Reading
/// and editing use dedicated full-screen routes so the timeline remains mounted
/// and keeps its scroll and filter context.
class JottingsPage extends StatefulWidget {
  const JottingsPage({
    super.key,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    this.onReferenceTap,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<JottingReference>? onReferenceTap;

  @override
  State<JottingsPage> createState() => _JottingsPageState();
}

enum _DateRange { all, today, last7Days, last30Days, custom }

enum _CardAction { edit, copy, delete }

class _JottingsPageState extends State<JottingsPage> {
  final _scrollController = ScrollController();
  final Set<String> _selectedTags = {};
  final Set<String> _expandedJottingIds = {};

  _DateRange _dateRange = _DateRange.all;
  LocalDate? _customStart;
  LocalDate? _customEnd;
  late bool _searchExpanded;
  late bool _filterExpanded;
  String? _highlightedJottingId;
  Timer? _highlightResetTimer;

  @override
  void initState() {
    super.initState();
    _searchExpanded = widget.searchQuery.trim().isNotEmpty;
    _filterExpanded = false;
  }

  @override
  void didUpdateWidget(covariant JottingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery.trim().isNotEmpty &&
        oldWidget.searchQuery.trim().isEmpty) {
      _searchExpanded = true;
    }
  }

  @override
  void dispose() {
    _highlightResetTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<JottingProvider>();
    final query = widget.searchQuery.trim();
    final matcher = FeatureSearchMatcher.fromSearchSyntax(query);
    final visible = _visibleJottings(provider, matcher);
    final hasSearchQuery = query.isNotEmpty;
    final hasDateOrTagFilters =
        _dateRange != _DateRange.all || _selectedTags.isNotEmpty;
    final hasActiveFilters = hasDateOrTagFilters || hasSearchQuery;

    return Column(
      children: [
        _composer(),
        _searchFilterHeader(
          hasSearchQuery: hasSearchQuery,
          hasDateOrTagFilters: hasDateOrTagFilters,
        ),
        _collapsiblePanel(provider),
        if (matcher.hasError)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
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
              ? _emptyState(
                  icon: provider.jottings.isEmpty && !hasActiveFilters
                      ? Icons.edit_note
                      : Icons.search_off,
                  title: provider.jottings.isEmpty && !hasActiveFilters
                      ? '暂无随记'
                      : '未找到匹配的随记',
                  subtitle: provider.jottings.isEmpty && !hasActiveFilters
                      ? '点击上方输入框记录此刻的想法，支持 Markdown 和 LaTeX。'
                      : '试试调整关键词、标签或日期范围。',
                  showClearFilters: hasActiveFilters,
                )
              : _timeline(visible),
        ),
      ],
    );
  }

  Widget _composer() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Semantics(
        button: true,
        label: '新建随记',
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _createJotting,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.edit_note, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '记下此刻的想法…',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: scheme.outline,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchFilterHeader({
    required bool hasSearchQuery,
    required bool hasDateOrTagFilters,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '时间线',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (hasSearchQuery || hasDateOrTagFilters)
            TextButton(onPressed: _clearFilters, child: const Text('清除')),
          IconButton(
            tooltip: '搜索',
            isSelected: _searchExpanded || hasSearchQuery,
            icon: const Icon(Icons.search),
            onPressed: () => setState(() => _searchExpanded = !_searchExpanded),
          ),
          IconButton(
            tooltip: '筛选',
            isSelected: _filterExpanded || hasDateOrTagFilters,
            icon: Icon(
              hasDateOrTagFilters ? Icons.filter_alt : Icons.filter_list,
            ),
            onPressed: () => setState(() => _filterExpanded = !_filterExpanded),
          ),
        ],
      ),
    );
  }

  Widget _collapsiblePanel(JottingProvider provider) {
    final children = [
      if (_searchExpanded) _searchBox(),
      if (_filterExpanded) _filterBar(provider),
    ];
    return AnimatedSize(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: children.isEmpty
          ? const SizedBox(width: double.infinity)
          : Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _searchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: TextField(
        controller: widget.searchController,
        decoration: InputDecoration(
          hintText: '搜索内容或标签',
          prefixIcon: const Icon(Icons.search),
          helperText: '高级：re:正则 或 /正则/i',
          isDense: true,
          suffixIcon: widget.searchQuery.isNotEmpty
              ? IconButton(
                  tooltip: '清空搜索',
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
      height: 42,
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
                visualDensity: VisualDensity.compact,
                selected: _dateRange == entry.$1,
                onSelected: (_) => _selectDateRange(entry.$1),
              ),
            ),
          for (final tag in provider.tagCounts())
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text('#$tag'),
                visualDensity: VisualDensity.compact,
                selected: _selectedTags.contains(tag),
                onSelected: (selected) => setState(() {
                  selected ? _selectedTags.add(tag) : _selectedTags.remove(tag);
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool showClearFilters,
  }) {
    return Stack(
      children: [
        FeatureEmptyState(icon: icon, title: title, subtitle: subtitle),
        if (showClearFilters)
          Align(
            alignment: const Alignment(0, 0.55),
            child: FilledButton.tonal(
              onPressed: _clearFilters,
              child: const Text('清除筛选'),
            ),
          ),
      ],
    );
  }

  Widget _timeline(List<Jotting> visible) {
    final rows = <_TimelineRow>[];
    for (final entry in _groupByDate(visible)) {
      rows.add(_TimelineRow.date(entry.$1));
      rows.addAll(entry.$2.map(_TimelineRow.jotting));
    }
    return ListView.builder(
      key: const PageStorageKey('jottings-timeline'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 88),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return row.isDate
            ? _dateHeader(row.dateLabel!)
            : _timelineEntry(row.jotting!);
      },
    );
  }

  Widget _dateHeader(String label) {
    final scheme = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: scheme.outlineVariant),
                ),
                Positioned(
                  top: 10,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.surface, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
              child: Semantics(
                header: true,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineEntry(Jotting item) {
    final scheme = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: scheme.outlineVariant),
                ),
                Positioned(
                  top: 16,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.primary, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _jottingCard(item)),
        ],
      ),
    );
  }

  Widget _jottingCard(Jotting item) {
    final scheme = Theme.of(context).colorScheme;
    final expanded = _expandedJottingIds.contains(item.id);
    final shouldCollapse = _shouldCollapse(item.content);
    final highlighted = _highlightedJottingId == item.id;
    return AnimatedContainer(
      key: ValueKey('jotting-card-${item.id}'),
      duration: const Duration(milliseconds: 280),
      margin: const EdgeInsets.fromLTRB(0, 4, 4, 10),
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.primaryContainer.withValues(alpha: 0.48)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openDetail(item.id),
          onLongPress: () => _showCardActions(item),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatTime(item.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRect(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: !expanded && shouldCollapse
                            ? 240
                            : double.infinity,
                      ),
                      child: MarkdownWithLatex(
                        content: item.content,
                        selectable: false,
                        renderMermaid: false,
                      ),
                    ),
                  ),
                ),
                if (shouldCollapse) ...[
                  const SizedBox(height: 2),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      expanded
                          ? _expandedJottingIds.remove(item.id)
                          : _expandedJottingIds.add(item.id);
                    }),
                    icon: Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                    label: Text(expanded ? '收起' : '展开全文'),
                  ),
                ],
                _buildTimelineAttachments(item),
                _buildTimelineReferences(item),
                if (item.tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
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
      ),
    );
  }

  Widget _buildTimelineAttachments(Jotting item) {
    if (item.attachments.isEmpty) return const SizedBox.shrink();
    final images = item.attachments.where((item) => item.isImage).toList();
    final files = item.attachments.where((item) => !item.isImage).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (images.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final image in images)
                  _TimelineImageAttachment(attachment: image),
              ],
            ),
          if (files.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final file in files) _TimelineFileAttachment(attachment: file),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineReferences(Jotting item) {
    if (item.references.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final reference in item.references)
            _TimelineReferenceChip(
              reference: reference,
              onTap: widget.onReferenceTap == null
                  ? null
                  : () => widget.onReferenceTap!(reference),
            ),
        ],
      ),
    );
  }

  Future<void> _createJotting() async {
    final result = await _openEditor();
    if (!mounted || result == null) return;
    await _afterEditorResult(result);
  }

  Future<void> _editJotting(String id) async {
    final result = await _openEditor(jottingId: id);
    if (!mounted || result == null) return;
    await _afterEditorResult(result);
  }

  Future<JottingEditorResult?> _openEditor({String? jottingId}) {
    return Navigator.of(context).push<JottingEditorResult>(
      MaterialPageRoute(
        fullscreenDialog: jottingId == null,
        builder: (_) => JottingEditorPage(jottingId: jottingId),
      ),
    );
  }

  Future<void> _afterEditorResult(JottingEditorResult result) async {
    if (result.created) {
      widget.searchController.clear();
      widget.onSearchChanged('');
      setState(() {
        _dateRange = _DateRange.all;
        _customStart = null;
        _customEnd = null;
        _selectedTags.clear();
        _highlightedJottingId = result.jottingId;
      });
      await Future<void>.delayed(Duration.zero);
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    } else {
      setState(() => _highlightedJottingId = result.jottingId);
    }
    _highlightResetTimer?.cancel();
    _highlightResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _highlightedJottingId == result.jottingId) {
        setState(() => _highlightedJottingId = null);
      }
    });
  }

  Future<void> _openDetail(String id) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) {
          return Consumer<JottingProvider>(
            builder: (context, provider, _) {
              final item = provider.byId(id);
              if (item == null) {
                return const Scaffold(body: Center(child: Text('随记不存在或已删除')));
              }
              return JottingDetail(
                jotting: item,
                onEdit: () async {
                  final result = await _openEditor(jottingId: id);
                  if (!mounted || result == null) return;
                  await _afterEditorResult(result);
                },
                onReferenceTap: widget.onReferenceTap == null
                    ? null
                    : (reference) {
                        Navigator.of(context).pop();
                        widget.onReferenceTap!(reference);
                      },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showCardActions(Jotting item) async {
    final action = await showModalBottomSheet<_CardAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () => Navigator.pop(context, _CardAction.edit),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制正文'),
              onTap: () => Navigator.pop(context, _CardAction.copy),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '删除',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.pop(context, _CardAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _CardAction.edit:
        await _editJotting(item.id);
      case _CardAction.copy:
        await Clipboard.setData(ClipboardData(text: item.content));
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('随记正文已复制')));
      case _CardAction.delete:
        await _confirmDelete(item);
    }
  }

  Future<void> _confirmDelete(Jotting item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除随记'),
        content: const Text('删除后将移入回收站，可稍后恢复。确定删除这条随记吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      await context.read<JottingProvider>().delete(item.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
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
      if (!mounted || picked == null) return;
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

  void _clearFilters() {
    widget.searchController.clear();
    widget.onSearchChanged('');
    setState(() {
      _dateRange = _DateRange.all;
      _customStart = null;
      _customEnd = null;
      _selectedTags.clear();
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
          if (matcher.isEmpty) return true;
          return matcher.matches(item.content) ||
              matcher.matches(item.tags.join(' '));
        })
        .toList();
  }

  (LocalDate?, LocalDate?) _dateRangeBounds() {
    final today = LocalDate.fromDateTime(DateTime.now());
    return switch (_dateRange) {
      _DateRange.all => (null, null),
      _DateRange.today => (today, today),
      _DateRange.last7Days => (today.addDays(-6), today),
      _DateRange.last30Days => (today.addDays(-29), today),
      _DateRange.custom => (_customStart, _customEnd),
    };
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

  bool _shouldCollapse(String content) {
    return content.length > 420 || '\n'.allMatches(content).length >= 9;
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _TimelineRow {
  const _TimelineRow.date(this.dateLabel) : jotting = null;

  const _TimelineRow.jotting(this.jotting) : dateLabel = null;

  final String? dateLabel;
  final Jotting? jotting;

  bool get isDate => dateLabel != null;
}

class _TimelineImageAttachment extends StatefulWidget {
  const _TimelineImageAttachment({required this.attachment});

  final JottingAttachment attachment;

  @override
  State<_TimelineImageAttachment> createState() =>
      _TimelineImageAttachmentState();
}

class _TimelineImageAttachmentState extends State<_TimelineImageAttachment> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _resolvePath();
  }

  Future<void> _resolvePath() async {
    try {
      final storage = context.read<StorageV2Service>();
      final resource = await storage.findResourceById(
        widget.attachment.resourceId,
      );
      final path = resource == null ? null : await storage.resourcePath(resource);
      if (!mounted) return;
      setState(() => _path = path);
    } catch (_) {
      if (!mounted) return;
      setState(() => _path = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _path == null ? null : () => _openImage(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 72,
          height: 72,
          child: _path == null
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                  ),
                  child: const Icon(Icons.image_outlined),
                )
              : Image.file(
                  File(_path!),
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                    ),
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
        ),
      ),
    );
  }

  void _openImage(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                child: Image.file(File(_path!), fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineFileAttachment extends StatelessWidget {
  const _TimelineFileAttachment({required this.attachment});

  final JottingAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined, size: 16, color: scheme.primary),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              attachment.originalName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineReferenceChip extends StatelessWidget {
  const _TimelineReferenceChip({required this.reference, this.onTap});

  final JottingReference reference;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (reference.type) {
      JottingReferenceType.note => (Icons.sticky_note_2_outlined, Colors.blue),
      JottingReferenceType.task => (Icons.checklist, Colors.green),
      JottingReferenceType.knowledgeEntry => (
        Icons.local_library_outlined,
        Colors.orange,
      ),
    };
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  reference.title.isEmpty ? '未命名引用' : reference.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
