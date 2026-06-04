import 'dart:io';

import 'package:lua_dardo/lua.dart';
import 'package:uuid/uuid.dart';

import '../models/model_config.dart';
import '../models/note.dart';
import '../models/plugin.dart';
import '../models/schedule_item.dart';
import '../models/todo_list.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/plugin_path_utils.dart';
import 'api_service.dart';

/// Executes Lua handlers declared by plugins.
///
/// `lua_dardo` exposes synchronous Dart callbacks, so read-only LynAI APIs return
/// immediately and mutating/model APIs return a command that Dart executes after
/// the Lua handler finishes.
class PluginLuaRuntimeService {
  static const _uuid = Uuid();

  Future<Map<String, dynamic>> executeTool({
    required InstalledPlugin plugin,
    required PluginToolDefinition tool,
    required Map<String, dynamic> arguments,
    FeatureProvider? features,
    ModelConfigProvider? modelConfigs,
    SettingsProvider? settings,
  }) async {
    final entryPath = safePluginFilePath(plugin.path, plugin.manifest.entry);
    if (entryPath == null) {
      return _error('插件入口路径不安全: ${plugin.manifest.entry}');
    }
    final entry = File(entryPath);
    if (!await entry.exists()) return _error('插件入口文件不存在');

    final state = LuaState.newState();
    state.openLibs();
    _removeDangerousGlobals(state);
    _installLynAI(state, plugin: plugin, features: features);
    final loaded = state.loadString(await entry.readAsString());
    if (loaded != ThreadStatus.luaOk) return _error('Lua 加载失败: $loaded');
    final loadStatus = state.pCall(0, 0, 0);
    if (loadStatus != ThreadStatus.luaOk) {
      return _error('Lua 初始化失败: ${_popError(state, loadStatus)}');
    }

    state.getGlobal(tool.handler);
    if (!state.isFunction(-1)) {
      state.pop(1);
      return _error('Lua handler 不存在: ${tool.handler}');
    }
    _pushJsonValue(state, arguments);
    final status = state.pCall(1, 1, 0);
    if (status != ThreadStatus.luaOk) {
      return _error('Lua 执行失败: ${_popError(state, status)}');
    }
    final result = _readJsonValue(state, -1);
    state.pop(1);
    final commandResult = await _executeCommand(
      result,
      plugin: plugin,
      features: features,
      modelConfigs: modelConfigs,
      settings: settings,
    );
    if (commandResult != null) return commandResult;
    if (result is Map) {
      return result.map((key, value) => MapEntry(key.toString(), value));
    }
    return {'ok': true, 'result': result};
  }

  void _removeDangerousGlobals(LuaState state) {
    for (final name in const [
      'os',
      'io',
      'package',
      'require',
      'dofile',
      'loadfile',
    ]) {
      state.pushNil();
      state.setGlobal(name);
    }
  }

