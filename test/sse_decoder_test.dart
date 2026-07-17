import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/sse_decoder.dart';

void main() {
  test(
    'decodes multiline CRLF events, comments, and multiple events',
    () async {
      final source = Stream<String>.fromIterable(const [
        ': keep-alive\r\nevent: delta\r\ndata: first\r\n',
        'data: second\r\n\r\ndata: third\n\n',
      ]);

      final events = await source.transform(const SseDecoder()).toList();

      expect(events, hasLength(2));
      expect(events[0].event, 'delta');
      expect(events[0].data, 'first\nsecond');
      expect(events[1].event, isNull);
      expect(events[1].data, 'third');
    },
  );

  test('decodes events separated only by CR line endings', () async {
    final source = Stream<String>.fromIterable(const [
      'event: delta\rdata: first\r',
      'data: second\r\rdata: third\r\r',
    ]);

    final events = await source.transform(const SseDecoder()).toList();

    expect(events, hasLength(2));
    expect(events[0].event, 'delta');
    expect(events[0].data, 'first\nsecond');
    expect(events[1].data, 'third');
  });
}
