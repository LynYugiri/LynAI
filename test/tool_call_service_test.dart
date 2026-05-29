import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/services/tool_call_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('fallback parser tolerates malformed tool arguments', () {
    final calls = ToolCallService.parseFallbackToolCalls(r'''
```json
{
  "tool_calls": [
    {"name": "list_notes", "arguments": "{\"query\":\"alpha\"}"},
    {"name": "save_note", "arguments": "{bad json"},
    {"name": "save_note", "arguments": {"title": "x"}},
    {"arguments": {"query": "drop"}}
  ]
}
```
''');

    expect(calls, hasLength(3));
    expect(calls[0].name, 'list_notes');
    expect(calls[0].arguments, {'query': 'alpha'});
    expect(calls[1].name, 'save_note');
    expect(calls[1].arguments, isEmpty);
    expect(calls[2].name, 'save_note');
    expect(calls[2].arguments, {'title': 'x'});
    expect(calls.map((call) => call.id).toSet(), hasLength(calls.length));
  });

  test('fallback parser converts non-object arguments to empty maps', () {
    final calls = ToolCallService.parseFallbackToolCalls(
      jsonEncode({
        'tool_calls': [
          {'name': 'list_schedules', 'arguments': []},
          {'name': 'list_notes', 'arguments': '[]'},
          {'name': 'list_todo_lists', 'arguments': null},
        ],
      }),
    );

    expect(calls, hasLength(3));
    expect(calls.every((call) => call.arguments.isEmpty), isTrue);
  });

  test(
    'list_notes requires query before returning full note contents',
    () async {
      SharedPreferences.setMockInitialValues({});
      final features = FeatureProvider();
      await features.load();
      await features.addNoteWithContent('secret', 'private body');
      final service = ToolCallService(features);

      final blocked = await service.execute(
        const ChatToolCall(
          id: 'list-all-content',
          name: 'list_notes',
          arguments: {'includeContent': true},
        ),
        const [],
      );
      final allowed = await service.execute(
        const ChatToolCall(
          id: 'list-filtered-content',
          name: 'list_notes',
          arguments: {'query': 'secret', 'includeContent': true},
        ),
        const [],
      );

      expect(blocked['ok'], isFalse);
      expect(allowed['ok'], isTrue);
      expect(allowed['notes'], hasLength(1));
      expect(allowed['notes'].single['content'], 'private body');
    },
  );
}
