import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/model_config.dart';
import '../models/anniversary.dart';
import '../models/calendar_event.dart';
import '../models/item_reminder.dart';
import '../models/local_date.dart';
import '../models/local_time.dart';
import '../models/note.dart';
import '../models/plugin.dart';
import '../models/recycle_bin_item.dart';
import '../models/task.dart';
import '../models/task_list.dart';
import '../providers/calendar_provider.dart';
import '../providers/conversation_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/task_provider.dart';
import '../repositories/recycle_bin_repository.dart';
import 'api_service.dart';
import 'backend_client.dart';
import 'device_control_service.dart';
import 'device_run_controller.dart';
import 'lynai_call_identity.dart';
import 'lynai_permission_definitions.dart';
import 'lynai_permission_service.dart';
import 'image_generation_service.dart';
import 'model_recognition_service.dart';
import 'storage_v2_service.dart';

/// AI 函数调用描述。
class LynAIFunctionCall {
  final String name;
  final Map<String, dynamic> arguments;

  const LynAIFunctionCall({required this.name, required this.arguments});
}

/// AI 函数执行的上下文环境。
class LynAIFunctionContext {
  final LynAICallIdentity identity;
  final FeatureProvider? features;
  final TaskProvider? tasks;
  final CalendarProvider? calendar;
  final ModelConfigProvider? modelConfigs;
  final SettingsProvider? settings;
  final PluginProvider? plugins;
  final ConversationProvider? conversations;
  final BackendClient? backend;
  final InstalledPlugin? plugin;
  final void Function(String message)? showToast;

  const LynAIFunctionContext({
    this.identity = const LynAICallIdentity(type: LynAICallerType.system),
    this.features,
    this.tasks,
    this.calendar,
    this.modelConfigs,
    this.settings,
    this.plugins,
    this.conversations,
    this.backend,
    this.plugin,
    this.showToast,
  });
}

class _NoteLineEdit {
  final int startLine;
  final int deleteCount;
  final List<String> insertLines;
  final List<String>? expectedLines;

  const _NoteLineEdit({
    required this.startLine,
    required this.deleteCount,
    required this.insertLines,
    this.expectedLines,
  });

  static _NoteLineEdit? fromRaw(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final startLine = _intArg(json['startLine']);
    final deleteCount = _intArg(json['deleteCount']);
    if (startLine == null || deleteCount == null || deleteCount < 0) {
      return null;
    }
    final rawLines = json['insertLines'];
    final insertLines = rawLines is List
        ? rawLines.map((line) => line?.toString() ?? '').toList()
        : const <String>[];
    final rawExpectedLines = json['expectedLines'];
    final expectedLines = rawExpectedLines is List
        ? rawExpectedLines.map((line) => line?.toString() ?? '').toList()
        : null;
    return _NoteLineEdit(
      startLine: startLine,
      deleteCount: deleteCount,
      insertLines: insertLines,
      expectedLines: expectedLines,
    );
  }

  static int? _intArg(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }
}

class _ParsedNoteEdit {
  final Note? note;
  final List<_NoteLineEdit> edits;
  final String? baseRevisionId;
  final String? error;

  const _ParsedNoteEdit({
    required this.note,
    required this.edits,
    required this.baseRevisionId,
  }) : error = null;

  const _ParsedNoteEdit.error(this.error)
    : note = null,
      edits = const [],
      baseRevisionId = null;
}

class _SelectedNote {
  final Note? note;
  final String? error;

  const _SelectedNote({required this.note}) : error = null;
  const _SelectedNote.error(this.error) : note = null;
}

class _AppliedLineEdits {
  final String? content;
  final String? error;

  const _AppliedLineEdits.success(this.content) : error = null;
  const _AppliedLineEdits.error(this.error) : content = null;
}

class _TextMatcher {
  final String query;
  final RegExp? _regex;

  const _TextMatcher._(this.query, this._regex);

  factory _TextMatcher(String query) {
    final trimmed = query.trim();
    final parsed = _parseRegexSearch(trimmed);
    if (parsed == null) return _TextMatcher._(trimmed.toLowerCase(), null);
    try {
      return _TextMatcher._(
        trimmed,
        RegExp(parsed.pattern, caseSensitive: parsed.caseSensitive),
      );
    } catch (_) {
      return _TextMatcher._('', RegExp(r'a^'));
    }
  }

  bool get isEmpty => query.isEmpty;
  bool get isRegex => _regex != null;

  bool matches(String text) {
    final regex = _regex;
    if (query.isEmpty) return true;
    if (regex != null) return regex.hasMatch(text);
    return text.toLowerCase().contains(query);
  }
}

class _ParsedRegexSearch {
  final String pattern;
  final bool caseSensitive;

  const _ParsedRegexSearch(this.pattern, {required this.caseSensitive});
}

enum _LegacyScheduleKind { task, schedule, unspecified }

/// 解析用户输入的正则表示式搜索语法。
///
/// 支持两种格式：
/// - `re:<pattern>` —— 强制正则模式，默认不区分大小写
/// - `/<pattern>/<flags>` —— 标准正则字面量，`i` flag 表示不区分大小写
///
/// 使用 `lastIndexOf('/')` 而非 `indexOf('/')` 来查找结束斜杠，
/// 是为了支持 pattern 内部包含 `/` 转义字符的场景（如 `/a\/b/i`），
/// 虽然在这个简单实现中并未完全处理转义，但 `lastIndexOf` 能避免
/// 把 pattern 中间的 `/` 误判为结束定界符。
_ParsedRegexSearch? _parseRegexSearch(String query) {
  if (query.startsWith('re:')) {
    final pattern = query.substring(3).trim();
    return pattern.isEmpty
        ? null
        : _ParsedRegexSearch(pattern, caseSensitive: false);
  }
  if (!query.startsWith('/') || query.length < 2) return null;
  final lastSlash = query.lastIndexOf('/');
  if (lastSlash <= 0) return null;
  final pattern = query.substring(1, lastSlash);
  if (pattern.isEmpty) return null;
  final flags = query.substring(lastSlash + 1);
  return _ParsedRegexSearch(pattern, caseSensitive: !flags.contains('i'));
}

/// LynAI 内置函数执行引擎。
///
/// 负责将模型发出的函数调用（[LynAIFunctionCall]）分发到具体实现，
/// 包括笔记/待办/日程 CRUD、插件沙箱 API、HTTP 请求、系统状态等。
/// 每个函数在执行前都会检查插件权限，无权限则拒绝执行。
class LynAIFunctionService {
  static const _uuid = Uuid();
  static const _nativeToolsChannel = MethodChannel('lynai/native_tools');
  static String? _appVersion;
  static const _permissionService = LynAIPermissionService();
  static final _recycleBinRepository = RecycleBinRepository();

  /// 工具别名映射表，将 comfyui 风格的短名映射到内部标准化函数名。
  /// 供 [ToolCallService] 在接收到旧版工具调用名称时进行兼容转换。
  static const aiToolAliases = {
    'list_tasks': 'tasks.list',
    'create_task': 'tasks.create',
    'update_task': 'tasks.update',
    'delete_task': 'tasks.delete',
    'list_calendar_events': 'calendar.list',
    'create_calendar_event': 'calendar.create',
    'update_calendar_event': 'calendar.update',
    'delete_calendar_event': 'calendar.delete',
    'list_anniversaries': 'anniversaries.list',
    'create_anniversary': 'anniversaries.create',
    'update_anniversary': 'anniversaries.update',
    'delete_anniversary': 'anniversaries.delete',
    'list_schedules': 'schedules.list',
    'create_schedule': 'schedules.create',
    'update_schedule': 'schedules.update',
    'list_notes': 'notes.list',
    'read_note': 'notes.read',
    'save_note': 'notes.save',
    'edit_note': 'notes.edit',
    'propose_note_edit': 'notes.proposeEdit',
    'list_note_pages': 'notes.pages.list',
    'save_note_page': 'notes.pages.save',
    'list_note_folders': 'notes.folders.list',
    'save_note_folder': 'notes.folders.save',
    'list_todo_lists': 'todos.list',
    'read_todo_list': 'todos.read',
    'save_todo_list': 'todos.saveList',
    'save_todo_item': 'todos.saveItem',
    'generate_image': 'model.generateImage',
  };

