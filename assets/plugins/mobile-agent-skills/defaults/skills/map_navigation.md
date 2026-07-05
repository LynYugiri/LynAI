# 地图与导航

当用户要求打车定位、搜索附近地点、查路线、开始导航时使用。本 skill 不自动叫车或支付。

## 应用信息

- 高德地图包名 `com.autonavi.minimap`。
- 百度地图包名 `com.baidu.map`。
- 谷歌地图 `com.google.android.apps.maps`。
- 用户未指定时偏好高德（国内场景），打开失败时降级百度或谷歌。

## 核心原则

- **动作成功不等于业务成功**：`waitAndClick.ok = true` 只能说明无障碍点击动作成功，不能说明已搜索到地点、已打开路线页或已进入导航态。
- 每个关键动作后必须重新读取屏幕状态，根据页面状态决定下一步；禁止线性盲点。
- 顶层 `ok` 只在业务结果已验证时才允许为 `true`。点击导航按钮后没有验证到导航态时，必须返回 `ok=false`。
- 一次能完成的"打开→搜地点→查路线→导航验证"合并为一次 `execute_lua`，但 Lua 内部必须维护 phase、debug steps 和最终业务验证。
- 查询结果摘要写入 `agent.memory.update`。

## 分流原则

- 用户说"搜 X 在哪"：搜地点→验证搜索结果/地点详情→返回名称、距离、地址，不开始导航。
- 用户说"去 X 怎么走/路线"：搜地点→验证路线页→返回步行/驾车/公交时长摘要。
- 用户说"导航去 X"：搜地点→路线页→点击当前可见导航按钮→验证进入导航态。
- 用户说"附近有什么 Y"：搜关键词→读附近列表返回前 5。

## 状态机

成功 phase：

```text
app_opened
search_entry_clicked
destination_input_done
search_submitted
poi_detail_opened
route_page_opened
nav_button_clicked
navigation_started
```

失败 phase：

```text
app_open_failed
search_entry_not_found
input_failed
search_result_not_found
poi_detail_not_opened
route_button_not_found
route_page_not_opened
nav_button_not_found
nav_clicked_but_not_verified
blocked_by_popup
unknown_state
```

## 导航态验证

点击"开始导航 / 导航 / 立即导航 / 继续导航"后，必须重新读取屏幕文本或节点。只有检测到以下任一标记，才允许返回 `navigation_started=true`：

```text
退出导航
退出導航
剩余
剩餘
全览
全覽
前方
限速
继续导航
繼續導航
```

未检测到上述标记时必须返回：

```lua
{
  ok = false,
  action_ok = true,
  business_ok = false,
  phase = "nav_clicked_but_not_verified",
  navigation_started = false
}
```

## 性能约束

- 禁止对候选按钮逐个 `timeoutMs = 3000+` 串行等待。
- 先 `readVisibleText` 或 `query` 当前屏幕，判断实际可见按钮，再只点击可见候选。
- 普通按钮点击 timeout 不超过 `800ms`。
- 页面跳转等待不超过 `1500ms`。
- 路线规划、导航态验证等重步骤不超过 `2500ms`。
- 禁止每一步无条件长 `sleep`；只允许在打开 App、加载路线、权限弹窗处理等场景做短循环等待。

## 高德首页搜索框规则

高德首页搜索入口不能假设为 `editable=true`。

1. 首页优先点击：

```text
viewId = com.autonavi.minimap:id/maphome_searchbar_bg
```

2. 若失败，再查找 text/description 包含以下内容且可点击的节点：

```text
搜索
搜尋
寻找
尋找
搜索框
搜尋框
```

3. 进入搜索页后，再等待真正的 `EditText`，然后输入目的地。

## 常用 Lua

