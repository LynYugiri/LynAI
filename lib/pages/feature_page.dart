import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:uuid/uuid.dart';
import 'latex_formula_editor_page.dart';
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

const _exportImagePixelRatio = 2.5;
const _exportTextChunkLength = 2800;
const _exportTodoPageWeight = 3200;
const _exportTodoItemChunkLength = 1200;

class _SearchMatcher {
  final String query;
  final bool caseSensitive;
  final String? regexError;
  final RegExp? _regex;

  _SearchMatcher._({
    required this.query,
    required this.caseSensitive,
    required RegExp? regex,
    required this.regexError,
  }) : _regex = regex;

  factory _SearchMatcher.literal(String query, {bool caseSensitive = false}) {
    return _SearchMatcher._(
      query: query,
      caseSensitive: caseSensitive,
      regex: null,
      regexError: null,
    );
  }

  factory _SearchMatcher.fromSearchSyntax(
    String query, {
    bool caseSensitive = false,
  }) {
    final parsed = _parseRegexSearch(query);
    if (parsed == null) return _SearchMatcher.literal(query);
    try {
      return _SearchMatcher._(
        query: query,
        caseSensitive: parsed.caseSensitive ?? caseSensitive,
        regex: RegExp(
          parsed.pattern,
          caseSensitive: parsed.caseSensitive ?? caseSensitive,
          multiLine: true,
        ),
        regexError: null,
      );
    } catch (e) {
      return _SearchMatcher._(
        query: query,
        caseSensitive: caseSensitive,
        regex: null,
        regexError: '$e',
      );
    }
  }

  factory _SearchMatcher.regex(String query, {required bool caseSensitive}) {
    if (query.isEmpty) return _SearchMatcher.literal(query);
    try {
      return _SearchMatcher._(
        query: query,
        caseSensitive: caseSensitive,
        regex: RegExp(query, caseSensitive: caseSensitive, multiLine: true),
        regexError: null,
      );
    } catch (e) {
      return _SearchMatcher._(
        query: query,
        caseSensitive: caseSensitive,
        regex: null,
        regexError: '$e',
      );
    }
  }

  bool get isEmpty => query.isEmpty;
  bool get isRegex => _regex != null;
  bool get hasError => regexError != null;

  bool matches(String text) {
    if (query.isEmpty) return true;
    final regex = _regex;
    if (regex != null) return regex.hasMatch(text);
    if (regexError != null) return false;
    if (caseSensitive) return text.contains(query);
    return text.toLowerCase().contains(query.toLowerCase());
  }

  Iterable<RegExpMatch> allMatches(String text) {
    final regex = _regex;
    if (query.isEmpty || regexError != null) return const Iterable.empty();
    if (regex != null) return regex.allMatches(text);
    final pattern = RegExp.escape(query);
    return RegExp(pattern, caseSensitive: caseSensitive).allMatches(text);
  }
}

class _ParsedRegexSearch {
  final String pattern;
  final bool? caseSensitive;

  const _ParsedRegexSearch(this.pattern, {this.caseSensitive});
}

_ParsedRegexSearch? _parseRegexSearch(String query) {
  final trimmed = query.trim();
  if (trimmed.startsWith('re:')) {
    final pattern = trimmed.substring(3).trim();
    return pattern.isEmpty ? null : _ParsedRegexSearch(pattern);
  }
  if (!trimmed.startsWith('/') || trimmed.length < 2) return null;
  final lastSlash = trimmed.lastIndexOf('/');
  if (lastSlash <= 0) return null;
  final pattern = trimmed.substring(1, lastSlash);
  if (pattern.isEmpty) return null;
  final flags = trimmed.substring(lastSlash + 1);
  final insensitive = flags.contains('i');
  return _ParsedRegexSearch(pattern, caseSensitive: !insensitive);
}

SnackBar _shortSnackBar(String message) {
  return SnackBar(
    content: Builder(
      builder: (context) {
        final messenger = ScaffoldMessenger.of(context);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: messenger.hideCurrentSnackBar,
          child: Text(message),
        );
      },
    ),
    duration: const Duration(seconds: 2),
    showCloseIcon: true,
  );
}

String _formatNoteTime(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}

_NoteDiffStats _noteDiffStats(String before, String after) {
  final delta = NoteTextDelta.between(before, after);
  return _NoteDiffStats(
    addedChars: delta.insertedText.length,
    removedChars: delta.deletedText.length,
    addedLines: _changedLineCount(delta.insertedText),
    removedLines: _changedLineCount(delta.deletedText),
  );
}

int _changedLineCount(String text) {
  if (text.isEmpty) return 0;
  return '\n'.allMatches(text).length + 1;
}

String _noteDiffSummary(String before, String after) {
  final stats = _noteDiffStats(before, after);
  if (!stats.hasChanges) return '无内容变化';
  if (stats.addedChars > 0 && stats.removedChars > 0) {
    return '+${stats.addedChars} / -${stats.removedChars} 字符';
  }
  if (stats.addedChars > 0) return '+${stats.addedChars} 字符';
  return '-${stats.removedChars} 字符';
}

String _noteLineDiffSummary(String before, String after) {
  final stats = _noteDiffStats(before, after);
  if (!stats.hasChanges) return '行无变化';
  if (stats.addedLines > 0 && stats.removedLines > 0) {
    return '+${stats.addedLines} / -${stats.removedLines} 行';
  }
  if (stats.addedLines > 0) return '+${stats.addedLines} 行';
  return '-${stats.removedLines} 行';
}

String _imageFileName(String prefix, int timestamp, int index, int total) {
  final suffix = total == 1 ? '' : '_part_${index + 1}_of_$total';
  return '${prefix}_$timestamp$suffix.png';
}

String _imageDoneText(String base, int count) {
  return count == 1 ? base : '$base，共 $count 张';
}

List<String> _splitExportText(String text) {
  final trimmed = text.trim();
  if (trimmed.length <= _exportTextChunkLength) return [trimmed];
  final chunks = <String>[];
  var start = 0;
  while (start < trimmed.length) {
    var end = (start + _exportTextChunkLength).clamp(0, trimmed.length);
    if (end < trimmed.length) {
      final paragraphBreak = trimmed.lastIndexOf('\n\n', end);
      final lineBreak = trimmed.lastIndexOf('\n', end);
      final space = trimmed.lastIndexOf(' ', end);
      final splitAt = [paragraphBreak, lineBreak, space]
          .where((i) => i > start + (_exportTextChunkLength ~/ 2))
          .fold<int>(-1, (best, i) => i > best ? i : best);
      if (splitAt != -1) end = splitAt;
    }
    final chunk = trimmed.substring(start, end).trim();
    if (chunk.isNotEmpty) chunks.add(chunk);
    start = end;
  }
  return chunks.isEmpty ? [''] : chunks;
}

class FeaturePage extends StatefulWidget {
  final void Function(String conversationId) onConversationTap;
  final VoidCallback onRoleChanged;
  final void Function(bool Function() handler)? onBackHandlerChanged;

