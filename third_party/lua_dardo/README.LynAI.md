# LynAI LuaDardo Fork

This vendored fork keeps the upstream synchronous API intact and adds a
LynAI-specific async execution path for Dart callbacks.

## Compatibility

- Existing `call`, `pCall` and `DartFunction` behavior is unchanged.
- Async execution is opt-in through `pushAsyncDartFunction`, `yieldAsync` and
  `pCallAsync`.
- The async path is designed as VM groundwork for Lua coroutine-style
  suspension. It does not expose a complete Lua 5.3 `coroutine` standard library
  yet.

## LynAI Usage

Agent Lua uses `pCallAsync` so `lynai.call("device.*", args)` can suspend while
Dart/Android performs asynchronous work, then resume the Lua loop with the
result table.