```lua
local NAV_MARKERS = {
  "退出导航", "退出導航", "剩余", "剩餘", "全览", "全覽", "前方", "限速", "继续导航", "繼續導航"
}

local NAV_BUTTONS = {
  "开始导航", "開始導航", "立即导航", "立即導航", "继续导航", "繼續導航", "导航", "導航"
}

local ROUTE_BUTTONS = { "路线", "路線", "到这去", "到這去", "去这里", "去這裡" }
local SEARCH_ENTRY_TEXTS = { "搜索", "搜尋", "寻找", "尋找", "搜索框", "搜尋框" }

local steps = {}

local function add_step(phase, action, ok, details)
  table.insert(steps, { phase = phase, action = action, ok = ok, details = details })
end

local function visible_text(limit)
  local visible = lynai.device.readVisibleText({ limit = limit or 80 })
  if not visible.ok then return { ok = false, phase = "visible_text_unreadable", error = visible.error } end
  local parts = {}
  for _, line in ipairs(visible.result.lines or {}) do
    if line.text and line.text ~= "" then table.insert(parts, line.text) end
  end
  return { ok = true, text = table.concat(parts, "\n"), lines = visible.result.lines or {} }
end

local function contains_any(text, markers)
  for _, marker in ipairs(markers) do
    if string.find(text or "", marker, 1, true) then return marker end
  end
  return nil
end

local function fail(phase, message, extra)
  local visible = visible_text(80)
  local result = {
    ok = false,
    action_ok = extra and extra.action_ok or false,
    business_ok = false,
    phase = phase,
    destination = DEST,
    error = message,
    navigation_started = false,
    visibleText = visible.ok and visible.text or nil,
    recoverable = true,
    debug = { steps = steps }
  }
  if extra then for k, v in pairs(extra) do result[k] = v end end
  return result
end

local function wait_for_marker(markers, timeout_ms)
  local deadline = os.clock() + ((timeout_ms or 1500) / 1000)
  repeat
    local visible = visible_text(100)
    if visible.ok then
      local marker = contains_any(visible.text, markers)
      if marker then return { ok = true, marker = marker, visibleText = visible.text } end
    end
    lynai.device.sleep(250)
  until os.clock() >= deadline
  local final = visible_text(100)
  return { ok = false, visibleText = final.ok and final.text or nil }
end

local function click_visible_text(candidates, phase, timeout_ms)
  local visible = visible_text(100)
  if not visible.ok then return { ok = false, phase = phase, visibleText = nil, error = visible.error } end
  for _, text in ipairs(candidates) do
    if string.find(visible.text, text, 1, true) then
      local clicked = lynai.device.waitAndClick({ text = text, clickable = true, limit = 10, timeoutMs = timeout_ms or 800 })
      add_step(phase, "click:" .. text, clicked.ok, clicked)
      if clicked.ok then return { ok = true, clicked = text, action = clicked } end
    end
  end
  return { ok = false, visibleText = visible.text }
end
```

```lua
local function click_amap_search_entry()
  local by_id = lynai.device.waitAndClick({
    viewId = "com.autonavi.minimap:id/maphome_searchbar_bg",
    clickable = true,
    limit = 3,
    timeoutMs = 800
  })
  add_step("search_entry_clicked", "click:amap_searchbar_viewId", by_id.ok, by_id)
  if by_id.ok then return { ok = true, clicked = "amap_searchbar_viewId" } end

  local by_text = lynai.device.waitAndClick({
    textAny = SEARCH_ENTRY_TEXTS,
    clickable = true,
    limit = 10,
    timeoutMs = 800
  })
  add_step("search_entry_clicked", "click:search_entry_textAny", by_text.ok, by_text)
  if by_text.ok then return { ok = true, clicked = "search_entry_textAny" } end

  local by_desc = lynai.device.waitAndClick({
    descriptionAny = SEARCH_ENTRY_TEXTS,
    clickable = true,
    limit = 10,
    timeoutMs = 800
  })
  add_step("search_entry_clicked", "click:search_entry_descriptionAny", by_desc.ok, by_desc)
  if by_desc.ok then return { ok = true, clicked = "search_entry_descriptionAny" } end

  local visible = visible_text(100)
  return { ok = false, visibleText = visible.ok and visible.text or nil }
end

local function input_destination(name)
  local typed = lynai.device.inputText({ editable = true, limit = 5, timeoutMs = 1500 }, name)
  add_step("destination_input_done", "input_destination", typed.ok, typed)
  if not typed.ok then return { ok = false, phase = "input_failed", action_ok = false, business_ok = false, error = typed.error } end

  local submitted = click_visible_text({ "搜索", "搜尋" }, "search_submitted", 800)
  if submitted.ok then return { ok = true, submitted_by = submitted.clicked } end
  return { ok = true, submitted_by = "keyboard_or_auto" }
end

local function verify_navigation_started()
  return wait_for_marker(NAV_MARKERS, 2500)
end

local function handle_startup_popup()
  local popup = wait_for_marker({ "允许", "始终允许", "仅使用期间允许", "同意", "取消" }, 1200)
  if not popup.ok then return { ok = true } end
  if popup.marker == "取消" then return { ok = false, marker = popup.marker } end
  local accepted = click_visible_text({ popup.marker }, "app_opened", 800)
  if accepted.ok then return { ok = true, clicked = popup.marker } end
  return { ok = false, marker = popup.marker, visibleText = popup.visibleText }
end
```

