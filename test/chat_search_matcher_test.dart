import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/utils/chat_search_matcher.dart';

void main() {
  group('ChatSearchMatcher', () {
    test('matches literal text case-insensitively', () {
      final matcher = ChatSearchMatcher.fromQuery('hello');

      final ranges = matcher.rangesIn('Hello hello HELLO');

      expect(ranges.map((range) => [range.start, range.end]), [
        [0, 5],
        [6, 11],
        [12, 17],
      ]);
    });

    test('supports re prefix regex search', () {
      final matcher = ChatSearchMatcher.fromQuery(r're:h.llo');

      expect(matcher.rangesIn('hello hallo hxllo').length, 3);
    });

    test('supports slash regex flags', () {
      final sensitive = ChatSearchMatcher.fromQuery('/hello/');
      final insensitive = ChatSearchMatcher.fromQuery('/hello/i');

      expect(sensitive.rangesIn('Hello hello').length, 1);
      expect(insensitive.rangesIn('Hello hello').length, 2);
    });

    test('reports invalid regex without matching text', () {
      final matcher = ChatSearchMatcher.fromQuery('re:[');

      expect(matcher.hasError, isTrue);
      expect(matcher.rangesIn('anything'), isEmpty);
    });

    test('ignores zero-width regex matches', () {
      final matcher = ChatSearchMatcher.fromQuery(r're:\b');

      expect(matcher.rangesIn('word'), isEmpty);
    });
  });
}
