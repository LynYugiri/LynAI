# 消息应用自动化

当用户要求读取、回复或发送外部消息应用内容时使用。

## 流程

1. 打开目标应用或确认当前应用。
2. 定位联系人、群聊或会话。
3. 进入会话后重新读取屏幕确认目标。
4. 优先用 `device.screen.extractMessages` 或 `lynai.device.extractMessages` 从无障碍节点读取最近可见消息；如果无障碍文本不足，再使用截图加 OCR 或识图。
5. 把最近消息压缩成结构化上下文返回给主模型。
6. 主模型生成回复文本后，重新定位输入框和发送按钮。
7. 用户任务目标包含回复或发送时，直接发送，不需要二次确认。
8. 发送后必须重新读取会话状态，验证消息已进入消息列表、输入框清空或出现"已发送"等业务标记；点击发送成功不能等同于发送成功。

复杂消息流程必须维护 phase：

```text
app_opened
conversation_located
conversation_verified
message_context_read
message_input_done
send_button_clicked
message_sent_verified
```

失败 phase 至少包括：

```text
app_open_failed
peer_uncertain
conversation_uncertain
input_failed
send_button_not_found
send_clicked_but_not_verified
message_context_unreadable
blocked_by_popup
```

## 分流原则

- 如果用户只说“帮我看看/总结/读一下”，返回上下文，不发送。
- 如果用户说“帮我回复”但没有给出回复内容，先读取上下文并返回给主模型生成回复，再发送。
- 如果用户说“给某人发某内容”或“回复某内容”，目标和内容明确时直接发送。
- 联系人、群聊或当前会话不确定时，不发送，返回 `peer_uncertain` 或 `conversation_uncertain`。
- 定位会话、读取最近消息、输入和点击发送能在同一屏内完成时，优先使用一次 `execute_lua` 编排。
- 读取到的联系人、最近消息摘要、置信度和是否已发送，应写入 `agent.memory.update` 供主 Agent 继续使用。

## Lua 发送函数建议

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

local function verify_message_sent(text)
  local deadline = os.clock() + 2.5
  repeat
    local ctx = lynai.device.extractMessages({ limit = 12 })
    if ctx.ok and ctx.result and ctx.result.messages then
      for _, msg in ipairs(ctx.result.messages) do
        if msg.text and string.find(msg.text, text, 1, true) then
          return { ok = true, marker = "message_list", context = ctx.result }
        end
      end
    end
    local visible = visible_text(80)
    if visible.ok and string.find(visible.text, "已发送", 1, true) then
      return { ok = true, marker = "sent_toast", visibleText = visible.text }
    end
    lynai.device.sleep(250)
  until os.clock() >= deadline
  local final = visible_text(80)
  return { ok = false, visibleText = final.ok and final.text or nil }
end

local function send_message(text)
  local typed = lynai.device.inputInto({ editable = true, limit = 5 }, text)
  if not typed.ok then return { ok = false, phase = "input_failed", action_ok = false, business_ok = false, error = typed.error } end
  local sent = lynai.device.waitAndClick({ text = "发送", clickable = true, timeoutMs = 800 })
  if not sent.ok then
    local current = visible_text(80)
    return {
      ok = false,
      phase = "send_button_not_found",
      action_ok = false,
      business_ok = false,
      visibleText = current.ok and current.text or nil
    }
  end
  local verified = verify_message_sent(text)
  if not verified.ok then
    return {
      ok = false,
      phase = "send_clicked_but_not_verified",
      action_ok = true,
      business_ok = false,
      clicked = "发送",
      visibleText = verified.visibleText
    }
  end
  return {
    ok = true,
    phase = "message_sent_verified",
    action_ok = true,
    business_ok = true,
    verified_by = verified.marker,
    context = verified.context
  }
end
```

发送前不要复用旧节点。进入会话、等待键盘、发送按钮状态变化后，都应重新 `device.screen.query`。
候选发送按钮、联系人或会话入口必须先读屏筛选可见项，再点击当前可见候选；普通按钮 timeout 不超过 `800ms`，页面跳转不超过 `1500ms`，发送验证不超过 `2500ms`。

## 一次读取或发送流程

```lua
local function remember(kind, content, details)
  return lynai.call("agent.memory.update", {
    entries = {{ kind = kind, source = "lua", content = content, details = details }}
  })
end

local ctx = lynai.device.extractMessages({ limit = 12 })
local verified_by = "extractMessages"
if not ctx.ok then
  ctx = lynai.device.context({ limit = 80 })
  verified_by = "device_context"
end
if not ctx.ok then
  return { ok = false, phase = "message_context_unreadable", action_ok = true, business_ok = false, error = ctx.error }
end
remember("fact", "已读取当前消息应用上下文", { phase = "message_context_read" })

-- 如果用户已明确要求发送具体内容，在确认会话后继续调用 send_message(text)。
-- 如果需要主模型生成回复，直接 return 最近消息摘要，不要发送。
return {
  ok = true,
  phase = "message_context_read",
  action_ok = true,
  business_ok = true,
  context = ctx.result,
  verified_by = verified_by
}
```

## 失败处理

- 收件人不确定时返回 `peer_uncertain`。
- 当前会话不确定时返回 `conversation_uncertain`。
- 输入框或发送按钮不存在时返回对应 phase。
- 点击发送后未验证到消息已发出时返回 `send_clicked_but_not_verified`，顶层 `ok=false`，`action_ok=true`，`business_ok=false`。
- 用户停止设备任务时立即返回停止结果。
