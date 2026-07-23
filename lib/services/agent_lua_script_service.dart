import 'dart:convert';

import 'package:lua_dardo/lua.dart';

import '../models/plugin.dart';
import '../providers/conversation_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/task_provider.dart';
import 'lynai_call_identity.dart';
import 'device_run_controller.dart';
import 'agent_runtime_service.dart';
import 'backend_client.dart';
import 'lynai_function_service.dart';
import 'lynai_permission_service.dart';
import 'lua_sandbox_utils.dart';
import 'plugin_lua_runtime_service.dart';

/// Executes model-provided Agent Lua scripts in a restricted sandbox.
class AgentLuaScriptService {
  static const _maxContinuationDepth = 8;

  Future<Map<String, dynamic>> execute({
    required String code,
    required String purpose,
    FeatureProvider? features,
    TaskProvider? tasks,
    CalendarProvider? calendar,
    ModelConfigProvider? modelConfigs,
    PluginProvider? plugins,
    SettingsProvider? settings,
    ConversationProvider? conversations,
    String? conversationId,
    LynAICallIdentity? identity,
    BackendClient? backend,
  }) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return _error('empty_code', 'Lua 脚本为空');
    final isDeviceScript = trimmed.contains('device.');
    if (isDeviceScript) {
      DeviceRunController.instance.start(
        purpose: purpose,
        conversationId: conversationId,
      );
    }
    final state = LuaState.newState();
    try {
      state.openLibs();
      removeDangerousLuaGlobals(state);
      var callCount = 0;
      final generatedImages = <Map<String, dynamic>>[];
      _installLynAI(
        state,
        asyncCalls: true,
        onCall: (method, args) {
          callCount++;
          return _call(
            method,
            args,
            features: features,
            tasks: tasks,
            calendar: calendar,
            modelConfigs: modelConfigs,
            plugins: plugins,
            settings: settings,
            conversations: conversations,
            conversationId: conversationId,
            identity: identity,
            backend: backend,
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
      final status = await state.pCallAsync(
        0,
        1,
        0,
        (request) => _handleYieldedCommand(
          request,
          state: state,
          generatedImages: generatedImages,
          features: features,
          tasks: tasks,
          calendar: calendar,
          modelConfigs: modelConfigs,
          plugins: plugins,
          settings: settings,
          conversations: conversations,
          conversationId: conversationId,
          identity: identity,
          backend: backend,
        ),
      );
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
        generatedImages: generatedImages,
        features: features,
        tasks: tasks,
        calendar: calendar,
        modelConfigs: modelConfigs,
        plugins: plugins,
        settings: settings,
        conversations: conversations,
        conversationId: conversationId,
        identity: identity,
        backend: backend,
      );
      if (commandResult != null) {
        return _finishDeviceRun({
          'ok': commandResult['ok'] != false,
          'purpose': purpose,
          'calls': callCount,
          'result': commandResult,
          if (generatedImages.isNotEmpty) 'generatedImages': generatedImages,
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
            if (generatedImages.isNotEmpty) 'generatedImages': generatedImages,
            'error': mapped['error'],
          }, isDeviceScript);
        }
        return _finishDeviceRun({
          'ok': true,
          'purpose': purpose,
          'calls': callCount,
          'result': mapped,
          if (generatedImages.isNotEmpty) 'generatedImages': generatedImages,
        }, isDeviceScript);
      }
      return _finishDeviceRun({
        'ok': true,
        'purpose': purpose,
        'calls': callCount,
        'result': result,
        if (generatedImages.isNotEmpty) 'generatedImages': generatedImages,
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
    TaskProvider? tasks,
    CalendarProvider? calendar,
    ModelConfigProvider? modelConfigs,
    PluginProvider? plugins,
    SettingsProvider? settings,
    ConversationProvider? conversations,
    String? conversationId,
    LynAICallIdentity? identity,
    BackendClient? backend,
  }) {
    if (method == 'plugins.functions.list') {
      return _listPluginFunctions(plugins?.plugins ?? const []);
    }
    if (method == 'agent.plan.update' || method == 'update_plan') {
      return _updateAgentPlan(args, conversations, conversationId);
    }
    if (method == 'agent.memory.read' || method == 'read_agent_memory') {
      return _readAgentMemory(conversations, conversationId);
    }
    if (method == 'agent.memory.update' || method == 'update_agent_memory') {
      return _updateAgentMemory(args, conversations, conversationId);
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
      tasks: tasks,
      calendar: calendar,
      modelConfigs: modelConfigs,
      plugins: plugins,
      settings: settings,
      backend: backend,
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

  Map<String, dynamic> _readAgentMemory(
    ConversationProvider? conversations,
    String? conversationId,
  ) {
    if (conversations == null || conversationId == null) {
      return _error('missing_context', '缺少对话上下文');
    }
    return const AgentRuntimeService().readMemory(
      conversations,
      conversationId,
    );
  }

  Map<String, dynamic> _updateAgentMemory(
    Map<String, dynamic> args,
    ConversationProvider? conversations,
    String? conversationId,
  ) {
    if (conversations == null || conversationId == null) {
      return _error('missing_context', '缺少对话上下文');
    }
    return const AgentRuntimeService().updateMemory(
      conversations,
      conversationId,
      args,
    );
  }

  Future<Map<String, dynamic>> _handleYieldedCommand(
    Object? request, {
    required LuaState state,
    required List<Map<String, dynamic>> generatedImages,
    FeatureProvider? features,
    TaskProvider? tasks,
    CalendarProvider? calendar,
    ModelConfigProvider? modelConfigs,
    PluginProvider? plugins,
    SettingsProvider? settings,
    ConversationProvider? conversations,
    String? conversationId,
    LynAICallIdentity? identity,
    BackendClient? backend,
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
      generatedImages: generatedImages,
      features: features,
      tasks: tasks,
      calendar: calendar,
      modelConfigs: modelConfigs,
      plugins: plugins,
      settings: settings,
      conversations: conversations,
      conversationId: conversationId,
      identity: identity,
      backend: backend,
    );
  }

  Future<Map<String, dynamic>?> _executeCommand(
    Object? raw, {
    required LuaState state,
    required int depth,
    required List<Map<String, dynamic>> generatedImages,
    FeatureProvider? features,
    TaskProvider? tasks,
    CalendarProvider? calendar,
    ModelConfigProvider? modelConfigs,
    PluginProvider? plugins,
    SettingsProvider? settings,
    ConversationProvider? conversations,
    String? conversationId,
    LynAICallIdentity? identity,
    BackendClient? backend,
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
      generatedImages: generatedImages,
      features: features,
      tasks: tasks,
      calendar: calendar,
      modelConfigs: modelConfigs,
      plugins: plugins,
      settings: settings,
      conversations: conversations,
      conversationId: conversationId,
      identity: identity,
      backend: backend,
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
      generatedImages: generatedImages,
      features: features,
      modelConfigs: modelConfigs,
      plugins: plugins,
      settings: settings,
      conversations: conversations,
      conversationId: conversationId,
      identity: identity,
      backend: backend,
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
    List<Map<String, dynamic>>? generatedImages,
    FeatureProvider? features,
    TaskProvider? tasks,
    CalendarProvider? calendar,
    ModelConfigProvider? modelConfigs,
    PluginProvider? plugins,
    SettingsProvider? settings,
    ConversationProvider? conversations,
    String? conversationId,
    LynAICallIdentity? identity,
    BackendClient? backend,
  }) async {
    if (name != 'plugins.callFunction') {
      final result = await LynAIFunctionService().execute(
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
          tasks: tasks,
          calendar: calendar,
          modelConfigs: modelConfigs,
          plugins: plugins,
          settings: settings,
          backend: backend,
        ),
      );
      if (name == 'model.generateImage') {
        generatedImages?.addAll(_generatedImageMaps(result));
      }
      return result;
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
      tasks: tasks,
      calendar: calendar,
      modelConfigs: modelConfigs,
      plugins: plugins,
      settings: settings,
    );
  }

  List<Map<String, dynamic>> _generatedImageMaps(Map<String, dynamic> result) {
    if (result['ok'] != true) return const [];
    final rawImages = result['images'];
    if (rawImages is! List) return const [];
    return rawImages
        .whereType<Map>()
        .map((image) => Map<String, dynamic>.from(image))
        .toList(growable: false);
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
          'qualifiedName': '${plugin.id}__${function.name}',
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
      final isCommand =
          result['__lynai_function'] is String ||
          result['__lynai_agent_function'] is String;
      final hasContinuation = result['__lynai_next'] is String;
      if (isCommand && !hasContinuation) {
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
    _installDeviceTable(state, -1, onCall, asyncCalls: asyncCalls);
    // 规范便捷表保留 lynai.call 的完整能力，同时避免脚本拼错函数名。
    _installFunctionTable(state, -1, 'tasks', 'tasks', onCall, asyncCalls);
    _installFunctionTable(
      state,
      -1,
      'calendar',
      'calendar',
      onCall,
      asyncCalls,
    );
    _installFunctionTable(
      state,
      -1,
      'anniversaries',
      'anniversaries',
      onCall,
      asyncCalls,
    );
    state.setGlobal('lynai');
  }

  void _installFunctionTable(
    LuaState state,
    int parentIndex,
    String tableName,
    String prefix,
    Map<String, dynamic> Function(String method, Map<String, dynamic> args)
    onCall,
    bool asyncCalls,
  ) {
    int invoke(LuaState ls, String operation) {
      final args = _mapArg(ls, 1);
      final result = onCall('$prefix.$operation', args);
      final isCommand = result['__lynai_function'] is String;
      if (isCommand && result['__lynai_next'] is! String && asyncCalls) {
        ls.yieldAsync(result);
      }
      _pushJsonValue(ls, result);
      return 1;
    }

    final parent = state.absIndex(parentIndex);
    state.newTable();
    final table = state.absIndex(-1);
    for (final operation in const ['list', 'create', 'update', 'delete']) {
      int function(LuaState ls) => invoke(ls, operation);
      if (asyncCalls) {
        _setAsyncFunction(state, table, operation, function);
      } else {
        _setFunction(state, table, operation, function);
      }
    }
    state.setField(parent, tableName);
  }

  void _installDeviceTable(
    LuaState state,
    int parentIndex,
    Map<String, dynamic> Function(String method, Map<String, dynamic> args)
    onCall, {
    required bool asyncCalls,
  }) {
    int callDevice(LuaState ls, String method, Object? args) {
      final normalizedArgs = args is Map
          ? args.map((key, item) => MapEntry(key.toString(), item))
          : <String, dynamic>{};
      final result = onCall(method, normalizedArgs);
      final isCommand =
          result['__lynai_function'] is String ||
          result['__lynai_agent_function'] is String;
      final hasContinuation = result['__lynai_next'] is String;
      if (isCommand && !hasContinuation) {
        if (asyncCalls) ls.yieldAsync(result);
      }
      _pushJsonValue(ls, result);
      return 1;
    }

    DartFunction direct(String method) {
      return (LuaState ls) => callDevice(ls, method, _readJsonValue(ls, 1));
    }

    DartFunction noArgs(String method) {
      return (LuaState ls) => callDevice(ls, method, const <String, dynamic>{});
    }

    final parent = state.absIndex(parentIndex);
    state.newTable();
    final deviceIndex = state.absIndex(-1);
    final functions = <String, DartFunction>{
      'status': noArgs('device.service.status'),
      'snapshot': noArgs('device.screen.snapshot'),
      'context': direct('device.screen.context'),
      'query': direct('device.screen.query'),
      'find': direct('device.node.find'),
      'findAll': direct('device.node.findAll'),
      'wait': direct('device.waitForNode'),
      'waitText': direct('device.screen.waitText'),
      'clickFirst': direct('device.screen.clickText'),
      'waitAndClick': direct('device.screen.waitAndClick'),
      'inputInto': (LuaState ls) {
        final args = _mapArg(ls, 1);
        final text = ls.checkString(2) ?? args['text']?.toString() ?? '';
        return callDevice(ls, 'device.screen.inputText', {
          ...args,
          'text': text,
        });
      },
      'scrollUntil': direct('device.screen.scrollUntil'),
      'readVisibleText': direct('device.screen.readVisibleText'),
      'extractMessages': direct('device.screen.extractMessages'),
      'screenshot': noArgs('device.screen.screenshot'),
      'back': noArgs('device.pressBack'),
      'swipe': direct('device.swipe'),
      'openSettings': direct('device.service.openSettings'),
      'openApp': (LuaState ls) {
        final raw = _readJsonValue(ls, 1);
        final args = raw is Map
            ? raw.map((key, value) => MapEntry(key.toString(), value))
            : {'packageName': raw?.toString() ?? ''};
        return callDevice(ls, 'device.app.open', args);
      },
      'sleep': (LuaState ls) {
        final raw = _readJsonValue(ls, 1);
        return callDevice(ls, 'device.sleep', {
          'ms': raw is Map ? raw['ms'] : raw,
        });
      },
      'tap': (LuaState ls) {
        final raw = _readJsonValue(ls, 1);
        if (raw is Map) return callDevice(ls, 'device.tap', raw);
        return callDevice(ls, 'device.tap', {
          'x': raw,
          'y': _readJsonValue(ls, 2),
        });
      },
      'action': (LuaState ls) {
        final target = _readJsonValue(ls, 1);
        final action = ls.checkString(2) ?? 'click';
        final extra = _mapArg(ls, 3);
        return callDevice(ls, 'device.node.action', {
          ...extra,
          'nodeId': _nodeId(target),
          'action': action,
        });
      },
      'click': (LuaState ls) => _deviceNodeAction(ls, callDevice, 'click'),
      'focus': (LuaState ls) => _deviceNodeAction(ls, callDevice, 'focus'),
      'longClick': (LuaState ls) =>
          _deviceNodeAction(ls, callDevice, 'longClick'),
      'clearText': (LuaState ls) =>
          _deviceNodeAction(ls, callDevice, 'clearText'),
      'setText': (LuaState ls) {
        final target = _readJsonValue(ls, 1);
        return callDevice(ls, 'device.node.action', {
          'nodeId': _nodeId(target),
          'action': 'setText',
          'text': ls.checkString(2) ?? '',
        });
      },
      'inputText': (LuaState ls) {
        final text = ls.checkString(1) ?? '';
        final target = _readJsonValue(ls, 2);
        return callDevice(ls, 'device.inputText', {
          'text': text,
          if (_nodeId(target).isNotEmpty) 'nodeId': _nodeId(target),
        });
      },
      'first': (LuaState ls) {
        _pushJsonValue(ls, _firstNode(_readJsonValue(ls, 1)));
        return 1;
      },
    };
    for (final entry in functions.entries) {
      if (asyncCalls) {
        _setAsyncFunction(state, deviceIndex, entry.key, entry.value);
      } else {
        _setFunction(state, deviceIndex, entry.key, entry.value);
      }
    }
    state.setField(parent, 'device');
  }

  int _deviceNodeAction(
    LuaState ls,
    int Function(LuaState, String, Object?) callDevice,
    String action,
  ) {
    final target = _readJsonValue(ls, 1);
    return callDevice(ls, 'device.node.action', {
      'nodeId': _nodeId(target),
      'action': action,
    });
  }

  Map<String, dynamic> _mapArg(LuaState state, int index) {
    final value = _readJsonValue(state, index);
    return value is Map
        ? value.map((key, item) => MapEntry(key.toString(), item))
        : <String, dynamic>{};
  }

  String _nodeId(Object? target) {
    if (target is Map) {
      final targetId = target['targetNodeId']?.toString() ?? '';
      if (targetId.isNotEmpty) return targetId;
      return target['id']?.toString() ?? target['nodeId']?.toString() ?? '';
    }
    return target?.toString() ?? '';
  }

  Object? _firstNode(Object? raw) {
    if (raw is! Map) return null;
    final result = raw['result'];
    if (result is! Map) return null;
    final nodes = result['nodes'];
    if (nodes is! List || nodes.isEmpty) return null;
    return nodes.first;
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
