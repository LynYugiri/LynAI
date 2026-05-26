# 服务层

`lib/services/` 把外部 API、平台工具和备份导入导出从页面中隔离出来。页面负责收集上下文和展示结果，服务负责协议转换、错误处理和数据搬运。

## ApiService

文件：`lib/services/api_service.dart`

`ApiService` 负责 Chat、流式 Chat、OCR、语音转写、图片生成、附件内容转换和 reasoning 提取。

### 核心数据类型

```dart
class ChatFileInput {
  final Uint8List bytes;
  final String mimeType;
  final String name;
}

class StreamChunk {
  final String? content;
  final String? reasoningContent;
  final List<ChatToolCall> toolCalls;
  final bool isDone;
}

class ChatResponse {
  final String content;
  final String? reasoning;
  final List<ChatToolCall> toolCalls;
}
```

`StreamChunk` 把正文、思考内容和工具调用分离，使 UI 可以独立展示正文和 reasoning，并在流结束后继续工具调用循环。

### Chat 请求入口

| 方法 | 用途 |
|------|------|
| `sendChatRequest(config, messages, {thinking, tools, toolChoice})` | 非流式对话、工具调用二次请求、工具结果回传后的最终回复 |
| `sendStreamRequest(config, messages, {thinking})` | 聊天主链路的流式回复 |
| `chatContentWithFiles(text, files)` | 把文本和附件转换为统一内容结构 |
| `recognizeImageText(config, imageBytes)` | vivo OCR 图片识别 |
| `recognizeImageTextWithChatModel(config, prompt, files)` | 用 Chat 模型识别图片或文件内容 |
| `transcribeAudio(config, audioBytes, {audioType})` | vivo 长语音转写 |
| `generateImages(config, prompt, {image, parameters})` | OpenAI Images 或 vivo 图片生成 |

### 支持协议

| `apiType` | 路径 | 认证 | 流式格式 |
|-----------|------|------|----------|
| `openai` | `/chat/completions` | `Authorization: Bearer <key>`，key 可为空 | SSE `data:` |
| `custom` | `/chat/completions` | 同 OpenAI 兼容 | SSE `data:` |
| `ollama` | `/api/chat` | 无认证 | 逐行 JSON |
| `anthropic` | `/messages` | `x-api-key` + `anthropic-version` | SSE `data:` |
| `openai_image` | `/images/generations` | Bearer Token | 非流式 JSON |
| `vivo_image` | 配置的完整 endpoint | Bearer Token | 非流式 JSON |

### 请求体策略

| 协议 | 行为 |
|------|------|
| OpenAI 兼容 | 发送 `model`、`messages`、`stream`、`thinking`、采样参数；工具开启时发送 `tools` 和 `tool_choice` |
| Ollama | 发送 `model`、`messages`、`stream`、`think`；采样参数进入 `options` |
| Anthropic | system 消息提升到顶层 `system`，其余消息写入 `messages`，默认 `max_tokens=4096` |
| 图片生成 | OpenAI Images 使用标准 `/images/generations`，vivo 使用配置的完整 endpoint |

`extraParams` 会合并到请求体，但不会覆盖代码已经设置的核心字段，例如 `model`、`messages`、`stream`。

### 模型能力开关

当前请求使用 `ModelConfig.activeEntry` 的能力字段。

| 字段 | 影响 |
|------|------|
| `supportsVision` | 控制是否把图片作为多模态内容发送；不支持时退化为文本上下文 |
| `supportsThinking` | 控制 UI 思考开关和请求中的 thinking/think 参数 |
| `supportsTools` | 控制 OpenAI 兼容协议是否发送原生 tools |

### 思考内容解析

| 协议 | 来源 |
|------|------|
| OpenAI 兼容 | `reasoning_content`、`reasoning`、`thinking`、`thinking_content` 及对应 delta 字段 |
| Ollama | 文本中的 `<think>...</think>` |
| Anthropic | 非流式 thinking content block 和流式 `thinking_delta` |

如果模型或接口没有暴露可见 reasoning，UI 会在最后一条回复中显示说明，而不是伪造思考过程。

### 附件转换

| 接口 | 图片 | 非图片文件 |
|------|------|------------|
| OpenAI 兼容 | `image_url` data URL | 文本上下文或 `input_file` 风格内容，取决于链路 |
| Ollama | `images` 数组 | 文本上下文 |
| Anthropic | `image` content block | 文本上下文 |
| 不支持多模态 | 文件名、MIME、大小、文本/base64 摘要 | 文件名、MIME、大小、文本/base64 摘要 |

对话主链路、OCR 前处理和文件识别链路都会复用相同的附件输入模型 `ChatFileInput`。

### vivo 长语音转写

