import 'dart:convert';

import 'package:lua_dardo/lua.dart';

import '../models/plugin.dart';
import '../providers/conversation_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import 'lynai_call_identity.dart';
import 'device_run_controller.dart';
import 'agent_runtime_service.dart';
import 'lynai_function_service.dart';
import 'lynai_permission_service.dart';
import 'lua_sandbox_utils.dart';
import 'plugin_lua_runtime_service.dart';

/// Executes model-provided Agent Lua scripts in a restricted sandbox.
class AgentLuaScriptService {
  static const maxCodeLength = 32000;
  static const maxCallCount = 40;
  static const _maxContinuationDepth = 8;

  Future<Map<String, dynamic>> execute({
    required String code,
    required String purpose,
    FeatureProvider? features,
    ModelConfigProvider? modelConfigs,
    PluginProvider? plugins,
    SettingsProvider? settings,
    ConversationProvider? conversations,
    String? conversationId,
    LynAICallIdentity? identity,
  }) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return _error('empty_code', 'Lua 脚本为空');
    if (trimmed.length > maxCodeLength) {
      return _error('code_too_long', 'Lua 脚本过长，最多 $maxCodeLength 字符');
    }
    final isDeviceScript = trimmed.contains('device.');
    if (isDeviceScript) {
      DeviceRunController.instance.start(purpose: purpose);
    }
    final state = LuaState.newState();
    try {
      state.openLibs();
      removeDangerousLuaGlobals(state);
      var callCount = 0;
      _installLynAI(
        state,
        asyncCalls: isDeviceScript,
        onCall: (method, args) {
          callCount++;
          final limit = isDeviceScript ? maxCallCount * 10 : maxCallCount;
          if (callCount > limit) {
            return _error('call_limit_exceeded', 'lynai.call 超过最大次数: $limit');
          }
          return _call(
            method,
            args,
            features: features,
            modelConfigs: modelConfigs,
            plugins: plugins,
            settings: settings,
            conversations: conversations,
            conversationId: conversationId,
            identity: identity,
          );
        },
      );
      final loaded = state.loadString(trimmed);
      if (loaded != ThreadStatus.luaOk) {
        return _finishDeviceRun(
          _error('load_failed', 'Lua 加载失败: $loaded'),
          isDeviceScript,
        );
      }
      final status = isDeviceScript
          ? await state.pCallAsync(
              0,
              1,
              0,
              (request) => _handleYieldedCommand(
                request,
                state: state,
                features: features,
                modelConfigs: modelConfigs,
                plugins: plugins,
                settings: settings,
                conversations: conversations,
                conversationId: conversationId,
                identity: identity,
              ),
            )
          : state.pCall(0, 1, 0);
      if (status != ThreadStatus.luaOk) {
        return _finishDeviceRun(
          _error('execution_failed', 'Lua 执行失败: ${_popError(state, status)}'),
          isDeviceScript,
        );
      }
      final result = _readJsonValue(state, -1);
      state.pop(1);
      final commandResult = await _executeCommand(
        result,
        state: state,
        depth: 0,
        features: features,
        modelConfigs: modelConfigs,
        plugins: plugins,
        settings: settings,
        conversations: conversations,
        conversationId: conversationId,
        identity: identity,
      );
      if (commandResult != null) {
        return _finishDeviceRun({
          'ok': commandResult['ok'] != false,
          'purpose': purpose,
          'calls': callCount,
          'result': commandResult,
          if (commandResult['ok'] == false) 'error': commandResult['error'],
        }, isDeviceScript);
      }
      if (result is Map) {
        final mapped = result.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        if (mapped['ok'] == false) {
          return _finishDeviceRun({
            'ok': false,
            'purpose': purpose,
            'calls': callCount,
            'result': mapped,
            'error': mapped['error'],
          }, isDeviceScript);
        }
        return _finishDeviceRun({
          'ok': true,
          'purpose': purpose,
          'calls': callCount,
          'result': mapped,
        }, isDeviceScript);
      }
      return _finishDeviceRun({
        'ok': true,
        'purpose': purpose,
        'calls': callCount,
        'result': result,
      }, isDeviceScript);
    } catch (e) {
      return _finishDeviceRun(
        _error('execution_failed', 'Lua 执行失败: $e'),
        isDeviceScript,
      );
    }
  }

  Map<String, dynamic> _finishDeviceRun(
    Map<String, dynamic> result,
    bool isDeviceScript,
  ) {
    if (!isDeviceScript) return result;
    if (result['ok'] == false) {
      final rawError = result['error'];
      final error = rawError is Map ? rawError : const <String, dynamic>{};
      if (error['code']?.toString() == 'user_stopped') {
        DeviceRunController.instance.stopped();
        return result;
      }
      DeviceRunController.instance.fail(
        error['code']?.toString() ?? 'failed',
        error['message']?.toString() ?? rawError?.toString() ?? '设备脚本执行失败',
      );
    } else {
      DeviceRunController.instance.complete();
    }
    return result;
  }

  Map<String, dynamic> _call(
    String method,
    Map<String, dynamic> args, {
    FeatureProvider? features,
    ModelConfigProvider? modelConfigs,
    PluginProvider? plugins,
    SettingsProvider? settings,
    ConversationProvider? conversations,
    String? conversationId,
    LynAICallIdentity? identity,
  }) {
    if (method == 'plugins.functions.list') {
      return _listPluginFunctions(plugins?.plugins ?? const []);
    }
    if (method == 'agent.plan.update' || method == 'update_plan') {
      return _updateAgentPlan(args, conversations, conversationId);
    }
    if (method == 'agent.note.add' || method == 'add_agent_note') {
      return _addAgentNote(args, conversations, conversationId);
    }
    if (method == 'plugins.callFunction') {
      final conv = conversationId == null
          ? null
          : conversations?.getConversation(conversationId);
      if (conv?.settings.agentEnabled != true) {
        return _error('agent_disabled', '当前对话未启用 Agent 模式');
      }
      final permitted = const LynAIPermissionService().canUseCapability(
        identity:
            identity ??
            LynAICallIdentity(
              type: LynAICallerType.agentLua,
              conversationId: conversationId,
            ),
        capability: LynAICapabilities.pluginCallFunction,
        appSettings: settings?.settings,
      );
      if (!permitted) {
        return _error('permission_denied', 'Agent 未授权 plugins.callFunction');
      }
      return {
        '__lynai_agent_function': 'plugins.callFunction',
        'args': args,
        if (args['__lynai_next'] is String)
          '__lynai_next': args['__lynai_next'],
      };
    }
    final functions = LynAIFunctionService();
    final context = LynAIFunctionContext(
      identity:
          identity ??
          LynAICallIdentity(
            type: LynAICallerType.agentLua,
            conversationId: conversationId,
            toolName: method,
          ),
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
      return {
        '__lynai_function': method,
        'args': args,
        if (args['__lynai_next'] is String)
          '__lynai_next': args['__lynai_next'],
      };
    }
    return sync;
  }

  Map<String, dynamic> _updateAgentPlan(
    Map<String, dynamic> args,
    ConversationProvider? conversations,
    String? conversationId,
  ) {
    if (conversations == null || conversationId == null) {
      return _error('missing_context', '缺少对话上下文');
    }
    return const AgentRuntimeService().updatePlan(
      conversations,
      conversationId,
      args,
    );
  }

  Map<String, dynamic> _addAgentNote(
    Map<String, dynamic> args,
    ConversationProvider? conversations,
    String? conversationId,
  ) {
    if (conversations == null || conversationId == null) {
      return _error('missing_context', '缺少对话上下文');
    }
    return const AgentRuntimeService().addNote(
      conversations,
      conversationId,
      args,
    );
  }

  Future<Map<String, dynamic>> _handleYieldedCommand(
    Object? request, {
    required LuaState state,
    FeatureProvider? features,
    ModelConfigProvider? modelConfigs,
    PluginProvider? plugins,
    SettingsProvider? settings,
    ConversationProvider? conversations,
    String? conversationId,
    LynAICallIdentity? identity,
  }) async {
    if (request is! Map) return _error('invalid_yield', 'Lua yield 请求无效');
    final command = request.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final name =
        command['__lynai_function'] as String? ??
        command['__lynai_agent_function'] as String?;
    if (name == null || name.isEmpty) {
      return _error('invalid_yield', 'Lua yield 缺少函数名');
    }
    final args = command['args'] is Map
        ? Map<String, dynamic>.from(command['args'] as Map)
        : <String, dynamic>{};
    return _executeAgentCommand(
      name,
      args,
      features: features,
      modelConfigs: modelConfigs,
      plugins: plugins,
      settings: settings,
      conversations: conversations,
      conversationId: conversationId,
      identity: identity,
    );
  }

  Future<Map<String, dynamic>?> _executeCommand(
    Object? raw, {
    required LuaState state,
    required int depth,
    FeatureProvider? features,
    ModelConfigProvider? modelConfigs,
    PluginProvider? plugins,
    SettingsProvider? settings,
    ConversationProvider? conversations,
    String? conversationId,
    LynAICallIdentity? identity,
  }) async {
    if (raw is! Map) return null;
    final command = raw.map((key, value) => MapEntry(key.toString(), value));
    final name =
        command['__lynai_function'] as String? ??
        command['__lynai_agent_function'] as String?;
    if (name == null || name.isEmpty) return null;
    if (depth >= _maxContinuationDepth) {
      return _error(
        'continuation_depth_exceeded',
        'Lua continuation 超过最大深度: $_maxContinuationDepth',
      );
    }
    final args = command['args'] is Map
        ? Map<String, dynamic>.from(command['args'] as Map)
        : <String, dynamic>{};
    final result = await _executeAgentCommand(
      name,
      args,
      features: features,
      modelConfigs: modelConfigs,
      plugins: plugins,
      settings: settings,
      conversations: conversations,
      conversationId: conversationId,
      identity: identity,
    );
    final next = (command['__lynai_next'] as String? ?? '').trim();
    if (next.isEmpty) return result;
    state.getGlobal(next);
    if (!state.isFunction(-1)) {
      state.pop(1);
      return _error('continuation_not_found', 'Lua continuation 不存在: $next');
    }
    _pushJsonValue(state, result);
    _pushJsonValue(state, args);
    final status = state.pCall(2, 1, 0);
    if (status != ThreadStatus.luaOk) {
      return _error(
        'continuation_failed',
        'Lua continuation 执行失败: ${_popError(state, status)}',
      );
    }
    final continuationResult = _readJsonValue(state, -1);
    state.pop(1);
    final nested = await _executeCommand(
      continuationResult,
      state: state,
      depth: depth + 1,
      features: features,
      modelConfigs: modelConfigs,
      plugins: plugins,
      settings: settings,
      conversations: conversations,
      conversationId: conversationId,
      identity: identity,
    );
    if (nested != null) return nested;
    if (continuationResult is Map) {
      return continuationResult.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return {'ok': true, 'result': continuationResult};
  }

  Future<Map<String, dynamic>> _executeAgentCommand(
    String name,
    Map<String, dynamic> args, {
    FeatureProvider? features,
    ModelConfigProvider? modelConfigs,
    PluginProvider? plugins,
    SettingsProvider? settings,
    ConversationProvider? conversations,
    String? conversationId,
    LynAICallIdentity? identity,
  }) async {
    if (name != 'plugins.callFunction') {
      return LynAIFunctionService().execute(
        LynAIFunctionCall(name: name, arguments: args),
        LynAIFunctionContext(
          identity:
              identity ??
              LynAICallIdentity(
                type: LynAICallerType.agentLua,
                conversationId: conversationId,
                toolName: name,
              ),
          features: features,
          modelConfigs: modelConfigs,
          plugins: plugins,
          settings: settings,
        ),
      );
    }
    final conv = conversationId == null
        ? null
        : conversations?.getConversation(conversationId);
    if (conv?.settings.agentEnabled != true) {
      return _error('agent_disabled', '当前对话未启用 Agent 模式');
    }
    final permitted = const LynAIPermissionService().canUseCapability(
      identity:
          identity ??
          LynAICallIdentity(
            type: LynAICallerType.agentLua,
            conversationId: conversationId,
          ),
      capability: LynAICapabilities.pluginCallFunction,
      appSettings: settings?.settings,
    );
    if (!permitted) {
      return _error('permission_denied', 'Agent 未授权 plugins.callFunction');
    }
    final provider = plugins;
    if (provider == null) return _error('plugin_system_unavailable', '插件系统不可用');
    final pluginId = (args['pluginId'] as String? ?? '').trim();
    final functionName = (args['functionName'] as String? ?? '').trim();
    final functionArgs = args['arguments'] is Map
        ? Map<String, dynamic>.from(args['arguments'] as Map)
        : <String, dynamic>{};
    InstalledPlugin? plugin;
    for (final item in provider.plugins) {
      if (item.id == pluginId) {
        plugin = item;
        break;
      }
    }
    if (plugin == null || !plugin.enabled || plugin.hasError) {
      return _error('plugin_not_found', '插件不可用: $pluginId');
    }
    PluginFunctionDefinition? function;
    for (final item in plugin.manifest.functions) {
      if (item.name == functionName) {
        function = item;
        break;
      }
    }
    if (function == null || !plugin.enabledFunctions.contains(function.name)) {
      return _error(
        'plugin_function_not_found',
        '插件函数不可用: $pluginId.$functionName',
      );
    }
    if (!plugin.hasAllPermissionsGranted) {
      return _error(
        'plugin_permissions_missing',
        '插件 ${plugin.displayName} 权限不足，无法执行 $functionName',
      );
    }
    return PluginLuaRuntimeService().executeFunction(
      plugin: plugin,
      function: function,
      arguments: functionArgs,
      features: features,
      modelConfigs: modelConfigs,
      plugins: plugins,
      settings: settings,
    );
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
    required bool asyncCalls,
    required Map<String, dynamic> Function(
      String method,
      Map<String, dynamic> args,
    )
    onCall,
  }) {
    state.newTable();
    int callFunction(LuaState ls) {
      final method = ls.checkString(1)?.trim() ?? '';
      final args = _readJsonValue(ls, 2);
      final normalizedArgs = args is Map
          ? args.map((key, item) => MapEntry(key.toString(), item))
          : <String, dynamic>{};
      final result = onCall(method, normalizedArgs);
      if (result['__lynai_function'] is String ||
          result['__lynai_agent_function'] is String) {
        if (asyncCalls) ls.yieldAsync(result);
      }
      _pushJsonValue(ls, result);
      return 1;
    }

    if (asyncCalls) {
      _setAsyncFunction(state, -1, 'call', callFunction);
    } else {
      _setFunction(state, -1, 'call', callFunction);
    }
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

  void _setAsyncFunction(
    LuaState state,
    int tableIndex,
    String name,
    DartFunction function,
  ) {
    final table = state.absIndex(tableIndex);
    state.pushAsyncDartFunction(function);
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

  static Map<String, dynamic> _error(String code, String message) => {
    'ok': false,
    'error': {'code': code, 'message': message},
  };
}
