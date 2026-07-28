import 'dart:async';
import 'dart:convert';

import 'package:lua_dardo/lua.dart';

import 'agent_cancellation.dart';

const luaSandboxMaxInstructions = 2000000;
const luaSandboxMaxDuration = Duration(seconds: 30);
const luaSandboxMaxHostCalls = 1024;
const luaSandboxMaxResultBytes = 256 * 1024;

final _luaCancellationZoneKey = Object();

Future<T> runWithLuaSandboxCancellation<T>(
  AgentCancellationToken? cancellationToken,
  Future<T> Function() action,
) {
  if (cancellationToken == null) return action();
  return runZoned(
    action,
    zoneValues: {_luaCancellationZoneKey: cancellationToken},
  );
}

LuaExecutionBudget createLuaSandboxBudget({
  AgentCancellationToken? cancellationToken,
  bool Function()? isCancelled,
}) => LuaExecutionBudget(
  maxInstructions: luaSandboxMaxInstructions,
  maxDuration: luaSandboxMaxDuration,
  maxHostCalls: luaSandboxMaxHostCalls,
  isCancelled:
      (cancellationToken ??
                  Zone.current[_luaCancellationZoneKey]
                      as AgentCancellationToken?) ==
              null &&
          isCancelled == null
      ? null
      : () {
          final token =
              cancellationToken ??
              Zone.current[_luaCancellationZoneKey] as AgentCancellationToken?;
          return token?.isCancellationRequested == true ||
              isCancelled?.call() == true;
        },
);

class LuaSandboxResultLimitException implements Exception {
  const LuaSandboxResultLimitException();

  @override
  String toString() => 'Lua result exceeds sandbox limit';
}

void enforceLuaSandboxResultLimit(Object? value) {
  final bytes = utf8.encode(jsonEncode(value)).length;
  if (bytes > luaSandboxMaxResultBytes) {
    throw const LuaSandboxResultLimitException();
  }
}

String? luaSandboxErrorCode(Object? error) {
  if (error is LuaExecutionLimitException) {
    return switch (error.limit) {
      LuaExecutionLimit.instructionLimit => 'instruction_limit_exceeded',
      LuaExecutionLimit.deadline => 'deadline_exceeded',
      LuaExecutionLimit.cancelled => 'cancelled',
      LuaExecutionLimit.hostCallLimit => 'host_call_limit_exceeded',
    };
  }
  if (error is LuaSandboxResultLimitException) return 'result_limit_exceeded';
  return null;
}

String luaSandboxErrorMessage(String code) => switch (code) {
  'instruction_limit_exceeded' => 'Lua 执行超过指令预算',
  'deadline_exceeded' => 'Lua 执行超过时间预算',
  'cancelled' => 'Lua 执行已取消',
  'host_call_limit_exceeded' => 'Lua 执行超过宿主调用预算',
  'result_limit_exceeded' => 'Lua 返回结果超过大小限制',
  _ => 'Lua 执行失败',
};

const _dangerousLuaGlobals = [
  'os',
  'io',
  'package',
  'require',
  'dofile',
  'loadfile',
  'load',
  'debug',
  'collectgarbage',
];

void removeDangerousLuaGlobals(LuaState state) {
  for (final name in _dangerousLuaGlobals) {
    state.pushNil();
    state.setGlobal(name);
  }
}
