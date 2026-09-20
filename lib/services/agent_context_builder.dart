import 'dart:convert';

import '../models/agent_defaults.dart';
import '../models/agent_runtime.dart';

class AgentContextBudget {
  final int modelTokenBudget;
  final int reservedOutputTokens;
  final int maxCompactionTokens;
  final int charactersPerToken;

  const AgentContextBudget({
    this.modelTokenBudget = defaultAgentContextWindow,
    this.reservedOutputTokens = 4096,
    this.maxCompactionTokens = 2048,
    this.charactersPerToken = 4,
  });

  int get inputTokenBudget {
    final available = modelTokenBudget - reservedOutputTokens;
    return available > 0 ? available : 1;
  }
}

class AgentCharacterContextEstimator {
  final int charactersPerToken;

  /// 每张图片内容的保守 token 估算。
  ///
  /// 视觉模型按像素/图块计算图片 token，而不是按 base64 长度计算；这里用
  /// 固定值避免把图片字节误算成文本 token，同时不声称是精确 tokenizer。
  final int imageTokensPerImage;

  const AgentCharacterContextEstimator({
    this.charactersPerToken = 4,
    this.imageTokensPerImage = 1024,
  });

  /// 单条消息的近似 token 成本。
  ///
  /// [estimateMessages] 是逐条成本之和，因此裁剪循环可以只算一次、删一条减一条，
  /// 不必每删一条就把整段历史重新 jsonEncode 一遍。
  int estimateMessageTokens(Map<String, dynamic> message) =>
      estimateText(jsonEncode(_budgetSafeMessage(message))) +
      _imagePartCount(message['content']) * imageTokensPerImage;

  int estimateMessages(Iterable<Map<String, dynamic>> messages) {
    var tokens = 0;
    for (final message in messages) {
      tokens += estimateMessageTokens(message);
    }
    return tokens;
  }

  int estimateText(String value) {
    if (value.isEmpty) return 0;
    return (value.length + charactersPerToken - 1) ~/ charactersPerToken;
  }

  Map<String, dynamic> _budgetSafeMessage(Map<String, dynamic> message) {
    final safe = Map<String, dynamic>.from(message);
    final content = message['content'];
    if (content is! List) return safe;
    safe['content'] = content
        .map<Object?>((part) {
          if (part is! Map) return part;
          final safePart = Map<String, dynamic>.from(part);
          switch (safePart['type']) {
            case 'input_file':
              final mimeType = safePart['mime_type']?.toString() ?? '';
              if (mimeType.startsWith('image/')) {
                safePart['data'] = '<base64 image omitted>';
              }
              break;
            case 'image_url':
              final imageUrl = safePart['image_url'];
              if (imageUrl is Map) {
                final safeImageUrl = Map<String, dynamic>.from(imageUrl);
                final url = safeImageUrl['url']?.toString() ?? '';
                if (url.startsWith('data:')) {
                  safeImageUrl['url'] =
                      'data:image/placeholder;base64,<base64 image omitted>';
                }
                safePart['image_url'] = safeImageUrl;
              }
              break;
            case 'image':
              final source = safePart['source'];
              if (source is Map) {
                final safeSource = Map<String, dynamic>.from(source);
                if (safeSource['data'] is String) {
                  safeSource['data'] = '<base64 image omitted>';
                }
                safePart['source'] = safeSource;
              }
              break;
          }
          return safePart;
        })
        .toList(growable: false);
    return safe;
  }

  int _imagePartCount(Object? content) {
    if (content is! List) return 0;
    var count = 0;
    for (final part in content) {
      if (part is! Map) continue;
      final type = part['type'];
      if (type == 'image_url' || type == 'image') {
        count++;
        continue;
      }
      if (type == 'input_file' &&
          (part['mime_type']?.toString() ?? '').startsWith('image/')) {
        count++;
      }
    }
    return count;
  }
}

class AgentCompactionRequest {
  final List<Map<String, dynamic>> droppedMessages;
  final int targetTokens;
  final AgentRunCancellation cancellationToken;

  AgentCompactionRequest({
    required Iterable<Map<String, dynamic>> droppedMessages,
    required this.targetTokens,
    required this.cancellationToken,
  }) : droppedMessages = List.unmodifiable(
         droppedMessages.map(
           (message) => Map<String, dynamic>.unmodifiable(message),
         ),
       );
}

class AgentCompactionCheckpoint {
  final String summary;
  final String? checkpoint;

  const AgentCompactionCheckpoint({required this.summary, this.checkpoint});
}

