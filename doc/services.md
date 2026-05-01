# API服务

## ApiService
**文件**: `lib/services/api_service.dart`

实例化服务类，支持流式(SSE)和非流式调用。

### 数据类型

```dart
class StreamChunk {
  final String? content;          // 本次chunk的内容
  final String? reasoningContent; // 推理/思考内容(DeepSeek reasoning_content / Anthropic thinking_delta)
  final bool isDone;             // 流结束标记
}
```

### sendChatRequest (非流式)

```dart
Future<({String content, String? reasoning})> sendChatRequest(
  ModelConfig config,
  List<Map<String, dynamic>> messages,
  {bool thinking = false}
)
```

返回元组 `(content, reasoning?)`。Anthropic 非流式请求显式传入 `stream: false`，响应会提取 `thinking` 类型块的推理内容。

### sendStreamRequest (流式)

```dart
Stream<StreamChunk> sendStreamRequest(
  ModelConfig config,
  List<Map<String, dynamic>> messages,
  {bool thinking = false}
)
```

- OpenAI兼容: SSE解析 `data:` 前缀行 + `[DONE]` 或 `finish_reason` 结束，提取 `delta.content` 和 `delta.reasoning_content`
- Ollama: 逐行JSON, `message.content` 为文本, `done: true` 结束。注意: 当前版本不提取 Ollama 的 reasoning/thinking 内容
- Anthropic: SSE `data:` 行中提取 `type` 字段, 区分 `content_block_delta` 事件中的 `text_delta` (内容) 和 `thinking_delta` (推理), `message_stop` 事件结束
- 自动注入 `max_tokens`, `temperature`, `top_p`, `extraParams`（extraParams不会覆盖已设置的关键字段）

### 思考模式控制

| thinking | 行为 |
|----------|------|
| `true` | 若无自定义系统提示词, 则在消息列表前插入默认逐步推理提示词 |
| `false` | 显式发送禁用参数: Anthropic→`thinking: {type: disabled}`, Ollama→`think: false`, OpenAI兼容→无额外参数 |

### 支持接口

| 类型 | 端点路径 | 认证 |
|------|----------|------|
| openai | `/chat/completions` | Bearer Token |
| ollama | `/api/chat` | 无认证 |
| anthropic | `/messages` | x-api-key + anthropic-version: 2023-06-01 |
| custom | `/chat/completions` | Bearer Token |

### 请求体处理

- **OpenAI兼容**: 发送 `model`, `messages`, `stream`, 可选的 `max_tokens`, `temperature`, `top_p`, 以及 `extraParams`
- **Ollama**: 将 content 为复杂类型(如多模态数组)的消息序列化为JSON字符串, 禁用思考时传入 `think: false`。参数通过 `options` 子对象发送
- **Anthropic**: 从消息列表中提取系统提示词作为顶层 `system` 字段, 其余作为 `messages` 数组。默认 `max_tokens` 为 4096

### 超时与错误处理

- 统一超时 60 秒，超时抛出中文提示异常
- 非 200 状态码返回包含状态码和响应体的中文错误信息
- 流式请求中格式错误的chunk会被静默跳过
