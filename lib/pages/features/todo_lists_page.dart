part of '../feature_page.dart';

enum _TaskPageView { overview, unfinished, completed }

class _TodoListsPage extends StatefulWidget {
  const _TodoListsPage({
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;

  @override
  State<_TodoListsPage> createState() => _TodoListsPageState();
}

class _TodoListsPageState extends State<_TodoListsPage> {
  static const _nativeTools = MethodChannel('lynai/native_tools');

  final _shot = ScreenshotController();
  final Set<String> _expandedListIds = {};
  _TaskPageView _view = _TaskPageView.overview;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TaskProvider>();
    return Column(
      children: [
        _statusNavigation(provider),
        _searchField(),
        Expanded(
          child: switch (_view) {
            _TaskPageView.overview => _overview(provider),
            _TaskPageView.unfinished => _statusView(
              provider,
              title: '未完成',
              tasks: _filteredTasks(provider.unfinishedTasks),
            ),
            _TaskPageView.completed => _statusView(
              provider,
              title: '已完成',
              tasks: _filteredTasks(provider.completedTasks),
            ),
          },
        ),
      ],
    );
  }

  Widget _statusNavigation(TaskProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: '任务清单',
            onPressed: () => setState(() => _view = _TaskPageView.overview),
            icon: const Icon(Icons.checklist),
            isSelected: _view == _TaskPageView.overview,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statusButton(
              label: '未完成',
              count: provider.unfinishedTasks.length,
              selected: _view == _TaskPageView.unfinished,
              onPressed: () => setState(() => _view = _TaskPageView.unfinished),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statusButton(
              label: '已完成',
              count: provider.completedTasks.length,
              selected: _view == _TaskPageView.completed,
              onPressed: () => setState(() => _view = _TaskPageView.completed),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusButton({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onPressed,
  }) => selected
      ? FilledButton.tonal(onPressed: onPressed, child: Text('$label $count'))
      : OutlinedButton(onPressed: onPressed, child: Text('$label $count'));

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: TextField(
        controller: widget.searchController,
        onChanged: widget.onSearchChanged,
        decoration: InputDecoration(
          hintText: '搜索清单标题、任务或备注...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: widget.searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除搜索',
                  onPressed: () {
                    widget.searchController.clear();
                    widget.onSearchChanged('');
                  },
                  icon: const Icon(Icons.clear),
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _overview(TaskProvider provider) {
    final lists = _filteredLists(provider);
    if (provider.lists.isEmpty) {
      return const _FeatureEmptyState(
        icon: Icons.checklist,
        title: '暂无任务清单',
        subtitle: '点击右上角 + 创建第一份清单。未归入清单的任务可在状态入口中查看。',
      );
    }
    if (lists.isEmpty) {
      return const ListTile(
        leading: Icon(Icons.search_off),
        title: Text('未找到匹配的清单'),
      );
    }
    if (widget.searchQuery.trim().isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 20),
        itemCount: lists.length,
        itemBuilder: (context, index) =>
            _listCard(provider, lists[index], index: index, draggable: false),
      );
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 20),
      itemCount: lists.length,
      buildDefaultDragHandles: false,
      onReorderItem: provider.reorderLists,
      itemBuilder: (context, index) =>
          _listCard(provider, lists[index], index: index, draggable: true),
    );
  }

  List<TaskList> _filteredLists(TaskProvider provider) {
    final query = widget.searchQuery.trim().toLowerCase();
    if (query.isEmpty) return provider.lists;
    return provider.lists.where((list) {
      return list.title.toLowerCase().contains(query) ||
          provider
              .tasksForList(list.id)
              .any(
                (task) =>
                    task.title.toLowerCase().contains(query) ||
                    (task.note ?? '').toLowerCase().contains(query),
              );
    }).toList();
  }

  List<Task> _filteredTasks(List<Task> tasks) {
    final query = widget.searchQuery.trim().toLowerCase();
    if (query.isEmpty) return tasks;
    return tasks.where((task) {
      return task.title.toLowerCase().contains(query) ||
          (task.note ?? '').toLowerCase().contains(query);
    }).toList();
  }

  Widget _listCard(
    TaskProvider provider,
    TaskList list, {
    required int index,
    required bool draggable,
  }) {
    final allTasks = provider.tasksForList(list.id);
    final tasks = _filteredTasks(allTasks);
    final expanded = _expandedListIds.contains(list.id);
    final done = allTasks.where((task) => task.isCompleted).length;
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
            subtitle: Text('${allTasks.length} 项，已完成 $done 项'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: expanded ? '折叠' : '展开',
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => _toggleExpanded(list.id),
                ),
                PopupMenuButton<String>(
                  tooltip: '清单操作',
                  onSelected: (value) => _listMenu(value, list),
                  itemBuilder: (_) => _listMenuItems,
                ),
              ],
            ),
            onTap: () => _toggleExpanded(list.id),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(
                Icons.add_task,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                '新增任务',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              onTap: () => _addTask(list.id),
            ),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.searchQuery.isEmpty ? '清单为空' : '没有匹配任务',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else if (widget.searchQuery.trim().isEmpty)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: tasks.length,
                onReorderItem: (oldIndex, newIndex) =>
                    provider.reorderTaskEntries(list.id, oldIndex, newIndex),
                itemBuilder: (context, taskIndex) =>
                    _taskTile(provider, tasks[taskIndex], dragIndex: taskIndex),
              )
            else
              for (final task in tasks) _taskTile(provider, task),
          ],
        ],
      ),
    );
  }

  void _toggleExpanded(String id) {
    setState(() {
      if (!_expandedListIds.add(id)) _expandedListIds.remove(id);
    });
  }

  Future<void> _addTask(String listId) async {
    final title = await _textDialog('新增任务', '');
    if (title == null || title.isEmpty || !mounted) return;
    await context.read<TaskProvider>().addTask(title: title, listId: listId);
  }

  Widget _statusView(
    TaskProvider provider, {
    required String title,
    required List<Task> tasks,
  }) {
    if (tasks.isEmpty) {
      return Center(
        child: Text(widget.searchQuery.isEmpty ? '暂无$title任务' : '未找到匹配任务'),
      );
    }
    final groups = <String?, List<Task>>{};
    for (final task in tasks) {
      final listId = provider.entryForTask(task.id)?.taskListId;
      groups.putIfAbsent(listId, () => []).add(task);
    }
    final orderedKeys = <String?>[
      for (final list in provider.lists)
        if (groups.containsKey(list.id)) list.id,
      if (groups.containsKey(null)) null,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        for (final listId in orderedKeys) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
            child: Text(
              listId == null
                  ? '未归入清单'
                  : provider.listById(listId)?.title ?? '未知清单',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final task in groups[listId]!) _taskTile(provider, task),
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<PopupMenuEntry<String>> get _listMenuItems => const [
    PopupMenuItem(value: 'rename', child: Text('重命名')),
    PopupMenuItem(value: 'export', child: Text('导出 Markdown')),
    PopupMenuItem(value: 'image', child: Text('导出长图')),
    PopupMenuDivider(),
    PopupMenuItem(value: 'delete', child: Text('删除清单')),
  ];

  Widget _taskTile(TaskProvider provider, Task task, {int? dragIndex}) {
    final scheme = Theme.of(context).colorScheme;
    final overdue = task.isOverdue;
    final status = _taskStatus(task);
    return ListTile(
      key: ValueKey(task.id),
      dense: true,
      tileColor: overdue ? scheme.error.withValues(alpha: 0.05) : null,
      contentPadding: const EdgeInsets.only(left: 8, right: 4),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dragIndex != null)
            ReorderableDragStartListener(
              index: dragIndex,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.drag_indicator),
              ),
            ),
          Semantics(
            label: task.isCompleted ? '标记为未完成' : '标记为已完成',
            child: Checkbox(
              value: task.isCompleted,
              onChanged: (_) => task.isCompleted
                  ? provider.uncompleteTask(task.id)
                  : provider.completeTask(task.id),
            ),
          ),
        ],
      ),
      title: Text(
        task.title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
          color: task.isCompleted
              ? scheme.onSurfaceVariant
              : overdue
              ? scheme.error
              : null,
        ),
      ),
      subtitle: status == null
          ? null
          : Text(
              status,
              style: TextStyle(
                color: overdue ? scheme.error : scheme.onSurfaceVariant,
                fontWeight: overdue ? FontWeight.w700 : null,
              ),
            ),
      trailing: PopupMenuButton<String>(
        tooltip: '任务操作',
        onSelected: (value) => _taskMenu(value, provider, task),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('编辑')),
          const PopupMenuItem(value: 'move', child: Text('移动到')),
          PopupMenuItem(
            value: 'complete',
            child: Text(task.isCompleted ? '标记为未完成' : '标记为已完成'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'delete', child: Text('删除任务')),
        ],
      ),
      onTap: () => _editTask(provider, task),
    );
  }

  String? _taskStatus(Task task) {
    final values = <String>[];
    if (task.isOverdue) values.add('已逾期');
    if (task.plannedDate != null) {
      values.add(
        '计划 ${task.plannedDate}${task.plannedTime == null ? '' : ' ${task.plannedTime}'}',
      );
    }
    if (task.dueDate != null) {
      values.add(
        '截止 ${task.dueDate}${task.dueTime == null ? '' : ' ${task.dueTime}'}',
      );
    }
    if (task.reminders.isNotEmpty) values.add('${task.reminders.length} 个提醒');
    if ((task.note ?? '').trim().isNotEmpty) values.add('有备注');
    return values.isEmpty ? null : values.join(' · ');
  }

  Future<void> _taskMenu(String value, TaskProvider provider, Task task) async {
    switch (value) {
      case 'edit':
        await _editTask(provider, task);
      case 'move':
        await _moveTask(provider, task);
      case 'complete':
        await (task.isCompleted
            ? provider.uncompleteTask(task.id)
            : provider.completeTask(task.id));
      case 'delete':
        await provider.deleteTask(task.id);
    }
  }

  Future<void> _editTask(TaskProvider provider, Task task) async {
    await _openCanonicalTaskEditor(context, task: task);
  }

  Future<void> _moveTask(TaskProvider provider, Task task) async {
    final current = provider.entryForTask(task.id)?.taskListId;
    const unassigned = '__unassigned__';
    final selection = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('移动任务'),
        children: [
          ListTile(
            leading: Icon(
              current == null
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: const Text('未归入清单'),
            onTap: () => Navigator.pop(ctx, unassigned),
          ),
          for (final list in provider.lists)
            ListTile(
              leading: Icon(
                current == list.id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(list.title),
              onTap: () => Navigator.pop(ctx, list.id),
            ),
        ],
      ),
    );
    if (!mounted || selection == null) return;
    final listId = selection == unassigned ? null : selection;
    if (listId == current) return;
    await provider.moveTask(task.id, listId);
  }

  Future<void> _listMenu(String value, TaskList list) async {
    switch (value) {
      case 'rename':
        await _renameList(list);
      case 'export':
        await _exportList(list);
      case 'image':
        await _exportListImage(list);
      case 'delete':
        await _deleteList(list);
    }
  }

  Future<void> _renameList(TaskList list) async {
    final title = await _textDialog('重命名清单', list.title);
    if (title == null || title.isEmpty || !mounted) return;
    await context.read<TaskProvider>().updateList(list.copyWith(title: title));
  }

  Future<String?> _textDialog(String title, String initialValue) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => TextEditingControllerHost(
        initialTexts: [initialValue],
        builder: (ctx, controllers) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controllers.single,
            autofocus: true,
            decoration: const InputDecoration(labelText: '名称'),
            onSubmitted: (_) =>
                Navigator.pop(ctx, controllers.single.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, controllers.single.text.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteList(TaskList list) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除任务清单'),
        content: Text(
          '删除“${list.title}”后，清单内任务会保留，但不再属于任何清单。未完成任务可在“未完成”中查看，已完成任务可在“已完成”中查看。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除清单'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<TaskProvider>().deleteList(list.id);
    if (mounted) setState(() => _expandedListIds.remove(list.id));
  }

  Future<void> _exportList(TaskList list) async {
    final tasks = context.read<TaskProvider>().tasksForList(list.id);
    final bytes = Uint8List.fromList(utf8.encode(_taskMarkdown(list, tasks)));
    final path = await saveBytesWithPicker(
      dialogTitle: '导出任务清单',
      fileName: '${safeExportFileName(list.title, fallback: 'tasks')}.md',
      bytes: bytes,
    );
    if (path == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('任务清单已导出到 $path')));
  }

  String _taskMarkdown(TaskList list, List<Task> tasks) {
    final items = tasks
        .map((task) => '- [${task.isCompleted ? 'x' : ' '}] ${task.title}')
        .join('\n');
    return '# ${list.title}\n\n$items\n';
  }

  Future<void> _exportListImage(TaskList list) async {
    final tasks = context.read<TaskProvider>().tasksForList(list.id);
    final chunks = _taskImagePages(tasks);
    final theme = Theme.of(context);
    final images = <Uint8List>[];
    for (var i = 0; i < chunks.length; i++) {
      if (!mounted) return;
      images.add(
        await _shot.captureFromLongWidget(
          _TaskShareImage(
            title: list.title,
            tasks: chunks[i],
            totalCount: tasks.length,
            totalCompleted: tasks.where((task) => task.isCompleted).length,
            seedColor: theme.colorScheme.primary,
            brightness: theme.brightness,
            pageNumber: chunks.length == 1 ? null : i + 1,
            pageCount: chunks.length == 1 ? null : chunks.length,
          ),
          pixelRatio: _exportImagePixelRatio,
          context: context,
          constraints: const BoxConstraints(maxWidth: 720),
        ),
      );
    }
    try {
      final message = await shareOrSavePngImages(
        images: images,
        filePrefix: 'tasks',
        nativeTools: _nativeTools,
        clipboardMessage: '任务清单图片已复制到剪贴板',
        galleryMessage: '任务清单图片已保存到图库',
      );
      if (message != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(shortSnackBar(message));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(shortSnackBar('导出图片失败: $error'));
      }
    }
  }

  List<List<Task>> _taskImagePages(List<Task> tasks) {
    if (tasks.isEmpty) return const [[]];
    final pages = <List<Task>>[];
    var page = <Task>[];
    var weight = 0;
    for (final task in tasks) {
      final nextWeight = task.title.length + 120;
      if (page.isNotEmpty && weight + nextWeight > _exportTodoPageWeight) {
        pages.add(page);
        page = <Task>[];
        weight = 0;
      }
      page.add(task);
      weight += nextWeight;
    }
    if (page.isNotEmpty) pages.add(page);
    return pages;
  }
}

