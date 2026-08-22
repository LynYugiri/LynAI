import 'dart:convert';

import '../models/agent_defaults.dart';
import '../models/agent_runtime.dart';

class AgentContextBudget {
  final int modelTokenBudget;
  final int reservedOutputTokens;
  final int maxToolResultTokens;
  final int maxCompactionTokens;
  final int charactersPerToken;

  const AgentContextBudget({
    this.modelTokenBudget = defaultAgentContextWindow,
    this.reservedOutputTokens = 4096,
    this.maxToolResultTokens = 2048,
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

  const AgentCharacterContextEstimator({this.charactersPerToken = 4});

  int estimateMessages(Iterable<Map<String, dynamic>> messages) {
    return estimateText(jsonEncode(messages));
  }

  int estimateText(String value) {
    if (value.isEmpty) return 0;
    return (value.length + charactersPerToken - 1) ~/ charactersPerToken;
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
  }) async {
    cancellationToken.throwIfCancellationRequested();
    final estimator = AgentCharacterContextEstimator(
      charactersPerToken: budget.charactersPerToken,
    );
    final normalized = _normalize(messages);
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
        if (message['role'] != 'tool') output.add(_boundToolResult(message));
        continue;
      }
      final resultMessages = <String, Map<String, dynamic>>{};
      var cursor = index + 1;
      while (cursor < input.length && input[cursor]['role'] == 'tool') {
        final result = input[cursor];
        final id = result['tool_call_id']?.toString();
        if (id != null) resultMessages[id] = _boundToolResult(result);
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

  Map<String, dynamic> _boundToolResult(Map<String, dynamic> message) {
    if (message['role'] != 'tool') return message;
    final content = message['content']?.toString() ?? '';
    final maxCharacters =
        budget.maxToolResultTokens * budget.charactersPerToken;
    if (content.length <= maxCharacters) return message;
    return {
      ...message,
      'content':
          '${content.substring(0, maxCharacters)}\n[tool result truncated]',
    };
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
    final result = unit;
    if (estimator.estimateMessages(result) <= targetTokens) return result;
    final userIndex = result.lastIndexWhere(
      (message) => message['role'] == 'user',
    );
    if (userIndex < 0) return result;
    final message = result[userIndex];
    final content = message['content']?.toString() ?? '';
    const suffix = '\n[earlier content truncated]';
    var low = 0;
    var high = content.length;
    while (low < high) {
      final length = (low + high + 1) ~/ 2;
      message['content'] =
          '${content.substring(content.length - length)}$suffix';
      if (estimator.estimateMessages(result) <= targetTokens) {
        low = length;
      } else {
        high = length - 1;
      }
    }
    message['content'] = low == content.length
        ? content
        : '${content.substring(content.length - low)}$suffix';
    if (estimator.estimateMessages(result) > targetTokens) {
      message['content'] = '';
    }
    return result;
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
    while (estimator.estimateMessages(result) > targetTokens) {
      final index = result.indexWhere(
        (message) =>
            !identical(message, checkpoint) &&
            !identical(message, newestUser) &&
            message['role'] != 'system',
      );
      if (index >= 0) {
        result.removeAt(index);
        continue;
      }
      final systemIndex = result.indexWhere(
        (message) => !identical(message, checkpoint),
      );
      if (systemIndex >= 0) {
        result.removeAt(systemIndex);
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
    while (result.length > 1 &&
        estimator.estimateMessages(result) > targetTokens) {
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
    }
    if (result.isEmpty || estimator.estimateMessages(result) <= targetTokens) {
      return result;
    }
    final message = result.single;
    final content = message['content']?.toString() ?? '';
    final maxCharacters = targetTokens * budget.charactersPerToken ~/ 2;
    message['content'] = content.length <= maxCharacters
        ? content
        : '${content.substring(content.length - maxCharacters)}\n[earlier content truncated]';
    return result;
  }

  bool _hasContent(Map<String, dynamic> message) {
    final content = message['content'];
    return content != null && content.toString().trim().isNotEmpty;
  }
}
