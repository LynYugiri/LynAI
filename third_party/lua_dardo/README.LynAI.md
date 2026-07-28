# LynAI LuaDardo Fork

This vendored fork keeps the upstream synchronous API intact and adds a
LynAI-specific async execution path for Dart callbacks.

## Compatibility

- Existing `call`, `pCall` and `DartFunction` behavior is unchanged.
- Async execution is opt-in through `pushAsyncDartFunction`, `yieldAsync` and
  `pCallAsync`.
- `LuaExecutionBudget` can enforce cumulative instruction, monotonic deadline,
  cancellation, and Dart host-call limits. A budget belongs to the state, so it
  is not reset by async yields, protected calls, or coroutine resumes, and is
  not exposed as a Lua global.

## LynAI Usage

Agent Lua uses `pCallAsync` so `lynai.call("device.*", args)` can suspend while
Dart/Android performs asynchronous work, then resume the Lua loop with the
result table.

```dart
final state = LuaState.newState(
  executionBudget: LuaExecutionBudget(
    maxInstructions: 100000,
    maxDuration: const Duration(seconds: 5),
    maxHostCalls: 100,
    isCancelled: () => cancelled,
  ),
);
```
