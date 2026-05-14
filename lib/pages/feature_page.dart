import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_role.dart';
import '../models/conversation.dart';
import '../models/note.dart';
import '../models/schedule_item.dart';
import '../models/todo_list.dart';
import '../providers/conversation_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/latex_renderer.dart';

String _safeExportFileName(String name, String fallback) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
  return cleaned.isEmpty ? fallback : cleaned;
}

class FeaturePage extends StatefulWidget {
  final void Function(String conversationId) onConversationTap;
  final VoidCallback onRoleChanged;

  const FeaturePage({
    super.key,
    required this.onConversationTap,
    required this.onRoleChanged,
  });

  @override
  State<FeaturePage> createState() => _FeaturePageState();
}

class _FeaturePageState extends State<FeaturePage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedNoteId;
  bool _noteEditing = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final feature = settings.lastFeature;
    return Scaffold(
      appBar: AppBar(
        leading: _selectedNoteId == null
            ? _featureSwitcher(feature)
            : IconButton(
                tooltip: '笔记列表',
                icon: const Icon(Icons.menu),
                onPressed: () => setState(() => _selectedNoteId = null),
              ),
        title: Text(_title(feature)),
        actions: _actions(feature),
      ),
      floatingActionButton: _floatingActionButton(feature),
      body: switch (feature) {
        'schedule' => const _SchedulePage(),
        'notes' => _NotesPage(
          selectedNoteId: _selectedNoteId,
          editing: _noteEditing,
          onSelect: (id) => setState(() {
            _selectedNoteId = id;
            _noteEditing = false;
          }),
          onEditingChanged: (v) => setState(() => _noteEditing = v),
          onBack: () => setState(() => _selectedNoteId = null),
          searchController: _searchController,
          searchQuery: _searchQuery,
          onSearchChanged: (v) => setState(() => _searchQuery = v),
          onNewNote: _newNote,
          onNewFolder: _newNoteFolder,
        ),
        'todos' => _TodoListsPage(
          searchController: _searchController,
          searchQuery: _searchQuery,
          onSearchChanged: (v) => setState(() => _searchQuery = v),
        ),
        _ => _HistoryList(
          searchController: _searchController,
          searchQuery: _searchQuery,
          onSearchChanged: (v) => setState(() => _searchQuery = v),
          onConversationTap: widget.onConversationTap,
          onRoleChanged: widget.onRoleChanged,
        ),
      },
    );
  }

  String _title(String feature) {
    if (_selectedNoteId != null) return '笔记';
    return switch (feature) {
      'schedule' => '日程表',
      'notes' => '笔记',
      'todos' => '待办清单',
      _ => '功能页',
    };
  }

  Widget _featureSwitcher(String feature) {
    return PopupMenuButton<String>(
      tooltip: '切换功能',
      initialValue: feature,
      onSelected: _selectFeature,
      itemBuilder: (_) => _featureItems(feature),
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: _FeatureIcon(feature: feature),
      ),
    );
  }

  List<PopupMenuEntry<String>> _featureItems(String feature) {
    return [
      _featureMenuItem(
        value: 'history',
        selected: feature == 'history',
        icon: Icons.history,
        title: '对话历史',
        subtitle: '按角色查看与搜索历史对话',
      ),
      _featureMenuItem(
        value: 'schedule',
        selected: feature == 'schedule',
        icon: Icons.calendar_month,
        title: '日程表',
        subtitle: '月历、周视图与全年日程总览',
      ),
      _featureMenuItem(
        value: 'notes',
        selected: feature == 'notes',
        icon: Icons.sticky_note_2_outlined,
        title: '笔记',
        subtitle: 'Markdown/LaTeX 记录与导出',
      ),
      _featureMenuItem(
        value: 'todos',
        selected: feature == 'todos',
        icon: Icons.checklist,
        title: '待办清单',
        subtitle: '任务勾选、导入、导出与图片分享',
      ),
    ];
  }

  PopupMenuItem<String> _featureMenuItem({
    required String value,
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return PopupMenuItem(
      value: value,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: selected ? const Icon(Icons.check, size: 18) : null,
      ),
    );
  }

  void _selectFeature(String value) {
    setState(() {
      _selectedNoteId = null;
      _noteEditing = false;
      _searchQuery = '';
      _searchController.clear();
    });
    context.read<SettingsProvider>().setLastFeature(value);
  }

  List<Widget> _actions(String feature) {
    if (feature == 'notes' && _selectedNoteId == null) {
      return [
        PopupMenuButton<String>(
          tooltip: '新建',
          icon: const Icon(Icons.add),
          onSelected: (value) {
            if (value == 'note') _newNote();
            if (value == 'folder') _newNoteFolder();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'note', child: Text('创建笔记')),
            PopupMenuItem(value: 'folder', child: Text('创建文件夹')),
          ],
        ),
        IconButton(
          tooltip: '导入 Markdown',
          icon: const Icon(Icons.upload_file),
          onPressed: _importMarkdown,
        ),
      ];
    }
    if (feature == 'todos') {
      return [
        IconButton(
          tooltip: '新建待办清单',
          icon: const Icon(Icons.add),
          onPressed: _newTodoList,
        ),
        IconButton(
          tooltip: '导入待办清单',
          icon: const Icon(Icons.upload_file),
          onPressed: _importTodoList,
        ),
      ];
    }
    return const [];
  }

  Widget? _floatingActionButton(String feature) {
    if (feature == 'notes' && _selectedNoteId == null) {
      return _AddMenuButton(
        items: const [
          _AddMenuItem('note', Icons.sticky_note_2_outlined, '创建笔记'),
          _AddMenuItem('folder', Icons.create_new_folder_outlined, '创建文件夹'),
        ],
        onSelected: (value) {
          if (value == 'note') _newNote();
          if (value == 'folder') _newNoteFolder();
        },
      );
    }
    if (feature == 'todos') {
      return _AddMenuButton(
        items: const [_AddMenuItem('todo', Icons.checklist, '新建待办清单')],
        onSelected: (_) => _newTodoList(),
      );
    }
    return null;
  }

  Future<void> _newNote({String? folderId}) async {
    final ctrl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建笔记'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '标题'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (!mounted || title == null || title.isEmpty) return;
    final id = await context.read<FeatureProvider>().addNote(
      title,
      folderId: folderId,
    );
    setState(() {
      _selectedNoteId = id;
      _noteEditing = true;
    });
  }

  Future<void> _newNoteFolder() async {
    final ctrl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (!mounted || title == null || title.isEmpty) return;
    await context.read<FeatureProvider>().addNoteFolder(title);
    _clearSearch();
  }

  Future<void> _importMarkdown() async {
    final features = context.read<FeatureProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'markdown', 'txt'],
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw Exception('无法读取文件内容');
      final content = utf8.decode(bytes, allowMalformed: true);
      final title = _noteTitleFromFileName(file.name);
      final id = await features.addNoteWithContent(title, content);
      setState(() {
        _selectedNoteId = id;
        _noteEditing = false;
      });
      messenger.showSnackBar(SnackBar(content: Text('已导入 $title')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  String _noteTitleFromFileName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'\.(md|markdown|txt)$', caseSensitive: false), '')
        .trim();
    return cleaned.isEmpty ? '导入笔记' : cleaned;
  }

  Future<void> _newTodoList() async {
    final ctrl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建待办清单'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '标题'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (!mounted || title == null || title.isEmpty) return;
    await context.read<FeatureProvider>().addTodoList(title);
    _clearSearch();
  }

  Future<void> _importTodoList() async {
    final features = context.read<FeatureProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'markdown', 'txt'],
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw Exception('无法读取文件内容');
      final content = utf8.decode(bytes, allowMalformed: true);
      final title = _todoTitleFromFileName(file.name);
      await features.addTodoListWithItems(title, _parseTodoItems(content));
      _clearSearch();
      messenger.showSnackBar(SnackBar(content: Text('已导入 $title')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  String _todoTitleFromFileName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'\.(md|markdown|txt)$', caseSensitive: false), '')
        .trim();
    return cleaned.isEmpty ? '导入待办清单' : cleaned;
  }

  List<TodoItem> _parseTodoItems(String content) {
    const uuid = Uuid();
    return content
        .split(RegExp(r'\r?\n'))
        .map((line) {
          final text = line.trim();
          if (text.isEmpty || text.startsWith('#')) return null;
          final match = RegExp(
            r'^[-*+]\s+\[([ xX])\]\s+(.*)$',
          ).firstMatch(text);
          if (match != null) {
            return TodoItem(
              id: uuid.v4(),
              text: match.group(2)!.trim(),
              done: match.group(1)!.toLowerCase() == 'x',
            );
          }
          final plain = text.replaceFirst(RegExp(r'^[-*+]\s+'), '').trim();
          return plain.isEmpty ? null : TodoItem(id: uuid.v4(), text: plain);
        })
        .whereType<TodoItem>()
        .toList();
  }

  void _clearSearch() {
    if (_searchQuery.isEmpty) return;
    setState(() {
      _searchQuery = '';
      _searchController.clear();
    });
  }
}