  const FeaturePage({
    super.key,
    required this.onConversationTap,
    required this.onRoleChanged,
    this.onBackHandlerChanged,
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
    widget.onBackHandlerChanged?.call(() => false);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.onBackHandlerChanged?.call(_handleBack);
  }

  bool _handleBack() {
    if (_selectedNoteId != null) {
      _closeSelectedNote();
      return true;
    }
    return false;
  }

  void _closeSelectedNote() {
    setState(() {
      _selectedNoteId = null;
      _noteEditing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final features = context.watch<FeatureProvider>();
    final feature = settings.lastFeature;
    return Scaffold(
      appBar: AppBar(
        leading: _selectedNoteId == null
            ? _featureSwitcher(feature)
            : IconButton(
                tooltip: '笔记列表',
                icon: const Icon(Icons.menu),
                onPressed: _closeSelectedNote,
              ),
        title: Text(
          _title(feature, features),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
          onBack: _closeSelectedNote,
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

  String _title(String feature, FeatureProvider features) {
    if (_selectedNoteId != null) {
      final title = features.getNote(_selectedNoteId!)?.title.trim();
      if (title != null && title.isNotEmpty) return title;
      return '笔记';
    }
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
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
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
                  _AddMenuButton(
                    items: const [
                      _AddMenuItem('schedule', Icons.event, '新建日程'),
                      _AddMenuItem('task', Icons.flag_outlined, '新建任务'),
                    ],
                    onSelected: (value) => value == 'task'
                        ? _newScheduleItem(ScheduleItem.kindTask)
                        : _newScheduleItem(ScheduleItem.kindSchedule),
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
                              '${_weekdayName(selectedDate.weekday)} | ${selectedItems.length} 条事项',
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
                          '这一天没有事项',
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
                                      _timeLabelForDate(item, selectedDate),
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
            '${_timeLabelForDate(item, date)}  ${item.title}',
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
            .where((e) => _itemOverlapsRange(e, monthStart, monthEnd))
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
                              count == 0 ? '这个月没有事项' : '共 $count 条事项',
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
    return items.where((e) => _itemOverlapsRange(e, dayStart, dayEnd)).toList();
  }

  bool _itemOverlapsRange(ScheduleItem item, DateTime from, DateTime to) {
    if (item.isTask) {
      return !item.start.isBefore(from) && item.start.isBefore(to);
    }
    return item.start.isBefore(to) && item.end.isAfter(from);
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

  String _timeLabelForDate(ScheduleItem item, DateTime date) {
    if (item.isTask) return '任务 ${_time(item.start)}';
    return _timeRangeForDate(item, date);
  }

  DateTime _visibleStartForDate(ScheduleItem item, DateTime date) {
    final dayStart = _dateOnly(date);
    return item.start.isAfter(dayStart) ? item.start : dayStart;
  }

  DateTime _visibleEndForDate(ScheduleItem item, DateTime date) {
    final dayEnd = _dateOnly(date).add(const Duration(days: 1));
    return item.end.isBefore(dayEnd) ? item.end : dayEnd;
  }

  Future<void> _newScheduleItem(String kind) async {
    final isTask = kind == ScheduleItem.kindTask;
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
            title: Text(isTask ? '新建任务' : '新建日程'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => Navigator.pop(ctx, true),
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
                  if (!isTask) ...[
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
      kind: kind,
    );
  }

  Future<void> _openScheduleEditor(ScheduleItem schedule) async {
    final fp = context.read<FeatureProvider>();
    final titleCtrl = TextEditingController(text: schedule.title);
    final noteCtrl = TextEditingController(text: schedule.note ?? '');
    final isTask = schedule.isTask;
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
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => Navigator.pop(ctx, 'save'),
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
                  if (!isTask)
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
          title: Text(isTask ? '删除任务' : '删除日程'),
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
        end: isTask ? start.add(const Duration(minutes: 1)) : end,
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
        onSelectNote: widget.onSelect,
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
    final query = widget.searchQuery.trim();
    final matcher = _SearchMatcher.fromSearchSyntax(query);
    final visibleNotes = notes
        .where((note) => _matchesNote(note, matcher))
        .toList();
    final visibleFolders = folders.where((folder) {
      if (matcher.isEmpty) return true;
      return matcher.matches(folder.title) ||
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
              : matcher.isEmpty
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
          hintText: '搜索笔记标题或内容，支持 re:正则 或 /正则/i',
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

  bool _matchesNote(Note note, _SearchMatcher matcher) {
    if (matcher.isEmpty) return true;
    return matcher.matches(note.title) || matcher.matches(note.content);
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
          (note) =>
              note.folderId == folder.id &&
              _matchesNote(note, _SearchMatcher.fromSearchSyntax(query)),
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
    final bytes = <Uint8List>[];
    final pages = _splitExportText(note.content);
    for (var i = 0; i < pages.length; i++) {
      bytes.add(
        await _shot.captureFromLongWidget(
          _NoteShareImage(
            title: note.title,
            content: pages[i],
            seedColor: theme.colorScheme.primary,
            brightness: theme.brightness,
            pageNumber: pages.length == 1 ? null : i + 1,
            pageCount: pages.length == 1 ? null : pages.length,
          ),
          pixelRatio: _exportImagePixelRatio,
          context: context,
          constraints: const BoxConstraints(maxWidth: 720),
        ),
      );
    }
    if (!mounted) return;
    await _writeNoteImage(bytes);
  }

  Future<void> _writeNoteImage(List<Uint8List> images) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    try {
      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        final clipboard = SystemClipboard.instance;
        if (clipboard == null) throw Exception('当前平台不支持写入剪贴板');
        final items = <DataWriterItem>[];
        for (var i = 0; i < images.length; i++) {
          final item = DataWriterItem(
            suggestedName: _imageFileName('note', timestamp, i, images.length),
          );
          item.add(Formats.png(images[i]));
          items.add(item);
        }
        await clipboard.write(items);
        if (!mounted) return;
        _showImageSnack(_imageDoneText('笔记图片已复制到剪贴板', images.length));
        return;
      }
      if (Platform.isAndroid || Platform.isIOS) {
        for (var i = 0; i < images.length; i++) {
          final result = await _nativeTools
              .invokeMapMethod<String, dynamic>('saveImageToGallery', {
                'bytes': images[i],
                'fileName': _imageFileName('note', timestamp, i, images.length),
              });
          if (result?['ok'] != true) {
            throw Exception(result?['error'] ?? '保存到图库失败');
          }
        }
        if (!mounted) return;
        _showImageSnack(_imageDoneText('笔记图片已保存到图库', images.length));
        return;
      }
      final dir = await getTemporaryDirectory();
      final files = <XFile>[];
      for (var i = 0; i < images.length; i++) {
        final file = File(
          '${dir.path}/${_imageFileName('note', timestamp, i, images.length)}',
        );
        await file.writeAsBytes(images[i], flush: true);
        files.add(XFile(file.path));
      }
      await SharePlus.instance.share(ShareParams(files: files));
    } catch (e) {
      if (!mounted) return;
      _showImageSnack('导出图片失败: $e');
    }
  }

  void _showImageSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(_shortSnackBar(message));
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
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
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

class _NoteDiffStats {
  final int addedChars;
  final int removedChars;
  final int addedLines;
  final int removedLines;

  const _NoteDiffStats({
    required this.addedChars,
    required this.removedChars,
    required this.addedLines,
    required this.removedLines,
  });

  bool get hasChanges => addedChars > 0 || removedChars > 0;
}

enum _DiffLineType { context, added, removed }

class _DiffLine {
  final _DiffLineType type;
  final int? beforeLine;
  final int? afterLine;
  final String text;

  const _DiffLine({
    required this.type,
    required this.beforeLine,
    required this.afterLine,
    required this.text,
  });
}

class _NoteTimelineSheet extends StatefulWidget {
  final Note note;
  final FeatureProvider features;
  final void Function(NoteRevision revision, String content) onOpen;
  final void Function(NoteRevision revision, String content) onCompare;
  final Future<void> Function(NoteRevision revision) onRestore;
  final Future<void> Function(String content) onCopy;
  final Future<void> Function(NoteRevision revision, String content)
  onDuplicate;
  final Future<void> Function(NoteRevision revision) onDelete;
  final Future<void> Function(NoteRevision revision, int branchCount)
  onDeleteBranches;

  const _NoteTimelineSheet({
    required this.note,
    required this.features,
    required this.onOpen,
    required this.onCompare,
    required this.onRestore,
    required this.onCopy,
    required this.onDuplicate,
    required this.onDelete,
    required this.onDeleteBranches,
  });

  @override
  State<_NoteTimelineSheet> createState() => _NoteTimelineSheetState();
}

class _NoteTimelineSheetState extends State<_NoteTimelineSheet> {
  final _searchCtrl = TextEditingController();
  final _contentCache = <String, String>{};
  final _previousContentCache = <String, String>{};
  final _statsCache = <String, _NoteDiffStats>{};
  var _query = '';
  var _filter = _NoteTimelineFilter.all;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.features,
      builder: (context, _) {
        final note = widget.features.getNote(widget.note.id) ?? widget.note;
        final timeline = widget.features.getNoteTimeline(note.id);
        _removeStaleCache(timeline);
        final currentPath = widget.features.getNoteCurrentRevisionPath(note.id);
        final entries = _filteredEntries(timeline, currentPath);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.82,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '时间线',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '${timeline.length} 个版本',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '搜索版本内容或时间...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _query = '');
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip('全部', _NoteTimelineFilter.all),
                        const SizedBox(width: 8),
                        _filterChip('当前路径', _NoteTimelineFilter.currentPath),
                        const SizedBox(width: 8),
                        _filterChip('分支', _NoteTimelineFilter.branches),
                        const SizedBox(width: 8),
                        _filterChip('大改动', _NoteTimelineFilter.largeChanges),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: timeline.isEmpty
                        ? const Center(child: Text('还没有保存过时间线'))
                        : entries.isEmpty
                        ? const Center(child: Text('没有匹配的版本'))
                        : ListView.builder(
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              if (entry.header != null) {
                                return _dateHeader(entry.header!);
                              }
                              return _revisionCard(
                                note,
                                entry.revision!,
                                currentPath,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _filterChip(String label, _NoteTimelineFilter filter) {
    return FilterChip(
      label: Text(label),
      selected: _filter == filter,
      onSelected: (_) => setState(() => _filter = filter),
    );
  }

  List<_NoteTimelineEntry> _filteredEntries(
    List<NoteRevision> timeline,
    Set<String> currentPath,
  ) {
    final query = _query.trim().toLowerCase();
    final revisions = <NoteRevision>[];
    for (final revision in timeline) {
      if (!_matchesFilter(revision, currentPath)) continue;
      if (query.isNotEmpty && !_matchesQuery(revision, query)) continue;
      revisions.add(revision);
    }
    final entries = <_NoteTimelineEntry>[];
    String? previousHeader;
    for (final revision in revisions) {
      final header = _dateGroup(revision.savedAt);
      if (header != previousHeader) {
        entries.add(_NoteTimelineEntry.header(header));
        previousHeader = header;
      }
      entries.add(_NoteTimelineEntry.revision(revision));
    }
    return entries;
  }

  bool _matchesFilter(NoteRevision revision, Set<String> currentPath) {
    return switch (_filter) {
      _NoteTimelineFilter.all => true,
      _NoteTimelineFilter.currentPath => currentPath.contains(revision.id),
      _NoteTimelineFilter.branches => !currentPath.contains(revision.id),
      _NoteTimelineFilter.largeChanges => _isLargeChange(revision),
    };
  }

  bool _matchesQuery(NoteRevision revision, String query) {
    final time = _formatNoteTime(revision.savedAt).toLowerCase();
    if (time.contains(query)) return true;
    final content = _contentFor(revision).toLowerCase();
    return content.contains(query);
  }

  bool _isLargeChange(NoteRevision revision) {
    final stats = _statsFor(revision);
    return stats.addedChars + stats.removedChars >= 240 ||
        stats.addedLines + stats.removedLines >= 8;
  }

  Widget _dateHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _revisionCard(
    Note note,
    NoteRevision revision,
    Set<String> currentPath,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final content = _contentFor(revision);
    final previous = _previousContentFor(revision);
    final current = note.currentRevisionId == revision.id;
    final onCurrentPath = currentPath.contains(revision.id);
    final branchCount = widget.features.countNoteBranchRevisions(
      note.id,
      revision.id,
    );
    final preview = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(
          current
              ? Icons.radio_button_checked
              : onCurrentPath
              ? Icons.timeline
              : Icons.call_split,
          color: current
              ? scheme.primary
              : onCurrentPath
              ? scheme.secondary
              : scheme.tertiary,
        ),
        title: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(_formatNoteTime(revision.savedAt)),
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text(
                current
                    ? '当前'
                    : onCurrentPath
                    ? '当前路径'
                    : '分支',
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${_noteDiffSummary(previous, content)} · ${_noteLineDiffSummary(previous, content)} · ${preview.isEmpty ? '空笔记' : preview}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _revisionAction(
            value,
            revision,
            content,
            onCurrentPath,
            branchCount,
          ),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'open', child: Text('查看此版本')),
            const PopupMenuItem(value: 'compare', child: Text('与当前对比')),
            const PopupMenuItem(value: 'restore', child: Text('恢复为当前版本')),
            const PopupMenuItem(value: 'copy', child: Text('复制内容')),
            const PopupMenuItem(value: 'duplicate', child: Text('另存为新笔记')),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'deleteBranches',
              enabled: branchCount > 0,
              child: Text(
                branchCount > 0 ? '删除从此分出的支线 ($branchCount)' : '没有可删除的支线',
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              enabled: !onCurrentPath,
              child: Text(onCurrentPath ? '当前路径版本不能删除' : '删除版本'),
            ),
          ],
        ),
        onTap: () => widget.onOpen(revision, content),
        onLongPress: () => widget.onCompare(revision, content),
      ),
    );
  }

  void _revisionAction(
    String value,
    NoteRevision revision,
    String content,
    bool onCurrentPath,
    int branchCount,
  ) {
    switch (value) {
      case 'open':
        widget.onOpen(revision, content);
      case 'compare':
        widget.onCompare(revision, content);
      case 'restore':
        widget.onRestore(revision);
      case 'copy':
        widget.onCopy(content);
      case 'duplicate':
        widget.onDuplicate(revision, content);
      case 'deleteBranches':
        if (branchCount > 0) widget.onDeleteBranches(revision, branchCount);
      case 'delete':
        if (!onCurrentPath) widget.onDelete(revision);
    }
  }

  String _dateGroup(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(value.year, value.month, value.day);
    final difference = today.difference(day).inDays;
    if (difference == 0) return '今天';
    if (difference == 1) return '昨天';
    if (difference < 7) return '本周';
    final month = value.month.toString().padLeft(2, '0');
    final date = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$date';
  }

  String _contentFor(NoteRevision revision) {
    return _contentCache.putIfAbsent(
      revision.id,
      () =>
          widget.features.getNoteContentAtRevision(widget.note.id, revision.id),
    );
  }

  String _previousContentFor(NoteRevision revision) {
    return _previousContentCache.putIfAbsent(revision.id, () {
      final parentId = revision.parentRevisionId;
      if (parentId == null) return '';
      return widget.features.getNoteContentAtRevision(widget.note.id, parentId);
    });
  }

  _NoteDiffStats _statsFor(NoteRevision revision) {
    return _statsCache.putIfAbsent(
      revision.id,
      () =>
          _noteDiffStats(_previousContentFor(revision), _contentFor(revision)),
    );
  }

  void _removeStaleCache(List<NoteRevision> timeline) {
    final ids = timeline.map((revision) => revision.id).toSet();
    _contentCache.removeWhere((id, _) => !ids.contains(id));
    _previousContentCache.removeWhere((id, _) => !ids.contains(id));
    _statsCache.removeWhere((id, _) => !ids.contains(id));
  }
}

enum _NoteTimelineFilter { all, currentPath, branches, largeChanges }

class _NoteTimelineEntry {
  final String? header;
  final NoteRevision? revision;

  const _NoteTimelineEntry.header(this.header) : revision = null;
  const _NoteTimelineEntry.revision(this.revision) : header = null;
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
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/${_safeExportFileName(list.title, 'todo')}.md',
    );
    await file.writeAsString(_todoMarkdown(list));
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  Future<void> _exportImage(TodoList list) async {
    final images = await _captureTodoImages(list);
    if (images.isEmpty) return;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    try {
      if (_isDesktopPlatform) {
        final clipboard = SystemClipboard.instance;
        if (clipboard == null) throw Exception('当前平台不支持写入剪贴板');
        final items = <DataWriterItem>[];
        for (var i = 0; i < images.length; i++) {
          final item = DataWriterItem(
            suggestedName: _imageFileName('todo', timestamp, i, images.length),
          );
          item.add(Formats.png(images[i]));
          items.add(item);
        }
        await clipboard.write(items);
        if (!mounted) return;
        _showImageSnack(_imageDoneText('待办清单图片已复制到剪贴板', images.length));
        return;
      }
      if (Platform.isAndroid || Platform.isIOS) {
        for (var i = 0; i < images.length; i++) {
          final result = await _nativeTools
              .invokeMapMethod<String, dynamic>('saveImageToGallery', {
                'bytes': images[i],
                'fileName': _imageFileName('todo', timestamp, i, images.length),
              });
          if (result?['ok'] != true) {
            throw Exception(result?['error'] ?? '保存到图库失败');
          }
        }
        if (!mounted) return;
        _showImageSnack(_imageDoneText('待办清单图片已保存到图库', images.length));
        return;
      }
      final dir = await getTemporaryDirectory();
      final files = <XFile>[];
      for (var i = 0; i < images.length; i++) {
        final file = File(
          '${dir.path}/${_imageFileName('todo', timestamp, i, images.length)}',
        );
        await file.writeAsBytes(images[i], flush: true);
        files.add(XFile(file.path));
      }
      await SharePlus.instance.share(ShareParams(files: files));
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
      images.add(
        await _shot.captureFromLongWidget(
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
        ),
      );
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
    messenger.showSnackBar(_shortSnackBar(message));
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

class _NoteDetail extends StatefulWidget {
  final String noteId;
  final bool editing;
  final ValueChanged<bool> onEditingChanged;
  final VoidCallback onDeleted;
  final ValueChanged<String> onSelectNote;

  const _NoteDetail({
    required this.noteId,
    required this.editing,
    required this.onEditingChanged,
    required this.onDeleted,
    required this.onSelectNote,
  });

  @override
  State<_NoteDetail> createState() => _NoteDetailState();
}

class _NoteDetailState extends State<_NoteDetail> {
  static const _nativeTools = MethodChannel('lynai/native_tools');

  final _shot = ScreenshotController();
  late final TextEditingController _ctrl;
  final _editorFocus = FocusNode();
  final _findFocus = FocusNode();
  final _editorScroll = ScrollController();
  final _findCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  late FeatureProvider _features;
  var _showFind = false;
  var _showReplace = false;
  var _showLatexPanel = false;
  var _caseSensitiveFind = false;
  var _regexFind = false;
  var _currentMatch = -1;
  String? _findError;
  var _matches = <TextRange>[];
  var _lastSavedDraft = '';
  var _lastEditorSelection = const TextSelection.collapsed(offset: 0);
  var _trackedEditorText = '';
  var _trackedEditorSelection = const TextSelection.collapsed(offset: 0);
  var _undoStack = <_NoteEditStep>[];
  var _redoStack = <_NoteEditStep>[];
  var _applyingEditHistory = false;
  String? _activeRevisionId;
  var _proposalSidebarExpanded = true;
  Offset? _proposalBubbleOffset;
  String? _pendingExternalSyncContent;

  @override
  void initState() {
    super.initState();
    _features = context.read<FeatureProvider>();
    final note = _features.getNote(widget.noteId);
    _lastSavedDraft = note?.content ?? '';
    _trackedEditorText = _lastSavedDraft;
    _ctrl = TextEditingController(text: _lastSavedDraft);
    _ctrl.addListener(_onEditorTextChanged);
    _editorFocus.addListener(_refreshLatexPanel);
    _findCtrl.addListener(_refreshMatches);
  }

  @override
  void didUpdateWidget(covariant _NoteDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId) {
      final note = _features.getNote(widget.noteId);
      _loadEditorSnapshot(note?.content ?? '', revisionId: null);
      _proposalSidebarExpanded = true;
      _proposalBubbleOffset = null;
      _refreshMatches();
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onEditorTextChanged);
    _editorFocus.removeListener(_refreshLatexPanel);
    _findCtrl.removeListener(_refreshMatches);
    _ctrl.dispose();
    _editorFocus.dispose();
    _findFocus.dispose();
    _editorScroll.dispose();
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = context.watch<FeatureProvider>().getNote(widget.noteId);
    if (note == null) return const Center(child: Text('笔记不存在'));
    final proposal = context.watch<FeatureProvider>().getNoteEditProposal(
      widget.noteId,
    );
    final hasProposal = proposal != null && proposal.blocks.isNotEmpty;
    if (!hasProposal && _proposalSidebarExpanded != true) {
      _proposalSidebarExpanded = true;
    }
    final viewingRevision = _activeRevisionId == null
        ? null
        : _features.getNoteRevision(_activeRevisionId!);
    final viewingHistorical = viewingRevision != null;
    _queueExternalNoteSyncIfNeeded(note, hasProposal: hasProposal);
    final canUndo = widget.editing && _undoStack.isNotEmpty;
    final canRedo = widget.editing && _redoStack.isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Row(
            children: [
              const Spacer(),
              IconButton(
                tooltip: '后退',
                onPressed: canUndo ? _undo : null,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: '前进',
                onPressed: canRedo ? _redo : null,
                icon: const Icon(Icons.redo),
              ),
              IconButton(
                tooltip: '时间线',
                icon: const Icon(Icons.timeline),
                onPressed: () => _openTimeline(note),
              ),
              IconButton(
                tooltip: widget.editing ? '预览' : '编辑',
                icon: Icon(widget.editing ? Icons.visibility : Icons.edit),
                onPressed: () {
                  widget.onEditingChanged(!widget.editing);
                },
              ),
              IconButton(
                tooltip: '保存',
                icon: const Icon(Icons.save),
                onPressed: _canSave ? () => _save() : null,
              ),
              IconButton(
                tooltip: '查找 / 替换',
                icon: const Icon(Icons.find_replace),
                onPressed: _openFind,
              ),
              PopupMenuButton<String>(
                onSelected: (v) => _menu(v, note),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'save', child: Text('保存')),
                  const PopupMenuItem(value: 'rename', child: Text('重命名')),
                  const PopupMenuItem(value: 'find', child: Text('查找 / 替换')),
                  const PopupMenuItem(value: 'goto', child: Text('跳转到行')),
                  const PopupMenuItem(value: 'latex', child: Text('LaTeX 工具')),
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
        if (viewingHistorical) _historyBanner(note, viewingRevision),
        if (widget.editing && !hasProposal) _editorToolbar(note),
        if (widget.editing && _showLatexPanel && !hasProposal) _latexPanel(),
        if (_showFind && !hasProposal) _findReplaceBar(),
        Expanded(
          child: _noteBody(note, proposal, hasProposal, viewingHistorical),
        ),
        _editorStatus(note),
      ],
    );
  }

  Widget _noteBody(
    Note note,
    NoteEditProposal? proposal,
    bool hasProposal,
    bool viewingHistorical,
  ) {
    final base = hasProposal && !viewingHistorical && _proposalSidebarExpanded
        ? _buildAiProposalReviewView(note, proposal!)
        : widget.editing
        ? _noteEditor(note)
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
                  child: MarkdownWithLatex(
                    content: _ctrl.text,
                    onEditLatexBlock: _editLatexBlockFromPreview,
                  ),
                ),
              ),
            ),
          );
    if (!hasProposal || viewingHistorical || _proposalSidebarExpanded) {
      return base;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final bubbleSize = _proposalBubbleSize(proposal!);
        final defaultOffset = Offset(
          (constraints.maxWidth - bubbleSize.width - 16).clamp(
            0.0,
            double.infinity,
          ),
          (constraints.maxHeight - bubbleSize.height - 16).clamp(
            0.0,
            double.infinity,
          ),
        );
        final offset = _clampProposalBubbleOffset(
          _proposalBubbleOffset ?? defaultOffset,
          constraints.biggest,
          bubbleSize,
        );
        return Stack(
          children: [
            Positioned.fill(child: base),
            Positioned(
              left: offset.dx,
              top: offset.dy,
              child: _proposalBubble(note, proposal, constraints.biggest),
            ),
          ],
        );
      },
    );
  }

  Widget _noteEditor(Note note) {
    final editorSurface = Container(
      color: Theme.of(context).colorScheme.surface,
      child: _buildNoteEditorField(note),
    );
    return editorSurface;
  }

  Widget _buildNoteEditorField(Note note) {
    final longestLine = _ctrl.text
        .split('\n')
        .fold<int>(
          0,
          (longest, line) => line.length > longest ? line.length : longest,
        );
    final editorWidth = (longestLine * 8.5 + 48).clamp(1600.0, 6000.0);
    final editor = TextField(
      controller: _ctrl,
      focusNode: _editorFocus,
      scrollController: _editorScroll,
      expands: true,
      maxLines: null,
      minLines: null,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(
        fontFamily: 'Hurmit Nerd Font',
        fontSize: 14,
        height: 1.45,
      ),
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.all(16),
      ),
      scrollPhysics: const ClampingScrollPhysics(),
    );
    if (note.wrap) return editor;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(width: editorWidth, child: editor),
    );
  }

  Widget _buildAiProposalReviewView(Note note, NoteEditProposal proposal) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final preview = Container(
          color: Theme.of(context).colorScheme.surface,
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            controller: _editorScroll,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: wide
                    ? constraints.maxWidth - 320
                    : constraints.maxWidth - 32,
              ),
              child: MarkdownWithLatex(
                content: _ctrl.text,
                onEditLatexBlock: _editLatexBlockFromPreview,
              ),
            ),
          ),
        );
        final sidebar = _aiProposalSidebar(note, proposal, wide: wide);
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: preview),
              SizedBox(width: 300, child: sidebar),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: preview),
            SizedBox(height: 260, child: sidebar),
          ],
        );
      },
    );
  }

  Widget _aiProposalSidebar(
    Note note,
    NoteEditProposal proposal, {
    required bool wide,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: wide ? EdgeInsets.zero : const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(
          left: wide
              ? BorderSide(color: scheme.outlineVariant)
              : BorderSide.none,
          top: !wide
              ? BorderSide(color: scheme.outlineVariant)
              : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.auto_fix_high, color: scheme.tertiary),
              Text(
                '逐行建议 · ${proposal.blocks.length} 处',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              IconButton(
                tooltip: '收起建议',
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    setState(() => _proposalSidebarExpanded = false),
                icon: const Icon(Icons.close_fullscreen, size: 18),
              ),
              TextButton(
                onPressed: () => _rejectAllProposal(note.id),
                child: const Text('全部拒绝'),
              ),
              FilledButton.tonal(
                onPressed: () => _acceptAllProposal(note, proposal),
                child: const Text('全部接受'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: proposal.blocks.length,
              itemBuilder: (context, index) =>
                  _aiSidebarSuggestion(note, proposal, proposal.blocks[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _proposalBubble(
    Note note,
    NoteEditProposal proposal,
    Size availableSize,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final bubbleSize = _proposalBubbleSize(proposal);
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final current =
                _proposalBubbleOffset ??
                Offset(
                  availableSize.width - bubbleSize.width - 16,
                  availableSize.height - bubbleSize.height - 16,
                );
            _proposalBubbleOffset = _clampProposalBubbleOffset(
              current + details.delta,
              availableSize,
              bubbleSize,
            );
          });
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => setState(() => _proposalSidebarExpanded = true),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_fix_high, color: scheme.tertiary),
                const SizedBox(width: 8),
                Text(
                  '${proposal.blocks.length} 条建议',
                  style: TextStyle(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _aiSidebarSuggestion(
    Note note,
    NoteEditProposal proposal,
    NoteEditBlock block,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final removed = block.deletedLines.isEmpty
        ? null
        : block.deletedLines.join('\n');
    final inserted = block.insertLines.isEmpty
        ? '删除这些行'
        : block.insertLines.join('\n');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '第 ${block.startLine} 行',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                block.deleteCount == 0 ? '插入' : '替换/删除',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              IconButton(
                tooltip: '定位到这一行',
                visualDensity: VisualDensity.compact,
                onPressed: () => _locateProposalLine(block.startLine),
                icon: const Icon(Icons.my_location_outlined, size: 18),
              ),
            ],
          ),
          if (removed != null) ...[
            const SizedBox(height: 8),
            Text(
              '原文',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            _renderProposalSnippet(
              removed,
              wrapCodeBlocks: true,
              style: TextStyle(
                color: scheme.error,
                fontSize: 11,
                height: 1.35,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '建议',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          _renderProposalSnippet(
            inserted,
            wrapCodeBlocks: true,
            style: TextStyle(color: scheme.primary, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _rejectProposalBlock(proposal, block.id),
                child: const Text('拒绝'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _acceptProposalBlock(note, proposal, block),
                child: const Text('接受'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _renderProposalSnippet(
    String text, {
    required TextStyle style,
    required bool wrapCodeBlocks,
  }) {
    if (text.isEmpty) return Text(' ', style: style);
    return DefaultTextStyle.merge(
      style: style,
      child: MarkdownWithLatex(
        content: text,
        selectable: false,
        wrapCodeBlocks: wrapCodeBlocks,
        textStyle: style,
      ),
    );
  }

  void _onEditorTextChanged() {
    final textChanged = _ctrl.text != _trackedEditorText;
    if (textChanged && !_applyingEditHistory) {
      _undoStack.add(
        _NoteEditStep.fromChange(
          beforeText: _trackedEditorText,
          afterText: _ctrl.text,
          beforeSelection: _trackedEditorSelection,
          afterSelection: _ctrl.selection,
        ),
      );
      _redoStack.clear();
    }
    if (textChanged && _showFind) _refreshMatches();
    if (_ctrl.selection.isValid) _lastEditorSelection = _ctrl.selection;
    _trackedEditorText = _ctrl.text;
    _trackedEditorSelection = _ctrl.selection.isValid
        ? _ctrl.selection
        : _lastEditorSelection;
    if (_showLatexPanel) setState(() {});
    if (textChanged && mounted) setState(() {});
  }

  void _refreshLatexPanel() {
    if (_showLatexPanel && mounted) setState(() {});
  }

  Future<void> _save() async {
    final note = _features.getNote(widget.noteId);
    final content = _ctrl.text;
    if (note == null) return;
    if (!_canSave) {
      _lastSavedDraft = content;
      return;
    }
    final revision = await _features.saveNoteContent(
      widget.noteId,
      content,
      baseRevisionId: _activeRevisionId,
    );
    if (!mounted) return;
    _lastSavedDraft = content;
    _activeRevisionId = null;
    if (revision != null) {
      ScaffoldMessenger.of(context).showSnackBar(_shortSnackBar('已保存到时间线'));
    }
    setState(() {});
  }

  bool get _canSave {
    final note = _features.getNote(widget.noteId);
    if (note == null) return false;
    final baseContent = _activeRevisionId == null
        ? note.content
        : _features.getNoteContentAtRevision(widget.noteId, _activeRevisionId);
    return _activeRevisionId != null || _ctrl.text != baseContent;
  }

  bool get _hasUnsavedChanges => _ctrl.text != _lastSavedDraft;

  void _loadEditorSnapshot(String text, {required String? revisionId}) {
    _activeRevisionId = revisionId;
    _lastSavedDraft = text;
    _resetEditorState(text);
  }

  void _resetEditorState(String text) {
    final selection = TextSelection.collapsed(offset: text.length);
    _undoStack = [];
    _redoStack = [];
    _trackedEditorText = text;
    _trackedEditorSelection = selection;
    _lastEditorSelection = selection;
    _ctrl.value = TextEditingValue(text: text, selection: selection);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final step = _undoStack.removeLast();
    _redoStack.add(step);
    _applyEditHistory(step.undo(_ctrl.text), step.beforeSelection);
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final step = _redoStack.removeLast();
    _undoStack.add(step);
    _applyEditHistory(step.redo(_ctrl.text), step.afterSelection);
  }

  void _applyEditHistory(String text, TextSelection selection) {
    _applyingEditHistory = true;
    _ctrl.value = TextEditingValue(text: text, selection: selection);
    _applyingEditHistory = false;
    if (mounted) setState(() {});
  }

  Widget _historyBanner(Note note, NoteRevision revision) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '正在查看 ${_formatNoteTime(revision.savedAt)} 的历史版本，基于它保存会新开分支并切到新分支。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () => _showCompareDialog(
              currentLabel: '当前版本',
              currentText: note.content,
              otherLabel: '历史版本',
              otherText: _ctrl.text,
            ),
            child: const Text('对比'),
          ),
          TextButton(
            onPressed: () {
              _returnToCurrentRevision(note);
            },
            child: const Text('回到当前'),
          ),
        ],
      ),
    );
  }

  Future<void> _openTimeline(Note note) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _NoteTimelineSheet(
        note: note,
        features: _features,
        onOpen: (revision, content) => _openRevisionFromTimeline(
          note: note,
          revision: revision,
          content: content,
        ),
        onCompare: (revision, content) {
          Navigator.pop(context);
          _showCompareDialog(
            currentLabel: '当前版本',
            currentText: note.content,
            otherLabel: _formatNoteTime(revision.savedAt),
            otherText: content,
          );
        },
        onRestore: (revision) => _restoreRevisionFromTimeline(note, revision),
        onCopy: (content) => _copyRevisionContent(content),
        onDuplicate: (revision, content) =>
            _duplicateRevision(note, revision, content),
        onDelete: (revision) => _deleteRevisionFromTimeline(note, revision),
        onDeleteBranches: (revision, branchCount) =>
            _deleteBranchesFromTimeline(note, revision, branchCount),
      ),
    );
  }

  String _diffSummary(String before, String after) {
    return '${_noteDiffSummary(before, after)} · ${_noteLineDiffSummary(before, after)}';
  }

  Future<void> _restoreRevisionFromTimeline(
    Note note,
    NoteRevision revision,
  ) async {
    Navigator.pop(context);
    if (!await _confirmDiscardUnsavedChanges()) return;
    if (!mounted) return;
    final restored = await _features.restoreNoteRevision(note.id, revision.id);
    if (!mounted || restored == null) return;
    final content = _features.getNoteContentAtRevision(note.id, restored.id);
    setState(() => _loadEditorSnapshot(content, revisionId: null));
    ScaffoldMessenger.of(context).showSnackBar(_shortSnackBar('已恢复为当前版本'));
  }

  Future<void> _copyRevisionContent(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(_shortSnackBar('版本内容已复制'));
  }

  Future<void> _duplicateRevision(
    Note note,
    NoteRevision revision,
    String content,
  ) async {
    final title = '${note.title} ${_formatNoteTime(revision.savedAt)}';
    final id = await _features.addNoteWithContent(
      title,
      content,
      folderId: note.folderId,
    );
    if (!mounted) return;
    widget.onEditingChanged(false);
    Navigator.pop(context);
    widget.onSelectNote(id);
    ScaffoldMessenger.of(context).showSnackBar(_shortSnackBar('已另存为新笔记'));
  }

  Future<void> _deleteRevisionFromTimeline(
    Note note,
    NoteRevision revision,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除版本？'),
        content: const Text('删除此版本会同时删除基于它的分支版本，当前路径上的版本不能删除。'),
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
    if (ok != true) return;
    final deleted = await _features.deleteNoteRevision(note.id, revision.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(_shortSnackBar(deleted ? '版本已删除' : '当前路径版本不能删除'));
  }

  Future<void> _deleteBranchesFromTimeline(
    Note note,
    NoteRevision revision,
    int branchCount,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除整条支线？'),
        content: Text(
          '将删除从 ${_formatNoteTime(revision.savedAt)} 分出的 $branchCount 个非当前路径版本，当前路径会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除支线'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await _features.deleteNoteBranchesFromRevision(
      note.id,
      revision.id,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      _shortSnackBar(deleted > 0 ? '已删除 $deleted 个支线版本' : '没有可删除的支线'),
    );
  }

  Future<void> _showCompareDialog({
    required String currentLabel,
    required String currentText,
    required String otherLabel,
    required String otherText,
  }) {
    final diffLines = _buildDiffLines(otherText, currentText);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('版本对比'),
        content: SizedBox(
          width: 820,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$otherLabel -> $currentLabel'),
                const SizedBox(height: 8),
                Text(_diffSummary(otherText, currentText)),
                const SizedBox(height: 4),
                Text(
                  _lineChangeDetail(otherText, currentText),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                _diffLegend(otherLabel: otherLabel, currentLabel: currentLabel),
                const SizedBox(height: 8),
                _diffView(diffLines),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _lineChangeDetail(String before, String after) {
    final stats = _noteDiffStats(before, after);
    if (!stats.hasChanges) return '行级变化：无';
    return '行级变化：新增 ${stats.addedLines} 行，删除 ${stats.removedLines} 行';
  }

  List<_DiffLine> _buildDiffLines(String before, String after) {
    final beforeLines = before.split('\n');
    final afterLines = after.split('\n');
    final n = beforeLines.length;
    final m = afterLines.length;
    final maxCells = 60000;
    if (n * m > maxCells) {
      return _fallbackDiffLines(beforeLines, afterLines);
    }
    final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        dp[i][j] = beforeLines[i] == afterLines[j]
            ? dp[i + 1][j + 1] + 1
            : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
      }
    }
    final lines = <_DiffLine>[];
    var i = 0;
    var j = 0;
    while (i < n && j < m) {
      if (beforeLines[i] == afterLines[j]) {
        lines.add(
          _DiffLine(
            type: _DiffLineType.context,
            beforeLine: i + 1,
            afterLine: j + 1,
            text: beforeLines[i],
          ),
        );
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        lines.add(
          _DiffLine(
            type: _DiffLineType.removed,
            beforeLine: i + 1,
            afterLine: null,
            text: beforeLines[i],
          ),
        );
        i++;
      } else {
        lines.add(
          _DiffLine(
            type: _DiffLineType.added,
            beforeLine: null,
            afterLine: j + 1,
            text: afterLines[j],
          ),
        );
        j++;
      }
    }
    while (i < n) {
      lines.add(
        _DiffLine(
          type: _DiffLineType.removed,
          beforeLine: i + 1,
          afterLine: null,
          text: beforeLines[i],
        ),
      );
      i++;
    }
    while (j < m) {
      lines.add(
        _DiffLine(
          type: _DiffLineType.added,
          beforeLine: null,
          afterLine: j + 1,
          text: afterLines[j],
        ),
      );
      j++;
    }
    return lines;
  }

  List<_DiffLine> _fallbackDiffLines(
    List<String> beforeLines,
    List<String> afterLines,
  ) {
    final lines = <_DiffLine>[];
    final shared = beforeLines.length < afterLines.length
        ? beforeLines.length
        : afterLines.length;
    for (var i = 0; i < shared; i++) {
      if (beforeLines[i] == afterLines[i]) {
        lines.add(
          _DiffLine(
            type: _DiffLineType.context,
            beforeLine: i + 1,
            afterLine: i + 1,
            text: beforeLines[i],
          ),
        );
      } else {
        lines.add(
          _DiffLine(
            type: _DiffLineType.removed,
            beforeLine: i + 1,
            afterLine: null,
            text: beforeLines[i],
          ),
        );
        lines.add(
          _DiffLine(
            type: _DiffLineType.added,
            beforeLine: null,
            afterLine: i + 1,
            text: afterLines[i],
          ),
        );
      }
    }
    for (var i = shared; i < beforeLines.length; i++) {
      lines.add(
        _DiffLine(
          type: _DiffLineType.removed,
          beforeLine: i + 1,
          afterLine: null,
          text: beforeLines[i],
        ),
      );
    }
    for (var i = shared; i < afterLines.length; i++) {
      lines.add(
        _DiffLine(
          type: _DiffLineType.added,
          beforeLine: null,
          afterLine: i + 1,
          text: afterLines[i],
        ),
      );
    }
    return lines;
  }

  Widget _diffLegend({
    required String otherLabel,
    required String currentLabel,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _diffLegendChip('-', otherLabel, scheme.errorContainer, scheme.error),
        _diffLegendChip(
          '+',
          currentLabel,
          scheme.primaryContainer,
          scheme.primary,
        ),
        _diffLegendChip(
          ' ',
          '未改上下文',
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      ],
    );
  }

  Widget _diffLegendChip(String sign, String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$sign $label',
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _diffView(List<_DiffLine> lines) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                _diffHeaderCell('旧行', 56),
                _diffHeaderCell('新行', 56),
                const Expanded(
                  child: Text(
                    '内容',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: lines.length,
              itemBuilder: (context, index) => _diffRow(lines[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _diffHeaderCell(String label, double width) {
    return SizedBox(
      width: width,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _diffRow(_DiffLine line) {
    final scheme = Theme.of(context).colorScheme;
    final rowStyle = switch (line.type) {
      _DiffLineType.added => (
        scheme.primaryContainer.withValues(alpha: 0.42),
        scheme.primary,
        '+',
      ),
      _DiffLineType.removed => (
        scheme.errorContainer.withValues(alpha: 0.42),
        scheme.error,
        '-',
      ),
      _DiffLineType.context => (scheme.surface, scheme.onSurfaceVariant, ' '),
    };
    return Container(
      color: rowStyle.$1,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              line.beforeLine?.toString() ?? '',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontFamily: 'Hurmit Nerd Font',
                fontSize: 12,
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              line.afterLine?.toString() ?? '',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontFamily: 'Hurmit Nerd Font',
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${rowStyle.$3} ${line.text.isEmpty ? ' ' : line.text}',
              style: TextStyle(
                color: rowStyle.$2,
                fontFamily: 'Hurmit Nerd Font',
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _returnToCurrentRevision(Note note) async {
    if (!await _confirmDiscardUnsavedChanges()) return;
    if (!mounted) return;
    setState(() => _loadEditorSnapshot(note.content, revisionId: null));
  }

  Future<void> _acceptProposalBlock(
    Note note,
    NoteEditProposal proposal,
    NoteEditBlock block,
  ) async {
    await _applyProposalBlocks(note, proposal, [block]);
  }

  void _locateProposalLine(int lineNumber) {
    final offset = _offsetForLine(lineNumber);
    if (widget.editing) {
      setState(() {
        _ctrl.selection = TextSelection.collapsed(offset: offset);
        _lastEditorSelection = _ctrl.selection;
        _trackedEditorSelection = _ctrl.selection;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToOffset(offset);
      if (widget.editing) _editorFocus.requestFocus();
    });
  }

  Future<void> _acceptAllProposal(Note note, NoteEditProposal proposal) async {
    await _applyProposalBlocks(note, proposal, proposal.blocks);
  }

  Future<void> _applyProposalBlocks(
    Note note,
    NoteEditProposal proposal,
    List<NoteEditBlock> blocks,
  ) async {
    if (blocks.isEmpty) return;
    final latestNote = _features.getNote(note.id);
    if (latestNote == null) return;
    final currentText = _ctrl.text;
    final editorHash = _contentHash(currentText);
    final latestHash = _contentHash(latestNote.content);
    if (editorHash != proposal.baseContentHash ||
        latestHash != proposal.baseContentHash) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(_shortSnackBar('笔记内容已变化，请让 AI 重新生成修改建议'));
      _features.removeNoteEditProposal(note.id);
      return;
    }
    final next = _applyProposalBlocksToText(currentText, blocks);
    if (next == null) {
      ScaffoldMessenger.of(context).showSnackBar(_shortSnackBar('修改建议行号已失效'));
      _features.removeNoteEditProposal(note.id);
      return;
    }
    final revision = await _features.saveNoteContent(
      note.id,
      next,
      baseRevisionId: proposal.baseRevisionId,
    );
    if (!mounted) return;
    final acceptedIds = blocks.map((block) => block.id).toSet();
    final remaining = proposal.blocks
        .where((block) => !acceptedIds.contains(block.id))
        .toList();
    if (remaining.isEmpty) {
      _features.removeNoteEditProposal(note.id);
    } else {
      _features.setNoteEditProposal(
        proposal.copyWith(
          baseRevisionId: revision?.id ?? note.currentRevisionId,
          baseContentHash: _contentHash(next),
          createdAt: DateTime.now(),
          blocks: remaining.map((block) {
            final shift = _proposalLineShift(blocks, block.startLine);
            return NoteEditBlock(
              id: block.id,
              startLine: block.startLine + shift,
              deleteCount: block.deleteCount,
              deletedLines: block.deletedLines,
              insertLines: block.insertLines,
            );
          }).toList(),
        ),
      );
    }
    setState(() => _loadEditorSnapshot(next, revisionId: null));
    ScaffoldMessenger.of(context).showSnackBar(
      _shortSnackBar(revision == null ? '建议没有产生新修改' : '已接受建议并保存到时间线'),
    );
  }

  void _queueExternalNoteSyncIfNeeded(Note note, {required bool hasProposal}) {
    if (_activeRevisionId != null || hasProposal || _hasUnsavedChanges) {
      _pendingExternalSyncContent = null;
      return;
    }
    if (note.content == _lastSavedDraft) {
      _pendingExternalSyncContent = null;
      return;
    }
    if (_pendingExternalSyncContent == note.content) return;
    _pendingExternalSyncContent = note.content;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final latestNote = _features.getNote(widget.noteId);
      if (latestNote == null ||
          latestNote.content != _pendingExternalSyncContent) {
        return;
      }
      _pendingExternalSyncContent = null;
      setState(() => _loadEditorSnapshot(latestNote.content, revisionId: null));
    });
  }

  void _rejectProposalBlock(NoteEditProposal proposal, String blockId) {
    final remaining = proposal.blocks
        .where((block) => block.id != blockId)
        .toList();
    if (remaining.isEmpty) {
      _features.removeNoteEditProposal(proposal.noteId);
      return;
    }
    _features.setNoteEditProposal(proposal.copyWith(blocks: remaining));
  }

  void _rejectAllProposal(String noteId) {
    _features.removeNoteEditProposal(noteId);
  }

  String? _applyProposalBlocksToText(
    String content,
    List<NoteEditBlock> blocks,
  ) {
    final lines = content.isEmpty ? [''] : content.split('\n');
    final sorted = [...blocks]
      ..sort((a, b) => b.startLine.compareTo(a.startLine));
    var previousStart = lines.length + 1;
    for (final block in sorted) {
      final start = block.startLine - 1;
      final end = start + block.deleteCount;
      if (block.startLine < 1 || start > lines.length || end > lines.length) {
        return null;
      }
      if (end > previousStart - 1) return null;
      lines.replaceRange(start, end, block.insertLines);
      previousStart = block.startLine;
    }
    return lines.join('\n');
  }

  int _proposalLineShift(List<NoteEditBlock> accepted, int line) {
    var shift = 0;
    for (final block in accepted) {
      if (block.startLine >= line) continue;
      shift += block.insertLines.length - block.deleteCount;
    }
    return shift;
  }

  String _contentHash(String content) {
    return sha256.convert(utf8.encode(content)).toString();
  }

  int _offsetForLine(int lineNumber) {
    if (lineNumber <= 1) return 0;
    final text = _ctrl.text;
    var currentLine = 1;
    for (var i = 0; i < text.length; i++) {
      if (currentLine >= lineNumber) return i;
      if (text.codeUnitAt(i) == 10) currentLine++;
    }
    return text.length;
  }

  Size _proposalBubbleSize(NoteEditProposal proposal) {
    final digits = proposal.blocks.length.toString().length;
    return Size(88 + digits * 12, 48);
  }

  Offset _clampProposalBubbleOffset(
    Offset offset,
    Size availableSize,
    Size bubbleSize,
  ) {
    final maxX = (availableSize.width - bubbleSize.width).clamp(
      0.0,
      double.infinity,
    );
    final maxY = (availableSize.height - bubbleSize.height).clamp(
      0.0,
      double.infinity,
    );
    return Offset(offset.dx.clamp(0.0, maxX), offset.dy.clamp(0.0, maxY));
  }

  Future<void> _openRevisionFromTimeline({
    required Note note,
    required NoteRevision revision,
    required String content,
  }) async {
    Navigator.pop(context);
    if (!await _confirmDiscardUnsavedChanges()) return;
    if (!mounted) return;
    final revisionId = revision.id == note.currentRevisionId
        ? null
        : revision.id;
    setState(() => _loadEditorSnapshot(content, revisionId: revisionId));
  }

  Future<bool> _confirmDiscardUnsavedChanges() async {
    if (!_hasUnsavedChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未保存修改？'),
        content: const Text('当前修改还没有保存到时间线，继续会丢失这些修改。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Widget _editorToolbar(Note note) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            _toolButton(
              Icons.format_bold,
              '粗体',
              () => _wrapSelection('**', placeholder: '粗体'),
            ),
            _toolButton(
              Icons.format_italic,
              '斜体',
              () => _wrapSelection('*', placeholder: '斜体'),
            ),
            _toolButton(
              Icons.format_strikethrough,
              '删除线',
              () => _wrapSelection('~~', placeholder: '删除线'),
            ),
            _toolButton(
              Icons.code,
              '行内代码',
              () => _wrapSelection('`', placeholder: 'code'),
            ),
            _toolDivider(),
            _toolButton(Icons.title, '标题', () => _prefixLines('## ')),
            _toolButton(
              Icons.format_list_bulleted,
              '无序列表',
              () => _prefixLines('- '),
            ),
            _toolButton(
              Icons.format_list_numbered,
              '有序列表',
              _numberSelectionLines,
            ),
            _toolButton(
              Icons.check_box_outlined,
              '任务列表',
              () => _prefixLines('- [ ] '),
            ),
            _toolButton(Icons.format_quote, '引用', () => _prefixLines('> ')),
            _toolDivider(),
            _toolButton(Icons.data_object, '代码块', _insertCodeBlock),
            _toolButton(Icons.table_chart_outlined, '表格', _insertTable),
            _toolButton(
              Icons.horizontal_rule,
              '分割线',
              () => _insertText('\n---\n'),
            ),
            _toolButton(Icons.link, '链接', _insertLink),
            _toolButton(Icons.image_outlined, '图片', _insertImage),
            _toolDivider(),
            _toolButton(Icons.functions, 'LaTeX 行内公式', _insertInlineLatex),
            _toolButton(
              Icons.calculate_outlined,
              'LaTeX 块公式',
              _insertBlockLatex,
            ),
            _toolButton(Icons.science_outlined, 'LaTeX 工具', _toggleLatexPanel),
            _toolDivider(),
            _toolButton(Icons.find_replace, '查找 / 替换', _openFind),
            _toolButton(Icons.low_priority, '跳转行', _showGoToLineDialog),
            _toolButton(
              note.wrap ? Icons.wrap_text : Icons.short_text,
              note.wrap ? '关闭自动换行' : '开启自动换行',
              () => _features.updateNote(note.copyWith(wrap: !note.wrap)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }

  Widget _toolDivider() {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }

  Widget _latexPanel() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Color.lerp(scheme.surface, scheme.tertiaryContainer, 0.18),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 310),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: scheme.outlineVariant),
            bottom: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.functions, color: scheme.tertiary),
                      const SizedBox(width: 8),
                      Text(
                        'LaTeX 编辑器',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: _insertInlineLatex,
                    icon: const Icon(Icons.short_text),
                    label: const Text('行内'),
                  ),
                  TextButton.icon(
                    onPressed: _insertBlockLatex,
                    icon: const Icon(Icons.view_agenda_outlined),
                    label: const Text('块级'),
                  ),
                  TextButton.icon(
                    onPressed: _editCurrentLatexFormula,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('编辑当前公式'),
                  ),
                  IconButton(
                    tooltip: '关闭 LaTeX 工具',
                    icon: const Icon(Icons.close),
                    onPressed: _toggleLatexPanel,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) => _latexPreview(_latexPreviewSource),
              ),
              const SizedBox(height: 8),
              _latexPalette('结构', _latexStructures),
              _latexPalette('希腊', _latexGreek),
              _latexPalette('运算', _latexOperators),
              _latexPalette('关系', _latexRelations),
              _latexPalette('箭头', _latexArrows),
            ],
          ),
        ),
      ),
    );
  }

  Widget _latexPreview(String source) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            source.isEmpty ? '选中公式或把光标放在公式内可即时预览' : source,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Hurmit Nerd Font',
              fontSize: 12,
              color: source.isEmpty
                  ? scheme.onSurfaceVariant
                  : scheme.onSurfaceVariant,
            ),
          ),
          if (source.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Math.tex(
                source,
                mathStyle: MathStyle.display,
                textStyle: TextStyle(fontSize: 20, color: scheme.onSurface),
                onErrorFallback: (_) => Text(
                  'LaTeX 语法错误：请检查括号、命令或环境是否闭合',
                  style: TextStyle(
                    color: scheme.error,
                    fontSize: 12,
                    fontFamily: 'Hurmit Nerd Font',
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _latexPalette(String title, List<_LatexSnippet> snippets) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final snippet in snippets)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(snippet.label),
                  tooltip: snippet.source,
                  onPressed: () => _insertLatexSnippet(snippet),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _findReplaceBar() {
    final scheme = Theme.of(context).colorScheme;
    final matchText = _matches.isEmpty
        ? '无匹配'
        : '${_currentMatch + 1}/${_matches.length}';
    final controls = Wrap(
      spacing: 2,
      runSpacing: 2,
      alignment: WrapAlignment.end,
      children: [
        IconButton(
          tooltip: '上一个',
          icon: const Icon(Icons.keyboard_arrow_up),
          onPressed: _previousMatch,
        ),
        IconButton(
          tooltip: '下一个',
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: _nextMatch,
        ),
        IconButton(
          tooltip: _caseSensitiveFind ? '区分大小写' : '不区分大小写',
          icon: Icon(
            Icons.text_fields,
            color: _caseSensitiveFind ? scheme.primary : null,
          ),
          onPressed: () {
            setState(() => _caseSensitiveFind = !_caseSensitiveFind);
            _refreshMatches();
          },
        ),
        IconButton(
          tooltip: _regexFind ? '正则匹配' : '普通匹配',
          icon: Icon(
            Icons.data_object,
            color: _regexFind ? scheme.primary : null,
          ),
          onPressed: () {
            setState(() => _regexFind = !_regexFind);
            _refreshMatches();
          },
        ),
        IconButton(
          tooltip: _showReplace ? '隐藏替换' : '显示替换',
          icon: const Icon(Icons.swap_horiz),
          onPressed: () => setState(() => _showReplace = !_showReplace),
        ),
        IconButton(
          tooltip: '关闭',
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => _showFind = false),
        ),
      ],
    );
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _findCtrl,
                    focusNode: _findFocus,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: _regexFind ? '查找正则' : '查找',
                      prefixIcon: const Icon(Icons.search),
                      suffixText: matchText,
                      errorText: _findError,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _nextMatch(),
                  ),
                ),
                controls,
              ],
            ),
            if (_showReplace) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replaceCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: '替换为',
                        prefixIcon: Icon(Icons.edit_note),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _replaceCurrent(),
                    ),
                  ),
                  TextButton(
                    onPressed: _replaceCurrent,
                    child: const Text('替换'),
                  ),
                  TextButton(onPressed: _replaceAll, child: const Text('全部替换')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _editorStatus(Note note) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final currentText = _ctrl.text;
        final currentSelection = _ctrl.selection;
        final lineCount = currentText.isEmpty
            ? 1
            : '\n'.allMatches(currentText).length + 1;
        final currentLine = _lineForOffset(
          currentSelection.baseOffset < 0 ? 0 : currentSelection.baseOffset,
        );
        final currentColumn = _columnForOffset(
          currentSelection.baseOffset < 0 ? 0 : currentSelection.baseOffset,
        );
        final currentWords = RegExp(
          r'[^\s]+',
        ).allMatches(currentText.trim()).length;
        final saved = currentText == _lastSavedDraft;
        final viewLabel = _activeRevisionId == null ? '当前' : '历史';
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$viewLabel · 行 $currentLine/$lineCount · 列 $currentColumn · 字符 ${currentText.length} · 词 $currentWords · ${note.wrap ? '自动换行' : '横向滚动'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                saved ? '已保存' : '编辑中',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: saved
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openFind() {
    if (!widget.editing) {
      widget.onEditingChanged(true);
    }
    setState(() {
      _showFind = true;
      _showReplace = _showReplace || _findCtrl.text.isNotEmpty;
    });
    final selected = _selectedText;
    if (selected.isNotEmpty && !selected.contains('\n')) {
      _findCtrl.text = selected;
      _findCtrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: selected.length,
      );
    }
    _refreshMatches();
    _findFocus.requestFocus();
  }

  void _refreshMatches() {
    final query = _findCtrl.text;
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _matches = [];
          _currentMatch = -1;
          _findError = null;
        });
      }
      return;
    }
    final matcher = _regexFind
        ? _SearchMatcher.regex(query, caseSensitive: _caseSensitiveFind)
        : _SearchMatcher.literal(query, caseSensitive: _caseSensitiveFind);
    final matches = matcher
        .allMatches(_ctrl.text)
        .where((match) => match.end > match.start)
        .map((match) => TextRange(start: match.start, end: match.end))
        .toList();
    var current = matches.indexWhere((range) {
      final offset = _ctrl.selection.baseOffset;
      return offset >= range.start && offset <= range.end;
    });
    if (current == -1 && matches.isNotEmpty) current = 0;
    if (!mounted) return;
    setState(() {
      _matches = matches;
      _currentMatch = current;
      _findError = matcher.hasError ? '正则表达式无效' : null;
    });
  }

  void _nextMatch() => _selectMatch(_currentMatch + 1);

  void _previousMatch() => _selectMatch(_currentMatch - 1);

  void _selectMatch(int index) {
    if (_matches.isEmpty) return;
    if (!widget.editing) {
      widget.onEditingChanged(true);
    }
    final next = index % _matches.length;
    final normalized = next < 0 ? next + _matches.length : next;
    final match = _matches[normalized];
    setState(() => _currentMatch = normalized);
    _ctrl.selection = TextSelection(
      baseOffset: match.start,
      extentOffset: match.end,
    );
    _scrollToOffset(match.start);
    _editorFocus.requestFocus();
  }

  void _replaceCurrent() {
    final index = _matchIndexAtCursor();
    if (index < 0 || index >= _matches.length) return;
    final match = _matches[index];
    _replaceRange(match.start, match.end, _replaceCtrl.text);
    _refreshMatches();
    if (_matches.isNotEmpty) {
      _selectMatch(index.clamp(0, _matches.length - 1));
    }
  }

  void _replaceAll() {
    if (_matches.isEmpty) return;
    final replacement = _replaceCtrl.text;
    final buffer = StringBuffer();
    var cursor = 0;
    for (final match in _matches) {
      buffer
        ..write(_ctrl.text.substring(cursor, match.start))
        ..write(replacement);
      cursor = match.end;
    }
    buffer.write(_ctrl.text.substring(cursor));
    final count = _matches.length;
    _setText(buffer.toString(), TextSelection.collapsed(offset: buffer.length));
    _refreshMatches();
    ScaffoldMessenger.of(context).showSnackBar(_shortSnackBar('已替换 $count 处'));
  }

  Future<void> _showGoToLineDialog() async {
    final ctrl = TextEditingController();
    final line = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转到行'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '行号'),
          onSubmitted: (_) => Navigator.pop(ctx, int.tryParse(ctrl.text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)),
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (line == null || line < 1) return;
    _goToLine(line);
  }

  void _goToLine(int line) {
    final lines = _ctrl.text.split('\n');
    final targetLine = line.clamp(1, lines.length);
    var offset = 0;
    for (var i = 0; i < targetLine - 1; i++) {
      offset += lines[i].length + 1;
    }
    _ctrl.selection = TextSelection.collapsed(offset: offset);
    _scrollToOffset(offset);
    _editorFocus.requestFocus();
  }

  void _wrapSelection(String marker, {String placeholder = ''}) {
    _wrapSelectionWith(marker, marker, placeholder: placeholder);
  }

  void _wrapSelectionWith(
    String before,
    String after, {
    String placeholder = '',
  }) {
    final selection = _normalizedSelection;
    final selected = selection.isCollapsed
        ? placeholder
        : _ctrl.text.substring(selection.start, selection.end);
    final replacement = '$before$selected$after';
    _replaceRange(
      selection.start,
      selection.end,
      replacement,
      TextSelection(
        baseOffset: selection.start + before.length,
        extentOffset: selection.start + before.length + selected.length,
      ),
    );
  }

  void _prefixLines(String prefix) {
    final range = _expandedLineRange;
    final selected = _ctrl.text.substring(range.start, range.end);
    final replacement = selected
        .split('\n')
        .map(
          (line) => line.startsWith(prefix)
              ? line.substring(prefix.length)
              : '$prefix$line',
        )
        .join('\n');
    _replaceRange(range.start, range.end, replacement);
  }

  void _numberSelectionLines() {
    final range = _expandedLineRange;
    final lines = _ctrl.text.substring(range.start, range.end).split('\n');
    final numbered = <String>[];
    for (var i = 0; i < lines.length; i++) {
      numbered.add(
        '${i + 1}. ${lines[i].replaceFirst(RegExp(r'^\d+\.\s*'), '')}',
      );
    }
    _replaceRange(range.start, range.end, numbered.join('\n'));
  }

  void _insertCodeBlock() {
    _wrapSelectionWith('\n```\n', '\n```\n', placeholder: 'code');
  }

  void _toggleLatexPanel() {
    setState(() => _showLatexPanel = !_showLatexPanel);
    if (_showLatexPanel) _editorFocus.requestFocus();
  }

  Future<void> _insertInlineLatex() =>
      _insertLatexWithEditor(preferBlock: false);

  Future<void> _insertBlockLatex() => _insertLatexWithEditor(preferBlock: true);

  Future<void> _editCurrentLatexFormula() async {
    final segment = _currentLatexSegment;
    if (segment == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(_shortSnackBar('请先选中公式或把光标放到公式内'));
      return;
    }
    final edited = await _openLatexFormulaEditor(
      title: '编辑公式',
      initialFormula: segment.formula,
      preferBlock: _isBlockLatex(segment.source),
    );
    if (edited == null) return;
    _replaceRange(
      segment.start,
      segment.end,
      _wrapLatexFormula(edited, segment.source),
    );
  }

  Future<void> _insertLatexWithEditor({required bool preferBlock}) async {
    final formula = await _openLatexFormulaEditor(
      title: preferBlock ? '插入块级公式' : '插入行内公式',
      initialFormula: '',
      preferBlock: preferBlock,
    );
    if (formula == null) return;
    final wrapped = preferBlock ? '\n\$\$\n$formula\n\$\$\n' : '\$$formula\$';
    _replaceSelection(wrapped);
  }

  void _insertLatexSnippet(_LatexSnippet snippet) {
    final selection = _normalizedSelection;
    final selected = selection.isCollapsed
        ? 'x'
        : _ctrl.text.substring(selection.start, selection.end);
    final replacement = snippet.source.replaceAll(_latexPlaceholder, selected);
    final placeholderStart = snippet.source.indexOf(_latexPlaceholder);
    final selectionStart = placeholderStart == -1
        ? selection.start + replacement.length
        : selection.start + placeholderStart;
    final selectionEnd = selectionStart + selected.length;
    _replaceRange(
      selection.start,
      selection.end,
      replacement,
      TextSelection(baseOffset: selectionStart, extentOffset: selectionEnd),
    );
  }

  void _insertTable() {
    _insertText('\n| 列 1 | 列 2 |\n| --- | --- |\n| 内容 | 内容 |\n');
  }

  void _insertLink() {
    final selected = _selectedText;
    final text = selected.isEmpty ? '链接文字' : selected;
    _replaceSelection('[$text](https://)');
  }

  void _insertImage() {
    final selected = _selectedText;
    final text = selected.isEmpty ? '图片描述' : selected;
    _replaceSelection('![$text](https://)');
  }

  void _insertText(String text) => _replaceSelection(text);

  void _replaceSelection(String replacement) {
    final selection = _normalizedSelection;
    _replaceRange(selection.start, selection.end, replacement);
  }

  void _replaceRange(
    int start,
    int end,
    String replacement, [
    TextSelection? selection,
  ]) {
    final next = _ctrl.text.replaceRange(start, end, replacement);
    _setText(
      next,
      selection ?? TextSelection.collapsed(offset: start + replacement.length),
    );
    _editorFocus.requestFocus();
  }

  void _setText(String text, TextSelection selection) {
    _ctrl.value = TextEditingValue(text: text, selection: selection);
  }

  void _scrollToOffset(int offset) {
    if (!_editorScroll.hasClients) return;
    final line = _lineForOffset(offset);
    final target = ((line - 1) * 22.0).clamp(
      0.0,
      _editorScroll.position.maxScrollExtent,
    );
    _editorScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  TextSelection get _normalizedSelection {
    final selection = _ctrl.selection.isValid
        ? _ctrl.selection
        : _lastEditorSelection;
    if (!selection.isValid) {
      return TextSelection.collapsed(offset: _ctrl.text.length);
    }
    final start = selection.start.clamp(0, _ctrl.text.length);
    final end = selection.end.clamp(0, _ctrl.text.length);
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  TextRange get _expandedLineRange {
    final selection = _normalizedSelection;
    final text = _ctrl.text;
    var start = selection.start;
    var end = selection.end;
    while (start > 0 && text.codeUnitAt(start - 1) != 10) {
      start--;
    }
    while (end < text.length && text.codeUnitAt(end) != 10) {
      end++;
    }
    return TextRange(start: start, end: end);
  }

  String get _selectedText {
    final selection = _normalizedSelection;
    if (selection.isCollapsed) return '';
    return _ctrl.text.substring(selection.start, selection.end);
  }

  int _lineForOffset(int offset) {
    final safeOffset = offset.clamp(0, _ctrl.text.length);
    return '\n'.allMatches(_ctrl.text.substring(0, safeOffset)).length + 1;
  }

  int _columnForOffset(int offset) {
    final safeOffset = offset.clamp(0, _ctrl.text.length);
    final lineStart = _ctrl.text.lastIndexOf(
      '\n',
      safeOffset == 0 ? 0 : safeOffset - 1,
    );
    return safeOffset - lineStart;
  }

  String get _latexPreviewSource {
    return _currentLatexSegment?.formula ?? '';
  }

  _LatexSegment? get _currentLatexSegment {
    final selected = _selectedText.trim();
    if (selected.isNotEmpty) {
      final source = _stripLatexDelimiters(selected);
      if (source.isNotEmpty && _shouldPreviewLatexSource(selected)) {
        final selection = _normalizedSelection;
        return _LatexSegment(selection.start, selection.end, selected, source);
      }
    }
    final selection = _normalizedSelection;
    return _latexSegmentAt(selection.baseOffset);
  }

  _LatexSegment? _latexSegmentAt(int offset) {
    final text = _ctrl.text;
    if (text.isEmpty) return null;
    final safeOffset = offset.clamp(0, text.length);
    final blockRanges = <_LatexSegment>[
      ..._latexSegments(text, RegExp(r'\$\$(.+?)\$\$', dotAll: true)),
      ..._latexSegments(text, RegExp(r'\\\[(.+?)\\\]', dotAll: true)),
    ];
    final ranges = <_LatexSegment>[
      ...blockRanges,
      ..._latexSegments(text, RegExp(r'\\\((.+?)\\\)')),
      ..._inlineLatexRanges(text, blockRanges),
    ];
    ranges.sort((a, b) {
      final aContains = safeOffset >= a.start && safeOffset <= a.end;
      final bContains = safeOffset >= b.start && safeOffset <= b.end;
      if (aContains != bContains) return aContains ? -1 : 1;
      return (a.end - a.start).compareTo(b.end - b.start);
    });
    for (final range in ranges) {
      if (safeOffset >= range.start &&
          safeOffset <= range.end &&
          _shouldPreviewLatexSource(range.source)) {
        return range;
      }
    }
    return null;
  }

  bool _shouldPreviewLatexSource(String source) {
    if (source.startsWith(r'$$')) return true;
    if (source.startsWith(r'\[') || source.startsWith(r'\(')) return true;
    return LatexRenderer.hasLatexContent(source);
  }

  List<_LatexSegment> _latexSegments(String text, RegExp pattern) {
    return pattern
        .allMatches(text)
        .map(
          (match) => _LatexSegment(
            match.start,
            match.end,
            match.group(0) ?? '',
            _stripLatexDelimiters(match.group(0) ?? ''),
          ),
        )
        .toList();
  }

  List<_LatexSegment> _inlineLatexRanges(
    String text,
    List<_LatexSegment> blockRanges,
  ) {
    return RegExp(r'\$(.+?)\$')
        .allMatches(text)
        .where(
          (match) => !blockRanges.any((range) {
            return match.start >= range.start && match.end <= range.end;
          }),
        )
        .map(
          (match) => _LatexSegment(
            match.start,
            match.end,
            match.group(0) ?? '',
            _stripLatexDelimiters(match.group(0) ?? ''),
          ),
        )
        .toList();
  }

  Future<String?> _openLatexFormulaEditor({
    required String title,
    required String initialFormula,
    required bool preferBlock,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => LatexFormulaEditorPage(
          title: title,
          initialFormula: initialFormula,
          preferBlock: preferBlock,
        ),
      ),
    );
  }

  Future<void> _editLatexBlockFromPreview(
    String source,
    int start,
    int end,
  ) async {
    final edited = await _openLatexFormulaEditor(
      title: '编辑公式',
      initialFormula: _stripLatexDelimiters(source),
      preferBlock: _isBlockLatex(source),
    );
    if (edited == null) return;
    _replaceRange(start, end, _wrapLatexFormula(edited, source));
  }

  int _matchIndexAtCursor() {
    final offset = _ctrl.selection.baseOffset;
    final exactIndex = _matches.indexWhere(
      (range) => offset >= range.start && offset <= range.end,
    );
    if (exactIndex != -1) return exactIndex;
    return _currentMatch;
  }

  bool _isBlockLatex(String source) {
    final trimmed = source.trimLeft();
    return trimmed.startsWith(r'$$') || trimmed.startsWith(r'\[');
  }

  String _wrapLatexFormula(String formula, String originalSource) {
    final trimmed = formula.trim();
    final source = originalSource.trim();
    if (source.startsWith(r'\[') && source.endsWith(r'\]')) {
      return '\\[$trimmed\\]';
    }
    if (source.startsWith(r'\(') && source.endsWith(r'\)')) {
      return '\\($trimmed\\)';
    }
    if (source.startsWith(r'$$') && source.endsWith(r'$$')) {
      return '\$\$\n$trimmed\n\$\$';
    }
    return '\$$trimmed\$';
  }

  String _stripLatexDelimiters(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith(r'$$') && trimmed.endsWith(r'$$')) {
      return trimmed.substring(2, trimmed.length - 2).trim();
    }
    if (trimmed.startsWith(r'\[') && trimmed.endsWith(r'\]')) {
      return trimmed.substring(2, trimmed.length - 2).trim();
    }
    if (trimmed.startsWith(r'\(') && trimmed.endsWith(r'\)')) {
      return trimmed.substring(2, trimmed.length - 2).trim();
    }
    if (trimmed.startsWith(r'$') && trimmed.endsWith(r'$')) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
    return trimmed;
  }

  Future<void> _menu(String value, Note note) async {
    switch (value) {
      case 'save':
        await _save();
      case 'rename':
        await _rename(note);
      case 'find':
        _openFind();
      case 'goto':
        await _showGoToLineDialog();
      case 'latex':
        if (!widget.editing) widget.onEditingChanged(true);
        _toggleLatexPanel();
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
      await _features.updateNote(note.copyWith(title: title));
    }
  }

  Future<void> _export(Note note) async {
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
    final note = _features.getNote(widget.noteId);
    if (note == null) return;
    final images = await _captureNoteImages(note.title, _ctrl.text);
    if (images.isEmpty) return;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    try {
      if (_isDesktopPlatform) {
        final clipboard = SystemClipboard.instance;
        if (clipboard == null) throw Exception('当前平台不支持写入剪贴板');
        final items = <DataWriterItem>[];
        for (var i = 0; i < images.length; i++) {
          final item = DataWriterItem(
            suggestedName: _imageFileName('note', timestamp, i, images.length),
          );
          item.add(Formats.png(images[i]));
          items.add(item);
        }
        await clipboard.write(items);
        if (!mounted) return;
        _showImageSnack(_imageDoneText('笔记图片已复制到剪贴板', images.length));
        return;
      }
      if (Platform.isAndroid || Platform.isIOS) {
        for (var i = 0; i < images.length; i++) {
          final result = await _nativeTools
              .invokeMapMethod<String, dynamic>('saveImageToGallery', {
                'bytes': images[i],
                'fileName': _imageFileName('note', timestamp, i, images.length),
              });
          if (result?['ok'] != true) {
            throw Exception(result?['error'] ?? '保存到图库失败');
          }
        }
        if (!mounted) return;
        _showImageSnack(_imageDoneText('笔记图片已保存到图库', images.length));
        return;
      }
      final dir = await getTemporaryDirectory();
      final files = <XFile>[];
      for (var i = 0; i < images.length; i++) {
        final file = File(
          '${dir.path}/${_imageFileName('note', timestamp, i, images.length)}',
        );
        await file.writeAsBytes(images[i], flush: true);
        files.add(XFile(file.path));
      }
      await SharePlus.instance.share(ShareParams(files: files));
    } catch (e) {
      if (!mounted) return;
      _showImageSnack('导出图片失败: $e');
    }
  }

  Future<void> _shareImage() async {
    final note = _features.getNote(widget.noteId);
    if (note == null) return;
    final images = await _captureNoteImages(note.title, _ctrl.text);
    if (images.isEmpty) return;
    try {
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final files = <XFile>[];
      for (var i = 0; i < images.length; i++) {
        final file = File(
          '${dir.path}/${_imageFileName('note', timestamp, i, images.length)}',
        );
        await file.writeAsBytes(images[i], flush: true);
        files.add(XFile(file.path));
      }
      await SharePlus.instance.share(ShareParams(files: files));
    } catch (e) {
      if (!mounted) return;
      _showImageSnack('分享失败: $e');
    }
  }

  Future<List<Uint8List>> _captureNoteImages(
    String title,
    String content,
  ) async {
    final theme = Theme.of(context);
    final pages = _splitExportText(content);
    final images = <Uint8List>[];
    for (var i = 0; i < pages.length; i++) {
      images.add(
        await _shot.captureFromLongWidget(
          _NoteShareImage(
            title: title,
            content: pages[i],
            seedColor: theme.colorScheme.primary,
            brightness: theme.brightness,
            pageNumber: pages.length == 1 ? null : i + 1,
            pageCount: pages.length == 1 ? null : pages.length,
          ),
          pixelRatio: _exportImagePixelRatio,
          context: context,
          constraints: const BoxConstraints(maxWidth: 720),
        ),
      );
    }
    return images;
  }

  void _showImageSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(_shortSnackBar(message));
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

const _latexPlaceholder = '__LYNAI_LATEX_SELECTION__';

class _LatexSegment {
  final int start;
  final int end;
  final String source;
  final String formula;

  const _LatexSegment(this.start, this.end, this.source, this.formula);
}

class _NoteEditStep {
  final NoteTextDelta delta;
  final TextSelection beforeSelection;
  final TextSelection afterSelection;

  const _NoteEditStep({
    required this.delta,
    required this.beforeSelection,
    required this.afterSelection,
  });

  factory _NoteEditStep.fromChange({
    required String beforeText,
    required String afterText,
    required TextSelection beforeSelection,
    required TextSelection afterSelection,
  }) {
    return _NoteEditStep(
      delta: NoteTextDelta.between(beforeText, afterText),
      beforeSelection: beforeSelection,
      afterSelection: afterSelection,
    );
  }

  String undo(String source) => delta.revert(source);

  String redo(String source) => delta.apply(source);
}

class _LatexSnippet {
  final String label;
  final String source;

  const _LatexSnippet(this.label, this.source);
}

const _latexStructures = [
  _LatexSnippet('分数', r'\frac{__LYNAI_LATEX_SELECTION__}{y}'),
  _LatexSnippet('根号', r'\sqrt{__LYNAI_LATEX_SELECTION__}'),
  _LatexSnippet('n 次根', r'\sqrt[n]{__LYNAI_LATEX_SELECTION__}'),
  _LatexSnippet('上标', r'__LYNAI_LATEX_SELECTION__^{2}'),
  _LatexSnippet('下标', r'__LYNAI_LATEX_SELECTION___{i}'),
  _LatexSnippet('求和', r'\sum_{i=1}^{n} __LYNAI_LATEX_SELECTION__'),
  _LatexSnippet('积分', r'\int_{a}^{b} __LYNAI_LATEX_SELECTION__\,dx'),
  _LatexSnippet('极限', r'\lim_{x \to 0} __LYNAI_LATEX_SELECTION__'),
  _LatexSnippet('向量', r'\vec{__LYNAI_LATEX_SELECTION__}'),
  _LatexSnippet('帽记号', r'\hat{__LYNAI_LATEX_SELECTION__}'),
  _LatexSnippet('横线', r'\overline{__LYNAI_LATEX_SELECTION__}'),
  _LatexSnippet('矩阵 2x2', r'\begin{bmatrix} a & b \\ c & d \end{bmatrix}'),
  _LatexSnippet(
    '分段',
    r'\begin{cases} x^2, & x \ge 0 \\ -x, & x < 0 \end{cases}',
  ),
  _LatexSnippet(
    '对齐',
    r'\begin{aligned} a &= b + c \\ d &= e + f \end{aligned}',
  ),
];

const _latexGreek = [
  _LatexSnippet('α', r'\alpha'),
  _LatexSnippet('β', r'\beta'),
  _LatexSnippet('γ', r'\gamma'),
  _LatexSnippet('δ', r'\delta'),
  _LatexSnippet('ε', r'\epsilon'),
  _LatexSnippet('θ', r'\theta'),
  _LatexSnippet('λ', r'\lambda'),
  _LatexSnippet('μ', r'\mu'),
  _LatexSnippet('π', r'\pi'),
  _LatexSnippet('ρ', r'\rho'),
  _LatexSnippet('σ', r'\sigma'),
  _LatexSnippet('φ', r'\varphi'),
  _LatexSnippet('ω', r'\omega'),
  _LatexSnippet('Γ', r'\Gamma'),
  _LatexSnippet('Δ', r'\Delta'),
  _LatexSnippet('Ω', r'\Omega'),
];

const _latexOperators = [
  _LatexSnippet('×', r'\times'),
  _LatexSnippet('÷', r'\div'),
  _LatexSnippet('±', r'\pm'),
  _LatexSnippet('∓', r'\mp'),
  _LatexSnippet('⋅', r'\cdot'),
  _LatexSnippet('∞', r'\infty'),
  _LatexSnippet('∂', r'\partial'),
  _LatexSnippet('∇', r'\nabla'),
  _LatexSnippet('∫', r'\int'),
  _LatexSnippet('∮', r'\oint'),
  _LatexSnippet('∑', r'\sum'),
  _LatexSnippet('∏', r'\prod'),
  _LatexSnippet('sin', r'\sin'),
  _LatexSnippet('cos', r'\cos'),
  _LatexSnippet('ln', r'\ln'),
];

const _latexRelations = [
  _LatexSnippet('≤', r'\le'),
  _LatexSnippet('≥', r'\ge'),
  _LatexSnippet('≠', r'\ne'),
  _LatexSnippet('≈', r'\approx'),
  _LatexSnippet('≡', r'\equiv'),
  _LatexSnippet('∝', r'\propto'),
  _LatexSnippet('∈', r'\in'),
  _LatexSnippet('∉', r'\notin'),
  _LatexSnippet('⊂', r'\subset'),
  _LatexSnippet('⊆', r'\subseteq'),
  _LatexSnippet('∪', r'\cup'),
  _LatexSnippet('∩', r'\cap'),
];

const _latexArrows = [
  _LatexSnippet('→', r'\to'),
  _LatexSnippet('←', r'\leftarrow'),
  _LatexSnippet('⇒', r'\Rightarrow'),
  _LatexSnippet('⇔', r'\Leftrightarrow'),
  _LatexSnippet('↦', r'\mapsto'),
  _LatexSnippet('↑', r'\uparrow'),
  _LatexSnippet('↓', r'\downarrow'),
];

class _NoteShareImage extends StatelessWidget {
  final String title;
  final String content;
  final Color seedColor;
  final Brightness brightness;
  final int? pageNumber;
  final int? pageCount;

  const _NoteShareImage({
    required this.title,
    required this.content,
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
