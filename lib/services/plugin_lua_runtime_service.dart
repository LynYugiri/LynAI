import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lua_dardo/lua.dart';

import '../models/plugin.dart';
import '../providers/feature_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/task_provider.dart';
import '../utils/plugin_path_utils.dart';
import 'agent_cancellation.dart';
import 'agent_json_schema.dart';
import 'lynai_call_identity.dart';
import 'lua_sandbox_utils.dart';
import 'lynai_function_service.dart';

/// Executes Lua handlers declared by plugins.
///
/// `lua_dardo` exposes synchronous Dart callbacks, so read-only LynAI APIs return
/// immediately and mutating/model APIs return a command that Dart executes after
/// the Lua handler finishes.
class PluginLuaRuntimeService {
  static const _maxContinuationDepth = 8;
  static const _schemaValidator = AgentJsonSchemaValidator();

  /// 在 Lua 沙箱中执行插件定义的工具 handler。
  ///
  /// 完整流程：
  /// 1. 读取插件入口 Lua 文件（优先用根目录自定义入口，否则回退 defaults/ 出厂模板）
  /// 2. 初始化受限 Lua 状态机——禁用 os/io/package/require/dofile/loadfile 等危险全局函数
  /// 3. 注入 `lynai` 全局表（沙箱 API），将同步读操作直接返回、异步写操作包装为延迟命令
  /// 4. 执行脚本初始化，再调用 tool.handler 命名的全局函数
  /// 5. 执行结束后处理 Lua 返回的延迟命令（__lynai_function），调用 Dart 端执行实际 I/O
  /// 6. 如果命令声明 __lynai_next，则把 I/O 结果交回 Lua continuation 继续整理结果
  ///
  /// 之所以异步分阶段执行而非直接在 Lua 回调中做 I/O，是因为 lua_dardo
  /// 的 DartFunction 回调必须是同步的，无法在其中 await 异步操作。
  Future<Map<String, dynamic>> executeTool({
    required InstalledPlugin plugin,
    required PluginToolDefinition tool,
    required Map<String, dynamic> arguments,
    FeatureProvider? features,
    TaskProvider? tasks,
    CalendarProvider? calendar,
    ModelConfigProvider? modelConfigs,
    PluginProvider? plugins,
    SettingsProvider? settings,
    AgentCancellationToken? cancellationToken,
    DateTime? deadline,
  }) {
    final invalid = _validateArguments(arguments, tool.parameters);
    if (invalid != null) return Future.value(invalid);
    return _executeHandler(
      plugin: plugin,
      handler: tool.handler,
      arguments: arguments,
      cancellationToken: cancellationToken,
      deadline: deadline,
      features: features,
      tasks: tasks,
      calendar: calendar,
      modelConfigs: modelConfigs,
      plugins: plugins,
      settings: settings,
    );
  }

  Future<Map<String, dynamic>> executeFunction({
    required InstalledPlugin plugin,
    required PluginFunctionDefinition function,
    required Map<String, dynamic> arguments,
    FeatureProvider? features,
    TaskProvider? tasks,
    CalendarProvider? calendar,
    ModelConfigProvider? modelConfigs,
    PluginProvider? plugins,
    SettingsProvider? settings,
    AgentCancellationToken? cancellationToken,
    DateTime? deadline,
  }) {
    final invalid = _validateArguments(arguments, function.parameters);
    if (invalid != null) return Future.value(invalid);
    return _executeHandler(
      plugin: plugin,
      handler: function.handler,
      arguments: arguments,
      cancellationToken: cancellationToken,
      deadline: deadline,
      features: features,
      tasks: tasks,
      calendar: calendar,
      modelConfigs: modelConfigs,
      plugins: plugins,
      settings: settings,
    );
  }

