import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/agent_cancellation.dart';
import 'package:lynai/services/agent_context_builder.dart';

void main() {
  test(
    'keeps tool results intact and bounds total estimated context',
    () async {
      const builder = AgentContextBuilder(
        budget: AgentContextBudget(
          modelTokenBudget: 200,
          reservedOutputTokens: 20,
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

      expect(result.estimatedTokens, lessThanOrEqualTo(180));
      expect(
        result.messages.any(
          (message) => message.containsKey('reasoning_content'),
        ),
        isFalse,
      );
      final tool = result.messages.where(
        (message) => message['role'] == 'tool',
      );
      expect(tool, isNotEmpty);
      expect(tool.single['content'], 'x' * 100);
      expect(
        tool.single['content'],
        isNot(contains('[tool result truncated]')),
      );
      expect(result.messages.last['content'], 'newest question');
    },
  );

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

  test(
    'counts image parts by vision estimate instead of base64 length',
    () async {
      final imageData = base64Encode(List<int>.filled(1024 * 1024, 7));
      const builder = AgentContextBuilder(
        budget: AgentContextBudget(modelTokenBudget: 262144),
      );
      var compactCalls = 0;
      final result = await builder.build(
        messages: [
          const {'role': 'system', 'content': 'system prompt'},
          {
            'role': 'user',
            'content': [
              const {'type': 'text', 'text': '看看这张图'},
              {
                'type': 'input_file',
                'name': 'photo.png',
                'mime_type': 'image/png',
                'data': imageData,
              },
            ],
          },
        ],
        cancellationToken: AgentCancellationSource().token,
        compact: (request) async {
          compactCalls++;
          return const AgentCompactionCheckpoint(summary: 'summary');
        },
      );

      expect(compactCalls, 0);
      expect(result.compacted, isFalse);
      expect(result.droppedMessageCount, 0);
      expect(result.estimatedTokens, lessThan(5000));

      final user = result.messages.lastWhere(
        (message) => message['role'] == 'user',
      );
      expect(user['content'], isA<List<Object?>>());
      final parts = user['content'] as List<Object?>;
      expect(parts, hasLength(2));
      final imagePart = parts[1] as Map;
      expect(imagePart['data'], imageData);
    },
  );

  test(
    'applyBudget false sends full context without truncating or compacting',
    () async {
      final toolResult = 'r${'x' * 2000}';
      const builder = AgentContextBuilder(
        budget: AgentContextBudget(
          modelTokenBudget: 20,
          reservedOutputTokens: 10,
          charactersPerToken: 1,
        ),
      );
      var compactCalls = 0;
      final result = await builder.build(
        messages: [
          const {'role': 'system', 'content': 'system'},
          {
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {'id': 'call-1'},
            ],
          },
          {'role': 'tool', 'tool_call_id': 'call-1', 'content': toolResult},
        ],
        cancellationToken: AgentCancellationSource().token,
        compact: (request) async {
          compactCalls++;
          return const AgentCompactionCheckpoint(summary: 'summary');
        },
        applyBudget: false,
      );

      expect(compactCalls, 0);
      expect(result.compacted, isFalse);
      expect(result.droppedMessageCount, 0);
      expect(result.messages, hasLength(3));
      expect(result.messages.last['content'], toolResult);
      expect(
        result.messages.last['content'],
        isNot(contains('[tool result truncated]')),
      );
      expect(result.estimatedTokens, greaterThan(10));
    },
  );

  test('structured image content survives budget truncation', () async {
    final imageData = base64Encode(List<int>.filled(64 * 1024, 9));
    const builder = AgentContextBuilder(
      budget: AgentContextBudget(
        modelTokenBudget: 100,
        reservedOutputTokens: 60,
        charactersPerToken: 2,
      ),
    );
    final messages = <Map<String, dynamic>>[
      for (var index = 0; index < 10; index++)
        {
          'role': index.isEven ? 'user' : 'assistant',
          'content': 'old message $index ${'x' * 30}',
        },
      {
        'role': 'user',
        'content': [
          const {'type': 'text', 'text': 'newest image question'},
          {
            'type': 'input_file',
            'name': 'photo.png',
            'mime_type': 'image/png',
            'data': imageData,
          },
        ],
      },
    ];
    final result = await builder.build(
      messages: messages,
      cancellationToken: AgentCancellationSource().token,
    );

    final user = result.messages.lastWhere(
      (message) => message['role'] == 'user',
    );
    expect(user['content'], isA<List<Object?>>());
    final parts = user['content'] as List<Object?>;
    expect(parts, hasLength(2));
    expect((parts[0] as Map)['text'], 'newest image question');
    expect((parts[1] as Map)['data'], imageData);
    expect((parts[1] as Map)['type'], 'input_file');
  });
}
