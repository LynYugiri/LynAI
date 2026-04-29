import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/model_config.dart';

class StreamChunk {
  final String? content;
  final String? reasoningContent;
  final bool isDone;

  StreamChunk({this.content, this.reasoningContent, this.isDone = false});
}

class ApiService {
  Future<({String content, String? reasoning})> sendChatRequest(
    ModelConfig config,
    List<Map<String, String>> messages, {
    bool thinking = false,
  }) async {
    try {
      final processedMessages = thinking
          ? _addThinkingPrompt(messages)
          : messages;

      if (config.apiType == 'ollama') {
        return await _sendOllamaRequest(config, processedMessages, thinking: thinking);
      } else if (config.apiType == 'anthropic') {
        return await _sendAnthropicRequest(config, processedMessages, thinking: thinking);
      } else {
        return await _sendOpenAICompatibleRequest(config, processedMessages, thinking: thinking);
      }
    } catch (e) {
      throw Exception('API 请求异常: $e');
    }
  }

  Stream<StreamChunk> sendStreamRequest(
    ModelConfig config,
    List<Map<String, String>> messages, {
    bool thinking = false,
  }) async* {
    try {
      final processedMessages = thinking
          ? _addThinkingPrompt(messages)
          : messages;

      if (config.apiType == 'ollama') {
        yield* _sendOllamaStreamRequest(config, processedMessages, thinking: thinking);
      } else {
        yield* _sendOpenAICompatibleStreamRequest(config, processedMessages, thinking: thinking);
      }
    } catch (e) {
      throw Exception('流式请求异常: $e');
    }
  }

  Map<String, dynamic>
      _thinkingDisabledParams() {
    return {
      'thinking': {'type': 'disabled'},
      'enable_thinking': false,
    };
  }

  List<Map<String, String>> _addThinkingPrompt(
      List<Map<String, String>> messages) {
    final hasSystem = messages.any((m) => m['role'] == 'system');
    if (hasSystem) return messages;

    return [
      {
        'role': 'system',
        'content': 'Please think step by step before providing your final answer. '
            'First, analyze the question deeply and provide your reasoning, '
            'then give a clear and concise answer.'
      },
      ...messages,
    ];
  }

