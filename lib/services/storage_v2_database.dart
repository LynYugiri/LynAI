import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

import '../models/model_config.dart';
import '../models/merge_models.dart';
import '../models/shared_sync_models.dart';
import '../models/sync_change.dart';

part 'storage_v2_database.g.dart';

class StorageMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class AppSettingsRows extends Table {
  @override
  String get tableName => 'app_settings';

  IntColumn get id => integer()();
  TextColumn get settingsJson => text().named('settings_json')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class ModelConfigRows extends Table {
  @override
  String get tableName => 'model_configs';

  TextColumn get id => text()();
  TextColumn get configJson => text().named('config_json')();
  TextColumn get category => text()();
  IntColumn get enabled => integer()();
  IntColumn get priority => integer()();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class ResourceRows extends Table {
  @override
  String get tableName => 'resources';

  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get role => text()();
  TextColumn get originalPath => text().named('original_path')();
  TextColumn get originalName => text().named('original_name')();
  TextColumn get relativePath => text().named('relative_path').nullable()();
  TextColumn get mimeType => text().named('mime_type')();
  IntColumn get size => integer()();
  TextColumn get sha256 => text().nullable()();
  IntColumn get missing => integer()();
  TextColumn get createdAt => text().named('created_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class ConversationRows extends Table {
  @override
  String get tableName => 'conversations';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get modelId => text().named('model_id')();
  TextColumn get settingsJson => text().named('settings_json')();
  TextColumn get agentPlanJson => text().named('agent_plan_json').nullable()();
  TextColumn get agentWorkingMemoryJson =>
      text().named('agent_working_memory_json').nullable()();
  TextColumn get roleId => text().named('role_id')();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class MessageRows extends Table {
  @override
  String get tableName => 'messages';

  TextColumn get id => text()();
  TextColumn get conversationId => text().named('conversation_id')();
  TextColumn get role => text()();
  TextColumn get content => text()();
  TextColumn get thinkingContent =>
      text().named('thinking_content').nullable()();
  TextColumn get agentTraceJson =>
      text().named('agent_trace_json').nullable()();
  TextColumn get timestamp => text()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get updatedAt =>
      text().named('updated_at').withDefault(const Constant(''))();
  IntColumn get sortOrder =>
      integer().named('sort_order').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class MessageAttachmentRows extends Table {
  @override
  String get tableName => 'message_attachments';

  TextColumn get id => text()();
  TextColumn get messageId => text().named('message_id')();
  TextColumn get resourceId => text().named('resource_id').nullable()();
  TextColumn get displayName => text().named('display_name')();
  TextColumn get mimeType => text().named('mime_type')();
  IntColumn get size => integer()();
  IntColumn get sortOrder =>
      integer().named('sort_order').withDefault(const Constant(0))();
  TextColumn get legacyPath => text().named('legacy_path').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class NoteFolderRows extends Table {
  @override
  String get tableName => 'note_folders';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();
  IntColumn get sortOrder => integer().named('sort_order')();

  @override
  Set<Column> get primaryKey => {id};
}

class NoteRows extends Table {
  @override
  String get tableName => 'notes';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get folderId => text().named('folder_id').nullable()();
  TextColumn get currentRevisionId =>
      text().named('current_revision_id').nullable()();
  TextColumn get currentPageId => text().named('current_page_id').nullable()();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();
  IntColumn get wrap => integer()();
  IntColumn get sortOrder => integer().named('sort_order')();

  @override
  Set<Column> get primaryKey => {id};
}

class NotePageRows extends Table {
  @override
  String get tableName => 'note_pages';

  TextColumn get id => text()();
  TextColumn get noteId => text().named('note_id')();
  TextColumn get title => text()();
  TextColumn get fileName => text().named('file_name')();
  TextColumn get relativePath => text().named('relative_path')();
  TextColumn get currentRevisionId =>
      text().named('current_revision_id').nullable()();
  IntColumn get sortOrder => integer().named('sort_order')();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class NoteRevisionRows extends Table {
  @override
  String get tableName => 'note_revisions';

  TextColumn get id => text()();
  TextColumn get noteId => text().named('note_id')();
  TextColumn get pageId => text().named('page_id').nullable()();
  TextColumn get parentIdsJson => text().named('parent_ids_json')();
  TextColumn get authorDeviceId => text().named('author_device_id')();
  TextColumn get contentHash => text().named('content_hash')();
  TextColumn get createdAt => text().named('created_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class NotePageHeadRows extends Table {
  @override
  String get tableName => 'note_page_heads';

  TextColumn get id => text()();
  TextColumn get pageId => text().named('page_id')();
  TextColumn get headIdsJson => text().named('head_ids_json')();
  TextColumn get selectedHeadId =>
      text().named('selected_head_id').nullable()();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class NotePageTombstoneRows extends Table {
  @override
  String get tableName => 'note_page_tombstones';

  TextColumn get id => text()();
  TextColumn get pageId => text().named('page_id')();
  TextColumn get revisionId => text().named('revision_id')();
  TextColumn get createdAt => text().named('created_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class NotePageConflictRows extends Table {
  @override
  String get tableName => 'note_page_conflicts';

  TextColumn get pageId => text().named('page_id')();
  TextColumn get headIdsJson => text().named('head_ids_json')();
  TextColumn get localHeadId => text().named('local_head_id')();
  TextColumn get incomingHeadId => text().named('incoming_head_id')();
  TextColumn get commonAncestorId =>
      text().named('common_ancestor_id').nullable()();
  TextColumn get createdAt => text().named('created_at')();

  @override
  Set<Column> get primaryKey => {pageId};
}

class NoteEditProposalRows extends Table {
  @override
  String get tableName => 'note_edit_proposals';

  TextColumn get id => text()();
  TextColumn get noteId => text().named('note_id')();
  TextColumn get pageId => text().named('page_id').nullable()();
  TextColumn get baseRevisionId =>
      text().named('base_revision_id').nullable()();
  TextColumn get baseContentHash => text().named('base_content_hash')();
  TextColumn get createdAt => text().named('created_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class NoteEditBlockRows extends Table {
  @override
  String get tableName => 'note_edit_blocks';

  TextColumn get id => text()();
  TextColumn get proposalId => text().named('proposal_id')();
  IntColumn get startLine => integer().named('start_line')();
  IntColumn get deleteCount => integer().named('delete_count')();
  TextColumn get deletedLinesJson => text().named('deleted_lines_json')();
  TextColumn get insertLinesJson => text().named('insert_lines_json')();
  IntColumn get sortOrder => integer().named('sort_order')();

  @override
  Set<Column> get primaryKey => {id};
}

class ScheduleRows extends Table {
  @override
  String get tableName => 'schedules';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get startTime => text().named('start_time')();
  TextColumn get endTime => text().named('end_time')();
  TextColumn get note => text().nullable()();
  TextColumn get kind => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class TodoListRows extends Table {
  @override
  String get tableName => 'todo_lists';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class TodoItemRows extends Table {
  @override
  String get tableName => 'todo_items';

  TextColumn get id => text()();
  TextColumn get listId => text().named('list_id')();
  TextColumn get itemText => text().named('text')();
  IntColumn get done => integer()();
  IntColumn get sortOrder => integer().named('sort_order')();
  TextColumn get updatedAt =>
      text().named('updated_at').withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 角色演绎场景（可复用模板）。从 storage_meta JSON 迁移到专用表，
/// 支持按行 upsert/delete 用于增量同步。
class RoleplayScenarioRows extends Table {
  @override
  String get tableName => 'roleplay_scenarios';

  TextColumn get id => text()();
  TextColumn get dataJson => text().named('data_json')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

/// 角色演绎线程（独立会话快照）。从 storage_meta JSON 迁移到专用表。
class RoleplayThreadRows extends Table {
  @override
  String get tableName => 'roleplay_threads';

  TextColumn get id => text()();
  TextColumn get dataJson => text().named('data_json')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

/// 回收站条目。从 storage_meta JSON 迁移到专用表。
class RecycleBinRows extends Table {
  @override
  String get tableName => 'recycle_bin';

  TextColumn get id => text()();
  TextColumn get owner => text()();
  TextColumn get category => text()();
  TextColumn get type => text()();
  TextColumn get title => text()();
  TextColumn get preview => text()();
  TextColumn get payloadJson => text().named('payload_json')();
  TextColumn get deletedAt => text().named('deleted_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncOutboxRows extends Table {
  @override
  String get tableName => 'sync_outbox';

  TextColumn get scope => text()();
  TextColumn get table => text().named('table_name')();
  TextColumn get recordId => text().named('record_id')();
  TextColumn get op => text()();
  TextColumn get dataJson => text().named('data_json').nullable()();
  TextColumn get changeId => text().named('change_id')();
  TextColumn get deviceId => text().named('device_id')();
  TextColumn get clientCreatedAt => text().named('client_created_at')();
  IntColumn get mutationVersion => integer().named('mutation_version')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {scope, table, recordId};
}

class SyncConflictRows extends Table {
  @override
  String get tableName => 'sync_conflicts';

  TextColumn get scope => text()();
  IntColumn get seq => integer()();
  TextColumn get table => text().named('table_name')();
  TextColumn get recordId => text().named('record_id')();
  TextColumn get op => text()();
  TextColumn get dataJson => text().named('data_json').nullable()();
  TextColumn get changeId => text().named('change_id')();
  TextColumn get deviceId => text().named('device_id')();
  TextColumn get clientCreatedAt => text().named('client_created_at')();
  TextColumn get createdAt => text().named('created_at').nullable()();
  TextColumn get localOp => text().named('local_op')();
  TextColumn get localDataJson => text().named('local_data_json').nullable()();
  TextColumn get localChangeId => text().named('local_change_id')();
  IntColumn get localMutationVersion =>
      integer().named('local_mutation_version')();

  @override
  Set<Column> get primaryKey => {scope, seq};
}

class SyncStateRows extends Table {
  @override
  String get tableName => 'sync_state';

  TextColumn get scope => text()();
  IntColumn get since => integer().withDefault(const Constant(0))();
  BoolColumn get initialized => boolean().withDefault(const Constant(false))();
  BoolColumn get active => boolean().withDefault(const Constant(false))();
  BoolColumn get capturesLocal =>
      boolean().named('captures_local').withDefault(const Constant(false))();
  TextColumn get deviceId =>
      text().named('device_id').withDefault(const Constant(''))();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {scope};
}

class SyncScopeBaselineRows extends Table {
  @override
  String get tableName => 'sync_scope_baselines';

  TextColumn get scope => text()();
  TextColumn get table => text().named('table_name')();
  TextColumn get recordId => text().named('record_id')();
  TextColumn get dataJson => text().named('data_json')();

  @override
  Set<Column> get primaryKey => {scope, table, recordId};
}

class SyncAppliedChangeRows extends Table {
  @override
  String get tableName => 'sync_applied_changes';

  TextColumn get changeId => text().named('change_id')();
  TextColumn get source => text()();
  TextColumn get appliedAt => text().named('applied_at')();

  @override
  Set<Column> get primaryKey => {changeId};
}

@DriftDatabase(
  tables: [
    StorageMeta,
    AppSettingsRows,
    ModelConfigRows,
    ResourceRows,
    ConversationRows,
    MessageRows,
    MessageAttachmentRows,
    NoteFolderRows,
    NoteRows,
    NotePageRows,
    NoteRevisionRows,
    NotePageHeadRows,
    NotePageTombstoneRows,
    NotePageConflictRows,
    NoteEditProposalRows,
    NoteEditBlockRows,
    ScheduleRows,
    TodoListRows,
    TodoItemRows,
    RoleplayScenarioRows,
    RoleplayThreadRows,
    RecycleBinRows,
    SyncOutboxRows,
    SyncConflictRows,
    SyncStateRows,
    SyncScopeBaselineRows,
    SyncAppliedChangeRows,
  ],
)
class StorageV2DriftDatabase extends _$StorageV2DriftDatabase {
  StorageV2DriftDatabase(File file) : super(_open(file));

  static QueryExecutor _open(File file) {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    return NativeDatabase.createInBackground(file);
  }

  /// Version of app.db's internal SQLite schema.
  ///
  /// This is separate from [StorageV2Service.currentLayoutVersion], which
  /// describes the storage_v2 directory layout.
  @override
  int get schemaVersion => 14;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA busy_timeout = 5000');
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(notePageRows, notePageRows.currentRevisionId);
      }
      if (from < 3) {
        await _addColumnIfMissing(
          'note_folders',
          'sort_order',
          'INTEGER NOT NULL DEFAULT 0',
        );
        await _addColumnIfMissing(
          'notes',
          'sort_order',
          'INTEGER NOT NULL DEFAULT 0',
        );
      }
      if (from < 4) {
        await _addColumnIfMissing('conversations', 'agent_plan_json', 'TEXT');
        await _addColumnIfMissing(
          'conversations',
          'agent_working_memory_json',
          'TEXT',
        );
        await _addColumnIfMissing('messages', 'agent_trace_json', 'TEXT');
      }
      // v5: add dedicated tables for roleplay and recycle bin.
      // Data is migrated lazily — the load methods fall back to
      // storage_meta JSON if the new tables are empty.
      if (from < 5) {
        await m.createTable(roleplayScenarioRows);
        await m.createTable(roleplayThreadRows);
        await m.createTable(recycleBinRows);
      }
      if (from < 6) {
        await m.createTable(syncOutboxRows);
        await m.createTable(syncStateRows);
      }
      if (from < 7) {
        await _addColumnIfMissing(
          'sync_outbox',
          'change_id',
          "TEXT NOT NULL DEFAULT ''",
        );
        await _addColumnIfMissing(
          'sync_outbox',
          'device_id',
          "TEXT NOT NULL DEFAULT ''",
        );
        await _addColumnIfMissing(
          'sync_outbox',
          'client_created_at',
          "TEXT NOT NULL DEFAULT ''",
        );
        await m.createTable(syncConflictRows);
      }
      if (from < 8) {
        await _migrateNoteRevisionDag();
      }
      if (from < 9) {
        await m.createTable(syncAppliedChangeRows);
      }
      if (from < 10) {
        await _addColumnIfMissing(
          'messages',
          'revision',
          'INTEGER NOT NULL DEFAULT 1',
        );
        await _addColumnIfMissing(
          'messages',
          'updated_at',
          "TEXT NOT NULL DEFAULT ''",
        );
        await _addColumnIfMissing(
          'todo_items',
          'updated_at',
          "TEXT NOT NULL DEFAULT ''",
        );
        await _addColumnIfMissing(
          'sync_conflicts',
          'local_op',
          "TEXT NOT NULL DEFAULT 'upsert'",
        );
        await _addColumnIfMissing('sync_conflicts', 'local_data_json', 'TEXT');
        await _addColumnIfMissing(
          'sync_conflicts',
          'local_change_id',
          "TEXT NOT NULL DEFAULT ''",
        );
        await _addColumnIfMissing(
          'sync_conflicts',
          'local_mutation_version',
          'INTEGER NOT NULL DEFAULT 0',
        );
      }
      if (from < 11) {
        await _addColumnIfMissing(
          'sync_state',
          'device_id',
          "TEXT NOT NULL DEFAULT ''",
        );
        await customStatement('''
UPDATE sync_state
SET device_id = COALESCE((
  SELECT device_id FROM sync_outbox
  WHERE sync_outbox.scope = sync_state.scope AND device_id <> ''
  LIMIT 1
), device_id)
''');
      }
      if (from < 12) {
        await _addColumnIfMissing(
          'note_page_conflicts',
          'local_head_id',
          "TEXT NOT NULL DEFAULT ''",
        );
        await _addColumnIfMissing(
          'note_page_conflicts',
          'incoming_head_id',
          "TEXT NOT NULL DEFAULT ''",
        );
        await customStatement('''
UPDATE note_page_conflicts
SET local_head_id = COALESCE(json_extract(head_ids_json, '\$[0]'), ''),
    incoming_head_id = COALESCE(json_extract(head_ids_json, '\$[1]'), '')
WHERE local_head_id = '' OR incoming_head_id = ''
''');
      }
      if (from < 13) {
        await _addColumnIfMissing(
          'sync_state',
          'active',
          'INTEGER NOT NULL DEFAULT 0',
        );
        await m.createTable(syncScopeBaselineRows);
      }
      if (from < 14) {
        await _addColumnIfMissing(
          'sync_state',
          'captures_local',
          'INTEGER NOT NULL DEFAULT 0',
        );
        if (await _tableExists('sync_state')) {
          await customStatement('''
UPDATE sync_state
SET captures_local = active
''');
        }
        if (await _tableExists('sync_scope_baselines')) {
          await customStatement('DELETE FROM sync_scope_baselines');
        }
      }
    },
  );

  Future<void> _migrateNoteRevisionDag() async {
    final legacyExists = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'note_revisions'",
    ).getSingleOrNull();
    if (legacyExists != null) {
      await customStatement(
        'ALTER TABLE note_revisions RENAME TO note_revisions_legacy',
      );
    }
    await customStatement('''
CREATE TABLE note_revisions (
  id TEXT PRIMARY KEY NOT NULL,
  note_id TEXT NOT NULL,
  page_id TEXT,
  parent_ids_json TEXT NOT NULL,
  author_device_id TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE
)
''');
    await customStatement('''
CREATE TABLE note_page_heads (
  id TEXT PRIMARY KEY NOT NULL,
  page_id TEXT NOT NULL UNIQUE,
  head_ids_json TEXT NOT NULL,
  selected_head_id TEXT,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (page_id) REFERENCES note_pages(id) ON DELETE CASCADE
)
''');
    await customStatement('''
CREATE TABLE note_page_tombstones (
  id TEXT PRIMARY KEY NOT NULL,
  page_id TEXT NOT NULL,
  revision_id TEXT NOT NULL,
  created_at TEXT NOT NULL
)
''');
    await customStatement('''
CREATE TABLE note_page_conflicts (
  page_id TEXT PRIMARY KEY NOT NULL,
  head_ids_json TEXT NOT NULL,
  local_head_id TEXT NOT NULL,
  incoming_head_id TEXT NOT NULL,
  common_ancestor_id TEXT,
  created_at TEXT NOT NULL
)
''');
    await customStatement(
      'CREATE INDEX idx_note_revisions_page_created ON note_revisions(page_id, created_at)',
    );
    await customStatement(
      'CREATE INDEX idx_note_revisions_content_hash ON note_revisions(content_hash)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX idx_note_page_heads_page ON note_page_heads(page_id)',
    );
    await customStatement(
      'CREATE INDEX idx_note_page_tombstones_page ON note_page_tombstones(page_id)',
    );
  }

  Future<void> _addColumnIfMissing(
    String table,
    String column,
    String definition,
  ) async {
    final existing = await customSelect('PRAGMA table_info($table)').get();
    if (existing.isEmpty) return;
    final hasColumn = existing.any((row) => row.data['name'] == column);
    if (!hasColumn) {
      await customStatement(
        'ALTER TABLE $table ADD COLUMN $column $definition',
      );
    }
  }

  Future<bool> _tableExists(String table) async =>
      await customSelect(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        variables: [Variable.withString(table)],
      ).getSingleOrNull() !=
      null;
}

class StorageV2Database {
  StorageV2Database(this.storageRoot);

  static final Map<String, StorageV2DriftDatabase> _openDatabases = {};
  // Multiple repository facades can point at the same app.db during startup.
  // Reference counts prevent one facade from closing another facade's handle.
  static final Map<String, int> _openReferenceCounts = {};
  static final Map<String, Future<StorageV2DriftDatabase>> _pendingOpens = {};
  static const _uuid = Uuid();

  final Directory storageRoot;
  StorageV2DriftDatabase? _db;

  File get file => File('${storageRoot.path}/app.db');

  Future<bool> exists() async => file.exists();

  Future<void> close() async {
    final existing = _db;
    if (existing != null) {
      final path = file.absolute.path;
      final references = _openReferenceCounts[path] ?? 1;
      if (references <= 1) {
        _openReferenceCounts.remove(path);
        _openDatabases.remove(path);
        await existing.close();
      } else {
        _openReferenceCounts[path] = references - 1;
      }
    }
    _db = null;
  }

  Future<Map<String, dynamic>?> loadDataFile(String fileName) async {
    final db = await _open();
    return switch (fileName) {
      'app_settings.json' => await _loadAppSettings(db),
      'model_configs.json' => await _loadModelConfigs(db),
      'conversations.json' => await _loadConversations(db),
      'notes.json' => await _loadNotes(db),
      'schedules.json' => await _loadSchedules(db),
      'todo_lists.json' => await _loadTodoLists(db),
      'resources.json' => await _loadResources(db),
      'roleplay_scenarios.json' => await _loadRoleplayScenarios(db),
      'roleplay_threads.json' => await _loadRoleplayThreads(db),
      'recycle_bin.json' => await _loadRecycleBin(db),
      _ => await _loadGenericDataFile(db, fileName),
    };
  }

  Future<void> writeDataFile(String fileName, Map<String, dynamic> data) async {
    final db = await _open();
    await db.transaction(() async {
      final tables = _syncTablesForFile(fileName);
      final before = await _syncSnapshot(db, tables);
      switch (fileName) {
        case 'app_settings.json':
          await _replaceAppSettings(db, data);
        case 'model_configs.json':
          await _replaceModelConfigs(db, data);
        case 'conversations.json':
          await _replaceConversations(db, data);
        case 'notes.json':
          await _replaceNotes(db, data);
        case 'schedules.json':
          await _replaceSchedules(db, data);
        case 'todo_lists.json':
          await _replaceTodoLists(db, data);
        case 'resources.json':
          await _replaceResources(db, data);
        case 'roleplay_scenarios.json':
          await _replaceRoleplayScenarios(db, data);
        case 'roleplay_threads.json':
          await _replaceRoleplayThreads(db, data);
        case 'recycle_bin.json':
          await _replaceRecycleBin(db, data);
        default:
          await _replaceGenericDataFile(db, fileName, data);
      }
      final after = await _syncSnapshot(db, tables);
      await _recordSnapshotDiff(db, before, after);
      await _setMeta(
        db,
        'data.$fileName.updatedAt',
        DateTime.now().toIso8601String(),
      );
    });
  }

  // ─── Incremental per-row operations ───
  //
  // These methods complement the full-replace writeDataFile. They use
  // INSERT ON CONFLICT UPDATE (upsert) and targeted DELETE to avoid
  // wiping entire tables on every save. The full-replace methods remain
  // for backup/restore/first-sync; normal runtime mutations go through
  // these incremental methods.

  Future<void> upsertConversationRow(
    Map<String, dynamic> json, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return;
    await db
        .into(db.conversationRows)
        .insertOnConflictUpdate(
          ConversationRowsCompanion.insert(
            id: id,
            title: json['title'] as String? ?? '',
            modelId: json['modelId'] as String? ?? '',
            settingsJson: jsonEncode(json['settings'] ?? const {}),
            agentPlanJson: Value(
              json['agentPlan'] == null ? null : jsonEncode(json['agentPlan']),
            ),
            agentWorkingMemoryJson: Value(
              json['agentWorkingMemory'] == null
                  ? null
                  : jsonEncode(json['agentWorkingMemory']),
            ),
            roleId: json['roleId'] as String? ?? 'default',
            createdAt: json['createdAt'] as String? ?? '',
            updatedAt: json['updatedAt'] as String? ?? '',
          ),
        );
  }

  Future<void> deleteConversationRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await (db.delete(db.conversationRows)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertMessageRow(
    Map<String, dynamic> json, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return;
    await db
        .into(db.messageRows)
        .insertOnConflictUpdate(
          MessageRowsCompanion.insert(
            id: id,
            conversationId: json['conversationId'] as String? ?? '',
            role: json['role'] as String? ?? '',
            content: json['content'] as String? ?? '',
            thinkingContent: Value(json['thinkingContent'] as String?),
            agentTraceJson: Value(
              json['agentTrace'] == null
                  ? null
                  : jsonEncode(json['agentTrace']),
            ),
            timestamp: json['timestamp'] as String? ?? '',
            revision: Value((json['revision'] as num?)?.toInt() ?? 1),
            updatedAt: Value(
              json['updatedAt'] as String? ??
                  json['timestamp'] as String? ??
                  '',
            ),
            sortOrder: Value((json['sortOrder'] as num?)?.toInt() ?? 0),
          ),
        );
  }

  Future<void> deleteMessageRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await (db.delete(db.messageRows)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertMessageAttachmentRow(
    Map<String, dynamic> json, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return;
    await db
        .into(db.messageAttachmentRows)
        .insertOnConflictUpdate(
          MessageAttachmentRowsCompanion.insert(
            id: id,
            messageId: json['messageId'] as String? ?? '',
            resourceId: Value(json['resourceId'] as String?),
            displayName:
                (json['displayName'] as String?) ??
                (json['name'] as String?) ??
                'file',
            mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
            size: (json['size'] as num?)?.toInt() ?? 0,
            sortOrder: Value((json['sortOrder'] as num?)?.toInt() ?? 0),
            legacyPath: Value(json['path'] as String?),
          ),
        );
  }

  Future<void> deleteMessageAttachmentRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await (db.delete(
      db.messageAttachmentRows,
    )..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertResourceRow(
    Map<String, dynamic> json, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return;
    await db
        .into(db.resourceRows)
        .insertOnConflictUpdate(
          ResourceRowsCompanion.insert(
            id: id,
            kind: json['kind'] as String? ?? 'unknown',
            role: json['role'] as String? ?? 'unknown',
            originalPath: json['originalPath'] as String? ?? '',
            originalName: json['originalName'] as String? ?? 'file',
            relativePath: Value(json['relativePath'] as String?),
            mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
            size: (json['size'] as num?)?.toInt() ?? 0,
            sha256: Value(json['sha256'] as String?),
            missing: json['missing'] == true ? 1 : 0,
            createdAt:
                json['createdAt'] as String? ??
                DateTime.now().toIso8601String(),
          ),
        );
  }

  Future<void> deleteResourceRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await (db.delete(db.resourceRows)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertScheduleRow(
    Map<String, dynamic> json, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return;
    await db
        .into(db.scheduleRows)
        .insertOnConflictUpdate(
          ScheduleRowsCompanion.insert(
            id: id,
            title: json['title'] as String? ?? '',
            startTime:
                json['start'] as String? ?? json['startTime'] as String? ?? '',
            endTime: json['end'] as String? ?? json['endTime'] as String? ?? '',
            note: Value(json['note'] as String?),
            kind: json['kind'] as String? ?? '',
          ),
        );
  }

  Future<void> deleteScheduleRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await (db.delete(db.scheduleRows)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertTodoListRow(
    Map<String, dynamic> json, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return;
    await db
        .into(db.todoListRows)
        .insertOnConflictUpdate(
          TodoListRowsCompanion.insert(
            id: id,
            title: json['title'] as String? ?? '',
            createdAt: json['createdAt'] as String? ?? '',
            updatedAt: json['updatedAt'] as String? ?? '',
          ),
        );
  }

  Future<void> deleteTodoListRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await (db.delete(db.todoListRows)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertTodoItemRow(
    Map<String, dynamic> json, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return;
    await db
        .into(db.todoItemRows)
        .insertOnConflictUpdate(
          TodoItemRowsCompanion.insert(
            id: id,
            listId: json['listId'] as String? ?? '',
            itemText:
                json['text'] as String? ?? json['itemText'] as String? ?? '',
            done: switch (json['done']) {
              true => 1,
              false || null => 0,
              final num value => value.toInt(),
              _ => 0,
            },
            sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
            updatedAt: Value(json['updatedAt'] as String? ?? ''),
          ),
        );
  }

  Future<void> deleteTodoItemRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await (db.delete(db.todoItemRows)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertRoleplayScenarioRow(
    String id,
    Map<String, dynamic> data,
    String updatedAt, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await db
        .into(db.roleplayScenarioRows)
        .insertOnConflictUpdate(
          RoleplayScenarioRowsCompanion.insert(
            id: id,
            dataJson: jsonEncode(data),
            updatedAt: updatedAt,
          ),
        );
  }

  Future<void> deleteRoleplayScenarioRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await (db.delete(
      db.roleplayScenarioRows,
    )..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertRoleplayThreadRow(
    String id,
    Map<String, dynamic> data,
    String updatedAt, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await db
        .into(db.roleplayThreadRows)
        .insertOnConflictUpdate(
          RoleplayThreadRowsCompanion.insert(
            id: id,
            dataJson: jsonEncode(data),
            updatedAt: updatedAt,
          ),
        );
  }

  Future<void> deleteRoleplayThreadRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await (db.delete(
      db.roleplayThreadRows,
    )..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertRecycleBinRow(
    Map<String, dynamic> json, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return;
    await db
        .into(db.recycleBinRows)
        .insertOnConflictUpdate(
          RecycleBinRowsCompanion.insert(
            id: id,
            owner: json['owner'] as String? ?? 'core',
            category: json['category'] as String? ?? '',
            type: json['type'] as String? ?? '',
            title: json['title'] as String? ?? '',
            preview: json['preview'] as String? ?? '',
            payloadJson: jsonEncode(json['payload'] ?? const {}),
            deletedAt: json['deletedAt'] as String? ?? '',
          ),
        );
  }

  Future<void> deleteRecycleBinRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await (db.delete(db.recycleBinRows)..where((t) => t.id.equals(id))).go();
  }

  Future<void> clearRecycleBinRows() async {
    final db = await _open();
    await db.delete(db.recycleBinRows).go();
  }

  Future<void> activateSyncScope(
    String scope, {
    required String deviceId,
  }) async {
    if (scope.isEmpty) return;
    final db = await _open();
    await db.transaction(() async {
      await _migrateLegacySyncTables(db);
      await _repairOutboxIdentity(db, scope, deviceId);
      final sameFamilyExists = await _hasInitializedScopeInFamily(db, scope);
      await _claimLocalCapture(db, scope);
      final state = await (db.select(
        db.syncStateRows,
      )..where((row) => row.scope.equals(scope))).getSingleOrNull();
      if (state?.initialized == true) {
        await (db.delete(
          db.syncScopeBaselineRows,
        )..where((row) => row.scope.equals(scope))).go();
        await (db.update(
          db.syncStateRows,
        )..where((row) => row.scope.equals(scope))).write(
          SyncStateRowsCompanion(
            active: const Value(true),
            capturesLocal: const Value(true),
            deviceId: Value(deviceId),
            updatedAt: Value(DateTime.now().toIso8601String()),
          ),
        );
        await _repairOutboxIdentity(db, scope, deviceId);
        return;
      }
      if (!sameFamilyExists) {
        final snapshot = await _syncSnapshot(db, _syncTableNames);
        for (final table in snapshot.entries) {
          for (final row in table.value.entries) {
            await _putOutbox(
              db,
              scope,
              table.key,
              row.key,
              'upsert',
              row.value,
              deviceId: deviceId,
            );
          }
        }
      }
      await db
          .into(db.syncStateRows)
          .insertOnConflictUpdate(
            SyncStateRowsCompanion.insert(
              scope: scope,
              since: const Value(0),
              initialized: const Value(true),
              active: const Value(true),
              capturesLocal: const Value(true),
              deviceId: Value(deviceId),
              updatedAt: DateTime.now().toIso8601String(),
            ),
          );
    });
  }

  Future<void> deactivateSyncScope(String scope) async {
    if (scope.isEmpty) return;
    final db = await _open();
    await db.transaction(() async {
      final state = await (db.select(
        db.syncStateRows,
      )..where((row) => row.scope.equals(scope))).getSingleOrNull();
      if (state?.initialized != true || state?.active != true) return;
      await (db.delete(
        db.syncScopeBaselineRows,
      )..where((row) => row.scope.equals(scope))).go();
      await (db.update(
        db.syncStateRows,
      )..where((row) => row.scope.equals(scope))).write(
        SyncStateRowsCompanion(
          active: const Value(false),
          updatedAt: Value(DateTime.now().toIso8601String()),
        ),
      );
    });
  }

  Future<int> syncSince(String scope) async {
    final db = await _open();
    final row = await (db.select(
      db.syncStateRows,
    )..where((row) => row.scope.equals(scope))).getSingleOrNull();
    return row?.since ?? 0;
  }

  Future<List<SyncOutboxEntry>> loadSyncOutbox(String scope) async {
    final db = await _open();
    final rows =
        await (db.select(db.syncOutboxRows)
              ..where((row) => row.scope.equals(scope))
              ..orderBy([(row) => OrderingTerm.asc(row.updatedAt)]))
            .get();
    final entries = rows
        .map(
          (row) => SyncOutboxEntry(
            table: row.table,
            recordId: row.recordId,
            op: row.op,
            data: row.dataJson == null
                ? null
                : Map<String, dynamic>.from(jsonDecode(row.dataJson!) as Map),
            changeId: row.changeId,
            deviceId: row.deviceId,
            clientCreatedAt: DateTime.parse(row.clientCreatedAt),
            mutationVersion: row.mutationVersion,
          ),
        )
        .toList(growable: false);
    entries.sort((a, b) {
      final byPriority = _syncOperationPriority(
        a.table,
        a.op,
      ).compareTo(_syncOperationPriority(b.table, b.op));
      return byPriority != 0
          ? byPriority
          : a.clientCreatedAt.compareTo(b.clientCreatedAt);
    });
    return entries;
  }

  Future<void> replacePluginSyncRows(
    String pluginId,
    List<Map<String, dynamic>> rows,
  ) async {
    final db = await _open();
    await db.transaction(() async {
      final scopes = await _activeSyncStates(db);
      const domains = {'plugin_files', 'plugin_settings', 'plugin_config'};
      final next = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        final table = row['domain'] as String? ?? 'plugin_files';
        final id = row['id'] as String?;
        if (!domains.contains(table) || id == null || id.isEmpty) continue;
        next['$table\u0000$id'] = row;
      }
      final existing = await db
          .customSelect(
            "SELECT key, value FROM storage_meta WHERE key LIKE 'sync.plugin.%'",
          )
          .get();
      for (final row in existing) {
        final data = Map<String, dynamic>.from(
          jsonDecode(row.data['value'] as String) as Map,
        );
        if (data['pluginId'] != pluginId) continue;
        final key = row.data['key'] as String;
        final parsed = _pluginSyncMetaParts(key);
        if (parsed == null) continue;
        final composite = '${parsed.$1}\u0000${parsed.$2}';
        if (next.containsKey(composite)) continue;
        await _deleteMeta(db, key);
        for (final scope in scopes) {
          await _putOutbox(
            db,
            scope.scope,
            parsed.$1,
            parsed.$2,
            'delete',
            null,
            deviceId: scope.deviceId,
          );
        }
      }
      for (final entry in next.entries) {
        final separator = entry.key.indexOf('\u0000');
        final table = entry.key.substring(0, separator);
        final id = entry.key.substring(separator + 1);
        await _setMeta(
          db,
          _pluginSyncMetaKey(table, id),
          jsonEncode(entry.value),
        );
        for (final scope in scopes) {
          await _putOutbox(
            db,
            scope.scope,
            table,
            id,
            'upsert',
            entry.value,
            deviceId: scope.deviceId,
          );
        }
      }
    });
  }

  Future<List<Map<String, dynamic>>> loadPluginSyncRows() async {
    final db = await _open();
    final rows = await db
        .customSelect(
          "SELECT value FROM storage_meta WHERE key LIKE 'sync.plugin.%'",
        )
        .get();
    return rows
        .map(
          (row) => Map<String, dynamic>.from(
            jsonDecode(row.data['value'] as String) as Map,
          ),
        )
        .toList(growable: false);
  }

  Future<bool> acknowledgeSyncOutbox(
    String scope,
    List<SyncOutboxEntry> uploaded,
  ) async {
    if (uploaded.isEmpty) return false;
    final db = await _open();
    await db.transaction(() async {
      for (final entry in uploaded) {
        await (db.delete(db.syncOutboxRows)..where(
              (row) =>
                  row.scope.equals(scope) &
                  row.changeId.equals(entry.changeId) &
                  row.mutationVersion.equals(entry.mutationVersion),
            ))
            .go();
      }
    });
    return false;
  }

  Future<List<SyncConflictEntry>> loadSyncConflicts(String scope) async {
    final db = await _open();
    final rows =
        await (db.select(db.syncConflictRows)
              ..where((row) => row.scope.equals(scope))
              ..orderBy([(row) => OrderingTerm.asc(row.seq)]))
            .get();
    return rows
        .map(
          (row) => SyncConflictEntry(
            seq: row.seq,
            table: row.table,
            recordId: row.recordId,
            localOp: row.localOp,
            localData: row.localDataJson == null
                ? null
                : Map<String, dynamic>.from(
                    jsonDecode(row.localDataJson!) as Map,
                  ),
            remoteOp: row.op,
            remoteData: row.dataJson == null
                ? null
                : Map<String, dynamic>.from(jsonDecode(row.dataJson!) as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<void> resolveSyncConflict(
    String scope,
    int seq,
    SyncConflictResolution resolution,
  ) async {
    final db = await _open();
    await db.transaction(() async {
      final conflict =
          await (db.select(db.syncConflictRows)
                ..where((row) => row.scope.equals(scope) & row.seq.equals(seq)))
              .getSingleOrNull();
      if (conflict == null) return;
      final localData = conflict.localDataJson == null
          ? <String, dynamic>{'id': conflict.recordId}
          : Map<String, dynamic>.from(
              jsonDecode(conflict.localDataJson!) as Map,
            );
      final remoteData = conflict.dataJson == null
          ? <String, dynamic>{'id': conflict.recordId}
          : Map<String, dynamic>.from(jsonDecode(conflict.dataJson!) as Map);
      if (resolution == SyncConflictResolution.useRemote) {
        await _applySyncOperation(db, conflict.table, conflict.op, remoteData);
      } else {
        await _applySyncOperation(
          db,
          conflict.table,
          conflict.localOp,
          localData,
        );
        await _putOutbox(
          db,
          scope,
          conflict.table,
          conflict.recordId,
          conflict.localOp,
          conflict.localOp == 'upsert' ? localData : null,
        );
      }
      await (db.delete(
        db.syncConflictRows,
      )..where((row) => row.scope.equals(scope) & row.seq.equals(seq))).go();
    });
  }

  /// 批量执行增量操作（一个事务内）。
  ///
  /// [ops] 是 `(tableName, json, op)` 元组列表，op 为 'upsert' 或 'delete'。
  /// 由 Provider 的防抖 flush 调用，替代全量 writeDataFile。
  Future<void> batchIncremental(
    List<SyncRemoteOperation> ops, {
    bool remote = false,
    String? scope,
    int? nextSince,
    String appliedSource = 'cloud',
  }) async {
    final db = await _open();
    await db.transaction(() async {
      final orderedOps = remote ? List<SyncRemoteOperation>.from(ops) : ops;
      if (remote) {
        orderedOps.sort((a, b) {
          final byPriority = _syncOperationPriority(
            a.table,
            a.op,
          ).compareTo(_syncOperationPriority(b.table, b.op));
          if (byPriority != 0) return byPriority;
          return (a.change?.seq ?? 0).compareTo(b.change?.seq ?? 0);
        });
      }
      for (final op in orderedOps) {
        final changeId = op.change?.changeId;
        if (remote && changeId != null) {
          final existing = await (db.select(
            db.syncAppliedChangeRows,
          )..where((row) => row.changeId.equals(changeId))).getSingleOrNull();
          if (existing != null) continue;
        }
        final id = op.data?['id'] as String?;
        if (!_syncTableNames.contains(op.table)) {
          throw StateError('unsupported remote sync table: ${op.table}');
        }
        if (op.op != 'upsert' && op.op != 'delete') {
          throw StateError('unsupported remote sync operation: ${op.op}');
        }
        if (id == null || id.isEmpty) {
          throw StateError('remote sync operation is missing record id');
        }
        if (remote &&
            scope != null &&
            !_isNoteDagTable(op.table) &&
            await _hasPendingOutbox(db, scope, op.table, id)) {
          final change = op.change;
          if (change == null) {
            throw StateError('remote conflict metadata is missing');
          }
          final local = await _pendingOutbox(db, scope, op.table, id);
          if (local == null) continue;
          final automatic = _automaticConflictAction(
            op.table,
            local.dataJson == null
                ? null
                : Map<String, dynamic>.from(jsonDecode(local.dataJson!) as Map),
            op.data,
          );
          if (automatic == MergeAction.useIncoming ||
              automatic == MergeAction.unchanged) {
            await (db.delete(db.syncOutboxRows)..where(
                  (row) =>
                      row.scope.equals(scope) &
                      row.table.equals(op.table) &
                      row.recordId.equals(id),
                ))
                .go();
          } else if (automatic == MergeAction.keepLocal) {
            continue;
          } else {
            await db
                .into(db.syncConflictRows)
                .insertOnConflictUpdate(
                  SyncConflictRowsCompanion.insert(
                    scope: scope,
                    seq: change.seq,
                    table: op.table,
                    recordId: id,
                    op: op.op,
                    dataJson: Value(
                      op.data == null ? null : jsonEncode(op.data),
                    ),
                    changeId: change.changeId,
                    deviceId: change.deviceId,
                    clientCreatedAt: change.clientCreatedAt.toIso8601String(),
                    createdAt: Value(change.createdAt?.toIso8601String()),
                    localOp: local.op,
                    localDataJson: Value(local.dataJson),
                    localChangeId: local.changeId,
                    localMutationVersion: local.mutationVersion,
                  ),
                );
            await (db.delete(db.syncOutboxRows)..where(
                  (row) =>
                      row.scope.equals(scope) &
                      row.table.equals(op.table) &
                      row.recordId.equals(id),
                ))
                .go();
            continue;
          }
        }
        if (remote && scope != null && !_isNoteDagTable(op.table)) {
          final existingConflict =
              await (db.select(db.syncConflictRows)..where(
                    (row) =>
                        row.scope.equals(scope) &
                        row.table.equals(op.table) &
                        row.recordId.equals(id),
                  ))
                  .getSingleOrNull();
          if (existingConflict != null) {
            final change = op.change;
            if (change == null) {
              throw StateError('remote conflict metadata is missing');
            }
            await (db.delete(db.syncConflictRows)..where(
                  (row) =>
                      row.scope.equals(scope) &
                      row.table.equals(op.table) &
                      row.recordId.equals(id),
                ))
                .go();
            await db
                .into(db.syncConflictRows)
                .insert(
                  SyncConflictRowsCompanion.insert(
                    scope: scope,
                    seq: change.seq,
                    table: op.table,
                    recordId: id,
                    op: op.op,
                    dataJson: Value(
                      op.data == null ? null : jsonEncode(op.data),
                    ),
                    changeId: change.changeId,
                    deviceId: change.deviceId,
                    clientCreatedAt: change.clientCreatedAt.toIso8601String(),
                    createdAt: Value(change.createdAt?.toIso8601String()),
                    localOp: existingConflict.localOp,
                    localDataJson: Value(existingConflict.localDataJson),
                    localChangeId: existingConflict.localChangeId,
                    localMutationVersion: existingConflict.localMutationVersion,
                  ),
                );
            continue;
          }
        }
        switch (op.table) {
          case 'resources':
            if (op.op == 'upsert' && op.data != null) {
              await upsertResourceRow(op.data!, transactionDb: db);
            } else if (op.op == 'delete') {
              await deleteResourceRow(
                op.data!['id'] as String,
                transactionDb: db,
              );
            }
          case 'conversations':
            if (op.op == 'upsert' && op.data != null) {
              await upsertConversationRow(op.data!, transactionDb: db);
            } else if (op.op == 'delete') {
              await deleteConversationRow(
                op.data!['id'] as String,
                transactionDb: db,
              );
            }
          case 'messages':
            if (op.op == 'upsert' && op.data != null) {
              await upsertMessageRow(op.data!, transactionDb: db);
            } else if (op.op == 'delete') {
              await deleteMessageRow(
                op.data!['id'] as String,
                transactionDb: db,
              );
            }
          case 'message_attachments':
            if (op.op == 'upsert' && op.data != null) {
              await upsertMessageAttachmentRow(op.data!, transactionDb: db);
            } else if (op.op == 'delete') {
              await deleteMessageAttachmentRow(
                op.data!['id'] as String,
                transactionDb: db,
              );
            }
          case 'schedules':
            if (op.op == 'upsert' && op.data != null) {
              await upsertScheduleRow(op.data!, transactionDb: db);
            } else if (op.op == 'delete') {
              await deleteScheduleRow(
                op.data!['id'] as String,
                transactionDb: db,
              );
            }
          case 'todo_lists':
            if (op.op == 'upsert' && op.data != null) {
              await upsertTodoListRow(op.data!, transactionDb: db);
            } else if (op.op == 'delete') {
              await deleteTodoListRow(
                op.data!['id'] as String,
                transactionDb: db,
              );
            }
          case 'todo_items':
            if (op.op == 'upsert' && op.data != null) {
              await upsertTodoItemRow(op.data!, transactionDb: db);
            } else if (op.op == 'delete') {
              await deleteTodoItemRow(
                op.data!['id'] as String,
                transactionDb: db,
              );
            }
          case 'roleplay_scenarios':
            if (op.op == 'upsert' && op.data != null) {
              final id = op.data!['id'] as String? ?? '';
              await upsertRoleplayScenarioRow(
                id,
                op.data!,
                op.data!['updatedAt'] as String? ?? '',
                transactionDb: db,
              );
            } else if (op.op == 'delete') {
              await deleteRoleplayScenarioRow(
                op.data!['id'] as String,
                transactionDb: db,
              );
            }
          case 'roleplay_threads':
            if (op.op == 'upsert' && op.data != null) {
              final id = op.data!['id'] as String? ?? '';
              await upsertRoleplayThreadRow(
                id,
                op.data!,
                op.data!['updatedAt'] as String? ?? '',
                transactionDb: db,
              );
            } else if (op.op == 'delete') {
              await deleteRoleplayThreadRow(
                op.data!['id'] as String,
                transactionDb: db,
              );
            }
          case 'recycle_bin':
            if (op.op == 'upsert' && op.data != null) {
              await upsertRecycleBinRow(op.data!, transactionDb: db);
            } else if (op.op == 'delete') {
              await deleteRecycleBinRow(
                op.data!['id'] as String,
                transactionDb: db,
              );
            }
          case 'note_folders':
            await _applyNoteFolderOperation(db, op.op, op.data!);
          case 'notes':
            await _applyNoteOperation(db, op.op, op.data!);
          case 'note_pages':
            await _applyNotePageOperation(db, op.op, op.data!);
          case 'note_revisions':
            await _applyNoteRevisionOperation(db, op.op, op.data!);
          case 'note_page_heads':
            await _applyNotePageHeadOperation(db, op.op, op.data!);
          case 'note_page_tombstones':
            await _applyNotePageTombstoneOperation(db, op.op, op.data!);
          case 'shared_settings':
            if (op.op == 'upsert') {
              final local = await _loadAppSettings(db);
              await _replaceAppSettings(
                db,
                SharedSettingsV1.fromRemote(op.data!).mergeIntoLocal(local),
              );
            }
          case 'synced_model_configs':
            await _applySyncedModelConfigOperation(db, op.op, op.data!);
          case 'plugin_files':
          case 'plugin_settings':
          case 'plugin_config':
            await _applyPluginSyncMetadata(db, op.table, op.op, op.data!);
        }
        if (!remote) {
          final targetScopes = await _localCaptureStates(db);
          for (final targetScope in targetScopes) {
            await _putOutbox(
              db,
              targetScope.scope,
              op.table,
              id,
              op.op,
              op.op == 'upsert' ? op.data : null,
              deviceId: targetScope.deviceId,
            );
          }
        }
        if (remote && changeId != null) {
          await db
              .into(db.syncAppliedChangeRows)
              .insert(
                SyncAppliedChangeRowsCompanion.insert(
                  changeId: changeId,
                  source: appliedSource,
                  appliedAt: DateTime.now().toUtc().toIso8601String(),
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }
      }
      if (remote && scope != null && nextSince != null) {
        await _setSyncSince(db, scope, nextSince);
      }
    });
  }

  bool _isNoteDagTable(String table) => const {
    'note_revisions',
    'note_page_heads',
    'note_page_tombstones',
  }.contains(table);

  Future<void> _applyNoteFolderOperation(
    StorageV2DriftDatabase db,
    String op,
    Map<String, dynamic> data,
  ) async {
    final id = data['id'] as String;
    if (op == 'delete') {
      await (db.delete(
        db.noteFolderRows,
      )..where((row) => row.id.equals(id))).go();
      return;
    }
    await db
        .into(db.noteFolderRows)
        .insertOnConflictUpdate(
          NoteFolderRowsCompanion.insert(
            id: id,
            title: data['title'] as String? ?? '',
            createdAt: data['createdAt'] as String? ?? '',
            updatedAt: data['updatedAt'] as String? ?? '',
            sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
          ),
        );
  }

  Future<void> _applyNoteOperation(
    StorageV2DriftDatabase db,
    String op,
    Map<String, dynamic> data,
  ) async {
    final id = data['id'] as String;
    if (op == 'delete') {
      await (db.delete(db.noteRows)..where((row) => row.id.equals(id))).go();
      return;
    }
    await db
        .into(db.noteRows)
        .insertOnConflictUpdate(
          NoteRowsCompanion.insert(
            id: id,
            title: data['title'] as String? ?? '',
            folderId: Value(data['folderId'] as String?),
            currentRevisionId: Value(data['currentRevisionId'] as String?),
            currentPageId: Value(data['currentPageId'] as String?),
            createdAt: data['createdAt'] as String? ?? '',
            updatedAt: data['updatedAt'] as String? ?? '',
            wrap: data['wrap'] == false ? 0 : 1,
            sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
          ),
        );
  }

  Future<void> _applyNotePageOperation(
    StorageV2DriftDatabase db,
    String op,
    Map<String, dynamic> data,
  ) async {
    final id = data['id'] as String;
    if (op == 'delete') {
      await (db.delete(
        db.notePageRows,
      )..where((row) => row.id.equals(id))).go();
      return;
    }
    await db
        .into(db.notePageRows)
        .insertOnConflictUpdate(
          NotePageRowsCompanion.insert(
            id: id,
            noteId: data['noteId'] as String,
            title: data['title'] as String? ?? '',
            fileName: data['fileName'] as String? ?? '',
            relativePath: data['relativePath'] as String? ?? '',
            currentRevisionId: Value(data['currentRevisionId'] as String?),
            sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
            createdAt: data['createdAt'] as String? ?? '',
            updatedAt: data['updatedAt'] as String? ?? '',
          ),
        );
  }

  Future<void> _applyNoteRevisionOperation(
    StorageV2DriftDatabase db,
    String op,
    Map<String, dynamic> data,
  ) async {
    if (op == 'delete') return;
    final id = data['id'] as String;
    final pageId = data['pageId'] as String?;
    if (pageId != null && await _isNoteRevisionTombstoned(db, pageId, id)) {
      return;
    }
    final existing = await (db.select(
      db.noteRevisionRows,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final encodedParents = jsonEncode(data['parentIds'] ?? const []);
    if (existing != null) {
      if (existing.noteId != data['noteId'] ||
          existing.pageId != data['pageId'] ||
          existing.parentIdsJson != encodedParents ||
          existing.authorDeviceId != data['authorDeviceId'] ||
          existing.contentHash != data['contentHash'] ||
          existing.createdAt != data['createdAt']) {
        throw StateError('immutable note revision ID collision: $id');
      }
      return;
    }
    await db
        .into(db.noteRevisionRows)
        .insert(
          NoteRevisionRowsCompanion.insert(
            id: id,
            noteId: data['noteId'] as String,
            pageId: Value(data['pageId'] as String?),
            parentIdsJson: encodedParents,
            authorDeviceId: data['authorDeviceId'] as String? ?? 'unknown',
            contentHash: data['contentHash'] as String,
            createdAt: data['createdAt'] as String,
          ),
        );
  }

  Future<void> _applyNotePageHeadOperation(
    StorageV2DriftDatabase db,
    String op,
    Map<String, dynamic> data,
  ) async {
    final pageId = data['pageId'] as String? ?? data['id'] as String;
    if (op == 'delete') return;
    if (await _hasNotePageTombstone(db, pageId)) return;
    final existing = await (db.select(
      db.notePageHeadRows,
    )..where((row) => row.pageId.equals(pageId))).getSingleOrNull();
    final candidates = <String>{
      ...?existing == null
          ? null
          : (jsonDecode(existing.headIdsJson) as List).whereType<String>(),
      ...(data['headIds'] as List<dynamic>? ?? const []).whereType<String>(),
    };
    final heads = <String>{};
    for (final revisionId in candidates) {
      if (!await _isNoteRevisionTombstoned(db, pageId, revisionId)) {
        heads.add(revisionId);
      }
    }
    final reduced = await _reduceHeads(db, heads);
    if (reduced.isEmpty) {
      await (db.delete(
        db.notePageHeadRows,
      )..where((row) => row.pageId.equals(pageId))).go();
      await (db.update(db.notePageRows)..where((row) => row.id.equals(pageId)))
          .write(const NotePageRowsCompanion(currentRevisionId: Value(null)));
      return;
    }
    final remoteSelected = data['selectedHeadId'] as String?;
    final selected = reduced.contains(remoteSelected)
        ? remoteSelected
        : reduced.contains(existing?.selectedHeadId)
        ? existing!.selectedHeadId
        : reduced.length == 1
        ? reduced.single
        : existing?.selectedHeadId;
    await db
        .into(db.notePageHeadRows)
        .insertOnConflictUpdate(
          NotePageHeadRowsCompanion.insert(
            id: pageId,
            pageId: pageId,
            headIdsJson: jsonEncode(reduced.toList()..sort()),
            selectedHeadId: Value(selected),
            updatedAt:
                data['updatedAt'] as String? ??
                DateTime.now().toIso8601String(),
          ),
        );
    if (selected != null) {
      await (db.update(db.notePageRows)..where((row) => row.id.equals(pageId)))
          .write(NotePageRowsCompanion(currentRevisionId: Value(selected)));
    }
  }

  Future<Set<String>> _reduceHeads(
    StorageV2DriftDatabase db,
    Set<String> heads,
  ) async {
    final result = {...heads};
    for (final candidate in heads) {
      for (final other in heads) {
        if (candidate != other &&
            await _isRevisionAncestor(db, candidate, other)) {
          result.remove(candidate);
          break;
        }
      }
    }
    return result;
  }

  Future<bool> _isRevisionAncestor(
    StorageV2DriftDatabase db,
    String ancestor,
    String descendant,
  ) async {
    final pending = <String>[descendant];
    final visited = <String>{};
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!visited.add(id)) continue;
      if (id == ancestor) return true;
      final row = await (db.select(
        db.noteRevisionRows,
      )..where((item) => item.id.equals(id))).getSingleOrNull();
      if (row != null) {
        pending.addAll(
          (jsonDecode(row.parentIdsJson) as List).whereType<String>(),
        );
      }
    }
    return false;
  }

  Future<void> _applyNotePageTombstoneOperation(
    StorageV2DriftDatabase db,
    String op,
    Map<String, dynamic> data,
  ) async {
    if (op == 'delete') {
      await (db.delete(
        db.notePageTombstoneRows,
      )..where((row) => row.id.equals(data['id'] as String))).go();
      return;
    }
    final pageId = data['pageId'] as String;
    final revisionId = data['revisionId'] as String;
    await db
        .into(db.notePageTombstoneRows)
        .insertOnConflictUpdate(
          NotePageTombstoneRowsCompanion.insert(
            id: data['id'] as String,
            pageId: pageId,
            revisionId: revisionId,
            createdAt: data['createdAt'] as String,
          ),
        );
    await _removeTombstonedNotePageState(db, pageId, revisionId);
  }

  Future<bool> _hasNotePageTombstone(
    StorageV2DriftDatabase db,
    String pageId,
  ) async {
    return await (db.select(db.notePageTombstoneRows)..where(
              (row) => row.pageId.equals(pageId) & row.revisionId.equals('*'),
            ))
            .getSingleOrNull() !=
        null;
  }

  Future<bool> _isNoteRevisionTombstoned(
    StorageV2DriftDatabase db,
    String pageId,
    String revisionId,
  ) async {
    return await (db.select(db.notePageTombstoneRows)..where(
              (row) =>
                  row.pageId.equals(pageId) &
                  row.revisionId.isIn([revisionId, '*']),
            ))
            .getSingleOrNull() !=
        null;
  }

  Future<void> _removeTombstonedNotePageState(
    StorageV2DriftDatabase db,
    String pageId,
    String revisionId,
  ) async {
    final deletedRevisionIds = revisionId == '*'
        ? (await (db.select(
                db.noteRevisionRows,
              )..where((row) => row.pageId.equals(pageId))).get())
              .map((row) => row.id)
              .toSet()
        : <String>{revisionId};
    if (revisionId == '*') {
      await (db.delete(
        db.noteRevisionRows,
      )..where((row) => row.pageId.equals(pageId))).go();
    } else {
      await (db.delete(db.noteRevisionRows)..where(
            (row) => row.id.equals(revisionId) & row.pageId.equals(pageId),
          ))
          .go();
    }

    final headRow = await (db.select(
      db.notePageHeadRows,
    )..where((row) => row.pageId.equals(pageId))).getSingleOrNull();
    String? selectedHeadId;
    if (headRow != null) {
      final remainingHeads = revisionId == '*'
          ? <String>{}
          : (jsonDecode(headRow.headIdsJson) as List)
                .whereType<String>()
                .where((id) => id != revisionId)
                .toSet();
      if (remainingHeads.isEmpty) {
        await (db.delete(
          db.notePageHeadRows,
        )..where((row) => row.pageId.equals(pageId))).go();
      } else {
        selectedHeadId = remainingHeads.contains(headRow.selectedHeadId)
            ? headRow.selectedHeadId
            : remainingHeads.length == 1
            ? remainingHeads.single
            : null;
        await (db.update(
          db.notePageHeadRows,
        )..where((row) => row.pageId.equals(pageId))).write(
          NotePageHeadRowsCompanion(
            headIdsJson: Value(jsonEncode(remainingHeads.toList()..sort())),
            selectedHeadId: Value(selectedHeadId),
            updatedAt: Value(DateTime.now().toIso8601String()),
          ),
        );
      }
    }
    await (db.update(db.notePageRows)..where((row) => row.id.equals(pageId)))
        .write(NotePageRowsCompanion(currentRevisionId: Value(selectedHeadId)));
    if (deletedRevisionIds.isNotEmpty) {
      await (db.update(db.noteRows)..where(
            (row) =>
                row.currentPageId.equals(pageId) &
                row.currentRevisionId.isIn(deletedRevisionIds),
          ))
          .write(NoteRowsCompanion(currentRevisionId: Value(selectedHeadId)));
    }

    final conflict = await (db.select(
      db.notePageConflictRows,
    )..where((row) => row.pageId.equals(pageId))).getSingleOrNull();
    if (conflict == null) return;
    final remainingConflictHeads = revisionId == '*'
        ? <String>[]
        : (jsonDecode(conflict.headIdsJson) as List)
              .whereType<String>()
              .where((id) => id != revisionId)
              .toList();
    if (remainingConflictHeads.length < 2) {
      await (db.delete(
        db.notePageConflictRows,
      )..where((row) => row.pageId.equals(pageId))).go();
      return;
    }
    final localHeadId = remainingConflictHeads.contains(conflict.localHeadId)
        ? conflict.localHeadId
        : remainingConflictHeads.first;
    final incomingHeadId =
        remainingConflictHeads.contains(conflict.incomingHeadId) &&
            conflict.incomingHeadId != localHeadId
        ? conflict.incomingHeadId
        : remainingConflictHeads.firstWhere((id) => id != localHeadId);
    await (db.update(
      db.notePageConflictRows,
    )..where((row) => row.pageId.equals(pageId))).write(
      NotePageConflictRowsCompanion(
        headIdsJson: Value(jsonEncode(remainingConflictHeads)),
        localHeadId: Value(localHeadId),
        incomingHeadId: Value(incomingHeadId),
        commonAncestorId: Value(
          conflict.commonAncestorId == revisionId
              ? null
              : conflict.commonAncestorId,
        ),
      ),
    );
  }

  Future<void> updateSyncSince(String scope, int since) async {
    final db = await _open();
    await _setSyncSince(db, scope, since);
  }

  static int _syncOperationPriority(String table, String op) {
    if (table == 'note_page_tombstones') return op == 'delete' ? 2 : 6;
    return switch (table) {
      'note_folders' => 0,
      'notes' => 1,
      'note_pages' => 3,
      'note_revisions' => 4,
      'note_page_heads' => 5,
      'resources' => 7,
      _ => 10,
    };
  }

  Future<StorageV2DriftDatabase> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    if (!await storageRoot.exists()) await storageRoot.create(recursive: true);
    final path = file.absolute.path;
    final shared = _openDatabases[path];
    if (shared != null) {
      _openReferenceCounts[path] = (_openReferenceCounts[path] ?? 0) + 1;
      _db = shared;
      return shared;
    }
    final pending = _pendingOpens[path];
    if (pending != null) {
      final db = await pending;
      _openReferenceCounts[path] = (_openReferenceCounts[path] ?? 0) + 1;
      _db = db;
      return db;
    }
    Future<StorageV2DriftDatabase> init() async {
      final db = StorageV2DriftDatabase(file);
      await db.customStatement('PRAGMA foreign_keys = ON');
      await _createSchema(db);
      await db._addColumnIfMissing('note_pages', 'current_revision_id', 'TEXT');
      await _finishLegacyNoteRevisionMigration(db);
      _openDatabases[path] = db;
      _openReferenceCounts[path] = 1;
      _pendingOpens.remove(path);
      return db;
    }

    final future = init();
    _pendingOpens[path] = future;
    final db = await future;
    _db = db;
    return db;
  }

  Future<void> _finishLegacyNoteRevisionMigration(
    StorageV2DriftDatabase db,
  ) async {
    final legacyTable = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'note_revisions_legacy'",
        )
        .getSingleOrNull();
    if (legacyTable == null) return;

    final legacyRows = await db
        .customSelect(
          'SELECT id, note_id, page_id, parent_revision_id, saved_at, '
          'delta_start, deleted_text, inserted_text FROM note_revisions_legacy',
        )
        .get();
    final rowsById = {
      for (final row in legacyRows) row.read<String>('id'): row,
    };
    final contentById = <String, String>{};

    String reconstruct(String id, Set<String> visiting) {
      final cached = contentById[id];
      if (cached != null) return cached;
      final row = rowsById[id];
      if (row == null || !visiting.add(id)) {
        throw StateError('Invalid legacy note revision chain at $id');
      }
      final parentId = row.readNullable<String>('parent_revision_id');
      final parent = parentId == null ? '' : reconstruct(parentId, visiting);
      final start = row.read<int>('delta_start').clamp(0, parent.length);
      final deleted = row.read<String>('deleted_text');
      final end = (start + deleted.length).clamp(start, parent.length);
      if (parent.substring(start, end) != deleted) {
        throw StateError(
          'Legacy note revision delta does not match parent: $id',
        );
      }
      final content = parent.replaceRange(
        start,
        end,
        row.read<String>('inserted_text'),
      );
      visiting.remove(id);
      contentById[id] = content;
      return content;
    }

    for (final id in rowsById.keys) {
      final content = reconstruct(id, <String>{});
      await _writeNoteBlob(
        sha256.convert(utf8.encode(content)).toString(),
        content,
      );
    }

    await db.transaction(() async {
      for (final row in legacyRows) {
        final id = row.read<String>('id');
        final parentId = row.readNullable<String>('parent_revision_id');
        final contentHash = sha256
            .convert(utf8.encode(contentById[id]!))
            .toString();
        await db
            .into(db.noteRevisionRows)
            .insertOnConflictUpdate(
              NoteRevisionRowsCompanion.insert(
                id: id,
                noteId: row.read<String>('note_id'),
                pageId: Value(row.readNullable<String>('page_id')),
                parentIdsJson: jsonEncode(
                  parentId == null ? const <String>[] : <String>[parentId],
                ),
                authorDeviceId: 'legacy',
                contentHash: contentHash,
                createdAt: row.read<String>('saved_at'),
              ),
            );
      }
      final pages = await db.select(db.notePageRows).get();
      for (final page in pages) {
        final pageRevisions = legacyRows
            .where((row) => row.readNullable<String>('page_id') == page.id)
            .map((row) => row.read<String>('id'))
            .toSet();
        final parents = legacyRows
            .where((row) => pageRevisions.contains(row.read<String>('id')))
            .map((row) => row.readNullable<String>('parent_revision_id'))
            .whereType<String>()
            .toSet();
        final heads = pageRevisions.difference(parents).toList()..sort();
        final selected = page.currentRevisionId;
        if (selected != null && !heads.contains(selected)) heads.add(selected);
        if (heads.isEmpty) continue;
        await db
            .into(db.notePageHeadRows)
            .insertOnConflictUpdate(
              NotePageHeadRowsCompanion.insert(
                id: page.id,
                pageId: page.id,
                headIdsJson: jsonEncode(heads),
                selectedHeadId: Value(selected ?? heads.first),
                updatedAt: page.updatedAt,
              ),
            );
      }
      await db.customStatement('DROP TABLE note_revisions_legacy');
    });
  }

  Future<void> _writeNoteBlob(String hash, String content) async {
    final target = File(
      '${storageRoot.path}/notes/blobs/${hash.substring(0, 2)}/$hash',
    );
    if (await target.exists()) {
      final existing = await target.readAsBytes();
      if (sha256.convert(existing).toString() == hash) return;
      throw StateError('Existing note blob hash mismatch: $hash');
    }
    await target.parent.create(recursive: true);
    final temporary = File(
      '${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsString(content, flush: true);
      await temporary.rename(target.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> _createSchema(StorageV2DriftDatabase db) async {
    await db.customStatement('''
CREATE TABLE IF NOT EXISTS storage_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS app_settings (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  settings_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS model_configs (
  id TEXT PRIMARY KEY,
  config_json TEXT NOT NULL,
  category TEXT NOT NULL,
  enabled INTEGER NOT NULL,
  priority INTEGER NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS resources (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  role TEXT NOT NULL,
  original_path TEXT NOT NULL,
  original_name TEXT NOT NULL,
  relative_path TEXT,
  mime_type TEXT NOT NULL,
  size INTEGER NOT NULL,
  sha256 TEXT,
  missing INTEGER NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS conversations (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  model_id TEXT NOT NULL,
  settings_json TEXT NOT NULL,
  agent_plan_json TEXT,
  agent_working_memory_json TEXT,
  role_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  thinking_content TEXT,
  agent_trace_json TEXT,
  timestamp TEXT NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL,
  FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS message_attachments (
  id TEXT PRIMARY KEY,
  message_id TEXT NOT NULL,
  resource_id TEXT,
  display_name TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  size INTEGER NOT NULL,
  sort_order INTEGER NOT NULL,
  legacy_path TEXT,
  FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
  FOREIGN KEY (resource_id) REFERENCES resources(id) ON DELETE SET NULL
);
CREATE TABLE IF NOT EXISTS note_folders (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS notes (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  folder_id TEXT,
  current_revision_id TEXT,
  current_page_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  wrap INTEGER NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS note_pages (
  id TEXT PRIMARY KEY,
  note_id TEXT NOT NULL,
  title TEXT NOT NULL,
  file_name TEXT NOT NULL,
  relative_path TEXT NOT NULL,
  current_revision_id TEXT,
  sort_order INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS note_revisions (
  id TEXT PRIMARY KEY,
  note_id TEXT NOT NULL,
  page_id TEXT,
  parent_ids_json TEXT NOT NULL,
  author_device_id TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS note_page_heads (
  id TEXT PRIMARY KEY,
  page_id TEXT NOT NULL UNIQUE,
  head_ids_json TEXT NOT NULL,
  selected_head_id TEXT,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (page_id) REFERENCES note_pages(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS note_page_tombstones (
  id TEXT PRIMARY KEY,
  page_id TEXT NOT NULL,
  revision_id TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS note_page_conflicts (
  page_id TEXT PRIMARY KEY,
  head_ids_json TEXT NOT NULL,
  local_head_id TEXT NOT NULL,
  incoming_head_id TEXT NOT NULL,
  common_ancestor_id TEXT,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS note_edit_proposals (
  id TEXT PRIMARY KEY,
  note_id TEXT NOT NULL,
  page_id TEXT,
  base_revision_id TEXT,
  base_content_hash TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS note_edit_blocks (
  id TEXT PRIMARY KEY,
  proposal_id TEXT NOT NULL,
  start_line INTEGER NOT NULL,
  delete_count INTEGER NOT NULL,
  deleted_lines_json TEXT NOT NULL,
  insert_lines_json TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  FOREIGN KEY (proposal_id) REFERENCES note_edit_proposals(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS schedules (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  start_time TEXT NOT NULL,
  end_time TEXT NOT NULL,
  note TEXT,
  kind TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS todo_lists (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS todo_items (
  id TEXT PRIMARY KEY,
  list_id TEXT NOT NULL,
  text TEXT NOT NULL,
  done INTEGER NOT NULL,
  sort_order INTEGER NOT NULL,
  updated_at TEXT NOT NULL DEFAULT '',
  FOREIGN KEY (list_id) REFERENCES todo_lists(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_attachments_message ON message_attachments(message_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_note_pages_note ON note_pages(note_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_note_revisions_page_created ON note_revisions(page_id, created_at);
CREATE INDEX IF NOT EXISTS idx_note_revisions_content_hash ON note_revisions(content_hash);
CREATE UNIQUE INDEX IF NOT EXISTS idx_note_page_heads_page ON note_page_heads(page_id);
CREATE INDEX IF NOT EXISTS idx_note_page_tombstones_page ON note_page_tombstones(page_id);
CREATE INDEX IF NOT EXISTS idx_todo_items_list ON todo_items(list_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_resources_hash_size ON resources(sha256, size);
CREATE TABLE IF NOT EXISTS sync_outbox (
  scope TEXT NOT NULL,
  table_name TEXT NOT NULL,
  record_id TEXT NOT NULL,
  op TEXT NOT NULL,
  data_json TEXT,
  change_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  client_created_at TEXT NOT NULL,
  mutation_version INTEGER NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (scope, table_name, record_id)
);
CREATE TABLE IF NOT EXISTS sync_conflicts (
  scope TEXT NOT NULL,
  seq INTEGER NOT NULL,
  table_name TEXT NOT NULL,
  record_id TEXT NOT NULL,
  op TEXT NOT NULL,
  data_json TEXT,
  change_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  client_created_at TEXT NOT NULL,
  created_at TEXT,
  local_op TEXT NOT NULL,
  local_data_json TEXT,
  local_change_id TEXT NOT NULL,
  local_mutation_version INTEGER NOT NULL,
  PRIMARY KEY (scope, seq)
);
CREATE TABLE IF NOT EXISTS sync_state (
  scope TEXT PRIMARY KEY,
  since INTEGER NOT NULL DEFAULT 0,
  initialized INTEGER NOT NULL DEFAULT 0,
  device_id TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sync_applied_changes (
  change_id TEXT PRIMARY KEY,
  source TEXT NOT NULL,
  applied_at TEXT NOT NULL
);
''');
  }

  Future<Map<String, dynamic>> _loadAppSettings(
    StorageV2DriftDatabase db,
  ) async {
    final row = await (db.select(
      db.appSettingsRows,
    )..where((table) => table.id.equals(1))).getSingleOrNull();
    return row == null
        ? <String, dynamic>{}
        : jsonDecode(row.settingsJson) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _loadModelConfigs(
    StorageV2DriftDatabase db,
  ) async {
    final rows =
        await (db.select(db.modelConfigRows)..orderBy([
              (table) => OrderingTerm.asc(table.category),
              (table) => OrderingTerm.asc(table.priority),
            ]))
            .get();
    return {'models': rows.map((row) => jsonDecode(row.configJson)).toList()};
  }

  Future<Map<String, dynamic>> _loadResources(StorageV2DriftDatabase db) async {
    final rows =
        await (db.select(db.resourceRows)..orderBy([
              (table) => OrderingTerm.asc(table.createdAt),
              (table) => OrderingTerm.asc(table.id),
            ]))
            .get();
    return {'resources': rows.map(_resourceRow).toList()};
  }

  Future<Map<String, dynamic>> _loadConversations(
    StorageV2DriftDatabase db,
  ) async {
    final conversations =
        (await (db.select(
          db.conversationRows,
        )..orderBy([(table) => OrderingTerm.desc(table.updatedAt)])).get()).map(
          (row) {
            return {
              'id': row.id,
              'title': row.title,
              'modelId': row.modelId,
              'settings': jsonDecode(row.settingsJson),
              if (row.agentPlanJson != null)
                'agentPlan': jsonDecode(row.agentPlanJson!),
              if (row.agentWorkingMemoryJson != null)
                'agentWorkingMemory': jsonDecode(row.agentWorkingMemoryJson!),
              'roleId': row.roleId,
              'createdAt': row.createdAt,
              'updatedAt': row.updatedAt,
            };
          },
        ).toList();
    final messages =
        (await (db.select(db.messageRows)..orderBy([
                  (table) => OrderingTerm.asc(table.conversationId),
                  (table) => OrderingTerm.asc(table.sortOrder),
                ]))
                .get())
            .map((row) {
              return {
                'id': row.id,
                'conversationId': row.conversationId,
                'role': row.role,
                'content': row.content,
                if (row.thinkingContent != null)
                  'thinkingContent': row.thinkingContent,
                if (row.agentTraceJson != null)
                  'agentTrace': jsonDecode(row.agentTraceJson!),
                'timestamp': row.timestamp,
                'revision': row.revision,
                'updatedAt': row.updatedAt.isEmpty
                    ? row.timestamp
                    : row.updatedAt,
                'sortOrder': row.sortOrder,
              };
            })
            .toList();
    final attachments =
        (await (db.select(db.messageAttachmentRows)..orderBy([
                  (table) => OrderingTerm.asc(table.messageId),
                  (table) => OrderingTerm.asc(table.sortOrder),
                ]))
                .get())
            .map((row) {
              return {
                'id': row.id,
                'messageId': row.messageId,
                if (row.resourceId != null) 'resourceId': row.resourceId,
                if (row.legacyPath != null) 'path': row.legacyPath,
                'displayName': row.displayName,
                'mimeType': row.mimeType,
                'size': row.size,
                'sortOrder': row.sortOrder,
              };
            })
            .toList();
    return {
      'conversations': conversations,
      'messages': messages,
      'messageAttachments': attachments,
    };
  }

  Future<Map<String, dynamic>> _loadNotes(StorageV2DriftDatabase db) async {
    final folders =
        (await (db.select(
              db.noteFolderRows,
            )..orderBy([(table) => OrderingTerm.asc(table.sortOrder)])).get())
            .map(
              (row) => {
                'id': row.id,
                'title': row.title,
                'createdAt': row.createdAt,
                'updatedAt': row.updatedAt,
                'sortOrder': row.sortOrder,
              },
            )
            .toList();
    final notes =
        (await (db.select(
              db.noteRows,
            )..orderBy([(table) => OrderingTerm.asc(table.sortOrder)])).get())
            .map(
              (row) => {
                'id': row.id,
                'title': row.title,
                if (row.folderId != null) 'folderId': row.folderId,
                if (row.currentRevisionId != null)
                  'currentRevisionId': row.currentRevisionId,
                if (row.currentPageId != null)
                  'currentPageId': row.currentPageId,
                'createdAt': row.createdAt,
                'updatedAt': row.updatedAt,
                'wrap': row.wrap != 0,
                'sortOrder': row.sortOrder,
              },
            )
            .toList();
    final pages =
        (await (db.select(db.notePageRows)..orderBy([
                  (table) => OrderingTerm.asc(table.noteId),
                  (table) => OrderingTerm.asc(table.sortOrder),
                ]))
                .get())
            .map(
              (row) => {
                'id': row.id,
                'noteId': row.noteId,
                'title': row.title,
                'fileName': row.fileName,
                'relativePath': row.relativePath,
                if (row.currentRevisionId != null)
                  'currentRevisionId': row.currentRevisionId,
                'sortOrder': row.sortOrder,
                'createdAt': row.createdAt,
                'updatedAt': row.updatedAt,
              },
            )
            .toList();
    final revisions =
        (await (db.select(
              db.noteRevisionRows,
            )..orderBy([(table) => OrderingTerm.desc(table.createdAt)])).get())
            .map(
              (row) => {
                'id': row.id,
                'noteId': row.noteId,
                if (row.pageId != null) 'pageId': row.pageId,
                'parentIds': jsonDecode(row.parentIdsJson),
                'authorDeviceId': row.authorDeviceId,
                'contentHash': row.contentHash,
                'createdAt': row.createdAt,
              },
            )
            .toList();
    final pageHeads = (await db.select(db.notePageHeadRows).get())
        .map(
          (row) => {
            'id': row.id,
            'pageId': row.pageId,
            'headIds': jsonDecode(row.headIdsJson),
            if (row.selectedHeadId != null)
              'selectedHeadId': row.selectedHeadId,
            'updatedAt': row.updatedAt,
          },
        )
        .toList();
    final pageTombstones = (await db.select(db.notePageTombstoneRows).get())
        .map(
          (row) => {
            'id': row.id,
            'pageId': row.pageId,
            'revisionId': row.revisionId,
            'createdAt': row.createdAt,
          },
        )
        .toList();
    final pageConflicts = (await db.select(db.notePageConflictRows).get())
        .map(
          (row) => {
            'pageId': row.pageId,
            'headIds': jsonDecode(row.headIdsJson),
            'localHeadId': row.localHeadId,
            'incomingHeadId': row.incomingHeadId,
            if (row.commonAncestorId != null)
              'commonAncestorId': row.commonAncestorId,
            'createdAt': row.createdAt,
          },
        )
        .toList();
    final editProposals =
        (await (db.select(
              db.noteEditProposalRows,
            )..orderBy([(table) => OrderingTerm.desc(table.createdAt)])).get())
            .map(
              (row) => {
                'id': row.id,
                'noteId': row.noteId,
                if (row.pageId != null) 'pageId': row.pageId,
                if (row.baseRevisionId != null)
                  'baseRevisionId': row.baseRevisionId,
                'baseContentHash': row.baseContentHash,
                'createdAt': row.createdAt,
              },
            )
            .toList();
    final editBlocks =
        (await (db.select(db.noteEditBlockRows)..orderBy([
                  (table) => OrderingTerm.asc(table.proposalId),
                  (table) => OrderingTerm.asc(table.sortOrder),
                ]))
                .get())
            .map(
              (row) => {
                'id': row.id,
                'proposalId': row.proposalId,
                'startLine': row.startLine,
                'deleteCount': row.deleteCount,
                'deletedLines': jsonDecode(row.deletedLinesJson),
                'insertLines': jsonDecode(row.insertLinesJson),
                'sortOrder': row.sortOrder,
              },
            )
            .toList();
    return {
      'folders': folders,
      'notes': notes,
      'pages': pages,
      'revisions': revisions,
      'pageHeads': pageHeads,
      'pageTombstones': pageTombstones,
      'pageConflicts': pageConflicts,
      'editProposals': editProposals,
      'editBlocks': editBlocks,
    };
  }

  Future<Map<String, dynamic>> _loadSchedules(StorageV2DriftDatabase db) async {
    final rows = await (db.select(
      db.scheduleRows,
    )..orderBy([(table) => OrderingTerm.asc(table.startTime)])).get();
    return {
      'schedules': rows
          .map(
            (row) => {
              'id': row.id,
              'title': row.title,
              'start': row.startTime,
              'end': row.endTime,
              if (row.note != null) 'note': row.note,
              if (row.kind != 'schedule') 'kind': row.kind,
            },
          )
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _loadTodoLists(StorageV2DriftDatabase db) async {
    final todoLists =
        (await (db.select(
              db.todoListRows,
            )..orderBy([(table) => OrderingTerm.desc(table.updatedAt)])).get())
            .map(
              (row) => {
                'id': row.id,
                'title': row.title,
                'createdAt': row.createdAt,
                'updatedAt': row.updatedAt,
              },
            )
            .toList();
    final todoItems =
        (await (db.select(db.todoItemRows)..orderBy([
                  (table) => OrderingTerm.asc(table.listId),
                  (table) => OrderingTerm.asc(table.sortOrder),
                ]))
                .get())
            .map(
              (row) => {
                'id': row.id,
                'listId': row.listId,
                'text': row.itemText,
                'done': row.done != 0,
                'sortOrder': row.sortOrder,
              },
            )
            .toList();
    return {'todoLists': todoLists, 'todoItems': todoItems};
  }

  Future<Map<String, dynamic>> _loadRoleplayScenarios(
    StorageV2DriftDatabase db,
  ) async {
    final rows = await db.select(db.roleplayScenarioRows).get();
    if (rows.isEmpty) {
      return await _loadGenericDataFile(db, 'roleplay_scenarios.json') ??
          const {'scenarios': <dynamic>[]};
    }
    return {
      'scenarios': rows
          .map(
            (row) => Map<String, dynamic>.from(jsonDecode(row.dataJson) as Map),
          )
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _loadRoleplayThreads(
    StorageV2DriftDatabase db,
  ) async {
    final rows = await db.select(db.roleplayThreadRows).get();
    if (rows.isEmpty) {
      return await _loadGenericDataFile(db, 'roleplay_threads.json') ??
          const {'threads': <dynamic>[]};
    }
    return {
      'threads': rows
          .map(
            (row) => Map<String, dynamic>.from(jsonDecode(row.dataJson) as Map),
          )
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _loadRecycleBin(
    StorageV2DriftDatabase db,
  ) async {
    final rows = await db.select(db.recycleBinRows).get();
    if (rows.isEmpty) {
      return await _loadGenericDataFile(db, 'recycle_bin.json') ??
          const {'items': <dynamic>[]};
    }
    return {
      'items': rows
          .map(
            (row) => {
              'id': row.id,
              'owner': row.owner,
              'category': row.category,
              'type': row.type,
              'title': row.title,
              'preview': row.preview,
              'payload': jsonDecode(row.payloadJson),
              'deletedAt': row.deletedAt,
            },
          )
          .toList(),
    };
  }

  Future<Map<String, dynamic>?> _loadGenericDataFile(
    StorageV2DriftDatabase db,
    String fileName,
  ) async {
    final raw = await _meta(db, 'datafile.$fileName');
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  Future<void> _replaceAppSettings(
    StorageV2DriftDatabase db,
    Map<String, dynamic> data,
  ) async {
    await db.delete(db.appSettingsRows).go();
    await db
        .into(db.appSettingsRows)
        .insert(
          AppSettingsRowsCompanion.insert(
            id: const Value(1),
            settingsJson: jsonEncode(data),
            updatedAt: DateTime.now().toIso8601String(),
          ),
        );
  }

  Future<void> _replaceModelConfigs(
    StorageV2DriftDatabase db,
    Map<String, dynamic> data,
  ) async {
    await db.delete(db.modelConfigRows).go();
    for (final item in data['models'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      if (id == null || id.isEmpty) continue;
      final models = json['models'] as List<dynamic>? ?? const [];
      final enabled = models.any(
        (item) => item is Map && item['enabled'] == true,
      );
      await db
          .into(db.modelConfigRows)
          .insert(
            ModelConfigRowsCompanion.insert(
              id: id,
              configJson: jsonEncode(json),
              category: json['category'] as String? ?? 'chat',
              enabled: enabled ? 1 : 0,
              priority: (json['priority'] as num?)?.toInt() ?? 0,
              updatedAt: DateTime.now().toIso8601String(),
            ),
          );
    }
  }

  Future<void> _replaceResources(
    StorageV2DriftDatabase db,
    Map<String, dynamic> data,
  ) async {
    await db.delete(db.resourceRows).go();
    for (final item in data['resources'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      if (id == null || id.isEmpty) continue;
      final row = ResourceRowsCompanion.insert(
        id: id,
        kind: json['kind'] as String? ?? 'unknown',
        role: json['role'] as String? ?? 'unknown',
        originalPath: json['originalPath'] as String? ?? '',
        originalName: json['originalName'] as String? ?? 'file',
        relativePath: Value(json['relativePath'] as String?),
        mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
        size: (json['size'] as num?)?.toInt() ?? 0,
        sha256: Value(json['sha256'] as String?),
        missing: json['missing'] == true ? 1 : 0,
        createdAt: DateTime.now().toIso8601String(),
      );
      await db.into(db.resourceRows).insert(row);
    }
  }

  Future<void> _replaceConversations(
    StorageV2DriftDatabase db,
    Map<String, dynamic> data,
  ) async {
    await db.delete(db.messageAttachmentRows).go();
    await db.delete(db.messageRows).go();
    await db.delete(db.conversationRows).go();
    final resourceIds = (await db.select(db.resourceRows).get())
        .map((row) => row.id)
        .toSet();
    final conversationIds = <String>{};
    final messageIds = <String>{};
    for (final item in data['conversations'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      if (id == null || id.isEmpty) continue;
      await db
          .into(db.conversationRows)
          .insert(
            ConversationRowsCompanion.insert(
              id: id,
              title: json['title'] as String? ?? '',
              modelId: json['modelId'] as String? ?? '',
              settingsJson: jsonEncode(json['settings'] ?? const {}),
              agentPlanJson: Value(
                json['agentPlan'] == null
                    ? null
                    : jsonEncode(json['agentPlan']),
              ),
              agentWorkingMemoryJson: Value(
                json['agentWorkingMemory'] == null
                    ? null
                    : jsonEncode(json['agentWorkingMemory']),
              ),
              roleId: json['roleId'] as String? ?? 'default',
              createdAt: json['createdAt'] as String? ?? '',
              updatedAt: json['updatedAt'] as String? ?? '',
            ),
          );
      conversationIds.add(id);
    }
    for (final item in data['messages'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      final conversationId = json['conversationId'] as String?;
      if (id == null ||
          id.isEmpty ||
          conversationId == null ||
          !conversationIds.contains(conversationId)) {
        continue;
      }
      await db
          .into(db.messageRows)
          .insert(
            MessageRowsCompanion.insert(
              id: id,
              conversationId: conversationId,
              role: json['role'] as String? ?? '',
              content: json['content'] as String? ?? '',
              thinkingContent: Value(json['thinkingContent'] as String?),
              agentTraceJson: Value(
                json['agentTrace'] == null
                    ? null
                    : jsonEncode(json['agentTrace']),
              ),
              timestamp: json['timestamp'] as String? ?? '',
              revision: Value((json['revision'] as num?)?.toInt() ?? 1),
              updatedAt: Value(
                json['updatedAt'] as String? ??
                    json['timestamp'] as String? ??
                    '',
              ),
              sortOrder: Value((json['sortOrder'] as num?)?.toInt() ?? 0),
            ),
          );
      messageIds.add(id);
    }
    for (final item
        in data['messageAttachments'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      final messageId = json['messageId'] as String?;
      if (id == null ||
          id.isEmpty ||
          messageId == null ||
          !messageIds.contains(messageId)) {
        continue;
      }
      final resourceId = json['resourceId'] as String?;
      await db
          .into(db.messageAttachmentRows)
          .insert(
            MessageAttachmentRowsCompanion.insert(
              id: id,
              messageId: messageId,
              resourceId: Value(
                resourceId == null || resourceIds.contains(resourceId)
                    ? resourceId
                    : null,
              ),
              displayName:
                  (json['displayName'] as String?) ??
                  (json['name'] as String?) ??
                  'file',
              mimeType:
                  json['mimeType'] as String? ?? 'application/octet-stream',
              size: (json['size'] as num?)?.toInt() ?? 0,
              sortOrder: Value((json['sortOrder'] as num?)?.toInt() ?? 0),
              legacyPath: Value(json['path'] as String?),
            ),
          );
    }
  }

  Future<void> _replaceNotes(
    StorageV2DriftDatabase db,
    Map<String, dynamic> data,
  ) async {
    await db.delete(db.noteEditBlockRows).go();
    await db.delete(db.noteEditProposalRows).go();
    await db.delete(db.noteRevisionRows).go();
    await db.delete(db.notePageHeadRows).go();
    await db.delete(db.notePageTombstoneRows).go();
    await db.delete(db.notePageConflictRows).go();
    await db.delete(db.notePageRows).go();
    await db.delete(db.noteRows).go();
    await db.delete(db.noteFolderRows).go();
    final noteIds = <String>{};
    final proposalIds = <String>{};
    var folderOrder = 0;
    for (final item in data['folders'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      if (id == null || id.isEmpty) continue;
      await db
          .into(db.noteFolderRows)
          .insert(
            NoteFolderRowsCompanion.insert(
              id: id,
              title: json['title'] as String? ?? '',
              createdAt: json['createdAt'] as String? ?? '',
              updatedAt: json['updatedAt'] as String? ?? '',
              sortOrder: (json['sortOrder'] as num?)?.toInt() ?? folderOrder,
            ),
          );
      folderOrder++;
    }
    var noteOrder = 0;
    for (final item in data['notes'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      if (id == null || id.isEmpty) continue;
      await db
          .into(db.noteRows)
          .insert(
            NoteRowsCompanion.insert(
              id: id,
              title: json['title'] as String? ?? '',
              folderId: Value(json['folderId'] as String?),
              currentRevisionId: Value(json['currentRevisionId'] as String?),
              currentPageId: Value(json['currentPageId'] as String?),
              createdAt: json['createdAt'] as String? ?? '',
              updatedAt: json['updatedAt'] as String? ?? '',
              wrap: json['wrap'] == false ? 0 : 1,
              sortOrder: (json['sortOrder'] as num?)?.toInt() ?? noteOrder,
            ),
          );
      noteIds.add(id);
      noteOrder++;
    }
    for (final item in data['pages'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      final noteId = json['noteId'] as String?;
      if (id == null ||
          id.isEmpty ||
          noteId == null ||
          !noteIds.contains(noteId)) {
        continue;
      }
      await db
          .into(db.notePageRows)
          .insert(
            NotePageRowsCompanion.insert(
              id: id,
              noteId: noteId,
              title: json['title'] as String? ?? '',
              fileName: json['fileName'] as String? ?? '',
              relativePath: json['relativePath'] as String? ?? '',
              currentRevisionId: Value(json['currentRevisionId'] as String?),
              sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
              createdAt: json['createdAt'] as String? ?? '',
              updatedAt: json['updatedAt'] as String? ?? '',
            ),
          );
    }
    for (final item in data['revisions'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      final noteId = json['noteId'] as String?;
      if (id == null ||
          id.isEmpty ||
          noteId == null ||
          !noteIds.contains(noteId)) {
        continue;
      }
      await db
          .into(db.noteRevisionRows)
          .insert(
            NoteRevisionRowsCompanion.insert(
              id: id,
              noteId: noteId,
              pageId: Value(json['pageId'] as String?),
              parentIdsJson: jsonEncode(json['parentIds'] ?? const []),
              authorDeviceId: json['authorDeviceId'] as String? ?? 'legacy',
              contentHash: json['contentHash'] as String? ?? '',
              createdAt:
                  json['createdAt'] as String? ??
                  json['savedAt'] as String? ??
                  '',
            ),
          );
    }
    for (final item in data['pageHeads'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final pageId = json['pageId'] as String?;
      if (pageId == null) continue;
      await db
          .into(db.notePageHeadRows)
          .insert(
            NotePageHeadRowsCompanion.insert(
              id: json['id'] as String? ?? pageId,
              pageId: pageId,
              headIdsJson: jsonEncode(json['headIds'] ?? const []),
              selectedHeadId: Value(json['selectedHeadId'] as String?),
              updatedAt: json['updatedAt'] as String? ?? '',
            ),
          );
    }
    for (final item in data['pageTombstones'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      await db
          .into(db.notePageTombstoneRows)
          .insert(
            NotePageTombstoneRowsCompanion.insert(
              id: json['id'] as String,
              pageId: json['pageId'] as String,
              revisionId: json['revisionId'] as String,
              createdAt: json['createdAt'] as String? ?? '',
            ),
          );
    }
    for (final item in data['pageConflicts'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      await db
          .into(db.notePageConflictRows)
          .insert(
            NotePageConflictRowsCompanion.insert(
              pageId: json['pageId'] as String,
              headIdsJson: jsonEncode(json['headIds'] ?? const []),
              localHeadId: json['localHeadId'] as String? ?? '',
              incomingHeadId: json['incomingHeadId'] as String? ?? '',
              commonAncestorId: Value(json['commonAncestorId'] as String?),
              createdAt: json['createdAt'] as String? ?? '',
            ),
          );
    }
    for (final item in data['editProposals'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      final noteId = json['noteId'] as String?;
      if (id == null ||
          id.isEmpty ||
          noteId == null ||
          !noteIds.contains(noteId)) {
        continue;
      }
      await db
          .into(db.noteEditProposalRows)
          .insert(
            NoteEditProposalRowsCompanion.insert(
              id: id,
              noteId: noteId,
              pageId: Value(json['pageId'] as String?),
              baseRevisionId: Value(json['baseRevisionId'] as String?),
              baseContentHash: json['baseContentHash'] as String? ?? '',
              createdAt: json['createdAt'] as String? ?? '',
            ),
          );
      proposalIds.add(id);
    }
    for (final item in data['editBlocks'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      final proposalId = json['proposalId'] as String?;
      if (id == null ||
          id.isEmpty ||
          proposalId == null ||
          !proposalIds.contains(proposalId)) {
        continue;
      }
      await db
          .into(db.noteEditBlockRows)
          .insert(
            NoteEditBlockRowsCompanion.insert(
              id: id,
              proposalId: proposalId,
              startLine: (json['startLine'] as num?)?.toInt() ?? 1,
              deleteCount: (json['deleteCount'] as num?)?.toInt() ?? 0,
              deletedLinesJson: jsonEncode(json['deletedLines'] ?? const []),
              insertLinesJson: jsonEncode(json['insertLines'] ?? const []),
              sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
            ),
          );
    }
  }

  Future<void> _replaceSchedules(
    StorageV2DriftDatabase db,
    Map<String, dynamic> data,
  ) async {
    await db.delete(db.scheduleRows).go();
    for (final item in data['schedules'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      if (id == null || id.isEmpty) continue;
      await db
          .into(db.scheduleRows)
          .insert(
            ScheduleRowsCompanion.insert(
              id: id,
              title: json['title'] as String? ?? '',
              startTime: json['start'] as String? ?? '',
              endTime: json['end'] as String? ?? '',
              note: Value(json['note'] as String?),
              kind: json['kind'] as String? ?? 'schedule',
            ),
          );
    }
  }

  Future<void> _replaceTodoLists(
    StorageV2DriftDatabase db,
    Map<String, dynamic> data,
  ) async {
    await db.delete(db.todoItemRows).go();
    await db.delete(db.todoListRows).go();
    final listIds = <String>{};
    for (final item in data['todoLists'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      if (id == null || id.isEmpty) continue;
      await db
          .into(db.todoListRows)
          .insert(
            TodoListRowsCompanion.insert(
              id: id,
              title: json['title'] as String? ?? '',
              createdAt: json['createdAt'] as String? ?? '',
              updatedAt: json['updatedAt'] as String? ?? '',
            ),
          );
      listIds.add(id);
    }
    for (final item in data['todoItems'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      final listId = json['listId'] as String?;
      if (id == null ||
          id.isEmpty ||
          listId == null ||
          !listIds.contains(listId)) {
        continue;
      }
      await db
          .into(db.todoItemRows)
          .insert(
            TodoItemRowsCompanion.insert(
              id: id,
              listId: listId,
              itemText: json['text'] as String? ?? '',
              done: json['done'] == true ? 1 : 0,
              sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
              updatedAt: Value(json['updatedAt'] as String? ?? ''),
            ),
          );
    }
  }

  Future<void> _replaceRoleplayScenarios(
    StorageV2DriftDatabase db,
    Map<String, dynamic> data,
  ) async {
    await db.delete(db.roleplayScenarioRows).go();
    for (final item in data['scenarios'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      if (id == null || id.isEmpty) continue;
      await db
          .into(db.roleplayScenarioRows)
          .insert(
            RoleplayScenarioRowsCompanion.insert(
              id: id,
              dataJson: jsonEncode(json),
              updatedAt: json['updatedAt'] as String? ?? '',
            ),
          );
    }
    await _deleteMeta(db, 'datafile.roleplay_scenarios.json');
  }

  Future<void> _replaceRoleplayThreads(
    StorageV2DriftDatabase db,
    Map<String, dynamic> data,
  ) async {
    await db.delete(db.roleplayThreadRows).go();
    for (final item in data['threads'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      if (id == null || id.isEmpty) continue;
      await db
          .into(db.roleplayThreadRows)
          .insert(
            RoleplayThreadRowsCompanion.insert(
              id: id,
              dataJson: jsonEncode(json),
              updatedAt: json['updatedAt'] as String? ?? '',
            ),
          );
    }
    await _deleteMeta(db, 'datafile.roleplay_threads.json');
  }

  Future<void> _replaceRecycleBin(
    StorageV2DriftDatabase db,
    Map<String, dynamic> data,
  ) async {
    await db.delete(db.recycleBinRows).go();
    for (final item in data['items'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      if (id == null || id.isEmpty) continue;
      await db
          .into(db.recycleBinRows)
          .insert(
            RecycleBinRowsCompanion.insert(
              id: id,
              owner: json['owner'] as String? ?? 'core',
              category: json['category'] as String? ?? '',
              type: json['type'] as String? ?? '',
              title: json['title'] as String? ?? '',
              preview: json['preview'] as String? ?? '',
              payloadJson: jsonEncode(json['payload'] ?? const {}),
              deletedAt: json['deletedAt'] as String? ?? '',
            ),
          );
    }
    await _deleteMeta(db, 'datafile.recycle_bin.json');
  }

  Future<void> _replaceGenericDataFile(
    StorageV2DriftDatabase db,
    String fileName,
    Map<String, dynamic> data,
  ) {
    return _setMeta(db, 'datafile.$fileName', jsonEncode(data));
  }

  static const _syncTableNames = <String>{
    'resources',
    'conversations',
    'messages',
    'message_attachments',
    'schedules',
    'todo_lists',
    'todo_items',
    'roleplay_scenarios',
    'roleplay_threads',
    'recycle_bin',
    'note_folders',
    'notes',
    'note_pages',
    'note_revisions',
    'note_page_heads',
    'note_page_tombstones',
    'shared_settings',
    'synced_model_configs',
    'plugin_files',
    'plugin_settings',
    'plugin_config',
  };

  Set<String> _syncTablesForFile(String fileName) => switch (fileName) {
    'app_settings.json' => {'shared_settings'},
    'model_configs.json' => {'synced_model_configs'},
    'resources.json' => {'resources'},
    'conversations.json' => {
      'conversations',
      'messages',
      'message_attachments',
    },
    'schedules.json' => {'schedules'},
    'todo_lists.json' => {'todo_lists', 'todo_items'},
    'roleplay_scenarios.json' => {'roleplay_scenarios'},
    'roleplay_threads.json' => {'roleplay_threads'},
    'recycle_bin.json' => {'recycle_bin'},
    'notes.json' => {
      'note_folders',
      'notes',
      'note_pages',
      'note_revisions',
      'note_page_heads',
      'note_page_tombstones',
    },
    _ => const {},
  };

  Future<Map<String, Map<String, Map<String, dynamic>>>> _syncSnapshot(
    StorageV2DriftDatabase db,
    Set<String> tables,
  ) async {
    final result = <String, Map<String, Map<String, dynamic>>>{};
    void add(String table, Iterable<dynamic> rows) {
      if (!tables.contains(table)) return;
      result[table] = {
        for (final item in rows)
          if (item is Map && item['id'] is String)
            item['id'] as String: Map<String, dynamic>.from(item),
      };
    }

    if (tables.any(
      {'conversations', 'messages', 'message_attachments'}.contains,
    )) {
      final data = await _loadConversations(db);
      add('conversations', data['conversations'] as List);
      add('messages', data['messages'] as List);
      add('message_attachments', data['messageAttachments'] as List);
    }
    if (tables.contains('resources')) {
      add(
        'resources',
        ((await _loadResources(db))['resources'] as List).where(
          (item) =>
              item is Map &&
              (item['role'] == 'message_attachment' ||
                  item['role'] == 'message_image' ||
                  item['role'] == 'background'),
        ),
      );
    }
    if (tables.contains('shared_settings')) {
      final local = await _loadAppSettings(db);
      if (local.isNotEmpty) {
        add('shared_settings', [SharedSettingsV1.fromLocalJson(local).data]);
      }
    }
    if (tables.contains('synced_model_configs')) {
      final configs = (await _loadModelConfigs(db))['models'] as List;
      add(
        'synced_model_configs',
        configs.whereType<Map>().expand((raw) {
          try {
            final model = ModelConfig.fromJson(Map<String, dynamic>.from(raw));
            if (model.managed || !model.cloudSyncEnabled) return const [];
            return [SyncedModelConfigV1.fromLocal(model).data];
          } catch (_) {
            return const [];
          }
        }),
      );
    }
    if (tables.any(
      {'plugin_files', 'plugin_settings', 'plugin_config'}.contains,
    )) {
      final rows = await db
          .customSelect(
            "SELECT key, value FROM storage_meta WHERE key LIKE 'sync.plugin.%'",
          )
          .get();
      for (final row in rows) {
        final parts = _pluginSyncMetaParts(row.data['key'] as String);
        if (parts == null || !tables.contains(parts.$1)) continue;
        result.putIfAbsent(
          parts.$1,
          () => {},
        )[parts.$2] = Map<String, dynamic>.from(
          jsonDecode(row.data['value'] as String) as Map,
        );
      }
    }
    if (tables.contains('schedules')) {
      add('schedules', (await _loadSchedules(db))['schedules'] as List);
    }
    if (tables.any({'todo_lists', 'todo_items'}.contains)) {
      final data = await _loadTodoLists(db);
      add('todo_lists', data['todoLists'] as List);
      add('todo_items', data['todoItems'] as List);
    }
    if (tables.contains('roleplay_scenarios')) {
      add(
        'roleplay_scenarios',
        (await _loadRoleplayScenarios(db))['scenarios'] as List,
      );
    }
    if (tables.contains('roleplay_threads')) {
      add(
        'roleplay_threads',
        (await _loadRoleplayThreads(db))['threads'] as List,
      );
    }
    if (tables.contains('recycle_bin')) {
      add('recycle_bin', (await _loadRecycleBin(db))['items'] as List);
    }
    if (tables.any(
      {
        'note_folders',
        'notes',
        'note_pages',
        'note_revisions',
        'note_page_heads',
        'note_page_tombstones',
      }.contains,
    )) {
      final data = await _loadNotes(db);
      add('note_folders', data['folders'] as List);
      add('notes', data['notes'] as List);
      add('note_pages', data['pages'] as List);
      add('note_revisions', data['revisions'] as List);
      add('note_page_heads', data['pageHeads'] as List);
      add('note_page_tombstones', data['pageTombstones'] as List);
    }
    for (final table in tables) {
      result.putIfAbsent(table, () => {});
    }
    return result;
  }

  Future<void> _recordSnapshotDiff(
    StorageV2DriftDatabase db,
    Map<String, Map<String, Map<String, dynamic>>> before,
    Map<String, Map<String, Map<String, dynamic>>> after,
  ) async {
    final scopes = await _localCaptureStates(db);
    if (scopes.isEmpty) return;
    await _recordSnapshotDiffForScopes(
      db,
      before,
      after,
      scopes.map((scope) => (scope: scope.scope, deviceId: scope.deviceId)),
    );
  }

  Future<void> _recordSnapshotDiffForScopes(
    StorageV2DriftDatabase db,
    Map<String, Map<String, Map<String, dynamic>>> before,
    Map<String, Map<String, Map<String, dynamic>>> after,
    Iterable<({String scope, String deviceId})> scopes,
  ) async {
    for (final table in after.keys) {
      final oldRows = before[table] ?? const {};
      final newRows = after[table] ?? const {};
      for (final id in oldRows.keys.where((id) => !newRows.containsKey(id))) {
        for (final scope in scopes) {
          await _putOutbox(
            db,
            scope.scope,
            table,
            id,
            'delete',
            null,
            deviceId: scope.deviceId,
          );
        }
      }
      for (final row in newRows.entries) {
        if (jsonEncode(oldRows[row.key]) != jsonEncode(row.value)) {
          for (final scope in scopes) {
            await _putOutbox(
              db,
              scope.scope,
              table,
              row.key,
              'upsert',
              row.value,
              deviceId: scope.deviceId,
            );
          }
        }
      }
    }
  }

  Future<void> _migrateLegacySyncTables(StorageV2DriftDatabase db) async {
    if ((await db.select(db.roleplayScenarioRows).get()).isEmpty) {
      final legacy = await _loadGenericDataFile(db, 'roleplay_scenarios.json');
      if (legacy != null) await _replaceRoleplayScenarios(db, legacy);
    }
    if ((await db.select(db.roleplayThreadRows).get()).isEmpty) {
      final legacy = await _loadGenericDataFile(db, 'roleplay_threads.json');
      if (legacy != null) await _replaceRoleplayThreads(db, legacy);
    }
    if ((await db.select(db.recycleBinRows).get()).isEmpty) {
      final legacy = await _loadGenericDataFile(db, 'recycle_bin.json');
      if (legacy != null) await _replaceRecycleBin(db, legacy);
    }
  }

  Future<void> _putOutbox(
    StorageV2DriftDatabase db,
    String scope,
    String table,
    String recordId,
    String op,
    Map<String, dynamic>? data, {
    String? deviceId,
  }) async {
    final current =
        await (db.select(db.syncOutboxRows)..where(
              (row) =>
                  row.scope.equals(scope) &
                  row.table.equals(table) &
                  row.recordId.equals(recordId),
            ))
            .getSingleOrNull();
    final effectiveDeviceId =
        deviceId ??
        (await (db.select(
              db.syncStateRows,
            )..where((row) => row.scope.equals(scope))).getSingleOrNull())
            ?.deviceId ??
        '';
    final createdAt = DateTime.now().toUtc();
    await db
        .into(db.syncOutboxRows)
        .insertOnConflictUpdate(
          SyncOutboxRowsCompanion.insert(
            scope: scope,
            table: table,
            recordId: recordId,
            op: op,
            dataJson: Value(data == null ? null : jsonEncode(data)),
            changeId: _uuid.v4(),
            deviceId: effectiveDeviceId,
            clientCreatedAt: createdAt.toIso8601String(),
            mutationVersion: (current?.mutationVersion ?? 0) + 1,
            updatedAt: createdAt.toIso8601String(),
          ),
        );
  }

  Future<List<SyncStateRow>> _activeSyncStates(StorageV2DriftDatabase db) =>
      (db.select(db.syncStateRows)..where(
            (row) => row.initialized.equals(true) & row.active.equals(true),
          ))
          .get();

  Future<List<SyncStateRow>> _localCaptureStates(StorageV2DriftDatabase db) =>
      (db.select(db.syncStateRows)..where(
            (row) =>
                row.initialized.equals(true) & row.capturesLocal.equals(true),
          ))
          .get();

  Future<bool> _hasInitializedScopeInFamily(
    StorageV2DriftDatabase db,
    String scope,
  ) async {
    final states = await (db.select(
      db.syncStateRows,
    )..where((row) => row.initialized.equals(true))).get();
    return states.any(
      (state) =>
          state.scope != scope && _sameSyncScopeFamily(state.scope, scope),
    );
  }

  Future<void> _claimLocalCapture(
    StorageV2DriftDatabase db,
    String scope,
  ) async {
    final states = await (db.select(
      db.syncStateRows,
    )..where((row) => row.capturesLocal.equals(true))).get();
    for (final state in states) {
      if (state.scope == scope || !_sameSyncScopeFamily(state.scope, scope)) {
        continue;
      }
      await (db.update(
        db.syncStateRows,
      )..where((row) => row.scope.equals(state.scope))).write(
        SyncStateRowsCompanion(
          capturesLocal: const Value(false),
          updatedAt: Value(DateTime.now().toIso8601String()),
        ),
      );
    }
  }

  bool _sameSyncScopeFamily(String first, String second) =>
      first.startsWith('lan:') == second.startsWith('lan:');

  Future<bool> _hasPendingOutbox(
    StorageV2DriftDatabase db,
    String scope,
    String table,
    String recordId,
  ) async {
    final row =
        await (db.select(db.syncOutboxRows)..where(
              (item) =>
                  item.scope.equals(scope) &
                  item.table.equals(table) &
                  item.recordId.equals(recordId),
            ))
            .getSingleOrNull();
    return row != null;
  }

  Future<SyncOutboxRow?> _pendingOutbox(
    StorageV2DriftDatabase db,
    String scope,
    String table,
    String recordId,
  ) {
    return (db.select(db.syncOutboxRows)..where(
          (row) =>
              row.scope.equals(scope) &
              row.table.equals(table) &
              row.recordId.equals(recordId),
        ))
        .getSingleOrNull();
  }

  MergeAction _automaticConflictAction(
    String table,
    Map<String, dynamic>? local,
    Map<String, dynamic>? remote,
  ) {
    if (table == 'messages') {
      return MergePlanner.latestWins(local: local, incoming: remote);
    }
    if (table == 'todo_items') {
      return MergePlanner.latestWins(
        local: local,
        incoming: remote,
        revisionKey: '_unusedRevision',
      );
    }
    if (local != null &&
        remote != null &&
        jsonEncode(local) == jsonEncode(remote)) {
      return MergeAction.unchanged;
    }
    return MergeAction.conflict;
  }

  Future<void> _repairOutboxIdentity(
    StorageV2DriftDatabase db,
    String scope,
    String deviceId,
  ) async {
    final rows = await (db.select(
      db.syncOutboxRows,
    )..where((row) => row.scope.equals(scope))).get();
    for (final row in rows) {
      if (row.changeId.isNotEmpty &&
          row.deviceId.isNotEmpty &&
          row.clientCreatedAt.isNotEmpty) {
        continue;
      }
      final createdAt = row.updatedAt.isEmpty
          ? DateTime.now().toUtc().toIso8601String()
          : DateTime.parse(row.updatedAt).toUtc().toIso8601String();
      await (db.update(db.syncOutboxRows)..where(
            (item) =>
                item.scope.equals(scope) &
                item.table.equals(row.table) &
                item.recordId.equals(row.recordId),
          ))
          .write(
            SyncOutboxRowsCompanion(
              changeId: Value(row.changeId.isEmpty ? _uuid.v4() : row.changeId),
              deviceId: Value(row.deviceId.isEmpty ? deviceId : row.deviceId),
              clientCreatedAt: Value(
                row.clientCreatedAt.isEmpty ? createdAt : row.clientCreatedAt,
              ),
            ),
          );
    }
  }

  Future<void> _applySyncOperation(
    StorageV2DriftDatabase db,
    String table,
    String op,
    Map<String, dynamic> data,
  ) async {
    switch (table) {
      case 'resources':
        if (op == 'upsert') {
          await upsertResourceRow(data, transactionDb: db);
        } else {
          await deleteResourceRow(data['id'] as String, transactionDb: db);
        }
      case 'conversations':
        if (op == 'upsert') {
          await upsertConversationRow(data, transactionDb: db);
        } else {
          await deleteConversationRow(data['id'] as String, transactionDb: db);
        }
      case 'messages':
        if (op == 'upsert') {
          await upsertMessageRow(data, transactionDb: db);
        } else {
          await deleteMessageRow(data['id'] as String, transactionDb: db);
        }
      case 'message_attachments':
        if (op == 'upsert') {
          await upsertMessageAttachmentRow(data, transactionDb: db);
        } else {
          await deleteMessageAttachmentRow(
            data['id'] as String,
            transactionDb: db,
          );
        }
      case 'schedules':
        if (op == 'upsert') {
          await upsertScheduleRow(data, transactionDb: db);
        } else {
          await deleteScheduleRow(data['id'] as String, transactionDb: db);
        }
      case 'todo_lists':
        if (op == 'upsert') {
          await upsertTodoListRow(data, transactionDb: db);
        } else {
          await deleteTodoListRow(data['id'] as String, transactionDb: db);
        }
      case 'todo_items':
        if (op == 'upsert') {
          await upsertTodoItemRow(data, transactionDb: db);
        } else {
          await deleteTodoItemRow(data['id'] as String, transactionDb: db);
        }
      case 'roleplay_scenarios':
        if (op == 'upsert') {
          await upsertRoleplayScenarioRow(
            data['id'] as String,
            data,
            data['updatedAt'] as String? ?? '',
            transactionDb: db,
          );
        } else {
          await deleteRoleplayScenarioRow(
            data['id'] as String,
            transactionDb: db,
          );
        }
      case 'roleplay_threads':
        if (op == 'upsert') {
          await upsertRoleplayThreadRow(
            data['id'] as String,
            data,
            data['updatedAt'] as String? ?? '',
            transactionDb: db,
          );
        } else {
          await deleteRoleplayThreadRow(
            data['id'] as String,
            transactionDb: db,
          );
        }
      case 'recycle_bin':
        if (op == 'upsert') {
          await upsertRecycleBinRow(data, transactionDb: db);
        } else {
          await deleteRecycleBinRow(data['id'] as String, transactionDb: db);
        }
      case 'note_folders':
        await _applyNoteFolderOperation(db, op, data);
      case 'notes':
        await _applyNoteOperation(db, op, data);
      case 'note_pages':
        await _applyNotePageOperation(db, op, data);
      case 'note_revisions':
        await _applyNoteRevisionOperation(db, op, data);
      case 'note_page_heads':
        await _applyNotePageHeadOperation(db, op, data);
      case 'note_page_tombstones':
        await _applyNotePageTombstoneOperation(db, op, data);
      case 'shared_settings':
        if (op == 'upsert') {
          final local = await _loadAppSettings(db);
          await _replaceAppSettings(
            db,
            SharedSettingsV1.fromRemote(data).mergeIntoLocal(local),
          );
        }
      case 'synced_model_configs':
        await _applySyncedModelConfigOperation(db, op, data);
      case 'plugin_files':
      case 'plugin_settings':
      case 'plugin_config':
        await _applyPluginSyncMetadata(db, table, op, data);
      default:
        throw StateError('unsupported remote sync table: $table');
    }
  }

  Future<void> _applyPluginSyncMetadata(
    StorageV2DriftDatabase db,
    String table,
    String op,
    Map<String, dynamic> data,
  ) async {
    final id = data['id'] as String;
    final key = _pluginSyncMetaKey(table, id);
    if (op == 'delete') {
      await _deleteMeta(db, key);
    } else {
      await _setMeta(db, key, jsonEncode(data));
    }
  }

  String _pluginSyncMetaKey(String table, String id) =>
      'sync.plugin.$table.${base64UrlEncode(utf8.encode(id)).replaceAll('=', '')}';

  (String, String)? _pluginSyncMetaParts(String key) {
    final match = RegExp(
      r'^sync\.plugin\.(plugin_files|plugin_settings|plugin_config)\.([A-Za-z0-9_-]+)$',
    ).firstMatch(key);
    if (match == null) return null;
    try {
      return (
        match.group(1)!,
        utf8.decode(base64Url.decode(base64Url.normalize(match.group(2)!))),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _applySyncedModelConfigOperation(
    StorageV2DriftDatabase db,
    String op,
    Map<String, dynamic> data,
  ) async {
    final id = data['id'] as String;
    final existing = await (db.select(
      db.modelConfigRows,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (op == 'delete') {
      if (existing == null) return;
      final local = ModelConfig.fromJson(
        Map<String, dynamic>.from(jsonDecode(existing.configJson) as Map),
      );
      if (!local.managed && local.cloudSyncEnabled) {
        await (db.delete(
          db.modelConfigRows,
        )..where((row) => row.id.equals(id))).go();
      }
      return;
    }

    final existingJson = existing == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(existing.configJson) as Map);
    if (existingJson?['managed'] == true) return;
    if (existingJson != null && existingJson['cloudSyncEnabled'] != true) {
      return;
    }
    final localJson = SyncedModelConfigV1.fromRemote(
      data,
    ).toLocalJson(existing: existingJson);
    final model = ModelConfig.fromJson(localJson);
    await db
        .into(db.modelConfigRows)
        .insertOnConflictUpdate(
          ModelConfigRowsCompanion.insert(
            id: model.id,
            configJson: jsonEncode(localJson),
            category: model.category,
            enabled: model.enabledModelNames.isNotEmpty ? 1 : 0,
            priority: model.priority,
            updatedAt: DateTime.now().toIso8601String(),
          ),
        );
  }

  Future<void> _setSyncSince(
    StorageV2DriftDatabase db,
    String scope,
    int since,
  ) async {
    final updated =
        await (db.update(
          db.syncStateRows,
        )..where((row) => row.scope.equals(scope))).write(
          SyncStateRowsCompanion(
            since: Value(since),
            initialized: const Value(true),
            updatedAt: Value(DateTime.now().toIso8601String()),
          ),
        );
    if (updated == 0) {
      await db
          .into(db.syncStateRows)
          .insert(
            SyncStateRowsCompanion.insert(
              scope: scope,
              since: Value(since),
              initialized: const Value(true),
              deviceId: const Value(''),
              updatedAt: DateTime.now().toIso8601String(),
            ),
          );
    }
  }

  Map<String, dynamic> _resourceRow(ResourceRow row) => {
    'id': row.id,
    'kind': row.kind,
    'role': row.role,
    'originalPath': row.originalPath,
    'originalName': row.originalName,
    if (row.relativePath != null) 'relativePath': row.relativePath,
    'mimeType': row.mimeType,
    'size': row.size,
    if (row.sha256 != null) 'sha256': row.sha256,
    'missing': row.missing != 0,
  };

  Future<String?> _meta(StorageV2DriftDatabase db, String key) async {
    final row = await (db.select(
      db.storageMeta,
    )..where((table) => table.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _setMeta(StorageV2DriftDatabase db, String key, String value) {
    return db
        .into(db.storageMeta)
        .insertOnConflictUpdate(
          StorageMetaCompanion.insert(key: key, value: value),
        );
  }

  Future<void> _deleteMeta(StorageV2DriftDatabase db, String key) async {
    await (db.delete(db.storageMeta)..where((row) => row.key.equals(key))).go();
  }
}

class SyncOutboxEntry {
  final String table;
  final String recordId;
  final String op;
  final Map<String, dynamic>? data;
  final String changeId;
  final String deviceId;
  final DateTime clientCreatedAt;
  final int mutationVersion;

  const SyncOutboxEntry({
    required this.table,
    required this.recordId,
    required this.op,
    required this.data,
    required this.changeId,
    required this.deviceId,
    required this.clientCreatedAt,
    required this.mutationVersion,
  });
}

enum SyncConflictResolution { keepLocal, useRemote }

class SyncConflictEntry {
  final int seq;
  final String table;
  final String recordId;
  final String localOp;
  final Map<String, dynamic>? localData;
  final String remoteOp;
  final Map<String, dynamic>? remoteData;

  const SyncConflictEntry({
    required this.seq,
    required this.table,
    required this.recordId,
    required this.localOp,
    required this.localData,
    required this.remoteOp,
    required this.remoteData,
  });

  MergeConflictView get view => MergeConflictView(
    id: '$table:$recordId:$seq',
    domain: table,
    title: '$table / $recordId',
    localSummary: localOp == 'delete' ? '已删除' : _summary(localData),
    incomingSummary: remoteOp == 'delete' ? '已删除' : _summary(remoteData),
  );

  static String _summary(Map<String, dynamic>? data) {
    if (data == null) return '无数据';
    final title = data['title'] ?? data['text'] ?? data['content'];
    if (title != null) {
      final value = title.toString();
      return value.length > 80 ? '${value.substring(0, 80)}…' : value;
    }
    return '${data.length} 个字段';
  }
}

typedef SyncRemoteOperation = ({
  String table,
  String op,
  Map<String, dynamic>? data,
  SyncChange? change,
});
