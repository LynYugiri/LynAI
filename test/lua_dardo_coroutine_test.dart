import 'package:flutter_test/flutter_test.dart';
import 'package:lua_dardo/lua.dart';

void main() {
  test('coroutine resume and yield exchange values', () {
    final state = LuaState.newState();
    state.openLibs();
    final loaded = state.loadString(r'''
local co = coroutine.create(function(a)
  local b = coroutine.yield(a + 1)
  return b + 2
end)
local ok1, y = coroutine.resume(co, 10)
local mid = coroutine.status(co)
local ok2, done = coroutine.resume(co, 20)
local last = coroutine.status(co)
return ok1, y, mid, ok2, done, last
''');
    expect(loaded, ThreadStatus.luaOk);

    final status = state.pCall(0, 6, 0);

    expect(status, ThreadStatus.luaOk);
    expect(state.toBoolean(-6), isTrue);
    expect(state.toInteger(-5), 11);
    expect(state.toStr(-4), 'suspended');
    expect(state.toBoolean(-3), isTrue);
    expect(state.toInteger(-2), 22);
    expect(state.toStr(-1), 'dead');
  });

  test('coroutine wrap returns yielded and final values', () {
    final state = LuaState.newState();
    state.openLibs();
    final loaded = state.loadString(r'''
local f = coroutine.wrap(function()
  coroutine.yield("a")
  return "b"
end)
return f(), f()
''');
    expect(loaded, ThreadStatus.luaOk);

    final status = state.pCall(0, 2, 0);

    expect(status, ThreadStatus.luaOk);
    expect(state.toStr(-2), 'a');
    expect(state.toStr(-1), 'b');
  });

  test('coroutine running reports current coroutine', () {
    final state = LuaState.newState();
    state.openLibs();
    final loaded = state.loadString(r'''
local co = coroutine.create(function()
  local running, isMain = coroutine.running()
  return running ~= nil, isMain
end)
local ok, hasRunning, isMain = coroutine.resume(co)
return ok, hasRunning, isMain
''');
    expect(loaded, ThreadStatus.luaOk);

    final status = state.pCall(0, 3, 0);

    expect(status, ThreadStatus.luaOk);
    expect(state.toBoolean(-3), isTrue);
    expect(state.toBoolean(-2), isTrue);
    expect(state.toBoolean(-1), isFalse);
  });

  test('suspended coroutine survives unrelated pCall', () {
    final state = LuaState.newState();
    state.openLibs();
    var loaded = state.loadString(r'''
co = coroutine.create(function()
  local value = coroutine.yield("first")
  return value
end)
local ok, value = coroutine.resume(co)
return ok, value
''');
    expect(loaded, ThreadStatus.luaOk);
    expect(state.pCall(0, 2, 0), ThreadStatus.luaOk);
    expect(state.toBoolean(-2), isTrue);
    expect(state.toStr(-1), 'first');
    state.pop(2);

    loaded = state.loadString('return 42');
    expect(loaded, ThreadStatus.luaOk);
    expect(state.pCall(0, 1, 0), ThreadStatus.luaOk);
    expect(state.toInteger(-1), 42);
    state.pop(1);

    loaded = state.loadString('return coroutine.resume(co, "second")');
    expect(loaded, ThreadStatus.luaOk);
    expect(state.pCall(0, 2, 0), ThreadStatus.luaOk);
    expect(state.toBoolean(-2), isTrue);
    expect(state.toStr(-1), 'second');
  });

  test('yield outside coroutine returns runtime error', () {
    final state = LuaState.newState();
    state.openLibs();
    final loaded = state.loadString('return coroutine.yield("x")');
    expect(loaded, ThreadStatus.luaOk);

    final status = state.pCall(0, 1, 0);

    expect(status, ThreadStatus.luaErrRun);
    expect(state.toStr(-1), contains('outside a coroutine'));
  });
}