class _FeatureIcon extends StatelessWidget {
  final String feature;

  const _FeatureIcon({required this.feature});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (feature) {
      'schedule' => Icons.calendar_month,
      'notes' => Icons.sticky_note_2_outlined,
      'todos' => Icons.checklist,
      _ => Icons.widgets_outlined,
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
      ),
      child: Icon(icon, color: scheme.primary),
    );
  }
}

class _AddMenuItem {
  final String value;
  final IconData icon;
  final String label;

  const _AddMenuItem(this.value, this.icon, this.label);
}

class _AddMenuButton extends StatelessWidget {
  final List<_AddMenuItem> items;
  final ValueChanged<String> onSelected;

  const _AddMenuButton({required this.items, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: null,
      tooltip: '新建',
      onPressed: () => _showMenu(context),
      child: const Icon(Icons.add),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero, ancestor: overlay);
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy,
        overlay.size.width - offset.dx - box.size.width,
        overlay.size.height - offset.dy - box.size.height,
      ),
      items: items
          .map(
            (item) => PopupMenuItem(
              value: item.value,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(item.icon),
                title: Text(item.label),
              ),
            ),
          )
          .toList(),
    );
    if (value != null) onSelected(value);
  }
}

class _HistoryList extends StatelessWidget {
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final void Function(String conversationId) onConversationTap;
  final VoidCallback onRoleChanged;

