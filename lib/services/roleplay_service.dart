import 'dart:convert';

import '../models/message.dart';
import '../models/model_config.dart';
import '../models/roleplay.dart';
import 'api_service.dart';
import 'backend_client.dart';

class RoleplayDecision {
  final String action;
  final String? speakerId;
  final String reason;
  final String? content;

  const RoleplayDecision({
    required this.action,
    this.speakerId,
    this.reason = '',
    this.content,
  });

  bool get waitsForUser => action == 'wait_user';
  bool get isNarrator => action == 'narrate';
}

class RoleplayService {
  RoleplayService({ApiService? api, BackendClient? backend})
    : _api = api ?? ApiService(backend: backend);

  final ApiService _api;

  void dispose() => _api.dispose();

  Future<RoleplayDecision> decideNext({
    required RoleplayThread thread,
    required ModelConfig model,
  }) async {
    final response = await _api.sendChatRequest(model, [
      {'role': 'system', 'content': _directorSystemPrompt(thread)},
      {'role': 'user', 'content': _directorUserPrompt(thread)},
    ], thinking: false);
    return parseDecision(
      response.content,
      thread.characters.map((e) => e.id).toSet(),
    );
  }

  Future<String> speak({
    required RoleplayThread thread,
    required RoleplayParticipant participant,
    required ModelConfig model,
  }) async {
    final response = await _api.sendChatRequest(model, [
      {'role': 'system', 'content': _speakerSystemPrompt(thread, participant)},
      {'role': 'user', 'content': _speakerUserPrompt(thread, participant)},
    ]);
    return response.content.trim();
  }

  Stream<StreamChunk> speakStream({
    required RoleplayThread thread,
    required RoleplayParticipant participant,
    required ModelConfig model,
  }) {
    return _api.sendStreamRequest(model, [
      {'role': 'system', 'content': _speakerSystemPrompt(thread, participant)},
      {'role': 'user', 'content': _speakerUserPrompt(thread, participant)},
    ]);
  }

  static ModelConfig? resolveModel(
    RoleplayModelSelection selection,
    List<ModelConfig> models,
  ) {
    ModelConfig? selected;
    final id = selection.modelId;
    if (id != null && id.isNotEmpty) {
      for (final model in models) {
        if (model.id == id) {
          selected = model;
          break;
        }
      }
    }
    selected ??= models.isEmpty ? null : models.first;
    if (selected == null) return null;
    final modelName = selection.modelName;
    if (modelName == null || modelName.isEmpty) return selected;
    return selected.copyWith(modelName: modelName);
  }

  static RoleplayDecision parseDecision(
    String content,
    Set<String> speakerIds,
  ) {
    try {
      final raw = _extractJsonObject(content);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final action = data['action'] as String? ?? 'wait_user';
      final speakerId = data['speakerId'] as String?;
      final reason = data['reason'] as String? ?? '';
      if (action == 'speak' &&
          speakerId != null &&
          speakerIds.contains(speakerId)) {
        return RoleplayDecision(
          action: action,
          speakerId: speakerId,
          reason: reason,
        );
      }
      if (action == 'narrate') {
        final content = data['content'] as String? ?? reason;
        return RoleplayDecision(
          action: action,
          reason: reason,
          content: content.isNotEmpty ? content : reason,
        );
      }
      return RoleplayDecision(action: 'wait_user', reason: reason);
    } catch (_) {
      return const RoleplayDecision(action: 'wait_user', reason: '导演返回无法解析');
    }
  }

  static String _extractJsonObject(String content) {
    final trimmed = content.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(trimmed);
    final source = fence?.group(1)?.trim() ?? trimmed;
    final start = source.indexOf('{');
    final end = source.lastIndexOf('}');
    if (start == -1 || end < start) return source;
    return source.substring(start, end + 1);
  }

  String _directorSystemPrompt(RoleplayThread thread) {
    return '''${thread.director.systemPrompt}

返回格式只能是 JSON：
{"action":"speak","speakerId":"角色 id","reason":"简短原因"}
或：
{"action":"wait_user","reason":"简短原因"}
或：
{"action":"narrate","content":"一段旁白、环境描写或场景推进","reason":"简短原因"}''';
  }

  String _directorUserPrompt(RoleplayThread thread) {
    return '''场景：
${thread.scenario}

用户扮演：
${thread.player?.name ?? '我'}
${thread.player?.description ?? ''}

可选 AI 角色：
${thread.characters.map((role) => '- id: ${role.id}\n  name: ${role.name}\n  description: ${role.description}').join('\n')}

最近历史：
${_history(thread)}

规则：
1. 不要替用户发言。
2. 如果需要用户回应，返回 wait_user。
3. 如果 AI 角色应该回应，返回 speak，并给出 speakerId。
4. 如果需要转场、环境描写或旁白，返回 narrate，并给出 content。
5. 避免同一角色无意义连续发言。
6. 只返回 JSON。''';
  }

  String _speakerSystemPrompt(
    RoleplayThread thread,
    RoleplayParticipant participant,
  ) {
    return '''你正在参与一个多角色情景演绎。

你扮演：${participant.name}

你的角色设定：
${participant.systemPrompt}

规则：
1. 只输出你的角色会说的话或动作描写。
2. 不要替其他角色发言。
3. 保持符合你的角色设定。

期待你的表现 ''';
  }

  String _speakerUserPrompt(
    RoleplayThread thread,
    RoleplayParticipant participant,
  ) {
    final others = thread.participants
        .where((role) => role.id != participant.id)
        .map((role) => '- ${role.name}: ${role.description}')
        .join('\n');
    return '''场景：
${thread.scenario}

其他角色：
$others

最近历史：
${_history(thread)}

现在轮到你发言。只输出 ${participant.name} 的内容。''';
  }

  String _history(RoleplayThread thread) {
    final messages = thread.messages.length <= 28
        ? thread.messages
        : thread.messages.sublist(thread.messages.length - 28);
    if (messages.isEmpty) return '（暂无）';
    return messages
        .map((message) {
          final attachments = _attachmentSummary(message.attachments);
          final content = message.content.trim();
          if (attachments.isEmpty) return '${message.speakerName}: $content';
          if (content.isEmpty) return '${message.speakerName}: $attachments';
          return '${message.speakerName}: $content\n$attachments';
        })
        .join('\n');
  }

  String _attachmentSummary(List<MessageImage> attachments) {
    if (attachments.isEmpty) return '';
    return attachments
        .map(
          (item) => '[附件: ${item.name} (${item.mimeType}, ${item.size} bytes)]',
        )
        .join('\n');
  }
}