typedef AgentContextCompactor =
    Future<AgentCompactionCheckpoint?> Function(AgentCompactionRequest request);

class AgentContextBuildResult {
  final List<Map<String, dynamic>> messages;
  final int estimatedTokens;
  final int droppedMessageCount;
  final bool compacted;

  AgentContextBuildResult({
    required Iterable<Map<String, dynamic>> messages,
    required this.estimatedTokens,
    required this.droppedMessageCount,
    required this.compacted,
  }) : messages = List.unmodifiable(
         messages.map((message) => Map<String, dynamic>.unmodifiable(message)),
       );
}

class AgentContextBuilder {
  final AgentContextBudget budget;

  const AgentContextBuilder({this.budget = const AgentContextBudget()});

  Future<AgentContextBuildResult> build({
    required Iterable<Map<String, dynamic>> messages,
    required AgentRunCancellation cancellationToken,
    AgentContextCompactor? compact,
    bool forceCompaction = false,
    bool applyBudget = true,
  }) async {
    cancellationToken.throwIfCancellationRequested();
    final estimator = AgentCharacterContextEstimator(
      charactersPerToken: budget.charactersPerToken,
    );
    final normalized = _normalize(messages);
    if (!applyBudget) {
      return AgentContextBuildResult(
        messages: normalized,
        estimatedTokens: estimator.estimateMessages(normalized),
        droppedMessageCount: 0,
        compacted: false,
      );
    }
    final targetTokens = forceCompaction
        ? (budget.inputTokenBudget * 3 ~/ 4).clamp(1, budget.inputTokenBudget)
        : budget.inputTokenBudget;
    var bounded = _selectWithinBudget(normalized, targetTokens, estimator);
    var dropped = _difference(normalized, bounded);
    var compacted = false;

    if (dropped.isNotEmpty && compact != null) {
      final checkpoint = await compact(
        AgentCompactionRequest(
          droppedMessages: dropped,
          targetTokens: budget.maxCompactionTokens,
          cancellationToken: cancellationToken,
        ),
      );
      cancellationToken.throwIfCancellationRequested();
      if (checkpoint != null && checkpoint.summary.trim().isNotEmpty) {
        final summary = _checkpointMessage(checkpoint, estimator);
        bounded = _insertCheckpoint(bounded, summary);
        bounded = _fitCheckpoint(bounded, summary, targetTokens, estimator);
        compacted = bounded.contains(summary);
      }
    }

    if (estimator.estimateMessages(bounded) > targetTokens) {
      bounded = _truncateNewest(bounded, targetTokens, estimator);
    }
    return AgentContextBuildResult(
      messages: bounded,
      estimatedTokens: estimator.estimateMessages(bounded),
      droppedMessageCount: _missingMessageCount(normalized, bounded),
      compacted: compacted,
    );
  }

  List<Map<String, dynamic>> _normalize(Iterable<Map<String, dynamic>> source) {
    final input = source.map(_withoutReasoning).toList(growable: false);
    final output = <Map<String, dynamic>>[];
    for (var index = 0; index < input.length; index++) {
      final message = input[index];
      final calls = message['tool_calls'];
      if (message['role'] != 'assistant' || calls is! List || calls.isEmpty) {
        if (message['role'] != 'tool') output.add(message);
        continue;
      }
      final resultMessages = <String, Map<String, dynamic>>{};
      var cursor = index + 1;
      while (cursor < input.length && input[cursor]['role'] == 'tool') {
        final result = input[cursor];
        final id = result['tool_call_id']?.toString();
        if (id != null) resultMessages[id] = result;
        cursor++;
      }
      final completeCalls = <Object?>[];
      final completeResults = <Map<String, dynamic>>[];
      for (final rawCall in calls) {
        if (rawCall is! Map) continue;
        final id = rawCall['id']?.toString();
        final result = id == null ? null : resultMessages[id];
        if (result == null) continue;
        completeCalls.add(Map<String, dynamic>.from(rawCall));
        completeResults.add(result);
      }
      final assistant = Map<String, dynamic>.from(message);
      if (completeCalls.isEmpty) {
        assistant.remove('tool_calls');
        if (_hasContent(assistant)) output.add(assistant);
      } else {
        assistant['tool_calls'] = completeCalls;
        output.add(assistant);
        output.addAll(completeResults);
      }
      index = cursor - 1;
    }
    return output;
  }

  Map<String, dynamic> _withoutReasoning(Map<String, dynamic> source) {
    final message = Map<String, dynamic>.from(source);
    for (final key in const [
      'reasoning_content',
      'reasoning',
      'thinking',
      'thinking_content',
    ]) {
      message.remove(key);
    }
    return message;
  }

