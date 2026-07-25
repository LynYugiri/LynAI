import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/pages/chat_page.dart';

void main() {
  test('retry rebuilds structured content when attachments exist', () async {
    var prepared = false;
    final message = Message(
      id: 'message-1',
      role: 'user',
      content: 'inspect',
      modelContextContent: 'inspect\n[文件: payload.bin]',
      images: const [
        MessageImage(path: '/tmp/payload.bin', name: 'payload.bin', size: 4),
      ],
      timestamp: DateTime.utc(2026),
    );

    final content = await retryUserContent(message, () async {
      prepared = true;
      return const [
        {'type': 'input_file', 'name': 'payload.bin', 'data': 'AQIDBA=='},
      ];
    });

    expect(prepared, isTrue);
    expect(content, isA<List<dynamic>>());
  });

  test(
    'retry reuses persisted text context when no attachments exist',
    () async {
      var prepared = false;
      final message = Message(
        id: 'message-1',
        role: 'user',
        content: 'visible',
        modelContextContent: 'recognized context',
        timestamp: DateTime.utc(2026),
      );

      final content = await retryUserContent(message, () async {
        prepared = true;
        return 'unexpected';
      });

      expect(prepared, isFalse);
      expect(content, 'recognized context');
    },
  );
}