  const _HistoryList({
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onConversationTap,
    required this.onRoleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cp = context.watch<ConversationProvider>();
    final sp = context.watch<SettingsProvider>();
    final roles = sp.settings.roles;
    final currentRoleId = sp.settings.currentRoleId;
    final current = roles.firstWhere(
      (r) => r.id == currentRoleId,
      orElse: ChatRole.defaultRole,
    );
    final results = cp.searchConversations(searchQuery);
    final currentResults = results
        .where(
          (r) => (r['conversation'] as Conversation).roleId == currentRoleId,
        )
        .toList();
    final otherResults = results
        .where(
          (r) => (r['conversation'] as Conversation).roleId != currentRoleId,
        )
        .toList();
    final otherRoleIds = otherResults
        .map((r) => (r['conversation'] as Conversation).roleId)
        .toSet()
        .toList();
    final hasAnyConversation = cp.conversations.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(
            children: [
              Expanded(child: _searchBox(context)),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: '切换角色',
                initialValue: currentRoleId,
                onSelected: (id) {
                  sp.selectRole(id);
                  onRoleChanged();
                },
                itemBuilder: (_) => roles
                    .map((r) => PopupMenuItem(value: r.id, child: Text(r.name)))
                    .toList(),
                child: Chip(label: Text(current.name)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              if (!hasAnyConversation && searchQuery.isEmpty)
                _historyEmptyState(context, current.name),
              _sectionTitle(context, current.name, current.themeColor),
              if (currentResults.isEmpty) _emptyTile(searchQuery),
              for (final r in currentResults)
                _conversationItem(context, r, cp, current.themeColor),
              for (final roleId in otherRoleIds) ...[
                Builder(
                  builder: (context) {
                    final role = roles.firstWhere(
                      (r) => r.id == roleId,
                      orElse: () =>
                          ChatRole.defaultRole().copyWith(name: roleId),
                    );
                    final list = otherResults
                        .where(
                          (r) =>
                              (r['conversation'] as Conversation).roleId ==
                              roleId,
                        )
                        .toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () {
                            sp.selectRole(role.id);
                            onRoleChanged();
                          },
                          child: _sectionTitle(
                            context,
                            role.name,
                            role.themeColor,
                          ),
                        ),
                        for (final result in list)
                          _conversationItem(
                            context,
                            result,
                            cp,
                            role.themeColor,
                          ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _historyEmptyState(BuildContext context, String roleName) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_awesome, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '开始使用 $roleName',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '在底部切到“对话”发送第一条消息，这里会自动沉淀历史记录。',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBox(BuildContext context) {
    return TextField(
      controller: searchController,
      decoration: InputDecoration(
        hintText: '搜索对话标题或内容...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  searchController.clear();
                  onSearchChanged('');
                },
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onChanged: onSearchChanged,
    );
  }

  Widget _sectionTitle(BuildContext context, String title, Color? color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: color ?? Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _emptyTile(String query) {
    return ListTile(
      leading: const Icon(Icons.chat_bubble_outline),
      title: Text(query.isEmpty ? '当前角色暂无对话' : '未找到匹配的对话'),
      subtitle: query.isEmpty ? const Text('切换到对话页后开始聊天') : null,
    );
  }

  Widget _conversationItem(
    BuildContext context,
    Map<String, dynamic> result,
    ConversationProvider provider,
    Color? roleColor,
  ) {
    final conversation = result['conversation'] as Conversation;
    final matchInTitle = result['matchInTitle'] as bool? ?? false;
    final matchContent = result['matchContent'] as String? ?? '';
    final color = roleColor ?? Theme.of(context).colorScheme.primary;
    return Card(
      color: roleColor == null ? null : color.withValues(alpha: 0.06),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          child: Icon(Icons.chat, color: color),
        ),
        title: searchQuery.isNotEmpty && matchInTitle
            ? _highlight(
                context,
                conversation.title,
                Theme.of(context).textTheme.titleMedium,
              )
            : Text(
                conversation.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        subtitle: searchQuery.isNotEmpty && !matchInTitle
            ? _highlight(
                context,
                matchContent.isNotEmpty ? matchContent : conversation.preview,
                Theme.of(context).textTheme.bodySmall,
              )
            : Text(
                conversation.preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_formatDate(conversation.updatedAt)),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _deleteDialog(context, provider, conversation),
            ),
          ],
        ),
        onTap: () {
          context.read<SettingsProvider>().selectRole(conversation.roleId);
          onConversationTap(conversation.id);
        },
        onLongPress: () => _deleteDialog(context, provider, conversation),
      ),
    );
  }

  Widget _highlight(BuildContext context, String text, TextStyle? style) {
    if (searchQuery.isEmpty) return Text(text, style: style);
    final lowerText = text.toLowerCase();
    final lowerQuery = searchQuery.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + searchQuery.length),
          style: const TextStyle(
            backgroundColor: Colors.yellow,
            color: Colors.black,
          ),
        ),
      );
      start = index + searchQuery.length;
    }
    return RichText(
      text: TextSpan(
        style: style ?? DefaultTextStyle.of(context).style,
        children: spans,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${date.month}/${date.day}';
  }

  void _deleteDialog(
    BuildContext context,
    ConversationProvider provider,
    Conversation c,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除对话'),
        content: Text('确定要删除"${c.title}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              provider.deleteConversation(c.id);
              Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

enum _CalendarMode { month, day, year }

class _SchedulePage extends StatefulWidget {
  const _SchedulePage();

  @override
  State<_SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<_SchedulePage> {
  static const _baseHourRowHeight = 56.0;
  static const _dayInitialHour = 8;
  static const _dayBaseColumnWidth = 72.0;
  static const _timeColumnWidth = 56.0;
  static const _dayHeaderHeight = 46.0;
  static const _minDayZoom = 0.7;
  static const _maxDayZoom = 1.8;

  final _dayScrollController = ScrollController(
    initialScrollOffset: _dayInitialHour * _baseHourRowHeight,
  );
  final _dayHorizontalController = ScrollController(
    initialScrollOffset: 14 * _dayBaseColumnWidth,
  );
  final _dayHeaderHorizontalController = ScrollController(
    initialScrollOffset: 14 * _dayBaseColumnWidth,
  );
  bool _syncingDayHorizontalScroll = false;
  double _dayZoom = 1.0;
  double _dayScaleStartZoom = 1.0;
  double? _dayScaleStartDistance;
  final Map<int, Offset> _dayPointerPositions = {};

  _CalendarMode _mode = _CalendarMode.month;
  DateTime _focus = DateTime.now();
  DateTime? _selectedDate;
  bool _showMonthDetail = false;
  double _scheduleControlsCollapse = 0;

  @override
  void initState() {
    super.initState();
    _dayHorizontalController.addListener(() {
      _syncDayHorizontalScroll(
        _dayHorizontalController,
        _dayHeaderHorizontalController,
      );
    });
    _dayHeaderHorizontalController.addListener(() {
      _syncDayHorizontalScroll(
        _dayHeaderHorizontalController,
        _dayHorizontalController,
      );
    });
  }

  @override
  void dispose() {
    _dayScrollController.dispose();
    _dayHorizontalController.dispose();
    _dayHeaderHorizontalController.dispose();
    super.dispose();
  }

  void _syncDayHorizontalScroll(
    ScrollController source,
    ScrollController target,
  ) {
    if (_syncingDayHorizontalScroll ||
        !source.hasClients ||
        !target.hasClients) {
      return;
    }
    _syncingDayHorizontalScroll = true;
    final targetPosition = target.position;
    final offset = source.offset.clamp(
      targetPosition.minScrollExtent,
      targetPosition.maxScrollExtent,
    );
    target.jumpTo(offset.toDouble());
    _syncingDayHorizontalScroll = false;
  }

  void _setDayZoom(double value) {
    final next = value.clamp(_minDayZoom, _maxDayZoom).toDouble();
    if ((next - _dayZoom).abs() < 0.01) return;
    setState(() => _dayZoom = next);
  }

  void _handleDayPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      if (event is! PointerScrollEvent) return;
      final delta = event.scrollDelta.dy < 0 ? 0.08 : -0.08;
      _setDayZoom(_dayZoom + delta);
    });
  }

  void _handleDayPointerDown(PointerDownEvent event) {
    _dayPointerPositions[event.pointer] = event.localPosition;
    if (_dayPointerPositions.length == 2) {
      _dayScaleStartZoom = _dayZoom;
      _dayScaleStartDistance = _dayPointerDistance();
    }
  }

  void _handleDayPointerMove(PointerMoveEvent event) {
    if (!_dayPointerPositions.containsKey(event.pointer)) return;
    _dayPointerPositions[event.pointer] = event.localPosition;
    final startDistance = _dayScaleStartDistance;
    final currentDistance = _dayPointerDistance();
    if (_dayPointerPositions.length < 2 ||
        startDistance == null ||
        startDistance <= 0 ||
        currentDistance == null) {
      return;
    }
    _setDayZoom(_dayScaleStartZoom * currentDistance / startDistance);
  }

  void _handleDayPointerEnd(PointerEvent event) {
    _dayPointerPositions.remove(event.pointer);
    if (_dayPointerPositions.length < 2) {
      _dayScaleStartDistance = null;
      _dayScaleStartZoom = _dayZoom;
    } else {
      _dayScaleStartDistance = _dayPointerDistance();
      _dayScaleStartZoom = _dayZoom;
    }
  }

  double? _dayPointerDistance() {
    if (_dayPointerPositions.length < 2) return null;
    final values = _dayPointerPositions.values.take(2).toList();
    return (values[0] - values[1]).distance;
  }

  bool _onScheduleScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta;
      if (delta == null || delta == 0) return false;
      final next = (_scheduleControlsCollapse + delta / 72).clamp(0.0, 1.0);
      if ((next - _scheduleControlsCollapse).abs() >= 0.01) {
        setState(() => _scheduleControlsCollapse = next);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final fp = context.watch<FeatureProvider>();
    return Column(
      children: [
        _scheduleHeader(context),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScheduleScroll,
            child: switch (_mode) {
              _CalendarMode.day => _dayView(fp.schedules),
              _CalendarMode.year => _yearView(fp.schedules),
              _ => _monthView(fp.schedules),
            },
          ),
        ),
      ],
    );
  }

  Widget _scheduleHeader(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 560;
    final progress = _scheduleControlsCollapse;
    final controls = ClipRect(
      child: Align(
        alignment: Alignment.centerRight,
        widthFactor: compact ? 1 : 1 - progress,
        heightFactor: compact ? 1 - progress : 1,
        child: Opacity(
          opacity: 1 - progress,
          child: Transform.translate(
            offset: Offset(0, -12 * progress),
            child: IgnorePointer(
              ignoring: progress > 0.6,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<_CalendarMode>(
                    segments: const [
                      ButtonSegment(
                        value: _CalendarMode.month,
                        label: Text('月'),
                      ),
                      ButtonSegment(value: _CalendarMode.day, label: Text('日')),
                      ButtonSegment(
                        value: _CalendarMode.year,
                        label: Text('年'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (v) => setState(() => _mode = v.first),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _newSchedule,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新建'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: compact
          ? Column(
              children: [
                _dateNavigator(context),
                SizedBox(height: 10 * (1 - progress)),
                Align(alignment: Alignment.centerRight, child: controls),
              ],
            )
          : Row(
              children: [
                Expanded(child: _dateNavigator(context)),
                controls,
              ],
            ),
    );
  }

  Widget _dateNavigator(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _move(-1),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _focusLabel(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _modeLabel(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton.filledTonal(
          icon: const Icon(Icons.chevron_right),
          onPressed: () => _move(1),
        ),
      ],
    );
  }

  void _move(int delta) {
    setState(() {
      _focus = switch (_mode) {
        _CalendarMode.day => _focus.add(Duration(days: delta)),
        _CalendarMode.year => DateTime(_focus.year + delta, 1, 1),
        _ => DateTime(_focus.year, _focus.month + delta, 1),
      };
      if (_mode == _CalendarMode.month) {
        final daysInMonth = DateTime(_focus.year, _focus.month + 1, 0).day;
        final selectedDay = _selectedDate?.day ?? _focus.day;
        final clampedDay = selectedDay.clamp(1, daysInMonth);
        _selectedDate = _showMonthDetail
            ? DateTime(_focus.year, _focus.month, clampedDay)
            : null;
      } else if (_mode == _CalendarMode.year) {
        _selectedDate = null;
        _showMonthDetail = false;
      }
    });
  }

  String _focusLabel() {
    return switch (_mode) {
      _CalendarMode.day => '${_focus.year}-${_focus.month}-${_focus.day}',
      _CalendarMode.year => '${_focus.year}',
      _ => '${_focus.year}-${_focus.month}',
    };
  }

  String _modeLabel() {
    return switch (_mode) {
      _CalendarMode.day => '周日程时间轴',
      _CalendarMode.year => '全年总览',
      _ => '月历总览',
    };
  }

  Widget _monthView(List<ScheduleItem> items) {
    final first = DateTime(_focus.year, _focus.month, 1);
    final days = DateTime(_focus.year, _focus.month + 1, 0).day;
    final offset = first.weekday - 1;
    final total = ((offset + days + 6) ~/ 7) * 7;
    final selectedDate = _selectedDate;
    final selectedItems = selectedDate == null
        ? <ScheduleItem>[]
        : _itemsOnDate(items, selectedDate);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              Text(
                '${_focus.year} 年 ${_focus.month} 月',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() {
                  final now = DateTime.now();
                  _focus = DateTime(now.year, now.month, 1);
                  _selectedDate = _dateOnly(now);
                  _showMonthDetail = true;
                }),
                icon: const Icon(Icons.today, size: 18),
                label: const Text('今天'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(
            children: const ['一', '二', '三', '四', '五', '六', '日']
                .map(
                  (e) => Expanded(
                    child: Center(
                      child: Text(
                        e,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        SizedBox(
          height: _showMonthDetail ? 244 : 0,
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
            ),
            itemCount: total,
            itemBuilder: (context, index) {
              if (index < offset || index >= offset + days) {
                return const SizedBox.shrink();
              }
              final day = index - offset + 1;
              final date = DateTime(_focus.year, _focus.month, day);
              final dayItems = _itemsOnDate(items, date);
              final today = _sameDate(date, DateTime.now());
              final selected =
                  selectedDate != null && _sameDate(date, selectedDate);
              return _monthDayCell(context, date, dayItems, today, selected);
            },
          ),
        ),
        if (!_showMonthDetail)
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
              ),
              itemCount: total,
              itemBuilder: (context, index) {
                if (index < offset || index >= offset + days) {
                  return const SizedBox.shrink();
                }
                final day = index - offset + 1;
                final date = DateTime(_focus.year, _focus.month, day);
                final dayItems = _itemsOnDate(items, date);
                final today = _sameDate(date, DateTime.now());
                final selected =
                    selectedDate != null && _sameDate(date, selectedDate);
                return _monthDayCell(context, date, dayItems, today, selected);
              },
            ),
          ),
        if (_showMonthDetail && selectedDate != null) ...[
          const SizedBox(height: 4),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${selectedDate.day}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${selectedDate.year}-${selectedDate.month}-${selectedDate.day}',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_weekdayName(selectedDate.weekday)} | ${selectedItems.length} 条日程',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭日程摘要',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _selectedDate = null;
                          _showMonthDetail = false;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (selectedItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '这一天没有日程',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    ...selectedItems.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () => _openScheduleEditor(item),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.16),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _timeRangeForDate(item, selectedDate),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                                if ((item.note ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    item.note!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _monthDayCell(
    BuildContext context,
    DateTime date,
    List<ScheduleItem> dayItems,
    bool today,
    bool selected,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.9)
          : today
          ? scheme.primaryContainer.withValues(alpha: 0.55)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.9)
                : today
                ? scheme.primary.withValues(alpha: 0.55)
                : scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: InkWell(
          onTap: () => setState(() {
            _selectedDate = _dateOnly(date);
            _showMonthDetail = true;
          }),
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primary
                            : today
                            ? scheme.primary.withValues(alpha: 0.85)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: selected || today ? scheme.onPrimary : null,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (dayItems.isNotEmpty)
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
              if (dayItems.isNotEmpty)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Text(
                    '${dayItems.length}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayView(List<ScheduleItem> items) {
    final startDate = _focus.subtract(const Duration(days: 14));
    final days = List.generate(42, (i) => startDate.add(Duration(days: i)));
    final scheme = Theme.of(context).colorScheme;
    final hourRowHeight = _baseHourRowHeight * _dayZoom;
    final dayColumnWidth = _dayBaseColumnWidth * _dayZoom;
    final timelineHeight = 24 * hourRowHeight;
    final timelineWidth = days.length * dayColumnWidth;
    final now = DateTime.now();
    final showNow = days.any((date) => _sameDate(date, now));

    return Listener(
      onPointerSignal: _handleDayPointerSignal,
      onPointerDown: _handleDayPointerDown,
      onPointerMove: _handleDayPointerMove,
      onPointerUp: _handleDayPointerEnd,
      onPointerCancel: _handleDayPointerEnd,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SizedBox(
                height: _dayHeaderHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: _timeColumnWidth,
                      child: Center(
                        child: Text(
                          '${(_dayZoom * 100).round()}%',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _dayHeaderHorizontalController,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: days
                              .map(
                                (date) => _dayHeaderCell(
                                  date,
                                  scheme,
                                  width: dayColumnWidth,
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _dayScrollController,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: _timeColumnWidth,
                        height: timelineHeight,
                        child: Stack(
                          children: [
                            for (var h = 0; h < 24; h++)
                              Positioned(
                                top: h * hourRowHeight,
                                left: 0,
                                right: 0,
                                child: SizedBox(
                                  height: hourRowHeight,
                                  child: Align(
                                    alignment: Alignment.topCenter,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        '${h.toString().padLeft(2, '0')}:00',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (showNow)
                              _nowTimeLabel(
                                now,
                                scheme,
                                hourRowHeight: hourRowHeight,
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _dayHorizontalController,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: timelineWidth,
                            height: timelineHeight,
                            child: Stack(
                              children: [
                                for (var h = 0; h < 24; h++)
                                  Positioned(
                                    top: h * hourRowHeight,
                                    left: 0,
                                    right: 0,
                                    child: Divider(
                                      height: 1,
                                      color: scheme.outlineVariant.withValues(
                                        alpha: 0.45,
                                      ),
                                    ),
                                  ),
                                for (var i = 0; i < days.length; i++)
                                  Positioned(
                                    left: i * dayColumnWidth,
                                    top: 0,
                                    width: dayColumnWidth,
                                    height: timelineHeight,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          left: BorderSide(
                                            color: scheme.outlineVariant
                                                .withValues(alpha: 0.35),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                for (var i = 0; i < days.length; i++)
                                  ..._itemsOnDate(items, days[i]).map(
                                    (item) => _dayScheduleBlock(
                                      item,
                                      days[i],
                                      scheme,
                                      hourRowHeight: hourRowHeight,
                                      left: i * dayColumnWidth + 2,
                                      width: dayColumnWidth - 4,
                                    ),
                                  ),
                                for (var i = 0; i < days.length; i++)
                                  if (_sameDate(days[i], now))
                                    _nowLine(
                                      now,
                                      scheme,
                                      left: i * dayColumnWidth,
                                      width: dayColumnWidth,
                                      hourRowHeight: hourRowHeight,
                                    ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayHeaderCell(
    DateTime date,
    ColorScheme scheme, {
    required double width,
  }) {
    final today = _sameDate(date, DateTime.now());
    final focused = _sameDate(date, _focus);
    return InkWell(
      onTap: () => setState(() => _focus = _dateOnly(date)),
      child: Container(
        width: width,
        height: _dayHeaderHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: focused ? scheme.primary.withValues(alpha: 0.08) : null,
          border: Border(
            left: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _weekdayName(date.weekday),
              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
            ),
            Text(
              '${date.month}/${date.day}',
              style: TextStyle(
                fontWeight: today ? FontWeight.w800 : FontWeight.w600,
                color: today ? scheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nowTimeLabel(
    DateTime now,
    ColorScheme scheme, {
    required double hourRowHeight,
  }) {
    final top = now.hour * hourRowHeight + now.minute / 60 * hourRowHeight;
    return Positioned(
      top: (top - 8).clamp(0, 24 * hourRowHeight - 16).toDouble(),
      left: 0,
      right: 4,
      height: 16,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '现在',
              style: TextStyle(
                fontSize: 9.5,
                height: 1.1,
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _nowLine(
    DateTime now,
    ColorScheme scheme, {
    required double left,
    required double width,
    required double hourRowHeight,
  }) {
    final top = now.hour * hourRowHeight + now.minute / 60 * hourRowHeight;
    return Positioned(
      top: top,
      left: left,
      width: width,
      child: IgnorePointer(
        child: Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: scheme.error,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Container(
                height: 1.6,
                color: scheme.error.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayScheduleBlock(
    ScheduleItem item,
    DateTime date,
    ColorScheme scheme, {
    required double hourRowHeight,
    double? left,
    double? width,
  }) {
    final visibleStart = _visibleStartForDate(item, date);
    final visibleEnd = _visibleEndForDate(item, date);
    final top =
        visibleStart.hour * hourRowHeight +
        visibleStart.minute / 60 * hourRowHeight;
    final height =
        (visibleEnd.difference(visibleStart).inMinutes / 60 * hourRowHeight)
            .clamp(26, 24 * hourRowHeight)
            .toDouble();
    final maxLines = ((height - 8) / 13.5).floor().clamp(1, 20);

    return Positioned(
      top: top,
      left: left ?? 2,
      right: width == null ? 2 : null,
      width: width,
      height: height,
      child: InkWell(
        onTap: () => _openScheduleEditor(item),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
          ),
          child: Text(
            '${_timeRangeForDate(item, date)}  ${item.title}',
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, height: 1.25),
          ),
        ),
      ),
    );
  }

  Widget _yearView(List<ScheduleItem> items) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: 12,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final month = i + 1;
        final monthStart = DateTime(_focus.year, month, 1);
        final monthEnd = DateTime(_focus.year, month + 1, 1);
        final monthItems = items
            .where(
              (e) => e.start.isBefore(monthEnd) && e.end.isAfter(monthStart),
            )
            .toList();
        final count = monthItems.length;
        return Material(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() {
              _focus = DateTime(_focus.year, month, 1);
              _selectedDate = null;
              _mode = _CalendarMode.month;
            }),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            '$month',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$month 月',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              count == 0 ? '这个月没有日程' : '共 $count 条日程',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  if (monthItems.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final chipWidth = (constraints.maxWidth - 6) / 2;
                        return Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: monthItems.take(6).map((item) {
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _focus = DateTime(
                                    _focus.year,
                                    month,
                                    _visibleStartForDate(item, monthStart).day,
                                  );
                                  _selectedDate = DateTime(
                                    _focus.year,
                                    month,
                                    _visibleStartForDate(item, monthStart).day,
                                  );
                                  _mode = _CalendarMode.month;
                                });
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: SizedBox(
                                width: chipWidth.clamp(128.0, 260.0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Text(
                                    '${_visibleStartForDate(item, monthStart).month}/${_visibleStartForDate(item, monthStart).day} ${item.title}',
                                    style: const TextStyle(fontSize: 11),
                                    maxLines: 2,
                                    softWrap: true,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<ScheduleItem> _itemsOnDate(List<ScheduleItem> items, DateTime date) {
    final dayStart = _dateOnly(date);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return items
        .where((e) => e.start.isBefore(dayEnd) && e.end.isAfter(dayStart))
        .toList();
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _weekdayName(int weekday) =>
      const ['一', '二', '三', '四', '五', '六', '日'][weekday - 1];

  String _time(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  String _timeRangeForDate(ScheduleItem item, DateTime date) {
    final visibleStart = _visibleStartForDate(item, date);
    final visibleEnd = _visibleEndForDate(item, date);
    return '${_time(visibleStart)} - ${_time(visibleEnd)}';
  }

  DateTime _visibleStartForDate(ScheduleItem item, DateTime date) {
    final dayStart = _dateOnly(date);
    return item.start.isAfter(dayStart) ? item.start : dayStart;
  }

  DateTime _visibleEndForDate(ScheduleItem item, DateTime date) {
    final dayEnd = _dateOnly(date).add(const Duration(days: 1));
    return item.end.isBefore(dayEnd) ? item.end : dayEnd;
  }

  Future<void> _newSchedule() async {
    final titleCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final baseDate = _mode == _CalendarMode.month
        ? _selectedDate ?? _dateOnly(_focus)
        : _focus;
    var start = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      DateTime.now().hour,
    );
    var end = start.add(const Duration(hours: 1));
    DateTime selectedDate = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
    );
    TimeOfDay startTime = TimeOfDay.fromDateTime(start);
    TimeOfDay endTime = TimeOfDay.fromDateTime(end);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          return AlertDialog(
            title: const Text('新建日程'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: '标题',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '备注（可选）',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('日期'),
                    subtitle: Text(
                      '${selectedDate.year}-${selectedDate.month}-${selectedDate.day}',
                    ),
                    trailing: const Icon(Icons.date_range),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: selectedDate,
                      );
                      if (date != null) {
                        setDialog(() {
                          selectedDate = date;
                          start = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            startTime.hour,
                            startTime.minute,
                          );
                          end = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            endTime.hour,
                            endTime.minute,
                          );
                        });
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('开始时间'),
                    subtitle: Text(_time(start)),
                    trailing: const Icon(Icons.schedule),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: ctx,
                        initialTime: startTime,
                      );
                      if (time != null) {
                        setDialog(() {
                          startTime = time;
                          start = DateTime(
                            selectedDate.year,
                            selectedDate.month,
                            selectedDate.day,
                            time.hour,
                            time.minute,
                          );
                          if (!end.isAfter(start)) {
                            end = start.add(const Duration(hours: 1));
                            endTime = TimeOfDay.fromDateTime(end);
                          }
                        });
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('结束时间'),
                    subtitle: Text(_time(end)),
                    trailing: const Icon(Icons.schedule_outlined),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: ctx,
                        initialTime: endTime,
                      );
                      if (time != null) {
                        setDialog(() {
                          endTime = time;
                          end = DateTime(
                            selectedDate.year,
                            selectedDate.month,
                            selectedDate.day,
                            time.hour,
                            time.minute,
                          );
                          if (!end.isAfter(start)) {
                            end = start.add(const Duration(hours: 1));
                            endTime = TimeOfDay.fromDateTime(end);
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '时长：${(end.difference(start).inMinutes / 60).toStringAsFixed(1)} 小时',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    final title = titleCtrl.text.trim();
    final note = noteCtrl.text.trim();
    titleCtrl.dispose();
    noteCtrl.dispose();
    if (!mounted || result != true || title.isEmpty) return;
    await context.read<FeatureProvider>().addSchedule(
      title,
      start,
      end,
      note: note.isEmpty ? null : note,
    );
  }

  Future<void> _openScheduleEditor(ScheduleItem schedule) async {
    final fp = context.read<FeatureProvider>();
    final titleCtrl = TextEditingController(text: schedule.title);
    final noteCtrl = TextEditingController(text: schedule.note ?? '');
    var start = schedule.start;
    var end = schedule.end;
    DateTime selectedDate = DateTime(
      schedule.start.year,
      schedule.start.month,
      schedule.start.day,
    );
    TimeOfDay startTime = TimeOfDay.fromDateTime(start);
    TimeOfDay endTime = TimeOfDay.fromDateTime(end);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: '标题',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '备注（可选）',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('日期'),
                    subtitle: Text(
                      '${selectedDate.year}-${selectedDate.month}-${selectedDate.day}',
                    ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: selectedDate,
                      );
                      if (date != null) {
                        setDialog(() {
                          selectedDate = date;
                          start = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            startTime.hour,
                            startTime.minute,
                          );
                          end = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            endTime.hour,
                            endTime.minute,
                          );
                        });
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('开始时间'),
                    subtitle: Text(_time(start)),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: ctx,
                        initialTime: startTime,
                      );
                      if (time != null) {
                        setDialog(() {
                          startTime = time;
                          start = DateTime(
                            selectedDate.year,
                            selectedDate.month,
                            selectedDate.day,
                            time.hour,
                            time.minute,
                          );
                          if (!end.isAfter(start)) {
                            end = start.add(const Duration(hours: 1));
                            endTime = TimeOfDay.fromDateTime(end);
                          }
                        });
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('结束时间'),
                    subtitle: Text(_time(end)),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: ctx,
                        initialTime: endTime,
                      );
                      if (time != null) {
                        setDialog(() {
                          endTime = time;
                          end = DateTime(
                            selectedDate.year,
                            selectedDate.month,
                            selectedDate.day,
                            time.hour,
                            time.minute,
                          );
                          if (!end.isAfter(start)) {
                            end = start.add(const Duration(hours: 1));
                            endTime = TimeOfDay.fromDateTime(end);
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(ctx, 'save'),
                        icon: const Icon(Icons.save),
                        label: const Text('保存'),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: () => Navigator.pop(ctx, 'delete'),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('删除'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (!mounted || action == null) {
      titleCtrl.dispose();
      noteCtrl.dispose();
      return;
    }
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除日程'),
          content: Text('确定删除 "${schedule.title}" 吗？'),
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
      if (ok == true) {
        await fp.deleteSchedule(schedule.id);
      }
      titleCtrl.dispose();
      noteCtrl.dispose();
      return;
    }
    final title = titleCtrl.text.trim();
    final note = noteCtrl.text.trim();
    await fp.updateSchedule(
      schedule.copyWith(
        title: title.isEmpty ? schedule.title : title,
        start: start,
        end: end,
        note: note.isEmpty ? null : note,
      ),
    );
    titleCtrl.dispose();
    noteCtrl.dispose();
  }
}

class _NotesPage extends StatefulWidget {
  final String? selectedNoteId;
  final bool editing;
  final ValueChanged<String> onSelect;
  final ValueChanged<bool> onEditingChanged;
  final VoidCallback onBack;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final Future<void> Function({String? folderId}) onNewNote;
  final VoidCallback onNewFolder;

  const _NotesPage({
    required this.selectedNoteId,
    required this.editing,
    required this.onSelect,
    required this.onEditingChanged,
    required this.onBack,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onNewNote,
    required this.onNewFolder,
  });

  @override
  State<_NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<_NotesPage> {
  static const _nativeTools = MethodChannel('lynai/native_tools');

  final _shot = ScreenshotController();
  final Set<String> _expandedFolderIds = {};
  late FeatureProvider _features;

  @override
  void initState() {
    super.initState();
    _features = context.read<FeatureProvider>();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedNoteId != null) {
      return _NoteDetail(
        noteId: widget.selectedNoteId!,
        editing: widget.editing,
        onEditingChanged: widget.onEditingChanged,
        onDeleted: widget.onBack,
      );
    }
    final provider = context.watch<FeatureProvider>();
    final notes = provider.notes;
    final folders = provider.noteFolders;
    if (notes.isEmpty && folders.isEmpty) {
      return Column(
        children: [
          _noteSearchBox(),
          const Expanded(
            child: _FeatureEmptyState(
              icon: Icons.sticky_note_2_outlined,
              title: '暂无笔记',
              subtitle: '点击右上角 + 创建第一篇笔记，支持 Markdown 和 LaTeX 渲染。',
            ),
          ),
        ],
      );
    }
    final query = widget.searchQuery.trim().toLowerCase();
    final visibleNotes = notes
        .where((note) => _matchesNote(note, query))
        .toList();
    final visibleFolders = folders.where((folder) {
      if (query.isEmpty) return true;
      return folder.title.toLowerCase().contains(query) ||
          visibleNotes.any((note) => note.folderId == folder.id);
    }).toList();
    final looseNotes = visibleNotes
        .where((note) => note.folderId == null || _folderMissing(note, folders))
        .toList();
    final entries = <_NoteListEntry>[
      ...visibleFolders.map(_NoteListEntry.folder),
      ...looseNotes.map(_NoteListEntry.note),
    ];
    return Column(
      children: [
        _noteSearchBox(),
        Expanded(
          child: entries.isEmpty
              ? ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: const [
                    ListTile(
                      leading: Icon(Icons.search_off),
                      title: Text('未找到匹配的笔记'),
                    ),
                  ],
                )
              : query.isEmpty
              ? ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 88),
                  itemCount: entries.length,
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) =>
                      _reorderTopLevel(entries, oldIndex, newIndex),
                  itemBuilder: (context, index) => _entryCard(
                    entries[index],
                    index: index,
                    draggable: true,
                    query: query,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 88),
                  itemCount: entries.length,
                  itemBuilder: (context, index) => _entryCard(
                    entries[index],
                    index: index,
                    draggable: false,
                    query: query,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _noteSearchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: TextField(
        controller: widget.searchController,
        decoration: InputDecoration(
          hintText: '搜索笔记标题或内容...',
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

  bool _matchesNote(Note note, String query) {
    if (query.isEmpty) return true;
    return note.title.toLowerCase().contains(query) ||
        note.content.toLowerCase().contains(query);
  }

  bool _folderMissing(Note note, List<NoteFolder> folders) {
    final folderId = note.folderId;
    if (folderId == null) return false;
    return !folders.any((folder) => folder.id == folderId);
  }

  Widget _entryCard(
    _NoteListEntry entry, {
    required int index,
    required bool draggable,
    required String query,
  }) {
    final folder = entry.folder;
    if (folder != null) {
      return _folderCard(
        folder,
        index: index,
        draggable: draggable,
        query: query,
      );
    }
    return _noteTile(entry.note!, index: index, draggable: draggable);
  }

  Widget _folderCard(
    NoteFolder folder, {
    required int index,
    required bool draggable,
    required String query,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final expanded = query.isNotEmpty || _expandedFolderIds.contains(folder.id);
    final notes = context
        .watch<FeatureProvider>()
        .notes
        .where(
          (note) => note.folderId == folder.id && _matchesNote(note, query),
        )
        .toList();
    return Card(
      key: ValueKey('folder-${folder.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Column(
        children: [
          ListTile(
            leading: draggable
                ? ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  )
                : const Icon(Icons.folder_outlined),
            title: Text(
              folder.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('${notes.length} 篇笔记'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: expanded ? '折叠' : '展开',
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: query.isEmpty
                      ? () => _toggleFolder(folder.id)
                      : null,
                ),
                PopupMenuButton<String>(
                  onSelected: (v) => _folderMenu(v, folder),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('重命名')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
            onTap: query.isEmpty ? () => _toggleFolder(folder.id) : null,
          ),
          if (expanded) ...[
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(Icons.note_add_outlined, color: scheme.primary),
              title: Text('创建笔记', style: TextStyle(color: scheme.primary)),
              onTap: () => widget.onNewNote(folderId: folder.id),
            ),
            if (notes.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '文件夹为空',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              )
            else if (query.isEmpty)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: notes.length,
                onReorder: (oldIndex, newIndex) => _features
                    .reorderNotesInFolder(folder.id, oldIndex, newIndex),
                itemBuilder: (context, noteIndex) => _noteTile(
                  notes[noteIndex],
                  index: noteIndex,
                  draggable: true,
                  nested: true,
                ),
              )
            else
              ...notes.map(
                (note) =>
                    _noteTile(note, index: 0, draggable: false, nested: true),
              ),
          ],
        ],
      ),
    );
  }

  Widget _noteTile(
    Note note, {
    required int index,
    required bool draggable,
    bool nested = false,
  }) {
    final preview = note.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Card(
      key: ValueKey('${nested ? 'nested' : 'note'}-${note.id}'),
      margin: nested
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      elevation: nested ? 0 : null,
      child: ListTile(
        dense: nested,
        leading: draggable
            ? ReorderableDragStartListener(
                index: index,
                child: Icon(nested ? Icons.drag_indicator : Icons.drag_handle),
              )
            : const Icon(Icons.sticky_note_2_outlined),
        title: Text(
          note.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          preview.isEmpty ? '空笔记' : preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) => _noteMenu(v, note),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('重命名')),
            PopupMenuItem(value: 'move', child: Text('移动到文件夹')),
            PopupMenuItem(value: 'export', child: Text('导出')),
            PopupMenuItem(value: 'image', child: Text('导出长图')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
        onTap: () => widget.onSelect(note.id),
      ),
    );
  }

  Future<void> _reorderTopLevel(
    List<_NoteListEntry> entries,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex < 0 || oldIndex >= entries.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= entries.length) return;
    final oldEntry = entries[oldIndex];
    final newEntry = entries[newIndex];
    if (oldEntry.isFolder != newEntry.isFolder) return;
    if (oldEntry.isFolder && newEntry.isFolder) {
      final folders = entries.where((e) => e.isFolder).toList();
      final oldFolderIndex = folders.indexWhere(
        (e) => e.folder!.id == oldEntry.folder!.id,
      );
      final newFolderIndex = folders.indexWhere(
        (e) => e.folder!.id == newEntry.folder!.id,
      );
      await _features.reorderNoteFolders(oldFolderIndex, newFolderIndex);
    } else if (!oldEntry.isFolder && !newEntry.isFolder) {
      final notes = entries.where((e) => !e.isFolder).toList();
      final oldNoteIndex = notes.indexWhere(
        (e) => e.note!.id == oldEntry.note!.id,
      );
      final newNoteIndex = notes.indexWhere(
        (e) => e.note!.id == newEntry.note!.id,
      );
      await _features.reorderNotesInFolder(null, oldNoteIndex, newNoteIndex);
    }
  }

  void _toggleFolder(String id) {
    setState(() {
      if (!_expandedFolderIds.add(id)) _expandedFolderIds.remove(id);
    });
  }

  Future<void> _noteMenu(String value, Note note) async {
    switch (value) {
      case 'rename':
        await _renameNote(note);
      case 'move':
        await _moveNote(note);
      case 'export':
        await _exportNote(note);
      case 'image':
        await _exportNoteImage(note);
      case 'delete':
        await _deleteNote(note);
    }
  }

  Future<void> _folderMenu(String value, NoteFolder folder) async {
    switch (value) {
      case 'rename':
        await _renameFolder(folder);
      case 'delete':
        await _deleteFolder(folder);
    }
  }

  Future<void> _renameNote(Note note) async {
    final title = await _textDialog(
      title: '重命名',
      label: '标题',
      initialText: note.title,
    );
    if (title == null || title.isEmpty) return;
    await _features.updateNote(note.copyWith(title: title));
  }

  Future<void> _moveNote(Note note) async {
    final folders = _features.noteFolders;
    final folderId = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('移动到文件夹'),
        children: [
          ListTile(
            leading: note.folderId == null
                ? const Icon(Icons.check, size: 20)
                : const SizedBox(width: 20),
            title: const Text('不放入文件夹'),
            onTap: () => Navigator.pop(ctx, ''),
          ),
          for (final folder in folders)
            ListTile(
              leading: note.folderId == folder.id
                  ? const Icon(Icons.check, size: 20)
                  : const SizedBox(width: 20),
              title: Text(folder.title),
              onTap: () => Navigator.pop(ctx, folder.id),
            ),
        ],
      ),
    );
    if (!mounted || folderId == null) return;
    await _features.updateNote(
      note.copyWith(folderId: folderId.isEmpty ? null : folderId),
    );
  }

  Future<void> _exportNote(Note note) async {
    final fileName = '${_safeExportFileName(note.title, 'note')}.md';
    try {
      final bytes = Uint8List.fromList(utf8.encode(note.content));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出笔记',
        fileName: fileName,
        bytes: bytes,
      );
      if (path == null) return;
      final file = File(path);
      if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('笔记已导出到 $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }

  Future<void> _exportNoteImage(Note note) async {
    final theme = Theme.of(context);
    final bytes = await _shot.captureFromLongWidget(
      _NoteShareImage(
        title: note.title,
        content: note.content,
        seedColor: theme.colorScheme.primary,
        brightness: theme.brightness,
      ),
      pixelRatio: 2.5,
      context: context,
      constraints: const BoxConstraints(maxWidth: 720),
    );
    if (!mounted) return;
    await _writeNoteImage(bytes);
  }

  Future<void> _writeNoteImage(Uint8List bytes) async {
    final fileName = 'note_${DateTime.now().millisecondsSinceEpoch}.png';
    try {
      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        final clipboard = SystemClipboard.instance;
        if (clipboard == null) throw Exception('当前平台不支持写入剪贴板');
        final item = DataWriterItem(suggestedName: fileName);
        item.add(Formats.png(bytes));
        await clipboard.write([item]);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('笔记图片已复制到剪贴板')));
        return;
      }
      if (Platform.isAndroid || Platform.isIOS) {
        final result = await _nativeTools.invokeMapMethod<String, dynamic>(
          'saveImageToGallery',
          {'bytes': bytes, 'fileName': fileName},
        );
        if (result?['ok'] != true) {
          throw Exception(result?['error'] ?? '保存到图库失败');
        }
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('笔记图片已保存到图库')));
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出图片失败: $e')));
    }
  }

  Future<void> _deleteNote(Note note) async {
    final ok = await _confirm(title: '删除笔记', message: '确定删除"${note.title}"吗？');
    if (ok != true || !mounted) return;
    await _features.deleteNote(note.id);
  }

  Future<void> _renameFolder(NoteFolder folder) async {
    final title = await _textDialog(
      title: '重命名文件夹',
      label: '名称',
      initialText: folder.title,
    );
    if (title == null || title.isEmpty) return;
    await _features.updateNoteFolder(folder.copyWith(title: title));
  }

  Future<void> _deleteFolder(NoteFolder folder) async {
    final ok = await _confirm(
      title: '删除文件夹',
      message: '确定删除"${folder.title}"吗？文件夹内笔记会移出文件夹。',
    );
    if (ok != true || !mounted) return;
    await _features.deleteNoteFolder(folder.id);
    setState(() => _expandedFolderIds.remove(folder.id));
  }

  Future<String?> _textDialog({
    required String title,
    required String label,
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
          decoration: InputDecoration(labelText: label),
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

  Future<bool?> _confirm({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
  }
}

class _NoteListEntry {
  final NoteFolder? folder;
  final Note? note;

  const _NoteListEntry.folder(this.folder) : note = null;
  const _NoteListEntry.note(this.note) : folder = null;

  bool get isFolder => folder != null;
}

class _FeatureEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: scheme.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

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
                  onReorder: provider.reorderTodoLists,
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
                onReorder: (oldIndex, newIndex) =>
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
          ...list.items,
          TodoItem(id: uuid.v4(), text: text),
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
    if (newIndex > oldIndex) newIndex -= 1;
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
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/${_safeExportFileName(list.title, 'todo')}.md',
    );
    await file.writeAsString(_todoMarkdown(list));
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  Future<void> _exportImage(TodoList list) async {
    final bytes = await _captureTodoImage(list);
    if (bytes == null) return;
    final fileName = 'todo_${DateTime.now().millisecondsSinceEpoch}.png';
    try {
      if (_isDesktopPlatform) {
        final clipboard = SystemClipboard.instance;
        if (clipboard == null) throw Exception('当前平台不支持写入剪贴板');
        final item = DataWriterItem(suggestedName: fileName);
        item.add(Formats.png(bytes));
        await clipboard.write([item]);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('待办清单图片已复制到剪贴板')));
        return;
      }
      if (Platform.isAndroid || Platform.isIOS) {
        final result = await _nativeTools.invokeMapMethod<String, dynamic>(
          'saveImageToGallery',
          {'bytes': bytes, 'fileName': fileName},
        );
        if (result?['ok'] != true) {
          throw Exception(result?['error'] ?? '保存到图库失败');
        }
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('待办清单图片已保存到图库')));
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出图片失败: $e')));
    }
  }

  Future<Uint8List?> _captureTodoImage(TodoList list) {
    final theme = Theme.of(context);
    return _shot.captureFromLongWidget(
      _TodoShareImage(
        list: list,
        seedColor: theme.colorScheme.primary,
        brightness: theme.brightness,
      ),
      pixelRatio: 2.5,
      context: context,
      constraints: const BoxConstraints(maxWidth: 720),
    );
  }

  bool get _isDesktopPlatform {
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
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
  final Color seedColor;
  final Brightness brightness;

  const _TodoShareImage({
    required this.list,
    required this.seedColor,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    final done = list.items.where((e) => e.done).length;
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
                        '待办清单 · ${list.items.length} 项 · 已完成 $done 项',
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
              'Exported from LynAI',
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

class _NoteDetail extends StatefulWidget {
  final String noteId;
  final bool editing;
  final ValueChanged<bool> onEditingChanged;
  final VoidCallback onDeleted;

  const _NoteDetail({
    required this.noteId,
    required this.editing,
    required this.onEditingChanged,
    required this.onDeleted,
  });

  @override
  State<_NoteDetail> createState() => _NoteDetailState();
}

class _NoteDetailState extends State<_NoteDetail> {
  static const _nativeTools = MethodChannel('lynai/native_tools');

  final _shot = ScreenshotController();
  late final TextEditingController _ctrl;
  late FeatureProvider _features;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _features = context.read<FeatureProvider>();
    final note = _features.getNote(widget.noteId);
    _ctrl = TextEditingController(text: note?.content ?? '');
    _ctrl.addListener(_scheduleSave);
  }

  @override
  void didUpdateWidget(covariant _NoteDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId) {
      _saveNote(oldWidget.noteId);
      final note = _features.getNote(widget.noteId);
      _ctrl.text = note?.content ?? '';
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _save();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = context.watch<FeatureProvider>().getNote(widget.noteId);
    if (note == null) return const Center(child: Text('笔记不存在'));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  note.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: widget.editing ? '保存' : '编辑',
                icon: Icon(widget.editing ? Icons.save : Icons.edit),
                onPressed: () {
                  _save();
                  widget.onEditingChanged(!widget.editing);
                },
              ),
              PopupMenuButton<String>(
                onSelected: (v) => _menu(v, note),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'save', child: Text('保存')),
                  const PopupMenuItem(value: 'rename', child: Text('重命名')),
                  const PopupMenuItem(value: 'export', child: Text('导出')),
                  const PopupMenuItem(value: 'image', child: Text('导出图片')),
                  const PopupMenuItem(
                    value: 'share_image',
                    child: Text('分享长图'),
                  ),
                  CheckedPopupMenuItem(
                    value: 'wrap',
                    checked: note.wrap,
                    child: const Text('自动换行'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.editing
              ? TextField(
                  controller: _ctrl,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                  scrollPhysics: const ClampingScrollPhysics(),
                )
              : Screenshot(
                  controller: _shot,
                  child: Container(
                    color: Theme.of(context).colorScheme.surface,
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: MediaQuery.sizeOf(context).width - 32,
                        ),
                        child: MarkdownWithLatex(content: note.content),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  void _scheduleSave() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 800), _save);
  }

  void _save() {
    _saveNote(widget.noteId);
  }

  void _saveNote(String noteId) {
    final note = _features.getNote(noteId);
    if (note == null || note.content == _ctrl.text) return;
    unawaited(_features.updateNote(note.copyWith(content: _ctrl.text)));
  }

  Future<void> _menu(String value, Note note) async {
    switch (value) {
      case 'save':
        _save();
        widget.onEditingChanged(false);
      case 'rename':
        await _rename(note);
      case 'export':
        await _export(note);
      case 'image':
        await _exportImage();
      case 'share_image':
        await _shareImage();
      case 'wrap':
        await _features.updateNote(note.copyWith(wrap: !note.wrap));
      case 'delete':
        await _delete(note);
    }
  }

  Future<void> _rename(Note note) async {
    final ctrl = TextEditingController(text: note.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: ctrl,
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
      await _features.updateNote(note.copyWith(title: title));
    }
  }

  Future<void> _export(Note note) async {
    _save();
    final fileName = '${_safeExportFileName(note.title, 'note')}.md';
    try {
      final bytes = Uint8List.fromList(utf8.encode(_ctrl.text));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出笔记',
        fileName: fileName,
        bytes: bytes,
      );
      if (path == null) return;
      final file = File(path);
      if (!await file.exists()) {
        await file.writeAsBytes(bytes, flush: true);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('笔记已导出到 $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }

  Future<void> _exportImage() async {
    _save();
    final note = _features.getNote(widget.noteId);
    if (note == null) return;
    final bytes = await _captureNoteImage(note.title, _ctrl.text);
    if (bytes == null) return;
    final fileName = 'note_${DateTime.now().millisecondsSinceEpoch}.png';
    try {
      if (_isDesktopPlatform) {
        final clipboard = SystemClipboard.instance;
        if (clipboard == null) throw Exception('当前平台不支持写入剪贴板');
        final item = DataWriterItem(suggestedName: fileName);
        item.add(Formats.png(bytes));
        await clipboard.write([item]);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('笔记图片已复制到剪贴板')));
        return;
      }
      if (Platform.isAndroid || Platform.isIOS) {
        final result = await _nativeTools.invokeMapMethod<String, dynamic>(
          'saveImageToGallery',
          {'bytes': bytes, 'fileName': fileName},
        );
        if (result?['ok'] != true) {
          throw Exception(result?['error'] ?? '保存到图库失败');
        }
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('笔记图片已保存到图库')));
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出图片失败: $e')));
    }
  }

  Future<void> _shareImage() async {
    _save();
    final note = _features.getNote(widget.noteId);
    if (note == null) return;
    final bytes = await _captureNoteImage(note.title, _ctrl.text);
    if (bytes == null) return;
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/note_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('分享失败: $e')));
    }
  }

  Future<Uint8List?> _captureNoteImage(String title, String content) {
    final theme = Theme.of(context);
    final shareWidget = _NoteShareImage(
      title: title,
      content: content,
      seedColor: theme.colorScheme.primary,
      brightness: theme.brightness,
    );
    return _shot.captureFromLongWidget(
      shareWidget,
      pixelRatio: 2.5,
      context: context,
      constraints: const BoxConstraints(maxWidth: 720),
    );
  }

  bool get _isDesktopPlatform {
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  Future<void> _delete(Note note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除笔记'),
        content: Text('确定删除"${note.title}"吗？'),
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
    await _features.deleteNote(note.id);
    widget.onDeleted();
  }
}

class _NoteShareImage extends StatelessWidget {
  final String title;
  final String content;
  final Color seedColor;
  final Brightness brightness;

  const _NoteShareImage({
    required this.title,
    required this.content,
    required this.seedColor,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
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
        decoration: BoxDecoration(color: bgColor),
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
                    Icons.sticky_note_2_outlined,
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
                        title.isEmpty ? 'LynAI 笔记' : title,
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
                        'Markdown 笔记 · ${DateTime.now().year}/${DateTime.now().month}/${DateTime.now().day}',
                        style: TextStyle(color: mutedColor, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
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
              child: MarkdownWithLatex(
                content: content,
                selectable: false,
                wrapCodeBlocks: true,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Exported from LynAI',
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
