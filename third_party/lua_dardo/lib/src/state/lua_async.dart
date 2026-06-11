import 'closure.dart';
import 'lua_stack.dart';

import '../api/lua_state.dart';

typedef LuaAsyncHandler = Future<Object?> Function(Object? request);
typedef AsyncDartFunction = int Function(LuaState ls);

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
