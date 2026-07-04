# 系统设置自动化

当用户要求切换 Wi-Fi、蓝牙、热点、飞行模式、勿扰、亮度、定位、省电模式等系统开关时使用。

## 应用信息

- Android 系统设置包名优先使用 `com.android.settings`。
- 厂商定制 ROM（MIUI/HyperOS、ColorOS、OriginOS、OneUI 等）设置包名可能不同，打开失败时可尝试 `com.android.settings/.Settings` 或厂商专属 Activity；找不到入口时向用户报告。

## 原则

- 优先用 `lynai.device.openApp` 打开设置后用 `lynai.device.waitAndClick` 按文案逐级导航。
- 文案找不到时用 `device.screen.readVisibleText` 读取当前可见项，再决定点击路径。
- 一次能完成的开关切换合并为一次 `execute_lua`，避免每步都返回主模型。
- 切换状态后用 `device.screen.query` 复核开关文案（"开启"/"关闭"/"已连接"）确认结果。
- 切换完成写入 `agent.memory.update` 供主 Agent 继续使用。

## 分流原则

- 用户说"打开/关闭 X"：直接导航到目标开关并切换。
- 用户只问"X 现在是开还是关"：读取状态后返回，不切换。
- 厂商 ROM 入口文案与 AOSP 不同时，先 `readVisibleText` 抓真实文案再点击。

## 流程

1. 调用 `lynai.device.openApp("com.android.settings")`。
2. 用 `device.screen.query` 或 `device.screen.readVisibleText` 找目标入口（"WLAN"/"Wi-Fi"/"蓝牙"/"热点"/"飞行模式"/"勿扰"/"显示"等）。
3. `waitAndClick` 进入子页，必要时再下一级。
4. 找到开关文案，`waitAndClick` 切换。
5. 用 `device.screen.query` 复核目标开关当前文案，确认是否达到期望状态。
6. 返回切换前后状态、目标项名称。

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
local function tap_text(text)
  return lynai.device.waitAndClick({ text = text, limit = 10, timeoutMs = 4000 })
end
```

```lua
local function read_status(label)
  local visible = lynai.device.readVisibleText({ limit = 80 })
  if not visible.ok then return visible end
  local found = nil
  for _, line in ipairs(visible.result.lines or {}) do
    if line.text and string.find(line.text, label, 1, true) then
      found = line.text
      break
    end
  end
  return { ok = true, status = found }
end
```

## 返回约定

- 返回 `ok`、`phase`、`target`、`before`、`after`、`summary`。
- 不返回完整 snapshot、无关节点树。
- 被用户停止时直接返回 `user_stopped`。

错误码：

| 码 | 说明 |
|---|---|
| `ok` | 成功 |
| `element_not_found` | 目标入口或开关不存在 |
| `permission_denied` | 缺少无障碍权限 |
| `user_stopped` | 用户停止任务 |

## 失败处理

- `element_not_found`：用 `readVisibleText` 抓真实文案，重试一次仍找不到时返回候选入口列表。
- `permission_denied`：按错误提示请求用户授权，不重试点击。

## 一次 Lua 工作流骨架

```lua
local function remember(content, details)
  return lynai.call("agent.memory.update", {
    entries = {{ kind = "fact", source = "lua", content = content, details = details }}
  })
end

local opened = lynai.device.openApp("com.android.settings")
if not opened.ok then return opened end

local entered = lynai.device.waitAndClick({ text = "WLAN", limit = 10, timeoutMs = 4000 })
if not entered.ok then return entered end

local toggled = lynai.device.waitAndClick({ text = "WLAN", clickable = true, limit = 5, timeoutMs = 4000 })
if not toggled.ok then return toggled end

local status = read_status("WLAN")
remember("已切换 WLAN 开关", { target = "wlan", before = "unknown", after = status.status })
return {
  ok = true,
  phase = "system_settings",
  target = "wlan",
  after = status.status,
  summary = "已切换 WLAN 开关"
}
```

## 禁止行为

- 不直接坐标乱点，必须按文案导航。
- 不自动修改账号/安全相关设置项。