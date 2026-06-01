import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/model_config.dart';
import 'tool_call_service.dart';

/// 发送给模型前的附件输入。
///
/// 页面层负责把用户选择的文件复制到应用私有目录；服务层只接收文件字节、
/// MIME 类型和展示名称，并按不同协议转换为多模态内容或文本上下文。
class ChatFileInput {
  final Uint8List bytes;
  final String mimeType;
  final String name;

  ChatFileInput({
    required this.bytes,
    required this.mimeType,
    required this.name,
  });

  bool get isImage => mimeType.startsWith('image/');
}

/// 流式聊天中的一个标准化增量。
///
/// 不同供应商的 SSE/JSON 行格式在这里被统一成正文、思考内容、工具调用
/// 和结束信号，页面层不需要关心底层协议差异。
class StreamChunk {
  final String? content;
  final String? reasoningContent;
  final List<ChatToolCall> toolCalls;
  final bool isDone;

  const StreamChunk({
    this.content,
    this.reasoningContent,
    this.toolCalls = const [],
    this.isDone = false,
  });
}

/// 非流式聊天响应。
///
/// 主要用于工具调用后的二次请求，或不需要逐字刷新的接口调用。
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

/// 封装外部模型接口、OCR、语音转写、图片生成和附件转换。
///
/// 服务层只处理协议和数据转换，不保存应用状态。调用者负责选择模型、
/// 构建上下文、处理取消和把结果写回 Provider。
class ApiService {
  static const _timeout = Duration(minutes: 5);
  static const _streamTimeout = Duration(minutes: 30);
  static const _speechSliceSize = 5 * 1024 * 1024;

  http.Client? _client;
  http.Client get client => _client ??= http.Client();

  void dispose() {
    _client?.close();
    _client = null;
  }

  Uri _endpointUri(ModelConfig config, String path) {
    final endpoint = config.endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    if (endpoint.isEmpty) {
      throw Exception('API Endpoint 不能为空');
    }
    return Uri.parse('$endpoint$path');
  }

  static String _truncateErrorBody(String body) {
    if (body.length <= 200) return body;
    return '${body.substring(0, 200)}...';
  }

