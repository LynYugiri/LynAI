# 通讯录与电话

当用户要求查找联系人、读取号码、拨打电话、挂断电话时使用。

## 应用信息

- 通讯录包名 `com.android.contacts` 或 `com.samsung.android.app.contacts`、`com.huawei.contacts` 等。
- 拨号器 `com.android.dialer`、`com.android.incallui`、`com.samsung.android.dialtacts2` 等。
- 打开失败时向用户报告。

## 原则

- 优先用 `lynai.device.openApp` 打开通讯录后用 `lynai.device.query` 按名称查联系人。
- 拨号是不可逆动作，进入拨号界面后由主模型或用户最终确认再点拨号键。
- 一次能完成的"查找→进入详情→拨号"合并为一次 `execute_lua`，但最终拨号点击前停下确认。
- 拨号完成后返回号码、目标姓名、是否接通（如可读）；点击拨号键成功不等于进入通话页，必须验证业务状态。
- 候选联系人、搜索入口、拨号按钮先读屏筛选当前可见项，再点击；普通按钮 timeout 不超过 `800ms`，页面跳转或通话态验证不超过 `2500ms`。
- 不自动回拨未接陌生来电，先返回候选号码让用户确认。

## 分流原则

- 用户说"给 X 打电话"：查联系人→进详情→拨号前确认。
- 用户说"X 的电话是多少"：查到后返回，不拨号。
- 用户说"挂断"：打开拨号界面找挂断按钮点击；找不到时提示用户手动挂断。
- 联系人不存在：返回 `contact_not_found`。

## 流程

1. 调用 `lynai.device.openApp("com.android.contacts")`。
2. 用搜索框或列表 `device.screen.query` 找目标姓名。
3. `waitAndClick` 进入联系人详情，读取号码、备注。
4. 找"电话"或"拨打"项 `waitAndClick` 进入拨号界面。
5. 拨号界面准备就绪后**停下**，把号码和姓名回主模型确认或等用户唤起确认。
6. 确认后再 `execute_lua` 或 `device.screen.clickText` 点击拨号键。
7. 需要挂断时打开拨号界面 `query` 挂断按钮并点击。

复杂流程 phase：

```text
contacts_opened
contact_search_done
contact_detail_opened
phone_number_read
dialer_ready
dial_button_clicked
call_state_verified
```

失败 phase 至少包括：

```text
app_open_failed
search_entry_not_found
input_failed
contact_not_found
contact_detail_not_opened
phone_number_not_found
dialer_not_ready
dial_button_not_found
dial_clicked_but_not_verified
hangup_button_not_found
```

## 常用 Lua

```lua
local function find_contact(name)
  local opened = lynai.device.openApp("com.android.contacts")
  if not opened.ok then return { ok = false, phase = "app_open_failed", action_ok = false, business_ok = false, contact = name, error = opened.error } end
  local searched = lynai.device.waitAndClick({ text = "搜索", clickable = true, limit = 5, timeoutMs = 800 })
  if not searched.ok then return { ok = false, phase = "search_entry_not_found", action_ok = false, business_ok = false, contact = name, error = searched.error } end
  local typed = lynai.device.inputText({ editable = true, limit = 3 }, name)
  if not typed.ok then return { ok = false, phase = "input_failed", action_ok = false, business_ok = false, contact = name, error = typed.error } end
  lynai.device.sleep(500)
  local found = lynai.device.query({ text = name, limit = 5 })
  if not found.ok or not (found.result and found.result.nodes and found.result.nodes[1]) then
    return { ok = false, phase = "contact_not_found", action_ok = true, business_ok = false, contact = name }
  end
  return { ok = true, phase = "contact_search_done", action_ok = true, business_ok = true, contact = name, result = found.result }
end
```

```lua
local function dial_number(phone)
  local entered = lynai.device.openApp("com.android.dialer")
  if not entered.ok then return { ok = false, phase = "dialer_not_ready", action_ok = false, business_ok = false, phone = phone, error = entered.error } end
  local typed = lynai.device.inputText({ editable = true, limit = 3 }, phone)
  if not typed.ok then return { ok = false, phase = "input_failed", action_ok = false, business_ok = false, phone = phone, error = typed.error } end
  return { ok = true, phase = "dialer_ready", action_ok = true, business_ok = true, phone = phone }
end
```

