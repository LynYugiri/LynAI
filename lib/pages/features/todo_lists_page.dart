part of '../feature_page.dart';

class _TodoListsPage extends StatefulWidget {
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;

  const _TodoListsPage({
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
  });

  @override
  State<_TodoListsPage> createState() => _TodoListsPageState();
}

class _TodoListsPageState extends State<_TodoListsPage> {
  static const _nativeTools = MethodChannel('lynai/native_tools');

  final _shot = ScreenshotController();
  final Set<String> _expandedListIds = {};
  late FeatureProvider _features;

  @override
  void initState() {
    super.initState();
    _features = context.read<FeatureProvider>();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FeatureProvider>();
    final lists = provider.todoLists;
    final visibleLists = _filteredLists(lists);
    if (lists.isEmpty) {
      return const _FeatureEmptyState(
        icon: Icons.checklist,
        title: '暂无待办清单',
        subtitle: '点击右上角 + 创建第一份清单，支持 Markdown 任务列表导入与导出。',
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: TextField(
            controller: widget.searchController,
            decoration: InputDecoration(
              hintText: '搜索清单标题或待办内容...',
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
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: widget.onSearchChanged,
          ),
        ),
        Expanded(
          child: visibleLists.isEmpty
              ? ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: const [
                    ListTile(
                      leading: Icon(Icons.search_off),
                      title: Text('未找到匹配的清单'),
                    ),
                  ],
                )
              : widget.searchQuery.isEmpty
              ? ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 20),
                  itemCount: visibleLists.length,
                  buildDefaultDragHandles: false,
                  onReorderItem: provider.reorderTodoLists,
                  itemBuilder: (context, index) => _listCard(
                    visibleLists[index],
                    index: index,
                    draggable: true,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 20),
                  itemCount: visibleLists.length,
                  itemBuilder: (context, index) => _listCard(
                    visibleLists[index],
                    index: index,
                    draggable: false,
                  ),
                ),
        ),
      ],
    );
  }

  List<TodoList> _filteredLists(List<TodoList> lists) {
    final query = widget.searchQuery.trim().toLowerCase();
    if (query.isEmpty) return lists;
    return lists.where((list) {
      return list.title.toLowerCase().contains(query) ||
          list.items.any((item) => item.text.toLowerCase().contains(query));
    }).toList();
  }

  Widget _listCard(
    TodoList list, {
    required int index,
    required bool draggable,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final expanded = _expandedListIds.contains(list.id);
    final done = list.items.where((e) => e.done).length;
    return Card(
      key: ValueKey(list.id),
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Column(
        children: [
          ListTile(
            leading: draggable
                ? ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  )
                : const Icon(Icons.checklist),
            title: Text(
              list.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('${list.items.length} 项，已完成 $done 项'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: expanded ? '折叠' : '展开',
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => _toggleExpanded(list.id),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) => _menu(v, list),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('重命名')),
                    const PopupMenuItem(value: 'export', child: Text('导出')),
                    const PopupMenuItem(value: 'image', child: Text('导出图片')),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
            onTap: () => _toggleExpanded(list.id),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(Icons.add_task, color: scheme.primary),
              title: Text('新增待办', style: TextStyle(color: scheme.primary)),
              onTap: () => _addItem(list),
            ),
            if (list.items.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '清单为空',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: list.items.length,
                onReorderItem: (oldIndex, newIndex) =>
                    _reorderItems(list, oldIndex, newIndex),
                itemBuilder: (context, index) =>
                    _todoItemTile(list, list.items[index], index),
              ),
          ],
        ],
      ),
    );
  }

  Widget _todoItemTile(TodoList list, TodoItem item, int index) {
    return ListTile(
      key: ValueKey(item.id),
      dense: true,
      leading: ReorderableDragStartListener(
        index: index,
        child: const Icon(Icons.drag_indicator),
      ),
      title: Row(
        children: [
          Checkbox(
            value: item.done,
            onChanged: (v) => _toggleItem(list, item, v ?? false),
          ),
          Expanded(
            child: Text(
              item.text,
              style: TextStyle(
                decoration: item.done ? TextDecoration.lineThrough : null,
                color: item.done
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : null,
              ),
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _editItemText(list, item),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => _deleteItem(list, item),
          ),
        ],
      ),
      onTap: () => _toggleItem(list, item, !item.done),
    );
  }

  void _toggleExpanded(String id) {
    setState(() {
      if (!_expandedListIds.add(id)) _expandedListIds.remove(id);
    });
  }

  Future<void> _menu(String value, TodoList list) async {
    switch (value) {
      case 'rename':
        await _rename(list);
      case 'export':
        await _export(list);
      case 'image':
        await _exportImage(list);
      case 'delete':
        await _delete(list);
    }
  }

  Future<void> _addItem(TodoList list) async {
    final text = await _itemTextDialog(title: '新增待办');
    if (text == null || text.isEmpty) return;
    const uuid = Uuid();
    await _features.updateTodoList(
      list.copyWith(
        items: [
          TodoItem(id: uuid.v4(), text: text),
          ...list.items,
        ],
      ),
    );
  }

  Future<void> _editItemText(TodoList list, TodoItem item) async {
    final text = await _itemTextDialog(title: '编辑待办', initialText: item.text);
    if (text == null || text.isEmpty) return;
    await _features.updateTodoList(
      list.copyWith(
        items: list.items
            .map((e) => e.id == item.id ? e.copyWith(text: text) : e)
            .toList(),
      ),
    );
  }

  Future<void> _deleteItem(TodoList list, TodoItem item) async {
    await _features.updateTodoList(
      list.copyWith(items: list.items.where((e) => e.id != item.id).toList()),
    );
  }

  Future<void> _reorderItems(TodoList list, int oldIndex, int newIndex) async {
    final items = List<TodoItem>.from(list.items);
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);
    await _features.updateTodoList(list.copyWith(items: items));
  }

  Future<String?> _itemTextDialog({
    required String title,
    String initialText = '',
  }) async {
    final ctrl = TextEditingController(text: initialText);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
          decoration: const InputDecoration(labelText: '内容'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return text;
  }

  Future<void> _toggleItem(TodoList list, TodoItem item, bool done) async {
    await _features.updateTodoList(
      list.copyWith(
        items: list.items
            .map((e) => e.id == item.id ? e.copyWith(done: done) : e)
            .toList(),
      ),
    );
  }

  Future<void> _rename(TodoList list) async {
    final ctrl = TextEditingController(text: list.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
          decoration: const InputDecoration(labelText: '标题'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (!mounted) return;
    if (title != null && title.isNotEmpty) {
      await _features.updateTodoList(list.copyWith(title: title));
    }
  }

  Future<void> _export(TodoList list) async {
    final fileName = '${safeExportFileName(list.title, fallback: 'todo')}.md';
    final bytes = Uint8List.fromList(utf8.encode(_todoMarkdown(list)));
    final path = await saveBytesWithPicker(
      dialogTitle: '导出待办清单',
      fileName: fileName,
      bytes: bytes,
    );
    if (path == null) return;
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('待办清单已导出到 $path')));
  }

  Future<void> _exportImage(TodoList list) async {
    final images = await _captureTodoImages(list);
    if (images.isEmpty) return;
    try {
      final message = await shareOrSavePngImages(
        images: images,
        filePrefix: 'todo',
        nativeTools: _nativeTools,
        clipboardMessage: '待办清单图片已复制到剪贴板',
        galleryMessage: '待办清单图片已保存到图库',
      );
      if (!mounted || message == null) return;
      _showImageSnack(message);
    } catch (e) {
      if (!mounted) return;
      _showImageSnack('导出图片失败: $e');
    }
  }

  Future<List<Uint8List>> _captureTodoImages(TodoList list) async {
    final theme = Theme.of(context);
    final chunks = _todoImagePages(list.items);
    final images = <Uint8List>[];
    for (var i = 0; i < chunks.length; i++) {
      if (!mounted) return images;
      final image = await _shot.captureFromLongWidget(
        _TodoShareImage(
          list: list.copyWith(items: chunks[i]),
          totalCount: list.items.length,
          totalDone: list.items.where((e) => e.done).length,
          seedColor: theme.colorScheme.primary,
          brightness: theme.brightness,
          pageNumber: chunks.length == 1 ? null : i + 1,
          pageCount: chunks.length == 1 ? null : chunks.length,
        ),
        pixelRatio: _exportImagePixelRatio,
        context: context,
        constraints: const BoxConstraints(maxWidth: 720),
      );
      if (!mounted) return images;
      images.add(image);
    }
    return images;
  }

  List<List<TodoItem>> _todoImagePages(List<TodoItem> items) {
    if (items.isEmpty) return const [[]];
    final pages = <List<TodoItem>>[];
    var current = <TodoItem>[];
    var currentWeight = 0;
    for (final item in items.expand(_splitTodoItemForImage)) {
      final weight = item.text.length + 120;
      if (current.isNotEmpty &&
          currentWeight + weight > _exportTodoPageWeight) {
        pages.add(current);
        current = <TodoItem>[];
        currentWeight = 0;
      }
      current.add(item);
      currentWeight += weight;
    }
    if (current.isNotEmpty) pages.add(current);
    return pages;
  }

  Iterable<TodoItem> _splitTodoItemForImage(TodoItem item) sync* {
    if (item.text.length <= _exportTodoItemChunkLength) {
      yield item;
      return;
    }
    final chunks = _splitTodoTextForImage(item.text);
    for (var i = 0; i < chunks.length; i++) {
      yield TodoItem(
        id: '${item.id}_export_$i',
        text: chunks[i],
        done: item.done,
      );
    }
  }

  List<String> _splitTodoTextForImage(String text) {
    final chunks = <String>[];
    var start = 0;
    while (start < text.length) {
      var end = (start + _exportTodoItemChunkLength).clamp(0, text.length);
      if (end < text.length) {
        final lineBreak = text.lastIndexOf('\n', end);
        final space = text.lastIndexOf(' ', end);
        final splitAt = [lineBreak, space]
            .where((i) => i > start + (_exportTodoItemChunkLength ~/ 2))
            .fold<int>(-1, (best, i) => i > best ? i : best);
        if (splitAt != -1) end = splitAt;
      }
      final chunk = text.substring(start, end).trim();
      if (chunk.isNotEmpty) chunks.add(chunk);
      start = end;
    }
    return chunks;
  }

  void _showImageSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(shortSnackBar(message));
  }

  Future<void> _delete(TodoList list) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除待办清单'),
        content: Text('确定删除"${list.title}"吗？'),
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
    if (ok != true || !mounted) return;
    await _features.deleteTodoList(list.id);
    setState(() => _expandedListIds.remove(list.id));
  }

  String _todoMarkdown(TodoList list) {
    final items = list.items
        .map((e) => '- [${e.done ? 'x' : ' '}] ${e.text}')
        .join('\n');
    return '# ${list.title}\n\n$items\n';
  }
}

