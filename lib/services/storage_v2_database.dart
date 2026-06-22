import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

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
  TextColumn get parentRevisionId =>
      text().named('parent_revision_id').nullable()();
  TextColumn get savedAt => text().named('saved_at')();
  IntColumn get deltaStart => integer().named('delta_start')();
  TextColumn get deletedText => text().named('deleted_text')();
  TextColumn get insertedText => text().named('inserted_text')();

  @override
  Set<Column> get primaryKey => {id};
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

  @override
  Set<Column> get primaryKey => {id};
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
    NoteEditProposalRows,
    NoteEditBlockRows,
    ScheduleRows,
    TodoListRows,
    TodoItemRows,
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
  int get schemaVersion => 4;

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
    },
  );

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
}

class StorageV2Database {
  StorageV2Database(this.storageRoot);

  static final Map<String, StorageV2DriftDatabase> _openDatabases = {};
  // Multiple repository facades can point at the same app.db during startup.
  // Reference counts prevent one facade from closing another facade's handle.
  static final Map<String, int> _openReferenceCounts = {};
  static final Map<String, Future<StorageV2DriftDatabase>> _pendingOpens = {};

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
      _ => await _loadGenericDataFile(db, fileName),
    };
  }

  Future<void> writeDataFile(String fileName, Map<String, dynamic> data) async {
    final db = await _open();
    await db.transaction(() async {
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
        default:
          await _replaceGenericDataFile(db, fileName, data);
      }
      await _setMeta(
        db,
        'data.$fileName.updatedAt',
        DateTime.now().toIso8601String(),
      );
    });
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
  parent_revision_id TEXT,
  saved_at TEXT NOT NULL,
  delta_start INTEGER NOT NULL,
  deleted_text TEXT NOT NULL,
  inserted_text TEXT NOT NULL,
  FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE
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
  FOREIGN KEY (list_id) REFERENCES todo_lists(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_attachments_message ON message_attachments(message_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_note_pages_note ON note_pages(note_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_todo_items_list ON todo_items(list_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_resources_hash_size ON resources(sha256, size);
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
            )..orderBy([(table) => OrderingTerm.desc(table.savedAt)])).get())
            .map(
              (row) => {
                'id': row.id,
                'noteId': row.noteId,
                if (row.pageId != null) 'pageId': row.pageId,
                if (row.parentRevisionId != null)
                  'parentRevisionId': row.parentRevisionId,
                'savedAt': row.savedAt,
                'deltaStart': row.deltaStart,
                'deletedText': row.deletedText,
                'insertedText': row.insertedText,
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
              parentRevisionId: Value(json['parentRevisionId'] as String?),
              savedAt: json['savedAt'] as String? ?? '',
              deltaStart: (json['deltaStart'] as num?)?.toInt() ?? 0,
              deletedText: json['deletedText'] as String? ?? '',
              insertedText: json['insertedText'] as String? ?? '',
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
            ),
          );
    }
  }

  Future<void> _replaceGenericDataFile(
    StorageV2DriftDatabase db,
    String fileName,
    Map<String, dynamic> data,
  ) {
    return _setMeta(db, 'datafile.$fileName', jsonEncode(data));
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
}
