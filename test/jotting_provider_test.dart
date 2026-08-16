import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/local_date.dart';
import 'package:lynai/models/recycle_bin_item.dart';
import 'package:lynai/providers/jotting_provider.dart';
import 'package:lynai/repositories/jotting_repository.dart';
import 'package:lynai/repositories/recycle_bin_repository.dart';

void main() {
  test('add updates memory before serialized save completes', () async {
    final repository = _JottingRepository();
    final provider = JottingProvider(
      repository: repository,
      recycleBinRepository: _RecycleBinRepository(),
    );
    var notifications = 0;
    provider.addListener(() => notifications++);

    final add = provider.add('第一条随记', tags: ['灵感']);

    expect(provider.jottings.single.content, '第一条随记');
    expect(notifications, 1);
    expect(repository.saveCalls, 0);
    repository.allowSave.complete();
    await add;
    expect(repository.saveCalls, 1);
  });

  test('search filters by query tags and date range', () async {
    final repository = _JottingRepository()..allowSave.complete();
    final provider = JottingProvider(
      repository: repository,
      recycleBinRepository: _RecycleBinRepository(),
    );
    await provider.add(
      '今天有点 emo',
      tags: ['心情'],
      createdAt: DateTime(2026, 8, 10, 9),
    );
    await provider.add(
      '读书笔记：深度工作',
      tags: ['读书'],
      createdAt: DateTime(2026, 8, 16, 10),
    );
    await provider.add(
      '周末去爬山',
      tags: ['生活', '运动'],
      createdAt: DateTime(2026, 8, 17, 11),
    );

    final byQuery = provider.search(const JottingSearchFilter(query: '读书'));
    expect(byQuery.single.tags, ['读书']);

    final byTag = provider.search(const JottingSearchFilter(tags: ['生活']));
    expect(byTag.single.content, '周末去爬山');

    final byDate = provider.search(
      JottingSearchFilter(
        dateFrom: LocalDate(2026, 8, 16),
        dateTo: LocalDate(2026, 8, 16),
      ),
    );
    expect(byDate.single.content, contains('深度工作'));

    final limited = provider.search(
      const JottingSearchFilter(limit: 1),
    );
    expect(limited, hasLength(1));
    expect(limited.single.content, '周末去爬山');
  });

  test('delete writes to recycle bin and restore brings it back', () async {
    final repository = _JottingRepository()..allowSave.complete();
    final recycleBin = _RecycleBinRepository();
    final provider = JottingProvider(
      repository: repository,
      recycleBinRepository: recycleBin,
    );
    final id = await provider.add('待删除随记', tags: ['灵感']);

    await provider.delete(id);

    expect(provider.jottings, isEmpty);
    expect(recycleBin.added.single.type, RecycleBinItemTypes.jotting);
    expect(recycleBin.added.single.payload['jotting'], containsPair('id', id));

    await provider.restorePayload(recycleBin.added.single.payload);
    expect(provider.jottings.single.id, id);
  });

  test('load does not overwrite a concurrent mutation', () async {
    final repository = _JottingRepository()..allowSave.complete();
    final loadResult = Completer<JottingLoadResult>();
    repository.loadResult = loadResult.future;
    final provider = JottingProvider(
      repository: repository,
      recycleBinRepository: _RecycleBinRepository(),
    );

    final load = provider.load();
    final id = await provider.add('并发新增');
    loadResult.complete(const JottingLoadResult(jottings: []));
    await load;

    expect(provider.jottings.single.id, id);
  });
}

class _JottingRepository implements JottingRepository {
  final allowSave = Completer<void>();
  Future<JottingLoadResult>? loadResult;
  int saveCalls = 0;

  @override
  Future<JottingLoadResult> load() async {
    return await (loadResult ?? Future.value(const JottingLoadResult(jottings: [])));
  }

  @override
  Future<void> replace(JottingLoadResult value) async {
    saveCalls++;
    await allowSave.future;
  }
}

class _RecycleBinRepository implements RecycleBinRepository {
  final added = <RecycleBinItem>[];
  final removed = <String>[];
  Object? addError;

  @override
  Future<void> add(RecycleBinItem item) async {
    if (addError != null) throw addError!;
    added.add(item);
  }

  @override
  Future<List<RecycleBinItem>> load() async => [];

  @override
  Future<void> remove(String id) async {
    removed.add(id);
  }

  @override
  Future<void> save(List<RecycleBinItem> items) async {}
}