class _TodoShareImage extends StatelessWidget {
  final TodoList list;
  final int? totalCount;
  final int? totalDone;
  final Color seedColor;
  final Brightness brightness;
  final int? pageNumber;
  final int? pageCount;

  const _TodoShareImage({
    required this.list,
    this.totalCount,
    this.totalDone,
    required this.seedColor,
    required this.brightness,
    this.pageNumber,
    this.pageCount,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    final done = totalDone ?? list.items.where((e) => e.done).length;
    final count = totalCount ?? list.items.length;
    final bgColor = Color.lerp(
      scheme.surface,
      scheme.primary,
      isDark ? 0.08 : 0.035,
    )!;
    final cardColor = Color.lerp(
      scheme.surface,
      scheme.surfaceContainerHighest,
      isDark ? 0.35 : 0.18,
    )!;
    final mutedColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 720,
        padding: const EdgeInsets.all(28),
        color: bgColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.checklist,
                    color: scheme.onPrimary,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        list.title.isEmpty ? 'LynAI 待办清单' : list.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '待办清单 · $count 项 · 已完成 $done 项',
                        style: TextStyle(color: mutedColor, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.55),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: list.items.isEmpty
                    ? [
                        Text(
                          '暂无待办',
                          style: TextStyle(color: mutedColor, fontSize: 18),
                        ),
                      ]
                    : list.items.map((item) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                item.done
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: item.done ? scheme.primary : mutedColor,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.text,
                                  style: TextStyle(
                                    color: item.done
                                        ? mutedColor
                                        : scheme.onSurface,
                                    fontSize: 18,
                                    height: 1.35,
                                    decoration: item.done
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              pageNumber == null || pageCount == null
                  ? 'Exported from LynAI'
                  : 'Exported from LynAI · $pageNumber/$pageCount',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: mutedColor,
                fontSize: 18,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