  Future<({String content, String? reasoning})>
      _sendOpenAICompatibleRequest(
    ModelConfig config,
    List<Map<String, String>> messages, {
    bool thinking = false,
  }) async {
    final uri = Uri.parse('${config.endpoint}/chat/completions');

    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': messages,
      'stream': false,
      if (config.maxTokens != null) 'max_tokens': config.maxTokens,
      if (config.temperature != null) 'temperature': config.temperature,
      if (config.topP != null) 'top_p': config.topP,
      if (!thinking) ..._thinkingDisabledParams(),
      ...config.extraParams,
    };

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (config.apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.apiKey}';
    }

    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final choice = data['choices'][0];
      final message = choice['message'];
      final content = message['content'] as String? ?? '';
      final reasoning = message['reasoning_content'] as String?;
      return (content: content, reasoning: reasoning);
    } else {
      throw Exception(
          'API 请求失败: ${response.statusCode} ${response.body}');
    }
  }

  Stream<StreamChunk> _sendOpenAICompatibleStreamRequest(
    ModelConfig config,
    List<Map<String, String>> messages, {
    bool thinking = false,
  }) async* {
    final uri = Uri.parse('${config.endpoint}/chat/completions');

    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': messages,
      'stream': true,
      if (config.maxTokens != null) 'max_tokens': config.maxTokens,
      if (config.temperature != null) 'temperature': config.temperature,
      if (config.topP != null) 'top_p': config.topP,
      if (!thinking) ..._thinkingDisabledParams(),
      ...config.extraParams,
    };

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (config.apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.apiKey}';
    }

    final request = http.Request('POST', uri);
    request.headers.addAll(headers);
    request.body = jsonEncode(body);

    final client = http.Client();
    try {
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception('流式请求失败: ${streamedResponse.statusCode} $errorBody');
      }

      await for (final chunk in streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (chunk.startsWith('data: ')) {
          final data = chunk.substring(6);
          if (data == '[DONE]') {
            yield StreamChunk(isDone: true);
            break;
          }
          try {
            final json = jsonDecode(data);
            final choice = json['choices']?[0];
            if (choice != null) {
              final delta = choice['delta'];
              final content = delta?['content'] as String?;
              final reasoning = delta?['reasoning_content'] as String?;
              if (content != null || reasoning != null) {
                yield StreamChunk(
                  content: content,
                  reasoningContent: reasoning,
                );
              }
            }
            final finishReason = choice?['finish_reason'];
            if (finishReason != null && finishReason != '') {
              yield StreamChunk(isDone: true);
              break;
            }
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
  }

  Future<({String content, String? reasoning})> _sendOllamaRequest(
    ModelConfig config,
    List<Map<String, String>> messages, {
    bool thinking = false,
  }) async {
    final uri = Uri.parse('${config.endpoint}/api/chat');

    final ollamaMessages = messages.map((m) {
      return {'role': m['role'], 'content': m['content']};
    }).toList();

    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': ollamaMessages,
      'stream': false,
    };

    if (config.temperature != null || config.topP != null) {
      body['options'] = {
        if (config.temperature != null) 'temperature': config.temperature,
        if (config.topP != null) 'top_p': config.topP,
        if (config.maxTokens != null) 'num_predict': config.maxTokens,
      };
    }

    body.addAll(config.extraParams);

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final content = data['message']['content'] as String? ?? '';
      return (content: content, reasoning: null);
    } else {
      throw Exception(
          'Ollama 请求失败: ${response.statusCode} ${response.body}');
    }
  }

  Stream<StreamChunk> _sendOllamaStreamRequest(
    ModelConfig config,
    List<Map<String, String>> messages, {
    bool thinking = false,
  }) async* {
    final uri = Uri.parse('${config.endpoint}/api/chat');

    final ollamaMessages = messages.map((m) {
      return {'role': m['role'], 'content': m['content']};
    }).toList();

    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': ollamaMessages,
      'stream': true,
    };

    if (config.temperature != null || config.topP != null) {
      body['options'] = {
        if (config.temperature != null) 'temperature': config.temperature,
        if (config.topP != null) 'top_p': config.topP,
        if (config.maxTokens != null) 'num_predict': config.maxTokens,
      };
    }

    body.addAll(config.extraParams);

    final request = http.Request('POST', uri);
    request.headers.addAll({'Content-Type': 'application/json'});
    request.body = jsonEncode(body);

    final client = http.Client();
    try {
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception('Ollama 流式请求失败: ${streamedResponse.statusCode} $errorBody');
      }

      await for (final chunk in streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (chunk.trim().isEmpty) continue;
        try {
          final json = jsonDecode(chunk);
          final content = json['message']?['content'] as String?;
          final done = json['done'] as bool? ?? false;
          if (content != null) {
            yield StreamChunk(content: content);
          }
          if (done) {
            yield StreamChunk(isDone: true);
            break;
          }
        } catch (_) {}
      }
    } finally {
      client.close();
    }
  }

  Future<({String content, String? reasoning})> _sendAnthropicRequest(
    ModelConfig config,
    List<Map<String, String>> messages, {
    bool thinking = false,
  }) async {
    final uri = Uri.parse('${config.endpoint}/messages');

    final anthropicMessages = <Map<String, dynamic>>[];
    String? systemPrompt;

    for (final m in messages) {
      if (m['role'] == 'system') {
        systemPrompt = m['content'];
      } else {
        anthropicMessages.add({
          'role': m['role'],
          'content': m['content'],
        });
      }
    }

    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': anthropicMessages,
      'max_tokens': config.maxTokens ?? 4096,
      if (systemPrompt != null) 'system': systemPrompt,
      if (config.temperature != null) 'temperature': config.temperature,
      if (config.topP != null) 'top_p': config.topP,
      if (!thinking) ..._thinkingDisabledParams(),
      ...config.extraParams,
    };

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': config.apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      String content = '';
      for (final block in data['content'] ?? []) {
        if (block['type'] == 'text') {
          content += block['text'] as String;
        }
      }
      return (content: content, reasoning: null);
    } else {
      throw Exception(
          'Anthropic 请求失败: ${response.statusCode} ${response.body}');
    }
  }
}
