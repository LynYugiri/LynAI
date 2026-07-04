# 时钟与闹钟

当用户要求设置系统闹钟、倒计时、查看世界钟或时间时使用。本地提醒走 `schedules.create`，本 skill 仅用于系统级闹钟。

## 应用信息

- 系统时钟包名 `com.google.android.deskclock`、`com.android.deskclock`、`com.sec.android.app.clockpackage`、`com.android_alarmclock` 等。
- 厂商定制时钟可能合并闹钟/倒计时/秒表/世界钟于同一 App，打开后按文案导航。
- 打开失败时向用户报告。

## 原则

- 优先用 `lynai.device.openApp` 打开时钟后用 `lynai.device.waitAndClick` 按文案导航到闹钟/倒计时页签。
- 新建闹钟走"+ 添加"或"新建"入口，输入时间后保存。
- 只读已有闹钟列表时不要点删除按钮。
- 与本地 `schedule_item` 区分：系统级闹钟触发响铃由系统发起；本地 `schedules.create` 仅在 LynAI 内提醒。
- 设置完成写入 `agent.memory.update` 供主 Agent 继续使用。

## 分流原则

- 用户说"设明天 7 点的闹钟"：进闹钟页签→新建→设时间→保存。
- 用户说"X 分钟后提醒我"：进倒计时页签或用本地 `schedules.create`；本 skill 走倒计时。
- 用户说"我有哪些闹钟"：进闹钟页签读取列表返回。
- 用户说"删掉某闹钟"：返回 `confirm_required` 列出目标闹钟，由主模型确认后再删。

## 流程

1. 调用 `lynai.device.openApp(<时钟包名>)`。
2. `waitAndClick` 进入"闹钟"页签（文案可能为"闹钟"/"Alarm"）。
3. 新建：`waitAndClick` 找"+ 添加"/"新建"按钮。
4. 输入时间：用 `device.screen.inputText` 或滚动时间选择器，按厂商流程；不同厂商控件不同，先用 `readVisibleText` 看清控件。
5. 保存：`waitAndClick` "确定"/"保存"/"完成"。
6. 倒计时：切到倒计时页签，输入分钟，点开始。
7. 复核：`device.screen.query` 确认新建闹钟出现在列表中、时间正确。

## 常用 Lua

```lua
local function tap_text(text)
  return lynai.device.waitAndClick({ text = text, limit = 10, timeoutMs = 4000 })
end
```

```lua
local function set_time_picker(hour, minute)
  -- 厂商控件差异大，先读取可见文案判断控件类型
  local visible = lynai.device.readVisibleText({ limit = 30 })
  if not visible.ok then return visible end
  -- 数字键盘或时间滚轮，按厂商流程点击对应数字
  -- 这里给出通用框架，实际数值输入按真实控件调整
  return { ok = true, hour = hour, minute = minute }
end
```

## 返回约定

- 返回 `ok`、`phase`、`alarm`（time/label/enabled）、`summary`。
- 不返回完整闹钟列表除非用户明确要列出。
- 被用户停止时直接返回 `user_stopped`。

错误码：

| 码 | 说明 |
|---|---|
| `ok` | 成功 |
| `element_not_found` | 闹钟入口/时间控件不存在 |
| `permission_denied` | 缺少无障碍权限 |
| `user_stopped` | 用户停止任务 |

## 失败处理

- `element_not_found`：`readVisibleText` 抓真实文案再试一次。
- 厂商时钟控件不可控：标明 `confirm_required` 让用户手动调整时间，Agent 只负责打开页面。

## 一次 Lua 工作流骨架

```lua
local function remember(content, details)
  return lynai.call("agent.memory.update", {
    entries = {{ kind = "fact", source = "lua", content = content, details = details }}
  })
end

local opened = lynai.device.openApp("com.google.android.deskclock")
if not opened.ok then return opened end

local entered_alarm = tap_text("闹钟")
if not entered_alarm.ok then return entered_alarm end

local added = tap_text("添加")
if not added.ok then return added end

local set = set_time_picker(7, 0)
if not set.ok then return set end

local saved = tap_text("确定")
if not saved.ok then return saved end

remember("已设置周一至周五 7 点闹钟", { time = "07:00", label = "默认" })
return {
  ok = true,
  phase = "clock_alarm",
  alarm = { time = "07:00", enabled = true },
  summary = "已新建 7 点闹钟"
}
```

## 禁止行为

- 关热点/勿扰前确认；不自动删除已存在的闹钟。
