import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart' show FileType;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/feature_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/task_provider.dart';
import '../widgets/plugin_feature_webview.dart';
import '../widgets/text_editing_controller_host.dart';
import '../utils/file_picker_io_utils.dart';
import 'features/dashboard.dart';
import 'features/feature_shared.dart';
import 'features/feature_shell.dart';
import 'features/knowledge_page.dart';
import 'features/note_detail_page.dart';
import 'features/notes_page.dart';
import 'features/roleplay_page.dart';
import 'features/schedule_page.dart';
import 'features/todo_lists_page.dart';

/// 功能页 shell。
///
/// 根据 `AppSettings.lastFeature` 在历史、日程、笔记和待办之间切换。子页面
/// 拆成 `part` 文件，但共享搜索语法、导出工具和若干内部组件。
class FeaturePage extends StatefulWidget {
  final bool active;
  final void Function(String conversationId) onConversationTap;
  final void Function(bool Function() handler)? onBackHandlerChanged;
  final void Function(Future<void> Function() handler)?
  onDashboardHandlerChanged;

  const FeaturePage({
    super.key,
    this.active = true,
    required this.onConversationTap,
    this.onBackHandlerChanged,
    this.onDashboardHandlerChanged,
  });

  @override
  State<FeaturePage> createState() => _FeaturePageState();
}

class _FeaturePageState extends State<FeaturePage> {
  static const _dashboardFeature = 'dashboard';
  static const _featureValues = {
    'history',
    'schedule',
    'notes',
    'todos',
    'roleplay',
    'knowledge',
  };

  final _searchController = TextEditingController();
  final _noteDetailKey = GlobalKey<NoteDetailState>();
  final _knowledgePageKey = GlobalKey<KnowledgePageState>();
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

  // 返回键处理：先尝试关闭功能内详情，再尝试返回功能仪表盘。
  bool _handleBack() {
    if (_selectedNoteId != null) {
      _closeSelectedNote();
      return true;
    }
    final feature = context.read<SettingsProvider>().settings.lastFeature;
    if (feature == 'knowledge' &&
        (_knowledgePageKey.currentState?.handleBack() ?? false)) {
      return true;
    }
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

  // 根据 lastFeature 决定显示仪表盘或对应子页面。
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
        'schedule' => const SchedulePage(),
        'notes' => NotesPage(
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
        'todos' => TodoListsPage(
          searchController: _searchController,
          searchQuery: _searchQuery,
          onSearchChanged: (v) => setState(() => _searchQuery = v),
        ),
        'history' => HistoryList(
          searchController: _searchController,
          searchQuery: _searchQuery,
          onSearchChanged: (v) => setState(() => _searchQuery = v),
          onConversationTap: widget.onConversationTap,
        ),
        'roleplay' => RoleplayPage(active: widget.active),
        'knowledge' => KnowledgePage(key: _knowledgePageKey),
        _ when pluginFeature != null && widget.active => PluginFeatureWebView(
          plugin: pluginFeature.plugin,
          page: pluginFeature.page,
        ),
        _ when pluginFeature != null => const SizedBox.shrink(),
        _ => FeatureDashboard(onFeatureSelected: _selectFeature),
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
      'todos' => '任务',
      'history' => '对话历史',
      'roleplay' => '情景演绎',
      'knowledge' => '知识库',
      _ => _pluginFeatureFor(feature, plugins)?.page.title ?? '功能',
    };
  }

  bool _isContentFeature(String feature) {
    return _featureValues.contains(feature) ||
        PluginFeatureRef.tryParse(feature) != null;
  }