```lua
local function verify_call_started()
  local markers = { "挂断", "结束通话", "通话", "正在拨号", "免提", "静音" }
  local deadline = os.clock() + 2.5
  repeat
    local visible = lynai.device.readVisibleText({ limit = 80 })
    if visible.ok then
      for _, line in ipairs(visible.result.lines or {}) do
        for _, marker in ipairs(markers) do
          if line.text and string.find(line.text, marker, 1, true) then
            return { ok = true, marker = marker }
          end
        end
      end
    end
    lynai.device.sleep(250)
  until os.clock() >= deadline
  return { ok = false }
end
```

```lua
local function confirm_and_dial(phone)
  local clicked = lynai.device.waitAndClick({ textAny = { "拨号", "呼叫", "Call" }, clickable = true, limit = 5, timeoutMs = 800 })
  if not clicked.ok then
    return { ok = false, phase = "dial_button_not_found", action_ok = false, business_ok = false, phone = phone, error = clicked.error }
  end
  local verified = verify_call_started()
  if not verified.ok then
    return { ok = false, phase = "dial_clicked_but_not_verified", action_ok = true, business_ok = false, phone = phone }
  end
  return {
    ok = true,
    phase = "call_state_verified",
    action_ok = true,
    business_ok = true,
    phone = phone,
    verified_by = verified.marker
  }
end
```

## 返回约定

- 返回 `ok`、`phase`、`action_ok`、`business_ok`、`contact`、`phone`、`confirm_required`、`verified_by`、`summary`。
- 拨号前返回 `confirm_required = true`，不自动点击拨号键。
- 已点击拨号但未验证进入通话页时，返回 `dial_clicked_but_not_verified`，顶层 `ok=false`，`action_ok=true`，`business_ok=false`。
- 不返回完整通讯录、无关节点树。

错误码：

| 码 | 说明 |
|---|---|
| `ok` | 成功 |
| `contact_not_found` | 联系人不存在 |
| `element_not_found` | 拨号界面元素缺失 |
| `dial_clicked_but_not_verified` | 点击拨号后未验证进入通话页 |
| `permission_denied` | 缺少电话/无障碍权限 |
| `user_stopped` | 用户停止任务 |

## 失败处理

- `contact_not_found`：返回候选姓名列表（搜索结果前 5），由主模型再询问用户。
- `element_not_found`：用 `readVisibleText` 抓界面真实文案再点击一次。

## 一次 Lua 工作流骨架

```lua
local function remember(content, details)
  return lynai.call("agent.memory.update", {
    entries = {{ kind = "fact", source = "lua", content = content, details = details }}
  })
end

local found = find_contact("张三")
if not found.ok then
  return { ok = false, phase = found.phase or "contact_not_found", action_ok = found.action_ok or false, business_ok = false, contact = "张三", error = found.error }
end

local clicked = lynai.device.waitAndClick({ text = "张三", limit = 5, timeoutMs = 800 })
if not clicked.ok then
  return { ok = false, phase = "contact_detail_not_opened", action_ok = false, business_ok = false, contact = "张三", error = clicked.error }
end

local visible = lynai.device.readVisibleText({ limit = 40 })
if not visible.ok then
  return { ok = false, phase = "phone_number_not_found", action_ok = true, business_ok = false, contact = "张三", error = visible.error }
end

local phone = nil
for _, line in ipairs(visible.result.lines or {}) do
  if line.text and string.match(line.text, "^[%d +%%-()]+$") then
    phone = line.text
    break
  end
end

if not phone then
  return {
    ok = false,
    phase = "phone_number_not_found",
    action_ok = true,
    business_ok = false,
    contact = "张三",
    summary = "已打开联系人详情，但未验证到电话号码"
  }
end

remember("已查找联系人并读取号码", { contact = "张三", phone = phone })
return {
  ok = true,
  phase = "phone_number_read",
  action_ok = true,
  business_ok = true,
  contact = "张三",
  phone = phone,
  confirm_required = true,
  summary = "已读取张三的号码，是否拨号请确认"
}
```

## 禁止行为

- 不自动回拨未接陌生来电。
- 未经确认不点击最终拨号键。