  void _installLynAI(
    LuaState state, {
    required InstalledPlugin plugin,
    required FeatureProvider? features,
  }) {
    state.newTable();
    _setFunction(state, -1, 'command', (ls) {
      final method = ls.checkString(1)?.trim() ?? '';
      final args = _readJsonValue(ls, 2);
      _pushCommand(ls, method, args is Map ? args : const <String, dynamic>{});
      return 1;
    });
    _setTable(state, -1, 'plugin', {
      'info': (LuaState ls) {
        _pushJsonValue(ls, {
          'id': plugin.id,
          'name': plugin.manifest.name,
          'version': plugin.manifest.version,
        });
        return 1;
      },
    });
    _setTable(state, -1, 'model', {
      'chat': (LuaState ls) {
        _pushCommand(ls, 'model.chat', _readJsonValue(ls, 1));
        return 1;
      },
    });
    _setTable(state, -1, 'notes', {
      'list': (LuaState ls) {
        _requirePermission(plugin, 'notes:read');
        _pushJsonValue(ls, _notesList(features, _mapArg(ls, 1)));
        return 1;
      },
      'read': (LuaState ls) {
        _requirePermission(plugin, 'notes:read');
        _pushJsonValue(ls, _notesRead(features, _mapArg(ls, 1)));
        return 1;
      },
      'save': (LuaState ls) {
        _pushCommand(ls, 'notes.save', _readJsonValue(ls, 1));
        return 1;
      },
      'delete': (LuaState ls) {
        _pushCommand(ls, 'notes.delete', _readJsonValue(ls, 1));
        return 1;
      },
    });
    _setTable(state, -1, 'todos', {
      'list': (LuaState ls) {
        _requirePermission(plugin, 'todos:read');
        _pushJsonValue(ls, _todosList(features, _mapArg(ls, 1)));
        return 1;
      },
      'read': (LuaState ls) {
        _requirePermission(plugin, 'todos:read');
        _pushJsonValue(ls, _todosRead(features, _mapArg(ls, 1)));
        return 1;
      },
      'saveList': (LuaState ls) {
        _pushCommand(ls, 'todos.saveList', _readJsonValue(ls, 1));
        return 1;
      },
      'saveItem': (LuaState ls) {
        _pushCommand(ls, 'todos.saveItem', _readJsonValue(ls, 1));
        return 1;
      },
    });
    _setTable(state, -1, 'schedules', {
      'list': (LuaState ls) {
        _requirePermission(plugin, 'schedules:read');
        _pushJsonValue(ls, _schedulesList(features, _mapArg(ls, 1)));
        return 1;
      },
      'create': (LuaState ls) {
        _pushCommand(ls, 'schedules.create', _readJsonValue(ls, 1));
        return 1;
      },
      'update': (LuaState ls) {
        _pushCommand(ls, 'schedules.update', _readJsonValue(ls, 1));
        return 1;
      },
      'delete': (LuaState ls) {
        _pushCommand(ls, 'schedules.delete', _readJsonValue(ls, 1));
        return 1;
      },
    });
    state.setGlobal('lynai');
  }

  void _setTable(
    LuaState state,
    int parentIndex,
    String name,
    Map<String, DartFunction> functions,
  ) {
    final parent = state.absIndex(parentIndex);
    state.newTable();
    for (final entry in functions.entries) {
      _setFunction(state, -1, entry.key, entry.value);
    }
    state.setField(parent, name);
  }

  void _setFunction(
    LuaState state,
    int tableIndex,
    String name,
    DartFunction function,
  ) {
    final table = state.absIndex(tableIndex);
    state.pushDartFunction(function);
    state.setField(table, name);
  }

  Map<String, dynamic> _mapArg(LuaState state, int index) {
    final value = _readJsonValue(state, index);
    return value is Map
        ? value.map((key, item) => MapEntry(key.toString(), item))
        : <String, dynamic>{};
  }

  void _pushCommand(LuaState state, String method, Object? args) {
    _pushJsonValue(state, {
      '__lynai_command': method,
      'args': args is Map ? args : <String, dynamic>{},
    });
  }

  void _pushJsonValue(LuaState state, Object? value) {
    if (value == null) {
      state.pushNil();
    } else if (value is bool) {
      state.pushBoolean(value);
    } else if (value is int) {
      state.pushInteger(value);
    } else if (value is num) {
      state.pushNumber(value.toDouble());
    } else if (value is String) {
      state.pushString(value);
    } else if (value is List) {
      state.createTable(value.length, 0);
      for (var i = 0; i < value.length; i++) {
        _pushJsonValue(state, value[i]);
        state.setI(-2, i + 1);
      }
    } else if (value is Map) {
      state.createTable(0, value.length);
      for (final entry in value.entries) {
        _pushJsonValue(state, entry.value);
        state.setField(-2, entry.key.toString());
      }
    } else {
      state.pushString(value.toString());
    }
  }

  Object? _readJsonValue(LuaState state, int index) {
    if (state.isNoneOrNil(index)) return null;
    if (state.isBoolean(index)) return state.toBoolean(index);
    if (state.isInteger(index)) return state.toInteger(index);
    if (state.isNumber(index)) return state.toNumber(index);
    if (state.isString(index)) return state.toStr(index);
    if (state.isTable(index)) return _readTable(state, index);
    return state.toStr(index) ?? state.typeName2(index);
  }