  ResolvedPluginFeature? _pluginFeatureFor(
    String feature,
    PluginProvider provider,
  ) {
    final ref = PluginFeatureRef.tryParse(feature);
    if (ref == null) return null;
    final plugin = provider.pluginById(ref.pluginId);
    if (plugin == null || !plugin.enabled || plugin.hasError) return null;
    if (!plugin.enabledFeaturePages.contains(ref.pageId)) return null;
    for (final page in plugin.manifest.featurePages) {
      if (page.id == ref.pageId && page.entry.trim().isNotEmpty) {
        return ResolvedPluginFeature(plugin: plugin, page: page);
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
          tooltip: '新建任务清单',
          icon: const Icon(Icons.add),
          onPressed: _newTodoList,
        ),
        IconButton(
          tooltip: '导入任务清单',
          icon: const Icon(Icons.upload_file),
          onPressed: _importTodoList,
        ),
      ];
    }
    return const [];
  }

  Widget? _floatingActionButton(String feature) {
    if (feature == 'notes' && _selectedNoteId == null) {
      return AddMenuButton(
        items: const [
          AddMenuItem('note', Icons.sticky_note_2_outlined, '创建笔记'),
          AddMenuItem('folder', Icons.create_new_folder_outlined, '创建文件夹'),
        ],
        onSelected: (value) {
          if (value == 'note') _newNote();
          if (value == 'folder') _newNoteFolder();
        },
      );
    }
    if (feature == 'todos') {
      return AddMenuButton(
        items: const [AddMenuItem('todo', Icons.checklist, '新建任务清单')],
        onSelected: (_) => _newTodoList(),
      );
    }
    return null;
  }

  Future<void> _newNote({String? folderId}) async {
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => TextEditingControllerHost(
        initialTexts: const [''],
        builder: (ctx, controllers) {
          final ctrl = controllers.single;
          return AlertDialog(
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
          );
        },
      ),
    );
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
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => TextEditingControllerHost(
        initialTexts: const [''],
        builder: (ctx, controllers) {
          final ctrl = controllers.single;
          return AlertDialog(
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
          );
        },
      ),
    );
    if (!mounted || title == null || title.isEmpty) return;
    await context.read<FeatureProvider>().addNoteFolder(title);
    if (!mounted) return;
    _clearSearch();
  }

  Future<void> _importMarkdown() async {
    final features = context.read<FeatureProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await pickSingleFilePayload(
        dialogTitle: '导入 Markdown',
        type: FileType.custom,
        allowedExtensions: ['md', 'markdown', 'txt'],
      );
      if (!mounted || file == null) return;
      final bytes = await file.readBytes();
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
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => TextEditingControllerHost(
        initialTexts: const [''],
        builder: (ctx, controllers) {
          final ctrl = controllers.single;
          return AlertDialog(
            title: const Text('新建任务清单'),
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
          );
        },
      ),
    );
    if (!mounted || title == null || title.isEmpty) return;
    await context.read<TaskProvider>().addList(title);
    if (!mounted) return;
    _clearSearch();
  }

  Future<void> _importTodoList() async {
    final tasks = context.read<TaskProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await pickSingleFilePayload(
        dialogTitle: '导入任务清单',
        type: FileType.custom,
        allowedExtensions: ['md', 'markdown', 'txt'],
      );
      if (!mounted || file == null) return;
      final bytes = await file.readBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      final title = _todoTitleFromFileName(file.name);
      final listId = await tasks.addList(title);
      for (final item in _parseTodoItems(content)) {
        final taskId = await tasks.addTask(title: item.title, listId: listId);
        if (item.completed) await tasks.completeTask(taskId);
      }
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
    return cleaned.isEmpty ? '导入任务清单' : cleaned;
  }

  List<({String title, bool completed})> _parseTodoItems(String content) {
    return content
        .split(RegExp(r'\r?\n'))
        .map((line) {
          final text = line.trim();
          if (text.isEmpty || text.startsWith('#')) return null;
          final match = RegExp(
            r'^[-*+]\s+\[([ xX])\]\s+(.*)$',
          ).firstMatch(text);
          if (match != null) {
            return (
              title: match.group(2)!.trim(),
              completed: match.group(1)!.toLowerCase() == 'x',
            );
          }
          final plain = text.replaceFirst(RegExp(r'^[-*+]\s+'), '').trim();
          return plain.isEmpty ? null : (title: plain, completed: false);
        })
        .whereType<({String title, bool completed})>()
        .toList();
  }

  void _clearSearch() {
    if (_searchQuery.isEmpty && _searchController.text.isEmpty) return;
    _searchController.clear();
    setState(() => _searchQuery = '');
  }
}
