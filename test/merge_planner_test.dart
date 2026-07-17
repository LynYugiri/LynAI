import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/merge_models.dart';

void main() {
  group('MergePlanner', () {
    test('classifies new, identical and conflicting records', () {
      expect(
        MergePlanner.classify<int>(
          local: null,
          incoming: 1,
          equals: (left, right) => left == right,
        ),
        MergeAction.addIncoming,
      );
      expect(
        MergePlanner.classify<int>(
          local: 1,
          incoming: 1,
          equals: (left, right) => left == right,
        ),
        MergeAction.unchanged,
      );
      expect(
        MergePlanner.classify<int>(
          local: 1,
          incoming: 2,
          equals: (left, right) => left == right,
        ),
        MergeAction.conflict,
      );
    });

    test('uses revision then updatedAt for latest-wins records', () {
      expect(
        MergePlanner.latestWins(
          local: {
            'id': 'm1',
            'revision': 1,
            'updatedAt': '2026-01-01T00:00:00Z',
          },
          incoming: {
            'id': 'm1',
            'revision': 2,
            'updatedAt': '2025-01-01T00:00:00Z',
          },
        ),
        MergeAction.useIncoming,
      );
      expect(
        MergePlanner.latestWins(
          local: {'id': 't1', 'updatedAt': '2026-01-02T00:00:00Z'},
          incoming: {'id': 't1', 'updatedAt': '2026-01-01T00:00:00Z'},
          revisionKey: '_none',
        ),
        MergeAction.keepLocal,
      );
    });
  });
}
