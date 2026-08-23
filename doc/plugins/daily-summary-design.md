# 「每日总结」内置插件设计

> 状态：已按 **标准内置插件** 方案设计并实现。
> 生产代码只保留内置插件登记（`PluginRepository.builtInPluginIds/builtInPluginFiles`）
> 与 `pubspec.yaml` 资产声明，插件逻辑全部使用 LynAI 已有插件接口。

---

## 0. 需求映射

| 需求 | 实现方式 |
| --- | --- |
| 内置插件「每日总结」 | `assets/plugins/daily-summary/`，登记为内置插件 |
| `config.json` 自定义模型与每日触发时间 | manifest 指向用户配置 `config.json`（首次保存时写入安装目录）与出厂 schema `defaults/config.schema.json`，由插件管理页既有 Schema 表单渲染 |
| 默认触发时间 23:00 | manifest 兜底任务 `"time": "23:00"`；`config.json` 默认同为 `"23:00"` |
| 可立即触发 | 功能页「立即总结」→ `plugin.call` 调用本插件 manifest 函数 `generate_now` |
| 默认模型 = 当前对话模型 | `"model": {}` 时 Lua 不传 `modelId`，`model.chat` 自动回退 `settings.lastChatModelId` |
| UI 好看 | `summary.html/css/js` 独立设计系统，浅色/深色、骨架屏、生成动效、空/错状态 |
| 类似笔记分页 | 左侧「往日总结」日期卡片（选中态、可展开目录）+ 主阅读区 + 前后翻页/滑动/键盘 |

---

## 1. 插件包结构

```text
lynai/assets/plugins/daily-summary/
├── plugin.json
├── icon.svg
└── defaults/
    ├── config.json          # 出厂默认模板（安装后仅作参考，用户配置写在根目录 config.json）
    ├── config.schema.json   # Schema：随内置同步刷新，不会被用户修改
    ├── main.lua             # 标准入口：素材采集、prompt、生成与保存、计划自举
    ├── daily_summary.lua    # manifest 定时任务脚本（定义 run）
    ├── summary.html         # 功能页
    ├── summary.css          # 设计系统与动效
    └── summary.js           # 分页渲染、桥接、立即总结
```

> 为什么 `config.schema.json` 放在 `defaults/`：内置插件每次启动会同步
> `builtInPluginFiles` 中的源码。`defaults/` 会整体刷新，适合放不可被用户
> 修改的 schema；而用户保存后的根目录 `config.json` 不在同步清单里，因此
> 不会被出厂模板覆盖。

`summary.html/css/js` 通过 `editableFiles` 声明为可编辑 overlay，可恢复默认。

---

## 2. `plugin.json`

```json
{
  "id": "daily-summary",
  "name": "每日总结",
  "version": "1.0.0",
  "author": "LynAI",
  "description": "每晚自动回顾当天的笔记、任务与日程，生成一篇可回看的每日总结；支持立即生成。",
  "icon": "icon.svg",
  "entry": "main.lua",
  "permissions": [
    "webview:bridge",
    "notes:read",
    "todos:read",
    "schedules:read",
    "model:chat",
    "scheduledTasks:read",
    "scheduledTasks:write"
  ],
  "scheduledTasks": [
    {
      "name": "每日总结",
      "time": "23:00",
      "script": "defaults/daily_summary.lua"
    }
  ],
  "featurePages": [
    {
      "id": "summary",
      "title": "每日总结",
      "icon": "icon.svg",
      "entry": "summary.html"
    }
  ],
  "functions": [
    {
      "name": "generate_now",
      "title": "立即生成总结",
      "description": "按 config.json 的模型设置，立即为指定日期生成一篇每日总结。不传 date 时默认为今天。",
      "handler": "generate_now",
      "parameters": {
        "type": "object",
        "properties": {
          "date": {"type": "string", "description": "目标日期 YYYY-MM-DD，默认今天"}
        }
      }
    }
  ],
  "config": {
    "path": "config.json",
    "schema": "defaults/config.schema.json"
  },
  "editableFiles": [
    {
      "path": "summary.html",
      "title": "每日总结页面",
      "type": "html",
      "defaultPath": "defaults/summary.html"
    },
    {
      "path": "summary.css",
      "title": "每日总结样式",
      "type": "css",
      "defaultPath": "defaults/summary.css"
    },
    {
      "path": "summary.js",
      "title": "每日总结交互",
      "type": "javascript",
      "defaultPath": "defaults/summary.js"
    }
  ]
}
```

