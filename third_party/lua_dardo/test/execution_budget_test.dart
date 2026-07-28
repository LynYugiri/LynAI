import 'package:lua_dardo/lua.dart';
import 'package:test/test.dart';

void main() {
  test('instruction budget interrupts an infinite loop', () {
    final budget = LuaExecutionBudget(maxInstructions: 100);
    final state = LuaState.newState(executionBudget: budget)..openLibs();

    expect(state.loadString('while true do end'), ThreadStatus.luaOk);
    expect(state.pCall(0, 0, 0), ThreadStatus.luaErrRun);
    expect(
      state.lastError,
      isA<LuaExecutionLimitException>().having(
        (error) => error.code,
        'code',
        'instruction_limit',
      ),
    );
  });

  test('Lua pcall cannot swallow a budget failure', () {
    final state = LuaState.newState(
      executionBudget: LuaExecutionBudget(maxInstructions: 100),
    )..openLibs();

    expect(
      state.loadString('pcall(function() while true do end end); return true'),
      ThreadStatus.luaOk,
    );
    expect(state.pCall(0, 1, 0), ThreadStatus.luaErrRun);
    expect(
      (state.lastError as LuaExecutionLimitException).code,
      'instruction_limit',
    );
  });

  test('budget persists across async yield and resume', () async {
    final budget = LuaExecutionBudget(maxInstructions: 45);
    final state = LuaState.newState(executionBudget: budget)..openLibs();
    state.pushAsyncDartFunction((ls) => ls.yieldAsync(null));
    state.setGlobal('pause');
    expect(
      state.loadString('for i = 1, 20 do pause() end return true'),
      ThreadStatus.luaOk,
    );

    final status = await state.pCallAsync(0, 1, 0, (_) async => null);

    expect(status, ThreadStatus.luaErrRun);
    expect(
      (state.lastError as LuaExecutionLimitException).code,
      'instruction_limit',
    );
  });

  test('cancellation is checked before the next instruction', () {
    var cancelled = true;
    final state = LuaState.newState(
      executionBudget: LuaExecutionBudget(isCancelled: () => cancelled),
    )..openLibs();
    expect(state.loadString('return 1'), ThreadStatus.luaOk);

    expect(state.pCall(0, 1, 0), ThreadStatus.luaErrRun);
    expect(
      (state.lastError as LuaExecutionLimitException).code,
      'cancelled',
    );
    cancelled = false;
  });

  test('deadline interrupts execution', () {
    final state = LuaState.newState(
      executionBudget: LuaExecutionBudget(maxDuration: Duration.zero),
    )..openLibs();
    expect(state.loadString('while true do end'), ThreadStatus.luaOk);

    expect(state.pCall(0, 0, 0), ThreadStatus.luaErrRun);
    expect(
      (state.lastError as LuaExecutionLimitException).code,
      'deadline_exceeded',
    );
  });

  test('host call budget counts Dart callbacks across Lua calls', () {
    final state = LuaState.newState(
      executionBudget: LuaExecutionBudget(maxHostCalls: 2),
    )..openLibs();
    state.pushDartFunction((ls) => 0);
    state.setGlobal('host');
    expect(state.loadString('host(); host(); host()'), ThreadStatus.luaOk);

    expect(state.pCall(0, 0, 0), ThreadStatus.luaErrRun);
    expect(
      (state.lastError as LuaExecutionLimitException).code,
      'host_call_limit',
    );
  });
}
