import 'dart:convert';

import 'package:lua_dardo/lua.dart';

import '../models/plugin.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import 'lynai_function_service.dart';

/// Executes model-provided Agent Lua scripts in a restricted sandbox.
class AgentLuaScriptService {
  static const maxCodeLength = 32000;
  static const maxCallCount = 40;

  Future<Map<String, dynamic>> execute({
    required String code,
    required String purpose,
    FeatureProvider? features,
    ModelConfigProvider? modelConfigs,
    PluginProvider? plugins,
    SettingsProvider? settings,
  }) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return _error('Lua 脚本为空');
    if (trimmed.length > maxCodeLength) {
      return _error('Lua 脚本过长，最多 $maxCodeLength 字符');
    }
    final state = LuaState.newState();
    state.openLibs();
    _removeDangerousGlobals(state);
    var callCount = 0;
    _installLynAI(
      state,
      onCall: (method, args) {
        callCount++;
        if (callCount > maxCallCount) {
          return _error('lynai.call 超过最大次数: $maxCallCount');
        }
        return _call(
          method,
          args,
          features: features,
          modelConfigs: modelConfigs,
          plugins: plugins,
          settings: settings,
        );
      },
    );
    final loaded = state.loadString(trimmed);
    if (loaded != ThreadStatus.luaOk) return _error('Lua 加载失败: $loaded');
    final status = state.pCall(0, 1, 0);
    if (status != ThreadStatus.luaOk) {
      return _error('Lua 执行失败: ${_popError(state, status)}');
    }
    final result = _readJsonValue(state, -1);
    state.pop(1);
    if (result is Map) {
      return {
        'ok': true,
        'purpose': purpose,
        'calls': callCount,
        'result': result.map((key, value) => MapEntry(key.toString(), value)),
      };
    }
    return {
      'ok': true,
      'purpose': purpose,
      'calls': callCount,
      'result': result,
    };
  }

  Map<String, dynamic> _call(
    String method,
    Map<String, dynamic> args, {
    FeatureProvider? features,
    ModelConfigProvider? modelConfigs,
    PluginProvider? plugins,
    SettingsProvider? settings,
  }) {
    if (method == 'plugins.functions.list') {
      return _listPluginFunctions(plugins?.plugins ?? const []);
    }
    final functions = LynAIFunctionService();
    final context = LynAIFunctionContext(
      features: features,
      modelConfigs: modelConfigs,
      plugins: plugins,
      settings: settings,
    );
    final sync = functions.executeSync(
      LynAIFunctionCall(name: method, arguments: args),
      context,
    );
    if (sync['ok'] == false &&
        (sync['error'] as String? ?? '').contains('需要异步执行')) {
      return _error('Agent Lua 第一版仅支持同步读取函数和 plugins.functions.list: $method');
    }
    return sync;
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

  Map<String, dynamic> _listPluginFunctions(Iterable<dynamic> plugins) {
    final functions = <Map<String, dynamic>>[];
    for (final plugin in plugins) {
      if (plugin is! InstalledPlugin || !plugin.enabled || plugin.hasError) {
        continue;
      }
      for (final function in plugin.manifest.functions) {
        if (!plugin.enabledFunctions.contains(function.name)) continue;
        functions.add({
          'pluginId': plugin.id,
          'pluginName': plugin.displayName,
          'name': function.name,
          'title': function.title,
          'description': function.description,
          'parameters': function.parameters,
        });
      }
    }
    return {'ok': true, 'functions': functions};
  }

  void _installLynAI(
    LuaState state, {
    required Map<String, dynamic> Function(
      String method,
      Map<String, dynamic> args,
    )
    onCall,
  }) {
    state.newTable();
    _setFunction(state, -1, 'call', (ls) {
      final method = ls.checkString(1)?.trim() ?? '';
      final args = _readJsonValue(ls, 2);
      final normalizedArgs = args is Map
          ? args.map((key, item) => MapEntry(key.toString(), item))
          : <String, dynamic>{};
      final result = onCall(method, normalizedArgs);
      _pushJsonValue(ls, result);
      return 1;
    });
    _setTable(state, -1, 'json', {
      'decode': (LuaState ls) {
        final text = ls.checkString(1) ?? '';
        try {
          _pushJsonValue(ls, jsonDecode(text));
          return 1;
        } catch (e) {
          ls.pushNil();
          ls.pushString(e.toString());
          return 2;
        }
      },
      'encode': (LuaState ls) {
        try {
          ls.pushString(jsonEncode(_readJsonValue(ls, 1)));
          return 1;
        } catch (e) {
          ls.pushNil();
          ls.pushString(e.toString());
          return 2;
        }
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

  String _popError(LuaState state, ThreadStatus status) {
    final message = state.getTop() > 0 ? state.toStr(-1) : null;
    if (state.getTop() > 0) state.pop(1);
    return message ?? status.toString();
  }

  static Map<String, dynamic> _error(String message) => {
    'ok': false,
    'error': message,
  };
}