---

## 3. `config.json` 与 `config.schema.json`

### 3.1 `config.json`

出厂默认模板位于 `defaults/config.json`，manifest 的实际配置路径为安装目录
根部的 `config.json`（不存在时 schema 默认值生效，首次保存时创建）：

```json
{
  "time": "23:00",
  "model": {}
}
```

### 3.2 `config.schema.json`

```json
{
  "title": "每日总结设置",
  "description": "设置每日总结的触发时间与生成模型。模型保持空表示跟随当前对话模型。",
  "fields": [
    {
      "key": "time",
      "type": "string",
      "title": "每日触发时间",
      "description": "每天生成总结的本地时间，24 小时制。修改后将在下一次定时任务运行时自动同步。",
      "placeholder": "23:00",
      "default": "23:00",
      "required": true,
      "minLength": 5,
      "maxLength": 5,
      "pattern": "^([01]\\d|2[0-3]):[0-5]\\d$",
      "patternMessage": "请使用 HH:mm 格式，例如 23:00"
    },
    {
      "key": "model",
      "type": "model",
      "title": "总结模型",
      "description": "生成每日总结使用的对话模型；清除选择表示跟随当前对话模型。",
      "category": "chat",
      "store": "selection",
      "default": {},
      "allowClear": true,
      "required": false
    }
  ]
}
```

### 3.3 字段语义

| 字段 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `time` | `string` | `"23:00"` | 目标触发时间，`HH:mm` 正则校验 |
| `model` | `model` | `{}` | `{}`/清除 = 跟随当前对话模型；选择后存 LynAI 模型选择对象 |

---

## 4. 定时触发方案（纯标准接口）

manifest 固定声明兜底任务 `每日总结 · 23:00`。`daily_summary.lua` 每次执行时做一次**计划自举**：

```text
manifest 兜底任务（23:00）运行
  ├─ 读 config.json.time
  ├─ time == "23:00"
  │   ├─ 停用「每日总结（自定义时间）」任务（若存在）
  │   └─ 生成当天总结
  └─ time != "23:00"
      ├─ 创建/更新「每日总结（自定义时间）」任务（time = config.time）
      ├─ 本次只完成计划同步，不重复生成
      └─ 后续由该 user 任务在配置时间生成
```

使用的标准接口：

- `scheduledTasks.list`：查找自己的任务（插件身份自动过滤为本插件）
- `scheduledTasks.create`：创建 `source=user` 的自定义时间任务
- `scheduledTasks.update`：更新其时间/启用状态
- `config.json` 修改入口为插件管理页的 Schema 表单

限制（与所选“零宿主改动”方案一致）：

- 修改 `config.time` 后，**下一次 23:00 兜底任务运行时**才同步计划；
- 页面只展示配置与说明，不直接读写计划；
- manifest 兜底任务始终存在，作为自举入口。

---

## 5. 生成流程（Lua + 标准接口）

```text
立即总结（功能页）
  plugin.call { functionName = "generate_now", arguments = { date } }
  → main.lua generate_now
     1. read_config()
     2. collect_material(date)
        · notes.list { includeContent = true }         → 当天更新的笔记
        · todos.list { includeItems = true }           → 清单与完成项
        · tasks.list                                   → 计划/截止/完成/创建于当天
        · calendar.list { from, to }                   → 当天日程
     3. lynai.model.chat { system, user }
        · model 为空 → 不传 modelId → 当前对话模型
        · model 已选 → 传 modelId/modelName
     4. __lynai_next: save_summary_result
        → plugin.storage.set { "summary.<date>", value }
```

定时触发复用同一套 `run_daily_summary`；`targetDate` 取 `taskContext.scheduledAt`
的日期，因此错过 23:00 后次日打开会正确补总结“昨天”。

---

## 6. 存储结构（插件私有 storage）

每个日期一个键，页面按需读取全部并自行构建索引：

```json
"summary.2026-08-23": {
  "date": "2026-08-23",
  "markdown": "# 把分页收尾的一天\n\n## 今日概览\n…",
  "model_label": "跟随当前对话模型",
  "generated_at": "2026-08-23T23:01:02.000",
  "source": "scheduled"
}
```