Future<void> _openCanonicalTaskEditor(
  BuildContext context, {
  Task? task,
  LocalDate? initialPlannedDate,
}) async {
  final provider = context.read<TaskProvider>();
  final result = await showModalBottomSheet<_TaskEditorResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _TaskEditorSheet(
      task: task,
      initialListId: task == null
          ? null
          : provider.entryForTask(task.id)?.taskListId,
      initialPlannedDate: initialPlannedDate,
      lists: provider.lists,
    ),
  );
  if (result == null || !context.mounted) return;
  if (result.delete && task != null) {
    await provider.deleteTask(task.id);
    return;
  }
  final calendarBridge = context.read<CalendarPlatformBridge?>();
  late final Task saved;
  if (task == null) {
    final id = await provider.addTask(
      title: result.title,
      note: result.note,
      plannedDate: result.plannedDate,
      plannedTime: result.plannedTime,
      dueDate: result.dueDate,
      dueTime: result.dueTime,
      reminders: result.reminders,
      listId: result.listId,
    );
    if (result.completed) await provider.completeTask(id);
    saved = provider.taskById(id)!;
  } else {
    await provider.updateTask(
      task.copyWith(
        title: result.title,
        note: result.note,
        plannedDate: result.plannedDate,
        plannedTime: result.plannedTime,
        dueDate: result.dueDate,
        dueTime: result.dueTime,
        completedAt: result.completed
            ? task.completedAt ?? DateTime.now()
            : null,
        reminders: result.reminders,
      ),
    );
    await provider.moveTask(task.id, result.listId);
    saved = provider.taskById(task.id)!;
  }
  await ReminderNotificationPermissionService.requestAfterExplicitSave(
    bridge: calendarBridge,
    previousReminderCount: task?.reminders.length ?? 0,
    savedReminderCount: saved.reminders.length,
  );
}

