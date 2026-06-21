# 消息应用自动化

当用户要求读取、回复或发送外部消息应用内容时使用。

## 流程

1. 打开目标应用或确认当前应用。
2. 定位联系人、群聊或会话。
3. 进入会话后重新读取屏幕确认目标。
4. 读取最近可见消息；如果无障碍文本不足，使用截图加 OCR 或识图。
5. 把最近消息压缩成结构化上下文返回给主模型。
6. 主模型生成回复文本后，重新定位输入框和发送按钮。
7. 用户任务目标包含回复或发送时，直接发送，不需要二次确认。

## 分流原则

- 如果用户只说“帮我看看/总结/读一下”，返回上下文，不发送。
- 如果用户说“帮我回复”但没有给出回复内容，先读取上下文并返回给主模型生成回复，再发送。
- 如果用户说“给某人发某内容”或“回复某内容”，目标和内容明确时直接发送。
- 联系人、群聊或当前会话不确定时，不发送，返回 `peer_uncertain` 或 `conversation_uncertain`。

## Lua 发送函数建议

```lua
local function first_node(result)
  if not result.ok then return nil end
  local nodes = result.result and result.result.nodes or {}
  return nodes[1]
end

local function click_node(node)
  local id = node.targetNodeId or node.id
  return lynai.call("device.node.action", { nodeId = id, action = "click" })
end

local function send_message(text)
  local input = first_node(lynai.call("device.screen.query", { editable = true, limit = 5 }))
  if not input then return { ok = false, error = { code = "input_not_found", message = "未找到输入框" } } end
  local focused = click_node(input)
  if not focused.ok then return focused end
  local typed = lynai.call("device.inputText", { text = text })
  if not typed.ok then return typed end
  local send = first_node(lynai.call("device.screen.query", { text = "发送", clickable = true, limit = 5 }))
  if not send then return { ok = false, error = { code = "send_button_not_found", message = "未找到发送按钮" } } end
  return click_node(send)
end
```

发送前不要复用旧节点。进入会话、等待键盘、发送按钮状态变化后，都应重新 `device.screen.query`。

## 失败处理

- 收件人不确定时返回 `peer_uncertain`。
- 当前会话不确定时返回 `conversation_uncertain`。
- 输入框或发送按钮不存在时返回对应错误。
- 用户停止设备任务时立即返回停止结果。
