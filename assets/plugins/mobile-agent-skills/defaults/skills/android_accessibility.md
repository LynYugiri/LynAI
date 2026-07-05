# Android 无障碍自动化

当任务需要读取 Android 屏幕、点击控件、输入文本、滚动页面或调用 OCR/识图时使用。

## 原则

- 优先使用 `lynai.device.query`、`lynai.device.waitAndClick`、`lynai.device.inputInto` 或 `device.screen.extractMessages`；需要底层能力时再用 `lynai.call("device.*", ...)`。
- 需要完整结构时再读取 `device.screen.snapshot`，不要默认把完整 snapshot 返回给主模型。
- 节点 `id` 只在当前无障碍快照缓存中有效；获取节点后应尽快执行 `device.node.action`，不要在点击前刷新屏幕。
- 优先使用节点动作和高级封装，必要时才使用坐标 `device.tap` 或 `device.swipe`。
- 页面切换后重新读取屏幕并确认 `packageName`、标题或关键文案。
- **动作成功不等于业务成功**：`waitAndClick.ok`、`click.ok`、`inputText.ok` 只代表无障碍动作成功。发送、保存、导航、拨号、开关、搜索等业务必须在动作后重新读取状态并验证。
- 复杂自动化必须按 `状态识别 -> 执行动作 -> 状态验证 -> 明确返回` 编排，不能只返回工具调用结果。
- 涉及多页面跳转的脚本必须维护 `phase`，失败时返回具体阶段、`visibleText` 和 `recoverable`，不要只返回 `{ ok = false, error = "failed" }`。
- 返回结构中要区分 `action_ok` 和 `business_ok`；未验证业务成功时顶层 `ok` 必须为 `false`。
- 候选按钮点击前先 `readVisibleText` 或 `query` 判断当前屏幕实际存在什么，禁止多个长 timeout 候选串行等待。
- 普通按钮 timeout 控制在 `800ms` 左右，页面跳转等待不超过 `1500ms`，重步骤验证不超过 `2500ms`；禁止无条件长 `sleep`。
- 截图只作为 OCR/识图输入，最终返回给模型的是 OCR 文本、识图描述或结构化结论，不返回 base64。
- 读屏、查节点、等待节点属于屏幕读取；点击、输入、返回、打开应用属于设备控制。缺权限时按错误提示请求用户授权。
- Lua 可以写清晰的多步流程和循环，不要为了节省长度牺牲判断、错误处理和返回结构。
- 同一应用内的打开、查找、等待、点击、滚动、输入和读取，能合并就放在一次 `execute_lua` 中线性编排。
- 重要发现、确认目标、失败原因和最终摘要写入 `agent.memory.update`，不要把完整 snapshot 或截图写入工作记忆。

## 常用调用

```lua
local ctx = lynai.device.query({ text = "发送", clickable = true, limit = 5 })
if not ctx.ok then
  return { ok = false, phase = "target_not_found", action_ok = false, business_ok = false, error = ctx.error }
end
```

```lua
local function query_retry(args, times)
  for _ = 1, times or 3 do
    local result = lynai.device.query(args)
    if result.ok and result.result and result.result.nodes and result.result.nodes[1] then
      return result
    end
    lynai.device.sleep(350)
  end
  return { ok = false, error = { code = "node_not_found", message = "未找到目标节点" } }
end
```

```lua
local clicked = lynai.device.waitAndClick({ text = "发送", clickable = true, timeoutMs = 800 })
if not clicked.ok then
  return { ok = false, phase = "send_button_not_found", action_ok = false, business_ok = false, error = clicked.error }
end
```

上面只说明"发送"按钮点击动作成功，不能直接当作消息已发出。必须继续读取会话、Toast、发送按钮状态或消息列表，验证业务结果。

```lua
local function visible_text(limit)
  local visible = lynai.device.readVisibleText({ limit = limit or 80 })
  if not visible.ok then return { ok = false, phase = "visible_text_unreadable", error = visible.error } end
  local parts = {}
  for _, line in ipairs(visible.result.lines or {}) do
    if line.text and line.text ~= "" then table.insert(parts, line.text) end
  end
  return { ok = true, text = table.concat(parts, "\n"), lines = visible.result.lines or {} }
end

local function fail(phase, message, steps, extra)
  local visible = visible_text(80)
  local result = {
    ok = false,
    phase = phase,
    action_ok = extra and extra.action_ok or false,
    business_ok = false,
    error = message,
    visibleText = visible.ok and visible.text or nil,
    recoverable = true,
    debug = { steps = steps or {} }
  }
  if extra then for k, v in pairs(extra) do result[k] = v end end
  return result
end
```

```lua
local shot = lynai.device.screenshot()
if shot.ok then
  local ocr = lynai.call("model.ocr", {
    files = {{ dataBase64 = shot.result.dataBase64, mimeType = shot.result.mimeType, name = "screen.png" }}
  })
end
```

## 返回约定

- 返回 `ok`、`phase`、`action_ok`、`business_ok`、`summary`、少量候选节点和必要文本。
- 复杂流程建议统一返回：

```lua
{
  ok = true or false,
  phase = "...",
  action_ok = true or false,
  business_ok = true or false,
  target = "...",
  result = "...",
  verified_by = "...",
  visibleText = "...",
  debug = {
    steps = {
      { phase = "...", action = "...", ok = true },
      { phase = "...", action = "...", ok = false }
    }
  }
}
```

- 不返回完整截图、完整 base64、无关节点树。
- 不确定时返回结构化错误，不盲目点击或发送。
- 被用户停止时直接返回工具给出的 `user_stopped` 错误，不要继续重试。

## 一次 Lua 编排模板

```lua
local memory = lynai.call("agent.memory.read", {})
local planned = lynai.call("agent.plan.update", {
  items = {{ id = "step_1", status = "in_progress", summary = "正在执行手机自动化" }}
})
if not planned.ok then
  return fail("plan_update_failed", "计划更新失败", {}, { action_ok = false, error = planned.error })
end

local opened = lynai.device.openApp("目标包名")
if not opened.ok then
  return fail("app_open_failed", "目标应用打开失败", {}, { action_ok = false, error = opened.error })
end

local found = query_retry({ text = "目标文案", limit = 10 }, 5)
if not found.ok then
  return fail("target_not_found", "未找到目标文案", {}, { action_ok = false, error = found.error })
end
local node = found.result.nodes[1]
local clicked = lynai.device.click(node)
if not clicked.ok then
  return fail("target_click_failed", "目标点击动作失败", {{ phase = "target_found", action = "query", ok = true }}, { action_ok = false, error = clicked.error })
end

local verified = query_retry({ text = "目标动作完成后的确认文案", limit = 5 }, 3)
if not verified.ok then
  local current = visible_text(80)
  return {
    ok = false,
    phase = "clicked_but_not_verified",
    action_ok = true,
    business_ok = false,
    visibleText = current.ok and current.text or nil,
    debug = { steps = {{ phase = "target_clicked", action = "click", ok = true }} }
  }
end

lynai.call("agent.memory.update", {
  entries = {{ kind = "fact", source = "lua", content = "已确认并点击目标文案" }}
})
return {
  ok = true,
  phase = "business_verified",
  action_ok = true,
  business_ok = true,
  summary = "自动化步骤完成",
  memorySeen = memory.ok
}
```
