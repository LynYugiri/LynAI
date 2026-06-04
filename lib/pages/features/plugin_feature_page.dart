part of '../feature_page.dart';

class _PluginFeatureRef {
  final String pluginId;
  final String pageId;

  const _PluginFeatureRef(this.pluginId, this.pageId);

  String get key =>
      '${_FeaturePageState._pluginFeaturePrefix}$pluginId:$pageId';

  static _PluginFeatureRef? tryParse(String value) {
    if (!value.startsWith(_FeaturePageState._pluginFeaturePrefix)) return null;
    final rest = value.substring(_FeaturePageState._pluginFeaturePrefix.length);
    final separator = rest.indexOf(':');
    if (separator <= 0 || separator == rest.length - 1) return null;
    final pluginId = rest.substring(0, separator);
    final pageId = rest.substring(separator + 1);
    if (pluginId.isEmpty || pageId.isEmpty) return null;
    return _PluginFeatureRef(pluginId, pageId);
  }
}

class _ResolvedPluginFeature {
  final InstalledPlugin plugin;
  final PluginFeaturePageDefinition page;

  const _ResolvedPluginFeature({required this.plugin, required this.page});
}

/// 插件 WebView 功能页。
///
/// 页面只加载插件目录内的本地 `file:` 入口，并通过 `LynAIBridge` 暴露一组
/// 白名单 API。所有 API 都在 Dart 端做权限检查；插件的 HTML/JS 不能直接访问
/// Provider，也不能导航到插件目录之外的文件。
class _PluginFeatureWebViewPage extends StatefulWidget {
  final InstalledPlugin plugin;
  final PluginFeaturePageDefinition page;

  const _PluginFeatureWebViewPage({required this.plugin, required this.page});

  @override
  State<_PluginFeatureWebViewPage> createState() =>
      _PluginFeatureWebViewPageState();
}

