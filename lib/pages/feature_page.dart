import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:uuid/uuid.dart';
import 'latex_formula_editor_page.dart';
import 'role_management_page.dart';
import '../models/chat_role.dart';
import '../models/app_settings.dart';
import '../models/conversation.dart';
import '../models/model_config.dart';
import '../models/message.dart';
import '../models/note.dart';
import '../models/plugin.dart';
import '../models/roleplay.dart';
import '../models/schedule_item.dart';
import '../models/todo_list.dart';
import '../providers/conversation_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/roleplay_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../services/roleplay_service.dart';
import '../services/system_scroll_capture_service.dart';
import '../utils/file_share_utils.dart';
import '../utils/file_name_utils.dart';
import '../utils/share_image_utils.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/latex_renderer.dart';
import '../widgets/plugin_feature_webview.dart';
import '../widgets/plugin_icon.dart';
import '../services/storage_v2_service.dart';
part 'features/shared.dart';
part 'features/feature_shell.dart';
part 'features/dashboard.dart';
part 'features/schedule_page.dart';
part 'features/notes_page.dart';
part 'features/todo_lists_page.dart';
part 'features/note_detail_page.dart';
part 'features/roleplay_page.dart';
part 'features/plugin_feature_page.dart';

const _exportImagePixelRatio = 2.5;
const _exportTextChunkLength = 2800;
const _exportTodoPageWeight = 3200;
const _exportTodoItemChunkLength = 1200;

/// 搜索匹配器。
///
/// 支持字面搜索、正则搜索（`re:` 前缀或 `/pattern/flags` 语法），
/// 提供 [matches] 和 [allMatches] 两个查询接口。
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

/// 解析后的正则搜索参数。
///
/// 包含正则模式字符串及大小写敏感性标志。
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

/// 功能页 shell。
///
/// 根据 `AppSettings.lastFeature` 在历史、日程、笔记和待办之间切换。子页面
/// 拆成 `part` 文件，但共享搜索语法、导出工具和若干内部组件。
class FeaturePage extends StatefulWidget {
  final void Function(String conversationId) onConversationTap;
  final VoidCallback onRoleChanged;
  final void Function(bool Function() handler)? onBackHandlerChanged;
  final void Function(Future<void> Function() handler)?
  onDashboardHandlerChanged;

  const FeaturePage({
    super.key,
    required this.onConversationTap,
    required this.onRoleChanged,
    this.onBackHandlerChanged,
    this.onDashboardHandlerChanged,
  });

  @override
  State<FeaturePage> createState() => _FeaturePageState();
}

class _FeaturePageState extends State<FeaturePage> {
  static const _dashboardFeature = 'dashboard';
  static const _pluginFeaturePrefix = 'plugin:';
  static const _featureValues = {
    'history',
    'schedule',
    'notes',
    'todos',
    'roleplay',
  };

  final _searchController = TextEditingController();
  final _noteDetailKey = GlobalKey<_NoteDetailState>();
  String _searchQuery = '';
  String? _selectedNoteId;
  bool _noteEditing = false;

  @override
  void dispose() {
    widget.onBackHandlerChanged?.call(() => false);
    widget.onDashboardHandlerChanged?.call(() async {});
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.onBackHandlerChanged?.call(_handleBack);
    widget.onDashboardHandlerChanged?.call(_goToDashboard);
  }

  bool _handleBack() {
    if (_selectedNoteId != null) {
      _closeSelectedNote();
      return true;
    }
    final feature = context.read<SettingsProvider>().settings.lastFeature;
    if (_isContentFeature(feature)) {
      _goToDashboard();
      return true;
    }
    return false;
  }

  Future<void> _goToDashboard() async {
    if (!await _canLeaveSelectedNote()) return;
    if (!mounted) return;
    setState(() {
      _selectedNoteId = null;
      _noteEditing = false;
      _searchQuery = '';
      _searchController.clear();
    });
    context.read<SettingsProvider>().setLastFeature(_dashboardFeature);
  }

