# API 服务与工具调用

## ApiService

**文件**：`lib/services/api_service.dart`

`ApiService` 是所有远程能力的入口，负责 Chat、流式 Chat、OCR、语音转写、图片生成和多模态图片识别。

## 数据类型

```dart
class ChatImageInput {
  final Uint8List bytes;
  final String mimeType;
}

class StreamChunk {
  final String? content;
  final String? reasoningContent;
  final bool isDone;
}

class ChatResponse {
  final String content;
  final String? reasoning;
  final List<ChatToolCall> toolCalls;
}
```

`StreamChunk` 将正文和思考内容拆开返回，便于 UI 分区展示。`ChatResponse` 用于非流式请求和工具调用二次请求。

## Chat 请求

### 非流式

```dart
Future<ChatResponse> sendChatRequest(
  ModelConfig config,
  List<Map<String, dynamic>> messages, {
  bool thinking = false,
  List<Map<String, dynamic>> tools = const [],
  String? toolChoice,
})
```

用途：普通非流式回复、工具调用、工具结果回传后的最终回复。

### 流式

```dart
Stream<StreamChunk> sendStreamRequest(
  ModelConfig config,
  List<Map<String, dynamic>> messages, {
  bool thinking = false,
})
```

用途：聊天主回复。UI 逐 chunk 更新最后一条 assistant 消息，流结束后再持久化。

## 支持接口

| `apiType` | 路径 | 认证 | 流式格式 |
|-----------|------|------|----------|
| `openai` | `/chat/completions` | `Authorization: Bearer <key>`，API Key 可为空 | SSE `data:` |
| `custom` | `/chat/completions` | 同 OpenAI 兼容 | SSE `data:` |
| `ollama` | `/api/chat` | 无认证 | 逐行 JSON |
| `anthropic` | `/messages` | `x-api-key` + `anthropic-version` | SSE `data:` |
| `openai_image` | `/images/generations` | Bearer Token | 非流式 JSON |
| `vivo_image` | 配置的完整 endpoint | Bearer Token | 非流式 JSON |

## 请求体策略

| 接口 | 行为 |
|------|------|
| OpenAI 兼容 | 发送 `model`、`messages`、`stream`、`thinking`、`max_tokens`、`temperature`、`top_p`、`tools`、`tool_choice` |
| Ollama | 发送 `model`、`messages`、`stream`、`think`；采样参数放入 `options` |
| Anthropic | 将 system 消息提取为顶层 `system`，其余消息写入 `messages`；默认 `max_tokens=4096` |
| 图片生成 | OpenAI Images 使用 `/images/generations`；vivo 图片生成使用配置的完整 endpoint |

`extraParams` 会被合并进请求体，但不会覆盖已经由代码设置的关键字段。

## 思考内容解析

| 接口 | 解析来源 |
|------|----------|
| OpenAI 兼容 | `reasoning_content`、`reasoning`、`thinking`、`thinking_content` 及对应流式 delta 字段 |
| Ollama | 非流式和流式文本中的 `<think>...</think>` |
| Anthropic | 非流式 `thinking` 内容块与流式 `thinking_delta` |

当 `thinking=true` 时，OpenAI 兼容接口发送 `thinking: {type: enabled}`，Ollama 发送 `think: true`。Anthropic 不自动注入厂商私有 thinking 参数，需要时通过 `extraParams` 显式配置。

## 图片与语音接口

| 方法 | 说明 |
|------|------|
| `recognizeImageText(config, imageBytes)` | 调用 vivo OCR，返回识别文本 |
| `recognizeImageTextWithChatModel(config, prompt, images)` | 使用多模态 Chat 模型识别图片，OpenAI 兼容使用 `image_url`，Ollama 使用 `images` 数组，Anthropic 使用 `/messages` |
| `transcribeAudio(config, audioBytes, {audioType})` | 调用 vivo 长语音转写，自动分片上传并轮询结果 |
| `generateImages(config, prompt, {image, parameters})` | 调用 OpenAI Images 或 vivo 图片生成接口 |

## vivo 长语音转写流程

1. `/lasr/create` 创建音频任务。
2. `/lasr/upload` 按 5 MB 分片上传音频。
3. `/lasr/run` 启动转写。
4. `/lasr/progress` 每 2 秒轮询，最多 120 次。
5. `/lasr/result` 获取最终 `onebest` 文本并拼接返回。

## 超时与错误处理

- 普通请求超时为 60 秒。
- 流式请求建立连接超时为 60 秒，流读取总超时为 10 分钟。
- 非 200 或业务错误码会抛出包含状态码和响应体的中文异常。
- 流式解析中格式异常的 chunk 会被跳过，避免单个坏 chunk 中断整个响应。

## ToolCallService

**文件**：`lib/services/tool_call_service.dart`

`ToolCallService` 定义本地工具、解析 fallback JSON，并把模型工具调用映射为本地执行结果。

## 工具数据类型

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

## 可用工具

| 工具名 | 说明 | 数据来源 |
|--------|------|----------|
| `get_current_time` | 获取当前时间、时区和 ISO 时间 | Dart `DateTime.now()` |
| `get_location` | 获取设备最近位置 | 原生通道 `getLocation` |
| `open_app` | Android 按包名打开应用 | 原生通道 `openApp` |
| `list_schedules` | 查询日程列表，可按时间范围过滤 | `FeatureProvider.schedules` |
| `create_schedule` | 创建日程 | `FeatureProvider.addSchedule()` |
| `update_schedule` | 修改日程 | `FeatureProvider.updateSchedule()` |
| `list_notes` | 查询笔记列表，可返回摘要或完整内容 | `FeatureProvider.notes` |
| `read_note` | 按 id、标题或关键字读取笔记 | `FeatureProvider.getNote()` |
| `save_note` | 创建、覆盖或追加笔记 | `FeatureProvider.addNote()` / `updateNote()` |

## 工具调用策略

- OpenAI 兼容接口支持原生 `tools` 和 `tool_choice`。
- 不支持原生 tool calls 的接口可按系统提示返回 JSON：`{"tool_calls":[{"name":"工具名","arguments":{...}}]}`。
- `parseFallbackToolCalls()` 会自动剥离 JSON 代码围栏并解析 `tool_calls`。
- 工具结果统一返回 `{ok: true, ...}` 或 `{ok: false, error: ...}`。
- 工具调用循环会累积每轮 `ChatResponse.reasoning`，并把工具调用阶段与最终回复阶段的思考过程一起显示在最终 assistant 消息上。
- 启用工具时，系统消息会追加当前设备本地时间、时区名和 `timezoneOffsetMinutes`，降低相对时间理解偏差。
- 日程工具参数使用 ISO-8601 字符串；解析后统一转本地时间保存，返回 `start`/`end` 时输出本地 ISO，并附带时区名与偏移量。
- `list_schedules` 使用时间区间相交过滤，适配跨天日程和按日期范围查询。

## 平台通道

通道名：`lynai/native_tools`。

Android 实现位于 `android/app/src/main/kotlin/com/github/lynyugiri/lynai/MainActivity.kt`。

| 方法 | 说明 |
|------|------|
| `openApp` | 使用 `PackageManager.getLaunchIntentForPackage()` 启动应用 |
| `getLocation` | 请求 `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` 后读取最近位置 |
| `saveImageToGallery` | 写入 `MediaStore.Images`，Android Q 及以上保存到 `Pictures/LynAI` |
