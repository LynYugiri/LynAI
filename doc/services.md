# API服务

## ApiService
**文件**: `lib/services/api_service.dart`

实例化服务类，支持流式(SSE)和非流式调用。

### 数据类型

```dart
class StreamChunk {
  final String? content;          // 本次chunk的内容
  final String? reasoningContent; // 推理/思考内容(DeepSeek reasoning_content)
  final bool isDone;             // 流结束标记
}
```

### sendChatRequest (非流式)

```dart
Future<({String content, String? reasoning})> sendChatRequest(
  ModelConfig config,
  List<Map<String, String>> messages,
  {bool thinking = false}
)
```

返回元组 `(content, reasoning?)`。Ollama 返回 `reasoning: null`。

### sendStreamRequest (流式)

```dart
Stream<StreamChunk> sendStreamRequest(
  ModelConfig config,
  List<Map<String, String>> messages,
  {bool thinking = false}
)
```

- SSE 解析: `data: ` 前缀行 + `[DONE]` 结束
- Ollama: 逐行 JSON, `done: true` 结束
- 自动注入 `max_tokens`, `temperature`, `top_p`, `extraParams`

### 思考模式控制

| thinking | 行为 |
|----------|------|
| `true` | 在消息列表前插入系统提示词，请求逐步推理 |
| `false` | 显式发送 `thinking: {type: disabled}`, `enable_thinking: false` |

### 支持接口

| 类型 | 端点路径 | 认证 |
|------|----------|------|
| openai | `/chat/completions` | Bearer Token |
| ollama | `/api/chat` | 无认证 |
| anthropic | `/messages` | x-api-key |
| custom | `/chat/completions` | Bearer Token |
