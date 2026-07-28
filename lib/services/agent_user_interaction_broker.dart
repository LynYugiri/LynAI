import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/agent_user_interaction.dart';

enum AgentUserInteractionResponseStatus {
  accepted,
  invalidAnswer,
  staleOrDuplicate,
}

class AgentUserInteractionBusyException implements Exception {
  final AgentUserInteractionSurface surface;

  const AgentUserInteractionBusyException(this.surface);

  @override
  String toString() =>
      'A user interaction is already pending on ${surface.name}';
}

class AgentUserInteractionBroker extends ChangeNotifier {
  final Map<AgentUserInteractionSurface, _PendingInteraction> _pending = {};
  final Uuid _uuid;

  AgentUserInteractionBroker({Uuid uuid = const Uuid()}) : _uuid = uuid;

  AgentUserInteractionRequest? pendingFor(
    AgentUserInteractionSurface surface,
  ) => _pending[surface]?.request;

  Future<AgentUserInteractionResult> ask({
    required AgentUserInteractionSurface surface,
    required AgentUserInteractionIdentity identity,
    required AgentUserQuestion question,
  }) {
    if (_pending.containsKey(surface)) {
      throw AgentUserInteractionBusyException(surface);
    }
    _validateIdentity(identity);
    final request = AgentUserInteractionRequest(
      id: _uuid.v4(),
      surface: surface,
      identity: identity,
      question: question,
    );
    final completer = Completer<AgentUserInteractionResult>();
    _pending[surface] = _PendingInteraction(request, completer);
    notifyListeners();
    return completer.future;
  }

  AgentUserInteractionResponseStatus answer({
    required AgentUserInteractionSurface surface,
    required String requestId,
    required AgentUserAnswer answer,
  }) {
    final pending = _pending[surface];
    if (pending == null || pending.request.id != requestId) {
      return AgentUserInteractionResponseStatus.staleOrDuplicate;
    }
    final normalized = _validateAnswer(pending.request.question, answer);
    if (normalized == null) {
      return AgentUserInteractionResponseStatus.invalidAnswer;
    }
    _pending.remove(surface);
    pending.completer.complete(AgentUserInteractionResult.answered(normalized));
    notifyListeners();
    return AgentUserInteractionResponseStatus.accepted;
  }

  AgentUserInteractionResponseStatus cancel({
    required AgentUserInteractionSurface surface,
    required String requestId,
    String? reason,
  }) {
    final pending = _pending[surface];
    if (pending == null || pending.request.id != requestId) {
      return AgentUserInteractionResponseStatus.staleOrDuplicate;
    }
    _pending.remove(surface);
    pending.completer.complete(AgentUserInteractionResult.cancelled(reason));
    notifyListeners();
    return AgentUserInteractionResponseStatus.accepted;
  }

  void cancelSurface(AgentUserInteractionSurface surface, {String? reason}) {
    final pending = _pending.remove(surface);
    if (pending == null) return;
    pending.completer.complete(AgentUserInteractionResult.cancelled(reason));
    notifyListeners();
  }

  AgentUserAnswer? _validateAnswer(
    AgentUserQuestion question,
    AgentUserAnswer answer,
  ) {
    if (question.kind != answer.kind) return null;
    switch (question.kind) {
      case AgentUserQuestionKind.text:
        final text = answer.text?.trim() ?? '';
        return text.isEmpty ? null : AgentUserAnswer.text(text);
      case AgentUserQuestionKind.confirm:
        final confirmed = answer.confirmed;
        return confirmed == null ? null : AgentUserAnswer.confirm(confirmed);
      case AgentUserQuestionKind.singleChoice:
        if (answer.choiceIds.length != 1) return null;
        final id = answer.choiceIds.single;
        return question.choices.any((choice) => choice.id == id)
            ? AgentUserAnswer.singleChoice(id)
            : null;
      case AgentUserQuestionKind.multipleChoice:
        final ids = answer.choiceIds.toSet();
        final max = question.maxSelections ?? question.choices.length;
        if (ids.length != answer.choiceIds.length ||
            ids.length < question.minSelections ||
            ids.length > max ||
            ids.any(
              (id) => !question.choices.any((choice) => choice.id == id),
            )) {
          return null;
        }
        return AgentUserAnswer.multipleChoice(ids);
    }
  }

  void _validateIdentity(AgentUserInteractionIdentity identity) {
    if (identity.runId.trim().isEmpty ||
        identity.turnId.trim().isEmpty ||
        identity.toolCallId.trim().isEmpty ||
        identity.toolName.trim().isEmpty) {
      throw ArgumentError('Interaction identity fields must not be empty');
    }
  }
}

class _PendingInteraction {
  final AgentUserInteractionRequest request;
  final Completer<AgentUserInteractionResult> completer;

  const _PendingInteraction(this.request, this.completer);
}
