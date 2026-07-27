import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/agent_cancellation.dart';
import 'package:lynai/services/agent_context_builder.dart';

void main() {
  test('bounds tool results and total estimated context', () async {
    const builder = AgentContextBuilder(
      budget: AgentContextBudget(
        modelTokenBudget: 80,
        reservedOutputTokens: 20,
        maxToolResultTokens: 8,
        charactersPerToken: 2,
      ),
    );
    final result = await builder.build(
      messages: [
        const {'role': 'system', 'content': 'system'},
        const {'role': 'user', 'content': 'old old old old old old old old'},
        {
          'role': 'assistant',
          'content': '',
          'reasoning_content': 'private reasoning',
          'tool_calls': [
            {
              'id': 'call-1',
              'type': 'function',
              'function': {'name': 'lookup', 'arguments': '{}'},
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'call-1', 'content': 'x' * 100},
        const {'role': 'user', 'content': 'newest question'},
      ],
      cancellationToken: AgentCancellationSource().token,
    );

    expect(result.estimatedTokens, lessThanOrEqualTo(60));
    expect(
      result.messages.any(
        (message) => message.containsKey('reasoning_content'),
      ),
      isFalse,
    );
    final tool = result.messages.where((message) => message['role'] == 'tool');
    if (tool.isNotEmpty) {
      expect(tool.single['content'], contains('[tool result truncated]'));
    }
    expect(result.messages.last['content'], 'newest question');
  });

  test('keeps only complete tool call and result pairs', () async {
    const builder = AgentContextBuilder();
    final result = await builder.build(
      messages: const [
        {
          'role': 'assistant',
          'content': 'partial',
          'tool_calls': [
            {'id': 'complete'},
            {'id': 'missing'},
          ],
        },
        {'role': 'tool', 'tool_call_id': 'complete', 'content': 'ok'},
        {'role': 'tool', 'tool_call_id': 'orphan', 'content': 'orphan'},
      ],
      cancellationToken: AgentCancellationSource().token,
    );

    expect(result.messages, hasLength(2));
    expect(
      (result.messages.first['tool_calls'] as List).single['id'],
      'complete',
    );
    expect(result.messages.last['tool_call_id'], 'complete');
  });

  test(
    'truncates and preserves newest user before selecting older context',
    () async {
      const builder = AgentContextBuilder(
        budget: AgentContextBudget(
          modelTokenBudget: 60,
          reservedOutputTokens: 20,
          charactersPerToken: 2,
        ),
      );
      final result = await builder.build(
        messages: [
          const {'role': 'user', 'content': 'short older question'},
          const {'role': 'assistant', 'content': 'short older answer'},
          {'role': 'user', 'content': 'newest marker ${'x' * 200}'},
        ],
        cancellationToken: AgentCancellationSource().token,
      );

      final users = result.messages.where(
        (message) => message['role'] == 'user',
      );
      expect(users, isNotEmpty);
      expect(users.last['content'], contains('[earlier content truncated]'));
      expect(users.last['content'], isNot('short older question'));
      expect(result.estimatedTokens, lessThanOrEqualTo(40));
    },
  );

  test('inserts bounded compaction checkpoint', () async {
    const builder = AgentContextBuilder(
      budget: AgentContextBudget(
        modelTokenBudget: 100,
        reservedOutputTokens: 20,
        maxCompactionTokens: 10,
        charactersPerToken: 2,
      ),
    );
    var compactedMessages = 0;
    final result = await builder.build(
      messages: List.generate(
        10,
        (index) => {
          'role': index.isEven ? 'user' : 'assistant',
          'content': 'message $index ${'x' * 30}',
        },
      ),
      cancellationToken: AgentCancellationSource().token,
      compact: (request) async {
        compactedMessages = request.droppedMessages.length;
        return const AgentCompactionCheckpoint(
          summary: 'Earlier work summary',
          checkpoint: 'step-4',
        );
      },
    );

    expect(compactedMessages, greaterThan(0));
    expect(result.compacted, isTrue);
    expect(
      result.messages.any(
        (message) =>
            message['content'].toString().contains('Context checkpoint:'),
      ),
      isTrue,
    );
    expect(result.estimatedTokens, lessThanOrEqualTo(80));
  });
}
