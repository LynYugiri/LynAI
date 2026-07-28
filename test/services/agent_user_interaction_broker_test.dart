import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_user_interaction.dart';
import 'package:lynai/services/agent_user_interaction_broker.dart';

void main() {
  const surface = AgentUserInteractionSurface.floatingAssistant;
  const identity = AgentUserInteractionIdentity(
    runId: 'run-1',
    turnId: 'turn-2',
    toolCallId: 'call-3',
    toolName: 'ask_user',
  );

  test('binds a pending request to run turn tool call and surface', () async {
    final broker = AgentUserInteractionBroker();
    final future = broker.ask(
      surface: surface,
      identity: identity,
      question: AgentUserQuestion(
        kind: AgentUserQuestionKind.text,
        prompt: 'Name?',
      ),
    );
    final pending = broker.pendingFor(surface)!;

    expect(pending.identity.runId, 'run-1');
    expect(pending.identity.turnId, 'turn-2');
    expect(pending.identity.toolCallId, 'call-3');
    expect(
      broker.answer(
        surface: surface,
        requestId: pending.id,
        answer: AgentUserAnswer.text('  Lyn  '),
      ),
      AgentUserInteractionResponseStatus.accepted,
    );

    final result = await future;
    expect(result.isAnswered, isTrue);
    expect(result.answer!.text, 'Lyn');
    expect(broker.pendingFor(surface), isNull);
  });

  test('allows only one pending request per surface', () {
    final broker = AgentUserInteractionBroker();
    broker.ask(
      surface: surface,
      identity: identity,
      question: AgentUserQuestion(
        kind: AgentUserQuestionKind.confirm,
        prompt: 'Continue?',
      ),
    );

    expect(
      () => broker.ask(
        surface: surface,
        identity: identity,
        question: AgentUserQuestion(
          kind: AgentUserQuestionKind.confirm,
          prompt: 'Again?',
        ),
      ),
      throwsA(isA<AgentUserInteractionBusyException>()),
    );
  });

  test('validates choices without consuming the pending request', () async {
    final broker = AgentUserInteractionBroker();
    final future = broker.ask(
      surface: surface,
      identity: identity,
      question: AgentUserQuestion(
        kind: AgentUserQuestionKind.multipleChoice,
        prompt: 'Pick two',
        choices: const [
          AgentUserChoice(id: 'a', label: 'A'),
          AgentUserChoice(id: 'b', label: 'B'),
          AgentUserChoice(id: 'c', label: 'C'),
        ],
        minSelections: 2,
        maxSelections: 2,
      ),
    );
    final requestId = broker.pendingFor(surface)!.id;

    expect(
      broker.answer(
        surface: surface,
        requestId: requestId,
        answer: AgentUserAnswer.multipleChoice(['a']),
      ),
      AgentUserInteractionResponseStatus.invalidAnswer,
    );
    expect(broker.pendingFor(surface), isNotNull);
    expect(
      broker.answer(
        surface: surface,
        requestId: requestId,
        answer: AgentUserAnswer.multipleChoice(['a', 'b']),
      ),
      AgentUserInteractionResponseStatus.accepted,
    );

    expect((await future).answer!.choiceIds, ['a', 'b']);
  });

  test('suppresses stale duplicate and cross-surface responses', () async {
    final broker = AgentUserInteractionBroker();
    final future = broker.ask(
      surface: surface,
      identity: identity,
      question: AgentUserQuestion(
        kind: AgentUserQuestionKind.confirm,
        prompt: 'Continue?',
      ),
    );
    final requestId = broker.pendingFor(surface)!.id;

    expect(
      broker.answer(
        surface: AgentUserInteractionSurface.mainChat,
        requestId: requestId,
        answer: AgentUserAnswer.confirm(true),
      ),
      AgentUserInteractionResponseStatus.staleOrDuplicate,
    );
    expect(
      broker.cancel(surface: surface, requestId: 'stale'),
      AgentUserInteractionResponseStatus.staleOrDuplicate,
    );
    expect(
      broker.cancel(surface: surface, requestId: requestId),
      AgentUserInteractionResponseStatus.accepted,
    );
    expect((await future).outcome, AgentUserInteractionOutcome.cancelled);
    expect(
      broker.answer(
        surface: surface,
        requestId: requestId,
        answer: AgentUserAnswer.confirm(true),
      ),
      AgentUserInteractionResponseStatus.staleOrDuplicate,
    );
  });
}
