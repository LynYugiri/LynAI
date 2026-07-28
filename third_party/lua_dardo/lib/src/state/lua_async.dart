import 'closure.dart';
import 'lua_stack.dart';

import '../api/lua_state.dart';

typedef LuaAsyncHandler = Future<Object?> Function(Object? request);
typedef AsyncDartFunction = int Function(LuaState ls);

enum LuaExecutionLimit {
  instructionLimit,
  deadline,
  cancelled,
  hostCallLimit,
}

class LuaExecutionLimitException implements Exception {
  final LuaExecutionLimit limit;

  const LuaExecutionLimitException(this.limit);

  String get code => switch (limit) {
        LuaExecutionLimit.instructionLimit => 'instruction_limit',
        LuaExecutionLimit.deadline => 'deadline_exceeded',
        LuaExecutionLimit.cancelled => 'cancelled',
        LuaExecutionLimit.hostCallLimit => 'host_call_limit',
      };

  @override
  String toString() => 'Lua execution budget exceeded: $code';
}

/// Opaque host-side limits shared by all calls, yields, and coroutine resumes
/// performed by a [LuaState]. Lua code cannot inspect or replace this object.
class LuaExecutionBudget {
  final int? maxInstructions;
  final Duration? maxDuration;
  final int? maxHostCalls;
  final bool Function()? isCancelled;

  final Stopwatch _clock = Stopwatch()..start();
  int _instructions = 0;
  int _hostCalls = 0;

  LuaExecutionBudget({
    this.maxInstructions,
    this.maxDuration,
    this.maxHostCalls,
    this.isCancelled,
  }) {
    if (maxInstructions != null && maxInstructions! < 0) {
      throw ArgumentError.value(maxInstructions, 'maxInstructions');
    }
    if (maxDuration != null && maxDuration! < Duration.zero) {
      throw ArgumentError.value(maxDuration, 'maxDuration');
    }
    if (maxHostCalls != null && maxHostCalls! < 0) {
      throw ArgumentError.value(maxHostCalls, 'maxHostCalls');
    }
  }

  int get instructions => _instructions;
  int get hostCalls => _hostCalls;
  Duration get elapsed => _clock.elapsed;

  void checkInstruction() {
    _checkCommon();
    _instructions++;
    if (maxInstructions != null && _instructions > maxInstructions!) {
      throw const LuaExecutionLimitException(
        LuaExecutionLimit.instructionLimit,
      );
    }
  }

  void checkHostCall() {
    _checkCommon();
    _hostCalls++;
    if (maxHostCalls != null && _hostCalls > maxHostCalls!) {
      throw const LuaExecutionLimitException(LuaExecutionLimit.hostCallLimit);
    }
  }

  void _checkCommon() {
    if (isCancelled?.call() ?? false) {
      throw const LuaExecutionLimitException(LuaExecutionLimit.cancelled);
    }
    if (maxDuration != null && _clock.elapsed > maxDuration!) {
      throw const LuaExecutionLimitException(LuaExecutionLimit.deadline);
    }
  }
}

class LuaYieldRequest implements Exception {
  final Object? request;

  const LuaYieldRequest(this.request);
}

class LuaYieldedCall implements Exception {
  final Object? request;
  final int a;
  final int c;

  const LuaYieldedCall(this.request, this.a, this.c);
}

class LuaYieldedCallSite {
  final int a;
  final int c;

  const LuaYieldedCallSite(this.a, this.c);
}

enum LuaCoroutineStatus { suspended, running, dead }

class LuaCoroutine {
  final Closure closure;
  Object? handle;
  LuaStack? stack;
  final List<LuaYieldedCallSite> yieldedCalls = <LuaYieldedCallSite>[];
  bool started = false;
  LuaCoroutineStatus status = LuaCoroutineStatus.suspended;

  LuaCoroutine(this.closure);
}
