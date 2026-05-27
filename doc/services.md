# 服务层、API 与工具调用

`lib/services/` 负责和外部世界交互：模型 API、平台能力、工具调用和备份文件。页面层只传入需要的上下文，服务层不持有 UI 状态。

## ApiService

文件：`lib/services/api_service.dart`

`ApiService` 负责：

- Chat 和流式 Chat。
- 图片 OCR。
- 语音转文字。
- 图片生成。
- 附件内容转换。
- reasoning/thinking 内容提取。
- OpenAI tool calls 解析。

### 标准化数据

| 类型 | 说明 |
|------|------|
| `ChatFileInput` | 发送前的附件字节、MIME 和文件名。 |
| `StreamChunk` | 流式增量，包含正文、思考内容、工具调用和结束信号。 |
| `ChatResponse` | 非流式回复，包含正文、思考内容和工具调用。 |

不同协议的返回格式差异会在 `ApiService` 内部消化。页面只处理 `StreamChunk` 和 `ChatResponse`。

### 支持协议

| `apiType` | 用途 | 流式格式 |
|-----------|------|----------|
| `openai` | OpenAI 兼容 Chat Completions。 | SSE `data:`。 |
| `custom` | 自定义 OpenAI 兼容接口。 | SSE `data:`。 |
| `ollama` | Ollama `/api/chat`。 | 逐行 JSON。 |
| `anthropic` | Anthropic Messages API。 | SSE `data:`。 |
| `openai_image` | OpenAI Images。 | 非流式 JSON。 |
| `vivo_image` | vivo 图片生成。 | 非流式 JSON。 |

### 请求体约定

| 协议 | 行为 |
|------|------|
| OpenAI 兼容 | 发送 `model`、`messages`、`stream`、`thinking`、采样参数；工具开启时发送 `tools` 和 `tool_choice`。 |
| Ollama | 发送 `model`、`messages`、`stream`、`think`；采样参数进入 `options`。 |
| Anthropic | system 消息提升到顶层 `system`，其余消息写入 `messages`，默认 `max_tokens=4096`。 |

OpenAI 兼容请求会始终发送 `thinking: {type: enabled|disabled}`。这是有意保留的行为，部分已配置后端依赖显式 disabled 标记。

`extraParams` 会合并到请求体，但不会覆盖代码已经设置的核心字段，例如 `model`、`messages`、`stream`。

### 附件转换

| 接口能力 | 图片 | 非图片文件 |
|----------|------|------------|
| 支持多模态 | 转成协议要求的 image content。 | 尽量转为文本上下文；部分链路可使用 input file 风格内容。 |
| 不支持多模态 | 文件名、MIME、大小和文本/base64 摘要。 | 文件名、MIME、大小和文本/base64 摘要。 |

OCR 和文件识别是发送前处理。处理结果会拼进用户上下文，而不是替换历史附件。

### 流式错误处理

| 场景 | 行为 |
|------|------|
| 建立连接超时 | 抛出中文异常。 |
| 非 200 响应 | 抛出包含状态码和响应体的异常。 |
| OpenAI SSE `error` | 转成异常进入 ChatPage 失败路径。 |
| Anthropic `type:error` | 转成异常进入失败路径。 |
| 单个坏 chunk | 跳过该 chunk，保留已收到正文。 |
| 工具参数不是 JSON 对象 | 跳过该工具调用。 |

## ToolCallService

文件：`lib/services/tool_call_service.dart`

`ToolCallService` 把模型请求转成本地动作。它定义工具 schema，解析 fallback JSON，校验参数，并调用 Provider 或平台通道。

### 工具清单

| 工具 | 副作用 |
|------|--------|
| `get_current_time` | 无，返回当前时间和时区。 |
| `get_location` | Android 请求定位权限并返回位置。 |
| `open_app` | Android 打开指定包名应用。 |
| `list_schedules` | 只读。 |
| `create_schedule` | 写入本地日程。 |
| `update_schedule` | 修改本地日程。 |
| `list_notes` | 只读。 |
| `read_note` | 只读。 |
| `save_note` | 创建、覆盖或追加笔记。 |

