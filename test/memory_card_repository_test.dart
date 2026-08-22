import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/repositories/memory_card_repository.dart';
import 'package:lynai/services/storage_v2_database.dart';
import 'package:lynai/services/storage_v2_service.dart';

class _FakeStorageV2Service extends StorageV2Service {
  Map<String, dynamic> data = {};

  @override
  Future<Map<String, dynamic>> loadDataFile(String fileName) async => data;

  @override
  Future<void> writeDataFile(String fileName, Map<String, dynamic> data) async {
    this.data = Map<String, dynamic>.from(data);
  }

  @override
  Future<void> applyLocalRowChanges(
    List<SyncRemoteOperation> operations,
  ) async {}
}

void main() {
  test('repository load 过滤悬空卡片/日志与重复 ID', () async {
    final storage = _FakeStorageV2Service();
    storage.data = {
      'decks': [
        {
          'id': 'deck-1',
          'name': '测试',
          'sortOrder': 0,
          'enabled': true,
          'createdAt': '2026-08-16T00:00:00.000Z',
          'updatedAt': '2026-08-16T00:00:00.000Z',
        },
        {
          'id': 'deck-1',
          'name': '重复牌组',
          'sortOrder': 1,
          'enabled': true,
          'createdAt': '2026-08-16T00:00:00.000Z',
          'updatedAt': '2026-08-16T00:00:00.000Z',
        },
      ],
      'cards': [
        {
          'id': 'card-1',
          'deckId': 'deck-1',
          'front': 'f1',
          'back': 'b1',
          'status': 'new',
          'sourceKind': 'manual',
          'createdAt': '2026-08-16T00:00:00.000Z',
          'updatedAt': '2026-08-16T00:00:00.000Z',
        },
        {
          'id': 'card-2',
          'deckId': 'missing-deck',
          'front': 'f2',
          'back': 'b2',
          'status': 'new',
          'sourceKind': 'manual',
          'createdAt': '2026-08-16T00:00:00.000Z',
          'updatedAt': '2026-08-16T00:00:00.000Z',
        },
      ],
      'reviewLogs': [
        {
          'id': 'log-1',
          'cardId': 'card-1',
          'deckId': 'deck-1',
          'reviewedAt': '2026-08-16T00:00:00.000Z',
          'rating': 'good',
          'statusBefore': 'new',
          'statusAfter': 'review',
          'intervalDaysBefore': 0,
          'intervalDaysAfter': 1,
          'easeBefore': 2.5,
          'easeAfter': 2.5,
        },
        {
          'id': 'log-2',
          'cardId': 'missing-card',
          'deckId': 'deck-1',
          'reviewedAt': '2026-08-16T00:00:00.000Z',
          'rating': 'good',
          'statusBefore': 'new',
          'statusAfter': 'review',
          'intervalDaysBefore': 0,
          'intervalDaysAfter': 1,
          'easeBefore': 2.5,
          'easeAfter': 2.5,
        },
      ],
    };

    final result = await MemoryCardRepository(storageV2: storage).load();

    expect(result.decks, hasLength(1));
    expect(result.decks.single.id, 'deck-1');
    expect(result.cards.map((card) => card.id), ['card-1']);
    expect(result.reviewLogs.map((log) => log.id), ['log-1']);
  });
}
