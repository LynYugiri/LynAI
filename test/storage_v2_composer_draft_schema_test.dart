import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/composer_draft.dart';
import 'package:lynai/models/composer_reference.dart';
import 'package:lynai/repositories/composer_draft_repository.dart';
import 'package:lynai/services/storage_v2_database.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('schema 35 migrates composer_drafts table and index', () async {
    final root = await Directory.systemTemp.createTemp('lynai_draft_schema_');
    final storageRoot = Directory('${root.path}/storage_v2');
    await storageRoot.create(recursive: true);
    final storage = StorageV2Database(storageRoot);
    try {
      await storage.loadDataFile('tasks.json');
      await storage.close();
      final raw = sqlite3.open('${storageRoot.path}/app.db');
      try {
        raw.execute('DROP TABLE composer_drafts');
        raw.execute('PRAGMA user_version = 34');
      } finally {
        raw.close();
      }

      final reopened = StorageV2Database(storageRoot);
      await reopened.loadDataFile('tasks.json');
      await reopened.close();
      final migrated = sqlite3.open('${storageRoot.path}/app.db');
      try {
        expect(
          migrated.userVersion,
          StorageV2DriftDatabase.currentSchemaVersion,
        );
        final tables = migrated
            .select("SELECT name FROM sqlite_master WHERE type = 'table'")
            .map((row) => row['name'])
            .toSet();
        expect(tables, contains('composer_drafts'));
        final indexes = migrated
            .select("SELECT name FROM sqlite_master WHERE type = 'index'")
            .map((row) => row['name'])
            .toSet();
        expect(indexes, contains('idx_composer_drafts_conversation'));
      } finally {
        migrated.close();
      }
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('草稿写入后可以重新读取', () async {
    final root = await Directory.systemTemp.createTemp('lynai_draft_rows_');
    final storage = StorageV2Service(rootDirectory: root);
    try {
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
      final repository = ComposerDraftRepository(storageV2: storage);
      await repository.save({
        'conversation-1': const ComposerDraft(
          segments: [ComposerTextSegment('还没发出去')],
        ),
      });

      final reloaded = await ComposerDraftRepository(storageV2: storage).load();
      expect(reloaded.single.slot, 'conversation-1');
      expect(
        reloaded.single.draft.segments
            .whereType<ComposerTextSegment>()
            .single
            .text,
        '还没发出去',
      );
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}
