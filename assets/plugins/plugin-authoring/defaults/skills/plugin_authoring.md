# 插件创作工作流

当用户要求从零创建一个 LynAI 插件、给已有插件加能力、修改插件清单/文件，或要把某个能力沉淀成插件时使用。本 skill 覆盖插件文件布局、plugin.json 清单、权限、校验与用户审查启用的完整流程。

## 核心概念

一个插件是一个自包含目录，`plugin.json` 声明五类能力，彼此独立、可任意组合：

| 清单字段 | 概念 | 说明 |
| --- | --- | --- |
| `tools` | 模型可调用的工具 | 声明参数 schema，由 main.lua 里的 handler 执行；通过工具调用进入模型上下文 |
| `functions` | 宿主/其他插件可调用的函数 | 不进模型工具列表，`expose: true` 可被其他插件依赖调用 |
| `commands` | 命令面板选项源 | 用户手动触发的快捷入口 |
| `skills` | 可编辑工作流知识 | 模型按需 `load_plugin_skill` 加载正文，正文是 `skills/<name>.md` |
| `featurePages` | WebView 功能页 | `index.html/css/js` 或 HTML 单文件，通过 `PluginFeatureWebView` 渲染 |

配套概念：`permissions`（能力授权）、`dependencies`（可选，对其他插件的版本依赖）、`editableFiles`（用户/模型可编辑文件与 `defaults/` 出厂模板的映射）、`lynai.autoEnable`（内置插件自动启用标记）。

## 文件布局

```text
<plugin-id>/
├── plugin.json            # 清单：id/name/version/description/permissions/能力声明/editableFiles
├── main.lua               # Lua 入口：tools 的 handler、functions 实现
├── skills/<name>.md       # 可编辑 Skill 正文（用户或模型修改后写在这里）
├── defaults/              # 出厂模板目录，运行时不可写、不可覆盖
│   ├── main.lua           #   工具 handler 出厂模板
│   ├── skills/<name>.md   #   Skill 出厂模板
│   └── <page>.html/.css   #   功能页出厂模板
├── index.html / index.css / index.js   # 功能页可编辑副本（根目录或页面子目录）
└── icon.svg               # 可选图标
```

规则：

- `defaults/` 目录不可写；删除可编辑副本（如 `skills/<name>.md`）后回退到 `defaults/` 出厂模板。
- `editableFiles` 中每项用 `path` 指向可编辑位置、`defaultPath` 指向出厂模板，两处文件都要存在。
- 技能型插件 `main.lua` 可以只有注释，无需 handler。

## 创作流程

1. 澄清目标：插件做什么、需要哪些能力（工具/函数/Skill/功能页）、需要哪些权限。
2. 调用 `create_plugin` 创建草稿：`id` 是唯一机器标识（只能字母、数字、下划线、点和横线），`name` 是显示名称。创建后当前对话自动绑定该插件为工作区，后续 `plugin_file_*` / `plugin_manifest_*` 不传 `pluginId` 即操作它。
3. 先 `plugin_file_list` 和 `plugin_manifest_get` 看现状，再用 `plugin_file_write` 写文件或 `plugin_manifest_update` 改清单；一次调用内可写多个文件。
4. 写完校验：`plugin_file_read` 读回关键文件，确认 `plugin.json` 能通过校验（`id` 不变、`entry` 存在、能力名合法、`editableFiles` 路径成对）。
5. 报告结果，请用户在插件工坊或插件管理页审查并启用。**不能自行启用插件**；生成后默认是禁用草稿。

写文件需要 `plugins.files:write` 权限；`defaults/` 目录不可写。保存 `editableFiles` 中的 Skill 正文用 `save_plugin_skill`（需要 `plugins.skills.files:write`）。

## plugin.json 清单要点

- `id`：唯一机器标识，匹配 `^[a-zA-Z0-9_.-]+$`，创建后不能改（改 id 等于换插件）。
- `name`：显示名称；`version`：SemVer；`author`、`description` 可选。
- `entry`：默认 `main.lua`；Lua 文件必须存在于插件目录。
- `permissions`：只填实际需要的权限（如 `network:public`、`notes:read`、`webview:bridge`、`model:ocr`）；声明不用的权限会让用户多一次授权决策，声明了用不到的权限会被视为越权请求。`permissions: []` 表示纯知识型插件。
- `tools`：`name` 匹配 `^[a-zA-Z0-9_-]{1,64}$`，`handler` 对应 main.lua 中的全局函数，`parameters` 必须是合法 JSON Schema（注册与执行时都要过 `AgentJsonSchemaValidator` 子集校验）。
- `dependencies`：可选；声明即要求对应插件已安装、启用且版本满足。不声明就没有依赖。
- `editableFiles`：每项 `path`/`title`/`type`/`defaultPath` 缺一不可；`type` 常用 `markdown`/`html`/`css`/`javascript`/`lua`。
- `skills`：`name` 决定正文路径 `skills/<name>.md`；`description` 和 `whenToUse` 是模型决定是否加载的唯一契约，必须写清触发场景；`modelInvocable: false` 可让 Skill 只接受显式调用。

## 工具调用惯例

- Lua 工具 handler 返回值统一 `{ok=..., error=..., ...业务字段}`；异步续延用 `__lynai_function` + `__lynai_next`（如 `http.fetchPublic`），不在 handler 里阻塞等待。
- 工具调用成功（`ok=true`、`action_ok=true`）不等于业务成功；必须检查返回的业务字段（如 `business_ok`、生成的对象 id），必要时读回验证。
- 功能页里调用插件函数或宿主能力走 WebView 桥接（`window.LynAI` / `webkit.messageHandlers`），以宿主实际注入的桥接 API 为准。
- 模型侧调用插件函数先 `list_plugin_functions` 看 `pluginId`、`functionName` 和参数 schema，再 `call_plugin_function`（需要 `plugins.callFunction` 权限）。

## 分流原则

- 用户说"做个插件/生成插件"：走完整创建流程，问清能力组合再动手。
- 用户说"改一下某插件"：先 `plugin_manifest_get` + `plugin_file_list` 看现状，小改动用 `plugin_file_write` 精准改，不要整包重写。
- 用户说"把这段经验沉淀成 Skill"：`create_plugin` 的 `kind: "skill"` 脚手架，或给既有插件加 `skills` 声明 + `defaults/skills/<name>.md` + `editableFiles`。
- 功能页/网页产物要好看：先加载 `plugin-authoring__web_design`；要做动效：先加载 `plugin-authoring__motion_design`。

## 成功 phase

```text
requirements_clarified
draft_created
files_written
manifest_validated
user_review_pending
```

## 检查清单

- `plugin.json` 的 `id` 与创建时一致；`entry` 文件存在；能力名合法且无重复。
- 每个 `editableFiles` 项的 `defaultPath` 指向 `defaults/` 下真实存在的文件。
- `permissions` 只包含实际用到的权限；生成后告知用户需要审查并启用，不自行启用。
- 写入后读回验证；发现插件处于加载错误状态时读取 `loadError` 定位问题并修复。
