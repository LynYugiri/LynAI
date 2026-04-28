import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/model_config.dart';

/// AI API 服务
///
/// 负责与 AI 模型 API 进行通信。
/// 支持 OpenAI 兼容接口和 Ollama 接口。
/// 目前为占位实现，可根据需要扩展。
class ApiService {
  /// 发送聊天请求到指定的 AI 模型
  ///
  /// [config] AI 模型配置
  /// [messages] 历史消息列表，格式为 [{"role": "user/assistant", "content": "..."}]
  /// 返回 AI 的回复文本
  Future<String> sendChatRequest(
    ModelConfig config,
    List<Map<String, String>> messages,
  ) async {
    try {
      final uri = Uri.parse('${config.endpoint}/chat/completions');

      final body = {
        'model': config.modelName,
        'messages': messages,
        'stream': false,
      };

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${config.apiKey}',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'] as String;
      } else {
        throw Exception(
            'API 请求失败: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('API 请求异常: $e');
    }
  }

  /// 发送聊天请求到 Ollama 接口
  ///
  /// Ollama 的 API 格式与 OpenAI 不同，需要特殊处理。
  Future<String> sendOllamaRequest(
    ModelConfig config,
    List<Map<String, String>> messages,
  ) async {
    try {
      final uri = Uri.parse('${config.endpoint}/api/chat');

      // 转换消息格式为 Ollama 格式
      final ollamaMessages = messages.map((m) {
        return {
          'role': m['role'],
          'content': m['content'],
        };
      }).toList();

      final body = {
        'model': config.modelName,
        'messages': ollamaMessages,
        'stream': false,
      };

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['message']['content'] as String;
      } else {
        throw Exception(
            'Ollama 请求失败: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Ollama 请求异常: $e');
    }
  }
}