class _PluginFeatureWebViewPageState extends State<_PluginFeatureWebViewPage> {
  WebViewController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEntry();
  }

  @override
  void didUpdateWidget(covariant _PluginFeatureWebViewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plugin.path != widget.plugin.path ||
        oldWidget.page.entry != widget.page.entry) {
      _loadEntry();
    }
  }

  void _loadEntry() {
    final path = safePluginFilePath(widget.plugin.path, widget.page.entry);
    if (path == null) {
      setState(() {
        _controller = null;
        _error = '插件入口路径不安全: ${widget.page.entry}';
      });
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      setState(() {
        _controller = null;
        _error = '插件入口文件不存在: ${widget.page.entry}';
      });
      return;
    }
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'LynAIBridge',
        onMessageReceived: (message) => _handleBridgeMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _injectBridge(),
          onNavigationRequest: (request) {
            final targetPath = _filePathFromUrl(request.url);
            if (targetPath == null) return NavigationDecision.prevent;
            final root = Directory(
              widget.plugin.path,
            ).absolute.path.replaceAll('\\', '/');
            final normalized = targetPath.replaceAll('\\', '/');
            return normalized.startsWith('$root/')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.file(file.absolute.path));
    setState(() {
      _controller = controller;
      _error = null;
    });
  }

  String? _filePathFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'file') return null;
    try {
      return uri.toFilePath();
    } catch (_) {
      return null;
    }
  }

  Future<void> _injectBridge() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.runJavaScript(r'''
(function () {
  if (window.lynai && window.lynai.call) return;
  var seq = 0;
  var pending = {};
  window.__lynaiBridgeResolve = function (payload) {
    var item = pending[payload.id];
    if (!item) return;
    delete pending[payload.id];
    if (payload.ok) {
      item.resolve(payload.result);
    } else {
      item.reject(new Error(payload.error || 'LynAI bridge call failed'));
    }
  };
  window.lynai = {
    call: function (method, params) {
      return new Promise(function (resolve, reject) {
        if (!window.LynAIBridge || !window.LynAIBridge.postMessage) {
          reject(new Error('LynAI bridge is unavailable'));
          return;
        }
        var id = 'req_' + (++seq) + '_' + Date.now();
        pending[id] = { resolve: resolve, reject: reject };
        window.LynAIBridge.postMessage(JSON.stringify({
          id: id,
          method: method,
          params: params || {}
        }));
      });
    }
  };
  window.dispatchEvent(new Event('lynai-ready'));
})();
''');
  }

  Future<void> _handleBridgeMessage(String message) async {
    String id = '';
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) throw Exception('Bridge 请求必须是对象');
      id = decoded['id']?.toString() ?? '';
      final method = decoded['method']?.toString() ?? '';
      if (id.isEmpty || method.isEmpty) {
        throw Exception('Bridge 请求缺少 id 或 method');
      }
      final result = _jsonMap(
        await _executeBridgeCall(method, decoded['params']),
      );
      await _sendBridgeResponse({'id': id, 'ok': true, 'result': result});
    } catch (e) {
      await _sendBridgeResponse({
        'id': id,
        'ok': false,
        'error': e.toString().replaceFirst('Exception: ', ''),
      });
    }
  }

  Future<Map<String, dynamic>> _executeBridgeCall(
    String method,
    Object? params,
  ) async {
    _requirePermission('webview:bridge');
    final args = params is Map
        ? Map<String, dynamic>.from(params)
        : <String, dynamic>{};
    final result = switch (method) {
      'plugin.info' => _pluginInfo(),
      'plugin.storage.get' => await _storageGet(args),
      'plugin.storage.set' => await _storageSet(args),
      'plugin.storage.remove' => await _storageRemove(args),
      'ui.toast' => _toast(args),
      'notes.list' => _notesList(args),
      'notes.read' => _notesRead(args),
      'notes.save' => await _notesSave(args),
      'notes.delete' => await _notesDelete(args),
      'todos.list' => _todosList(args),
      'todos.read' => _todosRead(args),
      'todos.saveList' => await _todosSaveList(args),
      'todos.saveItem' => await _todosSaveItem(args),
      'todos.deleteList' => await _todosDeleteList(args),
      'schedules.list' => _schedulesList(args),
      'schedules.create' => await _schedulesCreate(args),
      'schedules.update' => await _schedulesUpdate(args),
      'schedules.delete' => await _schedulesDelete(args),
      'model.chat' => await _modelChat(args),
      _ => throw Exception('未知 Bridge 方法: $method'),
    };
    return _jsonMap(result);
  }

  Map<String, dynamic> _pluginInfo() {
    final manifest = widget.plugin.manifest;
    return {
      'plugin': {
        'id': manifest.id,
        'name': manifest.name,
        'version': manifest.version,
        'author': manifest.author,
        'description': manifest.description,
        'permissions': manifest.permissions,
        'grantedPermissions': widget.plugin.grantedPermissions,
      },
      'page': {
        'id': widget.page.id,
        'title': widget.page.title,
        'entry': widget.page.entry,
      },
    };
  }

  Future<Map<String, dynamic>> _storageGet(Map<String, dynamic> args) async {
    _requirePermission('storage:read');
    final provider = context.read<PluginProvider>();
    final key = (args['key'] as String? ?? '').trim();
    if (key.isEmpty) {
      return {'values': await provider.loadStorage(widget.plugin.id)};
    }
    return {'value': await provider.readStorageValue(widget.plugin.id, key)};
  }

  Future<Map<String, dynamic>> _storageSet(Map<String, dynamic> args) async {
    _requirePermission('storage:write');
    final key = (args['key'] as String? ?? '').trim();
    if (key.isEmpty) throw Exception('plugin.storage.set 缺少 key');
    await context.read<PluginProvider>().writeStorageValue(
      widget.plugin.id,
      key,
      _jsonValue(args['value']),
    );
    return {'ok': true};
  }

  Future<Map<String, dynamic>> _storageRemove(Map<String, dynamic> args) async {
    _requirePermission('storage:write');
    final key = (args['key'] as String? ?? '').trim();
    if (key.isEmpty) throw Exception('plugin.storage.remove 缺少 key');
    await context.read<PluginProvider>().writeStorageValue(
      widget.plugin.id,
      key,
      null,
    );
    return {'ok': true};
  }

  Map<String, dynamic> _toast(Map<String, dynamic> args) {
    final message = (args['message'] as String? ?? '').trim();
    if (message.isEmpty) throw Exception('ui.toast 缺少 message');
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
    return {'ok': true};
  }

  Map<String, dynamic> _notesList(Map<String, dynamic> args) {
    _requirePermission('notes:read');
    final query = (args['query'] as String? ?? '').trim().toLowerCase();
    final folderId = (args['folderId'] as String? ?? '').trim();
    final includeContent = args['includeContent'] == true;
    final notes = context
        .read<FeatureProvider>()
        .notes
        .where((note) {
          if (folderId.isNotEmpty && note.folderId != folderId) return false;
          if (query.isEmpty) return true;
          return note.title.toLowerCase().contains(query) ||
              note.content.toLowerCase().contains(query);
        })
        .map((note) => _noteJson(note, includeContent: includeContent))
        .toList();
    return {'notes': notes};
  }

  Map<String, dynamic> _notesRead(Map<String, dynamic> args) {
    _requirePermission('notes:read');
    final features = context.read<FeatureProvider>();
    final id = (args['id'] as String? ?? '').trim();
    final title = (args['title'] as String? ?? '').trim().toLowerCase();
    Note? note;
    if (id.isNotEmpty) {
      note = features.getNote(id);
    }
    if (note == null && title.isNotEmpty) {
      for (final candidate in features.notes) {
        if (candidate.title.toLowerCase() == title) {
          note = candidate;
          break;
        }
      }
    }
    if (note == null) throw Exception('未找到笔记');
    return {'note': _noteJson(note, includeContent: true)};
  }

  Future<Map<String, dynamic>> _notesSave(Map<String, dynamic> args) async {
    _requirePermission('notes:write');
    final features = context.read<FeatureProvider>();
    final id = (args['id'] as String? ?? '').trim();
    final title = (args['title'] as String? ?? '').trim();
    final content = args['content'] as String? ?? '';
    final folderId = (args['folderId'] as String?)?.trim();
    final append = args['append'] == true;
    if (id.isEmpty) {
      if (title.isEmpty) throw Exception('notes.save 创建笔记缺少 title');
      final noteId = await features.addNoteWithContent(
        title,
        content,
        folderId: folderId,
      );
      final note = features.getNote(noteId)!;
      return {'note': _noteJson(note, includeContent: true)};
    }
    final current = features.getNote(id);
    if (current == null) throw Exception('未找到笔记: $id');
    final nextContent = append ? current.content + content : content;
    final updated = current.copyWith(
      title: title.isEmpty ? current.title : title,
      content: nextContent,
      folderId: args.containsKey('folderId') ? folderId : current.folderId,
    );
    await features.updateNote(updated);
    return {'note': _noteJson(updated, includeContent: true)};
  }

  Future<Map<String, dynamic>> _notesDelete(Map<String, dynamic> args) async {
    _requirePermission('notes:write');
    final id = (args['id'] as String? ?? '').trim();
    if (id.isEmpty) throw Exception('notes.delete 缺少 id');
    await context.read<FeatureProvider>().deleteNote(id);
    return {'ok': true};
  }

  Map<String, dynamic> _todosList(Map<String, dynamic> args) {
    _requirePermission('todos:read');
    final query = (args['query'] as String? ?? '').trim().toLowerCase();
    final includeItems = args['includeItems'] == true;
    final lists = context
        .read<FeatureProvider>()
        .todoLists
        .where((list) {
          if (query.isEmpty) return true;
          return list.title.toLowerCase().contains(query) ||
              list.items.any((item) => item.text.toLowerCase().contains(query));
        })
        .map((list) => _todoListJson(list, includeItems: includeItems))
        .toList();
    return {'todoLists': lists};
  }

  Map<String, dynamic> _todosRead(Map<String, dynamic> args) {
    _requirePermission('todos:read');
    final features = context.read<FeatureProvider>();
    final id = (args['id'] as String? ?? '').trim();
    final title = (args['title'] as String? ?? '').trim().toLowerCase();
    TodoList? list;
    if (id.isNotEmpty) {
      list = features.getTodoList(id);
    }
    if (list == null && title.isNotEmpty) {
      for (final candidate in features.todoLists) {
        if (candidate.title.toLowerCase() == title) {
          list = candidate;
          break;
        }
      }
    }
    if (list == null) throw Exception('未找到待办清单');
    return {'todoList': _todoListJson(list, includeItems: true)};
  }

  Future<Map<String, dynamic>> _todosSaveList(Map<String, dynamic> args) async {
    _requirePermission('todos:write');
    final features = context.read<FeatureProvider>();
    final id = (args['id'] as String? ?? '').trim();
    final title = (args['title'] as String? ?? '').trim();
    final rawItems = args['items'];
    final items = rawItems is List
        ? rawItems.whereType<Map>().map(_todoItemFromJson).toList()
        : <TodoItem>[];
    if (id.isEmpty) {
      if (title.isEmpty) throw Exception('todos.saveList 创建清单缺少 title');
      final listId = await features.addTodoListWithItems(title, items);
      final list = features.getTodoList(listId)!;
      return {'todoList': _todoListJson(list, includeItems: true)};
    }
    final current = features.getTodoList(id);
    if (current == null) throw Exception('未找到待办清单: $id');
    final updated = current.copyWith(
      title: title.isEmpty ? current.title : title,
      items: rawItems is List ? items : current.items,
    );
    await features.updateTodoList(updated);
    return {'todoList': _todoListJson(updated, includeItems: true)};
  }

  Future<Map<String, dynamic>> _todosSaveItem(Map<String, dynamic> args) async {
    _requirePermission('todos:write');
    final features = context.read<FeatureProvider>();
    final listId = (args['listId'] as String? ?? '').trim();
    final itemId = (args['itemId'] as String? ?? '').trim();
    final text = (args['text'] as String? ?? '').trim();
    final delete = args['delete'] == true;
    final list = features.getTodoList(listId);
    if (list == null) throw Exception('未找到待办清单: $listId');
    final items = [...list.items];
    final index = items.indexWhere((item) => item.id == itemId);
    if (delete) {
      if (index >= 0) items.removeAt(index);
    } else if (index >= 0) {
      final current = items[index];
      items[index] = current.copyWith(
        text: text.isEmpty ? current.text : text,
        done: args['done'] as bool?,
      );
    } else {
      if (text.isEmpty) throw Exception('创建待办项缺少 text');
      items.add(
        TodoItem(
          id: itemId.isEmpty ? const Uuid().v4() : itemId,
          text: text,
          done: args['done'] as bool? ?? false,
        ),
      );
    }
    final updated = list.copyWith(items: items);
    await features.updateTodoList(updated);
    return {'todoList': _todoListJson(updated, includeItems: true)};
  }

  Future<Map<String, dynamic>> _todosDeleteList(
    Map<String, dynamic> args,
  ) async {
    _requirePermission('todos:write');
    final id = (args['id'] as String? ?? '').trim();
    if (id.isEmpty) throw Exception('todos.deleteList 缺少 id');
    await context.read<FeatureProvider>().deleteTodoList(id);
    return {'ok': true};
  }

  Map<String, dynamic> _schedulesList(Map<String, dynamic> args) {
    _requirePermission('schedules:read');
    final from = _dateArg(args['from']);
    final to = _dateArg(args['to']);
    final schedules = context
        .read<FeatureProvider>()
        .schedules
        .where((item) {
          if (from != null && !item.end.isAfter(from)) return false;
          if (to != null && !item.start.isBefore(to)) return false;
          return true;
        })
        .map(_scheduleJson)
        .toList();
    return {
      'timezone': DateTime.now().timeZoneName,
      'timezoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      'schedules': schedules,
    };
  }

  Future<Map<String, dynamic>> _schedulesCreate(
    Map<String, dynamic> args,
  ) async {
    _requirePermission('schedules:write');
    final features = context.read<FeatureProvider>();
    final title = (args['title'] as String? ?? '').trim();
    final start = _dateArg(args['start']);
    final kind = _scheduleKind(args['kind']);
    final end = kind == ScheduleItem.kindTask
        ? start?.add(const Duration(minutes: 1))
        : _dateArg(args['end']);
    if (title.isEmpty || start == null || end == null) {
      throw Exception('schedules.create 缺少 title/start/end');
    }
    if (kind != ScheduleItem.kindTask && !end.isAfter(start)) {
      throw Exception('结束时间必须晚于开始时间');
    }
    final id = await features.addSchedule(
      title,
      start,
      end,
      note: args['note']?.toString(),
      kind: kind,
    );
    return {'schedule': _scheduleJson(features.getSchedule(id)!)};
  }

  Future<Map<String, dynamic>> _schedulesUpdate(
    Map<String, dynamic> args,
  ) async {
    _requirePermission('schedules:write');
    final features = context.read<FeatureProvider>();
    final id = (args['id'] as String? ?? '').trim();
    final current = features.getSchedule(id);
    if (current == null) throw Exception('未找到日程: $id');
    final kind = args.containsKey('kind')
        ? _scheduleKind(args['kind'])
        : current.kind;
    final start = _dateArg(args['start']) ?? current.start;
    final end = kind == ScheduleItem.kindTask
        ? start.add(const Duration(minutes: 1))
        : _dateArg(args['end']) ?? current.end;
    final updated = current.copyWith(
      title: (args['title'] as String?)?.trim(),
      start: start,
      end: end,
      note: args.containsKey('note') ? args['note']?.toString() : current.note,
      kind: kind,
    );
    if (!updated.isTask && !updated.end.isAfter(updated.start)) {
      throw Exception('结束时间必须晚于开始时间');
    }
    await features.updateSchedule(updated);
    return {'schedule': _scheduleJson(updated)};
  }

  Future<Map<String, dynamic>> _schedulesDelete(
    Map<String, dynamic> args,
  ) async {
    _requirePermission('schedules:write');
    final id = (args['id'] as String? ?? '').trim();
    if (id.isEmpty) throw Exception('schedules.delete 缺少 id');
    await context.read<FeatureProvider>().deleteSchedule(id);
    return {'ok': true};
  }

  Future<Map<String, dynamic>> _modelChat(Map<String, dynamic> args) async {
    _requirePermission('model:chat');
    final model = _selectChatModel(args['modelId'] as String?);
    final messages = _modelMessages(args);
    final api = ApiService();
    try {
      final response = await api.sendChatRequest(
        model,
        messages,
        thinking: args['thinking'] == true && model.supportsThinking,
        tools: const [],
        toolChoice: 'none',
      );
      return {
        'content': response.content,
        if (response.reasoning != null) 'reasoning': response.reasoning,
      };
    } finally {
      api.dispose();
    }
  }

  Map<String, dynamic> _noteJson(Note note, {required bool includeContent}) {
    final summary = note.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return {
      'id': note.id,
      'title': note.title,
      'createdAt': note.createdAt.toIso8601String(),
      'updatedAt': note.updatedAt.toIso8601String(),
      if (note.folderId != null) 'folderId': note.folderId,
      if (note.currentRevisionId != null)
        'currentRevisionId': note.currentRevisionId,
      'summary': summary.length > 160
          ? '${summary.substring(0, 160)}...'
          : summary,
      if (includeContent) 'content': note.content,
    };
  }

  Map<String, dynamic> _todoListJson(
    TodoList list, {
    required bool includeItems,
  }) {
    return {
      'id': list.id,
      'title': list.title,
      'createdAt': list.createdAt.toIso8601String(),
      'updatedAt': list.updatedAt.toIso8601String(),
      'totalCount': list.items.length,
      'doneCount': list.items.where((item) => item.done).length,
      if (includeItems)
        'items': list.items
            .map(
              (item) => {'id': item.id, 'text': item.text, 'done': item.done},
            )
            .toList(),
    };
  }

  Map<String, dynamic> _scheduleJson(ScheduleItem item) {
    return {
      'id': item.id,
      'title': item.title,
      'kind': item.kind,
      'start': item.start.toIso8601String(),
      'end': item.end.toIso8601String(),
      'isTask': item.isTask,
      if (item.note != null) 'note': item.note,
    };
  }

  TodoItem _todoItemFromJson(Map<dynamic, dynamic> json) {
    final id = (json['id'] as String? ?? '').trim();
    final text = (json['text'] as String? ?? '').trim();
    if (text.isEmpty) throw Exception('待办项缺少 text');
    return TodoItem(
      id: id.isEmpty ? const Uuid().v4() : id,
      text: text,
      done: json['done'] as bool? ?? false,
    );
  }

  String _scheduleKind(Object? raw) {
    final value = raw?.toString().trim();
    if (value == ScheduleItem.kindTask) return ScheduleItem.kindTask;
    return ScheduleItem.kindSchedule;
  }

  ModelConfig _selectChatModel(String? modelId) {
    final provider = context.read<ModelConfigProvider>();
    final chatModels = provider.modelsByCategory(ModelConfig.categoryChat);
    if (chatModels.isEmpty) throw Exception('没有可用聊天模型');
    final id = modelId?.trim();
    if (id != null && id.isNotEmpty) {
      for (final model in chatModels) {
        if (model.id == id) return model;
      }
      throw Exception('未找到模型: $id');
    }
    final lastId = context.read<SettingsProvider>().settings.lastChatModelId;
    if (lastId != null && lastId.isNotEmpty) {
      for (final model in chatModels) {
        if (model.id == lastId) return model;
      }
    }
    return chatModels.first;
  }

  List<Map<String, dynamic>> _modelMessages(Map<String, dynamic> args) {
    final rawMessages = args['messages'];
    if (rawMessages is List) {
      final messages = rawMessages
          .whereType<Map>()
          .map((item) {
            final role = _messageRole(item['role']);
            final content = item['content']?.toString() ?? '';
            return {'role': role, 'content': content};
          })
          .where((item) => (item['content'] as String).trim().isNotEmpty)
          .toList();
      if (messages.isNotEmpty) return messages;
    }
    final system = (args['system'] as String? ?? '').trim();
    final user = (args['user'] as String? ?? args['prompt'] as String? ?? '')
        .trim();
    if (user.isEmpty) throw Exception('model.chat 缺少 user/prompt/messages');
    return [
      if (system.isNotEmpty) {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  DateTime? _dateArg(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim())?.toLocal();
  }

  String _messageRole(Object? raw) {
    final role = raw?.toString().trim();
    return switch (role) {
      'system' || 'assistant' || 'user' => role!,
      _ => 'user',
    };
  }

  Object? _jsonValue(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is List) return value.map(_jsonValue).toList(growable: false);
    if (value is Map) return _jsonMap(value);
    return value.toString();
  }

  Map<String, dynamic> _jsonMap(Map<dynamic, dynamic> value) {
    return value.map((key, item) => MapEntry(key.toString(), _jsonValue(item)));
  }

  void _requirePermission(String permission) {
    if (!widget.plugin.grantedPermissions.contains(permission)) {
      throw Exception('插件未授权 $permission');
    }
  }

  Future<void> _sendBridgeResponse(Map<String, dynamic> response) async {
    final controller = _controller;
    if (controller == null) return;
    final payload = jsonEncode(response);
    await controller.runJavaScript('window.__lynaiBridgeResolve?.($payload);');
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final controller = _controller;
    if (error != null || controller == null) {
      return _PluginFeatureError(
        plugin: widget.plugin,
        page: widget.page,
        message: error ?? '插件页面未加载',
      );
    }
    return WebViewWidget(controller: controller);
  }
}

class _PluginFeatureError extends StatelessWidget {
  final InstalledPlugin plugin;
  final PluginFeaturePageDefinition page;
  final String message;

  const _PluginFeatureError({
    required this.plugin,
    required this.page,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PluginIcon(
              pluginPath: plugin.path,
              iconPath: page.icon,
              fallbackIconPath: plugin.manifest.icon,
              size: 52,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              page.title.isEmpty ? plugin.manifest.name : page.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      ),
    );
  }
}