1. `/lasr/create` 创建任务。
2. `/lasr/upload` 按 5 MB 分片上传。
3. `/lasr/run` 启动任务。
4. `/lasr/progress` 每 2 秒轮询，最多 120 次。
5. `/lasr/result` 获取 `onebest` 并拼接最终文本。

### 错误处理

| 场景 | 行为 |
|------|------|
| 普通请求超时 | 60 秒 |
| 流式建立超时 | 60 秒 |
| 流读取总超时 | 10 分钟 |
| 非 200 或业务错误 | 抛出包含状态码/响应体的中文异常 |
| OpenAI SSE `error` payload | 转换为异常进入 ChatPage 失败分支 |
| Anthropic `type:error` | 转换为异常进入失败分支 |
| 单个坏 chunk | 跳过，保留已收到正文 |
| 工具参数不是 JSON 对象 | 跳过该工具调用，保留回复正文 |

## ToolCallService

文件：`lib/services/tool_call_service.dart`

`ToolCallService` 定义工具 schema、解析 fallback JSON，并把模型工具调用映射到本地 Provider 或平台通道。

### 数据类型

```dart
class ChatToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

class ToolExecutionResult {
  final String toolCallId;
  final String name;
  final Map<String, dynamic> result;
}
```

### 工具清单

| 工具 | 来源/副作用 |
|------|-------------|
| `get_current_time` | `DateTime.now()`，无副作用 |
| `get_location` | Android 原生通道，需定位权限 |
| `open_app` | Android 原生通道，按包名打开应用 |
| `list_schedules` | 读取 `FeatureProvider.schedules` |
| `create_schedule` | 写入 `FeatureProvider.addSchedule()` |
| `update_schedule` | 写入 `FeatureProvider.updateSchedule()` |
| `list_notes` | 读取 `FeatureProvider.notes` |
| `read_note` | 读取单篇笔记 |
| `save_note` | 创建、覆盖或追加笔记 |

### 调用策略

- OpenAI 兼容协议在 `supportsTools=true` 且未设置 `extraParams.disableTools=true` 时使用原生 `tools`。
- Ollama、Anthropic 和不稳定兼容接口可走 JSON fallback：`{"tool_calls":[{"name":"工具名","arguments":{...}}]}`。
- `parseFallbackToolCalls()` 会剥离 JSON 代码围栏后解析。
- 工具结果统一返回 `{ok: true, ...}` 或 `{ok: false, error: ...}`。
- 工具调用循环会累积工具阶段和最终回复阶段的 reasoning，保存到最终 assistant 消息。
- 启用工具时会注入当前本地时间、时区名和 `timezoneOffsetMinutes`。
- 日程工具解析 ISO-8601 后统一转本地时间，返回时也输出本地 ISO。

### 平台通道

| 通道 | 方法 | 平台 | 说明 |
|------|------|------|------|
| `lynai/native_tools` | `openApp` | Android | 调用 `PackageManager.getLaunchIntentForPackage()` |
| `lynai/native_tools` | `getLocation` | Android | 请求定位权限并读取最近位置 |
| `lynai/native_tools` | `saveImageToGallery` | Android | 保存 PNG 到 `Pictures/LynAI` |
| `lynai/schedule_widget` | `refresh` | Android | 日程变更后刷新小组件 |
| `lynai/schedule_widget` | `rescheduleNotifications` | Android | 日程变更后重新安排通知 |

桌面端导出图片优先通过 `super_clipboard` 写入系统剪贴板；移动端优先保存到图库或调用系统分享。

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

实际文件由 `BackupSelection` 决定，不会无条件全部写入。`manifest.json` 记录类型、schema、应用版本、创建时间、分区信息和附件映射。

### 分区

| 分区 | 内容 |
|------|------|
| `settings` | `AppSettings` 和/或 `ModelConfig`，可细分 API 配置、外观、对话设置、角色与提示词 |
| `conversations` | 选中的对话和其私有附件 |
| `notes` | 选中笔记、关联文件夹和修订 |
| `schedules` | 选中日程 |
| `todoLists` | 选中待办清单 |

### 导入流程

1. `readZip(file)` 解压 ZIP，校验 `manifest.json`，解析各分区 JSON，收集警告。
2. `preview(archive, selection)` 根据用户选择过滤数据，生成分区摘要和冲突列表。
3. 用户选择导入模式和冲突动作。
4. `importArchive(archive, plan)` 恢复私有附件、重映射路径、应用各分区数据。
5. 导入完成后删除未被最终数据引用的临时恢复附件。

### 导入模式

| 模式 | 行为 |
|------|------|
| `merge` | 合并数据，冲突按用户选择处理 |
| `addOnly` | 只添加新数据，跳过冲突 |
| `replaceSection` | 替换所选分区 |

冲突动作包括保留本地、使用导入、两者保留。两者保留时服务会生成新 ID，并修复对话、笔记、修订等内部引用。