工具返回统一结构：成功为 `{ok: true, ...}`，失败为 `{ok: false, error: ...}`。这样模型可以继续解释错误，而不是让对话直接中断。

### 工具调用策略

1. OpenAI 兼容协议在子模型 `supportsTools=true` 且未通过 `extraParams.disableTools=true` 禁用时使用原生 `tools`。
2. 不适合原生工具的协议可以使用 JSON fallback。
3. 启用工具时会注入当前本地时间、时区和 `timezoneOffsetMinutes`。
4. 日程工具解析 ISO-8601 后统一转本地时间。
5. 工具调用循环会把工具阶段和最终回复阶段的 reasoning 合并保存。

### 平台通道

| 通道 | 方法 | 平台 | 说明 |
|------|------|------|------|
| `lynai/native_tools` | `openApp` | Android | 按包名打开应用。 |
| `lynai/native_tools` | `getLocation` | Android | 请求定位并读取最近位置。 |
| `lynai/native_tools` | `saveImageToGallery` | Android | 保存 PNG 到图库。 |
| `lynai/schedule_widget` | `refresh` | Android | 日程变更后刷新小组件。 |
| `lynai/schedule_widget` | `rescheduleNotifications` | Android | 日程变更后重新安排通知。 |

桌面端图片导出通常写入剪贴板；移动端更偏向图库或系统分享。

## BackupService

文件：`lib/services/backup_service.dart`

`BackupService` 负责 ZIP 备份导出、读取、预览和导入。当前 schema version 为 `1`，备份类型为 `lynai.backup`。

### 导出结构

```text
manifest.json
settings.json
model_configs.json
conversations.json
notes/folders.json
notes/notes.json
notes/revisions.json
schedules.json
todo_lists.json
assets/backgrounds/...
assets/message_images/...
```

实际写入哪些文件由 `BackupSelection` 决定。`manifest.json` 会记录类型、schema、应用版本、创建时间、分区信息和附件映射。

### 分区

| 分区 | 内容 |
|------|------|
| `settings` | `AppSettings` 和/或 `ModelConfig`，可细分 API 配置、外观、对话设置、角色与提示词。 |
| `conversations` | 选中的对话和私有附件。 |
| `notes` | 选中笔记、关联文件夹和修订。 |
| `schedules` | 选中日程。 |
| `todoLists` | 选中待办清单。 |

### 导入流程

1. `readZip()` 解压并校验 `manifest.json`。
2. 解析各分区 JSON，坏数据记录为 warning。
3. `preview()` 生成分区摘要和冲突列表。
4. 用户选择导入模式和冲突动作。
5. `importArchive()` 恢复私有附件并重映射路径。
6. 按分区应用到 Provider。
7. 清理最终数据没有引用的临时恢复附件。

### 导入模式

| 模式 | 说明 |
|------|------|
| `merge` | 合并导入；遇到冲突按用户选择处理。 |
| `addOnly` | 只添加本地不存在的数据。 |
| `replaceSection` | 对冲突项执行替换语义，非冲突项仍会按分区导入。 |

### 附件恢复

备份只归档应用私有目录中被引用的附件。导入时附件会恢复到当前设备的应用私有目录，并把旧路径替换成新路径。

如果 manifest 引用了某个附件但 ZIP 中缺失该文件，导入会记录 warning，并清除对应背景图或消息附件引用，避免导入后指向另一台设备上的无效路径。

## 服务层维护建议

1. 新增 API 协议时，先在 `ApiService` 内转换成现有 `StreamChunk` / `ChatResponse`，不要让页面知道新协议细节。
2. 新增工具时，同时更新工具 schema、参数校验、执行逻辑和文档。
3. 新增备份字段时，更新 manifest 或分区 JSON，并保证旧备份仍能读取。
4. 涉及 API Key、位置、工具写入本地数据的功能，都要在 UI 或文档中提示风险。
