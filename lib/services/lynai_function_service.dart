import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/model_config.dart';
import '../models/note.dart';
import '../models/plugin.dart';
import '../models/recycle_bin_item.dart';
import '../models/schedule_item.dart';
import '../models/todo_list.dart';
import '../providers/conversation_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import '../repositories/recycle_bin_repository.dart';
import 'api_service.dart';
import 'device_control_service.dart';
import 'device_run_controller.dart';
import 'lynai_call_identity.dart';
import 'lynai_permission_definitions.dart';
import 'lynai_permission_service.dart';
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
  final ModelConfigProvider? modelConfigs;
  final SettingsProvider? settings;
  final PluginProvider? plugins;
  final ConversationProvider? conversations;
  final InstalledPlugin? plugin;
  final void Function(String message)? showToast;

  const LynAIFunctionContext({
    this.identity = const LynAICallIdentity(type: LynAICallerType.system),
    this.features,
    this.modelConfigs,
    this.settings,
    this.plugins,
    this.conversations,
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
        'todos.list' => _listTodoLists(_features(context), call.arguments),
        'todos.read' => _readTodoList(_features(context), call.arguments),
        'todos.saveList' => await _saveTodoList(
          _features(context),
          call.arguments,
        ),
        'todos.saveItem' => await _saveTodoItem(
          _features(context),
          call.arguments,
        ),
        'todos.deleteList' => await _deleteTodoList(
          _features(context),
          call.arguments,
        ),
        'schedules.list' => _listSchedules(_features(context), call.arguments),
        'schedules.create' => await _createSchedule(
          _features(context),
          call.arguments,
        ),
        'schedules.update' => await _updateSchedule(
          _features(context),
          call.arguments,
        ),
        'schedules.delete' => await _deleteSchedule(
          _features(context),
          call.arguments,
        ),
        'model.chat' => await _modelChat(context, call.arguments),
        'model.ocr' => await _modelOcr(context, call.arguments),
        'model.recognizeFile' => await _modelRecognizeFile(
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
        'todos.list' => _listTodoLists(_features(context), call.arguments),
        'todos.read' => _readTodoList(_features(context), call.arguments),
        'schedules.list' => _listSchedules(_features(context), call.arguments),
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
      'schedules.list' => LynAIPermissions.schedulesRead,
      'schedules.create' ||
      'schedules.update' ||
      'schedules.delete' => LynAIPermissions.schedulesWrite,
      'model.chat' => LynAIPermissions.modelChat,
      'model.ocr' => LynAIPermissions.modelOcr,
      'model.recognizeFile' => LynAIPermissions.modelRecognizeFile,
      'device.screen.snapshot' ||
      'device.screen.context' ||
      'device.screen.screenshot' => LynAIPermissions.deviceScreenRead,
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

  /// 聚合统计：笔记总数、待办完成数/总数、对话数。
  Map<String, dynamic> _funcStats(LynAIFunctionContext context) {
    final features = context.features;
    final conversations = context.conversations;
    final noteCount = features?.notes.length ?? 0;
    var done = 0, total = 0;
    for (final list in features?.todoLists ?? const []) {
      for (final item in list.items) {
        total++;
        if (item.done) done++;
      }
    }
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

  Map<String, dynamic> _listSchedules(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) {
    final from = _dateArg(args, 'from');
    final to = _dateArg(args, 'to');
    final items = features.schedules
        .where((item) {
          if (from != null && !_scheduleVisibleEnd(item).isAfter(from)) {
            return false;
          }
          if (to != null && !item.start.isBefore(to)) return false;
          return true;
        })
        .map(_scheduleJson)
        .toList();
    return {
      'ok': true,
      'timezone': DateTime.now().timeZoneName,
      'timezoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      'schedules': items,
    };
  }

  Future<Map<String, dynamic>> _createSchedule(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) async {
    final title = (args['title'] as String? ?? '').trim();
    final start = _dateArg(args, 'start');
    final kind = _scheduleKindArg(args);
    final end = kind == ScheduleItem.kindTask
        ? start?.add(const Duration(minutes: 1))
        : _dateArg(args, 'end');
    if (title.isEmpty || start == null || end == null) {
      return _error(
        kind == ScheduleItem.kindTask
            ? '创建任务需要 title、start'
            : '创建日程需要 title、start、end',
      );
    }
    if (kind != ScheduleItem.kindTask && !end.isAfter(start)) {
      return _error('结束时间必须晚于开始时间');
    }
    final id = await features.addSchedule(
      title,
      start,
      end,
      note: args['note'] as String?,
      kind: kind,
    );
    final schedule = features.getSchedule(id);
    return {
      'ok': true,
      'schedule': schedule == null ? null : _scheduleJson(schedule),
    };
  }

  Future<Map<String, dynamic>> _updateSchedule(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String? ?? '').trim();
    final current = features.getSchedule(id);
    if (current == null) return _error('未找到日程: $id');
    final nextKind = args.containsKey('kind')
        ? _scheduleKindArg(args)
        : current.kind;
    final nextStart = _dateArg(args, 'start') ?? current.start;
    final parsedEnd = _dateArg(args, 'end');
    final nextEnd = nextKind == ScheduleItem.kindTask
        ? nextStart.add(const Duration(minutes: 1))
        : parsedEnd ?? current.end;
    final updated = args.containsKey('note')
        ? current.copyWith(
            title: (args['title'] as String?)?.trim(),
            start: nextStart,
            end: nextEnd,
            note: args['note'] as String?,
            kind: nextKind,
          )
        : current.copyWith(
            title: (args['title'] as String?)?.trim(),
            start: nextStart,
            end: nextEnd,
            kind: nextKind,
          );
    if (!updated.isTask && !updated.end.isAfter(updated.start)) {
      return _error('结束时间必须晚于开始时间');
    }
    await features.updateSchedule(updated);
    return {'ok': true, 'schedule': _scheduleJson(updated)};
  }

  Future<Map<String, dynamic>> _deleteSchedule(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String? ?? '').trim();
    if (id.isEmpty) return _error('schedules.delete 缺少 id');
    await features.deleteSchedule(id);
    return {'ok': true};
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
    FeatureProvider features,
    Map<String, dynamic> args,
  ) {
    final query = (args['query'] as String? ?? '').trim().toLowerCase();
    final includeItems = _boolArg(args, 'includeItems') ?? false;
    final lists = features.todoLists.where((list) {
      if (query.isEmpty) return true;
      return list.title.toLowerCase().contains(query) ||
          list.items.any((item) => item.text.toLowerCase().contains(query));
    });
    return {
      'ok': true,
      'todoLists': lists.map((list) {
        final done = list.items.where((item) => item.done).length;
        return {
          'id': list.id,
          'title': list.title,
          'createdAt': list.createdAt.toIso8601String(),
          'updatedAt': list.updatedAt.toIso8601String(),
          'totalItems': list.items.length,
          'doneItems': done,
          'totalCount': list.items.length,
          'doneCount': done,
          if (includeItems) 'items': list.items.map(_todoItemJson).toList(),
        };
      }).toList(),
    };
  }

  Map<String, dynamic> _readTodoList(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) {
    final list = _findTodoList(features, args);
    if (list == null) return _error('未找到匹配的待办清单，请先调用 list_todo_lists 查看可用清单');
    return {'ok': true, 'todoList': _todoListJson(list)};
  }

  Future<Map<String, dynamic>> _saveTodoList(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) async {
    final title = (args['title'] as String? ?? '').trim();
    final id = (args['id'] as String? ?? '').trim();
    final rawItems = args['items'];
    final items = rawItems is List
        ? rawItems.map(_todoItemFromRaw).whereType<TodoItem>().toList()
        : <TodoItem>[];
    if (id.isEmpty) {
      if (title.isEmpty) return _error('创建待办清单需要 title');
      final newId = await features.addTodoListWithItems(title, items);
      final list = features.getTodoList(newId);
      return {
        'ok': true,
        'todoList': list == null ? null : _todoListJson(list),
      };
    }
    final current = features.getTodoList(id);
    if (current == null) return _error('未找到待办清单: $id');
    if (title.isEmpty && rawItems is! List) {
      return _error('修改待办清单需要 title 或 items');
    }
    final updated = rawItems is List
        ? current.copyWith(title: title.isEmpty ? null : title, items: items)
        : current.copyWith(title: title);
    await features.updateTodoList(updated);
    return {'ok': true, 'todoList': _todoListJson(updated)};
  }

  Future<Map<String, dynamic>> _saveTodoItem(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) async {
    final listId = (args['listId'] as String? ?? '').trim();
    if (listId.isEmpty) return _error('缺少 listId');
    final list = features.getTodoList(listId);
    if (list == null) return _error('未找到待办清单: $listId');
    final itemId = (args['itemId'] as String? ?? '').trim();
    final delete = _boolArg(args, 'delete') ?? false;
    if (itemId.isEmpty) {
      if (delete) return _error('删除待办项需要 itemId');
      final text = (args['text'] as String? ?? '').trim();
      if (text.isEmpty) return _error('创建待办项需要 text');
      final item = TodoItem(
        id: _uuid.v4(),
        text: text,
        done: _boolArg(args, 'done') ?? false,
      );
      final updated = list.copyWith(items: [item, ...list.items]);
      await features.updateTodoList(updated);
      return {
        'ok': true,
        'todoList': _todoListJson(updated),
        'item': _todoItemJson(item),
      };
    }
    final index = list.items.indexWhere((item) => item.id == itemId);
    if (index == -1) return _error('未找到待办项: $itemId');
    if (delete) {
      final updated = list.copyWith(
        items: list.items.where((item) => item.id != itemId).toList(),
      );
      await features.updateTodoList(updated);
      return {'ok': true, 'todoList': _todoListJson(updated)};
    }
    final current = list.items[index];
    final text = (args['text'] as String?)?.trim();
    final done = _boolArg(args, 'done');
    final item = current.copyWith(
      text: text == null || text.isEmpty ? null : text,
      done: done,
    );
    final items = List<TodoItem>.from(list.items)..[index] = item;
    final updated = list.copyWith(items: items);
    await features.updateTodoList(updated);
    return {
      'ok': true,
      'todoList': _todoListJson(updated),
      'item': _todoItemJson(item),
    };
  }

  Future<Map<String, dynamic>> _deleteTodoList(
    FeatureProvider features,
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String? ?? '').trim();
    if (id.isEmpty) return _error('todos.deleteList 缺少 id');
    await features.deleteTodoList(id);
    return {'ok': true};
  }

  TodoList? _findTodoList(FeatureProvider features, Map<String, dynamic> args) {
    final id = (args['id'] as String? ?? '').trim();
    final title = (args['title'] as String? ?? '').trim().toLowerCase();
    final query = (args['query'] as String? ?? '').trim().toLowerCase();
    if (id.isNotEmpty) return features.getTodoList(id);
    if (title.isNotEmpty) {
      return _bestTodoListMatch(
            features,
            (list) => list.title.toLowerCase() == title,
          ) ??
          _bestTodoListMatch(
            features,
            (list) => list.title.toLowerCase().contains(title),
          );
    }
    if (query.isNotEmpty) {
      return _bestTodoListMatch(
            features,
            (list) => list.title.toLowerCase().contains(query),
          ) ??
          _bestTodoListMatch(
            features,
            (list) => list.items.any(
              (item) => item.text.toLowerCase().contains(query),
            ),
          );
    }
    return null;
  }

  TodoList? _bestTodoListMatch(
    FeatureProvider features,
    bool Function(TodoList list) test,
  ) {
    for (final list in features.todoLists) {
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
    final recognition = ModelRecognitionService();
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
    final recognition = ModelRecognitionService();
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
    final chatModels = provider.modelsByCategory(ModelConfig.categoryChat);
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

  static TodoItem? _todoItemFromRaw(Object? raw) {
    if (raw is! Map) return null;
    final item = _todoItemFromJson(Map<String, dynamic>.from(raw));
    return item.text.isEmpty ? null : item;
  }

  static TodoItem _todoItemFromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String? ?? '').trim();
    return TodoItem(
      id: id.isEmpty ? _uuid.v4() : id,
      text: (json['text'] as String? ?? '').trim(),
      done: _boolArg(json, 'done') ?? false,
    );
  }

  static Map<String, dynamic> _todoListJson(TodoList list) {
    return {
      'id': list.id,
      'title': list.title,
      'createdAt': list.createdAt.toIso8601String(),
      'updatedAt': list.updatedAt.toIso8601String(),
      'items': list.items.map(_todoItemJson).toList(),
      'totalCount': list.items.length,
      'doneCount': list.items.where((item) => item.done).length,
    };
  }

  static Map<String, dynamic> _todoItemJson(TodoItem item) {
    return {'id': item.id, 'text': item.text, 'done': item.done};
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

  static String _scheduleKindArg(Map<String, dynamic> args) {
    final raw = (args['kind'] as String? ?? '').trim().toLowerCase();
    if (raw == ScheduleItem.kindTask || raw == '任务') {
      return ScheduleItem.kindTask;
    }
    return ScheduleItem.kindSchedule;
  }

  static DateTime _scheduleVisibleEnd(ScheduleItem item) {
    return item.isTask ? item.start.add(const Duration(minutes: 1)) : item.end;
  }

  static Map<String, dynamic> _scheduleJson(ScheduleItem item) {
    return {
      'id': item.id,
      'kind': item.kind,
      'title': item.title,
      'start': item.start.toLocal().toIso8601String(),
      if (!item.isTask) 'end': item.end.toLocal().toIso8601String(),
      'isTask': item.isTask,
      'timezone': item.start.toLocal().timeZoneName,
      'timezoneOffsetMinutes': item.start.toLocal().timeZoneOffset.inMinutes,
      if (item.note != null) 'note': item.note,
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
