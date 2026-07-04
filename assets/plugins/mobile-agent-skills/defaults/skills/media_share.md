# 系统分享与跨应用转发

当用户要求通过系统分享面板把文本或图片转发到其他应用时使用。本 skill 走系统分享 Intent 流，不尝试任何支付/转账类动作。

## 应用信息

- 系统分享面板通常由系统应用弹出，包名视设备而定；触发入口在源应用的"分享"/"发送"按钮上。
- 接收应用：微信、QQ、微博、笔记、邮件、蓝牙等。
- 打开失败时向用户报告。

## 原则

- 优先在源应用内触发"分享"，等待分享面板弹出后 `device.screen.query` 找目标应用图标。
- 文本分享：选目标应用后多数应用会先弹输入框确认；图片分享：选目标应用后多数直接进入发送界面。
- 跨应用操作合并为一次 `execute_lua`：触发分享→选应用→确认输入→发送。
- 不向陌生人分享位置、原图（除非用户明确要求）。

## 分流原则

- 用户说"把这段话发到微信"：触发分享→选微信→进会话→确认发送。
- 用户说"把这张图存到笔记"：触发分享→选笔记应用→保存。
- 用户说"分享给 X"：分享面板选 X 对应应用+联系人；陌生联系人先返回候选列表确认。
- 用户说"用蓝牙发"：选蓝牙→选配对设备；不发起新配对。

## 流程

1. 在源应用找到"分享"/"发送"按钮，`waitAndClick` 触发。
2. 等待分享面板弹出，`device.screen.query` 找目标应用名称或图标文案。
3. `waitAndClick` 选目标应用。
4. 进入目标应用后按对应流程（wechat/qq 等）选择联系人并发送。
5. 复核：`device.screen.query` 看"已发送"Toast 或会话消息列表确认。

## 常用 Lua

```lua
local function share_to(app_name)
  local shared = lynai.device.waitAndClick({ text = "分享", clickable = true, timeoutMs = 4000 })
  if not shared.ok then return shared end
  lynai.device.sleep(800)
  return lynai.device.waitAndClick({ text = app_name, limit = 10, timeoutMs = 5000 })
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

- 返回 `ok`、`phase`、`via`、`target`、`summary`。
- 不返回完整 screenshot、无关节点树。
- 被用户停止时直接返回 `user_stopped`。

错误码：

| 码 | 说明 |
|---|---|
| `ok` | 成功 |
| `share_panel_not_found` | 分享面板未弹出 |
| `target_app_not_found` | 目标应用未出现在面板 |
| `permission_denied` | 缺少无障碍权限 |
| `user_stopped` | 用户停止任务 |

## 失败处理

- `share_panel_not_found`：`readVisibleText` 抓文案确认是否已弹出；持续失败提示用户手动触发分享。
- `target_app_not_found`：返回面板上可见应用列表让用户选。

## 一次 Lua 工作流骨架

```lua
local shared = share_to("微信")
if not shared.ok then return shared end

-- 微信内会弹出选择会话页；选目标会话
local picked = lynai.device.waitAndClick({ text = "目标昵称", limit = 10, timeoutMs = 4000 })
if not picked.ok then return picked end

local sent = lynai.device.waitAndClick({ text = "发送", clickable = true, timeoutMs = 3000 })
if not sent.ok then return sent end

remember("已通过微信分享给目标", { via = "wechat", target = "目标昵称" })
return {
  ok = true,
  phase = "media_share",
  via = "wechat",
  target = "目标昵称",
  summary = "已分享到微信目标会话"
}
```

## 禁止行为

- 不向陌生人分享位置或原图。