import 'package:flutter_test/flutter_test.dart';
import 'package:lua_dardo/lua.dart';
import 'package:lynai/models/agent_plan.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/device_control.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/services/agent_lua_script_service.dart';
import 'package:lynai/services/device_run_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test('Agent Lua awaits model calls without starting device run', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.replaceSettings(
      AppSettings.defaults().copyWith(agentGrantedPermissions: const []),
    );
    DeviceRunController.instance.reset();

    final result = await AgentLuaScriptService().execute(
      purpose: 'test async model call',
      settings: settings,
      code: r'''
local result = lynai.call("model.ocr", { imageBase64 = "AA==" })
return result
''',
    );

    expect(result['ok'], isFalse);
    expect(result['error'], contains('model:ocr'));
    expect(DeviceRunController.instance.snapshot.status, DeviceRunStatus.idle);
  });

  test('Agent Lua can update plan during async device script', () async {
    SharedPreferences.setMockInitialValues({});
    final conversations = ConversationProvider();
    final cid = conversations.createConversation(
      ConversationSettings(modelId: 'm1', agentEnabled: true),
    );
    conversations.addMessage(cid, 'user', 'run device plan');
    conversations.addMessage(cid, 'assistant', '', save: false);
    conversations.updateAgentPlan(
      cid,
      AgentPlan(
        id: 'plan_1',
        title: '测试计划',
        items: const [AgentPlanItem(id: 'step_1', title: '等待')],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    DeviceRunController.instance.reset();

    final result = await AgentLuaScriptService().execute(
      purpose: 'update plan from lua',
      conversations: conversations,
      conversationId: cid,
      code: r'''
local planned = lynai.call("agent.plan.update", {
  items = {
    { id = "step_1", status = "in_progress", summary = "Lua 正在等待" }
  }
})
if not planned.ok then return planned end
local slept = lynai.call("device.sleep", { ms = 1 })
if not slept.ok then return slept end
return lynai.call("agent.plan.update", {
  items = {
    { id = "step_1", status = "completed", resultSummary = "已等待" }
  }
})
''',
    );

    expect(result['ok'], isTrue);
    final conversation = conversations.getConversation(cid)!;
    final item = conversation.agentPlan!.items.single;
    expect(item.status, AgentPlanItem.completed);
    expect(item.resultSummary, '已等待');
    final trace = conversation.messages.last.agentTrace;
    expect(
      trace?.events.where((event) => event.type == 'plan_update'),
      hasLength(2),
    );
  });
}