## 一次 Lua 工作流骨架

```lua
DEST = "目标地点"

local function remember(content, details)
  return lynai.call("agent.memory.update", {
    entries = {{ kind = "fact", source = "lua", content = content, details = details }}
  })
end

local opened = lynai.device.openApp("com.autonavi.minimap")
add_step("app_opened", "openApp:com.autonavi.minimap", opened.ok, opened)
if not opened.ok then return fail("app_open_failed", "高德地图打开失败", { action_ok = false }) end

local popup = handle_startup_popup()
if not popup.ok then
  return fail("blocked_by_popup", "疑似被权限或协议弹窗阻塞", { action_ok = true, blocked_marker = popup.marker })
end

local entry = click_amap_search_entry()
if not entry.ok then return fail("search_entry_not_found", "未找到高德首页搜索入口", { action_ok = false, finalVisibleText = entry.visibleText }) end

local typed = input_destination(DEST)
if not typed.ok then return fail("input_failed", "目的地输入失败", { action_ok = false }) end

local result_ready = wait_for_marker({ DEST, "搜索结果", "结果", "路线", "到这去" }, 2500)
if not result_ready.ok then return fail("search_result_not_found", "未验证到搜索结果", { action_ok = true, finalVisibleText = result_ready.visibleText }) end

local poi = click_visible_text({ DEST }, "poi_detail_opened", 800)
if not poi.ok then
  return fail("poi_detail_not_opened", "未能打开目标地点详情", { action_ok = false, finalVisibleText = poi.visibleText })
end

local route = click_visible_text(ROUTE_BUTTONS, "route_page_opened", 800)
if not route.ok then return fail("route_button_not_found", "未找到路线按钮", { action_ok = false, finalVisibleText = route.visibleText }) end

local route_ready = wait_for_marker({ "分钟", "公里", "驾车", "步行", "公交", "开始导航", "导航" }, 2500)
if not route_ready.ok then return fail("route_page_not_opened", "未验证到路线规划页", { action_ok = true, finalVisibleText = route_ready.visibleText }) end

local nav = click_visible_text(NAV_BUTTONS, "nav_button_clicked", 800)
if not nav.ok then return fail("nav_button_not_found", "未找到可见导航按钮", { action_ok = false, finalVisibleText = nav.visibleText }) end

local verified = verify_navigation_started()
if not verified.ok then
  return fail("nav_clicked_but_not_verified", "已点击导航按钮，但未验证进入导航态", {
    action_ok = true,
    clicked = nav.clicked,
    finalVisibleText = verified.visibleText
  })
end

remember("已开始地图导航", { destination = DEST, verified_by = verified.marker })
return {
  ok = true,
  action_ok = true,
  business_ok = true,
  phase = "navigation_started",
  destination = DEST,
  clicked = nav.clicked,
  navigation_started = true,
  verified_by = verified.marker,
  visibleText = verified.visibleText,
  debug = { steps = steps },
  summary = "已验证进入导航态"
}
```

## 返回约定

- 复杂流程返回 `ok`、`phase`、`action_ok`、`business_ok`、`destination`、`routes`、`navigation_started`、`verified_by`、`visibleText`、`debug.steps`。
- 没有验证到业务成功时，顶层 `ok` 必须为 `false`。
- 不返回完整 screenshot、无关节点树。
- 被用户停止时直接返回 `user_stopped`。

错误码/失败 phase：

| phase | 说明 |
|---|---|
| `app_open_failed` | 地图 App 打开失败 |
| `search_entry_not_found` | 首页搜索入口未找到 |
| `input_failed` | 目的地输入失败 |
| `search_result_not_found` | 搜索结果未出现 |
| `poi_detail_not_opened` | 地点详情未打开 |
| `route_button_not_found` | 路线按钮未找到 |
| `route_page_not_opened` | 路线页未验证 |
| `nav_button_not_found` | 导航按钮未找到 |
| `nav_clicked_but_not_verified` | 点击导航按钮后未验证到导航态 |
| `blocked_by_popup` | 权限、协议或其它弹窗阻塞 |
| `unknown_state` | 页面状态无法识别 |

## 禁止行为

- 不自动叫车、不自动支付、不修改常用地址。
- 不把点击按钮成功当成导航成功。
- 不对多个候选按钮做长 timeout 串行等待。
