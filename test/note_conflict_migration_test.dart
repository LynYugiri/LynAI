import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('schema migration persists stable note conflict sides', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_note_conflict_migration_',
    );
    final storageRoot = Directory('${root.path}/storage_v2');
    await storageRoot.create(recursive: true);
    await File('${storageRoot.path}/manifest.json').writeAsString('{}');
    final raw = sqlite3.open('${storageRoot.path}/app.db');
    try {
      raw.execute('''
CREATE TABLE storage_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE note_page_conflicts (
  page_id TEXT PRIMARY KEY NOT NULL,
  head_ids_json TEXT NOT NULL,
  common_ancestor_id TEXT,
  created_at TEXT NOT NULL
);
INSERT INTO note_page_conflicts VALUES (
  'page', '["local","incoming","third"]', 'base', '2026-07-17T00:00:00.000Z'
);
PRAGMA user_version = 11;
''');
    } finally {
      raw.close();
    }

    final storage = StorageV2Service(rootDirectory: root);
    try {
      await storage.loadNotesData();
      final migrated = sqlite3.open('${storageRoot.path}/app.db');
      try {
        final row = migrated
            .select(
              'SELECT local_head_id, incoming_head_id FROM note_page_conflicts',
            )
            .single;
        expect(row['local_head_id'], 'local');
        expect(row['incoming_head_id'], 'incoming');
        expect(migrated.userVersion, 14);
      } finally {
        migrated.close();
      }
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}