  /// 异步执行 AI 函数调用。
  Future<Map<String, dynamic>> execute(
    LynAIFunctionCall call,
    LynAIFunctionContext context,
  ) async {
    try {
      final permission = _permissionFor(call.name);
      if (permission != null) {
        _requirePermission(context, call.name, permission);
      }
      return switch (call.name) {
        'plugin.info' => _pluginInfo(context),
        'plugin.config.read' => await _pluginConfigRead(
          context,
          call.arguments,
        ),
        'plugin.file.list' => await _pluginFileList(context, call.arguments),
        'plugin.file.read' => await _pluginFileRead(context, call.arguments),
        'plugin.file.write' => await _pluginFileWrite(context, call.arguments),
        'plugin.file.create' => await _pluginFileWrite(context, call.arguments),
        'plugin.file.delete' => await _pluginFileDelete(
          context,
          call.arguments,
        ),
        'plugin.file.rename' => await _pluginFileRename(
          context,
          call.arguments,
        ),
        'plugin.storage.get' => await _storageGet(context, call.arguments),
        'plugin.storage.set' => await _storageSet(context, call.arguments),
        'plugin.storage.remove' => await _storageRemove(
          context,
          call.arguments,
        ),
        'recycleBin.putData' => await _recycleBinPutData(
          context,
          call.arguments,
        ),
        'recycleBin.putFile' => await _recycleBinPutFile(
          context,
          call.arguments,
        ),
        'recycleBin.list' => await _recycleBinList(context, call.arguments),
        'recycleBin.restore' => await _recycleBinRestore(
          context,
          call.arguments,
        ),
        'recycleBin.deleteForever' => await _recycleBinDeleteForever(
          context,
          call.arguments,
        ),
        'plugin.restore' => await _pluginRestore(context),
        'plugin.func' => await _pluginFunc(context, call.arguments),
        'ui.toast' => _toast(context, call.arguments),
        'conversations.count' => _conversationCount(context),
        'system.status' => _systemStatus(context),
        'http.fetch' => await _httpFetch(context, call.arguments),
        'notes.list' => _listNotes(_features(context), call.arguments),
        'notes.read' => await _readNote(_features(context), call.arguments),
        'notes.save' => await _saveNote(_features(context), call.arguments),
        'notes.edit' => await _editNote(_features(context), call.arguments),
        'notes.proposeEdit' => await _proposeNoteEdit(
          _features(context),
          call.arguments,
        ),
        'notes.delete' => await _deleteNote(_features(context), call.arguments),
        'notes.pages.list' => _listNotePages(
          _features(context),
          call.arguments,
        ),
        'notes.pages.save' => await _saveNotePage(
          _features(context),
          call.arguments,
        ),
        'notes.folders.list' => _listNoteFolders(_features(context)),
        'notes.folders.save' => await _saveNoteFolder(
          _features(context),
          call.arguments,
        ),
        'todos.list' => _listTodoLists(_tasks(context), call.arguments),
        'todos.read' => _readTodoList(_tasks(context), call.arguments),
        'todos.saveList' => await _saveTodoList(
          _tasks(context),
          call.arguments,
        ),
        'todos.saveItem' => await _saveTodoItem(
          _tasks(context),
          call.arguments,
        ),
        'todos.deleteList' => await _deleteTodoList(
          _tasks(context),
          call.arguments,
        ),
        'tasks.list' => _listTasks(_tasks(context), call.arguments),
        'tasks.create' => await _createTask(_tasks(context), call.arguments),
        'tasks.update' => await _updateTask(_tasks(context), call.arguments),
        'tasks.delete' => await _deleteTask(_tasks(context), call.arguments),
        'calendar.list' => _listCalendar(_calendar(context), call.arguments),
        'calendar.create' => await _createCalendar(
          _calendar(context),
          call.arguments,
        ),
        'calendar.update' => await _updateCalendar(
          _calendar(context),
          call.arguments,
        ),
        'calendar.delete' => await _deleteCalendar(
          _calendar(context),
          call.arguments,
        ),
        'anniversaries.list' => _listAnniversaries(
          _calendar(context),
          call.arguments,
        ),
        'anniversaries.create' => await _createAnniversary(
          _calendar(context),
          call.arguments,
        ),
        'anniversaries.update' => await _updateAnniversary(
          _calendar(context),
          call.arguments,
        ),
        'anniversaries.delete' => await _deleteAnniversary(
          _calendar(context),
          call.arguments,
        ),
        // 兼容旧日程 API，但数据统一写入新任务和日历分区。
        'schedules.list' => _listSchedules(context, call.arguments),
        'schedules.create' => await _createSchedule(context, call.arguments),
        'schedules.update' => await _updateSchedule(context, call.arguments),
        'schedules.delete' => await _deleteSchedule(context, call.arguments),
        'model.chat' => await _modelChat(context, call.arguments),
        'model.ocr' => await _modelOcr(context, call.arguments),
        'model.recognizeFile' => await _modelRecognizeFile(
          context,
          call.arguments,
        ),
        'model.generateImage' => await _modelGenerateImage(
          context,
          call.arguments,
        ),
        'device.app.open' => await _openApp(call.arguments),
        String name when name.startsWith('device.') =>
          await DeviceControlService.instance.execute(name, call.arguments),
        _ => _error('未知 LynAI function: ${call.name}'),
      };
    } on Exception catch (e) {
      return _error(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// 同步执行 AI 函数调用。
  Map<String, dynamic> executeSync(
    LynAIFunctionCall call,
    LynAIFunctionContext context,
  ) {
    try {
      final permission = _permissionFor(call.name);
      if (permission != null) {
        _requirePermission(context, call.name, permission);
      }
      return switch (call.name) {
        'plugin.info' => _pluginInfo(context),
        'notes.list' => _listNotesForPlugin(_features(context), call.arguments),
        'notes.read' => _readNoteForPlugin(_features(context), call.arguments),
        'notes.pages.list' => _listNotePages(
          _features(context),
          call.arguments,
        ),
        'notes.folders.list' => _listNoteFolders(_features(context)),
        'todos.list' => _listTodoLists(_tasks(context), call.arguments),
        'todos.read' => _readTodoList(_tasks(context), call.arguments),
        'tasks.list' => _listTasks(_tasks(context), call.arguments),
        'calendar.list' => _listCalendar(_calendar(context), call.arguments),
        'anniversaries.list' => _listAnniversaries(
          _calendar(context),
          call.arguments,
        ),
        'schedules.list' => _listSchedules(context, call.arguments),
        'conversations.count' => _conversationCount(context),
        'system.status' => _systemStatus(context),
        'device.service.status' => DeviceRunController.instance.statusJson(),
        _ => _error('LynAI function 需要异步执行: ${call.name}'),
      };
    } on Exception catch (e) {
      return _error(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// 根据函数名称返回所需权限标识。
  String? _permissionFor(String name) {
    return switch (name) {
      'plugin.storage.get' => LynAIPermissions.storageRead,
      'plugin.storage.set' ||
      'plugin.storage.remove' => LynAIPermissions.storageWrite,
      'recycleBin.list' => LynAIPermissions.recycleBinRead,
      'recycleBin.putData' ||
      'recycleBin.putFile' => LynAIPermissions.recycleBinWrite,
      'recycleBin.restore' ||
      'recycleBin.deleteForever' => LynAIPermissions.recycleBinRestore,
      'plugin.file.write' ||
      'plugin.file.create' ||
      'plugin.file.delete' ||
      'plugin.file.rename' ||
      'plugin.restore' => LynAIPermissions.filesWrite,
      'http.fetch' => LynAIPermissions.networkAccess,
      'notes.list' ||
      'notes.read' ||
      'notes.pages.list' ||
      'notes.folders.list' => LynAIPermissions.notesRead,
      'notes.proposeEdit' => LynAIPermissions.notesPropose,
      'notes.save' ||
      'notes.edit' ||
      'notes.delete' ||
      'notes.pages.save' ||
      'notes.folders.save' => LynAIPermissions.notesWrite,
      'todos.list' || 'todos.read' => LynAIPermissions.todosRead,
      'todos.saveList' ||
      'todos.saveItem' ||
      'todos.deleteList' => LynAIPermissions.todosWrite,
      'tasks.list' => LynAIPermissions.todosRead,
      'tasks.create' ||
      'tasks.update' ||
      'tasks.delete' => LynAIPermissions.todosWrite,
      'calendar.list' ||
      'anniversaries.list' ||
      'schedules.list' => LynAIPermissions.schedulesRead,
      'calendar.create' ||
      'calendar.update' ||
      'calendar.delete' ||
      'anniversaries.create' ||
      'anniversaries.update' ||
      'anniversaries.delete' ||
      'schedules.create' ||
      'schedules.update' ||
      'schedules.delete' => LynAIPermissions.schedulesWrite,
      'model.chat' => LynAIPermissions.modelChat,
      'model.ocr' => LynAIPermissions.modelOcr,
      'model.recognizeFile' => LynAIPermissions.modelRecognizeFile,
      'model.generateImage' => LynAIPermissions.modelGenerateImage,
      'device.screen.snapshot' ||
      'device.screen.context' ||
      'device.screen.screenshot' ||
      'device.screen.query' ||
      'device.screen.waitText' ||
      'device.screen.readVisibleText' ||
      'device.screen.extractMessages' ||
      'device.node.find' ||
      'device.node.findAll' ||
      'device.waitForNode' => LynAIPermissions.deviceScreenRead,
      'device.screen.clickText' ||
      'device.screen.waitAndClick' ||
      'device.screen.inputText' ||
      'device.screen.scrollUntil' => LynAIPermissions.deviceControl,
      'device.service.status' ||
      'device.service.openSettings' => LynAIPermissions.deviceOverlay,
      'device.app.open' => LynAIPermissions.deviceControl,
      String name when name.startsWith('device.') =>
        LynAIPermissions.deviceControl,
      _ => null,
    };
  }

  void _requirePermission(
    LynAIFunctionContext context,
    String functionName,
    String permission,
  ) {
    if (_agentDeleteBlocked(context, functionName)) {
      throw Exception('当前暂不支持 Agent 删除操作，未来会在回收站能力完成后开放');
    }
    final allowed = _permissionService.canUsePermission(
      identity: context.identity,
      permission: permission,
      appSettings: context.settings?.settings,
      plugin: context.plugin,
    );
    if (!allowed) {
      throw Exception('未授权 $permission');
    }
  }

  bool _agentDeleteBlocked(LynAIFunctionContext context, String functionName) {
    final caller = context.identity.type;
    if (caller != LynAICallerType.agent &&
        caller != LynAICallerType.agentLua &&
        caller != LynAICallerType.lua) {
      return false;
    }
    return switch (functionName) {
      'notes.delete' ||
      'tasks.delete' ||
      'calendar.delete' ||
      'anniversaries.delete' ||
      'todos.deleteList' ||
      'schedules.delete' ||
      'plugin.file.delete' ||
      'recycleBin.deleteForever' ||
      'plugin.restore' => true,
      _ => false,
    };
  }

  FeatureProvider _features(LynAIFunctionContext context) {
    final features = context.features;
    if (features == null) throw Exception('LynAI function 需要功能上下文');
    return features;
  }

  TaskProvider _tasks(LynAIFunctionContext context) {
    final tasks = context.tasks;
    if (tasks == null) throw Exception('LynAI function 需要任务上下文');
    return tasks;
  }

  CalendarProvider _calendar(LynAIFunctionContext context) {
    final calendar = context.calendar;
    if (calendar == null) throw Exception('LynAI function 需要日历上下文');
    return calendar;
  }

  Map<String, dynamic> _pluginInfo(LynAIFunctionContext context) {
    final plugin = context.plugin;
    if (plugin == null) return _error('plugin.info 需要插件上下文');
    final manifest = plugin.manifest;
    return {
      'ok': true,
      'plugin': {
        'id': manifest.id,
        'name': manifest.name,
        'version': manifest.version,
        'author': manifest.author,
        'description': manifest.description,
        'permissions': manifest.permissions,
        'grantedPermissions': plugin.grantedPermissions,
      },
    };
  }

  Future<Map<String, dynamic>> _pluginConfigRead(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final plugins = context.plugins;
    final plugin = context.plugin;
    if (plugins == null || plugin == null) {
      return _error('plugin.config.read 需要插件上下文');
    }
    final requestedPath = (args['path'] as String? ?? '').trim();
    if (requestedPath.isNotEmpty &&
        requestedPath != plugin.manifest.config.path) {
      return _error('plugin.config.read 只能读取当前插件配置文件');
    }
    final rawValues = await plugins.loadConfig(plugin.id);
    final schema = await plugins.loadConfigSchema(plugin.id);
    return {
      'ok': true,
      'path': plugin.manifest.config.path,
      'schemaPath': plugin.manifest.config.schema,
      'values': schema?.applyDefaults(rawValues) ?? rawValues,
      'rawValues': rawValues,
    };
  }

  Future<Map<String, dynamic>> _pluginFileList(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final plugins = context.plugins;
    final plugin = context.plugin;
    if (plugins == null || plugin == null) {
      return _error('plugin.file.list 需要插件上下文');
    }
    final files = await plugins.listFiles(plugin.id);
    final hideUnmodified = args['hideUnmodified'] as bool? ?? false;
    final filtered = hideUnmodified
        ? files.where((f) => !f.isDefault).toList()
        : files;
    return {
      'ok': true,
      'files': filtered
          .map(
            (file) => {
              'path': file.path,
              'size': file.size,
              'isDirectory': file.isDirectory,
              'isEditable': file.isEditable,
              'isDefault': file.isDefault,
              'type': file.type,
            },
          )
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _pluginFileRead(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final plugins = context.plugins;
    final plugin = context.plugin;
    if (plugins == null || plugin == null) {
      return _error('plugin.file.read 需要插件上下文');
    }
    final path = (args['path'] as String? ?? '').trim();
    if (path.isEmpty) return _error('plugin.file.read 缺少 path');
    final content = await plugins.readFile(plugin.id, path);
    return {'ok': true, 'path': path, 'content': content};
  }

  /// 写入插件文件。
  Future<Map<String, dynamic>> _pluginFileWrite(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final plugins = context.plugins;
    final plugin = context.plugin;
    if (plugins == null || plugin == null) {
      return _error('plugin.file.write 需要插件上下文');
    }
    final path = (args['path'] as String? ?? '').trim();
    if (path.isEmpty) return _error('plugin.file.write 缺少 path');
    final content = (args['content'] as String? ?? '').toString();
    await plugins.writeEditableFile(plugin.id, path, content);
    return {'ok': true, 'path': path};
  }

  /// 删除插件文件。
  Future<Map<String, dynamic>> _pluginFileDelete(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final plugins = context.plugins;
    final plugin = context.plugin;
    if (plugins == null || plugin == null) {
      return _error('plugin.file.delete 需要插件上下文');
    }
    final path = (args['path'] as String? ?? '').trim();
    if (path.isEmpty) return _error('plugin.file.delete 缺少 path');
    await plugins.deleteFile(plugin.id, path);
    return {'ok': true, 'path': path};
  }

  /// 重命名插件文件。
  Future<Map<String, dynamic>> _pluginFileRename(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final plugins = context.plugins;
    final plugin = context.plugin;
    if (plugins == null || plugin == null) {
      return _error('plugin.file.rename 需要插件上下文');
    }
    final oldPath = (args['oldPath'] as String? ?? '').trim();
    final newPath = (args['newPath'] as String? ?? '').trim();
    if (oldPath.isEmpty || newPath.isEmpty) {
      return _error('plugin.file.rename 缺少 oldPath 或 newPath');
    }
    await plugins.renameFile(plugin.id, oldPath, newPath);
    return {'ok': true, 'oldPath': oldPath, 'newPath': newPath};
  }

  /// 获取当前对话总数。
  Map<String, dynamic> _conversationCount(LynAIFunctionContext context) {
    final conversations = context.conversations;
    if (conversations == null) return _error('对话上下文不可用');
    return {'ok': true, 'total': conversations.conversations.length};
  }

  /// 获取系统运行状态信息。
  Map<String, dynamic> _systemStatus(LynAIFunctionContext context) {
    String plat = 'unknown';
    try {
      plat = Platform.operatingSystem;
    } catch (_) {
      plat = 'web';
    }
    final now = DateTime.now();
    return {
      'ok': true,
      'appName': 'LynAI',
      'appVersion': _appVersion ?? 'dev',
      'platform': plat,
      'timestamp': now.toIso8601String(),
      'timezone': now.timeZoneName,
      'timezoneOffsetMinutes': now.timeZoneOffset.inMinutes,
    };
  }

  /// 通过 HTTP 请求获取远程资源。
  Future<Map<String, dynamic>> _httpFetch(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final url = (args['url'] as String? ?? '').trim();
    if (url.isEmpty) return _error('http.fetch 缺少 url');
    final method = (args['method'] as String? ?? 'GET').toUpperCase();
    final rawHeaders = args['headers'] as Map?;
    final body = args['body'] as String?;
    final headerMap = <String, String>{};
    if (rawHeaders != null) {
      rawHeaders.forEach((k, v) {
        headerMap[k.toString()] = v.toString();
      });
    }
    try {
      final uri = Uri.parse(url);
      final request = http.Request(method, uri);
      request.headers.addAll(headerMap);
      if (body != null && body.isNotEmpty) {
        request.body = body;
      }
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      return {
        'ok': true,
        'status': response.statusCode,
        'headers': response.headers,
        'body': response.body,
      };
    } catch (e) {
      return _error('http.fetch 请求失败: $e');
    }
  }

  Future<Map<String, dynamic>> _storageGet(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final plugins = context.plugins;
    final plugin = context.plugin;
    if (plugins == null || plugin == null) {
      return _error('plugin.storage.get 需要插件上下文');
    }
    final key = (args['key'] as String? ?? '').trim();
    if (key.isEmpty) {
      return {'ok': true, 'values': await plugins.loadStorage(plugin.id)};
    }
    return {
      'ok': true,
      'value': await plugins.readStorageValue(plugin.id, key),
    };
  }

  Future<Map<String, dynamic>> _storageSet(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final plugins = context.plugins;
    final plugin = context.plugin;
    if (plugins == null || plugin == null) {
      return _error('plugin.storage.set 需要插件上下文');
    }
    final key = (args['key'] as String? ?? '').trim();
    if (key.isEmpty) return _error('plugin.storage.set 缺少 key');
    await plugins.writeStorageValue(plugin.id, key, _jsonValue(args['value']));
    return {'ok': true};
  }

  Future<Map<String, dynamic>> _storageRemove(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final plugins = context.plugins;
    final plugin = context.plugin;
    if (plugins == null || plugin == null) {
      return _error('plugin.storage.remove 需要插件上下文');
    }
    final key = (args['key'] as String? ?? '').trim();
    if (key.isEmpty) return _error('plugin.storage.remove 缺少 key');
    await plugins.writeStorageValue(plugin.id, key, null);
    return {'ok': true};
  }

  Future<Map<String, dynamic>> _recycleBinPutData(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final plugin = context.plugin;
    if (plugin == null) return _error('recycleBin.putData 需要插件上下文');
    final category = (args['category'] as String? ?? 'data').trim();
    final title = (args['title'] as String? ?? '').trim();
    if (title.isEmpty) return _error('recycleBin.putData 缺少 title');
    final item = RecycleBinItem(
      owner: RecycleBinOwners.plugin(plugin.id),
      category: RecycleBinCategories.plugin(plugin.id, category),
      type: RecycleBinItemTypes.pluginData,
      title: title,
      preview: (args['preview'] as String? ?? '').trim(),
      payload: {
        'pluginId': plugin.id,
        'data': _jsonValue(args['data']),
        if ((args['restoreHandler'] as String? ?? '').trim().isNotEmpty)
          'restoreHandler': (args['restoreHandler'] as String).trim(),
        if ((args['deleteForeverHandler'] as String? ?? '').trim().isNotEmpty)
          'deleteForeverHandler': (args['deleteForeverHandler'] as String)
              .trim(),
      },
    );
    await _recycleBinRepository.add(item);
    return {'ok': true, 'item': item.toJson()};
  }

  Future<Map<String, dynamic>> _recycleBinPutFile(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final plugins = context.plugins;
    final plugin = context.plugin;
    if (plugins == null || plugin == null) {
      return _error('recycleBin.putFile 需要插件上下文');
    }
    final path = (args['path'] as String? ?? '').trim();
    if (path.isEmpty) return _error('recycleBin.putFile 缺少 path');
    if (!plugins.isEditableFile(plugin.id, path)) {
      return _error('recycleBin.putFile 只能处理 editableFiles 中声明的文件');
    }
    final content = await plugins.readFile(plugin.id, path);
    final title = (args['title'] as String? ?? '').trim();
    final item = RecycleBinItem(
      owner: RecycleBinOwners.plugin(plugin.id),
      category: RecycleBinCategories.pluginFiles(plugin.id),
      type: RecycleBinItemTypes.pluginFile,
      title: title.isEmpty ? path.split('/').last : title,
      preview: (args['preview'] as String? ?? '').trim(),
      payload: {
        'pluginId': plugin.id,
        'path': path,
        'content': content,
        'encoding': 'utf8',
      },
    );
    await _recycleBinRepository.add(item);
    if (args['deleteOriginal'] == true) {
      await plugins.deleteFile(plugin.id, path);
    }
    return {'ok': true, 'item': item.toJson()};
  }

  Future<Map<String, dynamic>> _recycleBinList(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final plugin = context.plugin;
    if (plugin == null) return _error('recycleBin.list 需要插件上下文');
    final category = (args['category'] as String?)?.trim();
    final owner = RecycleBinOwners.plugin(plugin.id);
    final items = (await _recycleBinRepository.load())
        .where((item) => item.owner == owner)
        .where(
          (item) => category == null || category.isEmpty
              ? true
              : item.category ==
                    RecycleBinCategories.plugin(plugin.id, category),
        )
        .map((item) => item.toJson())
        .toList();
    return {'ok': true, 'items': items};
  }

  Future<Map<String, dynamic>> _recycleBinRestore(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final plugins = context.plugins;
    final plugin = context.plugin;
    if (plugins == null || plugin == null) {
      return _error('recycleBin.restore 需要插件上下文');
    }
    final id = (args['id'] as String? ?? '').trim();
    if (id.isEmpty) return _error('recycleBin.restore 缺少 id');
    final owner = RecycleBinOwners.plugin(plugin.id);
    RecycleBinItem? item;
    for (final candidate in await _recycleBinRepository.load()) {
      if (candidate.id == id && candidate.owner == owner) {
        item = candidate;
        break;
      }
    }
    if (item == null) return _error('回收站项目不存在');
    if (item.type == RecycleBinItemTypes.pluginFile) {
      final path = item.payload['path'] as String?;
      final content = item.payload['content'] as String?;
      if (path == null || content == null) return _error('插件文件回收站数据损坏');
      await plugins.writeEditableFile(plugin.id, path, content);
      await _recycleBinRepository.remove(item.id);
      return {'ok': true, 'item': item.toJson()};
    }
    return {'ok': true, 'needsPluginRestore': true, 'item': item.toJson()};
  }

  Future<Map<String, dynamic>> _recycleBinDeleteForever(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final plugin = context.plugin;
    if (plugin == null) return _error('recycleBin.deleteForever 需要插件上下文');
    final id = (args['id'] as String? ?? '').trim();
    if (id.isEmpty) return _error('recycleBin.deleteForever 缺少 id');
    final owner = RecycleBinOwners.plugin(plugin.id);
    final exists = (await _recycleBinRepository.load()).any(
      (item) => item.id == id && item.owner == owner,
    );
    if (!exists) return _error('回收站项目不存在');
    await _recycleBinRepository.remove(id);
    return {'ok': true};
  }

  /// 恢复插件至初始状态。
  Future<Map<String, dynamic>> _pluginRestore(
    LynAIFunctionContext context,
  ) async {
    final plugins = context.plugins;
    final plugin = context.plugin;
    if (plugins == null || plugin == null) {
      return _error('plugin.restore 需要插件上下文');
    }
    final files = await plugins.listFiles(plugin.id);
    var deleted = 0;
    for (final file in files) {
      if (file.isDirectory) continue;
      final norm = file.path.replaceAll('\\', '/');
      if (norm == 'plugin.json') continue;
      if (norm.startsWith('defaults/')) continue;
      try {
        await plugins.deleteFile(plugin.id, file.path);
        deleted++;
      } catch (_) {}
    }
    return {'ok': true, 'deleted': deleted};
  }

  /// 执行插件自定义函数调用。
  ///
  /// 根据 name 分发到内置实现（stats / weather）或查找 manifest.functions
  /// 中的 Lua handler（预留扩展）。
  Future<Map<String, dynamic>> _pluginFunc(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final plugins = context.plugins;
    final plugin = context.plugin;
    if (plugins == null || plugin == null) {
      return _error('plugin.func 需要插件上下文');
    }
    final name = (args['name'] as String? ?? '').trim();
    if (name.isEmpty) return _error('plugin.func 缺少 name');
    if (!plugins.isFunctionEnabled(plugin.id, name)) {
      return _error('插件函数已禁用: $name');
    }
    return switch (name) {
      'stats' => _funcStats(context),
      'weather' => await _funcWeather(context),
      _ => _error('未知插件函数: $name'),
    };
  }

  /// 聚合统计：笔记总数、规范任务完成数/总数、对话数。
  Map<String, dynamic> _funcStats(LynAIFunctionContext context) {
    final features = context.features;
    final tasks = context.tasks?.tasks ?? const <Task>[];
    final conversations = context.conversations;
    final noteCount = features?.notes.length ?? 0;
    final done = tasks.where((task) => task.isCompleted).length;
    final total = tasks.length;
    return {
      'ok': true,
      'notes': noteCount,
      'todos_done': done,
      'todos_total': total,
      'conversations': conversations?.conversations.length ?? 0,
    };
  }

  /// 通过 wttr.in 获当前位置天气。
  Future<Map<String, dynamic>> _funcWeather(
    LynAIFunctionContext context,
  ) async {
    try {
      final response = await http.get(Uri.parse('https://wttr.in?format=j1'));
      if (response.statusCode != 200) {
        return _error('天气请求失败: ${response.statusCode}');
      }
      final data = jsonDecode(response.body);
      final current =
          (data['current_condition'] as List?)?.first as Map<String, dynamic>?;
      final area =
          (data['nearest_area'] as List?)?.first as Map<String, dynamic>?;
      final desc = (current?['weatherDesc'] as List?)?.first;
      return {
        'ok': true,
        'temp': current?['temp_C']?.toString() ?? '--',
        'condition': desc is Map ? desc['value']?.toString() ?? '--' : '--',
        'humidity': current?['humidity']?.toString() ?? '--',
        'location':
            (area?['areaName'] as List?)?.first?['value']?.toString() ?? '--',
      };
    } catch (e) {
      return _error('天气请求失败: $e');
    }
  }

  Map<String, dynamic> _toast(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) {
    final message = (args['message'] as String? ?? '').trim();
    if (message.isEmpty) return _error('ui.toast 缺少 message');
    context.showToast?.call(message);
    return {'ok': true};
  }

  Map<String, dynamic> _listTasks(
    TaskProvider tasks,
    Map<String, dynamic> args,
  ) {
    final query = (args['query'] as String? ?? '').trim().toLowerCase();
    final completed = args['completed'] as bool?;
    final listId = (args['listId'] as String? ?? '').trim();
    return {
      'ok': true,
      'tasks': tasks.tasks
          .where((task) {
            if (completed != null && task.isCompleted != completed) {
              return false;
            }
            if (listId.isNotEmpty &&
                tasks.entryForTask(task.id)?.taskListId != listId) {
              return false;
            }
            return query.isEmpty ||
                task.title.toLowerCase().contains(query) ||
                (task.note ?? '').toLowerCase().contains(query);
          })
          .map((task) => _taskJson(tasks, task))
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _createTask(
    TaskProvider tasks,
    Map<String, dynamic> args,
  ) async {
    final title = (args['title'] as String? ?? '').trim();
    if (title.isEmpty) return _error('tasks.create 缺少 title');
    final id = await tasks.addTask(
      title: title,
      note: _optionalString(args['note']),
      plannedDate: _localDateArg(args, 'plannedDate'),
      plannedTime: _localTimeArg(args, 'plannedTime'),
      dueDate: _localDateArg(args, 'dueDate'),
      dueTime: _localTimeArg(args, 'dueTime'),
      reminders: _taskRemindersArg(
        args,
        plannedDate: _localDateArg(args, 'plannedDate'),
        plannedTime: _localTimeArg(args, 'plannedTime'),
        dueDate: _localDateArg(args, 'dueDate'),
        dueTime: _localTimeArg(args, 'dueTime'),
      ),
      listId: _optionalString(args['listId']),
    );
    if (args['completed'] == true) await tasks.completeTask(id);
    return {'ok': true, 'task': _taskJson(tasks, tasks.taskById(id)!)};
  }

  Future<Map<String, dynamic>> _updateTask(
    TaskProvider tasks,
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String? ?? '').trim();
    final current = tasks.taskById(id);
    if (current == null) return _error('未找到任务: $id');
    final plannedDate = args.containsKey('plannedDate')
        ? _localDateArg(args, 'plannedDate')
        : current.plannedDate;
    final dueDate = args.containsKey('dueDate')
        ? _localDateArg(args, 'dueDate')
        : current.dueDate;
    final plannedTime = plannedDate == null
        ? null
        : args.containsKey('plannedTime')
        ? _localTimeArg(args, 'plannedTime')
        : current.plannedTime;
    final dueTime = dueDate == null
        ? null
        : args.containsKey('dueTime')
        ? _localTimeArg(args, 'dueTime')
        : current.dueTime;
    final updated = current.copyWith(
      title: args.containsKey('title')
          ? (args['title'] as String? ?? '').trim()
          : null,
      note: args.containsKey('note')
          ? _optionalString(args['note'])
          : current.note,
      plannedDate: plannedDate,
      plannedTime: plannedTime,
      dueDate: dueDate,
      dueTime: dueTime,
      reminders: _taskRemindersArg(
        args,
        current: current.reminders,
        plannedDate: plannedDate,
        plannedTime: plannedTime,
        dueDate: dueDate,
        dueTime: dueTime,
      ),
    );
    if (updated.title.isEmpty) return _error('任务标题不能为空');
    await tasks.updateTask(updated);
    if (args.containsKey('listId')) {
      await tasks.moveTask(id, _optionalString(args['listId']));
    }
    if (args['completed'] == true) await tasks.completeTask(id);
    if (args['completed'] == false) await tasks.uncompleteTask(id);
    return {'ok': true, 'task': _taskJson(tasks, tasks.taskById(id)!)};
  }

  Future<Map<String, dynamic>> _deleteTask(
    TaskProvider tasks,
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String? ?? '').trim();
    if (tasks.taskById(id) == null) return _error('未找到任务: $id');
    await tasks.deleteTask(id);
    return {'ok': true};
  }

  Map<String, dynamic> _listCalendar(
    CalendarProvider calendar,
    Map<String, dynamic> args,
  ) {
    final from = _dateArg(args, 'from');
    final to = _dateArg(args, 'to');
    return {
      'ok': true,
      'events': calendar.events
          .where((event) {
            final range = _eventRange(event);
            if (from != null && !range.$2.isAfter(from)) return false;
            if (to != null && !range.$1.isBefore(to)) return false;
            return true;
          })
          .map(_calendarEventJson)
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _createCalendar(
    CalendarProvider calendar,
    Map<String, dynamic> args,
  ) async {
    final title = (args['title'] as String? ?? '').trim();
    if (title.isEmpty) return _error('calendar.create 缺少 title');
    final spec = _calendarSpecArg(args);
    final id = await calendar.addEvent(
      title: title,
      note: _optionalString(args['note']),
      spec: spec,
      reminders: _calendarRemindersArg(args, spec: spec),
    );
    return {'ok': true, 'event': _calendarEventJson(calendar.getEvent(id)!)};
  }

  Future<Map<String, dynamic>> _updateCalendar(
    CalendarProvider calendar,
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String? ?? '').trim();
    final current = calendar.getEvent(id);
    if (current == null) return _error('未找到日历事件: $id');
    final hasSpec = args.keys.any(
      const {
        'allDay',
        'start',
        'end',
        'startDate',
        'endDateExclusive',
      }.contains,
    );
    final spec = hasSpec
        ? _calendarSpecArg(args, current: current.spec)
        : current.spec;
    final updated = current.copyWith(
      title: args.containsKey('title')
          ? (args['title'] as String? ?? '').trim()
          : null,
      note: args.containsKey('note')
          ? _optionalString(args['note'])
          : current.note,
      spec: spec,
      reminders: _calendarRemindersArg(
        args,
        current: current.reminders,
        spec: spec,
      ),
    );
    if (updated.title.isEmpty) return _error('日历事件标题不能为空');
    await calendar.updateEvent(updated);
    return {'ok': true, 'event': _calendarEventJson(calendar.getEvent(id)!)};
  }

  Future<Map<String, dynamic>> _deleteCalendar(
    CalendarProvider calendar,
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String? ?? '').trim();
    if (calendar.getEvent(id) == null) return _error('未找到日历事件: $id');
    await calendar.deleteEvent(id);
    return {'ok': true};
  }

  Map<String, dynamic> _listAnniversaries(
    CalendarProvider calendar,
    Map<String, dynamic> args,
  ) {
    final query = (args['query'] as String? ?? '').trim().toLowerCase();
    return {
      'ok': true,
      'anniversaries': calendar.anniversaries
          .where(
            (item) =>
                query.isEmpty ||
                item.title.toLowerCase().contains(query) ||
                (item.note ?? '').toLowerCase().contains(query),
          )
          .map(_anniversaryJson)
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _createAnniversary(
    CalendarProvider calendar,
    Map<String, dynamic> args,
  ) async {
    final title = (args['title'] as String? ?? '').trim();
    if (title.isEmpty) return _error('anniversaries.create 缺少 title');
    final id = await calendar.addAnniversary(
      title: title,
      note: _optionalString(args['note']),
      spec: _anniversarySpecArg(args),
      showYearCount: args['showYearCount'] == true,
      reminders: _anniversaryRemindersArg(args),
    );
    return {
      'ok': true,
      'anniversary': _anniversaryJson(calendar.getAnniversary(id)!),
    };
  }

  Future<Map<String, dynamic>> _updateAnniversary(
    CalendarProvider calendar,
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String? ?? '').trim();
    final current = calendar.getAnniversary(id);
    if (current == null) return _error('未找到纪念日: $id');
    final hasSpec = args.keys.any(
      const {'type', 'date', 'month', 'day', 'sourceYear'}.contains,
    );
    final updated = current.copyWith(
      title: args.containsKey('title')
          ? (args['title'] as String? ?? '').trim()
          : null,
      note: args.containsKey('note')
          ? _optionalString(args['note'])
          : current.note,
      spec: hasSpec
          ? _anniversarySpecArg(args, current: current.spec)
          : current.spec,
      showYearCount: args['showYearCount'] as bool?,
      reminders: _anniversaryRemindersArg(args, current: current.reminders),
    );
    if (updated.title.isEmpty) return _error('纪念日标题不能为空');
    await calendar.updateAnniversary(updated);
    return {
      'ok': true,
      'anniversary': _anniversaryJson(calendar.getAnniversary(id)!),
    };
  }

  Future<Map<String, dynamic>> _deleteAnniversary(
    CalendarProvider calendar,
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String? ?? '').trim();
    if (calendar.getAnniversary(id) == null) return _error('未找到纪念日: $id');
    await calendar.deleteAnniversary(id);
    return {'ok': true};
  }

  Map<String, dynamic> _listSchedules(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) {
    final from = _dateArg(args, 'from');
    final to = _dateArg(args, 'to');
    final taskItems = (_listTasks(_tasks(context), const {})['tasks'] as List)
        .where((item) => item['plannedDate'] != null)
        .map((item) => _legacyTaskScheduleJson(Map<String, dynamic>.from(item)))
        .where((item) {
          final start = DateTime.parse(item['start'] as String);
          if (from != null && start.isBefore(from)) return false;
          if (to != null && !start.isBefore(to)) return false;
          return true;
        });
    final eventItems =
        (_listCalendar(_calendar(context), args)['events'] as List).map(
          (item) => _legacyEventScheduleJson(Map<String, dynamic>.from(item)),
        );
    final items = [...taskItems, ...eventItems];
    items.sort(
      (a, b) => a['start'].toString().compareTo(b['start'].toString()),
    );
    return {'ok': true, 'schedules': items};
  }

  Future<Map<String, dynamic>> _createSchedule(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final start = _dateArg(args, 'start');
    if (start == null) return _error('schedules.create 缺少 start');
    if (_legacyScheduleIsTask(args)) {
      final result = await _createTask(_tasks(context), {
        ...args,
        'plannedDate': LocalDate.fromDateTime(start).toString(),
        'plannedTime': LocalTime.fromDateTime(start).toString(),
      });
      return {
        'ok': result['ok'],
        if (result['task'] != null)
          'schedule': _legacyTaskScheduleJson(
            Map<String, dynamic>.from(result['task'] as Map),
          ),
        if (result['error'] != null) 'error': result['error'],
      };
    }
    final result = await _createCalendar(_calendar(context), args);
    return {
      'ok': result['ok'],
      if (result['event'] != null)
        'schedule': _legacyEventScheduleJson(
          Map<String, dynamic>.from(result['event'] as Map),
        ),
      if (result['error'] != null) 'error': result['error'],
    };
  }

  Future<Map<String, dynamic>> _updateSchedule(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String? ?? '').trim();
    final task = context.tasks?.taskById(id);
    final event = context.calendar?.getEvent(id);
    if (task != null && event != null) {
      return _error('日程 id 同时匹配任务和事件: $id');
    }
    final requestedKind = _legacyScheduleKind(args);
    if (task != null && requestedKind == _LegacyScheduleKind.schedule) {
      return _convertTaskToSchedule(context, task, args);
    }
    if (event != null && requestedKind == _LegacyScheduleKind.task) {
      return _convertScheduleToTask(context, event, args);
    }
    if (task != null || requestedKind == _LegacyScheduleKind.task) {
      final start = _dateArg(args, 'start');
      final result = await _updateTask(_tasks(context), {
        ...args,
        if (start != null)
          'plannedDate': LocalDate.fromDateTime(start).toString(),
        if (start != null)
          'plannedTime': LocalTime.fromDateTime(start).toString(),
      });
      return {
        'ok': result['ok'],
        if (result['task'] != null)
          'schedule': _legacyTaskScheduleJson(
            Map<String, dynamic>.from(result['task'] as Map),
          ),
        if (result['error'] != null) 'error': result['error'],
      };
    }
    if (event == null) return _error('未找到日程或任务: $id');
    final result = await _updateCalendar(_calendar(context), args);
    return {
      'ok': result['ok'],
      if (result['event'] != null)
        'schedule': _legacyEventScheduleJson(
          Map<String, dynamic>.from(result['event'] as Map),
        ),
      if (result['error'] != null) 'error': result['error'],
    };
  }

  Future<Map<String, dynamic>> _convertTaskToSchedule(
    LynAIFunctionContext context,
    Task task,
    Map<String, dynamic> args,
  ) async {
    final start = _dateArg(args, 'start') ?? _taskPlannedDateTime(task);
    final end = _dateArg(args, 'end');
    if (start == null || end == null) {
      return _error('任务转换为日程需要 start、end');
    }
    final title = args.containsKey('title')
        ? (args['title'] as String? ?? '').trim()
        : task.title;
    if (title.isEmpty) return _error('日历事件标题不能为空');
    final event = CalendarEvent(
      id: task.id,
      title: title,
      note: args.containsKey('note')
          ? _optionalString(args['note'])
          : task.note,
      spec: TimedCalendarEventSpec(start: start, end: end),
      reminders: [
        for (final reminder in task.reminders)
          if (reminder.anchor == ItemReminderAnchor.taskPlanned)
            reminder.copyWith(
              anchor: ItemReminderAnchor.eventStart,
              dateOnlyTime: null,
            ),
      ],
      createdAt: task.createdAt,
      updatedAt: DateTime.now(),
    );
    final calendar = _calendar(context);
    final previousEvents = calendar.events;
    final previousAnniversaries = calendar.anniversaries;
    final tasks = _tasks(context);
    final previousTasks = tasks.tasks;
    final previousLists = tasks.lists;
    final previousEntries = tasks.entries;
    await _convertLegacyScheduleKind(
      description: '任务转换为日程',
      saveTarget: () => calendar.restoreEvent(event),
      removeSource: () => tasks.replaceAll(
        tasks: previousTasks.where((item) => item.id != task.id).toList(),
        lists: previousLists,
        entries: previousEntries,
      ),
      restoreSource: () => tasks.replaceAll(
        tasks: previousTasks,
        lists: previousLists,
        entries: previousEntries,
      ),
      rollbackTarget: () => calendar.replaceAll(
        events: previousEvents,
        anniversaries: previousAnniversaries,
      ),
    );
    return {
      'ok': true,
      'schedule': _legacyEventScheduleJson(_calendarEventJson(event)),
    };
  }

  Future<Map<String, dynamic>> _convertScheduleToTask(
    LynAIFunctionContext context,
    CalendarEvent event,
    Map<String, dynamic> args,
  ) async {
    final suppliedStart = _dateArg(args, 'start');
    final start = suppliedStart ?? _eventRange(event).$1.toLocal();
    final hasTime =
        suppliedStart != null || event.spec is TimedCalendarEventSpec;
    final title = args.containsKey('title')
        ? (args['title'] as String? ?? '').trim()
        : event.title;
    if (title.isEmpty) return _error('任务标题不能为空');
    final now = DateTime.now();
    final task = Task(
      id: event.id,
      title: title,
      note: args.containsKey('note')
          ? _optionalString(args['note'])
          : event.note,
      plannedDate: LocalDate.fromDateTime(start),
      plannedTime: hasTime ? LocalTime.fromDateTime(start) : null,
      createdAt: event.createdAt,
      updatedAt: now,
      reminders: [
        for (final reminder in event.reminders)
          reminder.copyWith(anchor: ItemReminderAnchor.taskPlanned),
      ],
    );
    final tasks = _tasks(context);
    final previousTasks = tasks.tasks;
    final previousLists = tasks.lists;
    final previousEntries = tasks.entries;
    final calendar = _calendar(context);
    final previousEvents = calendar.events;
    final previousAnniversaries = calendar.anniversaries;
    await _convertLegacyScheduleKind(
      description: '日程转换为任务',
      saveTarget: () => tasks.restoreTask(task),
      removeSource: () => calendar.replaceAll(
        events: previousEvents.where((item) => item.id != event.id).toList(),
        anniversaries: previousAnniversaries,
      ),
      restoreSource: () => calendar.replaceAll(
        events: previousEvents,
        anniversaries: previousAnniversaries,
      ),
      rollbackTarget: () => tasks.replaceAll(
        tasks: previousTasks,
        lists: previousLists,
        entries: previousEntries,
      ),
    );
    return {
      'ok': true,
      'schedule': _legacyTaskScheduleJson(_taskJson(tasks, task)),
    };
  }

  Future<void> _convertLegacyScheduleKind({
    required String description,
    required Future<void> Function() saveTarget,
    required Future<void> Function() removeSource,
    required Future<void> Function() restoreSource,
    required Future<void> Function() rollbackTarget,
  }) async {
    try {
      await saveTarget();
    } catch (error) {
      final compensationError = await _bestEffortCompensation(rollbackTarget);
      throw Exception(
        '$description失败：目标分区保存失败: $error'
        '${_compensationErrorSuffix(compensationError)}',
      );
    }

    try {
      await removeSource();
    } catch (error) {
      // 任务与日历属于独立分区，无法使用数据库事务，只能显式恢复源并回滚目标。
      final sourceError = await _bestEffortCompensation(restoreSource);
      final targetError = await _bestEffortCompensation(rollbackTarget);
      final compensationErrors = [
        if (sourceError != null) '恢复源分区失败: $sourceError',
        if (targetError != null) '回滚目标分区失败: $targetError',
      ];
      throw Exception(
        '$description失败：源分区移除保存失败: $error'
        '${_compensationErrorSuffix(compensationErrors)}',
      );
    }
  }

  Future<Object?> _bestEffortCompensation(
    Future<void> Function() compensate,
  ) async {
    try {
      await compensate();
      return null;
    } catch (error) {
      return error;
    }
  }

  String _compensationErrorSuffix(Object? error) {
    if (error == null || error is List && error.isEmpty) return '';
    if (error is List) return '；补偿未完全成功: ${error.join('; ')}';
    return '；补偿失败: $error';
  }

  Future<Map<String, dynamic>> _deleteSchedule(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String? ?? '').trim();
    if (context.tasks?.taskById(id) != null) {
      return _deleteTask(_tasks(context), args);
    }
    return _deleteCalendar(_calendar(context), args);
  }

  Map<String, dynamic> _listNotes(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) {
    final query = (args['query'] as String? ?? '').trim();
    final matcher = _TextMatcher(query);
    final folderId = (args['folderId'] as String? ?? '').trim();
    final includeContent = args['includeContent'] as bool? ?? false;
    if (includeContent && query.isEmpty) {
      return _error('includeContent 需要提供 query，避免一次读取全部笔记正文');
    }
    final notes = features.notes.where((note) {
      if (folderId.isNotEmpty && note.folderId != folderId) return false;
      if (matcher.isEmpty) return true;
      return matcher.matches(note.title) || matcher.matches(note.content);
    });
    return {
      'ok': true,
      'notes': notes
          .map((note) => _noteSummaryJson(note, includeContent: includeContent))
          .toList(),
    };
  }

  Map<String, dynamic> _listNotesForPlugin(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) {
    final query = (args['query'] as String? ?? '').trim().toLowerCase();
    return {
      'ok': true,
      'notes': features.notes
          .where((note) {
            if (query.isEmpty) return true;
            return note.title.toLowerCase().contains(query) ||
                note.content.toLowerCase().contains(query);
          })
          .map(
            (note) => _pluginNoteJson(
              note,
              includeContent: args['includeContent'] == true,
            ),
          )
          .toList(),
    };
  }

  Map<String, dynamic> _readNoteForPlugin(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) {
    final id = (args['id'] as String? ?? '').trim();
    final note = id.isEmpty ? null : features.getNote(id);
    if (note == null) return _error('未找到笔记: $id');
    return {'ok': true, 'note': _pluginNoteJson(note, includeContent: true)};
  }

  Future<Map<String, dynamic>> _readNote(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) async {
    final selected = await _selectNoteForTool(features, args);
    if (selected.error != null) return _error(selected.error!);
    return _noteReadResult(features, selected.note!);
  }

  Future<_SelectedNote> _selectNoteForTool(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String? ?? '').trim();
    final title = (args['title'] as String? ?? '').trim().toLowerCase();
    final query = (args['query'] as String? ?? '').trim();
    final pageId = (args['pageId'] as String? ?? '').trim();
    final pageTitle = (args['pageTitle'] as String? ?? '').trim();
    final matcher = _TextMatcher(query);

    Note? note;
    if (id.isNotEmpty) note = features.getNote(id);
    if (note == null && title.isNotEmpty) {
      note = _findNote(
        features,
        (candidate) =>
            _scoreNoteMatch(candidate, query: title, preferTitle: true),
      );
    }
    if (note == null && !matcher.isEmpty) {
      note = _findNote(
        features,
        (candidate) => _scoreNoteMatch(candidate, matcher: matcher),
      );
    }
    if (note == null) {
      return const _SelectedNote.error('未找到匹配的笔记，请先调用 list_notes 查看可用笔记');
    }
    if (pageId.isNotEmpty || pageTitle.isNotEmpty) {
      final page = _findNotePage(
        features,
        note.id,
        pageId: pageId,
        pageTitle: pageTitle,
      );
      if (page == null) {
        return _SelectedNote.error(
          '未找到笔记分页: ${pageId.isNotEmpty ? pageId : pageTitle}',
        );
      }
      await features.selectNotePage(note.id, page.id);
      note = features.getNote(note.id);
      if (note == null) return const _SelectedNote.error('切换分页后未找到笔记');
    }
    return _SelectedNote(note: note);
  }

  Map<String, dynamic> _noteReadResult(FeatureProvider features, Note note) {
    final activePage = features.activeNotePage(note.id);
    final pages = features.notePages(note.id);
    return {
      'ok': true,
      'note': {
        'id': note.id,
        'title': note.title,
        'content': note.content,
        if (activePage != null) 'pageId': activePage.id,
        if (activePage != null) 'pageTitle': activePage.title,
        if (note.folderId != null) 'folderId': note.folderId,
        'createdAt': note.createdAt.toIso8601String(),
        'updatedAt': note.updatedAt.toIso8601String(),
        'wrap': note.wrap,
      },
      if (activePage != null) 'activePage': _notePageJson(activePage),
      if (pages.isNotEmpty) 'pages': pages.map(_notePageJson).toList(),
      'outline': _noteOutline(note.content),
      'contentHash': _contentHash(note.content),
      'currentRevisionId': note.currentRevisionId,
      'lineCount': _splitNoteLines(note.content).length,
      'lineNumberBase': 1,
      'appendStartLine': _splitNoteLines(note.content).length + 1,
      'lineEditHint':
          'notes.edit/notes.proposeEdit 的 startLine 从 1 开始，对应 numberedLines.line；替换/删除时建议带 expectedLines 校验原文；startLine=lineCount+1 且 deleteCount=0 表示追加到末尾。',
      'numberedLines': _numberedNoteLines(note.content),
    };
  }

  StorageV2NotePage? _findNotePage(
    FeatureProvider features,
    String noteId, {
    required String pageId,
    required String pageTitle,
  }) {
    final pages = features.notePages(noteId);
    if (pages.isEmpty) return null;
    if (pageId.isNotEmpty) {
      for (final page in pages) {
        if (page.id == pageId) return page;
      }
      return null;
    }
    final normalized = pageTitle.toLowerCase();
    for (final page in pages) {
      if (page.title.toLowerCase() == normalized ||
          page.fileName.toLowerCase() == normalized) {
        return page;
      }
    }
    for (final page in pages) {
      if (page.title.toLowerCase().contains(normalized) ||
          page.fileName.toLowerCase().contains(normalized)) {
        return page;
      }
    }
    return null;
  }

  Note? _findNote(FeatureProvider features, int Function(Note note) score) {
    Note? best;
    var bestScore = 0;
    for (final note in features.notes) {
      final currentScore = score(note);
      if (currentScore <= 0) continue;
      if (best == null ||
          currentScore > bestScore ||
          (currentScore == bestScore &&
              note.updatedAt.isAfter(best.updatedAt))) {
        best = note;
        bestScore = currentScore;
      }
    }
    return best;
  }

  int _scoreNoteMatch(
    Note note, {
    String? query,
    _TextMatcher? matcher,
    bool preferTitle = false,
  }) {
    if (matcher != null && matcher.isRegex) {
      if (matcher.matches(note.title)) return 250;
      if (!preferTitle && matcher.matches(note.content)) return 100;
      return 0;
    }
    final normalizedQuery = (query ?? matcher?.query ?? '').toLowerCase();
    if (normalizedQuery.isEmpty) return 0;
    final normalizedTitle = note.title.toLowerCase();
    final normalizedContent = note.content.toLowerCase();
    if (normalizedTitle == normalizedQuery) return preferTitle ? 600 : 500;
    if (normalizedTitle.startsWith(normalizedQuery)) {
      return preferTitle ? 450 : 350;
    }
    if (normalizedTitle.contains(normalizedQuery)) {
      return preferTitle ? 300 : 250;
    }
    if (!preferTitle && normalizedContent.contains(normalizedQuery)) return 100;
    return 0;
  }

  Future<Map<String, dynamic>> _saveNote(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) async {
    final title = (args['title'] as String? ?? '').trim();
    final content = args['content'] as String? ?? '';
    final id = (args['id'] as String? ?? '').trim();
    final append = args['append'] as bool? ?? false;
    final hasContent = args.containsKey('content');
    final hasFolderId = args.containsKey('folderId');
    final folderId = (args['folderId'] as String? ?? '').trim();
    if (hasFolderId &&
        folderId.isNotEmpty &&
        features.getNoteFolder(folderId) == null) {
      return _error('未找到笔记文件夹: $folderId');
    }
    if (id.isEmpty) {
      if (title.isEmpty) return _error('创建笔记需要 title');
      if (!hasContent) return _error('创建笔记需要 content');
      final newId = await features.addNoteWithContent(
        title,
        content,
        folderId: hasFolderId && folderId.isNotEmpty ? folderId : null,
      );
      final note = features.getNote(newId);
      if (note == null) return _error('创建笔记失败');
      return _noteSaveResult(
        note,
        before: '',
        contentChanged: content.isNotEmpty,
        revisionId: note.currentRevisionId,
      );
    }
    final selected = await _selectNoteForTool(features, args);
    if (selected.error != null) return _error(selected.error!);
    final note = selected.note!;
    if (title.isEmpty && !hasContent && !hasFolderId) {
      return _error('修改笔记需要 title、content 或 folderId');
    }
    final nextContent = !hasContent
        ? note.content
        : append && note.content.trim().isNotEmpty
        ? '${note.content}\n\n$content'
        : content;
    final updated = note.copyWith(
      title: title.isEmpty ? null : title,
      folderId: hasFolderId
          ? (folderId.isEmpty ? null : folderId)
          : note.folderId,
    );
    if (updated.title != note.title || updated.folderId != note.folderId) {
      await features.updateNote(updated);
    }
    NoteRevision? revision;
    if (hasContent) {
      revision = await features.saveNoteContent(note.id, nextContent);
    }
    final savedNote = features.getNote(note.id) ?? updated;
    final contentChanged = hasContent && note.content != savedNote.content;
    return _noteSaveResult(
      savedNote,
      before: note.content,
      contentChanged: contentChanged,
      revisionId: contentChanged ? revision?.id : null,
      includeDiff: hasContent,
    );
  }

  Map<String, dynamic> _noteSaveResult(
    Note note, {
    required String before,
    required bool contentChanged,
    required String? revisionId,
    bool includeDiff = true,
  }) {
    return {
      'ok': true,
      'note': note.toJson(),
      'contentHash': _contentHash(note.content),
      'lineCount': _splitNoteLines(note.content).length,
      'currentRevisionId': note.currentRevisionId,
      'timelineSaved': revisionId != null && contentChanged,
      'revisionId': revisionId,
      'contentChanged': contentChanged,
      if (includeDiff) 'diff': _lineDiff(before, note.content),
      if (includeDiff) 'diffSummary': _diffSummary(before, note.content),
      if (includeDiff)
        'lineDiffSummary': _lineDiffSummary(before, note.content),
    };
  }

  Future<Map<String, dynamic>> _editNote(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) async {
    final parsed = await _parseNoteEditArgs(
      features,
      args,
      emptyMessage: 'notes.edit 需要 edits',
    );
    if (parsed.error != null) return _error(parsed.error!);
    final note = parsed.note!;
    final editResult = _applyLineEdits(note.content, parsed.edits);
    if (editResult.error != null) return _error(editResult.error!);
    final nextContent = editResult.content!;
    final revision = nextContent == note.content
        ? null
        : await features.saveNoteContent(
            note.id,
            nextContent,
            baseRevisionId: parsed.baseRevisionId,
          );
    final savedNote = features.getNote(note.id) ?? note;
    return {
      'ok': true,
      'note': savedNote.toJson(),
      'contentHash': _contentHash(savedNote.content),
      'lineCount': _splitNoteLines(savedNote.content).length,
      'currentRevisionId': savedNote.currentRevisionId,
      'timelineSaved': revision != null,
      'revisionId': revision?.id,
      'contentChanged': nextContent != note.content,
      'diff': _lineDiff(note.content, savedNote.content),
      'diffSummary': _diffSummary(note.content, savedNote.content),
      'lineDiffSummary': _lineDiffSummary(note.content, savedNote.content),
    };
  }

  Future<Map<String, dynamic>> _proposeNoteEdit(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) async {
    final parsed = await _parseNoteEditArgs(
      features,
      args,
      emptyMessage: 'notes.proposeEdit 需要 edits',
    );
    if (parsed.error != null) return _error(parsed.error!);
    final note = parsed.note!;
    final editResult = _applyLineEdits(note.content, parsed.edits);
    if (editResult.error != null) return _error(editResult.error!);
    final nextContent = editResult.content!;
    if (nextContent == note.content) return _error('修改建议没有产生内容变化');
    final proposal = _proposalFromEdits(
      note: note,
      pageId: features.activeNotePage(note.id)?.id,
      edits: parsed.edits,
      baseRevisionId: parsed.baseRevisionId,
    );
    await features.setNoteEditProposal(proposal);
    return {
      'ok': true,
      'proposal': proposal.toJson(),
      'note': note.toJson(),
      'contentHash': _contentHash(note.content),
      'lineCount': _splitNoteLines(note.content).length,
      'currentRevisionId': note.currentRevisionId,
      'contentChanged': true,
      'timelineSaved': false,
      'diff': _lineDiff(note.content, nextContent),
      'diffSummary': _diffSummary(note.content, nextContent),
      'lineDiffSummary': _lineDiffSummary(note.content, nextContent),
    };
  }

  Future<_ParsedNoteEdit> _parseNoteEditArgs(
    FeatureProvider features,
    Map<String, dynamic> args, {
    required String emptyMessage,
  }) async {
    final selected = await _selectNoteForTool(features, args);
    if (selected.error != null) return _ParsedNoteEdit.error(selected.error!);
    final note = selected.note!;
    final expectedHash = (args['expectedContentHash'] as String? ?? '').trim();
    final currentHash = _contentHash(note.content);
    if (expectedHash.isNotEmpty && expectedHash != currentHash) {
      return const _ParsedNoteEdit.error('笔记内容已变化，请重新 read_note 后再编辑');
    }
    final rawEdits = args['edits'];
    if (rawEdits is! List || rawEdits.isEmpty) {
      return _ParsedNoteEdit.error(emptyMessage);
    }
    final edits = <_NoteLineEdit>[];
    for (final raw in rawEdits) {
      final edit = _NoteLineEdit.fromRaw(raw);
      if (edit == null) return const _ParsedNoteEdit.error('edits 格式错误');
      edits.add(edit);
    }
    final baseRevisionId = (args['baseRevisionId'] as String? ?? '').trim();
    return _ParsedNoteEdit(
      note: note,
      edits: edits,
      baseRevisionId: baseRevisionId.isEmpty ? null : baseRevisionId,
    );
  }

  Future<Map<String, dynamic>> _deleteNote(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String? ?? '').trim();
    if (id.isEmpty) return _error('notes.delete 缺少 id');
    await features.deleteNote(id);
    return {'ok': true};
  }

  Map<String, dynamic> _listNotePages(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) {
    final id = (args['id'] as String? ?? '').trim();
    final note = features.getNote(id);
    if (note == null) return _error('未找到笔记: $id');
    final activePage = features.activeNotePage(id);
    return {
      'ok': true,
      'noteId': id,
      'activePageId': activePage?.id,
      'pages': features.notePages(id).map(_notePageJson).toList(),
    };
  }

  Future<Map<String, dynamic>> _saveNotePage(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) async {
    final noteId = (args['id'] as String? ?? '').trim();
    final note = features.getNote(noteId);
    if (note == null) return _error('未找到笔记: $noteId');
    final pageId = (args['pageId'] as String? ?? '').trim();
    final title = (args['title'] as String? ?? '').trim();
    final delete = args['delete'] == true;
    final move = (args['move'] as String? ?? '').trim().toLowerCase();
    if (delete) {
      if (pageId.isEmpty) return _error('删除分页需要 pageId');
      final deleted = await features.deleteNotePage(noteId, pageId);
      if (!deleted) return _error('删除分页失败，至少保留一个分页');
      return _listNotePages(features, {'id': noteId});
    }
    if (move.isNotEmpty) {
      if (pageId.isEmpty) return _error('移动分页需要 pageId');
      final delta = switch (move) {
        'up' => -1,
        'down' => 1,
        _ => 0,
      };
      if (delta == 0) return _error('move 只支持 up 或 down');
      final moved = await features.moveNotePage(noteId, pageId, delta);
      if (!moved) return _error('分页无法继续移动');
      return _listNotePages(features, {'id': noteId});
    }
    if (pageId.isEmpty) {
      final newPageId = await features.addNotePage(noteId, title);
      if (newPageId == null) return _error('当前存储不支持分页');
      return _noteReadResult(features, features.getNote(noteId) ?? note);
    }
    if (title.isEmpty) return _error('重命名分页需要 title');
    await features.renameNotePage(noteId, pageId, title);
    final page = _findNotePage(features, noteId, pageId: pageId, pageTitle: '');
    return {'ok': true, 'page': page == null ? null : _notePageJson(page)};
  }

  Map<String, dynamic> _listNoteFolders(FeatureProvider features) {
    final counts = <String, int>{};
    for (final note in features.notes) {
      final fid = note.folderId;
      if (fid != null) counts[fid] = (counts[fid] ?? 0) + 1;
    }
    return {
      'ok': true,
      'folders': features.noteFolders.map((folder) {
        return {
          'id': folder.id,
          'title': folder.title,
          'createdAt': folder.createdAt.toIso8601String(),
          'updatedAt': folder.updatedAt.toIso8601String(),
          'noteCount': counts[folder.id] ?? 0,
        };
      }).toList(),
    };
  }

  Future<Map<String, dynamic>> _saveNoteFolder(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String? ?? '').trim();
    final title = (args['title'] as String? ?? '').trim();
    final delete = _boolArg(args, 'delete') ?? false;
    if (id.isEmpty) {
      if (delete) return _error('删除文件夹需要 id');
      if (title.isEmpty) return _error('创建笔记文件夹需要 title');
      final newId = await features.addNoteFolder(title);
      final folder = features.getNoteFolder(newId);
      return {'ok': true, 'folder': folder?.toJson()};
    }
    final folder = features.getNoteFolder(id);
    if (folder == null) return _error('未找到笔记文件夹: $id');
    if (delete) {
      await features.deleteNoteFolder(id);
      return {'ok': true, 'deleted': true};
    }
    if (title.isEmpty) return _error('重命名笔记文件夹需要 title');
    final updated = folder.copyWith(title: title);
    await features.updateNoteFolder(updated);
    return {'ok': true, 'folder': updated.toJson()};
  }

  Map<String, dynamic> _listTodoLists(
    TaskProvider tasks,
    Map<String, dynamic> args,
  ) {
    final query = (args['query'] as String? ?? '').trim().toLowerCase();
    final includeItems = _boolArg(args, 'includeItems') ?? false;
    final lists = tasks.lists.where((list) {
      final items = tasks.tasksForList(list.id);
      if (query.isEmpty) return true;
      return list.title.toLowerCase().contains(query) ||
          items.any((item) => item.title.toLowerCase().contains(query));
    });
    return {
      'ok': true,
      'todoLists': lists.map((list) {
        final items = tasks.tasksForList(list.id);
        final done = items.where((item) => item.isCompleted).length;
        return {
          'id': list.id,
          'title': list.title,
          'createdAt': list.createdAt.toIso8601String(),
          'updatedAt': list.updatedAt.toIso8601String(),
          'totalItems': items.length,
          'doneItems': done,
          'totalCount': items.length,
          'doneCount': done,
          if (includeItems) 'items': items.map(_legacyTodoItemJson).toList(),
        };
      }).toList(),
    };
  }

  Map<String, dynamic> _readTodoList(
    TaskProvider tasks,
    Map<String, dynamic> args,
  ) {
    final list = _findTodoList(tasks, args);
    if (list == null) return _error('未找到匹配的待办清单，请先调用 list_todo_lists 查看可用清单');
    return {'ok': true, 'todoList': _legacyTodoListJson(tasks, list)};
  }

  Future<Map<String, dynamic>> _saveTodoList(
    TaskProvider tasks,
    Map<String, dynamic> args,
  ) async {
    final title = (args['title'] as String? ?? '').trim();
    final id = (args['id'] as String? ?? '').trim();
    final rawItems = args['items'];
    final current = id.isEmpty ? null : tasks.listById(id);
    if (id.isNotEmpty && current == null) return _error('未找到待办清单: $id');
    if (current == null && title.isEmpty) return _error('创建待办清单需要 title');
    if (current != null && title.isEmpty && rawItems is! List) {
      return _error('修改待办清单需要 title 或 items');
    }
    if (current == null && rawItems is! List) {
      final listId = await tasks.addList(title);
      return {
        'ok': true,
        'todoList': _legacyTodoListJson(tasks, tasks.listById(listId)!),
      };
    }

    final now = DateTime.now();
    final listId = current?.id ?? _uuid.v4();
    final list = current == null
        ? TaskList(
            id: listId,
            title: title,
            sortOrder: tasks.lists.length,
            createdAt: now,
            updatedAt: now,
          )
        : current.copyWith(title: title.isEmpty ? null : title, updatedAt: now);
    if (rawItems is! List) {
      await tasks.updateList(list);
      return {
        'ok': true,
        'todoList': _legacyTodoListJson(tasks, tasks.listById(listId)!),
      };
    }

    final existingTaskIds = tasks.tasks.map((task) => task.id).toSet();
    final taskById = current == null
        ? const <String, Task>{}
        : {for (final task in tasks.tasksForList(listId)) task.id: task};
    final selected = <Task>[];
    final selectedIds = <String>{};
    for (final raw in rawItems) {
      final item = _legacyTodoTaskFromRaw(raw, taskById, existingTaskIds, now);
      if (item == null || !selectedIds.add(item.id)) continue;
      selected.add(item);
    }
    final replacements = {for (final task in selected) task.id: task};
    final replacedTaskIds = taskById.keys.where(
      (taskId) => !selectedIds.contains(taskId),
    );
    final nextTasks = <Task>[
      for (final task in tasks.tasks)
        if (!replacedTaskIds.contains(task.id))
          replacements.remove(task.id) ?? task,
      ...replacements.values,
    ];
    final nextLists = <TaskList>[
      for (final existing in tasks.lists)
        if (existing.id == listId) list else existing,
      if (current == null) list,
    ];
    final nextEntries = <TaskListEntry>[
      for (final entry in tasks.entries)
        if (entry.taskListId != listId && !selectedIds.contains(entry.taskId))
          entry,
      for (var position = 0; position < selected.length; position++)
        TaskListEntry(
          taskListId: listId,
          taskId: selected[position].id,
          position: position,
          updatedAt: now,
        ),
    ];
    await tasks.replaceAll(
      tasks: nextTasks,
      lists: nextLists,
      entries: nextEntries,
    );
    return {
      'ok': true,
      'todoList': _legacyTodoListJson(tasks, tasks.listById(listId)!),
    };
  }

  Future<Map<String, dynamic>> _saveTodoItem(
    TaskProvider tasks,
    Map<String, dynamic> args,
  ) async {
    final listId = (args['listId'] as String? ?? '').trim();
    if (listId.isEmpty) return _error('缺少 listId');
    final list = tasks.listById(listId);
    if (list == null) return _error('未找到待办清单: $listId');
    final itemId = (args['itemId'] as String? ?? '').trim();
    final delete = _boolArg(args, 'delete') ?? false;
    if (itemId.isEmpty) {
      if (delete) return _error('删除待办项需要 itemId');
      final text = (args['text'] as String? ?? '').trim();
      if (text.isEmpty) return _error('创建待办项需要 text');
      final id = await tasks.addTask(title: text, listId: listId);
      await tasks.moveTask(id, listId, position: 0);
      if (_boolArg(args, 'done') ?? false) await tasks.completeTask(id);
      final item = tasks.taskById(id)!;
      return {
        'ok': true,
        'todoList': _legacyTodoListJson(tasks, list),
        'item': _legacyTodoItemJson(item),
      };
    }
    final current = tasks.taskById(itemId);
    final entry = tasks.entryForTask(itemId);
    if (current == null || entry?.taskListId != listId) {
      return _error('未找到待办项: $itemId');
    }
    if (delete) {
      await tasks.deleteTask(itemId);
      return {'ok': true, 'todoList': _legacyTodoListJson(tasks, list)};
    }
    final text = (args['text'] as String?)?.trim();
    final done = _boolArg(args, 'done');
    if (text != null && text.isNotEmpty) {
      await tasks.updateTask(current.copyWith(title: text));
    }
    if (done == true) await tasks.completeTask(itemId);
    if (done == false) await tasks.uncompleteTask(itemId);
    final item = tasks.taskById(itemId)!;
    return {
      'ok': true,
      'todoList': _legacyTodoListJson(tasks, list),
      'item': _legacyTodoItemJson(item),
    };
  }

  Future<Map<String, dynamic>> _deleteTodoList(
    TaskProvider tasks,
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String? ?? '').trim();
    if (id.isEmpty) return _error('todos.deleteList 缺少 id');
    await tasks.deleteList(id);
    return {'ok': true};
  }

  TaskList? _findTodoList(TaskProvider tasks, Map<String, dynamic> args) {
    final id = (args['id'] as String? ?? '').trim();
    final title = (args['title'] as String? ?? '').trim().toLowerCase();
    final query = (args['query'] as String? ?? '').trim().toLowerCase();
    if (id.isNotEmpty) return tasks.listById(id);
    if (title.isNotEmpty) {
      return _bestTodoListMatch(
            tasks,
            (list) => list.title.toLowerCase() == title,
          ) ??
          _bestTodoListMatch(
            tasks,
            (list) => list.title.toLowerCase().contains(title),
          );
    }
    if (query.isNotEmpty) {
      return _bestTodoListMatch(
            tasks,
            (list) => list.title.toLowerCase().contains(query),
          ) ??
          _bestTodoListMatch(
            tasks,
            (list) => tasks
                .tasksForList(list.id)
                .any((item) => item.title.toLowerCase().contains(query)),
          );
    }
    return null;
  }

  TaskList? _bestTodoListMatch(
    TaskProvider tasks,
    bool Function(TaskList list) test,
  ) {
    for (final list in tasks.lists) {
      if (test(list)) return list;
    }
    return null;
  }

  Future<Map<String, dynamic>> _modelChat(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final model = _selectChatModel(
      context,
      args['modelId'] as String?,
      args['modelName'] as String?,
    );
    final messages = _modelMessages(args);
    final api = ApiService(backend: context.backend);
    try {
      final response = await api.sendChatRequest(
        model,
        messages,
        thinking: args['thinking'] == true && model.supportsThinking,
        tools: const [],
        toolChoice: 'none',
      );
      return {
        'ok': true,
        'content': response.content,
        if (response.reasoning != null) 'reasoning': response.reasoning,
      };
    } finally {
      api.dispose();
    }
  }

  Future<Map<String, dynamic>> _modelOcr(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final provider = context.modelConfigs;
    if (provider == null) throw Exception('model.ocr 需要模型上下文');
    final files = _recognitionFiles(args, defaultName: 'image.png');
    if (files.isEmpty) throw Exception('model.ocr 缺少 imageBase64 或 files');
    if (!files.any((file) => file.mimeType.startsWith('image/'))) {
      throw Exception('model.ocr 需要 image/* MIME 类型文件');
    }
    final modelId = (args['modelId'] as String?)?.trim().isNotEmpty == true
        ? args['modelId'] as String
        : context.settings?.settings.imageModelId;
    final recognition = ModelRecognitionService(
      api: ApiService(backend: context.backend),
    );
    final String text;
    try {
      text = await recognition.recognizeImagesWithOcr(
        modelConfigs: provider,
        modelId: modelId,
        files: files,
      );
    } finally {
      recognition.dispose();
    }
    return {
      'ok': true,
      'text': text,
      'fileCount': files.length,
      if (modelId != null && modelId.isNotEmpty) 'modelId': modelId,
    };
  }

  Future<Map<String, dynamic>> _modelRecognizeFile(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final provider = context.modelConfigs;
    if (provider == null) throw Exception('model.recognizeFile 需要模型上下文');
    final files = _recognitionFiles(args, defaultName: 'file');
    if (files.isEmpty) {
      throw Exception('model.recognizeFile 缺少 dataBase64/imageBase64 或 files');
    }
    final modelId = (args['modelId'] as String?)?.trim().isNotEmpty == true
        ? args['modelId'] as String
        : context.settings?.settings.imageRecognitionModelId;
    final prompt = (args['prompt'] as String? ?? '').trim().isNotEmpty
        ? (args['prompt'] as String).trim()
        : context.settings?.settings.imageRecognitionPrompt ??
              '请根据下面的文件内容或识别结果回答。';
    final recognition = ModelRecognitionService(
      api: ApiService(backend: context.backend),
    );
    final String content;
    try {
      content = await recognition.recognizeFilesWithModel(
        modelConfigs: provider,
        modelId: modelId,
        prompt: prompt,
        files: files,
      );
    } finally {
      recognition.dispose();
    }
    return {
      'ok': true,
      'content': content,
      'fileCount': files.length,
      if (modelId != null && modelId.isNotEmpty) 'modelId': modelId,
    };
  }

  Future<Map<String, dynamic>> _modelGenerateImage(
    LynAIFunctionContext context,
    Map<String, dynamic> args,
  ) async {
    final provider = context.modelConfigs;
    if (provider == null) throw Exception('model.generateImage 需要模型上下文');
    final prompt = (args['prompt'] as String? ?? '').trim();
    if (prompt.isEmpty) throw Exception('model.generateImage 缺少 prompt');
    final modelId = (args['modelId'] as String?)?.trim().isNotEmpty == true
        ? args['modelId'] as String
        : context.settings?.settings.imageGenerationModelId;
    final modelName = (args['modelName'] as String?)?.trim().isNotEmpty == true
        ? args['modelName'] as String
        : null;
    final parameters = _imageGenerationParameters(args);
    final service = ImageGenerationService(
      api: ApiService(backend: context.backend),
    );
    try {
      final result = await service.generate(
        modelConfigs: provider,
        prompt: prompt,
        modelId: modelId,
        modelName: modelName,
        parameters: parameters,
      );
      return {
        'ok': true,
        'prompt': prompt,
        'modelId': result.model.id,
        'modelName': result.model.modelName,
        'imageCount': result.images.length,
        'images': result.images
            .map(
              (image) => {
                'path': image.path,
                'name': image.name,
                'size': image.size,
                'mimeType': image.mimeType,
              },
            )
            .toList(),
      };
    } finally {
      service.dispose();
    }
  }

  Map<String, dynamic> _imageGenerationParameters(Map<String, dynamic> args) {
    final parameters = <String, dynamic>{};
    void add(String key, Object? value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      parameters[key] = value;
    }

    add('n', args['count'] ?? args['n']);
    add('size', args['size']);
    add('quality', args['quality']);
    add('style', args['style']);
    if (args['parameters'] is Map) {
      parameters.addAll(Map<String, dynamic>.from(args['parameters'] as Map));
    }
    return parameters;
  }

  Future<Map<String, dynamic>> _openApp(Map<String, dynamic> args) async {
    final packageName = (args['packageName'] as String? ?? '').trim();
    if (packageName.isEmpty) return _error('device.app.open 缺少 packageName');
    if (!Platform.isAndroid) return _error('device.app.open 仅支持 Android');
    final result = await _nativeToolsChannel.invokeMapMethod<String, dynamic>(
      'openApp',
      {'packageName': packageName},
    );
    return result ?? {'ok': false, 'error': '平台无返回'};
  }

  List<ModelRecognitionFileInput> _recognitionFiles(
    Map<String, dynamic> args, {
    required String defaultName,
  }) {
    final files = <ModelRecognitionFileInput>[];
    final rawFiles = args['files'];
    if (rawFiles is List) {
      for (final raw in rawFiles.whereType<Map>()) {
        final json = Map<String, dynamic>.from(raw);
        final data =
            (json['dataBase64'] as String? ??
                    json['imageBase64'] as String? ??
                    '')
                .trim();
        if (data.isEmpty) continue;
        files.add(
          ModelRecognitionFileInput.fromBase64(
            name: _stringArg(json['name'], defaultName),
            mimeType: (json['mimeType'] as String? ?? 'image/png').trim(),
            dataBase64: data,
          ),
        );
      }
    }
    final directData =
        (args['dataBase64'] as String? ?? args['imageBase64'] as String? ?? '')
            .trim();
    if (directData.isNotEmpty) {
      files.add(
        ModelRecognitionFileInput.fromBase64(
          name: _stringArg(args['name'], defaultName),
          mimeType: (args['mimeType'] as String? ?? 'image/png').trim(),
          dataBase64: directData,
        ),
      );
    }
    return files;
  }

  String _stringArg(Object? raw, String fallback) {
    final value = raw?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  ModelConfig _selectChatModel(
    LynAIFunctionContext context,
    String? modelId,
    String? modelName,
  ) {
    final provider = context.modelConfigs;
    if (provider == null) throw Exception('model.chat 需要模型上下文');
    final chatModels = provider.enabledModelsByCategory(
      ModelConfig.categoryChat,
    );
    if (chatModels.isEmpty) throw Exception('没有可用聊天模型');
    final id = modelId?.trim();
    if (id != null && id.isNotEmpty) {
      for (final model in chatModels) {
        if (model.id == id) return _withRequestedModelName(model, modelName);
      }
      throw Exception('未找到模型: $id');
    }
    final lastId = context.settings?.settings.lastChatModelId;
    if (lastId != null && lastId.isNotEmpty) {
      for (final model in chatModels) {
        if (model.id == lastId) {
          return _withRequestedModelName(model, modelName);
        }
      }
    }
    return _withRequestedModelName(chatModels.first, modelName);
  }

  ModelConfig _withRequestedModelName(ModelConfig model, String? rawModelName) {
    final modelName = rawModelName?.trim();
    if (modelName == null ||
        modelName.isEmpty ||
        modelName == model.modelName) {
      return model;
    }
    for (final entry in model.models) {
      if (entry.name == modelName) {
        if (!entry.enabled) throw Exception('子模型未启用: $modelName');
        return model.copyWith(modelName: modelName);
      }
    }
    throw Exception('未找到子模型: $modelName');
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

  String _messageRole(Object? raw) {
    final role = raw?.toString().trim();
    return switch (role) {
      'system' || 'assistant' || 'user' => role!,
      _ => 'user',
    };
  }

  Map<String, dynamic> _noteSummaryJson(
    Note note, {
    required bool includeContent,
  }) {
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

  Map<String, dynamic> _pluginNoteJson(
    Note note, {
    required bool includeContent,
  }) {
    return {
      'id': note.id,
      'title': note.title,
      'updatedAt': note.updatedAt.toIso8601String(),
      if (includeContent) 'content': note.content,
    };
  }

  Map<String, dynamic> _notePageJson(StorageV2NotePage page) {
    return {
      'id': page.id,
      'noteId': page.noteId,
      'title': page.title,
      'fileName': page.fileName,
      'currentRevisionId': page.currentRevisionId,
      'updatedAt': page.updatedAt.toIso8601String(),
    };
  }

  List<Map<String, dynamic>> _noteOutline(String content) {
    final headings = <Map<String, dynamic>>[];
    final lines = content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final match = RegExp(r'^(#{1,6})\s+(.+?)\s*$').firstMatch(lines[i]);
      if (match == null) continue;
      headings.add({
        'line': i + 1,
        'level': match.group(1)!.length,
        'title': match.group(2)!,
      });
    }
    return headings;
  }

  static String _contentHash(String content) {
    return sha256.convert(utf8.encode(content)).toString();
  }

  static List<String> _splitNoteLines(String content) {
    if (content.isEmpty) return const [''];
    return content.split('\n');
  }

  static List<Map<String, dynamic>> _numberedNoteLines(String content) {
    final lines = _splitNoteLines(content);
    return [
      for (var i = 0; i < lines.length; i++) {'line': i + 1, 'text': lines[i]},
    ];
  }

  static String _joinNoteLines(List<String> lines) {
    return lines.join('\n');
  }

  static _AppliedLineEdits _applyLineEdits(
    String content,
    List<_NoteLineEdit> edits,
  ) {
    final lines = _splitNoteLines(content);
    final sorted = [...edits]
      ..sort((a, b) => b.startLine.compareTo(a.startLine));
    var previousStart = lines.length + 1;
    for (final edit in sorted) {
      final startIndex = edit.startLine - 1;
      final endIndex = startIndex + edit.deleteCount;
      if (edit.startLine < 1 || startIndex > lines.length) {
        return _AppliedLineEdits.error(
          'edits 行号越界：startLine 必须在 1 到 ${lines.length + 1} 之间，${lines.length + 1} 仅用于 deleteCount=0 的末尾追加',
        );
      }
      if (startIndex == lines.length && edit.deleteCount != 0) {
        return const _AppliedLineEdits.error('末尾追加时 deleteCount 必须为 0');
      }
      if (endIndex > lines.length) {
        return const _AppliedLineEdits.error('edits 删除范围越界：deleteCount 超过可用行数');
      }
      if (endIndex > previousStart - 1) {
        return const _AppliedLineEdits.error('edits 存在重叠或顺序冲突，请合并相邻修改');
      }
      final expectedLines = edit.expectedLines;
      if (expectedLines != null) {
        if (expectedLines.length != edit.deleteCount) {
          return const _AppliedLineEdits.error(
            'expectedLines 数量必须等于 deleteCount，用于校验被替换/删除的原文',
          );
        }
        final actualLines = lines.sublist(startIndex, endIndex);
        for (var i = 0; i < expectedLines.length; i++) {
          if (expectedLines[i] != actualLines[i]) {
            return _AppliedLineEdits.error(
              '第 ${edit.startLine + i} 行原文不匹配，请重新 read_note 后按 numberedLines 行号编辑',
            );
          }
        }
      }
      lines.replaceRange(startIndex, endIndex, edit.insertLines);
      previousStart = edit.startLine;
    }
    return _AppliedLineEdits.success(_joinNoteLines(lines));
  }

  static NoteEditProposal _proposalFromEdits({
    required Note note,
    required String? pageId,
    required List<_NoteLineEdit> edits,
    required String? baseRevisionId,
  }) {
    final lines = _splitNoteLines(note.content);
    return NoteEditProposal(
      id: _uuid.v4(),
      noteId: note.id,
      pageId: pageId,
      baseRevisionId: baseRevisionId,
      baseContentHash: _contentHash(note.content),
      createdAt: DateTime.now(),
      blocks: edits.map((edit) {
        final start = edit.startLine - 1;
        final end = (start + edit.deleteCount).clamp(0, lines.length);
        return NoteEditBlock(
          id: _uuid.v4(),
          startLine: edit.startLine,
          deleteCount: edit.deleteCount,
          deletedLines: start >= 0 && start <= end
              ? lines.sublist(start, end)
              : const [],
          insertLines: edit.insertLines,
        );
      }).toList(),
    );
  }

  static List<Map<String, dynamic>> _lineDiff(String before, String after) {
    final beforeLines = _splitNoteLines(before);
    final afterLines = _splitNoteLines(after);
    var prefix = 0;
    final maxPrefix = beforeLines.length < afterLines.length
        ? beforeLines.length
        : afterLines.length;
    while (prefix < maxPrefix && beforeLines[prefix] == afterLines[prefix]) {
      prefix++;
    }
    var beforeSuffix = beforeLines.length;
    var afterSuffix = afterLines.length;
    while (beforeSuffix > prefix &&
        afterSuffix > prefix &&
        beforeLines[beforeSuffix - 1] == afterLines[afterSuffix - 1]) {
      beforeSuffix--;
      afterSuffix--;
    }
    final diff = <Map<String, dynamic>>[];
    for (var i = prefix; i < beforeSuffix; i++) {
      diff.add({'line': i + 1, 'type': 'remove', 'text': beforeLines[i]});
    }
    for (var i = prefix; i < afterSuffix; i++) {
      diff.add({'line': i + 1, 'type': 'add', 'text': afterLines[i]});
    }
    return diff;
  }

  static String _diffSummary(String before, String after) {
    final delta = NoteTextDelta.between(before, after);
    final added = delta.insertedText.length;
    final removed = delta.deletedText.length;
    if (added == 0 && removed == 0) return '无内容变化';
    if (added > 0 && removed > 0) return '+$added / -$removed 字符';
    if (added > 0) return '+$added 字符';
    return '-$removed 字符';
  }

  static String _lineDiffSummary(String before, String after) {
    final diff = _lineDiff(before, after);
    final added = diff.where((line) => line['type'] == 'add').length;
    final removed = diff.where((line) => line['type'] == 'remove').length;
    if (added == 0 && removed == 0) return '行无变化';
    if (added > 0 && removed > 0) return '+$added / -$removed 行';
    if (added > 0) return '+$added 行';
    return '-$removed 行';
  }

  static Task? _legacyTodoTaskFromRaw(
    Object? raw,
    Map<String, Task> taskById,
    Set<String> existingTaskIds,
    DateTime now,
  ) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final id = (json['id'] as String? ?? '').trim();
    final text = (json['text'] as String? ?? '').trim();
    if (text.isEmpty) return null;
    final existing = id.isEmpty ? null : taskById[id];
    final taskId =
        id.isEmpty || (existing == null && existingTaskIds.contains(id))
        ? _uuid.v4()
        : id;
    final done = _boolArg(json, 'done') ?? false;
    return Task(
      id: taskId,
      title: text,
      note: existing?.note,
      plannedDate: existing?.plannedDate,
      plannedTime: existing?.plannedTime,
      dueDate: existing?.dueDate,
      dueTime: existing?.dueTime,
      completedAt: done ? existing?.completedAt ?? now : null,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      reminders: existing?.reminders ?? const [],
    );
  }

  static Map<String, dynamic> _legacyTodoListJson(
    TaskProvider provider,
    TaskList list,
  ) {
    final items = provider.tasksForList(list.id);
    return {
      'id': list.id,
      'title': list.title,
      'createdAt': list.createdAt.toIso8601String(),
      'updatedAt': list.updatedAt.toIso8601String(),
      'items': items.map(_legacyTodoItemJson).toList(),
      'totalCount': items.length,
      'doneCount': items.where((item) => item.isCompleted).length,
    };
  }

  static Map<String, dynamic> _legacyTodoItemJson(Task item) {
    return {'id': item.id, 'text': item.title, 'done': item.isCompleted};
  }

  static bool? _boolArg(Map<String, dynamic> args, String key) {
    final raw = args[key];
    if (raw is bool) return raw;
    if (raw is String) {
      final value = raw.trim().toLowerCase();
      if (value == 'true') return true;
      if (value == 'false') return false;
    }
    return null;
  }

  static DateTime? _dateArg(Map<String, dynamic> args, String key) {
    final raw = args[key] as String?;
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim())?.toLocal();
  }

  static String? _optionalString(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  static LocalDate? _localDateArg(Map<String, dynamic> args, String key) {
    final value = _optionalString(args[key]);
    if (value == null) return null;
    return LocalDate.parse(value);
  }

  static LocalTime? _localTimeArg(Map<String, dynamic> args, String key) {
    final value = _optionalString(args[key]);
    if (value == null) return null;
    return LocalTime.parse(value);
  }

  static List<ItemReminder> _taskRemindersArg(
    Map<String, dynamic> args, {
    List<ItemReminder> current = const [],
    required LocalDate? plannedDate,
    required LocalTime? plannedTime,
    required LocalDate? dueDate,
    required LocalTime? dueTime,
  }) {
    final reminders = args.containsKey('reminders')
        ? _remindersArg(args['reminders'], const {
            ItemReminderAnchor.taskPlanned,
            ItemReminderAnchor.taskDue,
          })
        : current;
    for (final reminder in reminders) {
      final planned = reminder.anchor == ItemReminderAnchor.taskPlanned;
      if (planned ? plannedDate == null : dueDate == null) {
        throw FormatException('${planned ? '计划' : '截止'}提醒缺少对应日期');
      }
      if ((planned ? plannedTime : dueTime) != null &&
          reminder.dateOnlyTime != null) {
        throw FormatException('${planned ? '计划' : '截止'}时间明确时不能设置 dateOnlyTime');
      }
    }
    return reminders;
  }

  static List<ItemReminder> _calendarRemindersArg(
    Map<String, dynamic> args, {
    List<ItemReminder> current = const [],
    required CalendarEventSpec spec,
  }) {
    final reminders = args.containsKey('reminders')
        ? _remindersArg(args['reminders'], const {
            ItemReminderAnchor.eventStart,
          })
        : current;
    if (spec is TimedCalendarEventSpec &&
        reminders.any((reminder) => reminder.dateOnlyTime != null)) {
      throw const FormatException('定时事件提醒不能设置 dateOnlyTime');
    }
    return reminders;
  }

  static List<ItemReminder> _anniversaryRemindersArg(
    Map<String, dynamic> args, {
    List<ItemReminder> current = const [],
  }) {
    if (!args.containsKey('reminders')) return current;
    return _remindersArg(args['reminders'], const {
      ItemReminderAnchor.anniversaryDate,
    });
  }

  static List<ItemReminder> _remindersArg(
    Object? raw,
    Set<ItemReminderAnchor> validAnchors,
  ) {
    if (raw is! List) throw const FormatException('reminders 必须是数组');
    final reminders = [
      for (final value in raw) _reminderArg(value, validAnchors),
    ];
    try {
      return validatedReminders(reminders);
    } on ArgumentError catch (error) {
      throw FormatException(error.message?.toString() ?? '提醒列表无效');
    }
  }

  static ItemReminder _reminderArg(
    Object? raw,
    Set<ItemReminderAnchor> validAnchors,
  ) {
    if (raw is! Map) throw const FormatException('提醒必须是对象');
    final json = Map<String, dynamic>.from(raw);
    final id = _optionalString(json['id']) ?? _uuid.v4();
    final anchor = json['anchor'];
    if (anchor is! String || anchor.trim().isEmpty) {
      throw const FormatException('提醒缺少 anchor');
    }
    final offset = _integerArg(json['offsetMinutes']);
    if (offset == null) {
      throw const FormatException('提醒缺少整数 offsetMinutes');
    }
    final reminder = ItemReminder.fromJson({
      'id': id,
      'anchor': anchor,
      'offsetMinutes': offset,
      if (json.containsKey('dateOnlyTime'))
        'dateOnlyTime': json['dateOnlyTime'],
    });
    if (!validAnchors.contains(reminder.anchor)) {
      throw FormatException('提醒锚点不适用于当前实体: ${reminder.anchor.name}');
    }
    return reminder;
  }

  static Map<String, dynamic> _taskJson(TaskProvider provider, Task task) {
    return {
      'id': task.id,
      'title': task.title,
      if (task.note != null) 'note': task.note,
      'plannedDate': task.plannedDate?.toString(),
      'plannedTime': task.plannedTime?.toString(),
      'dueDate': task.dueDate?.toString(),
      'dueTime': task.dueTime?.toString(),
      'completed': task.isCompleted,
      'completedAt': task.completedAt?.toIso8601String(),
      'listId': provider.entryForTask(task.id)?.taskListId,
      'createdAt': task.createdAt.toIso8601String(),
      'updatedAt': task.updatedAt.toIso8601String(),
      'reminders': task.reminders.map((value) => value.toJson()).toList(),
    };
  }

  static CalendarEventSpec _calendarSpecArg(
    Map<String, dynamic> args, {
    CalendarEventSpec? current,
  }) {
    final allDay =
        args['allDay'] as bool? ?? current is AllDayCalendarEventSpec;
    if (allDay) {
      final old = current is AllDayCalendarEventSpec ? current : null;
      final start = args.containsKey('startDate')
          ? _localDateArg(args, 'startDate')
          : old?.startDate;
      final end = args.containsKey('endDateExclusive')
          ? _localDateArg(args, 'endDateExclusive')
          : old?.endDateExclusive;
      if (start == null) throw const FormatException('全天事件需要 startDate');
      return AllDayCalendarEventSpec(
        startDate: start,
        endDateExclusive: end ?? start.addDays(1),
      );
    }
    final old = current is TimedCalendarEventSpec ? current : null;
    final start = _dateArg(args, 'start') ?? old?.start;
    final end = _dateArg(args, 'end') ?? old?.end;
    if (start == null || end == null) {
      throw const FormatException('定时事件需要 start、end');
    }
    return TimedCalendarEventSpec(start: start, end: end);
  }

  static Map<String, dynamic> _calendarEventJson(CalendarEvent event) {
    return {
      'id': event.id,
      'title': event.title,
      if (event.note != null) 'note': event.note,
      'allDay': event.spec is AllDayCalendarEventSpec,
      ...switch (event.spec) {
        TimedCalendarEventSpec spec => {
          'start': spec.start.toLocal().toIso8601String(),
          'end': spec.end.toLocal().toIso8601String(),
        },
        AllDayCalendarEventSpec spec => {
          'startDate': spec.startDate.toString(),
          'endDateExclusive': spec.endDateExclusive.toString(),
        },
      },
      'createdAt': event.createdAt.toIso8601String(),
      'updatedAt': event.updatedAt.toIso8601String(),
      'reminders': event.reminders.map((value) => value.toJson()).toList(),
    };
  }

  static (DateTime, DateTime) _eventRange(CalendarEvent event) {
    return switch (event.spec) {
      TimedCalendarEventSpec spec => (spec.start, spec.end),
      AllDayCalendarEventSpec spec => (
        spec.startDate.atStartOfDay(),
        spec.endDateExclusive.atStartOfDay(),
      ),
    };
  }

  static AnniversarySpec _anniversarySpecArg(
    Map<String, dynamic> args, {
    AnniversarySpec? current,
  }) {
    final type = (args['type'] as String? ?? '').trim();
    final once =
        type == 'once' || (type.isEmpty && current is OnceAnniversarySpec);
    if (once) {
      final date = args.containsKey('date')
          ? _localDateArg(args, 'date')
          : current is OnceAnniversarySpec
          ? current.date
          : null;
      if (date == null) throw const FormatException('一次性纪念日需要 date');
      return OnceAnniversarySpec(date: date);
    }
    final old = current is YearlyAnniversarySpec ? current : null;
    final month = _integerArg(args['month']) ?? old?.month;
    final day = _integerArg(args['day']) ?? old?.day;
    if (month == null || day == null) {
      throw const FormatException('年度纪念日需要 month、day');
    }
    return YearlyAnniversarySpec(
      month: month,
      day: day,
      sourceYear: args.containsKey('sourceYear')
          ? _integerArg(args['sourceYear'])
          : old?.sourceYear,
    );
  }

  static Map<String, dynamic> _anniversaryJson(Anniversary item) {
    return {
      'id': item.id,
      'title': item.title,
      if (item.note != null) 'note': item.note,
      ...switch (item.spec) {
        OnceAnniversarySpec spec => {
          'type': 'once',
          'date': spec.date.toString(),
        },
        YearlyAnniversarySpec spec => {
          'type': 'yearly',
          'month': spec.month,
          'day': spec.day,
          'sourceYear': spec.sourceYear,
        },
      },
      'showYearCount': item.showYearCount,
      'createdAt': item.createdAt.toIso8601String(),
      'updatedAt': item.updatedAt.toIso8601String(),
      'reminders': item.reminders.map((value) => value.toJson()).toList(),
    };
  }

  static bool _legacyScheduleIsTask(Map<String, dynamic> args) {
    return _legacyScheduleKind(args) == _LegacyScheduleKind.task;
  }

  static _LegacyScheduleKind _legacyScheduleKind(Map<String, dynamic> args) {
    final kind = (args['kind'] as String? ?? '').trim().toLowerCase();
    return switch (kind) {
      'task' || '任务' => _LegacyScheduleKind.task,
      'schedule' || 'event' || '日程' => _LegacyScheduleKind.schedule,
      _ => _LegacyScheduleKind.unspecified,
    };
  }

  static DateTime? _taskPlannedDateTime(Task task) {
    final date = task.plannedDate;
    if (date == null) return null;
    return (task.plannedTime ?? LocalTime(0, 0)).on(date);
  }

  static int? _integerArg(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString().trim() ?? '');
  }

  static Map<String, dynamic> _legacyTaskScheduleJson(
    Map<String, dynamic> task,
  ) {
    final date = task['plannedDate'] as String;
    final time = task['plannedTime'] as String? ?? '00:00';
    return {
      'id': task['id'],
      'kind': 'task',
      'isTask': true,
      'title': task['title'],
      'start': DateTime.parse('${date}T$time').toIso8601String(),
      if (task['note'] != null) 'note': task['note'],
    };
  }

  static Map<String, dynamic> _legacyEventScheduleJson(
    Map<String, dynamic> event,
  ) {
    final allDay = event['allDay'] == true;
    return {
      'id': event['id'],
      'kind': 'schedule',
      'isTask': false,
      'title': event['title'],
      'start': allDay ? '${event['startDate']}T00:00:00.000' : event['start'],
      'end': allDay
          ? '${event['endDateExclusive']}T00:00:00.000'
          : event['end'],
      if (event['note'] != null) 'note': event['note'],
    };
  }

  Object? _jsonValue(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is List) return value.map(_jsonValue).toList(growable: false);
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _jsonValue(item)),
      );
    }
    return value.toString();
  }

  static Map<String, dynamic> _error(String message) => {
    'ok': false,
    'error': message,
  };
}