- 页面调用 `plugin.storage.get`（无 key）一次读取全部值，按 `summary.` 前缀过滤并倒序。
- 页面负责展示最近 90 天，并通过 `plugin.storage.remove` 清理过期键。
- 同一天「立即总结」与定时触发幂等覆盖：后写覆盖旧值。

---

## 7. UI / UX

### 7.1 布局

- 顶部：品牌、今天日期、计划状态胶囊（`计划 23:00` / `计划 08:30 · 同步中`）、设置按钮、立即总结按钮。
- 桌面：左 286px「往日总结」分页抽屉 + 主阅读区 + 页脚翻页器。
- 移动：阅读区横向滑动翻页，底部页码圆点；日期卡片切换。
- 设置抽屉展示当前 `config.time / model` 与修改入口说明。

### 7.2 笔记式分页

- 每个日期 = 一个分页卡片：序号、标题、日期、生成时间。
- 选中卡片：主色容器 tint + 左侧 3px 主色条，并展开当天 Markdown 小节目录。
- 前后翻页：按钮 / 键盘 `← →` / 触摸滑动，页码 `3 / 42`。
- 正文懒加载语义由 storage 结构天然支持（页面只需一次读取，正文按需渲染）。

### 7.3 状态与动效

| 状态 | 表现 |
| --- | --- |
| loading | 分页卡片骨架屏 + shimmer |
| empty | 月亮插画 + “还没有总结” + 立即生成按钮 |
| generating | 呼吸光环 + 三阶段文案 + 进度条 |
| error | 错误卡 + 原因 + 重试 |
| ready | 文章卡 + 模型徽标 + 生成时间 + 复制/重新生成 |

- Light/Dark 通过 `prefers-color-scheme` 切换；
- `prefers-reduced-motion` 自动降级；
- Markdown 渲染只输出安全子集，HTML 全部转义，外链只作为文本展示。

---

## 8. 宿主改动清单（实际实现）

生产 Dart 代码仅一处登记：

| # | 位置 | 变化 |
| --- | --- | --- |
| H1 | `lib/repositories/plugin_repository.dart` | `builtInPluginIds` 增加 `daily-summary`；`builtInPluginFiles` 登记 `plugin.json/icon.svg/defaults/*`（**不含用户根目录 config.json**，避免启动同步覆盖） |
| H2 | `pubspec.yaml` | 增加 `assets/plugins/daily-summary/` 与 `defaults/` |

无模型、Provider、Scheduler、Runtime、Function Service、WebView 桥接改动。

---

## 9. 权限矩阵

| 权限 | 用途 |
| --- | --- |
| `webview:bridge` | 功能页桥接 |
| `notes:read` | 采集当天更新笔记 |
| `todos:read` | 采集待办清单 |
| `schedules:read` | 采集任务与日程 |
| `model:chat` | 生成总结 |
| `scheduledTasks:read` | 计划自举时查询自身任务 |
| `scheduledTasks:write` | 计划自举时创建/更新 user 任务 |

内置插件信任安装后按声明权限授权。

---

## 10. 验证

- `plugin.json / config.json / config.schema.json` 通过 manifest 与 schema 校验；
- Lua 文件通过 `luac -p` 语法校验，并用手写 stub 验证：
  - 默认模型不传 `modelId`；
  - `generate_now` 返回 `model.chat` continuation；
  - 配置 08:30 时生成 `scheduledTasks.create` 自举命令，23:00 时不生成；
- `flutter test test/plugin_repository_test.dart` 全绿；
- `flutter test test/plugin_system_test.dart` 全绿（含内置插件资产一致性）；
- `flutter analyze --no-pub lib/repositories/plugin_repository.dart` 通过。

---

## 11. 已知限制（标准接口边界）

- 修改 `config.time` 不会立即重排任务，下一次 23:00 兜底运行后生效；
- 功能页不读取/展示「定时任务」页的运行状态，只展示配置与总结数据；
- 素材范围限于笔记、待办、任务、日程；对话数据暂不可由插件标准接口读取；
- 历史日期可手动重新生成（页面调用 `generate_now(date)`），无宿主干预。
