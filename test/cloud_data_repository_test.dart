import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/cloud_data.dart';
import 'package:lynai/repositories/cloud_data_repository.dart';
import 'package:lynai/services/storage_v2_service.dart';

void main() {
  test('cloud cache and reseed operations are isolated by scope', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai-cloud-repository-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final storage = StorageV2Service(rootDirectory: root);
    addTearDown(storage.close);
    final repository = StorageV2CloudDataRepository(storage);
    final status = CloudIndexStatus(
      lastSeq: 8,
      generation: 2,
      indexRevision: 9,
      minAvailableSeq: 1,
      usage: const CloudUsage(
        recordCount: 3,
        blobCount: 1,
        blobBytes: 512,
        blobRefCount: 2,
      ),
    );
    final object = CloudIndexObject(
      category: 'notes',
      objectId: 'note-1',
      recordCount: 3,
      blobRefCount: 1,
      latestSeq: 8,
      updatedAt: DateTime.utc(2026, 7, 24),
    );
    final operation = CloudManagementOperation(
      id: 'operation-1',
      kind: 'selective',
      selectorType: 'object',
      category: 'notes',
      objectId: 'note-1',
      generation: 2,
      indexRevision: 10,
      createdAt: DateTime.utc(2026, 7, 24),
    );

    await repository.replace('scope-a', status, [object]);
    await repository.saveOperations('scope-a', [operation]);

    final cached = await repository.load('scope-a');
    expect(cached.status?.indexRevision, 9);
    expect(cached.objects.single.objectId, 'note-1');
    expect(cached.categoryCounts, {'notes': 1});
    expect(
      (await repository.loadOperations('scope-a')).single.id,
      'operation-1',
    );
    expect((await repository.load('scope-b')).objects, isEmpty);
    expect(await repository.loadOperations('scope-b'), isEmpty);

    await repository.removeOperation('scope-a', 'operation-1');
    expect(await repository.loadOperations('scope-a'), isEmpty);
  });
}