  static Map<String, dynamic>? _validateArguments(
    Map<String, dynamic> arguments,
    Map<String, dynamic> schema,
  ) {
    final validation = _schemaValidator.validate(arguments, schema);
    if (validation.isValid) return null;
    return {
      'ok': false,
      'error': '参数无效: ${validation.issues.join('; ')}',
      'errorCode': 'invalid_arguments',
    };
  }

  /// 在 Lua 沙箱中执行插件命令 handler，返回面板选项。
  Future<Map<String, dynamic>> executeCommandHandler({
    required InstalledPlugin plugin,
    required PluginCommandDefinition command,
    required Map<String, dynamic> arguments,
    FeatureProvider? features,
    TaskProvider? tasks,
    CalendarProvider? calendar,
    ModelConfigProvider? modelConfigs,
    PluginProvider? plugins,
    SettingsProvider? settings,
    AgentCancellationToken? cancellationToken,
    DateTime? deadline,
  }) {
    final invalid = _validateArguments(arguments, command.parameters);
    if (invalid != null) return Future.value(invalid);
    return _executeHandler(
      plugin: plugin,
      handler: command.handler,
      arguments: arguments,
      cancellationToken: cancellationToken,
      deadline: deadline,
      features: features,
      tasks: tasks,
      calendar: calendar,
      modelConfigs: modelConfigs,
      plugins: plugins,
      settings: settings,
    );
  }

