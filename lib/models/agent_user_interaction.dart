enum AgentUserInteractionSurface { mainChat, floatingAssistant }

enum AgentUserQuestionKind { text, confirm, singleChoice, multipleChoice }

enum AgentUserInteractionOutcome { answered, cancelled }

class AgentUserInteractionIdentity {
  final String runId;
  final String turnId;
  final String toolCallId;
  final String toolName;

  const AgentUserInteractionIdentity({
    required this.runId,
    required this.turnId,
    required this.toolCallId,
    required this.toolName,
  });
}

class AgentUserChoice {
  final String id;
  final String label;
  final String? description;

  const AgentUserChoice({
    required this.id,
    required this.label,
    this.description,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    if (description != null) 'description': description,
  };
}

class AgentUserQuestion {
  final AgentUserQuestionKind kind;
  final String prompt;
  final String? detail;
  final List<AgentUserChoice> choices;
  final int minSelections;
  final int? maxSelections;

  AgentUserQuestion({
    required this.kind,
    required this.prompt,
    this.detail,
    Iterable<AgentUserChoice> choices = const [],
    this.minSelections = 1,
    this.maxSelections,
  }) : choices = List.unmodifiable(choices) {
    if (prompt.trim().isEmpty) {
      throw ArgumentError.value(prompt, 'prompt', 'must not be empty');
    }
    final choiceKind =
        kind == AgentUserQuestionKind.singleChoice ||
        kind == AgentUserQuestionKind.multipleChoice;
    if (choiceKind != this.choices.isNotEmpty) {
      throw ArgumentError(
        'Choice questions require choices and other kinds forbid them',
      );
    }
    final ids = this.choices.map((choice) => choice.id.trim()).toList();
    if (ids.any((id) => id.isEmpty) || ids.toSet().length != ids.length) {
      throw ArgumentError('Choice IDs must be non-empty and unique');
    }
    if (this.choices.any((choice) => choice.label.trim().isEmpty)) {
      throw ArgumentError('Choice labels must not be empty');
    }
    if (kind == AgentUserQuestionKind.multipleChoice &&
        (minSelections < 0 ||
            minSelections > this.choices.length ||
            (maxSelections != null &&
                (maxSelections! < minSelections ||
                    maxSelections! > this.choices.length)))) {
      throw ArgumentError('Invalid multiple-choice selection bounds');
    }
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'prompt': prompt,
    if (detail != null) 'detail': detail,
    if (choices.isNotEmpty)
      'choices': choices
          .map((choice) => choice.toJson())
          .toList(growable: false),
    if (kind == AgentUserQuestionKind.multipleChoice) ...{
      'minSelections': minSelections,
      if (maxSelections != null) 'maxSelections': maxSelections,
    },
  };
}

class AgentUserAnswer {
  final AgentUserQuestionKind kind;
  final String? text;
  final bool? confirmed;
  final List<String> choiceIds;

  AgentUserAnswer._({
    required this.kind,
    this.text,
    this.confirmed,
    Iterable<String> choiceIds = const [],
  }) : choiceIds = List.unmodifiable(choiceIds);

  factory AgentUserAnswer.text(String value) =>
      AgentUserAnswer._(kind: AgentUserQuestionKind.text, text: value);

  factory AgentUserAnswer.confirm(bool value) =>
      AgentUserAnswer._(kind: AgentUserQuestionKind.confirm, confirmed: value);

  factory AgentUserAnswer.singleChoice(String choiceId) => AgentUserAnswer._(
    kind: AgentUserQuestionKind.singleChoice,
    choiceIds: [choiceId],
  );

  factory AgentUserAnswer.multipleChoice(Iterable<String> choiceIds) =>
      AgentUserAnswer._(
        kind: AgentUserQuestionKind.multipleChoice,
        choiceIds: choiceIds,
      );

  Map<String, dynamic> toJson() => switch (kind) {
    AgentUserQuestionKind.text => {'kind': kind.name, 'text': text},
    AgentUserQuestionKind.confirm => {
      'kind': kind.name,
      'confirmed': confirmed,
    },
    AgentUserQuestionKind.singleChoice ||
    AgentUserQuestionKind.multipleChoice => {
      'kind': kind.name,
      'choiceIds': choiceIds,
    },
  };
}

class AgentUserInteractionResult {
  final AgentUserInteractionOutcome outcome;
  final AgentUserAnswer? answer;
  final String? cancellationReason;

  const AgentUserInteractionResult._({
    required this.outcome,
    this.answer,
    this.cancellationReason,
  });

  const AgentUserInteractionResult.answered(AgentUserAnswer answer)
    : this._(outcome: AgentUserInteractionOutcome.answered, answer: answer);

  const AgentUserInteractionResult.cancelled([String? reason])
    : this._(
        outcome: AgentUserInteractionOutcome.cancelled,
        cancellationReason: reason,
      );

  bool get isAnswered => outcome == AgentUserInteractionOutcome.answered;
}

class AgentUserInteractionRequest {
  final String id;
  final AgentUserInteractionSurface surface;
  final AgentUserInteractionIdentity identity;
  final AgentUserQuestion question;

  const AgentUserInteractionRequest({
    required this.id,
    required this.surface,
    required this.identity,
    required this.question,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'surface': surface.name,
    'identity': {
      'runId': identity.runId,
      'turnId': identity.turnId,
      'toolCallId': identity.toolCallId,
      'toolName': identity.toolName,
    },
    'question': question.toJson(),
  };
}
