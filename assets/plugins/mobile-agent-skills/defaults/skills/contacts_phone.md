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
- 拨号完成后返回号码、目标姓名、是否接通（如可读）。
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

## 常用 Lua

```lua
local function find_contact(name)
  local opened = lynai.device.openApp("com.android.contacts")
  if not opened.ok then return opened end
  local searched = lynai.device.waitAndClick({ text = "搜索", clickable = true, limit = 5, timeoutMs = 3000 })
  if not searched.ok then return searched end
  local typed = lynai.device.inputText({ editable = true, limit = 3 }, name)
  if not typed.ok then return typed end
  lynai.device.sleep(800)
  return lynai.device.query({ text = name, limit = 5 })
end
```

```lua
local function dial_number(phone)
  local entered = lynai.device.openApp("com.android.dialer")
  if not entered.ok then return entered end
  local typed = lynai.device.inputText({ editable = true, limit = 3 }, phone)
  if not typed.ok then return typed end
  return { ok = true, phase = "dial_ready", phone = phone }
end
```

## 返回约定

- 返回 `ok`、`phase`、`contact`、`phone`、`confirm_required`、`summary`。
- 拨号前返回 `confirm_required = true`，不自动点击拨号键。
- 不返回完整通讯录、无关节点树。

错误码：

| 码 | 说明 |
|---|---|
| `ok` | 成功 |
| `contact_not_found` | 联系人不存在 |
| `element_not_found` | 拨号界面元素缺失 |
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
if not found.ok then return found end

local clicked = lynai.device.waitAndClick({ text = "张三", limit = 5, timeoutMs = 4000 })
if not clicked.ok then return clicked end

local visible = lynai.device.readVisibleText({ limit = 40 })
if not visible.ok then return visible end

local phone = nil
for _, line in ipairs(visible.result.lines or {}) do
  if line.text and string.match(line.text, "^[%d +%%-()]+$") then
    phone = line.text
    break
  end
end

remember("已查找联系人并读取号码", { contact = "张三", phone = phone })
return {
  ok = true,
  phase = "contact_lookup",
  contact = "张三",
  phone = phone,
  confirm_required = true,
  summary = "已读取张三的号码，是否拨号请确认"
}
```

## 禁止行为

- 不自动回拨未接陌生来电。