  static List<Map<String, dynamic>> chatContentWithFiles(
    String text,
    List<ChatFileInput> files,
  ) {
    return [
      if (text.trim().isNotEmpty) {'type': 'text', 'text': text.trim()},
      ...files.map((file) {
        final data = base64Encode(file.bytes);
        return {
          'type': 'input_file',
          'name': file.name,
          'mime_type': file.mimeType,
          'data': data,
        };
      }),
    ];
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
    List<ChatFileInput> files,
  ) async {
    if (files.isEmpty) return '';
    if (config.apiType == 'ollama') {
      return _recognizeImageTextWithOllama(config, prompt, files);
    }

    if (config.apiType == 'anthropic') {
      final result = await _sendAnthropicRequest(config, [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            ...files.map(_anthropicFileContentPart),
          ],
        },
      ]);
      return result.content.trim();
    }

    final messages = [
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': prompt},
          ..._openAIContentToChatContent(
            chatContentWithFiles('', files).where((part) {
              return part['type'] == 'input_file';
            }).toList(),
          ),
        ],
      },
    ];

    final result = await _sendOpenAICompatibleRequest(config, messages);
    return result.content.trim();
  }

  Future<String> _recognizeImageTextWithOllama(
    ModelConfig config,
    String prompt,
    List<ChatFileInput> files,
  ) async {
    final images = files.where((e) => e.isImage).toList();
    final nonImages = files.where((e) => !e.isImage).toList();
    final filePrompt = nonImages.isEmpty
        ? prompt
        : '$prompt\n\n附件文件：\n${nonImages.map((file) => '${file.name} (${file.mimeType}) base64: ${base64Encode(file.bytes)}').join('\n')}';
    final uri = _endpointUri(config, '/api/chat');
    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': [
        {
          'role': 'user',
          'content': filePrompt,
          'images': images.map((e) => base64Encode(e.bytes)).toList(),
        },
      ],
      'stream': false,
    };
    if (config.effectiveMaxTokens != null ||
        config.effectiveTemperature != null ||
        config.effectiveTopP != null) {
      body['options'] = {
        if (config.effectiveMaxTokens != null)
          'num_predict': config.effectiveMaxTokens,
        if (config.effectiveTemperature != null)
          'temperature': config.effectiveTemperature,
        if (config.effectiveTopP != null) 'top_p': config.effectiveTopP,
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
      throw Exception('Ollama 文件识别失败: ${response.statusCode} ${response.body}');
    }

    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final rawContent = data['message']?['content'] as String? ?? '';
    return rawContent
        .replaceAll(RegExp(r'<think[^>]*>.*?</think>', dotAll: true), '')
        .trim();
  }

  Map<String, dynamic> _anthropicFileContentPart(ChatFileInput file) {
    final base64 = base64Encode(file.bytes);
    if (file.isImage) {
      return {
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': file.mimeType,
          'data': base64,
        },
      };
    }
    return {
      'type': 'text',
      'text':
          '[文件: ${file.name} (${file.mimeType})]\ndata:${file.mimeType};base64,$base64',
    };
  }

  List<Map<String, dynamic>> _openAICompatibleMessages(
    List<Map<String, dynamic>> messages,
  ) {
    return openAICompatibleMessagesForTest(messages);
  }

  static List<Map<String, dynamic>> openAICompatibleMessagesForTest(
    List<Map<String, dynamic>> messages,
  ) {
    return messages.map((message) {
      final content = message['content'];
      if (content is! List) return message;
      return {...message, 'content': _openAIContentToChatContent(content)};
    }).toList();
  }

  List<Map<String, dynamic>> _ollamaMessages(
    List<Map<String, dynamic>> messages,
  ) {
    return messages.map((m) {
      final c = m['content'];
      if (c is! List) {
        return {'role': m['role'], 'content': c is String ? c : jsonEncode(c)};
      }
      final textParts = <String>[];
      final images = <String>[];
      for (final part in c) {
        if (part is! Map) continue;
        if (part['type'] == 'text') {
          final text = part['text'] as String? ?? '';
          if (text.isNotEmpty) textParts.add(text);
        } else if (part['type'] == 'input_file') {
          final mimeType =
              part['mime_type'] as String? ?? 'application/octet-stream';
          final data = part['data'] as String? ?? '';
          final name = part['name'] as String? ?? 'file';
          if (mimeType.startsWith('image/')) {
            images.add(data);
          } else {
            textParts.add(
              '[文件: $name ($mimeType)]\ndata:$mimeType;base64,$data',
            );
          }
        }
      }
      return {
        'role': m['role'],
        'content': textParts.join('\n\n'),
        if (images.isNotEmpty) 'images': images,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _anthropicMessages(
    List<Map<String, dynamic>> messages,
  ) {
    return messages.map((message) {
      final content = message['content'];
      if (content is! List) return message;
      return {
        'role': message['role'],
        'content': content.map((part) {
          if (part is! Map || part['type'] != 'input_file') return part;
          final mimeType =
              part['mime_type'] as String? ?? 'application/octet-stream';
          final data = part['data'] as String? ?? '';
          final name = part['name'] as String? ?? 'file';
          if (mimeType.startsWith('image/')) {
            return {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': mimeType,
                'data': data,
              },
            };
          }
          return {
            'type': 'text',
            'text': '[文件: $name ($mimeType)]\ndata:$mimeType;base64,$data',
          };
        }).toList(),
      };
    }).toList();
  }

  static List<Map<String, dynamic>> _openAIContentToChatContent(List content) {
    return content.map<Map<String, dynamic>>((part) {
      if (part is! Map || part['type'] != 'input_file') return part;
      final mimeType =
          part['mime_type'] as String? ?? 'application/octet-stream';
      final data = part['data'] as String? ?? '';
      final name = part['name'] as String? ?? 'file';
      if (mimeType.startsWith('image/')) {
        return {
          'type': 'image_url',
          'image_url': {'url': 'data:$mimeType;base64,$data'},
        };
      }
      return {
        'type': 'text',
        'text': '[文件: $name ($mimeType)]\ndata:$mimeType;base64,$data',
      };
    }).toList();
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
          _ollamaMessages(messages),
          thinking: thinking,
        ).timeout(_timeout);
      } else if (config.apiType == 'anthropic') {
        return await _sendAnthropicRequest(
          config,
          _anthropicMessages(messages),
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
    List<Map<String, dynamic>> tools = const [],
    String? toolChoice,
  }) async* {
    try {
      if (config.apiType == 'ollama') {
        yield* _sendOllamaStreamRequest(
          config,
          _ollamaMessages(messages),
          thinking: thinking,
        );
      } else if (config.apiType == 'anthropic') {
        yield* _sendAnthropicStreamRequest(
          config,
          _anthropicMessages(messages),
          thinking: thinking,
        );
      } else {
        yield* _sendOpenAICompatibleStreamRequest(
          config,
          messages,
          thinking: thinking,
          tools: tools,
          toolChoice: toolChoice,
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
      'messages': _openAICompatibleMessages(messages),
      'stream': false,
      if (config.effectiveMaxTokens != null)
        'max_tokens': config.effectiveMaxTokens,
      if (config.effectiveTemperature != null)
        'temperature': config.effectiveTemperature,
      if (config.effectiveTopP != null) 'top_p': config.effectiveTopP,
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
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw Exception('API 返回空的 choices');
      }
      final choice = choices[0];
      final message = choice['message'];
      if (message == null) {
        throw Exception('API 返回的 choice 缺少 message');
      }
      final content = _messageContentText(message['content']);
      final reasoning = _extractReasoning(message);
      return ChatResponse(
        content: content,
        reasoning: reasoning,
        toolCalls: _parseOpenAIToolCalls(message),
      );
    } else {
      throw Exception(
        'API 请求失败: ${response.statusCode} ${_truncateErrorBody(response.body)}',
      );
    }
  }

  Stream<StreamChunk> _sendOpenAICompatibleStreamRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
    List<Map<String, dynamic>> tools = const [],
    String? toolChoice,
  }) async* {
    final uri = _endpointUri(config, '/chat/completions');

    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': _openAICompatibleMessages(messages),
      'stream': true,
      if (config.effectiveMaxTokens != null)
        'max_tokens': config.effectiveMaxTokens,
      if (config.effectiveTemperature != null)
        'temperature': config.effectiveTemperature,
      if (config.effectiveTopP != null) 'top_p': config.effectiveTopP,
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

    final request = http.Request('POST', uri);
    request.headers.addAll(headers);
    request.body = jsonEncode(body);

    try {
      final streamedResponse = await client.send(request).timeout(_timeout);

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception(
          '流式请求失败: ${streamedResponse.statusCode} ${_truncateErrorBody(errorBody)}',
        );
      }

      final toolCallParts = <int, _OpenAIStreamToolCallAccumulator>{};
      var doneEmitted = false;

      await for (final chunk
          in streamedResponse.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .timeout(_streamTimeout)) {
        if (chunk.startsWith('data:')) {
          final data = chunk.substring(5).trim();
          if (data == '[DONE]') {
            doneEmitted = true;
            yield StreamChunk(
              toolCalls: _finalizeOpenAIToolCalls(toolCallParts),
              isDone: true,
            );
            break;
          }
          Object? finishReason;
          try {
            final json = jsonDecode(data);
            if (json is Map && json['error'] != null) {
              throw Exception(_formatApiError(json['error']));
            }
            final choice = json['choices']?[0];
            if (choice != null) {
              final delta = choice['delta'];
              final content = _streamContentText(delta?['content']);
              final reasoning = _extractReasoning(delta);
              _accumulateOpenAIToolCalls(delta, toolCallParts);
              if (content != null || reasoning != null) {
                yield StreamChunk(
                  content: content,
                  reasoningContent: reasoning,
                );
              }
            }
            finishReason = choice?['finish_reason'];
          } on FormatException {
            // malformed chunk, skip
          }
          if (finishReason != null && finishReason != '') {
            doneEmitted = true;
            yield StreamChunk(
              toolCalls: _finalizeOpenAIToolCalls(toolCallParts),
              isDone: true,
            );
            break;
          }
        }
      }
      if (!doneEmitted) {
        yield StreamChunk(
          toolCalls: _finalizeOpenAIToolCalls(toolCallParts),
          isDone: true,
        );
      }
    } finally {}
  }

  void _accumulateOpenAIToolCalls(
    dynamic delta,
    Map<int, _OpenAIStreamToolCallAccumulator> toolCallParts,
  ) {
    if (delta is! Map) return;
    final rawToolCalls = delta['tool_calls'];
    if (rawToolCalls is! List) return;
    for (final raw in rawToolCalls) {
      if (raw is! Map) continue;
      final index = (raw['index'] as num?)?.toInt() ?? 0;
      final acc = toolCallParts.putIfAbsent(
        index,
        _OpenAIStreamToolCallAccumulator.new,
      );
      final id = raw['id'] as String?;
      if (id != null && id.isNotEmpty) acc.id ??= id;
      final function = raw['function'];
      if (function is Map) {
        final name = function['name'] as String?;
        if (name != null && name.isNotEmpty) acc.name = name;
        final arguments = function['arguments'] as String?;
        if (arguments != null && arguments.isNotEmpty) {
          acc.arguments.write(arguments);
        }
      }
    }
  }

  List<ChatToolCall> _finalizeOpenAIToolCalls(
    Map<int, _OpenAIStreamToolCallAccumulator> toolCallParts,
  ) {
    final calls = <ChatToolCall>[];
    for (final entry
        in toolCallParts.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key))) {
      final acc = entry.value;
      final name = acc.name;
      if (name == null || name.isEmpty) continue;
      final rawArgs = acc.arguments.toString().trim();
      var args = <String, dynamic>{};
      if (rawArgs.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawArgs);
          if (decoded is Map) {
            args = decoded.map((key, value) => MapEntry(key.toString(), value));
          } else {
            debugPrint('跳过非 JSON 对象工具参数，长度: ${rawArgs.length}');
            continue;
          }
        } catch (e) {
          debugPrint('跳过无法解析的工具参数: $e');
          continue;
        }
      }
      calls.add(
        ChatToolCall(
          id: acc.id ?? 'call_${entry.key}',
          name: name,
          arguments: args,
        ),
      );
    }
    return calls;
  }

  Future<ChatResponse> _sendOllamaRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
  }) async {
    final uri = _endpointUri(config, '/api/chat');

    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': messages,
      'stream': false,
      'think': thinking,
    };

    if (config.effectiveMaxTokens != null ||
        config.effectiveTemperature != null ||
        config.effectiveTopP != null) {
      body['options'] = {
        if (config.effectiveMaxTokens != null)
          'num_predict': config.effectiveMaxTokens,
        if (config.effectiveTemperature != null)
          'temperature': config.effectiveTemperature,
        if (config.effectiveTopP != null) 'top_p': config.effectiveTopP,
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
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final rawContent = data['message']?['content'] as String? ?? '';
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

    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': messages,
      'stream': true,
      'think': thinking,
    };

    if (config.effectiveMaxTokens != null ||
        config.effectiveTemperature != null ||
        config.effectiveTopP != null) {
      body['options'] = {
        if (config.effectiveMaxTokens != null)
          'num_predict': config.effectiveMaxTokens,
        if (config.effectiveTemperature != null)
          'temperature': config.effectiveTemperature,
        if (config.effectiveTopP != null) 'top_p': config.effectiveTopP,
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

    try {
      final streamedResponse = await client.send(request).timeout(_timeout);

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception(
          'Ollama 流式请求失败: ${streamedResponse.statusCode} $errorBody',
        );
      }

      String ollamaBuf = '';
      bool inThink = false;

      int safeLengthForPartialTag(String text, List<String> prefixes) {
        for (var i = text.length - 1; i >= 0; i--) {
          final suffix = text.substring(i).toLowerCase();
          if (prefixes.any((prefix) => prefix.startsWith(suffix))) return i;
        }
        return text.length;
      }

      List<StreamChunk> processBuffer({bool flush = false}) {
        final result = <StreamChunk>[];
        while (ollamaBuf.isNotEmpty) {
          if (!inThink) {
            final lower = ollamaBuf.toLowerCase();
            final start = lower.indexOf('<think');
            if (start == -1) {
              final safeLength = flush
                  ? ollamaBuf.length
                  : safeLengthForPartialTag(ollamaBuf, const [
                      '<think',
                      '<think>',
                    ]);
              if (safeLength == 0) break;
              final content = ollamaBuf.substring(0, safeLength);
              if (content.isNotEmpty) result.add(StreamChunk(content: content));
              ollamaBuf = ollamaBuf.substring(safeLength);
              continue;
            }
            if (start > 0) {
              result.add(StreamChunk(content: ollamaBuf.substring(0, start)));
              ollamaBuf = ollamaBuf.substring(start);
              continue;
            }
            final tagEnd = ollamaBuf.indexOf('>');
            if (tagEnd == -1) {
              if (flush) ollamaBuf = '';
              break;
            }
            ollamaBuf = ollamaBuf.substring(tagEnd + 1);
            inThink = true;
          } else {
            final lower = ollamaBuf.toLowerCase();
            final end = lower.indexOf('</think>');
            if (end == -1) {
              final safeLength = flush
                  ? ollamaBuf.length
                  : safeLengthForPartialTag(ollamaBuf, const ['</think>']);
              if (safeLength == 0) break;
              final reasoning = ollamaBuf.substring(0, safeLength);
              if (reasoning.isNotEmpty) {
                result.add(StreamChunk(reasoningContent: reasoning));
              }
              ollamaBuf = ollamaBuf.substring(safeLength);
              continue;
            }
            if (end > 0) {
              result.add(
                StreamChunk(reasoningContent: ollamaBuf.substring(0, end)),
              );
            }
            ollamaBuf = ollamaBuf.substring(end + '</think>'.length);
            inThink = false;
          }
        }
        return result;
      }

      var doneEmitted = false;
      await for (final chunk
          in streamedResponse.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .timeout(_streamTimeout)) {
        if (chunk.trim().isEmpty) continue;
        try {
          final json = jsonDecode(chunk);
          final error = json['error'];
          if (error != null) throw Exception('Ollama 流式返回错误: $error');
          final rawContent = json['message']?['content'] as String?;
          final done = json['done'] as bool? ?? false;
          if (rawContent != null) {
            ollamaBuf += rawContent;
            for (final c in processBuffer()) {
              yield c;
            }
          }
          if (done) {
            for (final c in processBuffer(flush: true)) {
              yield c;
            }
            doneEmitted = true;
            yield StreamChunk(isDone: true);
            break;
          }
        } catch (e) {
          throw Exception('Ollama 流式解析失败: $e');
        }
      }
      if (!doneEmitted) {
        for (final c in processBuffer(flush: true)) {
          yield c;
        }
        yield StreamChunk(isDone: true);
      }
    } finally {}
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

    final maxTokens = config.effectiveMaxTokens ?? 4096;
    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': anthropicMessages,
      'max_tokens': maxTokens,
      'stream': true,
      // ignore: use_null_aware_elements
      if (systemPrompt != null) 'system': systemPrompt,
      if (config.effectiveTemperature != null)
        'temperature': config.effectiveTemperature,
      if (config.effectiveTopP != null) 'top_p': config.effectiveTopP,
      if (thinking && !config.extraParams.containsKey('thinking'))
        'thinking': {
          'type': 'enabled',
          'budget_tokens': _anthropicThinkingBudget(config, maxTokens),
        },
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

    try {
      final streamedResponse = await client.send(request).timeout(_timeout);

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception(
          'Anthropic 流式请求失败: ${streamedResponse.statusCode} $errorBody',
        );
      }

      var doneEmitted = false;
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
            if (type == 'error') {
              throw Exception(_formatApiError(json['error']));
            }

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
              doneEmitted = true;
              yield StreamChunk(isDone: true);
              break;
            }
          } on FormatException {
            // malformed chunk, skip
          }
        }
      }
      if (!doneEmitted) {
        yield StreamChunk(isDone: true);
      }
    } finally {}
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

    final maxTokens = config.effectiveMaxTokens ?? 4096;
    final body = <String, dynamic>{
      'model': config.modelName,
      'messages': anthropicMessages,
      'max_tokens': maxTokens,
      'stream': false,
      // ignore: use_null_aware_elements
      if (systemPrompt != null) 'system': systemPrompt,
      if (config.effectiveTemperature != null)
        'temperature': config.effectiveTemperature,
      if (config.effectiveTopP != null) 'top_p': config.effectiveTopP,
      if (thinking && !config.extraParams.containsKey('thinking'))
        'thinking': {
          'type': 'enabled',
          'budget_tokens': _anthropicThinkingBudget(config, maxTokens),
        },
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
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is Map && data['error'] != null) {
        throw Exception(_formatApiError(data['error']));
      }
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
          if (decoded is Map) {
            args = decoded.map((key, value) => MapEntry(key.toString(), value));
          } else {
            throw FormatException('工具参数不是 JSON 对象: $rawArgs');
          }
        } catch (e) {
          throw FormatException('工具参数不是合法 JSON: $rawArgs ($e)');
        }
      } else if (rawArgs is Map) {
        args = rawArgs.map((key, value) => MapEntry(key.toString(), value));
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

  String? _extractReasoning(dynamic message) {
    final parts = <String>[];

    void add(Object? value) {
      if (value is String && value.trim().isNotEmpty) {
        parts.add(value.trim());
      }
    }

    void visit(Object? value, {bool inReasoning = false}) {
      if (value is String) {
        if (inReasoning) add(value);
        return;
      }
      if (value is List) {
        for (final item in value) {
          visit(item, inReasoning: inReasoning);
        }
        return;
      }
      if (value is! Map) return;

      for (final key in const [
        'reasoning_content',
        'reasoning',
        'thinking',
        'thinking_content',
        'reasoning_text',
        'reasoning_summary',
        'reasoning_details',
      ]) {
        final raw = value[key];
        if (raw is String) {
          add(raw);
        } else if (raw != null) {
          visit(raw, inReasoning: true);
        }
      }

      final type = value['type'] as String?;
      final looksLikeReasoning =
          inReasoning ||
          (type != null &&
              (type.contains('reasoning') || type.contains('thinking')));
      if (looksLikeReasoning) {
        for (final key in const ['text', 'content', 'summary', 'value']) {
          visit(value[key], inReasoning: true);
        }
      }
    }

    visit(message);
    if (parts.isEmpty) return null;
    return parts.toSet().join('\n\n');
  }

  String _messageContentText(Object? content) {
    final text = _streamContentText(content);
    return text ?? '';
  }

  String? _streamContentText(Object? content) {
    if (content == null) return null;
    if (content is String) return content;
    if (content is List) {
      final text = content
          .map(_messageContentText)
          .where((part) => part.isNotEmpty)
          .join('');
      return text.isEmpty ? null : text;
    }
    if (content is Map) {
      for (final key in const ['text', 'content', 'value']) {
        final text = _streamContentText(content[key]);
        if (text != null && text.isNotEmpty) return text;
      }
      return null;
    }
    return content.toString();
  }

  int _anthropicThinkingBudget(ModelConfig config, int maxTokens) {
    final configured = config.extraParams['thinkingBudgetTokens'];
    if (configured is num && configured > 0) {
      return math.min(configured.toInt(), math.max(1, maxTokens - 1));
    }
    return math.min(1024, math.max(1, maxTokens - 1));
  }

  String _formatApiError(Object? error) {
    if (error is Map) {
      final message = error['message'] ?? error['error'] ?? error['type'];
      if (message != null) return message.toString();
    }
    return error?.toString() ?? '未知 API 错误';
  }
}

class _OpenAIStreamToolCallAccumulator {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}