  Future<Map<String, dynamic>> _executeHandler({
    required InstalledPlugin plugin,
    required String handler,
    required Map<String, dynamic> arguments,
    FeatureProvider? features,
    TaskProvider? tasks,
    CalendarProvider? calendar,
    ModelConfigProvider? modelConfigs,
    PluginProvider? plugins,
    SettingsProvider? settings,
    AgentCancellationToken? cancellationToken,
    DateTime? deadline,
  }) async {
    final deadlineSource = deadline == null
        ? null
        : AgentCancellationSource(parent: cancellationToken);
    final effectiveCancellationToken =
        deadlineSource?.token ?? cancellationToken;
    Timer? deadlineTimer;
    if (deadline != null) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        deadlineSource!.cancel(_deadlineReason);
      } else {
        deadlineTimer = Timer(
          remaining,
          () => deadlineSource!.cancel(_deadlineReason),
        );
      }
    }
    effectiveCancellationToken?.throwIfCancellationRequested();
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

    final state = LuaState.newState(
      executionBudget: createLuaSandboxBudget(
        cancellationToken: effectiveCancellationToken,
      ),
    );
    try {
      state.openLibs();
      removeDangerousLuaGlobals(state);
      final preloadedConfig = await _preloadPluginConfig(
        plugin: plugin,
        cancellationToken: effectiveCancellationToken,
        features: features,
        tasks: tasks,
        calendar: calendar,
        modelConfigs: modelConfigs,
        plugins: plugins,
        settings: settings,
      );
      _installLynAI(
        state,
        plugin: plugin,
        features: features,
        tasks: tasks,
        calendar: calendar,
        modelConfigs: modelConfigs,
        plugins: plugins,
        settings: settings,
        preloadedConfig: preloadedConfig,
        cancellationToken: effectiveCancellationToken,
      );
      effectiveCancellationToken?.throwIfCancellationRequested();
      final loaded = state.loadString(await entry.readAsString());
      if (loaded != ThreadStatus.luaOk) return _error('Lua 加载失败: $loaded');
      final loadStatus = state.pCall(0, 0, 0);
      if (loadStatus != ThreadStatus.luaOk) {
        return _budgetError(
              state.lastError,
              cancellationToken: effectiveCancellationToken,
            ) ??
            _error('Lua 初始化失败: ${_popError(state, loadStatus)}');
      }

      state.getGlobal(handler);
      if (!state.isFunction(-1)) {
        state.pop(1);
        return _error('Lua handler 不存在: $handler');
      }
      _pushJsonValue(state, arguments);
      final status = state.pCall(1, 1, 0);
      if (status != ThreadStatus.luaOk) {
        return _budgetError(
              state.lastError,
              cancellationToken: effectiveCancellationToken,
            ) ??
            _error('Lua 执行失败: ${_popError(state, status)}');
      }
      final result = _readJsonValue(state, -1);
      state.pop(1);
      enforceLuaSandboxResultLimit(result);
      final commandResult = await _executeCommand(
        result,
        state: state,
        originalArguments: arguments,
        plugin: plugin,
        features: features,
        tasks: tasks,
        calendar: calendar,
        modelConfigs: modelConfigs,
        plugins: plugins,
        settings: settings,
        cancellationToken: effectiveCancellationToken,
      );
      if (commandResult != null) return commandResult;
      if (result is Map) {
        return result.map((key, value) => MapEntry(key.toString(), value));
      }
      return {'ok': true, 'result': result};
    } catch (error) {
      return _budgetError(
            error,
            cancellationToken: effectiveCancellationToken,
          ) ??
          _error('Lua 执行失败: $error');
    } finally {
      deadlineTimer?.cancel();
      deadlineSource?.dispose();
    }
  }

  /// 向 Lua 状态机注入 `lynai` 全局 API 表（沙箱入口）。
  ///
  /// 注入策略采用"同步读 / 异步写分离"模式：
  /// - **读操作**（list/read/info 等）直接在 Lua 回调中同步返回，因为读取无需 I/O 等待
  /// - **写操作**（save/edit/create/delete 等）返回一个 `__lynai_function` 命令标记，
  ///   Lua 脚本执行完毕后由 Dart 端统一处理这些延迟命令
  /// - **异步读后处理**（HTTP 后解析 JSON 等）可在命令上声明 `__lynai_next`，
  ///   Dart 完成 I/O 后会再次调用 Lua continuation，让业务解析仍留在 Lua 内。
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
    required TaskProvider? tasks,
    required CalendarProvider? calendar,
    required ModelConfigProvider? modelConfigs,
    required PluginProvider? plugins,
    required SettingsProvider? settings,
    required Map<String, dynamic>? preloadedConfig,
    required AgentCancellationToken? cancellationToken,
  }) {
    final context = LynAIFunctionContext(
      identity: LynAICallIdentity(
        type: LynAICallerType.plugin,
        pluginId: plugin.id,
      ),
      features: features,
      tasks: tasks,
      calendar: calendar,
      modelConfigs: modelConfigs,
      settings: settings,
      plugins: plugins,
      plugin: plugin,
      cancellationToken: cancellationToken,
    );
    final functions = LynAIFunctionService();
    state.newTable();
    _setFunction(state, -1, 'call', (ls) {
      cancellationToken?.throwIfCancellationRequested();
      final method = ls.checkString(1)?.trim() ?? '';
      final args = _readJsonValue(ls, 2);
      final normalizedArgs = args is Map
          ? args.map((key, item) => MapEntry(key.toString(), item))
          : <String, dynamic>{};
      if (method == 'plugin.config.read' && preloadedConfig != null) {
        final requestedPath = (normalizedArgs['path'] as String? ?? '').trim();
        if (requestedPath.isEmpty ||
            requestedPath == plugin.manifest.config.path) {
          _pushHostResult(ls, preloadedConfig);
        } else {
          _pushHostResult(ls, _error('plugin.config.read 只能读取当前插件配置文件'));
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
        _pushHostResult(ls, sync);
      }
      return 1;
    });
    _setFunction(state, -1, 'command', (ls) {
      cancellationToken?.throwIfCancellationRequested();
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
        cancellationToken?.throwIfCancellationRequested();
        _pushHostResult(
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
      'call': (LuaState ls) {
        cancellationToken?.throwIfCancellationRequested();
        final pluginId = ls.checkString(1)?.trim() ?? '';
        final functionName = ls.checkString(2)?.trim() ?? '';
        final args = _readJsonValue(ls, 3);
        _pushFunctionCommand(
          ls,
          'plugin.call',
          {
            'pluginId': pluginId,
            'functionName': functionName,
            'arguments': args is Map
                ? args.map((key, item) => MapEntry(key.toString(), item))
                : <String, dynamic>{},
          },
        );
        return 1;
      },
    });
    _setTable(state, -1, 'json', {
      'decode': (LuaState ls) {
        cancellationToken?.throwIfCancellationRequested();
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
        cancellationToken?.throwIfCancellationRequested();
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
    _setTable(state, -1, 'model', {
      'chat': (LuaState ls) {
        cancellationToken?.throwIfCancellationRequested();
        _pushFunctionCommand(ls, 'model.chat', _readJsonValue(ls, 1));
        return 1;
      },
      'ocr': (LuaState ls) {
        cancellationToken?.throwIfCancellationRequested();
        _pushFunctionCommand(ls, 'model.ocr', _readJsonValue(ls, 1));
        return 1;
      },
      'recognizeFile': (LuaState ls) {
        cancellationToken?.throwIfCancellationRequested();
        _pushFunctionCommand(ls, 'model.recognizeFile', _readJsonValue(ls, 1));
        return 1;
      },
      'generateImage': (LuaState ls) {
        cancellationToken?.throwIfCancellationRequested();
        _pushFunctionCommand(ls, 'model.generateImage', _readJsonValue(ls, 1));
        return 1;
      },
    });
    _installDeviceTable(state, -1);
    _setTable(state, -1, 'notes', {
      'list': (LuaState ls) {
        _pushHostResult(
          ls,
          functions.executeSync(
            LynAIFunctionCall(name: 'notes.list', arguments: _mapArg(ls, 1)),
            context,
          ),
        );
        return 1;
      },
      'read': (LuaState ls) {
        _pushHostResult(
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
        _pushHostResult(
          ls,
          functions.executeSync(
            LynAIFunctionCall(name: 'todos.list', arguments: _mapArg(ls, 1)),
            context,
          ),
        );
        return 1;
      },
      'read': (LuaState ls) {
        _pushHostResult(
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
        _pushHostResult(
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
    // 规范 API 与旧 todos/schedules 并存，插件可逐步迁移。
    _installCrudTable(state, -1, 'tasks', 'tasks', functions, context);
    _installCrudTable(state, -1, 'taskLists', 'taskLists', functions, context);
    _installCrudTable(state, -1, 'calendar', 'calendar', functions, context);
    _installCrudTable(
      state,
      -1,
      'anniversaries',
      'anniversaries',
      functions,
      context,
    );
    state.setGlobal('lynai');
  }

  void _installCrudTable(
    LuaState state,
    int parentIndex,
    String tableName,
    String functionPrefix,
    LynAIFunctionService functions,
    LynAIFunctionContext context,
  ) {
    _setTable(state, parentIndex, tableName, {
      'list': (LuaState ls) {
        _pushHostResult(
          ls,
          functions.executeSync(
            LynAIFunctionCall(
              name: '$functionPrefix.list',
              arguments: _mapArg(ls, 1),
            ),
            context,
          ),
        );
        return 1;
      },
      'create': (LuaState ls) {
        _pushFunctionCommand(
          ls,
          '$functionPrefix.create',
          _readJsonValue(ls, 1),
        );
        return 1;
      },
      'update': (LuaState ls) {
        _pushFunctionCommand(
          ls,
          '$functionPrefix.update',
          _readJsonValue(ls, 1),
        );
        return 1;
      },
      'delete': (LuaState ls) {
        _pushFunctionCommand(
          ls,
          '$functionPrefix.delete',
          _readJsonValue(ls, 1),
        );
        return 1;
      },
    });
  }

  void _installDeviceTable(LuaState state, int parentIndex) {
    void pushCommand(LuaState ls, String method, Object? args) {
      _pushFunctionCommand(
        ls,
        method,
        args is Map ? args : <String, dynamic>{},
      );
    }

    DartFunction direct(String method) {
      return (LuaState ls) {
        pushCommand(ls, method, _readJsonValue(ls, 1));
        return 1;
      };
    }

    DartFunction noArgs(String method) {
      return (LuaState ls) {
        pushCommand(ls, method, const <String, dynamic>{});
        return 1;
      };
    }

    _setTable(state, parentIndex, 'device', {
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
        pushCommand(ls, 'device.screen.inputText', {...args, 'text': text});
        return 1;
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
        pushCommand(ls, 'device.app.open', args);
        return 1;
      },
      'listApps': noArgs('device.app.list'),
      'sleep': (LuaState ls) {
        final raw = _readJsonValue(ls, 1);
        pushCommand(ls, 'device.sleep', {'ms': raw is Map ? raw['ms'] : raw});
        return 1;
      },
      'tap': (LuaState ls) {
        final raw = _readJsonValue(ls, 1);
        pushCommand(
          ls,
          'device.tap',
          raw is Map ? raw : {'x': raw, 'y': _readJsonValue(ls, 2)},
        );
        return 1;
      },
      'action': (LuaState ls) {
        final target = _readJsonValue(ls, 1);
        final action = ls.checkString(2) ?? 'click';
        final extra = _mapArg(ls, 3);
        pushCommand(ls, 'device.node.action', {
          ...extra,
          'nodeId': _nodeId(target),
          'action': action,
        });
        return 1;
      },
      'click': (LuaState ls) => _pushDeviceNodeAction(ls, 'click'),
      'focus': (LuaState ls) => _pushDeviceNodeAction(ls, 'focus'),
      'longClick': (LuaState ls) => _pushDeviceNodeAction(ls, 'longClick'),
      'clearText': (LuaState ls) => _pushDeviceNodeAction(ls, 'clearText'),
      'setText': (LuaState ls) {
        final target = _readJsonValue(ls, 1);
        _pushFunctionCommand(ls, 'device.node.action', {
          'nodeId': _nodeId(target),
          'action': 'setText',
          'text': ls.checkString(2) ?? '',
        });
        return 1;
      },
      'inputText': (LuaState ls) {
        final text = ls.checkString(1) ?? '';
        final target = _readJsonValue(ls, 2);
        _pushFunctionCommand(ls, 'device.inputText', {
          'text': text,
          if (_nodeId(target).isNotEmpty) 'nodeId': _nodeId(target),
        });
        return 1;
      },
      'first': (LuaState ls) {
        _pushJsonValue(ls, _firstNode(_readJsonValue(ls, 1)));
        return 1;
      },
    });
  }

  int _pushDeviceNodeAction(LuaState ls, String action) {
    final target = _readJsonValue(ls, 1);
    _pushFunctionCommand(ls, 'device.node.action', {
      'nodeId': _nodeId(target),
      'action': action,
    });
    return 1;
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
    required TaskProvider? tasks,
    required CalendarProvider? calendar,
    required ModelConfigProvider? modelConfigs,
    required PluginProvider? plugins,
    required SettingsProvider? settings,
    required AgentCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    if (plugins == null) return null;
    final result = await LynAIFunctionService().execute(
      const LynAIFunctionCall(
        name: 'plugin.config.read',
        arguments: <String, dynamic>{},
      ),
      LynAIFunctionContext(
        identity: LynAICallIdentity(
          type: LynAICallerType.plugin,
          pluginId: plugin.id,
        ),
        features: features,
        tasks: tasks,
        calendar: calendar,
        modelConfigs: modelConfigs,
        settings: settings,
        plugins: plugins,
        plugin: plugin,
        cancellationToken: cancellationToken,
      ),
    );
    cancellationToken?.throwIfCancellationRequested();
    return result;
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

  void _pushHostResult(LuaState state, Object? value) {
    enforceLuaSandboxResultLimit(value);
    _pushJsonValue(state, value);
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
    required LuaState state,
    required Map<String, dynamic> originalArguments,
    required InstalledPlugin plugin,
    required FeatureProvider? features,
    required TaskProvider? tasks,
    required CalendarProvider? calendar,
    required ModelConfigProvider? modelConfigs,
    required PluginProvider? plugins,
    required SettingsProvider? settings,
    required AgentCancellationToken? cancellationToken,
    int depth = 0,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    if (value is! Map) return null;
    final rawMethod = value['__lynai_function'] ?? value['__lynai_command'];
    if (rawMethod is! String) return null;
    if (depth >= _maxContinuationDepth) {
      return _error('Lua continuation 超过最大深度: $_maxContinuationDepth');
    }
    final method = rawMethod;
    final rawArgs = value['args'];
    final args = rawArgs is Map
        ? rawArgs.map((key, item) => MapEntry(key.toString(), item))
        : <String, dynamic>{};
    final result = await LynAIFunctionService().execute(
      LynAIFunctionCall(name: method, arguments: args),
      LynAIFunctionContext(
        identity: LynAICallIdentity(
          type: LynAICallerType.plugin,
          pluginId: plugin.id,
          toolName: method,
        ),
        features: features,
        tasks: tasks,
        calendar: calendar,
        modelConfigs: modelConfigs,
        plugins: plugins,
        settings: settings,
        plugin: plugin,
        cancellationToken: cancellationToken,
      ),
    );
    cancellationToken?.throwIfCancellationRequested();
    enforceLuaSandboxResultLimit(result);
    final next = (value['__lynai_next'] as String? ?? '').trim();
    if (next.isEmpty) return result;

    state.getGlobal(next);
    if (!state.isFunction(-1)) {
      state.pop(1);
      return _error('Lua continuation 不存在: $next');
    }
    _pushJsonValue(state, result);
    _pushJsonValue(state, originalArguments);
    _pushJsonValue(state, args);
    final status = state.pCall(3, 1, 0);
    if (status != ThreadStatus.luaOk) {
      final budgetError = _budgetError(
        state.lastError,
        cancellationToken: cancellationToken,
      );
      if (budgetError != null) return budgetError;
      return _error('Lua continuation 执行失败: ${_popError(state, status)}');
    }
    final nextResult = _readJsonValue(state, -1);
    state.pop(1);
    enforceLuaSandboxResultLimit(nextResult);
    final commandResult = await _executeCommand(
      nextResult,
      state: state,
      originalArguments: originalArguments,
      plugin: plugin,
      features: features,
      tasks: tasks,
      calendar: calendar,
      modelConfigs: modelConfigs,
      plugins: plugins,
      settings: settings,
      cancellationToken: cancellationToken,
      depth: depth + 1,
    );
    if (commandResult != null) return commandResult;
    if (nextResult is Map) {
      return nextResult.map((key, value) => MapEntry(key.toString(), value));
    }
    return {'ok': true, 'result': nextResult};
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

  static const _deadlineReason = AgentCancellationReason(
    code: 'deadline_exceeded',
    message: 'Tool execution deadline exceeded',
  );

  Map<String, dynamic>? _budgetError(
    Object? error, {
    AgentCancellationToken? cancellationToken,
  }) {
    if (error is AgentCancellationException) {
      return {
        'ok': false,
        'error': error.reason.message,
        'errorCode': error.reason.code,
      };
    }
    final code = luaSandboxErrorCode(error);
    if (code == null) return null;
    final reason = cancellationToken?.reason;
    if (code == 'cancelled' && reason != null) {
      return {'ok': false, 'error': reason.message, 'errorCode': reason.code};
    }
    return {
      'ok': false,
      'error': luaSandboxErrorMessage(code),
      'errorCode': code,
    };
  }
}