class _TaskEditorResult {
  const _TaskEditorResult({
    required this.title,
    required this.note,
    required this.listId,
    required this.plannedDate,
    required this.plannedTime,
    required this.dueDate,
    required this.dueTime,
    required this.completed,
    required this.reminders,
    this.delete = false,
  });

  final String title;
  final String? note;
  final String? listId;
  final LocalDate? plannedDate;
  final LocalTime? plannedTime;
  final LocalDate? dueDate;
  final LocalTime? dueTime;
  final bool completed;
  final List<ItemReminder> reminders;
  final bool delete;
}

class _TaskEditorSheet extends StatefulWidget {
  const _TaskEditorSheet({
    this.task,
    required this.initialListId,
    this.initialPlannedDate,
    required this.lists,
  });

  final Task? task;
  final String? initialListId;
  final LocalDate? initialPlannedDate;
  final List<TaskList> lists;

  @override
  State<_TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<_TaskEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late String? _listId;
  late LocalDate? _plannedDate;
  late LocalTime? _plannedTime;
  late LocalDate? _dueDate;
  late LocalTime? _dueTime;
  late bool _completed;
  late List<ItemReminder> _reminders;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title ?? '');
    _noteController = TextEditingController(text: task?.note);
    _listId = widget.initialListId;
    _plannedDate = task?.plannedDate ?? widget.initialPlannedDate;
    _plannedTime = task?.plannedTime;
    _dueDate = task?.dueDate;
    _dueTime = task?.dueTime;
    _completed = task?.isCompleted ?? false;
    _reminders = List.of(task?.reminders ?? const []);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.task == null ? '新建任务' : '编辑任务',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: '备注'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _listId,
                decoration: const InputDecoration(labelText: '清单'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('未归入清单')),
                  for (final list in widget.lists)
                    DropdownMenuItem(value: list.id, child: Text(list.title)),
                ],
                onChanged: (value) => setState(() => _listId = value),
              ),
              const SizedBox(height: 8),
              _dateTimeTile(
                label: '计划',
                date: _plannedDate,
                time: _plannedTime,
                onDateChanged: (value) => setState(() {
                  _plannedDate = value;
                  if (value == null) {
                    _plannedTime = null;
                    _reminders.removeWhere(
                      (item) => item.anchor == ItemReminderAnchor.taskPlanned,
                    );
                  }
                }),
                onTimeChanged: (value) => setState(() => _plannedTime = value),
              ),
              _dateTimeTile(
                label: '截止',
                date: _dueDate,
                time: _dueTime,
                onDateChanged: (value) => setState(() {
                  _dueDate = value;
                  if (value == null) {
                    _dueTime = null;
                    _reminders.removeWhere(
                      (item) => item.anchor == ItemReminderAnchor.taskDue,
                    );
                  }
                }),
                onTimeChanged: (value) => setState(() => _dueTime = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('已完成'),
                value: _completed,
                onChanged: (value) => setState(() => _completed = value),
              ),
              _TaskReminderEditor(
                reminders: _reminders,
                plannedDate: _plannedDate,
                plannedTime: _plannedTime,
                dueDate: _dueDate,
                dueTime: _dueTime,
                onChanged: (value) => setState(() => _reminders = value),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (widget.task != null)
                    TextButton.icon(
                      onPressed: () => Navigator.pop(
                        context,
                        _TaskEditorResult(
                          title: '',
                          note: null,
                          listId: null,
                          plannedDate: null,
                          plannedTime: null,
                          dueDate: null,
                          dueTime: null,
                          completed: false,
                          reminders: const [],
                          delete: true,
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('删除'),
                    )
                  else
                    const SizedBox.shrink(),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: _save, child: const Text('保存')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateTimeTile({
    required String label,
    required LocalDate? date,
    required LocalTime? time,
    required ValueChanged<LocalDate?> onDateChanged,
    required ValueChanged<LocalTime?> onTimeChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_outlined),
      title: Text(label),
      subtitle: Text(
        date == null ? '未设置' : '$date${time == null ? '' : ' $time'}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (date != null)
            IconButton(
              tooltip: '设置时间',
              onPressed: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: time == null
                      ? TimeOfDay.now()
                      : TimeOfDay(hour: time.hour, minute: time.minute),
                );
                if (picked != null) {
                  onTimeChanged(LocalTime(picked.hour, picked.minute));
                }
              },
              icon: const Icon(Icons.schedule),
            ),
          if (date != null)
            IconButton(
              tooltip: '清除',
              onPressed: () => onDateChanged(null),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      onTap: () async {
        final initial = date?.atStartOfDay() ?? DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onDateChanged(LocalDate.fromDateTime(picked));
      },
    );
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final reminders = _reminders.map((reminder) {
      final hasTime = reminder.anchor == ItemReminderAnchor.taskPlanned
          ? _plannedTime != null
          : _dueTime != null;
      return hasTime ? reminder.copyWith(dateOnlyTime: null) : reminder;
    }).toList();
    Navigator.pop(
      context,
      _TaskEditorResult(
        title: title,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        listId: _listId,
        plannedDate: _plannedDate,
        plannedTime: _plannedTime,
        dueDate: _dueDate,
        dueTime: _dueTime,
        completed: _completed,
        reminders: reminders,
      ),
    );
  }
}

class _TaskReminderEditor extends StatelessWidget {
  const _TaskReminderEditor({
    required this.reminders,
    required this.plannedDate,
    required this.plannedTime,
    required this.dueDate,
    required this.dueTime,
    required this.onChanged,
  });

  final List<ItemReminder> reminders;
  final LocalDate? plannedDate;
  final LocalTime? plannedTime;
  final LocalDate? dueDate;
  final LocalTime? dueTime;
  final ValueChanged<List<ItemReminder>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('提醒', style: Theme.of(context).textTheme.titleMedium),
            ),
            TextButton.icon(
              onPressed: plannedDate == null && dueDate == null
                  ? null
                  : () => _addReminder(context),
              icon: const Icon(Icons.add_alert_outlined),
              label: const Text('添加'),
            ),
          ],
        ),
        if (plannedDate == null && dueDate == null)
          const Text('设置计划或截止日期后可添加提醒'),
        for (final reminder in reminders)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_outlined),
            title: Text(_reminderLabel(reminder)),
            trailing: IconButton(
              tooltip: '删除提醒',
              onPressed: () => onChanged(
                reminders.where((item) => item.id != reminder.id).toList(),
              ),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
      ],
    );
  }

  Future<void> _addReminder(BuildContext context) async {
    var anchor = plannedDate != null
        ? ItemReminderAnchor.taskPlanned
        : ItemReminderAnchor.taskDue;
    var offset = -15;
    final result = await showDialog<ItemReminder>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('添加提醒'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<ItemReminderAnchor>(
                initialValue: anchor,
                decoration: const InputDecoration(labelText: '基准'),
                items: [
                  if (plannedDate != null)
                    const DropdownMenuItem(
                      value: ItemReminderAnchor.taskPlanned,
                      child: Text('计划时间'),
                    ),
                  if (dueDate != null)
                    const DropdownMenuItem(
                      value: ItemReminderAnchor.taskDue,
                      child: Text('截止时间'),
                    ),
                ],
                onChanged: (value) => setState(() => anchor = value!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: offset,
                decoration: const InputDecoration(labelText: '提前时间'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('准时')),
                  DropdownMenuItem(value: -5, child: Text('提前 5 分钟')),
                  DropdownMenuItem(value: -15, child: Text('提前 15 分钟')),
                  DropdownMenuItem(value: -30, child: Text('提前 30 分钟')),
                  DropdownMenuItem(value: -60, child: Text('提前 1 小时')),
                  DropdownMenuItem(value: -1440, child: Text('提前 1 天')),
                ],
                onChanged: (value) => setState(() => offset = value!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final hasTime = anchor == ItemReminderAnchor.taskPlanned
                    ? plannedTime != null
                    : dueTime != null;
                Navigator.pop(
                  ctx,
                  ItemReminder(
                    id: const Uuid().v4(),
                    anchor: anchor,
                    offsetMinutes: offset,
                    dateOnlyTime: hasTime ? null : LocalTime(9, 0),
                  ),
                );
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    if (result != null) onChanged([...reminders, result]);
  }

  String _reminderLabel(ItemReminder reminder) {
    final anchor = reminder.anchor == ItemReminderAnchor.taskPlanned
        ? '计划'
        : '截止';
    final offset = switch (reminder.offsetMinutes) {
      0 => '准时',
      -1440 => '提前 1 天',
      final value when value < 0 => '提前 ${-value} 分钟',
      final value => '延后 $value 分钟',
    };
    final time = reminder.dateOnlyTime == null
        ? ''
        : '，当天 ${reminder.dateOnlyTime}';
    return '$anchor $offset$time';
  }
}

class _TaskShareImage extends StatelessWidget {
  const _TaskShareImage({
    required this.title,
    required this.tasks,
    required this.totalCount,
    required this.totalCompleted,
    required this.seedColor,
    required this.brightness,
    this.pageNumber,
    this.pageCount,
  });

  final String title;
  final List<Task> tasks;
  final int totalCount;
  final int totalCompleted;
  final Color seedColor;
  final Brightness brightness;
  final int? pageNumber;
  final int? pageCount;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    return Material(
      color: scheme.surface,
      child: Container(
        width: 720,
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '任务清单 · $totalCount 项 · 已完成 $totalCompleted 项',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16),
            ),
            const SizedBox(height: 20),
            if (tasks.isEmpty)
              Text('暂无任务', style: TextStyle(color: scheme.onSurfaceVariant))
            else
              for (final task in tasks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        task.isCompleted
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: task.isCompleted
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          task.title,
                          style: TextStyle(
                            color: task.isCompleted
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface,
                            fontSize: 18,
                            decoration: task.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 18),
            Text(
              pageNumber == null
                  ? 'Exported from LynAI'
                  : 'Exported from LynAI · $pageNumber/$pageCount',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
