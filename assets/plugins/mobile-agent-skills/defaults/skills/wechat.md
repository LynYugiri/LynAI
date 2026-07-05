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
- 发送、查找、进入会话等动作必须在动作后重新读屏验证业务状态；不能把点击成功当作业务成功。
- 候选按钮或联系人入口先读屏筛选当前可见项，再点击；普通按钮 timeout 不超过 `800ms`，页面跳转等待不超过 `1500ms`，发送验证不超过 `2500ms`。

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
9. 发送后必须验证消息已出现在会话列表、输入框已清空或出现"已发送"等标记；未验证则返回 `send_clicked_but_not_verified`。

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

```lua
local function send_message(text)
  local typed = lynai.device.inputInto({ editable = true, limit = 5 }, text)
  if not typed.ok then return { ok = false, phase = "input_failed", action_ok = false, business_ok = false, error = typed.error } end
  local clicked = lynai.device.waitAndClick({ text = "发送", clickable = true, timeoutMs = 800 })
  if not clicked.ok then
    return { ok = false, phase = "send_button_not_found", action_ok = false, business_ok = false }
  end
  local deadline = os.clock() + 2.5
  repeat
    local ctx = lynai.device.extractMessages({ app = "wechat", packageName = "com.tencent.mm", limit = 12 })
    if ctx.ok and ctx.result and ctx.result.messages then
      for _, msg in ipairs(ctx.result.messages) do
        if msg.text and string.find(msg.text, text, 1, true) then
          return {
            ok = true,
            phase = "message_sent_verified",
            action_ok = true,
            business_ok = true,
            verified_by = "message_list",
            context = ctx.result
          }
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
  return {
    ok = false,
    phase = "send_clicked_but_not_verified",
    action_ok = true,
    business_ok = false,
    clicked = "发送",
    visibleText = visible.ok and finalText or nil
  }
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

- 返回 `ok`、`phase`、`action_ok`、`business_ok`、`peer`、`messages`、`confidence`、`verified_by`、`summary`。
- 没有验证到业务成功时，顶层 `ok` 必须为 `false`。
- 不返回完整截图、完整 base64、无关节点树。
- 被用户停止时直接返回工具给出的 `user_stopped` 错误。

错误码：

| 码 | 说明 |
|---|---|
| `ok` | 成功 |
| `peer_uncertain` | 收件人不确定 |
| `conversation_uncertain` | 当前会话不确定 |
| `element_not_found` | 输入框或发送按钮不存在 |
| `send_clicked_but_not_verified` | 点击发送后未验证到消息发出 |
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

local context = lynai.device.extractMessages({ app = "wechat", packageName = "com.tencent.mm", limit = 12 })
if not context.ok then
  return { ok = false, phase = "message_context_unreadable", action_ok = true, business_ok = false, peer = "目标昵称", error = context.error }
end
remember("已读取目标微信会话上下文", { peer = "目标昵称", confidence = 0.8 })
return {
  ok = true,
  phase = "message_context_read",
  action_ok = true,
  business_ok = true,
  peer = "目标昵称",
  messages = context.result.messages,
  confidence = context.result.confidence,
  verified_by = "extractMessages",
  summary = "已进入目标微信会话并读取最近消息"
}
```

## 禁止行为

- 不确定收件人时不发送。
- 不群发、不自动转发陌生链接。
- 不把截图 base64 返回给模型。
