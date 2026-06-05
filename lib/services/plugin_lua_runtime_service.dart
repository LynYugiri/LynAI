import 'dart:io';

import 'package:lua_dardo/lua.dart';

import '../models/plugin.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/plugin_path_utils.dart';
import 'lynai_function_service.dart';

/// Executes Lua handlers declared by plugins.
///
/// `lua_dardo` exposes synchronous Dart callbacks, so read-only LynAI APIs return
/// immediately and mutating/model APIs return a command that Dart executes after
/// the Lua handler finishes.
class PluginLuaRuntimeService {

  /// 在 Lua 沙箱中执行插件定义的工具 handler。
  ///
  /// 完整流程：
  /// 1. 读取插件入口 Lua 文件（优先用根目录自定义入口，否则回退 defaults/ 出厂模板）
  /// 2. 初始化受限 Lua 状态机——禁用 os/io/package/require/dofile/loadfile 等危险全局函数
  /// 3. 注入 `lynai` 全局表（沙箱 API），将同步读操作直接返回、异步写操作包装为延迟命令
  /// 4. 执行脚本初始化，再调用 tool.handler 命名的全局函数
  /// 5. 执行结束后处理 Lua 返回的延迟命令（__lynai_function），调用 Dart 端执行实际写操作
  ///
  /// 之所以异步分阶段执行而非直接在 Lua 回调中做 I/O，是因为 lua_dardo
  /// 的 DartFunction 回调必须是同步的，无法在其中 await 异步操作。
  Future<Map<String, dynamic>> executeTool({
    required InstalledPlugin plugin,
    required PluginToolDefinition tool,
    required Map<String, dynamic> arguments,
    FeatureProvider? features,
    ModelConfigProvider? modelConfigs,
    PluginProvider? plugins,
    SettingsProvider? settings,
  }) async {
    final entryRelPath = plugin.manifest.entry;
    final entryPath = safePluginFilePath(plugin.path, entryRelPath);
    if (entryPath == null) {
      return _error('插件入口路径不安全: $entryRelPath');
    }
    var entry = File(entryPath);
    if (!await entry.exists()) {
      // 如根目录无自定义入口，回退读取 defaults/ 出厂模板
      final defPath = safePluginFilePath(plugin.path, 'defaults/$entryRelPath');
      if (defPath == null) return _error('插件入口文件不存在: $entryRelPath');
      entry = File(defPath);
      if (!await entry.exists()) return _error('插件入口文件不存在: $entryRelPath');
    }

    final state = LuaState.newState();
    state.openLibs();
    _removeDangerousGlobals(state);
    final preloadedConfig = await _preloadPluginConfig(
      plugin: plugin,
      features: features,
      modelConfigs: modelConfigs,
      plugins: plugins,
      settings: settings,
    );
    _installLynAI(
      state,
      plugin: plugin,
      features: features,
      modelConfigs: modelConfigs,
      plugins: plugins,
      settings: settings,
      preloadedConfig: preloadedConfig,
    );
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
      plugins: plugins,
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

  /// 向 Lua 状态机注入 `lynai` 全局 API 表（沙箱入口）。
  ///
  /// 注入策略采用"同步读 / 异步写分离"模式：
  /// - **读操作**（list/read/info 等）直接在 Lua 回调中同步返回，因为读取无需 I/O 等待
  /// - **写操作**（save/edit/create/delete 等）返回一个 `__lynai_function` 命令标记，
  ///   Lua 脚本执行完毕后由 Dart 端统一处理这些延迟命令
  ///
  /// 这样设计的原因是 lua_dardo 的 DartFunction 回调签名是同步的（`int Function(LuaState)`），
  /// 无法在其中使用 `await`。通过命令模式将异步操作推迟到脚本执行之后，
  /// 既保证了 Lua 脚本的可组合性，又不牺牲 Dart 端对异步 I/O 的支持。
  ///
  /// 此外，`plugin.config.read` 调用在此时使用了预加载的配置缓存（preloadedConfig），
  /// 而不是每次执行脚本都重新读取文件，减少文件 I/O。
  void _installLynAI(
    LuaState state, {
    required InstalledPlugin plugin,
    required FeatureProvider? features,
    required ModelConfigProvider? modelConfigs,
    required PluginProvider? plugins,
    required SettingsProvider? settings,
    required Map<String, dynamic>? preloadedConfig,
  }) {
    final context = LynAIFunctionContext(
      features: features,
      modelConfigs: modelConfigs,
      settings: settings,
      plugins: plugins,
      plugin: plugin,
    );
    final functions = LynAIFunctionService();
    state.newTable();
    _setFunction(state, -1, 'call', (ls) {
      final method = ls.checkString(1)?.trim() ?? '';
      final args = _readJsonValue(ls, 2);
      final normalizedArgs = args is Map
          ? args.map((key, item) => MapEntry(key.toString(), item))
          : <String, dynamic>{};
      if (method == 'plugin.config.read' && preloadedConfig != null) {
        final requestedPath = (normalizedArgs['path'] as String? ?? '').trim();
        if (requestedPath.isEmpty ||
            requestedPath == plugin.manifest.config.path) {
          _pushJsonValue(ls, preloadedConfig);
        } else {
          _pushJsonValue(ls, _error('plugin.config.read 只能读取当前插件配置文件'));
        }
        return 1;
      }
      final sync = functions.executeSync(
        LynAIFunctionCall(name: method, arguments: normalizedArgs),
        context,
      );
      if (sync['ok'] == false &&
          (sync['error'] as String? ?? '').contains('需要异步执行')) {
        _pushFunctionCommand(ls, method, normalizedArgs);
      } else {
        _pushJsonValue(ls, sync);
      }
      return 1;
    });
    _setFunction(state, -1, 'command', (ls) {
      final method = ls.checkString(1)?.trim() ?? '';
      final args = _readJsonValue(ls, 2);
      _pushFunctionCommand(
        ls,
        method,
        args is Map
            ? args.map((key, item) => MapEntry(key.toString(), item))
            : const <String, dynamic>{},
      );
      return 1;
    });
    _setTable(state, -1, 'plugin', {
      'info': (LuaState ls) {
        _pushJsonValue(
          ls,
          functions.executeSync(
            const LynAIFunctionCall(
              name: 'plugin.info',
              arguments: <String, dynamic>{},
            ),
            context,
          ),
        );
        return 1;
      },
    });
    _setTable(state, -1, 'model', {
      'chat': (LuaState ls) {
        _pushFunctionCommand(ls, 'model.chat', _readJsonValue(ls, 1));
        return 1;
      },
    });
    _setTable(state, -1, 'notes', {
      'list': (LuaState ls) {
        _pushJsonValue(
          ls,
          functions.executeSync(
            LynAIFunctionCall(name: 'notes.list', arguments: _mapArg(ls, 1)),
            context,
          ),
        );
        return 1;
      },
      'read': (LuaState ls) {
        _pushJsonValue(
          ls,
          functions.executeSync(
            LynAIFunctionCall(name: 'notes.read', arguments: _mapArg(ls, 1)),
            context,
          ),
        );
        return 1;
      },
      'save': (LuaState ls) {
        _pushFunctionCommand(ls, 'notes.save', _readJsonValue(ls, 1));
        return 1;
      },
      'proposeEdit': (LuaState ls) {
        _pushFunctionCommand(ls, 'notes.proposeEdit', _readJsonValue(ls, 1));
        return 1;
      },
      'edit': (LuaState ls) {
        _pushFunctionCommand(ls, 'notes.edit', _readJsonValue(ls, 1));
        return 1;
      },
      'delete': (LuaState ls) {
        _pushFunctionCommand(ls, 'notes.delete', _readJsonValue(ls, 1));
        return 1;
      },
    });
    _setTable(state, -1, 'todos', {
      'list': (LuaState ls) {
        _pushJsonValue(
          ls,
          functions.executeSync(
            LynAIFunctionCall(name: 'todos.list', arguments: _mapArg(ls, 1)),
            context,
          ),
        );
        return 1;
      },
      'read': (LuaState ls) {
        _pushJsonValue(
          ls,
          functions.executeSync(
            LynAIFunctionCall(name: 'todos.read', arguments: _mapArg(ls, 1)),
            context,
          ),
        );
        return 1;
      },
      'saveList': (LuaState ls) {
        _pushFunctionCommand(ls, 'todos.saveList', _readJsonValue(ls, 1));
        return 1;
      },
      'saveItem': (LuaState ls) {
        _pushFunctionCommand(ls, 'todos.saveItem', _readJsonValue(ls, 1));
        return 1;
      },
    });
    _setTable(state, -1, 'schedules', {
      'list': (LuaState ls) {
        _pushJsonValue(
          ls,
          functions.executeSync(
            LynAIFunctionCall(
              name: 'schedules.list',
              arguments: _mapArg(ls, 1),
            ),
            context,
          ),
        );
        return 1;
      },
      'create': (LuaState ls) {
        _pushFunctionCommand(ls, 'schedules.create', _readJsonValue(ls, 1));
        return 1;
      },
      'update': (LuaState ls) {
        _pushFunctionCommand(ls, 'schedules.update', _readJsonValue(ls, 1));
        return 1;
      },
      'delete': (LuaState ls) {
        _pushFunctionCommand(ls, 'schedules.delete', _readJsonValue(ls, 1));
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

  void _pushFunctionCommand(LuaState state, String method, Object? args) {
    _pushJsonValue(state, {
      '__lynai_function': method,
      'args': args is Map ? args : <String, dynamic>{},
    });
  }

  Future<Map<String, dynamic>?> _preloadPluginConfig({
    required InstalledPlugin plugin,
    required FeatureProvider? features,
    required ModelConfigProvider? modelConfigs,
    required PluginProvider? plugins,
    required SettingsProvider? settings,
  }) async {
    if (plugins == null) return null;
    return LynAIFunctionService().execute(
      const LynAIFunctionCall(
        name: 'plugin.config.read',
        arguments: <String, dynamic>{},
      ),
      LynAIFunctionContext(
        features: features,
        modelConfigs: modelConfigs,
        settings: settings,
        plugins: plugins,
        plugin: plugin,
      ),
    );
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
        if (entry.value == null) continue;
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
    required PluginProvider? plugins,
    required SettingsProvider? settings,
  }) async {
    if (value is! Map) return null;
    final rawMethod = value['__lynai_function'] ?? value['__lynai_command'];
    if (rawMethod is! String) return null;
    final method = rawMethod;
    final rawArgs = value['args'];
    final args = rawArgs is Map
        ? rawArgs.map((key, item) => MapEntry(key.toString(), item))
        : <String, dynamic>{};
    return LynAIFunctionService().execute(
      LynAIFunctionCall(name: method, arguments: args),
      LynAIFunctionContext(
        features: features,
        modelConfigs: modelConfigs,
        plugins: plugins,
        settings: settings,
        plugin: plugin,
      ),
    );
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
