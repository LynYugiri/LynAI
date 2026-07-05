# QQ 自动回复工作流

当用户要求打开 QQ、查找联系人、读取上下文、回复或发送 QQ 消息时使用。

## 应用信息

- Android QQ 包名优先使用 `com.tencent.mobileqq`。
- TIM 可尝试 `com.tencent.tim`。
- 如果打开失败，可使用应用解析能力或向用户报告未找到 QQ。

## 查找联系人或会话

1. 调用 `lynai.device.openApp("com.tencent.mobileqq")`。
2. 等待页面加载后调用 `device.screen.query` 查找目标名称。
3. 查找参数可使用 `{ text = "foo", regex = true, limit = 20 }`。
4. 优先点击匹配节点的 `targetNodeId`，否则点击节点自身。
5. 找不到时滚动会话列表或使用 QQ 搜索入口。
6. 每次滚动后重新查询屏幕。
7. 打开 QQ、查找会话、读取上下文或发送明确内容时，优先合并为一次 `execute_lua`，不要每点一步都返回主模型。
8. 点击联系人后必须验证进入目标会话；点击发送后必须验证消息已发出。动作成功不能当作业务成功。
9. 候选联系人、搜索入口、发送按钮必须先读屏筛选当前可见项，再点击；普通按钮 timeout 不超过 `800ms`。

复杂流程 phase：

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

```lua
local function click_text(text)
  return lynai.device.waitAndClick({ text = text, limit = 20, timeoutMs = 800 })
end
```

```lua
local function verify_conversation(peer)
  local visible = lynai.device.readVisibleText({ limit = 80 })
  if not visible.ok then return { ok = false, visibleText = nil, error = visible.error } end
  local text = ""
  for _, line in ipairs(visible.result.lines or {}) do
    text = text .. "\n" .. (line.text or "")
  end
  if string.find(text, peer, 1, true) then return { ok = true, marker = peer, visibleText = text } end
  return { ok = false, visibleText = text }
end
```

如果会话列表没有目标，先找“搜索”入口或顶部搜索框。找不到搜索入口时再滚动列表，不要直接坐标乱点。

## 读取聊天上下文

1. 进入会话后优先调用 `device.screen.extractMessages` 或 `lynai.device.extractMessages`，直接从无障碍节点读取可见文本消息。
2. 只收集最近可见消息、目标昵称、我方消息和时间线索。
3. 无障碍文本不足、图片/表情/语音无法读出时，调用 `lynai.device.screenshot()` 后使用 `model.ocr` 或 `model.recognizeFile`。
4. 返回给主模型的内容应是结构化摘要，不返回完整 snapshot 或截图 base64。

建议返回最近 5 到 12 条可见消息。不能可靠区分说话人时，使用 `speaker = "unknown"` 并降低 `confidence`。

## 发送回复

1. 主模型生成回复文本后，发送 Lua 需要重新定位输入框和发送按钮。
2. 用户要求回复或发送时，直接发送，不需要二次确认。
3. 连续多条消息可在 Lua 中定义 `send_message(text)` 并重复调用。
4. 发送后返回发送数量、目标、摘要和是否成功。
5. 成功读取或发送后，用 `agent.memory.update` 记录目标、最近消息摘要、置信度或发送结果。

发送前必须重新确认仍在目标 QQ 会话中。可用目标昵称、会话标题、最近消息关键字或包名判断。确认失败时返回 `conversation_uncertain`。
发送后必须重新调用 `extractMessages` 或 `readVisibleText` 验证业务结果；未验证时返回 `send_clicked_but_not_verified`，且 `ok=false`、`action_ok=true`、`business_ok=false`。

## 推荐返回结构

```lua
return {
  ok = true,
  phase = "message_context_read",
  action_ok = true,
  business_ok = true,
  peer = "foo",
  messages = {
    { speaker = "foo", text = "..." },
    { speaker = "me", text = "..." }
  },
  confidence = 0.85,
  verified_by = "extractMessages",
  summary = "已进入 foo 的 QQ 会话并读取最近消息"
}
```

## 发送后验证示例

```lua
local function send_message(text)
  local typed = lynai.device.inputInto({ editable = true, limit = 5 }, text)
  if not typed.ok then return { ok = false, phase = "input_failed", action_ok = false, business_ok = false } end
  local clicked = lynai.device.waitAndClick({ text = "发送", clickable = true, timeoutMs = 800 })
  if not clicked.ok then return { ok = false, phase = "send_button_not_found", action_ok = false, business_ok = false } end

  local deadline = os.clock() + 2.5
  repeat
    local ctx = lynai.device.extractMessages({ app = "qq", packageName = "com.tencent.mobileqq", limit = 12 })
    if ctx.ok and ctx.result and ctx.result.messages then
      for _, msg in ipairs(ctx.result.messages) do
        if msg.text and string.find(msg.text, text, 1, true) then
          return { ok = true, phase = "message_sent_verified", action_ok = true, business_ok = true, verified_by = "message_list", context = ctx.result }
        end
      end
    end
    lynai.device.sleep(250)
  until os.clock() >= deadline
  local visible = lynai.device.readVisibleText({ limit = 80 })
  local finalText = ""
  if visible.ok then
    for _, line in ipairs(visible.result.lines or {}) do
      finalText = finalText .. "\n" .. (line.text or "")
    end
  end
  return { ok = false, phase = "send_clicked_but_not_verified", action_ok = true, business_ok = false, visibleText = visible.ok and finalText or nil }
end
```

## 禁止行为

- 不要在无法确认联系人时盲目发送。
- 不要跨屏幕刷新后继续使用旧 nodeId。
- 不要把截图 base64 返回给模型。

## 一次 Lua 工作流骨架

```lua
local function remember(content, details)
  return lynai.call("agent.memory.update", {
    entries = {{ kind = "subagent_result", source = "lua", content = content, details = details }}
  })
end

local opened = lynai.device.openApp("com.tencent.mobileqq")
if not opened.ok then
  return { ok = false, phase = "app_open_failed", action_ok = false, business_ok = false, peer = "目标昵称", error = opened.error }
end

local clicked = lynai.device.waitAndClick({ text = "目标昵称", limit = 20, timeoutMs = 800 })
if not clicked.ok then
  return { ok = false, phase = "conversation_uncertain", action_ok = false, business_ok = false, peer = "目标昵称", error = clicked.error }
end

local conversation = verify_conversation("目标昵称")
if not conversation.ok then
  return { ok = false, phase = "conversation_uncertain", action_ok = true, business_ok = false, peer = "目标昵称", visibleText = conversation.visibleText }
end

local context = lynai.device.extractMessages({ app = "qq", packageName = "com.tencent.mobileqq", limit = 12 })
if not context.ok then
  return { ok = false, phase = "message_context_unreadable", action_ok = true, business_ok = false, peer = "目标昵称", error = context.error }
end
remember("已读取目标 QQ 会话上下文", { peer = "目标昵称", confidence = 0.8 })
return {
  ok = true,
  phase = "message_context_read",
  action_ok = true,
  business_ok = true,
  peer = "目标昵称",
  messages = context.result.messages,
  confidence = context.result.confidence,
  verified_by = "extractMessages"
}
```