  Future<void> _closeSelectedNote() async {
    if (!await _canLeaveSelectedNote()) return;
    if (!mounted) return;
    setState(() {
      _selectedNoteId = null;
      _noteEditing = false;
    });
  }

  Future<bool> _canLeaveSelectedNote() async {
    return await _noteDetailKey.currentState?.confirmDiscardUnsavedChanges() ??
        true;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final features = context.watch<FeatureProvider>();
    final plugins = context.watch<PluginProvider>();
    final feature = settings.lastFeature;
    final pluginFeature = _pluginFeatureFor(feature, plugins);
    final isDashboard =
        !_featureValues.contains(feature) && pluginFeature == null;
    return Scaffold(
      appBar: AppBar(
        leading: isDashboard
            ? null
            : _selectedNoteId == null
            ? IconButton(
                tooltip: '返回功能总览',
                icon: const Icon(Icons.arrow_back),
                onPressed: _goToDashboard,
              )
            : IconButton(
                tooltip: '笔记列表',
                icon: const Icon(Icons.menu),
                onPressed: _closeSelectedNote,
              ),
        title: Text(
          _title(feature, features, plugins),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: _actions(feature),
      ),
      floatingActionButton: _floatingActionButton(feature),
      body: switch (feature) {
        'schedule' => const _SchedulePage(),
        'notes' => _NotesPage(
          noteDetailKey: _noteDetailKey,
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
        'history' => _HistoryList(
          searchController: _searchController,
          searchQuery: _searchQuery,
          onSearchChanged: (v) => setState(() => _searchQuery = v),
          onConversationTap: widget.onConversationTap,
          onRoleChanged: widget.onRoleChanged,
        ),
        'roleplay' => const _RoleplayPage(),
        _ when pluginFeature != null => PluginFeatureWebView(
          plugin: pluginFeature.plugin,
          page: pluginFeature.page,
        ),
        _ => _FeatureDashboard(onFeatureSelected: _selectFeature),
      },
    );
  }

  String _title(
    String feature,
    FeatureProvider features,
    PluginProvider plugins,
  ) {
    if (_selectedNoteId != null) {
      final title = features.getNote(_selectedNoteId!)?.title.trim();
      if (title != null && title.isNotEmpty) return title;
      return '笔记';
    }
    return switch (feature) {
      'schedule' => '日程表',
      'notes' => '笔记',
      'todos' => '待办清单',
      'history' => '对话历史',
      'roleplay' => '情景演绎',
      _ => _pluginFeatureFor(feature, plugins)?.page.title ?? '功能',
    };
  }

  bool _isContentFeature(String feature) {
    return _featureValues.contains(feature) ||
        _PluginFeatureRef.tryParse(feature) != null;
  }

  _ResolvedPluginFeature? _pluginFeatureFor(
    String feature,
    PluginProvider provider,
  ) {
    final ref = _PluginFeatureRef.tryParse(feature);
    if (ref == null) return null;
    final plugin = provider.pluginById(ref.pluginId);
    if (plugin == null || !plugin.enabled || plugin.hasError) return null;
    if (!plugin.enabledFeaturePages.contains(ref.pageId)) return null;
    for (final page in plugin.manifest.featurePages) {
      if (page.id == ref.pageId && page.entry.trim().isNotEmpty) {
        return _ResolvedPluginFeature(plugin: plugin, page: page);
      }
    }
    return null;
  }

  Future<void> _selectFeature(String value) async {
    if (!await _canLeaveSelectedNote()) return;
    if (!mounted) return;
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
    if (!mounted) return;
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
    if (!mounted) return;
    _clearSearch();
  }

  Future<void> _importMarkdown() async {
    final features = context.read<FeatureProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.pickFiles(
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
      if (!mounted) return;
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
    if (!mounted) return;
    _clearSearch();
  }

  Future<void> _importTodoList() async {
    final features = context.read<FeatureProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.pickFiles(
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
      if (!mounted) return;
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
    if (_searchQuery.isEmpty && _searchController.text.isEmpty) return;
    _searchController.clear();
    setState(() => _searchQuery = '');
  }
}
