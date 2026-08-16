import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/jotting.dart';
import 'package:lynai/repositories/jotting_repository.dart';
import 'package:lynai/services/storage_v2_service.dart';

void main() {
  test('replace and load roundtrip', () async {
    final root = await Directory.systemTemp.createTemp('lynai_jottings_repo_');
    final storage = StorageV2Service(rootDirectory: root);
    try {
      await storage.initializeDatasets();
      final repository = JottingRepository(storageV2: storage);
      final now = DateTime.utc(2026, 8, 16, 12);
      final items = [
        Jotting(
          id: 'j1',
          content: '第一条随记',
          tags: ['灵感'],
          createdAt: now,
          updatedAt: now,
        ),
        Jotting(
          id: 'j2',
          content: '第二条随记',
          tags: const [],
          createdAt: now.subtract(const Duration(days: 1)),
          updatedAt: now.subtract(const Duration(days: 1)),
        ),
      ];

      await repository.replace(JottingLoadResult(jottings: items));

      final loaded = await repository.load();
      expect(loaded.jottings, hasLength(2));
      expect(loaded.jottings.first.id, 'j1');
      expect(loaded.jottings.last.id, 'j2');
      expect(loaded.jottings.first.tags, ['灵感']);
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('load treats missing top-level jottings as empty', () async {
    final root = await Directory.systemTemp.createTemp('lynai_jottings_repo_');
    final storage = StorageV2Service(rootDirectory: root);
    try {
      await storage.initializeDatasets();
      await storage.writeDataFile('jottings.json', {});
      final repository = JottingRepository(storageV2: storage);

      final loaded = await repository.load();

      expect(loaded.jottings, isEmpty);
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('replace rejects top-level jottings that is not a list', () async {
    final root = await Directory.systemTemp.createTemp('lynai_jottings_repo_');
    final storage = StorageV2Service(rootDirectory: root);
    try {
      await storage.initializeDatasets();

      await expectLater(
        storage.writeDataFile('jottings.json', {'jottings': 'bad'}),
        throwsA(isA<FormatException>()),
      );
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}
