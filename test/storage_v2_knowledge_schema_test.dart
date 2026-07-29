import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/storage_v2_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('schema 26 knowledge settings and constraints match', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_knowledge_schema_',
    );
    final storageRoot = Directory('${root.path}/storage_v2');
    await storageRoot.create(recursive: true);
    final storage = StorageV2Database(storageRoot);
    try {
      await storage.loadDataFile('knowledge.json');
      final raw = sqlite3.open('${storageRoot.path}/app.db');
      try {
        expect(raw.userVersion, 26);
        final columns = raw
            .select('PRAGMA table_info(knowledge_categories)')
            .map((row) => row['name'])
            .toSet();
        expect(
          columns,
          containsAll({
            'alias',
            'annotation_rule',
            'explanation_prompt',
            'color_value',
            'auto_annotate',
            'model_config_id',
          }),
        );
        for (final table in ['knowledge_sources', 'knowledge_explanations']) {
          final childColumns = raw
              .select('PRAGMA table_info($table)')
              .map((row) => row['name'])
              .toSet();
          expect(childColumns, contains('knowledge_base_id'));
        }
        final settingsColumns = raw
            .select('PRAGMA table_info(knowledge_settings)')
            .map((row) => row['name'])
            .toSet();
        expect(
          settingsColumns,
          containsAll({
            'id',
            'default_knowledge_base_id',
            'default_category_id',
            'updated_at',
          }),
        );
        raw.execute("""
INSERT INTO knowledge_bases VALUES ('base', 'Base', NULL, 1, 0, 'now', 'now');
INSERT INTO knowledge_categories VALUES (
  'one', 'base', 'One', 'valid_alias', NULL, '', '', 0, 1, NULL, 1, 1, 0, 'now', 'now'
);
UPDATE knowledge_settings
SET default_knowledge_base_id = 'base', default_category_id = 'one', updated_at = 'now'
WHERE id = 1;
""");
        expect(
          () => raw.execute(
            "INSERT INTO knowledge_settings VALUES (2, 'base', 'one', 'now')",
          ),
          throwsA(isA<SqliteException>()),
        );
        expect(
          () => raw.execute(
            "UPDATE knowledge_settings SET default_category_id = NULL WHERE id = 1",
          ),
          throwsA(isA<SqliteException>()),
        );
        expect(
          () => raw.execute("""
INSERT INTO knowledge_categories VALUES (
  'two', 'base', 'Two', 'valid_alias', NULL, '', '', 0, 0, NULL, 0, 1, 1, 'now', 'now'
);
"""),
          throwsA(isA<SqliteException>()),
        );
        expect(
          () => raw.execute("""
INSERT INTO knowledge_bases VALUES ('other', 'Other', NULL, 1, 1, 'now', 'now');
INSERT INTO knowledge_categories VALUES (
  'global-default', 'other', 'Global', 'global_default', NULL, '', '', 0, 0, NULL, 1, 1, 0, 'now', 'now'
);
"""),
          throwsA(isA<SqliteException>()),
        );
        expect(
          () => raw.execute("""
INSERT INTO knowledge_categories VALUES (
  'three', 'base', 'Three', 'Invalid', NULL, '', '', 0, 0, NULL, 0, 1, 1, 'now', 'now'
);
"""),
          throwsA(isA<SqliteException>()),
        );
      } finally {
        raw.close();
      }
      await storage.deleteKnowledgeCategoryRow('one');
      expect((await storage.loadDataFile('knowledge.json'))!['settings'], {
        'updatedAt': isA<String>(),
      });
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('schema 25 migration derives eligible knowledge settings', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_knowledge_settings_migration_',
    );
    final storageRoot = Directory('${root.path}/storage_v2');
    await storageRoot.create(recursive: true);
    final raw = sqlite3.open('${storageRoot.path}/app.db');
    try {
      raw.execute('PRAGMA foreign_keys = ON');
      raw.execute('''
CREATE TABLE knowledge_bases (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  enabled INTEGER NOT NULL DEFAULT 1,
  sort_order INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE knowledge_categories (
  id TEXT PRIMARY KEY,
  knowledge_base_id TEXT NOT NULL REFERENCES knowledge_bases(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  alias TEXT NOT NULL UNIQUE,
  description TEXT,
  annotation_rule TEXT NOT NULL,
  explanation_prompt TEXT NOT NULL,
  color_value INTEGER NOT NULL,
  auto_annotate INTEGER NOT NULL,
  model_config_id TEXT,
  is_default INTEGER NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  sort_order INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
INSERT INTO knowledge_bases VALUES
  ('disabled-base', 'Disabled', NULL, 0, 0, 'now', 'now'),
  ('enabled-base', 'Enabled', NULL, 1, 1, 'now', 'now');
INSERT INTO knowledge_categories VALUES
  ('legacy-default', 'disabled-base', 'Legacy', 'legacy', NULL, '', '', 0, 1, NULL, 1, 1, 0, 'now', 'now'),
  ('manual', 'enabled-base', 'Manual', 'manual', NULL, '', '', 0, 0, NULL, 0, 1, 0, 'now', 'now'),
  ('eligible', 'enabled-base', 'Eligible', 'eligible', NULL, '', '', 0, 1, NULL, 0, 1, 1, 'now', 'now');
PRAGMA user_version = 25;
''');
    } finally {
      raw.close();
    }

    final storage = StorageV2Database(storageRoot);
    try {
      final knowledge = await storage.loadDataFile('knowledge.json');
      expect(knowledge!['settings'], {
        'defaultKnowledgeBaseId': 'enabled-base',
        'defaultCategoryId': 'eligible',
        'updatedAt': isA<String>(),
      });
      final migrated = sqlite3.open('${storageRoot.path}/app.db');
      try {
        expect(migrated.userVersion, 26);
        expect(
          () => migrated.execute(
            "INSERT INTO knowledge_settings VALUES (2, 'enabled-base', 'eligible', 'now')",
          ),
          throwsA(isA<SqliteException>()),
        );
        expect(
          () => migrated.execute(
            "UPDATE knowledge_settings SET default_category_id = NULL WHERE id = 1",
          ),
          throwsA(isA<SqliteException>()),
        );
      } finally {
        migrated.close();
      }
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}
