import 'package:flutter_test/flutter_test.dart';
import 'package:lua_dardo/lua.dart';
import 'package:lynai/models/device_control.dart';
import 'package:lynai/services/agent_lua_script_service.dart';
import 'package:lynai/services/device_run_controller.dart';

void main() {
  test('pCallAsync resumes Lua loop after async Dart callback', () async {
    final state = LuaState.newState();
    state.openLibs();
    state.pushAsyncDartFunction((ls) {
      final value = ls.checkInteger(1) ?? 0;
      ls.yieldAsync({'value': value});
    });
    state.setGlobal('await_double');

    final loaded = state.loadString('''
local sum = 0
for i = 1, 3 do
  sum = sum + await_double(i)
end
return sum
''');
    expect(loaded, ThreadStatus.luaOk);

    final status = await state.pCallAsync(0, 1, 0, (request) async {
      final map = request as Map;
      return (map['value'] as int) * 2;
    });

    expect(status, ThreadStatus.luaOk);
    expect(state.toInteger(-1), 12);
  });

  test('Agent Lua can await repeated device calls linearly', () async {
    DeviceRunController.instance.reset();
    final result = await AgentLuaScriptService().execute(
      purpose: 'test async device loop',
      code: r'''
local count = 0
for i = 1, 3 do
  local result = lynai.call("device.sleep", { ms = 1 })
  if not result.ok then return result end
  count = count + 1
end
return { ok = true, count = count }
''',
    );

    expect(result['ok'], isTrue);
    expect((result['result'] as Map)['count'], 3);
    expect(
      DeviceRunController.instance.snapshot.status,
      DeviceRunStatus.completed,
    );
  });
}
