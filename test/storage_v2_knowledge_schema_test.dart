import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/storage_v2_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'schema omits knowledge defaults and keeps category constraints',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_knowledge_schema_',
      );
      final storageRoot = Directory('${root.path}/storage_v2');
      await storageRoot.create(recursive: true);
      final storage = StorageV2Database(storageRoot);
      try {
        final knowledge = await storage.loadDataFile('knowledge.json');
        expect(knowledge, isNot(contains('settings')));
        final raw = sqlite3.open('${storageRoot.path}/app.db');
        try {
          expect(raw.userVersion, StorageV2DriftDatabase.currentSchemaVersion);
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
          expect(columns, isNot(contains('is_default')));
          expect(
            raw.select(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'knowledge_settings'",
            ),
            isEmpty,
          );
          expect(
            raw.select(
              "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_knowledge_categories_default'",
            ),
            isEmpty,
          );
          raw.execute('''
INSERT INTO knowledge_bases VALUES ('base', 'Base', NULL, 1, 0, 'now', 'now');
INSERT INTO knowledge_categories VALUES (
  'one', 'base', 'One', 'valid_alias', NULL, '', '', 0, 1, NULL, 1, 0, 'now', 'now'
);
''');
          expect(
            () => raw.execute('''
INSERT INTO knowledge_categories VALUES (
  'two', 'base', 'Two', 'valid_alias', NULL, '', '', 0, 0, NULL, 1, 1, 'now', 'now'
);
'''),
            throwsA(isA<SqliteException>()),
          );
        } finally {
          raw.close();
        }
      } finally {
        await storage.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test('schema 26 migration preserves category links and reseeds cloud scopes', () async {
    final root = await Directory.systemTemp.createTemp('lynai_knowledge_v27_');
    final storageRoot = Directory('${root.path}/storage_v2');
    await storageRoot.create(recursive: true);
    final raw = sqlite3.open('${storageRoot.path}/app.db');
    try {
      raw.execute('PRAGMA foreign_keys = ON');
      raw.execute('''
CREATE TABLE knowledge_bases (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT,
  enabled INTEGER NOT NULL DEFAULT 1, sort_order INTEGER NOT NULL,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE knowledge_categories (
  id TEXT PRIMARY KEY,
  knowledge_base_id TEXT NOT NULL REFERENCES knowledge_bases(id) ON DELETE CASCADE,
  name TEXT NOT NULL, alias TEXT NOT NULL UNIQUE, description TEXT,
  annotation_rule TEXT NOT NULL, explanation_prompt TEXT NOT NULL,
  color_value INTEGER NOT NULL, auto_annotate INTEGER NOT NULL,
  model_config_id TEXT, is_default INTEGER NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1, sort_order INTEGER NOT NULL,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE knowledge_entries (
  id TEXT PRIMARY KEY,
  knowledge_base_id TEXT NOT NULL REFERENCES knowledge_bases(id) ON DELETE CASCADE,
  category_id TEXT REFERENCES knowledge_categories(id) ON DELETE SET NULL,
  title TEXT NOT NULL, content TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1,
  sort_order INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE knowledge_settings (
  id INTEGER PRIMARY KEY, default_knowledge_base_id TEXT,
  default_category_id TEXT, updated_at TEXT NOT NULL
);
CREATE TABLE sync_state (
  scope TEXT PRIMARY KEY, since INTEGER NOT NULL DEFAULT 0,
  initialized INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 0,
  captures_local INTEGER NOT NULL DEFAULT 0, device_id TEXT NOT NULL DEFAULT '',
  generation INTEGER NOT NULL DEFAULT 0,
  full_reseed_required INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL
);
CREATE TABLE sync_outbox (
  scope TEXT NOT NULL, table_name TEXT NOT NULL, record_id TEXT NOT NULL,
  op TEXT NOT NULL, data_json TEXT, selection_data_json TEXT,
  change_id TEXT NOT NULL, device_id TEXT NOT NULL,
  client_created_at TEXT NOT NULL, mutation_version INTEGER NOT NULL,
  updated_at TEXT NOT NULL, PRIMARY KEY(scope, table_name, record_id)
);
CREATE TABLE transport_change_heads (
  table_name TEXT NOT NULL, record_id TEXT NOT NULL, op TEXT NOT NULL,
  data_json TEXT, selection_data_json TEXT, change_id TEXT NOT NULL,
  device_id TEXT NOT NULL, client_created_at TEXT NOT NULL,
  mutation_version INTEGER NOT NULL, source TEXT NOT NULL, source_scope TEXT,
  lineage TEXT, route_scope TEXT, updated_at TEXT NOT NULL,
  PRIMARY KEY(table_name, record_id)
);
CREATE TABLE cloud_index_objects (
  scope TEXT NOT NULL, category TEXT NOT NULL, object_id TEXT NOT NULL,
  content_hash TEXT NOT NULL, object_json TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL, PRIMARY KEY(scope, category, object_id)
);
CREATE TABLE cloud_index_category_stats (
  scope TEXT NOT NULL, category TEXT NOT NULL, object_count INTEGER NOT NULL,
  updated_at TEXT NOT NULL, PRIMARY KEY(scope, category)
);
INSERT INTO knowledge_bases VALUES ('base', 'Base', NULL, 1, 0, 'now', 'now');
INSERT INTO knowledge_categories VALUES
  ('category', 'base', 'Category', 'category', NULL, '', '', 0, 1, NULL, 1, 1, 0, 'now', 'now');
INSERT INTO knowledge_entries VALUES
  ('entry', 'base', 'category', 'Entry', '', 1, 0, 'now', 'now');
INSERT INTO knowledge_settings VALUES (1, 'base', 'category', 'now');
INSERT INTO sync_state VALUES
  ('https://cloud.example|user', 3, 1, 1, 1, 'device', 1, 0, 'now'),
  ('lan:v1', 0, 1, 1, 1, 'device', 0, 0, 'now');
INSERT INTO sync_outbox VALUES
  ('https://cloud.example|user', 'knowledge_settings', 'global', 'upsert', '${jsonEncode({'id': 'global'})}', NULL, 'cloud-change', 'device', 'now', 1, 'now');
INSERT INTO transport_change_heads VALUES
  ('knowledge_settings', 'global', 'upsert', '${jsonEncode({'id': 'global'})}', NULL, 'lan-change', 'device', 'now', 1, 'local', 'lan:v1', NULL, NULL, 'now');
INSERT INTO cloud_index_objects VALUES
  ('https://cloud.example|user', 'knowledge', 'global', 'hash', '{}', 'now');
INSERT INTO cloud_index_category_stats VALUES
  ('https://cloud.example|user', 'knowledge', 1, 'now');
PRAGMA user_version = 26;
''');
    } finally {
      raw.close();
    }

    final storage = StorageV2Database(storageRoot);
    try {
      final knowledge = await storage.loadDataFile('knowledge.json');
      expect(knowledge!['categories'], hasLength(1));
      expect(
        (knowledge['categories'] as List).single,
        isNot(contains('isDefault')),
      );
      expect((knowledge['entries'] as List).single['categoryId'], 'category');
      final migrated = sqlite3.open('${storageRoot.path}/app.db');
      try {
        expect(migrated.userVersion, StorageV2DriftDatabase.currentSchemaVersion);
        expect(migrated.select('PRAGMA foreign_key_check'), isEmpty);
        expect(
          migrated.select(
            "SELECT * FROM sync_outbox WHERE table_name = 'knowledge_settings'",
          ),
          isEmpty,
        );
        expect(
          migrated.select(
            "SELECT * FROM transport_change_heads WHERE table_name = 'knowledge_settings'",
          ),
          isEmpty,
        );
        expect(
          migrated.select(
            "SELECT * FROM cloud_index_objects WHERE category = 'knowledge' AND object_id = 'global'",
          ),
          isEmpty,
        );
        expect(
          migrated.select(
            "SELECT * FROM cloud_index_category_stats WHERE category = 'knowledge'",
          ),
          isEmpty,
        );
        expect(
          migrated
              .select(
                "SELECT full_reseed_required FROM sync_state WHERE scope = 'https://cloud.example|user'",
              )
              .single['full_reseed_required'],
          1,
        );
        expect(
          migrated
              .select(
                "SELECT full_reseed_required FROM sync_state WHERE scope = 'lan:v1'",
              )
              .single['full_reseed_required'],
          0,
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
