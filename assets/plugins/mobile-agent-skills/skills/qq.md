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

```lua
local function click_text(text)
  return lynai.device.waitAndClick({ text = text, limit = 20, timeoutMs = 5000 })
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

## 推荐返回结构

```lua
return {
  ok = true,
  phase = "qq_context",
  peer = "foo",
  messages = {
    { speaker = "foo", text = "..." },
    { speaker = "me", text = "..." }
  },
  confidence = 0.85,
  summary = "已进入 foo 的 QQ 会话并读取最近消息"
}
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
if not opened.ok then return opened end

local clicked = lynai.device.waitAndClick({ text = "目标昵称", limit = 20, timeoutMs = 5000 })
if not clicked.ok then return clicked end

local context = lynai.device.extractMessages({ app = "qq", packageName = "com.tencent.mobileqq", limit = 12 })
if not context.ok then return context end
remember("已读取目标 QQ 会话上下文", { peer = "目标昵称", confidence = 0.8 })
return { ok = true, phase = "qq_context", peer = "目标昵称", messages = context.result.messages, confidence = context.result.confidence }
```
