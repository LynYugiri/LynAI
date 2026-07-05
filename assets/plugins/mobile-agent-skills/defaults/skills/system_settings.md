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
- 点击开关成功不等于状态已改变；必须验证 `after` 达到用户期望。未验证时返回 `switch_clicked_but_not_verified`，顶层 `ok=false`。
- 候选入口或开关按钮先读屏筛选当前可见项，再点击；普通按钮 timeout 不超过 `800ms`，页面跳转不超过 `1500ms`，状态验证不超过 `2500ms`。
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

复杂流程 phase：

```text
app_opened
settings_entry_opened
target_page_opened
status_before_read
switch_clicked
switch_state_verified
```

失败 phase 至少包括：

```text
app_open_failed
settings_entry_not_found
target_page_not_opened
switch_not_found
switch_clicked_but_not_verified
blocked_by_popup
unknown_state
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
local function tap_text(text)
  return lynai.device.waitAndClick({ text = text, limit = 10, timeoutMs = 800 })
end
```

```lua
local function read_status(label)
  local visible = lynai.device.readVisibleText({ limit = 80 })
  if not visible.ok then return { ok = false, phase = "status_unreadable", error = visible.error } end
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

```lua
local function verify_status(label, expected)
  local deadline = os.clock() + 2.5
  repeat
    local status = read_status(label)
    if status.ok and status.status then
      local text = status.status
      if expected == "on" and (string.find(text, "开启", 1, true) or string.find(text, "已连接", 1, true) or string.find(text, "打开", 1, true)) then
        return { ok = true, status = text, marker = "on" }
      end
      if expected == "off" and (string.find(text, "关闭", 1, true) or string.find(text, "未连接", 1, true) or string.find(text, "关", 1, true)) then
        return { ok = true, status = text, marker = "off" }
      end
    end
    lynai.device.sleep(250)
  until os.clock() >= deadline
  return read_status(label)
end
```

## 返回约定

- 返回 `ok`、`phase`、`action_ok`、`business_ok`、`target`、`before`、`after`、`verified_by`、`summary`。
- 没有验证到目标状态时，顶层 `ok` 必须为 `false`。
- 不返回完整 snapshot、无关节点树。
- 被用户停止时直接返回 `user_stopped`。

错误码：

| 码 | 说明 |
|---|---|
| `ok` | 成功 |
| `element_not_found` | 目标入口或开关不存在 |
| `switch_clicked_but_not_verified` | 点击开关后状态未验证 |
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
if not opened.ok then
  return { ok = false, phase = "app_open_failed", action_ok = false, business_ok = false, target = "wlan", error = opened.error }
end

local expected = "on"
local entered = lynai.device.waitAndClick({ text = "WLAN", limit = 10, timeoutMs = 800 })
if not entered.ok then
  return { ok = false, phase = "settings_entry_not_found", action_ok = false, business_ok = false, target = "wlan", error = entered.error }
end

local before = read_status("WLAN")
local toggled = lynai.device.waitAndClick({ text = "WLAN", clickable = true, limit = 5, timeoutMs = 800 })
if not toggled.ok then
  return { ok = false, phase = "switch_not_found", action_ok = false, business_ok = false, target = "wlan", before = before.status, error = toggled.error }
end

local status = verify_status("WLAN", expected)
if not status.ok or not status.marker then
  return {
    ok = false,
    phase = "switch_clicked_but_not_verified",
    action_ok = true,
    business_ok = false,
    target = "wlan",
    before = before.status,
    after = status.status,
    summary = "已点击 WLAN 开关，但未验证到目标状态"
  }
end

remember("已切换 WLAN 开关", { target = "wlan", before = before.status, after = status.status })
return {
  ok = true,
  phase = "switch_state_verified",
  action_ok = true,
  business_ok = true,
  target = "wlan",
  before = before.status,
  after = status.status,
  verified_by = status.marker,
  summary = "已切换 WLAN 开关"
}
```

## 禁止行为

- 不直接坐标乱点，必须按文案导航。
- 不自动修改账号/安全相关设置项。
