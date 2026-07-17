import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/note_revision_merge.dart';

void main() {
  group('mergeNoteMarkdown', () {
    test('fast-forwards unchanged side', () {
      final result = mergeNoteMarkdown('a\nb', 'a\nb', 'a\nremote');
      expect(result.conflicted, isFalse);
      expect(result.content, 'a\nremote');
    });

    test('merges independent line changes', () {
      final result = mergeNoteMarkdown(
        'one\ntwo\nthree',
        'ONE\ntwo\nthree',
        'one\ntwo\nTHREE',
      );
      expect(result.conflicted, isFalse);
      expect(result.content, 'ONE\ntwo\nTHREE');
    });

    test('reports overlapping edits without conflict markers', () {
      final result = mergeNoteMarkdown('one\ntwo', 'one\nours', 'one\ntheirs');
      expect(result.conflicted, isTrue);
      expect(result.content, isNull);
    });

    test('conflicts on insertion at replacement start boundary', () {
      final result = mergeNoteMarkdown(
        'one\ntwo\nthree',
        'one\ninserted\ntwo\nthree',
        'one\nreplaced\nthree',
      );

      expect(result.conflicted, isTrue);
      expect(result.content, isNull);
    });

    test('conflicts on insertion at replacement end boundary', () {
      final result = mergeNoteMarkdown(
        'one\ntwo\nthree',
        'one\nreplaced\nthree',
        'one\ntwo\ninserted\nthree',
      );

      expect(result.conflicted, isTrue);
      expect(result.content, isNull);
    });
  });
}