  List<Map<String, dynamic>> _selectWithinBudget(
    List<Map<String, dynamic>> messages,
    int targetTokens,
    AgentCharacterContextEstimator estimator,
  ) {
    if (estimator.estimateMessages(messages) <= targetTokens) return messages;
    final units = _units(messages);
    final selectedIndexes = <int>{};
    final newestUserUnitIndex = units.lastIndexWhere(
      (unit) => unit.any((message) => message['role'] == 'user'),
    );
    var used = 2;
    if (newestUserUnitIndex >= 0) {
      final newestUserUnit = _truncateUnit(
        units[newestUserUnitIndex],
        targetTokens,
        estimator,
      );
      selectedIndexes.add(newestUserUnitIndex);
      used = estimator.estimateMessages(newestUserUnit);
    }
    for (var index = units.length - 1; index >= 0; index--) {
      if (index == newestUserUnitIndex) continue;
      final unit = units[index];
      final cost = estimator.estimateMessages(unit);
      if (used + cost > targetTokens) continue;
      selectedIndexes.add(index);
      used += cost;
    }
    final result = <Map<String, dynamic>>[];
    for (var index = 0; index < units.length; index++) {
      if (selectedIndexes.contains(index)) result.addAll(units[index]);
    }
    for (final message in messages.where((item) => item['role'] == 'system')) {
      if (result.contains(message)) continue;
      final candidate = [message, ...result];
      if (estimator.estimateMessages(candidate) <= targetTokens) {
        result.insert(0, message);
      }
    }
    return result;
  }

  List<Map<String, dynamic>> _truncateUnit(
    List<Map<String, dynamic>> unit,
    int targetTokens,
    AgentCharacterContextEstimator estimator,
  ) {
    if (estimator.estimateMessages(unit) <= targetTokens) return unit;
    final userIndex = unit.lastIndexWhere(
      (message) => message['role'] == 'user',
    );
    if (userIndex < 0) return unit;
    _truncateMessageTextAt(unit, userIndex, targetTokens, estimator);
    return unit;
  }

  List<List<Map<String, dynamic>>> _units(List<Map<String, dynamic>> messages) {
    final units = <List<Map<String, dynamic>>>[];
    for (var index = 0; index < messages.length; index++) {
      final message = messages[index];
      final unit = <Map<String, dynamic>>[message];
      if (message['role'] == 'assistant' && message['tool_calls'] is List) {
        while (index + 1 < messages.length &&
            messages[index + 1]['role'] == 'tool') {
          unit.add(messages[++index]);
        }
      }
      units.add(unit);
    }
    return units;
  }

  List<Map<String, dynamic>> _difference(
    List<Map<String, dynamic>> source,
    List<Map<String, dynamic>> selected,
  ) {
    final retained = selected.toSet();
    return source.where((message) => !retained.contains(message)).toList();
  }

