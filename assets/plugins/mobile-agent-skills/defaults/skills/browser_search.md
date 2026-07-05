# 浏览器搜索与信息采集

当用户要求打开浏览器或搜索应用、输入关键词搜索、读取结果并结构化摘要回主模型时使用。

## 应用信息

- 系统浏览器包名视设备而定，常见的有 `com.android.browser`、`com.android.chrome`、`com.mi.globalbrowser` 等。
- 搜索类 App 可尝试 `com.google.android.googlequicksearchbox`、`com.baidu.searchbox`、`com.sogou.activity` 等。
- 打开失败时向用户报告，可让用户指定浏览器。

## 原则

- 优先用 `lynai.device.openApp` 打开浏览器后用 `lynai.device.inputText` 输入查询、`device.screen.readVisibleText` 读取结果。
- 结果页加载需要时间，用 `device.screen.scrollUntil` 或循环+`sleep` 等待。
- 抽取结果用 `model.ocr` 做截图兜底，仅在无障碍文本不足时。
- 一次能完成的"打开→输入→读取"合并为一次 `execute_lua`，避免每步都返回主模型。
- 搜索按钮点击成功不等于检索成功；必须验证结果页出现或抽取到非空结果。
- 候选搜索入口、搜索按钮、详情链接先读屏筛选当前可见项，再点击；普通按钮 timeout 不超过 `800ms`，结果页等待不超过 `2500ms`。
- 检索结果摘要写入 `agent.memory.update` 供主 Agent 继续使用。

## 分流原则

- 用户只说"搜一下 X"：返回结果标题+摘要+来源链接，不打开详情。
- 用户说"看看 X 是什么/怎么解决"：可对前 1-3 条结果点击进入详情页读取后综合。
- 用户说"找 X 的官网/教程"：返回最相关 1-3 条，标明置信度。
- 需要登录/付费/下载才能看的内容：返回摘要并标明门槛，不尝试登录。

## 流程

1. 调用 `lynai.device.openApp(<浏览器包名>)`。
2. 定位搜索框（`editable = true`），`device.screen.inputText` 输入关键词。
3. 触发搜索（点击搜索键或回车，或搜索按钮文案）。
4. 等待结果加载，用 `device.screen.readVisibleText` 抽取标题、摘要、来源。
5. 结果不足时 `scrollUntil` 加载更多，重抽一次后停止。
6. 如需详情，对前 1-3 条 `waitAndClick` 进入，读取正文后返回。
7. 结构化摘要回主模型，必要时写入记忆。

复杂流程 phase：

```text
app_opened
search_box_focused
query_input_done
search_submitted
results_page_verified
results_extracted
```

失败 phase 至少包括：

```text
app_open_failed
search_box_not_found
input_failed
search_button_not_found
search_clicked_but_not_verified
results_empty
results_unreadable
detail_page_not_opened
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
local function search(keyword)
  local typed = lynai.device.inputText({ editable = true, limit = 5 }, keyword)
  if not typed.ok then return { ok = false, phase = "input_failed", action_ok = false, business_ok = false, error = typed.error } end
  local clicked = lynai.device.waitAndClick({ text = "搜索", clickable = true, timeoutMs = 800 })
  if not clicked.ok then return { ok = false, phase = "search_button_not_found", action_ok = false, business_ok = false } end
  return { ok = true, phase = "search_submitted", action_ok = true, business_ok = false, clicked = "搜索" }
end
```

```lua
local function extract_results()
  local visible = lynai.device.readVisibleText({ limit = 60 })
  if not visible.ok then return { ok = false, phase = "results_unreadable", action_ok = true, business_ok = false, error = visible.error } end
  local items = {}
  for _, line in ipairs(visible.result.lines or {}) do
    if line.text and #line.text > 8 then
      table.insert(items, line.text)
    end
  end
  if #items == 0 then return { ok = false, phase = "results_empty", items = items } end
  return { ok = true, phase = "results_extracted", items = items }
end
```

```lua
local function wait_results(keyword)
  local deadline = os.clock() + 2.5
  repeat
    local visible = lynai.device.readVisibleText({ limit = 80 })
    if visible.ok then
      local text = ""
      for _, line in ipairs(visible.result.lines or {}) do
        text = text .. "\n" .. (line.text or "")
      end
      if string.find(text, keyword, 1, true) or string.find(text, "搜索结果", 1, true) or string.find(text, "相关", 1, true) then
        return { ok = true, phase = "results_page_verified", visibleText = text }
      end
    end
    lynai.device.sleep(250)
  until os.clock() >= deadline
  return { ok = false, phase = "search_clicked_but_not_verified" }
end
```

## 返回约定

- 返回 `ok`、`phase`、`action_ok`、`business_ok`、`query`、`results`（标题+摘要+url/源）、`verified_by`、`summary`。
- 未验证到结果页或结果为空时，顶层 `ok` 必须为 `false`。
- 不返回完整 snapshot、截图 base64、无关节点树。
- 不确定时返回结构化结果，不替用户点广告位或下载。

错误码：

| 码 | 说明 |
|---|---|
| `ok` | 成功 |
| `element_not_found` | 搜索框或结果不存在 |
| `search_clicked_but_not_verified` | 点击搜索后未验证到结果页 |
| `results_empty` | 结果页验证后仍未抽到结果 |
| `permission_denied` | 缺少无障碍权限 |
| `user_stopped` | 用户停止任务 |

## 失败处理

- `element_not_found`：用 `readVisibleText` 重新抓文案，必要时截图 OCR 重试一次。
- 结果空：标明 `confidence = 0.3` 并返回候选关键词建议。

## 一次 Lua 工作流骨架

```lua
local function remember(content, details)
  return lynai.call("agent.memory.update", {
    entries = {{ kind = "fact", source = "lua", content = content, details = details }}
  })
end

local opened = lynai.device.openApp("com.android.chrome")
if not opened.ok then
  return { ok = false, phase = "app_open_failed", action_ok = false, business_ok = false, query = "目标关键词", error = opened.error }
end

local searched = search("目标关键词")
if not searched.ok then
  return {
    ok = false,
    phase = searched.phase or "search_button_not_found",
    action_ok = searched.action_ok or false,
    business_ok = false,
    query = "目标关键词",
    error = searched.error
  }
end

local verified = wait_results("目标关键词")
if not verified.ok then
  return {
    ok = false,
    phase = "search_clicked_but_not_verified",
    action_ok = true,
    business_ok = false,
    query = "目标关键词",
    visibleText = verified.visibleText
  }
end

local extracted = extract_results()
if not extracted.ok then
  return {
    ok = false,
    phase = extracted.phase or "results_empty",
    action_ok = true,
    business_ok = false,
    query = "目标关键词",
    visibleText = verified.visibleText
  }
end
remember("已检索关键词并抽取结果", { query = "目标关键词", count = #extracted.items })
return {
  ok = true,
  phase = "results_extracted",
  action_ok = true,
  business_ok = true,
  query = "目标关键词",
  results = extracted.items,
  verified_by = "visible_results",
  summary = "已读取搜索结果"
}
```

## 禁止行为

- 不自动登录、不自动下单、不点广告位。
