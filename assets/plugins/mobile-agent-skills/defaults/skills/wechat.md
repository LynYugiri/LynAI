# 微信会话自动化

当用户要求打开微信、查找联系人或会话、读取上下文、回复或发送微信消息时使用。

## 应用信息

- Android 微信包名优先使用 `com.tencent.mm`。
- 企业微信可尝试 `com.tencent.wework`。
- 打开失败时向用户报告未找到微信。

## 原则

- 优先用 `lynai.device.openApp`、`lynai.device.extractMessages`、`lynai.device.waitAndClick`、`lynai.device.inputInto`；需要底层能力时再用 `lynai.call("device.*", ...)`。
- 节点 `id` 只在当前无障碍快照缓存中有效，进入会话、键盘弹出、发送按钮状态变化后必须重新 `device.screen.query`。
- 同一应用内打开、查找、读取、输入、发送能合并就放在一次 `execute_lua` 中线性编排，避免每步都返回主模型。
- 朋友圈、公众号、扫一扫属于次级入口，仅当用户明确要求时才进入。
- 读取到的联系人、最近消息摘要、置信度、是否已发送，应写入 `agent.memory.update`。

## 分流原则

- 用户只说"帮我看看/总结/读一下"：返回上下文，不发送。
- 用户说"帮我回复"但未给内容：读取上下文回主模型生成，再发送。
- 用户说"给某人发某内容"或"回复某内容"：目标和内容明确时直接发送。
- 收件人或会话不确定：不发送，返回 `peer_uncertain` 或 `conversation_uncertain`。

## 流程

1. 调用 `lynai.device.openApp("com.tencent.mm")`。
2. 等待首页加载，用 `device.screen.query` 查找目标昵称或会话标题。
3. 找不到目标时优先用顶部"搜索"入口，输入名称后等待结果；不要直接坐标乱点。
4. 进入会话后调用 `device.screen.extractMessages` 或 `lynai.device.extractMessages` 读取最近可见消息。
5. 无障碍文本不足、图片/语音无法读出时，截图后调用 `model.ocr` 或 `model.recognizeFile`。
6. 主模型生成回复后，重新定位输入框和发送按钮再发送。
7. 连续多条消息可在 Lua 中定义 `send_message(text)` 并重复调用。
8. 发送后返回发送数量、目标、摘要和是否成功。

## 常用 Lua

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
local function send_message(text)
  local typed = lynai.device.inputInto({ editable = true, limit = 5 }, text)
  if not typed.ok then return typed end
  return lynai.device.waitAndClick({ text = "发送", clickable = true, timeoutMs = 3000 })
end
```

```lua
local function remember(content, details)
  return lynai.call("agent.memory.update", {
    entries = {{ kind = "fact", source = "lua", content = content, details = details }}
  })
end
```

## 返回约定

- 返回 `ok`、`phase`、`peer`、`messages`、`confidence`、`summary`。
- 不返回完整截图、完整 base64、无关节点树。
- 被用户停止时直接返回工具给出的 `user_stopped` 错误。

错误码：

| 码 | 说明 |
|---|---|
| `ok` | 成功 |
| `peer_uncertain` | 收件人不确定 |
| `conversation_uncertain` | 当前会话不确定 |
| `element_not_found` | 输入框或发送按钮不存在 |
| `permission_denied` | 缺少无障碍权限 |
| `user_stopped` | 用户停止任务 |

## 失败处理

- `peer_uncertain`：返回候选联系人列表由主模型再询问用户。
- `conversation_uncertain`：用目标昵称、会话标题、最近消息关键字或包名重新确认；失败则返回。
- `element_not_found`：等待键盘弹出、滚动到底部、重新 `device.screen.query` 后再试一次。

## 一次 Lua 工作流骨架

```lua
local function remember(content, details)
  return lynai.call("agent.memory.update", {
    entries = {{ kind = "subagent_result", source = "lua", content = content, details = details }}
  })
end

local opened = lynai.device.openApp("com.tencent.mm")
if not opened.ok then return opened end

local clicked = lynai.device.waitAndClick({ text = "目标昵称", limit = 20, timeoutMs = 5000 })
if not clicked.ok then return clicked end

local context = lynai.device.extractMessages({ app = "wechat", packageName = "com.tencent.mm", limit = 12 })
if not context.ok then return context end
remember("已读取目标微信会话上下文", { peer = "目标昵称", confidence = 0.8 })
return {
  ok = true,
  phase = "wechat_context",
  peer = "目标昵称",
  messages = context.result.messages,
  confidence = context.result.confidence,
  summary = "已进入目标微信会话并读取最近消息"
}
```

## 禁止行为

- 不确定收件人时不发送。
- 不群发、不自动转发陌生链接。
- 不把截图 base64 返回给模型。