  int _missingMessageCount(
    List<Map<String, dynamic>> source,
    List<Map<String, dynamic>> selected,
  ) {
    final counts = <String, int>{};
    for (final message in selected) {
      final key = jsonEncode(message);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    var missing = 0;
    for (final message in source) {
      final key = jsonEncode(message);
      final count = counts[key] ?? 0;
      if (count == 0) {
        missing++;
      } else {
        counts[key] = count - 1;
      }
    }
    return missing;
  }

  Map<String, dynamic> _checkpointMessage(
    AgentCompactionCheckpoint checkpoint,
    AgentCharacterContextEstimator estimator,
  ) {
    var content = [
      'Context checkpoint:',
      checkpoint.summary.trim(),
      if (checkpoint.checkpoint?.trim().isNotEmpty == true)
        'Checkpoint: ${checkpoint.checkpoint!.trim()}',
    ].join('\n');
    final maxCharacters =
        budget.maxCompactionTokens * budget.charactersPerToken;
    if (content.length > maxCharacters) {
      content =
          '${content.substring(0, maxCharacters)}\n[checkpoint truncated]';
    }
    return {'role': 'system', 'content': content};
  }

  List<Map<String, dynamic>> _insertCheckpoint(
    List<Map<String, dynamic>> messages,
    Map<String, dynamic> checkpoint,
  ) {
    var index = 0;
    while (index < messages.length && messages[index]['role'] == 'system') {
      index++;
    }
    return [...messages]..insert(index, checkpoint);
  }

  List<Map<String, dynamic>> _fitCheckpoint(
    List<Map<String, dynamic>> messages,
    Map<String, dynamic> checkpoint,
    int targetTokens,
    AgentCharacterContextEstimator estimator,
  ) {
    final result = [...messages];
    final newestUser = result.lastWhere(
      (message) => message['role'] == 'user',
      orElse: () => const <String, dynamic>{},
    );
    final costs = result.map(estimator.estimateMessageTokens).toList();
    var total = costs.fold(0, (sum, cost) => sum + cost);
    while (total > targetTokens) {
      final index = result.indexWhere(
        (message) =>
            !identical(message, checkpoint) &&
            !identical(message, newestUser) &&
            message['role'] != 'system',
      );
      if (index >= 0) {
        result.removeAt(index);
        total -= costs.removeAt(index);
        continue;
      }
      final systemIndex = result.indexWhere(
        (message) => !identical(message, checkpoint),
      );
      if (systemIndex >= 0) {
        result.removeAt(systemIndex);
        total -= costs.removeAt(systemIndex);
        continue;
      }
      result.remove(checkpoint);
      break;
    }
    return result;
  }

  List<Map<String, dynamic>> _truncateNewest(
    List<Map<String, dynamic>> messages,
    int targetTokens,
    AgentCharacterContextEstimator estimator,
  ) {
    if (messages.isEmpty) return messages;
    final result = messages.map(Map<String, dynamic>.from).toList();
    final newestUserIndex = result.lastIndexWhere(
      (message) => message['role'] == 'user',
    );
    final newestUser = newestUserIndex < 0 ? null : result[newestUserIndex];
    final costs = result.map(estimator.estimateMessageTokens).toList();
    var total = costs.fold(0, (sum, cost) => sum + cost);
    while (result.length > 1 && total > targetTokens) {
      var removableIndex = result.indexWhere(
        (message) =>
            !identical(message, newestUser) && message['role'] != 'system',
      );
      if (removableIndex < 0) {
        removableIndex = result.indexWhere(
          (message) => !identical(message, newestUser),
        );
      }
      if (removableIndex < 0) break;
      result.removeAt(removableIndex);
      total -= costs.removeAt(removableIndex);
    }
    if (result.isEmpty || total <= targetTokens) {
      return result;
    }
    _truncateMessageTextAt(result, 0, targetTokens, estimator);
    return result;
  }

  void _truncateMessageTextAt(
    List<Map<String, dynamic>> unit,
    int messageIndex,
    int targetTokens,
    AgentCharacterContextEstimator estimator,
  ) {
    if (messageIndex < 0 || messageIndex >= unit.length) return;
    final message = unit[messageIndex];
    final content = message['content'];
    const suffix = '\n[earlier content truncated]';

    if (content is String) {
      if (content.isEmpty) return;
      var low = 0;
      var high = content.length;
      while (low < high) {
        final length = (low + high + 1) ~/ 2;
        message['content'] =
            '${content.substring(content.length - length)}$suffix';
        if (estimator.estimateMessages(unit) <= targetTokens) {
          low = length;
        } else {
          high = length - 1;
        }
      }
      message['content'] = low == content.length
          ? content
          : '${content.substring(content.length - low)}$suffix';
      if (estimator.estimateMessages(unit) > targetTokens) {
        message['content'] = '';
      }
      return;
    }

    if (content is! List) return;
    final parts = List<Object?>.from(content);
    message['content'] = parts;
    for (var index = 0; index < parts.length; index++) {
      final rawPart = parts[index];
      if (rawPart is! Map || rawPart['type'] != 'text') continue;
      final part = Map<String, dynamic>.from(rawPart);
      parts[index] = part;
      final text = part['text'];
      if (text is! String || text.isEmpty) continue;
      var low = 0;
      var high = text.length;
      while (low < high) {
        final length = (low + high + 1) ~/ 2;
        part['text'] = '${text.substring(text.length - length)}$suffix';
        if (estimator.estimateMessages(unit) <= targetTokens) {
          low = length;
        } else {
          high = length - 1;
        }
      }
      if (low == text.length) {
        part['text'] = text;
        if (estimator.estimateMessages(unit) <= targetTokens) return;
        continue;
      }
      part['text'] = '${text.substring(text.length - low)}$suffix';
      if (estimator.estimateMessages(unit) <= targetTokens) return;
      part['text'] = text;
    }
  }

  bool _hasContent(Map<String, dynamic> message) {
    final content = message['content'];
    return content != null && content.toString().trim().isNotEmpty;
  }
}
