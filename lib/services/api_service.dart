import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/model_config.dart';
import 'tool_call_service.dart';

class ChatImageInput {
  final Uint8List bytes;
  final String mimeType;

  ChatImageInput({required this.bytes, required this.mimeType});
}

class StreamChunk {
  final String? content;
  final String? reasoningContent;
  final bool isDone;

  StreamChunk({this.content, this.reasoningContent, this.isDone = false});
}

class ChatResponse {
  final String content;
  final String? reasoning;
  final List<ChatToolCall> toolCalls;

  const ChatResponse({
    required this.content,
    this.reasoning,
    this.toolCalls = const [],
  });
}

class ApiService {
  static const _timeout = Duration(seconds: 60);
  static const _streamTimeout = Duration(minutes: 10);
  static const _speechSliceSize = 5 * 1024 * 1024;

  Uri _endpointUri(ModelConfig config, String path) {
    final endpoint = config.endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    if (endpoint.isEmpty) {
      throw Exception('API Endpoint 不能为空');
    }
    return Uri.parse('$endpoint$path');
  }

  Future<String> recognizeImageText(
    ModelConfig config,
    Uint8List imageBytes,
  ) async {
    final appId = config.extraParams['appId'] as String? ?? '';
    if (appId.isEmpty) throw Exception('OCR 配置缺少 AppID');
    final uri = Uri.parse(config.endpoint).replace(
      queryParameters: {
        'requestId': DateTime.now().microsecondsSinceEpoch.toString(),
      },
    );
    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer ${config.apiKey}',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'image': base64Encode(imageBytes),
            'pos': '2',
            'businessid': 'aigc$appId',
          },
        )
        .timeout(_timeout);
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode != 200 || data['error_code'] != 0) {
      throw Exception('OCR 识别失败: ${response.statusCode} ${response.body}');
    }
    return _extractOcrText(data);
  }

  Future<String> recognizeImageTextWithChatModel(
    ModelConfig config,
    String prompt,
    List<ChatImageInput> images,
  ) async {
    if (images.isEmpty) return '';
    if (config.apiType == 'ollama') {
      return _recognizeImageTextWithOllama(config, prompt, images);
    }

    final messages = [
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': prompt},
          ...images.map(
            (image) => {
              'type': 'image_url',
              'image_url': {
                'url':
                    'data:${image.mimeType};base64,${base64Encode(image.bytes)}',
              },
            },
          ),
        ],
      },
    ];

    if (config.apiType == 'anthropic') {
      final result = await _sendAnthropicRequest(config, messages);
      return result.content.trim();
    }

    final result = await _sendOpenAICompatibleRequest(config, messages);
    return result.content.trim();
  }

  Future<String> _recognizeImageTextWithOllama(
    ModelConfig config,
    String prompt,
    List<ChatImageInput> images,
  ) async {
    final uri = _endpointUri(config, '/api/chat');
    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': [
        {
          'role': 'user',
          'content': prompt,
          'images': images.map((e) => base64Encode(e.bytes)).toList(),
        },
      ],
      'stream': false,
    };
    if (config.maxTokens != null ||
        config.temperature != null ||
        config.topP != null) {
      body['options'] = {
        if (config.maxTokens != null) 'num_predict': config.maxTokens,
        if (config.temperature != null) 'temperature': config.temperature,
        if (config.topP != null) 'top_p': config.topP,
      };
    }
    for (final entry in config.extraParams.entries) {
      if (!body.containsKey(entry.key)) {
        body[entry.key] = entry.value;
      }
    }

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(
          _timeout,
          onTimeout: () {
            throw TimeoutException('连接超时，请检查 Ollama 服务是否运行');
          },
        );

    if (response.statusCode != 200) {
      throw Exception('Ollama 图片识别失败: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rawContent = data['message']?['content'] as String? ?? '';
    final thinkMatch = RegExp(
      r'<think[^>]*>(.*?)</think>',
      dotAll: true,
    ).firstMatch(rawContent);
    return (thinkMatch?.group(1) ?? rawContent)
        .replaceAll(RegExp(r'<think[^>]*>.*?</think>', dotAll: true), '')
        .trim();
  }

  Future<String> transcribeAudio(
    ModelConfig config,
    Uint8List audioBytes, {
    String audioType = 'auto',
  }) async {
    final endpoint = config.endpoint.replaceAll(RegExp(r'/+$'), '');
    final sessionId = DateTime.now().microsecondsSinceEpoch.toString();
    final sliceCount = math.max(
      1,
      (audioBytes.length / _speechSliceSize).ceil(),
    );
    final commonQuery = _speechCommonQuery(config);

    final create = await _speechPostJson(
      Uri.parse('$endpoint/lasr/create').replace(queryParameters: commonQuery),
      config,
      {
        'audio_type': audioType,
        'x-sessionId': sessionId,
        'slice_num': sliceCount,
      },
    );
    final audioId = create['data']?['audio_id'] as String?;
    if (audioId == null || audioId.isEmpty) {
      throw Exception('创建音频失败: ${jsonEncode(create)}');
    }

    for (var i = 0; i < sliceCount; i++) {
      final start = i * _speechSliceSize;
      final end = math.min(start + _speechSliceSize, audioBytes.length);
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$endpoint/lasr/upload').replace(
          queryParameters: {
            ...commonQuery,
            'audio_id': audioId,
            'x-sessionId': sessionId,
            'slice_index': '$i',
          },
        ),
      );
      request.headers['Authorization'] = 'Bearer ${config.apiKey}';
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          audioBytes.sublist(start, end),
          filename: 'audio.part',
        ),
      );
      final streamed = await request.send().timeout(_timeout);
      final body = await streamed.stream.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (streamed.statusCode != 200 || data['code'] != 0) {
        throw Exception('上传音频分片失败: ${streamed.statusCode} $body');
      }
    }

    final run = await _speechPostJson(
      Uri.parse('$endpoint/lasr/run').replace(queryParameters: commonQuery),
      config,
      {'audio_id': audioId, 'x-sessionId': sessionId},
    );
    final taskId = run['data']?['task_id'] as String?;
    if (taskId == null || taskId.isEmpty) {
      throw Exception('创建转写任务失败: ${jsonEncode(run)}');
    }

    for (var i = 0; i < 120; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final progress = await _speechPostJson(
        Uri.parse(
          '$endpoint/lasr/progress',
        ).replace(queryParameters: commonQuery),
        config,
        {'task_id': taskId, 'x-sessionId': sessionId},
      );
      if ((progress['data']?['progress'] as num? ?? 0) >= 100) break;
      if (i == 119) {
        throw Exception('语音转写超时');
      }
    }

    final result = await _speechPostJson(
      Uri.parse('$endpoint/lasr/result').replace(queryParameters: commonQuery),
      config,
      {'task_id': taskId, 'x-sessionId': sessionId},
    );
    final items = result['data']?['result'] as List? ?? [];
    return items
        .map((e) => (e as Map)['onebest'] as String? ?? '')
        .where((e) => e.isNotEmpty)
        .join();
  }

  Future<List<String>> generateImages(
    ModelConfig config,
    String prompt, {
    Object? image,
    Map<String, dynamic>? parameters,
  }) async {
    if (config.apiType == 'vivo_image') {
      return _generateVivoImages(
        config,
        prompt,
        image: image,
        parameters: parameters,
      );
    }
    return _generateOpenAIImages(config, prompt, parameters: parameters);
  }

  Future<List<String>> _generateOpenAIImages(
    ModelConfig config,
    String prompt, {
    Map<String, dynamic>? parameters,
  }) async {
    final endpoint = config.endpoint.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$endpoint/images/generations');
    final body = <String, dynamic>{'model': config.modelName, 'prompt': prompt};
    if (parameters != null && parameters.isNotEmpty) {
      body.addAll(parameters);
    }
    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer ${config.apiKey}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception('图片生成失败: ${response.statusCode} ${response.body}');
    }
    final images = data['data'] as List? ?? [];
    return images
        .map((e) {
          final item = e as Map;
          return item['url'] as String? ?? item['b64_json'] as String? ?? '';
        })
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<List<String>> _generateVivoImages(
    ModelConfig config,
    String prompt, {
    Object? image,
    Map<String, dynamic>? parameters,
  }) async {
    final uri = Uri.parse(config.endpoint).replace(
      queryParameters: {
        'module': 'aigc',
        'request_id': DateTime.now().microsecondsSinceEpoch.toString(),
        'system_time': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      },
    );
    final body = <String, dynamic>{'model': config.modelName, 'prompt': prompt};
    if (image != null) {
      body['image'] = image;
    }
    if (parameters != null && parameters.isNotEmpty) {
      body['parameters'] = parameters;
    }
    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer ${config.apiKey}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode != 200 || data['code'] != 0) {
      throw Exception('图片生成失败: ${response.statusCode} ${response.body}');
    }
    final images = data['data']?['images'] as List? ?? [];
    return images
        .map((e) => (e as Map)['url'] as String? ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Map<String, String> _speechCommonQuery(ModelConfig config) {
    final appId = config.extraParams['appId'] as String? ?? '';
    if (appId.isEmpty) {
      throw Exception('语音转文字配置缺少 AppID');
    }
    // vivo 长语音转写要求每个阶段都携带同一组公共 URL 参数。
    // user_id 只要求 32 位小写字母/数字；这里基于 AppID 派生稳定值，避免再让
    // 用户额外维护一个无业务含义的字段。
    return {
      'client_version': '1.0.0',
      'package': 'lynai',
      'user_id': appId.padRight(32, '0').substring(0, 32).toLowerCase(),
      'system_time': '${DateTime.now().millisecondsSinceEpoch}',
      'engineid': config.modelName,
      'requestId': DateTime.now().microsecondsSinceEpoch.toString(),
    };
  }

  Future<Map<String, dynamic>> _speechPostJson(
    Uri uri,
    ModelConfig config,
    Map<String, dynamic> body,
  ) async {
    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer ${config.apiKey}',
            'Content-Type': 'application/json; charset=UTF-8',
          },
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode != 200 || data['code'] != 0) {
      throw Exception('${response.statusCode} ${response.body}');
    }
    return data;
  }

  String _extractOcrText(Map<String, dynamic> data) {
    final result = data['result'] as Map<String, dynamic>?;
    if (result == null) return '';
    final ocr = result['OCR'] as List?;
    if (ocr != null) {
      return ocr
          .map((e) => (e as Map)['words'] as String? ?? '')
          .where((e) => e.isNotEmpty)
          .join('\n');
    }
    final words = result['words'] as List?;
    if (words != null) {
      return words
          .map((e) => (e as Map)['words'] as String? ?? '')
          .where((e) => e.isNotEmpty)
          .join('\n');
    }
    return '';
  }

  Future<ChatResponse> sendChatRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
    List<Map<String, dynamic>> tools = const [],
    String? toolChoice,
  }) async {
    try {
      if (config.apiType == 'ollama') {
        return await _sendOllamaRequest(
          config,
          messages,
          thinking: thinking,
        ).timeout(_timeout);
      } else if (config.apiType == 'anthropic') {
        return await _sendAnthropicRequest(
          config,
          messages,
          thinking: thinking,
        ).timeout(_timeout);
      } else {
        return await _sendOpenAICompatibleRequest(
          config,
          messages,
          thinking: thinking,
          tools: tools,
          toolChoice: toolChoice,
        ).timeout(_timeout);
      }
    } on TimeoutException {
      throw Exception('请求超时，请检查网络连接或稍后重试');
    } catch (e) {
      throw Exception('API 请求异常: $e');
    }
  }

  Stream<StreamChunk> sendStreamRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
  }) async* {
    try {
      if (config.apiType == 'ollama') {
        yield* _sendOllamaStreamRequest(config, messages, thinking: thinking);
      } else if (config.apiType == 'anthropic') {
        yield* _sendAnthropicStreamRequest(
          config,
          messages,
          thinking: thinking,
        );
      } else {
        yield* _sendOpenAICompatibleStreamRequest(
          config,
          messages,
          thinking: thinking,
        );
      }
    } catch (e) {
      throw Exception('流式请求异常: $e');
    }
  }

  Future<ChatResponse> _sendOpenAICompatibleRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
    List<Map<String, dynamic>> tools = const [],
    String? toolChoice,
  }) async {
    final uri = _endpointUri(config, '/chat/completions');

    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': _withReasoningPlaceholders(messages, thinking: thinking),
      'stream': false,
      if (config.maxTokens != null) 'max_tokens': config.maxTokens,
      if (config.temperature != null) 'temperature': config.temperature,
      if (config.topP != null) 'top_p': config.topP,
      'thinking': {'type': thinking ? 'enabled' : 'disabled'},
      if (tools.isNotEmpty) 'tools': tools,
      if (tools.isNotEmpty) 'tool_choice': toolChoice ?? 'auto',
    };
    for (final entry in config.extraParams.entries) {
      if (!body.containsKey(entry.key)) {
        body[entry.key] = entry.value;
      }
    }

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (config.apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.apiKey}';
    }

    final response = await http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(
          _timeout,
          onTimeout: () {
            throw TimeoutException('连接超时，请检查 API 地址是否正确');
          },
        );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw Exception('API 返回空的 choices');
      }
      final choice = choices[0];
      final message = choice['message'];
      if (message == null) {
        throw Exception('API 返回的 choice 缺少 message');
      }
      final content = message['content'] as String? ?? '';
      final reasoning = message['reasoning_content'] as String?;
      return ChatResponse(
        content: content,
        reasoning: reasoning,
        toolCalls: _parseOpenAIToolCalls(message),
      );
    } else {
      throw Exception('API 请求失败: ${response.statusCode} ${response.body}');
    }
  }

  Stream<StreamChunk> _sendOpenAICompatibleStreamRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
  }) async* {
    final uri = _endpointUri(config, '/chat/completions');

    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': _withReasoningPlaceholders(messages, thinking: thinking),
      'stream': true,
      if (config.maxTokens != null) 'max_tokens': config.maxTokens,
      if (config.temperature != null) 'temperature': config.temperature,
      if (config.topP != null) 'top_p': config.topP,
      'thinking': {'type': thinking ? 'enabled' : 'disabled'},
    };
    for (final entry in config.extraParams.entries) {
      if (!body.containsKey(entry.key)) {
        body[entry.key] = entry.value;
      }
    }

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (config.apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.apiKey}';
    }

    final request = http.Request('POST', uri);
    request.headers.addAll(headers);
    request.body = jsonEncode(body);

    final client = http.Client();
    try {
      final streamedResponse = await client.send(request).timeout(_timeout);

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception('流式请求失败: ${streamedResponse.statusCode} $errorBody');
      }

      await for (final chunk
          in streamedResponse.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .timeout(_streamTimeout)) {
        if (chunk.startsWith('data:')) {
          final data = chunk.substring(5).trim();
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
          } catch (e) {
            // malformed chunk, skip
          }
        }
      }
    } finally {
      client.close();
    }
  }

  Future<ChatResponse> _sendOllamaRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
  }) async {
    final uri = _endpointUri(config, '/api/chat');

    final ollamaMessages = messages.map((m) {
      final c = m['content'];
      return {'role': m['role'], 'content': c is String ? c : jsonEncode(c)};
    }).toList();

    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': ollamaMessages,
      'stream': false,
      'think': thinking,
    };

    if (config.maxTokens != null ||
        config.temperature != null ||
        config.topP != null) {
      body['options'] = {
        if (config.maxTokens != null) 'num_predict': config.maxTokens,
        if (config.temperature != null) 'temperature': config.temperature,
        if (config.topP != null) 'top_p': config.topP,
      };
    }

    for (final entry in config.extraParams.entries) {
      if (!body.containsKey(entry.key)) {
        body[entry.key] = entry.value;
      }
    }

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(
          _timeout,
          onTimeout: () {
            throw TimeoutException('连接超时，请检查 Ollama 服务是否运行');
          },
        );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final rawContent = data['message']['content'] as String? ?? '';
      final thinkMatch = RegExp(
        r'<think[^>]*>(.*?)</think>',
        dotAll: true,
      ).firstMatch(rawContent);
      final reasoning = thinkMatch?.group(1)?.trim();
      final content = rawContent
          .replaceAll(RegExp(r'<think[^>]*>.*?</think>', dotAll: true), '')
          .trim();
      return ChatResponse(content: content, reasoning: reasoning);
    } else {
      throw Exception('Ollama 请求失败: ${response.statusCode} ${response.body}');
    }
  }

  Stream<StreamChunk> _sendOllamaStreamRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
  }) async* {
    final uri = _endpointUri(config, '/api/chat');

    final ollamaMessages = messages.map((m) {
      final c = m['content'];
      return {'role': m['role'], 'content': c is String ? c : jsonEncode(c)};
    }).toList();

    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': ollamaMessages,
      'stream': true,
      'think': thinking,
    };

    if (config.maxTokens != null ||
        config.temperature != null ||
        config.topP != null) {
      body['options'] = {
        if (config.maxTokens != null) 'num_predict': config.maxTokens,
        if (config.temperature != null) 'temperature': config.temperature,
        if (config.topP != null) 'top_p': config.topP,
      };
    }

    for (final entry in config.extraParams.entries) {
      if (!body.containsKey(entry.key)) {
        body[entry.key] = entry.value;
      }
    }

    final request = http.Request('POST', uri);
    request.headers.addAll({'Content-Type': 'application/json'});
    request.body = jsonEncode(body);

    final client = http.Client();
    try {
      final streamedResponse = await client.send(request).timeout(_timeout);

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception(
          'Ollama 流式请求失败: ${streamedResponse.statusCode} $errorBody',
        );
      }

      final thinkRegExp = RegExp(r'<think[^>]*>(.*?)</think>', dotAll: true);
      String ollamaBuf = '';

      List<StreamChunk> processBuffer() {
        final result = <StreamChunk>[];
        if (ollamaBuf.isEmpty) return result;
        final openStart = ollamaBuf.lastIndexOf(
          RegExp(r'<th(?:i(?:n(?:k(?:[^>]*)?)?)?)?$'),
        );
        final closeStart = ollamaBuf.lastIndexOf(
          RegExp(r'</(?:t(?:h(?:i(?:n(?:k)?)?)?)?)?$'),
        );
        final lastCompleteThink = ollamaBuf.lastIndexOf('</think>');
        int cutoff = ollamaBuf.length;
        if (openStart != -1 &&
            openStart >= ollamaBuf.length - 7 &&
            openStart > lastCompleteThink) {
          final lastFullThinkOpen = ollamaBuf.lastIndexOf(
            RegExp(r'<think[^>]*>'),
            openStart,
          );
          if (lastFullThinkOpen == -1 ||
              ollamaBuf.indexOf('</think>', lastFullThinkOpen) == -1) {
            cutoff = openStart;
          }
        }
        if (cutoff == ollamaBuf.length &&
            closeStart != -1 &&
            closeStart > lastCompleteThink) {
          cutoff = closeStart;
        }
        final process = ollamaBuf.substring(0, cutoff);
        ollamaBuf = ollamaBuf.substring(cutoff);

        int lastEnd = 0;
        for (final match in thinkRegExp.allMatches(process)) {
          if (match.start > lastEnd) {
            final plain = process.substring(lastEnd, match.start).trim();
            if (plain.isNotEmpty) result.add(StreamChunk(content: plain));
          }
          final thinkContent = match.group(1)?.trim();
          if (thinkContent != null && thinkContent.isNotEmpty) {
            result.add(StreamChunk(reasoningContent: thinkContent));
          }
          lastEnd = match.end;
        }
        if (lastEnd < process.length) {
          final plain = process.substring(lastEnd).trim();
          if (plain.isNotEmpty) result.add(StreamChunk(content: plain));
        }
        return result;
      }

      await for (final chunk
          in streamedResponse.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .timeout(_streamTimeout)) {
        if (chunk.trim().isEmpty) continue;
        try {
          final json = jsonDecode(chunk);
          final rawContent = json['message']?['content'] as String?;
          final done = json['done'] as bool? ?? false;
          if (rawContent != null) {
            ollamaBuf += rawContent;
            for (final c in processBuffer()) {
              yield c;
            }
          }
          if (done) {
            if (ollamaBuf.isNotEmpty) {
              final plain = ollamaBuf.trim();
              if (plain.isNotEmpty) yield StreamChunk(content: plain);
            }
            yield StreamChunk(isDone: true);
            break;
          }
        } catch (_) {}
      }
    } finally {
      client.close();
    }
  }

  Stream<StreamChunk> _sendAnthropicStreamRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
  }) async* {
    final uri = _endpointUri(config, '/messages');

    final anthropicMessages = <Map<String, dynamic>>[];
    String? systemPrompt;

    for (final m in messages) {
      if (m['role'] == 'system') {
        systemPrompt = m['content'] as String;
      } else {
        anthropicMessages.add({'role': m['role'], 'content': m['content']});
      }
    }

    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': anthropicMessages,
      'max_tokens': config.maxTokens ?? 4096,
      'stream': true,
      // ignore: use_null_aware_elements
      if (systemPrompt != null) 'system': systemPrompt,
      if (config.temperature != null) 'temperature': config.temperature,
      if (config.topP != null) 'top_p': config.topP,
    };
    for (final entry in config.extraParams.entries) {
      if (!body.containsKey(entry.key)) {
        body[entry.key] = entry.value;
      }
    }

    final request = http.Request('POST', uri);
    request.headers.addAll({
      'Content-Type': 'application/json',
      'x-api-key': config.apiKey,
      'anthropic-version': '2023-06-01',
    });
    request.body = jsonEncode(body);

    final client = http.Client();
    try {
      final streamedResponse = await client.send(request).timeout(_timeout);

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception(
          'Anthropic 流式请求失败: ${streamedResponse.statusCode} $errorBody',
        );
      }

      await for (final chunk
          in streamedResponse.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .timeout(_streamTimeout)) {
        // Anthropic SSE format: "event: <type>\ndata: <json>"
        if (chunk.startsWith('data:')) {
          final data = chunk.substring(5).trim();
          try {
            final json = jsonDecode(data);
            final type = json['type'] as String?;

            if (type == 'content_block_delta') {
              final delta = json['delta'];
              if (delta != null) {
                final deltaType = delta['type'] as String?;
                if (deltaType == 'text_delta') {
                  yield StreamChunk(content: delta['text'] as String?);
                } else if (deltaType == 'thinking_delta') {
                  yield StreamChunk(
                    reasoningContent: delta['thinking'] as String?,
                  );
                }
              }
            } else if (type == 'message_stop') {
              yield StreamChunk(isDone: true);
              break;
            }
          } catch (_) {
            // malformed chunk, skip
          }
        }
      }
    } finally {
      client.close();
    }
  }

  Future<ChatResponse> _sendAnthropicRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
  }) async {
    final uri = _endpointUri(config, '/messages');

    final anthropicMessages = <Map<String, dynamic>>[];
    String? systemPrompt;

    for (final m in messages) {
      if (m['role'] == 'system') {
        systemPrompt = m['content'] as String;
      } else {
        anthropicMessages.add({'role': m['role'], 'content': m['content']});
      }
    }

    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': anthropicMessages,
      'max_tokens': config.maxTokens ?? 4096,
      'stream': false,
      // ignore: use_null_aware_elements
      if (systemPrompt != null) 'system': systemPrompt,
      if (config.temperature != null) 'temperature': config.temperature,
      if (config.topP != null) 'top_p': config.topP,
    };
    for (final entry in config.extraParams.entries) {
      if (!body.containsKey(entry.key)) {
        body[entry.key] = entry.value;
      }
    }

    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': config.apiKey,
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode(body),
        )
        .timeout(
          _timeout,
          onTimeout: () {
            throw TimeoutException('连接超时，请检查 Anthropic API 配置');
          },
        );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      String content = '';
      String reasoning = '';
      for (final block in data['content'] ?? []) {
        if (block['type'] == 'text') {
          content += block['text'] as String;
        } else if (block['type'] == 'thinking') {
          reasoning += block['thinking'] as String? ?? '';
        }
      }
      return ChatResponse(
        content: content,
        reasoning: reasoning.isNotEmpty ? reasoning : null,
      );
    } else {
      throw Exception(
        'Anthropic 请求失败: ${response.statusCode} ${response.body}',
      );
    }
  }

  List<ChatToolCall> _parseOpenAIToolCalls(dynamic message) {
    final rawCalls = message is Map ? message['tool_calls'] : null;
    if (rawCalls is! List) return const [];
    final calls = <ChatToolCall>[];
    for (final raw in rawCalls) {
      if (raw is! Map) continue;
      final function = raw['function'];
      if (function is! Map) continue;
      final name = function['name'] as String? ?? '';
      if (name.isEmpty) continue;
      final rawArgs = function['arguments'];
      Map<String, dynamic> args = {};
      if (rawArgs is String && rawArgs.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawArgs);
          if (decoded is Map<String, dynamic>) args = decoded;
        } catch (_) {}
      } else if (rawArgs is Map<String, dynamic>) {
        args = rawArgs;
      }
      calls.add(
        ChatToolCall(
          id: raw['id'] as String? ?? 'call_${calls.length}',
          name: name,
          arguments: args,
        ),
      );
    }
    return calls;
  }

  List<Map<String, dynamic>> _withReasoningPlaceholders(
    List<Map<String, dynamic>> messages, {
    required bool thinking,
  }) {
    if (!thinking) return messages;
    return messages.map((message) {
      if (message['role'] != 'assistant' ||
          message.containsKey('reasoning_content')) {
        return message;
      }
      return {...message, 'reasoning_content': null};
    }).toList();
  }
}
