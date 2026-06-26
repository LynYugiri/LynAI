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

## 分流原则

- 如果用户只说“帮我看看/总结/读一下”，返回上下文，不发送。
- 如果用户说“帮我回复”但没有给出回复内容，先读取上下文并返回给主模型生成回复，再发送。
- 如果用户说“给某人发某内容”或“回复某内容”，目标和内容明确时直接发送。
- 联系人、群聊或当前会话不确定时，不发送，返回 `peer_uncertain` 或 `conversation_uncertain`。
- 定位会话、读取最近消息、输入和点击发送能在同一屏内完成时，优先使用一次 `execute_lua` 编排。
- 读取到的联系人、最近消息摘要、置信度和是否已发送，应写入 `agent.memory.update` 供主 Agent 继续使用。

## Lua 发送函数建议

```lua
local function send_message(text)
  local typed = lynai.device.inputInto({ editable = true, limit = 5 }, text)
  if not typed.ok then return typed end
  return lynai.device.waitAndClick({ text = "发送", clickable = true, timeoutMs = 3000 })
end
```

发送前不要复用旧节点。进入会话、等待键盘、发送按钮状态变化后，都应重新 `device.screen.query`。

## 一次读取或发送流程

```lua
local function remember(kind, content, details)
  return lynai.call("agent.memory.update", {
    entries = {{ kind = kind, source = "lua", content = content, details = details }}
  })
end

local ctx = lynai.device.extractMessages({ limit = 12 })
if not ctx.ok then ctx = lynai.device.context({ limit = 80 }) end
if not ctx.ok then return ctx end
remember("fact", "已读取当前消息应用上下文", { phase = "message_context" })

-- 如果用户已明确要求发送具体内容，在确认会话后继续调用 send_message(text)。
-- 如果需要主模型生成回复，直接 return 最近消息摘要，不要发送。
return { ok = true, phase = "message_context", context = ctx.result }
```

## 失败处理

- 收件人不确定时返回 `peer_uncertain`。
- 当前会话不确定时返回 `conversation_uncertain`。
- 输入框或发送按钮不存在时返回对应错误。
- 用户停止设备任务时立即返回停止结果。