  Object _readTable(LuaState state, int index) {
    final tableIndex = state.absIndex(index);
    final arrayLength = state.rawLen(tableIndex);
    if (arrayLength > 0) {
      final list = <Object?>[];
      for (var i = 1; i <= arrayLength; i++) {
        state.getI(tableIndex, i);
        list.add(_readJsonValue(state, -1));
        state.pop(1);
      }
      return list;
    }
    final map = <String, Object?>{};
    state.pushNil();
    while (state.next(tableIndex)) {
      final key = _readJsonValue(state, -2)?.toString();
      if (key != null && key.isNotEmpty) {
        map[key] = _readJsonValue(state, -1);
      }
      state.pop(1);
    }
    return map;
  }

  Future<Map<String, dynamic>?> _executeCommand(
    Object? value, {
    required InstalledPlugin plugin,
    required FeatureProvider? features,
    required ModelConfigProvider? modelConfigs,
    required SettingsProvider? settings,
  }) async {
    if (value is! Map || value['__lynai_command'] is! String) return null;
    final method = value['__lynai_command'] as String;
    final rawArgs = value['args'];
    final args = rawArgs is Map
        ? rawArgs.map((key, item) => MapEntry(key.toString(), item))
        : <String, dynamic>{};
    try {
      return switch (method) {
        'notes.save' => await _notesSave(plugin, features, args),
        'notes.delete' => await _notesDelete(plugin, features, args),
        'todos.saveList' => await _todosSaveList(plugin, features, args),
        'todos.saveItem' => await _todosSaveItem(plugin, features, args),
        'schedules.create' => await _schedulesCreate(plugin, features, args),
        'schedules.update' => await _schedulesUpdate(plugin, features, args),
        'schedules.delete' => await _schedulesDelete(plugin, features, args),
        'model.chat' => await _modelChat(plugin, modelConfigs, settings, args),
        _ => _error('未知 Lua command: $method'),
      };
    } catch (e) {
      return _error(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Map<String, dynamic> _notesList(
    FeatureProvider? features,
    Map<String, dynamic> args,
  ) {
    if (features == null) return _error('Lua notes.list 需要 LynAI 上下文');
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
            (note) =>
                _noteJson(note, includeContent: args['includeContent'] == true),
          )
          .toList(),
    };
  }

  Map<String, dynamic> _notesRead(
    FeatureProvider? features,
    Map<String, dynamic> args,
  ) {
    if (features == null) return _error('Lua notes.read 需要 LynAI 上下文');
    final id = (args['id'] as String? ?? '').trim();
    final note = id.isEmpty ? null : features.getNote(id);
    if (note == null) return _error('未找到笔记: $id');
    return {'ok': true, 'note': _noteJson(note, includeContent: true)};
  }

  Map<String, dynamic> _todosList(
    FeatureProvider? features,
    Map<String, dynamic> args,
  ) {
    if (features == null) return _error('Lua todos.list 需要 LynAI 上下文');
    return {
      'ok': true,
      'todoLists': features.todoLists
          .map(
            (list) =>
                _todoListJson(list, includeItems: args['includeItems'] == true),
          )
          .toList(),
    };
  }

  Map<String, dynamic> _todosRead(
    FeatureProvider? features,
    Map<String, dynamic> args,
  ) {
    if (features == null) return _error('Lua todos.read 需要 LynAI 上下文');
    final id = (args['id'] as String? ?? '').trim();
    final list = id.isEmpty ? null : features.getTodoList(id);
    if (list == null) return _error('未找到待办清单: $id');
    return {'ok': true, 'todoList': _todoListJson(list, includeItems: true)};
  }

  Map<String, dynamic> _schedulesList(
    FeatureProvider? features,
    Map<String, dynamic> args,
  ) {
    if (features == null) return _error('Lua schedules.list 需要 LynAI 上下文');
    final from = _dateArg(args['from']);
    final to = _dateArg(args['to']);
    return {
      'ok': true,
      'schedules': features.schedules
          .where((item) {
            if (from != null && !item.end.isAfter(from)) return false;
            if (to != null && !item.start.isBefore(to)) return false;
            return true;
          })
          .map(_scheduleJson)
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _notesSave(
    InstalledPlugin plugin,
    FeatureProvider? features,
    Map<String, dynamic> args,
  ) async {
    _requirePermission(plugin, 'notes:write');
    if (features == null) return _error('Lua notes.save 需要 LynAI 上下文');
    final id = (args['id'] as String? ?? '').trim();
    final title = (args['title'] as String? ?? '').trim();
    final content = args['content']?.toString() ?? '';
    if (id.isEmpty) {
      if (title.isEmpty) return _error('创建笔记缺少 title');
      final noteId = await features.addNoteWithContent(title, content);
      return {
        'ok': true,
        'note': _noteJson(features.getNote(noteId)!, includeContent: true),
      };
    }
    final note = features.getNote(id);
    if (note == null) return _error('未找到笔记: $id');
    final updated = note.copyWith(
      title: title.isEmpty ? note.title : title,
      content: args['append'] == true ? note.content + content : content,
    );
    await features.updateNote(updated);
    return {'ok': true, 'note': _noteJson(updated, includeContent: true)};
  }

  Future<Map<String, dynamic>> _notesDelete(
    InstalledPlugin plugin,
    FeatureProvider? features,
    Map<String, dynamic> args,
  ) async {
    _requirePermission(plugin, 'notes:write');
    if (features == null) return _error('Lua notes.delete 需要 LynAI 上下文');
    await features.deleteNote((args['id'] as String? ?? '').trim());
    return {'ok': true};
  }

  Future<Map<String, dynamic>> _todosSaveList(
    InstalledPlugin plugin,
    FeatureProvider? features,
    Map<String, dynamic> args,
  ) async {
    _requirePermission(plugin, 'todos:write');
    if (features == null) return _error('Lua todos.saveList 需要 LynAI 上下文');
    final title = (args['title'] as String? ?? '').trim();
    if (title.isEmpty) return _error('创建待办清单缺少 title');
    final id = await features.addTodoListWithItems(title, const []);
    return {
      'ok': true,
      'todoList': _todoListJson(features.getTodoList(id)!, includeItems: true),
    };
  }

  Future<Map<String, dynamic>> _todosSaveItem(
    InstalledPlugin plugin,
    FeatureProvider? features,
    Map<String, dynamic> args,
  ) async {
    _requirePermission(plugin, 'todos:write');
    if (features == null) return _error('Lua todos.saveItem 需要 LynAI 上下文');
    final listId = (args['listId'] as String? ?? '').trim();
    final list = features.getTodoList(listId);
    if (list == null) return _error('未找到待办清单: $listId');
    final text = (args['text'] as String? ?? '').trim();
    if (text.isEmpty) return _error('待办项缺少 text');
    final updated = list.copyWith(
      items: [
        ...list.items,
        TodoItem(id: _uuid.v4(), text: text),
      ],
    );
    await features.updateTodoList(updated);
    return {'ok': true, 'todoList': _todoListJson(updated, includeItems: true)};
  }

  Future<Map<String, dynamic>> _schedulesCreate(
    InstalledPlugin plugin,
    FeatureProvider? features,
    Map<String, dynamic> args,
  ) async {
    _requirePermission(plugin, 'schedules:write');
    if (features == null) return _error('Lua schedules.create 需要 LynAI 上下文');
    final title = (args['title'] as String? ?? '').trim();
    final start = _dateArg(args['start']);
    final end = _dateArg(args['end']);
    if (title.isEmpty || start == null || end == null) {
      return _error('创建日程缺少 title/start/end');
    }
    final id = await features.addSchedule(
      title,
      start,
      end,
      note: args['note']?.toString(),
    );
    return {'ok': true, 'schedule': _scheduleJson(features.getSchedule(id)!)};
  }

  Future<Map<String, dynamic>> _schedulesUpdate(
    InstalledPlugin plugin,
    FeatureProvider? features,
    Map<String, dynamic> args,
  ) async {
    _requirePermission(plugin, 'schedules:write');
    if (features == null) return _error('Lua schedules.update 需要 LynAI 上下文');
    final id = (args['id'] as String? ?? '').trim();
    final current = features.getSchedule(id);
    if (current == null) return _error('未找到日程: $id');
    final updated = current.copyWith(
      title: (args['title'] as String?)?.trim(),
      start: _dateArg(args['start']) ?? current.start,
      end: _dateArg(args['end']) ?? current.end,
      note: args.containsKey('note') ? args['note']?.toString() : current.note,
    );
    await features.updateSchedule(updated);
    return {'ok': true, 'schedule': _scheduleJson(updated)};
  }

  Future<Map<String, dynamic>> _schedulesDelete(
    InstalledPlugin plugin,
    FeatureProvider? features,
    Map<String, dynamic> args,
  ) async {
    _requirePermission(plugin, 'schedules:write');
    if (features == null) return _error('Lua schedules.delete 需要 LynAI 上下文');
    await features.deleteSchedule((args['id'] as String? ?? '').trim());
    return {'ok': true};
  }

  Future<Map<String, dynamic>> _modelChat(
    InstalledPlugin plugin,
    ModelConfigProvider? modelConfigs,
    SettingsProvider? settings,
    Map<String, dynamic> args,
  ) async {
    _requirePermission(plugin, 'model:chat');
    if (modelConfigs == null) return _error('Lua model.chat 需要模型上下文');
    final model = _selectModel(
      modelConfigs,
      settings,
      args['modelId'] as String?,
    );
    final prompt = (args['user'] ?? args['prompt'])?.toString().trim() ?? '';
    if (prompt.isEmpty) return _error('model.chat 缺少 user/prompt');
    final messages = [
      if ((args['system'] as String? ?? '').trim().isNotEmpty)
        {'role': 'system', 'content': (args['system'] as String).trim()},
      {'role': 'user', 'content': prompt},
    ];
    final api = ApiService();
    try {
      final response = await api.sendChatRequest(
        model,
        messages,
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

  ModelConfig _selectModel(
    ModelConfigProvider provider,
    SettingsProvider? settings,
    String? modelId,
  ) {
    final models = provider.modelsByCategory(ModelConfig.categoryChat);
    if (models.isEmpty) throw Exception('没有可用聊天模型');
    final id = modelId?.trim();
    if (id != null && id.isNotEmpty) {
      return models.firstWhere((model) => model.id == id);
    }
    final lastId = settings?.settings.lastChatModelId;
    if (lastId != null && lastId.isNotEmpty) {
      for (final model in models) {
        if (model.id == lastId) return model;
      }
    }
    return models.first;
  }

  Map<String, dynamic> _noteJson(Note note, {required bool includeContent}) {
    return {
      'id': note.id,
      'title': note.title,
      'updatedAt': note.updatedAt.toIso8601String(),
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
      'totalCount': list.items.length,
      'doneCount': list.items.where((item) => item.done).length,
      if (includeItems)
        'items': list.items.map((item) => item.toJson()).toList(),
    };
  }

  Map<String, dynamic> _scheduleJson(ScheduleItem item) {
    return {
      'id': item.id,
      'title': item.title,
      'kind': item.kind,
      'start': item.start.toIso8601String(),
      'end': item.end.toIso8601String(),
      if (item.note != null) 'note': item.note,
    };
  }

  DateTime? _dateArg(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim())?.toLocal();
  }

  void _requirePermission(InstalledPlugin plugin, String permission) {
    if (!plugin.grantedPermissions.contains(permission)) {
      throw Exception('插件未授权 $permission');
    }
  }

  String _popError(LuaState state, ThreadStatus status) {
    final message = state.getTop() > 0 ? state.toStr(-1) : null;
    if (state.getTop() > 0) state.pop(1);
    return message ?? status.toString();
  }

  Map<String, dynamic> _error(String message) => {
    'ok': false,
    'error': message,
  };
}
