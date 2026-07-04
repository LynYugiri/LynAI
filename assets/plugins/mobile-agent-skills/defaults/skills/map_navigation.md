# 地图与导航

当用户要求打车定位、搜索附近地点、查路线、开始导航时使用。本 skill 不自动叫车或支付。

## 应用信息

- 高德地图包名 `com.autonavi.minimap`。
- 百度地图包名 `com.baidu.map`。
- 谷歌地图 `com.google.android.apps.maps`。
- 用户未指定时偏好高德（国内场景），打开失败时降级百度或谷歌。

## 原则

- 优先用 `lynai.device.openApp` 打开地图后用 `lynai.device.inputText` 输入目的地。
- 路线查询前先确定起点（默认当前位置）；用户指定起点时显式输入。
- 导航走"开始导航"按钮；不点叫车、不点支付、不修改常用地址。
- 一次能完成的"打开→搜地点→查路线"合并为一次 `execute_lua`。
- 查询结果摘要写入 `agent.memory.update`。

## 分流原则

- 用户说"搜 X 在哪"：搜地点→返回名称、距离、地址，不开始导航。
- 用户说"去 X 怎么走/路线"：搜地点→查路线→返回步行/驾车/公交时长摘要。
- 用户说"导航去 X"：搜地点→查路线→点"开始导航"。
- 用户说"附近有什么 Y"：搜关键词→读附近列表返回前 5。

## 流程

1. 调用 `lynai.device.openApp("com.autonavi.minimap")`。
2. 定位搜索框（`editable = true`），`inputText` 输入目的地。
3. 等待搜索结果，`waitAndClick` 点目标地点。
4. 切换路线方式（驾车/公交/步行），`device.screen.query` 读取时长/距离。
5. 需要导航时 `waitAndClick` "开始导航"。

## 常用 Lua

```lua
local function search_place(name)
  local typed = lynai.device.inputText({ editable = true, limit = 5 }, name)
  if not typed.ok then return typed end
  lynai.device.sleep(1500)
  return lynai.device.waitAndClick({ text = name, limit = 10, timeoutMs = 5000 })
end
```

```lua
local function read_routes()
  local visible = lynai.device.readVisibleText({ limit = 50 })
  if not visible.ok then return visible end
  local routes = {}
  for _, line in ipairs(visible.result.lines or {}) do
    if line.text and (string.find(line.text, "分钟", 1, true) or string.find(line.text, "公里", 1, true)) then
      table.insert(routes, line.text)
    end
  end
  return { ok = true, routes = routes }
end
```

## 返回约定

- 返回 `ok`、`phase`、`destination`、`routes`（带 `mode`/`duration`/`distance`）、`navigation_started`、`summary`。
- 不返回完整 screenshot、无关节点树。
- 被用户停止时直接返回 `user_stopped`。

错误码：

| 码 | 说明 |
|---|---|
| `ok` | 成功 |
| `place_not_found` | 地点搜不到 |
| `element_not_found` | 路线/导航按钮不存在 |
| `permission_denied` | 缺少定位/无障碍权限 |
| `user_stopped` | 用户停止任务 |

## 失败处理

- `place_not_found`：返回候选地点列表由主模型再询问用户。
- `element_not_found`：`readVisibleText` 抓真实文案重试一次。

## 一次 Lua 工作流骨架

```lua
local function remember(content, details)
  return lynai.call("agent.memory.update", {
    entries = {{ kind = "fact", source = "lua", content = content, details = details }}
  })
end

local opened = lynai.device.openApp("com.autonavi.minimap")
if not opened.ok then return opened end

local found = search_place("目标地点")
if not found.ok then return found end

local routes = read_routes()
remember("已查询到目标地点的路线", { destination = "目标地点", routes = routes.routes })
return {
  ok = true,
  phase = "map_navigation",
  destination = "目标地点",
  routes = routes.routes,
  navigation_started = false,
  summary = "已查询路线摘要"
}
```

## 禁止行为

- 不自动叫车、不自动支付、不修改常用地址。