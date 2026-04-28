# API服务

## ApiService
**文件**: `lib/services/api_service.dart`

实例化服务类（无静态方法），支持流式和非流式调用。

### 数据类型

```dart
class StreamChunk {
  final String? content;          // 本次chunk的内容
  final String? reasoningContent; // 思考/推理内容 (DeepSeek等)
  final bool isDone;             // 是否结束
}
```

### sendChatRequest (非流式)
```dart
Future<({String content, String? reasoning})> sendChatRequest(
  ModelConfig config,
  List<Map<String, String>> messages, {
  bool thinking = false,
})
```
- OpenAI兼容: `POST {endpoint}/chat/completions`
- Ollama: `POST {endpoint}/api/chat`
- Anthropic: `POST {endpoint}/messages` (含 `x-api-key` 头，`anthropic-version: 2023-06-01`)
- 高级参数自动注入: `max_tokens`, `temperature`, `top_p`, `extraParams`
- 思考模式: 开启时自动添加系统思考提示词

### sendStreamRequest (流式)
```dart
Stream<StreamChunk> sendStreamRequest(
  ModelConfig config,
  List<Map<String, String>> messages, {
  bool thinking = false,
})
```
- SSE 流式解析 (`data: ` 行格式 + `[DONE]` 结束标记)
- Ollama 使用逐行JSON流
- 支持 `reasoning_content` (DeepSeek思考字段)
- 自动检测 `finish_reason` 结束

### 思考模式控制

- **开启** (`thinking: true`): 在消息列表前插入系统提示词，请求模型逐步推理
- **关闭** (`thinking: false`): 显式传递禁用参数
  ```json
  {
    "thinking": {"type": "disabled"},
    "enable_thinking": false,
    "reasoning_effort": "none"
  }
  ```

### 支持API类型

| 类型 | 端点路径 | 认证方式 | 特殊处理 |
|------|----------|----------|----------|
| openai | `/chat/completions` | Bearer Token | SSE流解析 |
| ollama | `/api/chat` | 无需认证 | opts→options转换, num_predict |
| anthropic | `/messages` | x-api-key | system独立字段, content数组解析 |
| custom | `/chat/completions` | Bearer Token | 兼容OpenAI格式 |
