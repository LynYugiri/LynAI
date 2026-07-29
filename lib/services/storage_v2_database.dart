import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

import '../models/cloud_data.dart';
import '../models/agent_persistence.dart';
import '../models/model_config.dart';
import '../models/merge_models.dart';
import '../models/shared_sync_models.dart';
import '../models/sync_change.dart';
import '../models/sync_data_selection.dart';
import 'lynai_permission_definitions.dart';

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

  IntColumn get id => integer().customConstraint('NOT NULL CHECK (id = 1)')();
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
  TextColumn get modelContextContent =>
      text().named('model_context_content').nullable()();
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

class TaskRows extends Table {
  @override
  String get tableName => 'tasks';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get note => text().nullable()();
  TextColumn get plannedDate => text().named('planned_date').nullable()();
  TextColumn get plannedTime => text().named('planned_time').nullable()();
  TextColumn get dueDate => text().named('due_date').nullable()();
  TextColumn get dueTime => text().named('due_time').nullable()();
  TextColumn get completedAt => text().named('completed_at').nullable()();
  TextColumn get remindersJson =>
      text().named('reminders_json').withDefault(const Constant('[]'))();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class TaskListRows extends Table {
  @override
  String get tableName => 'task_lists';

  TextColumn get id => text()();
  TextColumn get title => text()();
  IntColumn get sortOrder => integer().named('sort_order')();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class TaskListEntryRows extends Table {
  @override
  String get tableName => 'task_list_entries';

  TextColumn get taskId => text()
      .named('task_id')
      .customConstraint('NOT NULL REFERENCES tasks(id) ON DELETE CASCADE')();
  TextColumn get listId => text()
      .named('list_id')
      .customConstraint(
        'NOT NULL REFERENCES task_lists(id) ON DELETE CASCADE',
      )();
  IntColumn get sortOrder => integer().named('sort_order')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {taskId};
}

class KnowledgeBaseRows extends Table {
  @override
  String get tableName => 'knowledge_bases';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().named('sort_order')();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class KnowledgeCategoryRows extends Table {
  @override
  String get tableName => 'knowledge_categories';

  TextColumn get id => text()();
  TextColumn get knowledgeBaseId => text()
      .named('knowledge_base_id')
      .customConstraint(
        'NOT NULL REFERENCES knowledge_bases(id) ON DELETE CASCADE',
      )();
  TextColumn get name => text()();
  TextColumn get alias => text().customConstraint(
    "NOT NULL UNIQUE CHECK (alias GLOB '[a-z]*' AND length(alias) BETWEEN 1 AND 32 AND alias NOT GLOB '*[^a-z0-9_-]*')",
  )();
  TextColumn get description => text().nullable()();
  TextColumn get annotationRule => text().named('annotation_rule')();
  TextColumn get explanationPrompt => text().named('explanation_prompt')();
  IntColumn get colorValue => integer().named('color_value')();
  BoolColumn get autoAnnotate => boolean().named('auto_annotate')();
  TextColumn get modelConfigId => text().named('model_config_id').nullable()();
  BoolColumn get isDefault => boolean().named('is_default')();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().named('sort_order')();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class KnowledgeSettingsRows extends Table {
  @override
  String get tableName => 'knowledge_settings';

  IntColumn get id => integer()();
  TextColumn get defaultKnowledgeBaseId => text()
      .named('default_knowledge_base_id')
      .nullable()
      .customConstraint(
        'NULL REFERENCES knowledge_bases(id) ON DELETE SET NULL',
      )();
  TextColumn get defaultCategoryId => text()
      .named('default_category_id')
      .nullable()
      .customConstraint(
        'NULL REFERENCES knowledge_categories(id) ON DELETE SET NULL',
      )();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  List<String> get customConstraints => [
    'CHECK (id = 1)',
    'CHECK ((default_knowledge_base_id IS NULL) = (default_category_id IS NULL))',
  ];

  @override
  Set<Column> get primaryKey => {id};
}

class KnowledgeEntryRows extends Table {
  @override
  String get tableName => 'knowledge_entries';

  TextColumn get id => text()();
  TextColumn get knowledgeBaseId => text()
      .named('knowledge_base_id')
      .customConstraint(
        'NOT NULL REFERENCES knowledge_bases(id) ON DELETE CASCADE',
      )();
  TextColumn get categoryId => text()
      .named('category_id')
      .nullable()
      .customConstraint(
        'NULL REFERENCES knowledge_categories(id) ON DELETE SET NULL',
      )();
  TextColumn get title => text()();
  TextColumn get content => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().named('sort_order')();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class KnowledgeSourceRows extends Table {
  @override
  String get tableName => 'knowledge_sources';

  TextColumn get id => text()();
  TextColumn get knowledgeBaseId => text()
      .named('knowledge_base_id')
      .customConstraint(
        'NOT NULL REFERENCES knowledge_bases(id) ON DELETE CASCADE',
      )();
  TextColumn get entryId => text()
      .named('entry_id')
      .customConstraint(
        'NOT NULL REFERENCES knowledge_entries(id) ON DELETE CASCADE',
      )();
  TextColumn get title => text()();
  TextColumn get url => text().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get sortOrder => integer().named('sort_order')();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class KnowledgeExplanationRows extends Table {
  @override
  String get tableName => 'knowledge_explanations';

  TextColumn get id => text()();
  TextColumn get knowledgeBaseId => text()
      .named('knowledge_base_id')
      .customConstraint(
        'NOT NULL REFERENCES knowledge_bases(id) ON DELETE CASCADE',
      )();
  TextColumn get entryId => text()
      .named('entry_id')
      .customConstraint(
        'NOT NULL REFERENCES knowledge_entries(id) ON DELETE CASCADE',
      )();
  TextColumn get title => text()();
  TextColumn get content => text()();
  IntColumn get sortOrder => integer().named('sort_order')();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class CalendarEventRows extends Table {
  @override
  String get tableName => 'calendar_events';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get note => text().nullable()();
  TextColumn get timeKind => text()
      .named('time_kind')
      .customConstraint("NOT NULL CHECK (time_kind IN ('timed', 'allDay'))")();
  TextColumn get startAt => text().named('start_at').nullable()();
  TextColumn get endAt => text().named('end_at').nullable()();
  TextColumn get startDate => text().named('start_date').nullable()();
  TextColumn get endDateExclusive =>
      text().named('end_date_exclusive').nullable()();
  TextColumn get remindersJson =>
      text().named('reminders_json').withDefault(const Constant('[]'))();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class AnniversaryRows extends Table {
  @override
  String get tableName => 'anniversaries';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get note => text().nullable()();
  IntColumn get month => integer()();
  IntColumn get day => integer()();
  IntColumn get year => integer().nullable()();
  TextColumn get recurrence => text().customConstraint(
    "NOT NULL CHECK (recurrence IN ('once', 'yearly'))",
  )();
  IntColumn get showYearCount => integer().named('show_year_count')();
  TextColumn get remindersJson =>
      text().named('reminders_json').withDefault(const Constant('[]'))();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();

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

@TableIndex(
  name: 'idx_sync_outbox_scope_updated_table_record',
  columns: {#scope, #updatedAt, #table, #recordId},
)
@TableIndex(
  name: 'idx_sync_outbox_scope_change_mutation',
  columns: {#scope, #changeId, #mutationVersion},
)
class SyncOutboxRows extends Table {
  @override
  String get tableName => 'sync_outbox';

  TextColumn get scope => text()();
  TextColumn get table => text().named('table_name')();
  TextColumn get recordId => text().named('record_id')();
  TextColumn get op => text()();
  TextColumn get dataJson => text().named('data_json').nullable()();
  TextColumn get selectionDataJson =>
      text().named('selection_data_json').nullable()();
  TextColumn get changeId => text().named('change_id')();
  TextColumn get deviceId => text().named('device_id')();
  TextColumn get clientCreatedAt => text().named('client_created_at')();
  IntColumn get mutationVersion => integer().named('mutation_version')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {scope, table, recordId};
}

@TableIndex(
  name: 'idx_sync_conflicts_scope_table_record',
  columns: {#scope, #table, #recordId},
)
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
  TextColumn get source => text().withDefault(const Constant('cloud'))();
  TextColumn get sourceScope => text().named('source_scope').nullable()();
  TextColumn get lineage => text().nullable()();
  TextColumn get payloadHash =>
      text().named('payload_hash').withDefault(const Constant(''))();

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
  IntColumn get generation => integer().withDefault(const Constant(0))();
  BoolColumn get fullReseedRequired => boolean()
      .named('full_reseed_required')
      .withDefault(const Constant(false))();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {scope};
}

class SyncPolicyRows extends Table {
  @override
  String get tableName => 'sync_policies';

  TextColumn get scope => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get categoriesJson => text().named('categories_json')();
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

  TextColumn get scope => text()();
  TextColumn get changeId => text().named('change_id')();
  TextColumn get source => text()();
  TextColumn get appliedAt => text().named('applied_at')();

  @override
  Set<Column> get primaryKey => {scope, changeId};
}

@TableIndex(
  name: 'idx_transport_change_heads_change',
  columns: {#changeId},
  unique: true,
)
class TransportChangeHeadRows extends Table {
  @override
  String get tableName => 'transport_change_heads';

  TextColumn get table => text().named('table_name')();
  TextColumn get recordId => text().named('record_id')();
  TextColumn get op => text()();
  TextColumn get dataJson => text().named('data_json').nullable()();
  TextColumn get selectionDataJson =>
      text().named('selection_data_json').nullable()();
  TextColumn get changeId => text().named('change_id')();
  TextColumn get deviceId => text().named('device_id')();
  TextColumn get clientCreatedAt => text().named('client_created_at')();
  IntColumn get mutationVersion => integer().named('mutation_version')();
  TextColumn get source => text()();
  TextColumn get sourceScope => text().named('source_scope').nullable()();
  TextColumn get lineage => text().nullable()();
  TextColumn get routeScope => text().named('route_scope').nullable()();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {table, recordId};
}

class TransportChangeReceiptRows extends Table {
  @override
  String get tableName => 'transport_change_receipts';

  TextColumn get changeId => text().named('change_id')();
  TextColumn get payloadHash => text().named('payload_hash')();
  TextColumn get source => text()();
  TextColumn get sourceScope => text().named('source_scope').nullable()();
  TextColumn get lineage => text().nullable()();
  TextColumn get receivedAt => text().named('received_at')();

  @override
  Set<Column> get primaryKey => {changeId};
}

@TableIndex(name: 'idx_transport_peer_acks_change', columns: {#changeId})
class TransportPeerAckRows extends Table {
  @override
  String get tableName => 'transport_peer_acks';

  TextColumn get peerDeviceId => text().named('peer_device_id')();
  TextColumn get changeId => text().named('change_id')();
  IntColumn get mutationVersion => integer().named('mutation_version')();
  TextColumn get acknowledgedAt => text().named('acknowledged_at')();

  @override
  Set<Column> get primaryKey => {peerDeviceId, changeId};
}

class CloudIndexStateRows extends Table {
  @override
  String get tableName => 'cloud_index_states';

  TextColumn get scope => text()();
  IntColumn get generation => integer().withDefault(const Constant(0))();
  TextColumn get statusJson =>
      text().named('status_json').withDefault(const Constant('{}'))();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {scope};
}

class CloudIndexObjectRows extends Table {
  @override
  String get tableName => 'cloud_index_objects';

  TextColumn get scope => text()();
  TextColumn get category => text()();
  TextColumn get objectId => text().named('object_id')();
  TextColumn get contentHash => text().named('content_hash')();
  TextColumn get objectJson =>
      text().named('object_json').withDefault(const Constant('{}'))();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {scope, category, objectId};
}

class CloudIndexCategoryStatRows extends Table {
  @override
  String get tableName => 'cloud_index_category_stats';

  TextColumn get scope => text()();
  TextColumn get category => text()();
  IntColumn get objectCount => integer().named('object_count')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {scope, category};
}

class CloudReseedTaskRows extends Table {
  @override
  String get tableName => 'cloud_reseed_tasks';

  TextColumn get scope => text()();
  TextColumn get operationId => text().named('operation_id')();
  IntColumn get generation => integer()();
  TextColumn get status => text()();
  TextColumn get operationJson =>
      text().named('operation_json').withDefault(const Constant('{}'))();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {scope, operationId};
}

class CloudRequestRows extends Table {
  @override
  String get tableName => 'cloud_requests';

  TextColumn get scope => text()();
  TextColumn get requestKey => text().named('request_key')();
  TextColumn get requestId => text().named('request_id')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {scope, requestKey};
}

class RunRows extends Table {
  @override
  String get tableName => 'runs';

  TextColumn get id => text()();
  TextColumn get conversationId => text().named('conversation_id').nullable()();
  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK (status IN ('queued', 'running', 'completed', 'failed', 'cancelled'))",
  )();
  TextColumn get errorCode => text().named('error_code').nullable()();
  TextColumn get errorMessage => text().named('error_message').nullable()();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();
  TextColumn get completedAt => text().named('completed_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(
  name: 'idx_turns_run_index',
  columns: {#runId, #turnIndex},
  unique: true,
)
class TurnRows extends Table {
  @override
  String get tableName => 'turns';

  TextColumn get id => text()();
  TextColumn get runId => text()
      .named('run_id')
      .customConstraint('NOT NULL REFERENCES runs(id) ON DELETE CASCADE')();
  IntColumn get turnIndex => integer().named('turn_index')();
  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled'))",
  )();
  TextColumn get errorCode => text().named('error_code').nullable()();
  TextColumn get errorMessage => text().named('error_message').nullable()();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();
  TextColumn get completedAt => text().named('completed_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(
  name: 'idx_items_turn_index',
  columns: {#turnId, #itemIndex},
  unique: true,
)
class ItemRows extends Table {
  @override
  String get tableName => 'items';

  TextColumn get id => text()();
  TextColumn get turnId => text()
      .named('turn_id')
      .customConstraint('NOT NULL REFERENCES turns(id) ON DELETE CASCADE')();
  IntColumn get itemIndex => integer().named('item_index')();
  TextColumn get kind => text().customConstraint(
    "NOT NULL CHECK (kind IN ('message', 'reasoning', 'toolCall', 'toolResult'))",
  )();
  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled'))",
  )();
  TextColumn get payloadJson => text().named('payload_json')();
  TextColumn get errorCode => text().named('error_code').nullable()();
  TextColumn get errorMessage => text().named('error_message').nullable()();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();
  TextColumn get completedAt => text().named('completed_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_tool_calls_item', columns: {#itemId})
class ToolCallRows extends Table {
  @override
  String get tableName => 'tool_calls';

  TextColumn get id => text()();
  TextColumn get itemId => text()
      .named('item_id')
      .customConstraint('NOT NULL REFERENCES items(id) ON DELETE CASCADE')();
  TextColumn get toolName => text().named('tool_name')();
  TextColumn get argumentsJson => text().named('arguments_json')();
  TextColumn get status => text().customConstraint(
    "NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled'))",
  )();
  TextColumn get resultJson => text().named('result_json').nullable()();
  TextColumn get errorCode => text().named('error_code').nullable()();
  TextColumn get errorMessage => text().named('error_message').nullable()();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();
  TextColumn get completedAt => text().named('completed_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_snapshots_run_created', columns: {#runId, #createdAt})
class SnapshotRows extends Table {
  @override
  String get tableName => 'snapshots';

  TextColumn get id => text()();
  TextColumn get runId => text()
      .named('run_id')
      .customConstraint('NOT NULL REFERENCES runs(id) ON DELETE CASCADE')();
  TextColumn get turnId => text()
      .named('turn_id')
      .customConstraint('NULL REFERENCES turns(id) ON DELETE CASCADE')
      .nullable()();
  TextColumn get kind => text()();
  TextColumn get dataJson => text().named('data_json')();
  TextColumn get createdAt => text().named('created_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class McpServerRows extends Table {
  @override
  String get tableName => 'mcp_servers';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get transport => text()();
  TextColumn get command => text().nullable()();
  TextColumn get url => text().nullable()();
  TextColumn get argumentsJson => text().named('arguments_json')();
  TextColumn get environmentNamesJson =>
      text().named('environment_names_json')();
  BoolColumn get enabled => boolean()();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncScopeState {
  final int since;
  final int generation;
  final bool fullReseedRequired;

  const SyncScopeState({
    required this.since,
    required this.generation,
    required this.fullReseedRequired,
  });
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
    TaskRows,
    TaskListRows,
    TaskListEntryRows,
    KnowledgeBaseRows,
    KnowledgeCategoryRows,
    KnowledgeSettingsRows,
    KnowledgeEntryRows,
    KnowledgeSourceRows,
    KnowledgeExplanationRows,
    CalendarEventRows,
    AnniversaryRows,
    RoleplayScenarioRows,
    RoleplayThreadRows,
    RecycleBinRows,
    SyncOutboxRows,
    SyncConflictRows,
    SyncStateRows,
    SyncPolicyRows,
    SyncScopeBaselineRows,
    SyncAppliedChangeRows,
    TransportChangeHeadRows,
    TransportChangeReceiptRows,
    TransportPeerAckRows,
    CloudIndexStateRows,
    CloudIndexObjectRows,
    CloudIndexCategoryStatRows,
    CloudReseedTaskRows,
    CloudRequestRows,
    RunRows,
    TurnRows,
    ItemRows,
    ToolCallRows,
    SnapshotRows,
    McpServerRows,
  ],
)
class StorageV2DriftDatabase extends _$StorageV2DriftDatabase {
  StorageV2DriftDatabase(File file) : super(_open(file));

  bool needsTransportHeadBackfill = false;

  static QueryExecutor _open(File file) {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    return NativeDatabase.createInBackground(file);
  }

  /// Version of app.db's internal SQLite schema.
  ///
  /// This is separate from [StorageV2Service.currentLayoutVersion], which
  /// describes the storage_v2 directory layout.
  @override
  int get schemaVersion => 26;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createPermissionPolicyIndex();
      await _createKnowledgeDefaultCategoryIndex();
      await _createKnowledgeAliasIndex();
      await _migrateKnowledgeSettingsV26();
    },
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
      if (from < 15) {
        await _migratePlanningSchemaV15(m);
      }
      if (from < 16) {
        if (await _tableExists('sync_outbox')) {
          await customStatement(
            'CREATE INDEX IF NOT EXISTS '
            'idx_sync_outbox_scope_updated_table_record '
            'ON sync_outbox(scope, updated_at, table_name, record_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS '
            'idx_sync_outbox_scope_change_mutation '
            'ON sync_outbox(scope, change_id, mutation_version)',
          );
        }
        if (await _tableExists('sync_conflicts')) {
          await customStatement(
            'CREATE INDEX IF NOT EXISTS '
            'idx_sync_conflicts_scope_table_record '
            'ON sync_conflicts(scope, table_name, record_id)',
          );
        }
      }
      if (from < 17) {
        await _migrateSyncSchemaV17(m);
      }
      if (from < 18) {
        await m.createTable(cloudRequestRows);
      }
      if (from < 19) {
        await _addColumnIfMissing('messages', 'model_context_content', 'TEXT');
      }
      if (from < 20) {
        await m.createTable(syncPolicyRows);
      }
      if (from < 21) {
        await _addColumnIfMissing('sync_outbox', 'selection_data_json', 'TEXT');
      }
      if (from < 22) {
        await m.createTable(runRows);
        await m.createTable(turnRows);
        await m.createTable(itemRows);
        await m.createTable(toolCallRows);
        await m.createTable(snapshotRows);
        await m.createTable(mcpServerRows);
      }
      if (from < 23) {
        await _createPermissionPolicyIndex();
      }
      if (from < 24) {
        needsTransportHeadBackfill = from == 23;
        await _createTransportLedgerTablesV24(m);
        await _addColumnIfMissing(
          'sync_conflicts',
          'source',
          "TEXT NOT NULL DEFAULT 'cloud'",
        );
        await _addColumnIfMissing('sync_conflicts', 'source_scope', 'TEXT');
        await _addColumnIfMissing('sync_conflicts', 'lineage', 'TEXT');
        await _addColumnIfMissing(
          'sync_conflicts',
          'payload_hash',
          "TEXT NOT NULL DEFAULT ''",
        );
        await _migrateTransportLedgerV24();
      }
      if (from < 25) {
        await m.createTable(knowledgeBaseRows);
        await m.createTable(knowledgeCategoryRows);
        await m.createTable(knowledgeEntryRows);
        await m.createTable(knowledgeSourceRows);
        await m.createTable(knowledgeExplanationRows);
        await _createKnowledgeDefaultCategoryIndex();
        await _createKnowledgeAliasIndex();
      }
      if (from < 26) {
        await m.createTable(knowledgeSettingsRows);
        await _migrateKnowledgeSettingsV26();
      }
      await _ensureCloudDataColumns();
    },
  );

  Future<void> _createPermissionPolicyIndex() {
    return customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_snapshots_permission_policy_run '
      "ON snapshots(run_id) WHERE kind = 'permission_policy'",
    );
  }

  Future<void> _createKnowledgeDefaultCategoryIndex() async {
    await customStatement(
      'DROP INDEX IF EXISTS idx_knowledge_categories_default',
    );
    await customStatement('''
UPDATE knowledge_categories
SET is_default = 0
WHERE is_default = 1
  AND id <> COALESCE((
    SELECT id FROM knowledge_categories
    WHERE is_default = 1
    ORDER BY sort_order, created_at, id
    LIMIT 1
  ), '')
''');
    await customStatement(
      'CREATE UNIQUE INDEX idx_knowledge_categories_default '
      'ON knowledge_categories(is_default) WHERE is_default = 1',
    );
  }

  Future<void> _createKnowledgeAliasIndex() => customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_knowledge_categories_alias '
    'ON knowledge_categories(alias)',
  );

  Future<void> _migrateKnowledgeSettingsV26() async {
    final now = DateTime.now().toUtc().toIso8601String();
    await customStatement(
      '''
INSERT OR REPLACE INTO knowledge_settings(
  id, default_knowledge_base_id, default_category_id, updated_at
)
SELECT 1, selected.knowledge_base_id, selected.id, ?
FROM (
  SELECT category.id, category.knowledge_base_id
  FROM knowledge_categories AS category
  JOIN knowledge_bases AS base ON base.id = category.knowledge_base_id
  WHERE base.enabled = 1
    AND category.enabled = 1
    AND category.auto_annotate = 1
  ORDER BY category.is_default DESC, base.sort_order, category.sort_order,
           category.created_at, category.id
  LIMIT 1
) AS selected
''',
      [now],
    );
    await customStatement(
      '''
INSERT OR IGNORE INTO knowledge_settings(
  id, default_knowledge_base_id, default_category_id, updated_at
) VALUES (1, NULL, NULL, ?)
''',
      [now],
    );
  }

  Future<void> _migrateTransportLedgerV24() async {
    if (!await _tableExists('sync_outbox')) return;
    await customStatement('''
INSERT OR IGNORE INTO transport_change_heads(
  table_name, record_id, op, data_json, selection_data_json, change_id,
  device_id, client_created_at, mutation_version, source, source_scope,
  lineage, route_scope, updated_at
)
SELECT table_name, record_id, op, data_json, selection_data_json, change_id,
       device_id, client_created_at, mutation_version, 'local', 'lan:v1',
       NULL, NULL, updated_at
FROM sync_outbox
WHERE scope = 'lan:v1' AND change_id <> ''
''');
    await customStatement('''
INSERT OR IGNORE INTO transport_change_receipts(
  change_id, payload_hash, source, source_scope, lineage, received_at
)
SELECT change_id, '', source, scope, NULL, applied_at
FROM sync_applied_changes
WHERE change_id <> ''
''');
    await customStatement("DELETE FROM sync_outbox WHERE scope = 'lan:v1'");
  }

  Future<void> _createTransportLedgerTablesV24(Migrator m) async {
    if (!await _tableExists('transport_change_heads')) {
      await m.createTable(transportChangeHeadRows);
    }
    if (!await _tableExists('transport_change_receipts')) {
      await m.createTable(transportChangeReceiptRows);
    }
    if (!await _tableExists('transport_peer_acks')) {
      await m.createTable(transportPeerAckRows);
    }
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_transport_change_heads_change '
      'ON transport_change_heads(change_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_transport_peer_acks_change '
      'ON transport_peer_acks(change_id)',
    );
  }

  Future<void> _migrateSyncSchemaV17(Migrator m) async {
    await _addColumnIfMissing(
      'sync_state',
      'generation',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      'sync_state',
      'full_reseed_required',
      'INTEGER NOT NULL DEFAULT 0',
    );

    if (await _tableExists('sync_applied_changes')) {
      await customStatement(
        'ALTER TABLE sync_applied_changes RENAME TO sync_applied_changes_v16',
      );
    }
    await m.createTable(syncAppliedChangeRows);
    if (await _tableExists('sync_applied_changes_v16')) {
      await customStatement('''
INSERT OR IGNORE INTO sync_applied_changes(scope, change_id, source, applied_at)
SELECT 'lan:v1', change_id, source, applied_at
FROM sync_applied_changes_v16
WHERE source = 'lan'
''');
      await customStatement('DROP TABLE sync_applied_changes_v16');
    }

    await m.createTable(cloudIndexStateRows);
    await m.createTable(cloudIndexObjectRows);
    await m.createTable(cloudIndexCategoryStatRows);
    await m.createTable(cloudReseedTaskRows);

    if (await _tableExists('sync_outbox')) {
      await customStatement(
        "DELETE FROM sync_outbox WHERE scope NOT LIKE 'lan:%' AND op <> 'delete'",
      );
    }
    if (await _tableExists('sync_conflicts')) {
      await customStatement(
        "DELETE FROM sync_conflicts WHERE scope NOT LIKE 'lan:%'",
      );
    }
    if (await _tableExists('sync_state')) {
      await customStatement('''
UPDATE sync_state
SET since = 0,
    initialized = 0,
    generation = 0,
    full_reseed_required = 1
WHERE scope NOT LIKE 'lan:%'
''');
    }
  }

  Future<void> _ensureCloudDataColumns() async {
    await _addColumnIfMissing(
      'cloud_index_states',
      'status_json',
      "TEXT NOT NULL DEFAULT '{}'",
    );
    await _addColumnIfMissing(
      'cloud_index_objects',
      'object_json',
      "TEXT NOT NULL DEFAULT '{}'",
    );
    await _addColumnIfMissing(
      'cloud_reseed_tasks',
      'operation_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      'cloud_reseed_tasks',
      'operation_json',
      "TEXT NOT NULL DEFAULT '{}'",
    );
    if (await _tableExists('cloud_reseed_tasks')) {
      final columns = await customSelect(
        'PRAGMA table_info(cloud_reseed_tasks)',
      ).get();
      final operationIdIsPrimaryKey = columns.any(
        (row) => row.data['name'] == 'operation_id' && row.data['pk'] == 2,
      );
      if (!operationIdIsPrimaryKey) {
        await customStatement(
          'ALTER TABLE cloud_reseed_tasks RENAME TO cloud_reseed_tasks_legacy',
        );
        await customStatement('''
CREATE TABLE cloud_reseed_tasks (
  scope TEXT NOT NULL,
  operation_id TEXT NOT NULL,
  generation INTEGER NOT NULL,
  status TEXT NOT NULL,
  operation_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (scope, operation_id)
)
''');
        await customStatement('''
INSERT OR IGNORE INTO cloud_reseed_tasks(
  scope, operation_id, generation, status, operation_json, created_at, updated_at
)
SELECT scope, operation_id, generation, status, operation_json, created_at, updated_at
FROM cloud_reseed_tasks_legacy
WHERE operation_id <> ''
''');
        await customStatement('DROP TABLE cloud_reseed_tasks_legacy');
      }
      await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_cloud_reseed_scope_operation '
        'ON cloud_reseed_tasks(scope, operation_id)',
      );
    }
  }

  Future<void> _migratePlanningSchemaV15(Migrator m) async {
    await m.createTable(taskRows);
    await m.createTable(taskListRows);
    await m.createTable(taskListEntryRows);
    await m.createTable(calendarEventRows);
    await m.createTable(anniversaryRows);
    final migrationTimestamp = DateTime.now().toIso8601String();

    if (await _tableExists('todo_lists')) {
      final lists = await customSelect(
        'SELECT id, title, created_at, updated_at FROM todo_lists ORDER BY rowid',
      ).get();
      for (var index = 0; index < lists.length; index++) {
        final row = lists[index];
        await into(taskListRows).insert(
          TaskListRowsCompanion.insert(
            id: row.read<String>('id'),
            title: row.read<String>('title'),
            sortOrder: index,
            createdAt: row.read<String>('created_at'),
            updatedAt: row.read<String>('updated_at'),
          ),
        );
      }
    }
    if (await _tableExists('todo_items')) {
      final items = await customSelect('''
SELECT i.id, i.list_id, i.text, i.done, i.sort_order, i.updated_at,
       l.created_at AS list_created_at, l.updated_at AS list_updated_at
FROM todo_items i
JOIN todo_lists l ON l.id = i.list_id
ORDER BY i.list_id, i.sort_order, i.rowid
''').get();
      for (final row in items) {
        final createdAt = row.read<String>('list_created_at');
        final itemUpdatedAt = row.read<String>('updated_at');
        final listUpdatedAt = row.read<String>('list_updated_at');
        final updatedAt = itemUpdatedAt.isNotEmpty
            ? itemUpdatedAt
            : listUpdatedAt.isNotEmpty
            ? listUpdatedAt
            : createdAt.isNotEmpty
            ? createdAt
            : migrationTimestamp;
        final id = row.read<String>('id');
        await into(taskRows).insert(
          TaskRowsCompanion.insert(
            id: id,
            title: row.read<String>('text'),
            completedAt: Value(row.read<int>('done') != 0 ? updatedAt : null),
            createdAt: createdAt.isEmpty ? migrationTimestamp : createdAt,
            updatedAt: updatedAt,
          ),
        );
        await into(taskListEntryRows).insert(
          TaskListEntryRowsCompanion.insert(
            taskId: id,
            listId: row.read<String>('list_id'),
            sortOrder: row.read<int>('sort_order'),
            updatedAt: updatedAt,
          ),
        );
      }
    }
    if (await _tableExists('schedules')) {
      final schedules = await customSelect(
        'SELECT id, title, start_time, end_time, note, kind '
        'FROM schedules ORDER BY rowid',
      ).get();
      for (final row in schedules) {
        final oldId = row.read<String>('id');
        final start = row.read<String>('start_time');
        final kind = row.read<String>('kind');
        if (kind == 'task') {
          var id = oldId;
          if (await _migrationRecordExists('tasks', id)) {
            final base = 'legacy-schedule-task-$oldId';
            id = base;
            var suffix = 2;
            while (await _migrationRecordExists('tasks', id)) {
              id = '$base-$suffix';
              suffix++;
            }
          }
          final migratedStart =
              DateTime.tryParse(start) ?? DateTime.parse(migrationTimestamp);
          final localStart = migratedStart.toLocal();
          await into(taskRows).insert(
            TaskRowsCompanion.insert(
              id: id,
              title: row.read<String>('title'),
              note: Value(row.readNullable<String>('note')),
              plannedDate: Value(_datePart(localStart)),
              plannedTime: Value(_timePart(localStart)),
              createdAt: start.isEmpty ? migrationTimestamp : start,
              updatedAt: start.isEmpty ? migrationTimestamp : start,
            ),
          );
        } else {
          await into(calendarEventRows).insert(
            CalendarEventRowsCompanion.insert(
              id: oldId,
              title: row.read<String>('title'),
              note: Value(row.readNullable<String>('note')),
              timeKind: 'timed',
              startAt: Value(start),
              endAt: Value(row.read<String>('end_time')),
              createdAt: start.isEmpty ? migrationTimestamp : start,
              updatedAt: start.isEmpty ? migrationTimestamp : start,
            ),
          );
        }
      }
    }

    // 旧规划数据与 v15 的同步协议不兼容，清空而不是尝试双协议转换。
    for (final table in [
      'sync_outbox',
      'sync_conflicts',
      'sync_scope_baselines',
    ]) {
      if (await _tableExists(table)) {
        await customStatement(
          'DELETE FROM $table WHERE table_name IN (?, ?, ?)',
          ['schedules', 'todo_lists', 'todo_items'],
        );
      }
    }
    if (await _tableExists('sync_state')) {
      // 强制所有既有作用域重新建立基线，使下次绑定上传完整的 v15 规范快照。
      await customStatement('UPDATE sync_state SET initialized = 0');
    }
    if (await _tableExists('todo_items')) {
      await customStatement('DROP TABLE todo_items');
    }
    if (await _tableExists('todo_lists')) {
      await customStatement('DROP TABLE todo_lists');
    }
    if (await _tableExists('schedules')) {
      await customStatement('DROP TABLE schedules');
    }
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_task_list_entries_list '
      'ON task_list_entries(list_id, sort_order)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tasks_planned '
      'ON tasks(planned_date, planned_time)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_calendar_events_start '
      'ON calendar_events(start_at, start_date)',
    );
  }

  Future<bool> _migrationRecordExists(String table, String id) async =>
      await customSelect(
        'SELECT 1 FROM $table WHERE id = ? LIMIT 1',
        variables: [Variable.withString(id)],
      ).getSingleOrNull() !=
      null;

  static String _datePart(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _timePart(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

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
  StorageV2Database(this.storageRoot, {bool Function()? isLeaseCurrent})
    : _isLeaseCurrent = isLeaseCurrent;

  static final Map<String, StorageV2DriftDatabase> _openDatabases = {};
  // Multiple repository facades can point at the same app.db during startup.
  // Reference counts prevent one facade from closing another facade's handle.
  static final Map<String, int> _openReferenceCounts = {};
  static final Map<String, Future<StorageV2DriftDatabase>> _pendingOpens = {};
  static const _uuid = Uuid();

  final Directory storageRoot;
  final bool Function()? _isLeaseCurrent;
  StorageV2DriftDatabase? _db;

  File get file => File('${storageRoot.path}/app.db');

  Future<bool> exists() async => file.exists();

  Future<void> ensureDatasetOwnership(String datasetId) async {
    final db = await _open();
    final current = await _meta(db, 'physical_dataset_id');
    if (current == null) {
      await _setMeta(db, 'physical_dataset_id', datasetId);
      return;
    }
    if (current != datasetId) {
      throw StateError('Database belongs to a different physical dataset');
    }
  }

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

  Future<void> insertAgentRun(AgentRunCreation creation) async {
    final db = await _open();
    final run = creation.run;
    await db.transaction(() async {
      await db
          .into(db.runRows)
          .insert(
            RunRowsCompanion.insert(
              id: run.id,
              conversationId: Value(run.conversationId),
              status: run.status.name,
              errorCode: Value(run.errorCode),
              errorMessage: Value(run.errorMessage),
              createdAt: run.createdAt.toIso8601String(),
              updatedAt: run.updatedAt.toIso8601String(),
              completedAt: Value(run.completedAt?.toIso8601String()),
            ),
          );
      await db
          .into(db.snapshotRows)
          .insert(
            SnapshotRowsCompanion.insert(
              id: _uuid.v4(),
              runId: run.id,
              turnId: const Value(null),
              kind: 'permission_policy',
              dataJson: jsonEncode(creation.permissionPolicy.toJson()),
              createdAt: run.createdAt.toIso8601String(),
            ),
          );
    });
  }

  Future<AgentPermissionSnapshot?> loadAgentPermissionSnapshot(
    String runId,
  ) async {
    final db = await _open();
    final row =
        await (db.select(db.snapshotRows)..where(
              (snapshot) =>
                  snapshot.runId.equals(runId) &
                  snapshot.kind.equals('permission_policy'),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return AgentPermissionSnapshot.fromJson(
      Map<String, dynamic>.from(jsonDecode(row.dataJson) as Map),
    );
  }

  Future<void> insertAgentTurn(AgentTurnRecord turn) async {
    final db = await _open();
    await db
        .into(db.turnRows)
        .insert(
          TurnRowsCompanion.insert(
            id: turn.id,
            runId: turn.runId,
            turnIndex: turn.index,
            status: turn.status.name,
            errorCode: Value(turn.errorCode),
            errorMessage: Value(turn.errorMessage),
            createdAt: turn.createdAt.toIso8601String(),
            updatedAt: turn.updatedAt.toIso8601String(),
            completedAt: Value(turn.completedAt?.toIso8601String()),
          ),
        );
  }

  Future<void> insertAgentItem(AgentItemRecord item) async {
    final db = await _open();
    await db
        .into(db.itemRows)
        .insert(
          ItemRowsCompanion.insert(
            id: item.id,
            turnId: item.turnId,
            itemIndex: item.index,
            kind: item.kind.name,
            status: item.status.name,
            payloadJson: jsonEncode(item.payload),
            errorCode: Value(item.errorCode),
            errorMessage: Value(item.errorMessage),
            createdAt: item.createdAt.toIso8601String(),
            updatedAt: item.updatedAt.toIso8601String(),
            completedAt: Value(item.completedAt?.toIso8601String()),
          ),
        );
  }

  Future<void> insertAgentToolCall(AgentToolCallRecord call) async {
    final db = await _open();
    await db
        .into(db.toolCallRows)
        .insert(
          ToolCallRowsCompanion.insert(
            id: call.id,
            itemId: call.itemId,
            toolName: call.toolName,
            argumentsJson: jsonEncode(call.arguments),
            status: call.status.name,
            resultJson: Value(
              call.result == null ? null : jsonEncode(call.result),
            ),
            errorCode: Value(call.errorCode),
            errorMessage: Value(call.errorMessage),
            createdAt: call.createdAt.toIso8601String(),
            updatedAt: call.updatedAt.toIso8601String(),
            completedAt: Value(call.completedAt?.toIso8601String()),
          ),
        );
  }

  Future<void> insertAgentSnapshot(AgentSnapshotRecord snapshot) async {
    final db = await _open();
    await db
        .into(db.snapshotRows)
        .insert(
          SnapshotRowsCompanion.insert(
            id: snapshot.id,
            runId: snapshot.runId,
            turnId: Value(snapshot.turnId),
            kind: snapshot.kind,
            dataJson: jsonEncode(snapshot.data),
            createdAt: snapshot.createdAt.toIso8601String(),
          ),
        );
  }

  Future<void> upsertAgentMcpServer(AgentMcpServerRecord server) async {
    final db = await _open();
    await db
        .into(db.mcpServerRows)
        .insertOnConflictUpdate(
          McpServerRowsCompanion.insert(
            id: server.id,
            name: server.name,
            transport: server.transport,
            command: Value(server.command),
            url: Value(server.url),
            argumentsJson: jsonEncode(server.arguments),
            environmentNamesJson: jsonEncode(server.environmentNames),
            enabled: server.enabled,
            createdAt: server.createdAt.toIso8601String(),
            updatedAt: server.updatedAt.toIso8601String(),
          ),
        );
  }

  Future<List<AgentMcpServerRecord>> loadAgentMcpServers() async {
    final db = await _open();
    final rows =
        await (db.select(db.mcpServerRows)..orderBy([
              (row) => OrderingTerm.asc(row.name),
              (row) => OrderingTerm.asc(row.id),
            ]))
            .get();
    return rows
        .map(
          (row) => AgentMcpServerRecord(
            id: row.id,
            name: row.name,
            transport: row.transport,
            command: row.command,
            url: row.url,
            arguments: (jsonDecode(row.argumentsJson) as List).cast<String>(),
            environmentNames: (jsonDecode(row.environmentNamesJson) as List)
                .cast<String>(),
            enabled: row.enabled,
            createdAt: DateTime.parse(row.createdAt),
            updatedAt: DateTime.parse(row.updatedAt),
          ),
        )
        .toList(growable: false);
  }

  Future<bool> compareAndSetAgentStatus({
    required String table,
    required String id,
    required String expectedStatus,
    required String nextStatus,
    required DateTime updatedAt,
    String? errorCode,
    String? errorMessage,
    Object? result,
  }) async {
    const allowedTables = {'runs', 'turns', 'items', 'tool_calls'};
    if (!allowedTables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'unsupported Agent table');
    }
    final db = await _open();
    final terminal = const {
      'completed',
      'failed',
      'cancelled',
    }.contains(nextStatus);
    final assignments = <String>[
      'status = ?',
      'updated_at = ?',
      'completed_at = ?',
      'error_code = ?',
      'error_message = ?',
    ];
    final variables = <Variable<Object>>[
      Variable.withString(nextStatus),
      Variable.withString(updatedAt.toIso8601String()),
      Variable<String>(terminal ? updatedAt.toIso8601String() : null),
      Variable<String>(errorCode),
      Variable<String>(errorMessage),
    ];
    if (table == 'tool_calls' && result != null) {
      assignments.add('result_json = ?');
      variables.add(Variable.withString(jsonEncode(result)));
    }
    variables.addAll([
      Variable.withString(id),
      Variable.withString(expectedStatus),
    ]);
    final changed = await db.customUpdate(
      'UPDATE $table SET ${assignments.join(', ')} '
      'WHERE id = ? AND status = ?',
      variables: variables,
      updates: switch (table) {
        'runs' => {db.runRows},
        'turns' => {db.turnRows},
        'items' => {db.itemRows},
        _ => {db.toolCallRows},
      },
    );
    return changed == 1;
  }

  Future<AgentRestartReconciliation> reconcileAgentRestart(
    DateTime reconciledAt,
  ) async {
    final db = await _open();
    return db.transaction(() async {
      final activeRunRows = await db.customSelect('''
SELECT DISTINCT runs.id
FROM runs
LEFT JOIN turns ON turns.run_id = runs.id
LEFT JOIN items ON items.turn_id = turns.id
LEFT JOIN tool_calls ON tool_calls.item_id = items.id
WHERE runs.status IN ('queued', 'running')
   OR turns.status IN ('pending', 'running')
   OR items.status IN ('pending', 'running')
   OR tool_calls.status IN ('pending', 'running')
ORDER BY runs.created_at, runs.id
''').get();
      if (activeRunRows.isEmpty) {
        return const AgentRestartReconciliation(
          runIds: [],
          turnCount: 0,
          itemCount: 0,
          toolCallCount: 0,
        );
      }
      final runIds = activeRunRows
          .map((row) => row.read<String>('id'))
          .toList(growable: false);
      final timestamp = reconciledAt.toIso8601String();
      final toolCalls = await db.customUpdate(
        '''
UPDATE tool_calls
SET status = 'failed', error_code = 'interrupted',
    error_message = 'Interrupted by application restart',
    updated_at = ?, completed_at = ?
WHERE status IN ('pending', 'running') AND item_id IN (
  SELECT items.id FROM items
  JOIN turns ON turns.id = items.turn_id
  WHERE turns.run_id IN (${List.filled(runIds.length, '?').join(', ')})
)
''',
        variables: [
          Variable.withString(timestamp),
          Variable.withString(timestamp),
          ...runIds.map(Variable.withString),
        ],
        updates: {db.toolCallRows},
      );
      final items = await db.customUpdate(
        '''
UPDATE items
SET status = 'failed', error_code = 'interrupted',
    error_message = 'Interrupted by application restart',
    updated_at = ?, completed_at = ?
WHERE status IN ('pending', 'running') AND turn_id IN (
  SELECT id FROM turns
  WHERE run_id IN (${List.filled(runIds.length, '?').join(', ')})
)
''',
        variables: [
          Variable.withString(timestamp),
          Variable.withString(timestamp),
          ...runIds.map(Variable.withString),
        ],
        updates: {db.itemRows},
      );
      final turns = await db.customUpdate(
        '''
UPDATE turns
SET status = 'failed', error_code = 'interrupted',
    error_message = 'Interrupted by application restart',
    updated_at = ?, completed_at = ?
WHERE status IN ('pending', 'running')
  AND run_id IN (${List.filled(runIds.length, '?').join(', ')})
''',
        variables: [
          Variable.withString(timestamp),
          Variable.withString(timestamp),
          ...runIds.map(Variable.withString),
        ],
        updates: {db.turnRows},
      );
      await db.customUpdate(
        '''
UPDATE runs
SET status = 'failed', error_code = 'interrupted',
    error_message = 'Interrupted by application restart; automatic replay is disabled',
    updated_at = ?, completed_at = ?
WHERE id IN (${List.filled(runIds.length, '?').join(', ')})
  AND status IN ('queued', 'running')
''',
        variables: [
          Variable.withString(timestamp),
          Variable.withString(timestamp),
          ...runIds.map(Variable.withString),
        ],
        updates: {db.runRows},
      );
      return AgentRestartReconciliation(
        runIds: runIds,
        turnCount: turns,
        itemCount: items,
        toolCallCount: toolCalls,
      );
    });
  }

  Future<Map<String, dynamic>?> loadDataFile(String fileName) async {
    final db = await _open();
    return switch (fileName) {
      'app_settings.json' => await _loadAppSettings(db),
      'model_configs.json' => await _loadModelConfigs(db),
      'conversations.json' => await _loadConversations(db),
      'notes.json' => await _loadNotes(db),
      'tasks.json' => await _loadTasks(db),
      'knowledge.json' => await _loadKnowledge(db),
      'calendar.json' => await _loadCalendar(db),
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
        case 'tasks.json':
          await _replaceTasks(db, data);
        case 'knowledge.json':
          await _replaceKnowledge(db, data);
        case 'calendar.json':
          await _replaceCalendar(db, data);
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
            modelContextContent: Value(json['modelContextContent'] as String?),
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
    final resourceId = json['resourceId'] as String?;
    if (resourceId != null && resourceId.isNotEmpty) {
      final resource = await (db.select(
        db.resourceRows,
      )..where((row) => row.id.equals(resourceId))).getSingleOrNull();
      if (resource == null) {
        final mimeType =
            json['mimeType'] as String? ?? 'application/octet-stream';
        await upsertResourceRow({
          'id': resourceId,
          'kind': mimeType.startsWith('image/') ? 'image' : 'file',
          'role': mimeType.startsWith('image/')
              ? 'message_image'
              : 'message_attachment',
          'originalName':
              json['displayName'] as String? ??
              json['name'] as String? ??
              'file',
          'mimeType': mimeType,
          'size': (json['size'] as num?)?.toInt() ?? 0,
          'missing': true,
        }, transactionDb: db);
      }
    }
    await db
        .into(db.messageAttachmentRows)
        .insertOnConflictUpdate(
          MessageAttachmentRowsCompanion.insert(
            id: id,
            messageId: json['messageId'] as String? ?? '',
            resourceId: Value(resourceId),
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

  Future<Map<String, dynamic>?> findResourceById(String id) async {
    final db = await _open();
    final row = await (db.select(
      db.resourceRows,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null ? null : _resourceRow(row);
  }

  Future<List<Map<String, dynamic>>> findResourcesByIds(
    Iterable<String> ids,
  ) async {
    final uniqueIds = ids.where((id) => id.isNotEmpty).toSet();
    if (uniqueIds.isEmpty) return const [];
    final db = await _open();
    final rows = await (db.select(
      db.resourceRows,
    )..where((table) => table.id.isIn(uniqueIds))).get();
    return rows.map(_resourceRow).toList(growable: false);
  }

  Future<void> upsertTaskRow(
    Map<String, dynamic> json, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return;
    await db
        .into(db.taskRows)
        .insertOnConflictUpdate(
          TaskRowsCompanion.insert(
            id: id,
            title: json['title'] as String? ?? '',
            note: Value(json['note'] as String?),
            plannedDate: Value(json['plannedDate'] as String?),
            plannedTime: Value(json['plannedTime'] as String?),
            dueDate: Value(json['dueDate'] as String?),
            dueTime: Value(json['dueTime'] as String?),
            completedAt: Value(json['completedAt'] as String?),
            remindersJson: Value(jsonEncode(json['reminders'] ?? const [])),
            createdAt: json['createdAt'] as String? ?? '',
            updatedAt: json['updatedAt'] as String? ?? '',
          ),
        );
  }

  Future<void> deleteTaskRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await (db.delete(db.taskRows)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertTaskListRow(
    Map<String, dynamic> json, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return;
    await db
        .into(db.taskListRows)
        .insertOnConflictUpdate(
          TaskListRowsCompanion.insert(
            id: id,
            title: json['title'] as String? ?? '',
            sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
            createdAt: json['createdAt'] as String? ?? '',
            updatedAt: json['updatedAt'] as String? ?? '',
          ),
        );
  }

  Future<void> deleteTaskListRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await (db.delete(db.taskListRows)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertTaskListEntryRow(
    Map<String, dynamic> json, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    final taskId = json['taskId'] as String? ?? json['id'] as String?;
    if (taskId == null || taskId.isEmpty) return;
    await db
        .into(db.taskListEntryRows)
        .insertOnConflictUpdate(
          TaskListEntryRowsCompanion.insert(
            taskId: taskId,
            listId: json['listId'] as String? ?? '',
            sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
            updatedAt: json['updatedAt'] as String? ?? '',
          ),
        );
  }

  Future<void> deleteTaskListEntryRow(
    String taskId, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await (db.delete(
      db.taskListEntryRows,
    )..where((t) => t.taskId.equals(taskId))).go();
  }

  Future<void> upsertKnowledgeBaseRow(
    Map<String, dynamic> json, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return;
    await db
        .into(db.knowledgeBaseRows)
        .insertOnConflictUpdate(
          KnowledgeBaseRowsCompanion.insert(
            id: id,
            name: json['name'] as String? ?? '',
            description: Value(json['description'] as String?),
            enabled: Value(json['enabled'] as bool? ?? true),
            sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
            createdAt: json['createdAt'] as String? ?? '',
            updatedAt: json['updatedAt'] as String? ?? '',
          ),
        );
  }

  Future<void> deleteKnowledgeBaseRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    if (transactionDb == null) {
      final db = await _open();
      await db.transaction(() => deleteKnowledgeBaseRow(id, transactionDb: db));
      return;
    }
    final db = transactionDb;
    await _clearKnowledgeSettingsForDefault(db, knowledgeBaseId: id);
    await (db.delete(
      db.knowledgeBaseRows,
    )..where((row) => row.id.equals(id))).go();
  }

  Future<void> upsertKnowledgeCategoryRow(
    Map<String, dynamic> json, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return;
    final baseId = json['knowledgeBaseId'] as String? ?? '';
    final enabled = json['enabled'] as bool? ?? true;
    final isDefault = (json['isDefault'] as bool? ?? false) && enabled;
    if (isDefault) {
      await (db.update(db.knowledgeCategoryRows)
            ..where((row) => row.id.equals(id).not()))
          .write(const KnowledgeCategoryRowsCompanion(isDefault: Value(false)));
    }
    await db
        .into(db.knowledgeCategoryRows)
        .insertOnConflictUpdate(
          KnowledgeCategoryRowsCompanion.insert(
            id: id,
            knowledgeBaseId: baseId,
            name: json['name'] as String? ?? '',
            alias: json['alias'] as String? ?? '',
            description: Value(json['description'] as String?),
            annotationRule: json['annotationRule'] as String? ?? '',
            explanationPrompt: json['explanationPrompt'] as String? ?? '',
            colorValue: (json['colorValue'] as num?)?.toInt() ?? 0,
            autoAnnotate: json['autoAnnotate'] as bool? ?? false,
            modelConfigId: Value(json['modelConfigId'] as String?),
            isDefault: isDefault,
            enabled: Value(enabled),
            sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
            createdAt: json['createdAt'] as String? ?? '',
            updatedAt: json['updatedAt'] as String? ?? '',
          ),
        );
  }

  Future<void> deleteKnowledgeCategoryRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    if (transactionDb == null) {
      final db = await _open();
      await db.transaction(
        () => deleteKnowledgeCategoryRow(id, transactionDb: db),
      );
      return;
    }
    final db = transactionDb;
    await _clearKnowledgeSettingsForDefault(db, categoryId: id);
    await (db.delete(
      db.knowledgeCategoryRows,
    )..where((row) => row.id.equals(id))).go();
  }

  Future<void> _clearKnowledgeSettingsForDefault(
    StorageV2DriftDatabase db, {
    String? knowledgeBaseId,
    String? categoryId,
  }) async {
    final matchesDefault = knowledgeBaseId != null
        ? db.knowledgeSettingsRows.defaultKnowledgeBaseId.equals(
            knowledgeBaseId,
          )
        : db.knowledgeSettingsRows.defaultCategoryId.equals(categoryId!);
    await (db.update(
      db.knowledgeSettingsRows,
    )..where((_) => matchesDefault)).write(
      KnowledgeSettingsRowsCompanion(
        defaultKnowledgeBaseId: const Value(null),
        defaultCategoryId: const Value(null),
        updatedAt: Value(DateTime.now().toUtc().toIso8601String()),
      ),
    );
  }

  Future<void> writeKnowledgeSettings(Map<String, dynamic> json) async {
    final db = await _open();
    await _upsertKnowledgeSettings(db, json);
  }

  Future<void> deleteKnowledgeSettings({
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await db.delete(db.knowledgeSettingsRows).go();
  }

  Future<void> _upsertKnowledgeSettings(
    StorageV2DriftDatabase db,
    Map<String, dynamic> json,
  ) async {
    final baseId = json['defaultKnowledgeBaseId'] as String?;
    final categoryId = json['defaultCategoryId'] as String?;
    if (baseId != null || categoryId != null) {
      if (baseId == null ||
          categoryId == null ||
          !await _knowledgeCategoryIsEligibleDefault(db, categoryId, baseId)) {
        throw StateError('Knowledge settings default category is invalid');
      }
    }
    await db
        .into(db.knowledgeSettingsRows)
        .insertOnConflictUpdate(
          KnowledgeSettingsRowsCompanion.insert(
            id: const Value(1),
            defaultKnowledgeBaseId: Value(baseId),
            defaultCategoryId: Value(categoryId),
            updatedAt:
                json['updatedAt'] as String? ??
                DateTime.now().toUtc().toIso8601String(),
          ),
        );
  }

  Future<bool> _knowledgeCategoryIsEligibleDefault(
    StorageV2DriftDatabase db,
    String categoryId,
    String baseId,
  ) async {
    final row = await db
        .customSelect(
          '''
SELECT 1
FROM knowledge_categories AS category
JOIN knowledge_bases AS base ON base.id = category.knowledge_base_id
WHERE category.id = ? AND category.knowledge_base_id = ?
  AND category.enabled = 1 AND category.auto_annotate = 1
  AND base.enabled = 1
LIMIT 1
''',
          variables: [
            Variable.withString(categoryId),
            Variable.withString(baseId),
          ],
        )
        .getSingleOrNull();
    return row != null;
  }

  Future<void> upsertKnowledgeEntryRow(
    Map<String, dynamic> json, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return;
    final baseId = json['knowledgeBaseId'] as String? ?? '';
    final categoryId = json['categoryId'] as String?;
    if (categoryId != null &&
        !await _knowledgeCategoryBelongsToBase(db, categoryId, baseId)) {
      throw StateError('Knowledge entry category does not belong to its base');
    }
    await db
        .into(db.knowledgeEntryRows)
        .insertOnConflictUpdate(
          KnowledgeEntryRowsCompanion.insert(
            id: id,
            knowledgeBaseId: baseId,
            categoryId: Value(categoryId),
            title: json['title'] as String? ?? '',
            content: json['content'] as String? ?? '',
            enabled: Value(json['enabled'] as bool? ?? true),
            sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
            createdAt: json['createdAt'] as String? ?? '',
            updatedAt: json['updatedAt'] as String? ?? '',
          ),
        );
  }

  Future<bool> _knowledgeCategoryBelongsToBase(
    StorageV2DriftDatabase db,
    String categoryId,
    String baseId,
  ) async {
    final row =
        await (db.select(db.knowledgeCategoryRows)..where(
              (item) =>
                  item.id.equals(categoryId) &
                  item.knowledgeBaseId.equals(baseId),
            ))
            .getSingleOrNull();
    return row != null;
  }

  Future<void> deleteKnowledgeEntryRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await (db.delete(
      db.knowledgeEntryRows,
    )..where((row) => row.id.equals(id))).go();
  }

  Future<void> upsertKnowledgeSourceRow(
    Map<String, dynamic> json, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return;
    final baseId = json['knowledgeBaseId'] as String? ?? '';
    final entryId = json['entryId'] as String? ?? '';
    if (!await _knowledgeEntryBelongsToBase(db, entryId, baseId)) {
      throw StateError('Knowledge source entry does not belong to its base');
    }
    await db
        .into(db.knowledgeSourceRows)
        .insertOnConflictUpdate(
          KnowledgeSourceRowsCompanion.insert(
            id: id,
            knowledgeBaseId: baseId,
            entryId: entryId,
            title: json['title'] as String? ?? '',
            url: Value(json['url'] as String?),
            note: Value(json['note'] as String?),
            sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
            createdAt: json['createdAt'] as String? ?? '',
            updatedAt: json['updatedAt'] as String? ?? '',
          ),
        );
  }

  Future<void> deleteKnowledgeSourceRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await (db.delete(
      db.knowledgeSourceRows,
    )..where((row) => row.id.equals(id))).go();
  }

  Future<void> upsertKnowledgeExplanationRow(
    Map<String, dynamic> json, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return;
    final baseId = json['knowledgeBaseId'] as String? ?? '';
    final entryId = json['entryId'] as String? ?? '';
    if (!await _knowledgeEntryBelongsToBase(db, entryId, baseId)) {
      throw StateError(
        'Knowledge explanation entry does not belong to its base',
      );
    }
    await db
        .into(db.knowledgeExplanationRows)
        .insertOnConflictUpdate(
          KnowledgeExplanationRowsCompanion.insert(
            id: id,
            knowledgeBaseId: baseId,
            entryId: entryId,
            title: json['title'] as String? ?? '',
            content: json['content'] as String? ?? '',
            sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
            createdAt: json['createdAt'] as String? ?? '',
            updatedAt: json['updatedAt'] as String? ?? '',
          ),
        );
  }

  Future<void> deleteKnowledgeExplanationRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await (db.delete(
      db.knowledgeExplanationRows,
    )..where((row) => row.id.equals(id))).go();
  }

  Future<bool> _knowledgeEntryBelongsToBase(
    StorageV2DriftDatabase db,
    String entryId,
    String knowledgeBaseId,
  ) async {
    if (entryId.isEmpty || knowledgeBaseId.isEmpty) return false;
    final row =
        await (db.select(db.knowledgeEntryRows)..where(
              (item) =>
                  item.id.equals(entryId) &
                  item.knowledgeBaseId.equals(knowledgeBaseId),
            ))
            .getSingleOrNull();
    return row != null;
  }

  Future<void> upsertCalendarEventRow(
    Map<String, dynamic> json, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return;
    await db
        .into(db.calendarEventRows)
        .insertOnConflictUpdate(
          CalendarEventRowsCompanion.insert(
            id: id,
            title: json['title'] as String? ?? '',
            note: Value(json['note'] as String?),
            timeKind: json['timeKind'] as String? ?? 'timed',
            startAt: Value(json['startAt'] as String?),
            endAt: Value(json['endAt'] as String?),
            startDate: Value(json['startDate'] as String?),
            endDateExclusive: Value(json['endDateExclusive'] as String?),
            remindersJson: Value(jsonEncode(json['reminders'] ?? const [])),
            createdAt: json['createdAt'] as String? ?? '',
            updatedAt: json['updatedAt'] as String? ?? '',
          ),
        );
  }

  Future<void> deleteCalendarEventRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await (db.delete(db.calendarEventRows)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertAnniversaryRow(
    Map<String, dynamic> json, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return;
    await db
        .into(db.anniversaryRows)
        .insertOnConflictUpdate(
          AnniversaryRowsCompanion.insert(
            id: id,
            title: json['title'] as String? ?? '',
            note: Value(json['note'] as String?),
            month: (json['month'] as num?)?.toInt() ?? 1,
            day: (json['day'] as num?)?.toInt() ?? 1,
            year: Value((json['year'] as num?)?.toInt()),
            recurrence: json['recurrence'] as String? ?? 'yearly',
            showYearCount: switch (json['showYearCount']) {
              true => 1,
              false || null => 0,
              final num value => value.toInt(),
              _ => 0,
            },
            remindersJson: Value(jsonEncode(json['reminders'] ?? const [])),
            createdAt: json['createdAt'] as String? ?? '',
            updatedAt: json['updatedAt'] as String? ?? '',
          ),
        );
  }

  Future<void> deleteAnniversaryRow(
    String id, {
    StorageV2DriftDatabase? transactionDb,
  }) async {
    final db = transactionDb ?? await _open();
    await (db.delete(db.anniversaryRows)..where((t) => t.id.equals(id))).go();
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
      await _ensureTransportHeads(db, deviceId);
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
      if (state != null || !sameFamilyExists) {
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
              since: Value(state?.since ?? 0),
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

  Future<SyncScopeState> syncScopeState(String scope) async {
    final db = await _open();
    final row = await (db.select(
      db.syncStateRows,
    )..where((row) => row.scope.equals(scope))).getSingleOrNull();
    return SyncScopeState(
      since: row?.since ?? 0,
      generation: row?.generation ?? 0,
      fullReseedRequired: row?.fullReseedRequired ?? false,
    );
  }

  Future<CloudDataSnapshot> loadCloudData(String scope) async {
    final db = await _open();
    final state = await (db.select(
      db.cloudIndexStateRows,
    )..where((row) => row.scope.equals(scope))).getSingleOrNull();
    final objectRows =
        await (db.select(db.cloudIndexObjectRows)
              ..where((row) => row.scope.equals(scope))
              ..orderBy([
                (row) => OrderingTerm.asc(row.category),
                (row) => OrderingTerm.asc(row.objectId),
              ]))
            .get();
    final statRows = await (db.select(
      db.cloudIndexCategoryStatRows,
    )..where((row) => row.scope.equals(scope))).get();
    CloudIndexStatus? status;
    if (state != null) {
      final decoded = jsonDecode(state.statusJson);
      if (decoded is Map) {
        status = CloudIndexStatus.fromJson(Map<String, dynamic>.from(decoded));
      }
    }
    final objects = <CloudIndexObject>[];
    for (final row in objectRows) {
      final decoded = jsonDecode(row.objectJson);
      if (decoded is Map) {
        objects.add(
          CloudIndexObject.fromJson(Map<String, dynamic>.from(decoded)),
        );
      }
    }
    return CloudDataSnapshot(
      status: status,
      objects: objects,
      categoryCounts: {
        for (final row in statRows) row.category: row.objectCount,
      },
      updatedAt: state == null ? null : DateTime.tryParse(state.updatedAt),
    );
  }

  Future<void> replaceCloudData(
    String scope,
    CloudIndexStatus status,
    List<CloudIndexObject> objects,
  ) async {
    final db = await _open();
    final now = DateTime.now().toIso8601String();
    await db.transaction(() async {
      await db
          .into(db.cloudIndexStateRows)
          .insertOnConflictUpdate(
            CloudIndexStateRowsCompanion.insert(
              scope: scope,
              generation: Value(status.generation),
              statusJson: Value(jsonEncode(status.toJson())),
              updatedAt: now,
            ),
          );
      await (db.delete(
        db.cloudIndexObjectRows,
      )..where((row) => row.scope.equals(scope))).go();
      await (db.delete(
        db.cloudIndexCategoryStatRows,
      )..where((row) => row.scope.equals(scope))).go();
      final counts = <String, int>{};
      for (final object in objects) {
        counts.update(object.category, (value) => value + 1, ifAbsent: () => 1);
        final objectJson = jsonEncode(object.toJson());
        await db
            .into(db.cloudIndexObjectRows)
            .insert(
              CloudIndexObjectRowsCompanion.insert(
                scope: scope,
                category: object.category,
                objectId: object.objectId,
                contentHash: sha256.convert(utf8.encode(objectJson)).toString(),
                objectJson: Value(objectJson),
                updatedAt: now,
              ),
            );
      }
      for (final entry in counts.entries) {
        await db
            .into(db.cloudIndexCategoryStatRows)
            .insert(
              CloudIndexCategoryStatRowsCompanion.insert(
                scope: scope,
                category: entry.key,
                objectCount: entry.value,
                updatedAt: now,
              ),
            );
      }
    });
  }

  Future<void> saveCloudOperations(
    String scope,
    Iterable<CloudManagementOperation> operations,
  ) async {
    final db = await _open();
    final now = DateTime.now().toIso8601String();
    for (final operation in operations) {
      await db
          .into(db.cloudReseedTaskRows)
          .insertOnConflictUpdate(
            CloudReseedTaskRowsCompanion.insert(
              scope: scope,
              operationId: operation.id,
              generation: operation.generation,
              status: 'pending',
              operationJson: Value(
                jsonEncode({
                  'id': operation.id,
                  'kind': operation.kind,
                  'selectorType': operation.selectorType,
                  if (operation.category != null)
                    'category': operation.category,
                  if (operation.objectId != null)
                    'objectId': operation.objectId,
                  'generation': operation.generation,
                  'indexRevision': operation.indexRevision,
                  'createdAt': operation.createdAt.toUtc().toIso8601String(),
                }),
              ),
              createdAt: operation.createdAt.toUtc().toIso8601String(),
              updatedAt: now,
            ),
          );
    }
  }

  Future<List<CloudManagementOperation>> loadCloudOperations(
    String scope,
  ) async {
    final db = await _open();
    final rows =
        await (db.select(db.cloudReseedTaskRows)
              ..where(
                (row) => row.scope.equals(scope) & row.status.equals('pending'),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
            .get();
    return rows
        .map(
          (row) => CloudManagementOperation.fromJson(
            Map<String, dynamic>.from(jsonDecode(row.operationJson) as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<void> removeCloudOperation(String scope, String operationId) async {
    final db = await _open();
    await (db.delete(db.cloudReseedTaskRows)..where(
          (row) =>
              row.scope.equals(scope) & row.operationId.equals(operationId),
        ))
        .go();
  }

  Future<void> reconcileCloudOperations(
    String scope,
    Iterable<CloudManagementOperation> operations,
  ) async {
    final ids = operations.map((operation) => operation.id).toSet();
    final db = await _open();
    await db.transaction(() async {
      final rows = await (db.select(
        db.cloudReseedTaskRows,
      )..where((row) => row.scope.equals(scope))).get();
      for (final row in rows) {
        if (!ids.contains(row.operationId)) {
          await (db.delete(db.cloudReseedTaskRows)..where(
                (item) =>
                    item.scope.equals(scope) &
                    item.operationId.equals(row.operationId),
              ))
              .go();
        }
      }
      final now = DateTime.now().toIso8601String();
      for (final operation in operations) {
        await db
            .into(db.cloudReseedTaskRows)
            .insertOnConflictUpdate(
              CloudReseedTaskRowsCompanion.insert(
                scope: scope,
                operationId: operation.id,
                generation: operation.generation,
                status: 'pending',
                operationJson: Value(
                  jsonEncode({
                    'id': operation.id,
                    'kind': operation.kind,
                    'selectorType': operation.selectorType,
                    if (operation.category != null)
                      'category': operation.category,
                    if (operation.objectId != null)
                      'objectId': operation.objectId,
                    'generation': operation.generation,
                    'indexRevision': operation.indexRevision,
                    'createdAt': operation.createdAt.toUtc().toIso8601String(),
                  }),
                ),
                createdAt: operation.createdAt.toUtc().toIso8601String(),
                updatedAt: now,
              ),
            );
      }
    });
  }

  Future<String?> loadCloudRequestId(String scope, String requestKey) async {
    final db = await _open();
    final row =
        await (db.select(db.cloudRequestRows)..where(
              (row) =>
                  row.scope.equals(scope) & row.requestKey.equals(requestKey),
            ))
            .getSingleOrNull();
    return row?.requestId;
  }

  Future<void> saveCloudRequestId(
    String scope,
    String requestKey,
    String requestId,
  ) async {
    final db = await _open();
    await db
        .into(db.cloudRequestRows)
        .insertOnConflictUpdate(
          CloudRequestRowsCompanion.insert(
            scope: scope,
            requestKey: requestKey,
            requestId: requestId,
            updatedAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
  }

  Future<void> removeCloudRequestId(String scope, String requestKey) async {
    final db = await _open();
    await (db.delete(db.cloudRequestRows)..where(
          (row) => row.scope.equals(scope) & row.requestKey.equals(requestKey),
        ))
        .go();
  }

  Future<void> requireCloudReseed(String scope, int generation) async {
    final db = await _open();
    await (db.update(
      db.syncStateRows,
    )..where((row) => row.scope.equals(scope))).write(
      SyncStateRowsCompanion(
        generation: Value(generation),
        fullReseedRequired: const Value(true),
        updatedAt: Value(DateTime.now().toIso8601String()),
      ),
    );
  }

  Future<SyncDataSelection> syncPolicy(String scope) async {
    final db = await _open();
    final row = await (db.select(
      db.syncPolicyRows,
    )..where((item) => item.scope.equals(scope))).getSingleOrNull();
    if (row == null) return SyncDataSelection.defaults;
    return SyncDataSelection.fromJson(jsonDecode(row.categoriesJson));
  }

  Future<void> saveSyncPolicy(
    String scope,
    SyncDataSelection selection, {
    required bool requireReseed,
  }) async {
    final db = await _open();
    await db.transaction(() async {
      await db
          .into(db.syncPolicyRows)
          .insertOnConflictUpdate(
            SyncPolicyRowsCompanion.insert(
              scope: scope,
              categoriesJson: jsonEncode(selection.toJson()),
              updatedAt: DateTime.now().toUtc().toIso8601String(),
            ),
          );
      if (requireReseed) {
        await (db.update(
          db.syncStateRows,
        )..where((row) => row.scope.equals(scope))).write(
          SyncStateRowsCompanion(
            fullReseedRequired: const Value(true),
            updatedAt: Value(DateTime.now().toUtc().toIso8601String()),
          ),
        );
      }
    });
  }

  Future<void> resetCloudSyncScope(String scope, int generation) async {
    if (scope.startsWith('lan:')) {
      throw ArgumentError.value(scope, 'scope', 'cloud scope is required');
    }
    final db = await _open();
    await db.transaction(() async {
      await (db.delete(db.syncOutboxRows)
            ..where((row) => row.scope.equals(scope) & row.op.equals('upsert')))
          .go();
      await (db.delete(
        db.syncConflictRows,
      )..where((row) => row.scope.equals(scope))).go();
      await (db.delete(
        db.syncAppliedChangeRows,
      )..where((row) => row.scope.equals(scope))).go();
      await (db.delete(
        db.syncScopeBaselineRows,
      )..where((row) => row.scope.equals(scope))).go();
      await (db.delete(
        db.cloudIndexStateRows,
      )..where((row) => row.scope.equals(scope))).go();
      await (db.delete(
        db.cloudIndexObjectRows,
      )..where((row) => row.scope.equals(scope))).go();
      await (db.delete(
        db.cloudIndexCategoryStatRows,
      )..where((row) => row.scope.equals(scope))).go();
      await (db.update(
        db.syncStateRows,
      )..where((row) => row.scope.equals(scope))).write(
        SyncStateRowsCompanion(
          since: const Value(0),
          initialized: const Value(true),
          generation: Value(generation),
          fullReseedRequired: const Value(true),
          updatedAt: Value(DateTime.now().toIso8601String()),
        ),
      );
    });
  }

  Future<void> prepareFullSyncSnapshot(String scope, int generation) async {
    final db = await _open();
    await db.transaction(() async {
      final state = await (db.select(
        db.syncStateRows,
      )..where((row) => row.scope.equals(scope))).getSingleOrNull();
      if (state == null || state.deviceId.isEmpty) {
        throw StateError('sync scope is not active');
      }
      final pendingDeletes =
          await (db.select(db.syncOutboxRows)..where(
                (row) => row.scope.equals(scope) & row.op.equals('delete'),
              ))
              .get();
      await (db.delete(db.syncOutboxRows)
            ..where((row) => row.scope.equals(scope) & row.op.equals('upsert')))
          .go();
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
            deviceId: state.deviceId,
          );
        }
      }
      for (final row in pendingDeletes) {
        await db
            .into(db.syncOutboxRows)
            .insertOnConflictUpdate(
              SyncOutboxRowsCompanion.insert(
                scope: row.scope,
                table: row.table,
                recordId: row.recordId,
                op: row.op,
                dataJson: Value(row.dataJson),
                selectionDataJson: Value(row.selectionDataJson),
                changeId: row.changeId,
                deviceId: row.deviceId,
                clientCreatedAt: row.clientCreatedAt,
                mutationVersion: row.mutationVersion,
                updatedAt: row.updatedAt,
              ),
            );
      }
      await (db.update(
        db.syncStateRows,
      )..where((row) => row.scope.equals(scope))).write(
        SyncStateRowsCompanion(
          since: const Value(0),
          generation: Value(generation),
          fullReseedRequired: const Value(false),
          updatedAt: Value(DateTime.now().toIso8601String()),
        ),
      );
    });
  }

  Future<Set<String>> reconcileCurrentCloudProjection(
    String scope,
    int generation,
    int minAvailableSeq,
    List<Map<String, dynamic>> records,
    Set<String> authoritativeTables,
  ) async {
    if (scope.startsWith('lan:') || generation < 1 || minAvailableSeq < 0) {
      throw ArgumentError('invalid cloud projection reseed metadata');
    }
    if (!authoritativeTables.every(_syncTableNames.contains)) {
      throw ArgumentError('cloud projection contains unsupported tables');
    }
    final remote = <String, Map<String, Map<String, dynamic>>>{
      for (final table in authoritativeTables) table: {},
    };
    for (final record in records) {
      final table = record['table'];
      final op = record['op'];
      final recordId = record['recordId'];
      final data = record['data'];
      if (table is! String ||
          !authoritativeTables.contains(table) ||
          op != 'upsert' ||
          recordId is! String ||
          recordId.isEmpty ||
          data is! Map) {
        throw const FormatException('invalid cloud projection record');
      }
      final parsed = Map<String, dynamic>.from(data);
      if (parsed['id'] != recordId ||
          remote[table]!.putIfAbsent(recordId, () => parsed) != parsed) {
        throw const FormatException('duplicate cloud projection record');
      }
    }
    final db = await _open();
    final changedTables = <String>{};
    await db.transaction(() async {
      final state = await (db.select(
        db.syncStateRows,
      )..where((row) => row.scope.equals(scope))).getSingleOrNull();
      if (state == null || state.deviceId.isEmpty) {
        throw StateError('sync scope is not active');
      }
      final local = await _syncSnapshot(db, authoritativeTables);
      final pending = await (db.select(
        db.syncOutboxRows,
      )..where((row) => row.scope.equals(scope))).get();
      final pendingKeys = {
        for (final row in pending) '${row.table}\u0000${row.recordId}',
      };
      for (final table in authoritativeTables) {
        final localRows = local[table] ?? const {};
        final remoteRows = remote[table] ?? const {};
        for (final entry in remoteRows.entries) {
          if (pendingKeys.contains('$table\u0000${entry.key}')) continue;
          if (jsonEncode(localRows[entry.key]) == jsonEncode(entry.value)) {
            continue;
          }
          await _applySyncOperation(db, table, 'upsert', entry.value);
          changedTables.add(table);
        }
        for (final entry in localRows.entries) {
          if (remoteRows.containsKey(entry.key) ||
              pendingKeys.contains('$table\u0000${entry.key}')) {
            continue;
          }
          await _applySyncOperation(db, table, 'delete', {
            'id': entry.key,
            ...entry.value,
          });
          changedTables.add(table);
        }
      }
      await (db.delete(
        db.syncConflictRows,
      )..where((row) => row.scope.equals(scope))).go();
      await (db.delete(
        db.syncAppliedChangeRows,
      )..where((row) => row.scope.equals(scope))).go();
      await (db.delete(
        db.syncScopeBaselineRows,
      )..where((row) => row.scope.equals(scope))).go();
      await (db.update(
        db.syncStateRows,
      )..where((row) => row.scope.equals(scope))).write(
        SyncStateRowsCompanion(
          since: Value(minAvailableSeq),
          generation: Value(generation),
          fullReseedRequired: const Value(false),
          updatedAt: Value(DateTime.now().toUtc().toIso8601String()),
        ),
      );
    });
    return changedTables;
  }

  Future<List<SyncOutboxEntry>> loadSyncOutbox(
    String scope, {
    int? limit,
    int offset = 0,
  }) async {
    final db = await _open();
    if (limit != null && limit <= 0) return const [];
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    final variables = <Variable>[Variable.withString(scope)];
    final pagination = limit == null ? '' : ' LIMIT ? OFFSET ?';
    if (limit != null) {
      variables.add(Variable.withInt(limit));
      variables.add(Variable.withInt(offset));
    }
    final rows = await db
        .customSelect(
          '''
SELECT * FROM sync_outbox
WHERE scope = ?
ORDER BY CASE
  WHEN table_name = 'note_folders' THEN 0
  WHEN table_name = 'notes' THEN 1
  WHEN table_name = 'tasks' AND op <> 'delete' THEN 0
  WHEN table_name = 'tasks' THEN 9
  WHEN table_name = 'task_lists' AND op <> 'delete' THEN 1
  WHEN table_name = 'task_lists' THEN 9
  WHEN table_name = 'task_list_entries' AND op = 'delete' THEN 0
  WHEN table_name = 'task_list_entries' THEN 2
  WHEN table_name = 'knowledge_bases' AND op <> 'delete' THEN 0
  WHEN table_name = 'knowledge_categories' AND op <> 'delete' THEN 1
  WHEN table_name = 'knowledge_settings' AND op = 'delete' THEN 0
  WHEN table_name = 'knowledge_settings' THEN 2
  WHEN table_name = 'knowledge_entries' AND op <> 'delete' THEN 3
  WHEN table_name IN ('knowledge_sources', 'knowledge_explanations') AND op = 'delete' THEN 0
  WHEN table_name IN ('knowledge_sources', 'knowledge_explanations') THEN 4
  WHEN table_name = 'knowledge_entries' THEN 7
  WHEN table_name = 'knowledge_categories' THEN 8
  WHEN table_name = 'knowledge_bases' THEN 9
  WHEN table_name = 'note_page_tombstones' AND op = 'delete' THEN 2
  WHEN table_name = 'note_pages' THEN 3
  WHEN table_name = 'note_revisions' THEN 4
  WHEN table_name = 'note_page_heads' THEN 5
  WHEN table_name = 'note_page_tombstones' THEN 6
  WHEN table_name = 'resources' THEN 7
  ELSE 10
END, client_created_at, updated_at, table_name, record_id$pagination
''',
          variables: variables,
          readsFrom: {db.syncOutboxRows},
        )
        .get();
    final entries = rows
        .map(
          (row) => SyncOutboxEntry(
            table: row.read<String>('table_name'),
            recordId: row.read<String>('record_id'),
            op: row.read<String>('op'),
            data: row.readNullable<String>('data_json') == null
                ? null
                : Map<String, dynamic>.from(
                    jsonDecode(row.read<String>('data_json')) as Map,
                  ),
            selectionData:
                row.readNullable<String>('selection_data_json') == null
                ? null
                : Map<String, dynamic>.from(
                    jsonDecode(row.read<String>('selection_data_json')) as Map,
                  ),
            changeId: row.read<String>('change_id'),
            deviceId: row.read<String>('device_id'),
            clientCreatedAt: DateTime.parse(
              row.read<String>('client_created_at'),
            ),
            mutationVersion: row.read<int>('mutation_version'),
          ),
        )
        .toList(growable: false);
    return entries;
  }

  Future<List<SyncOutboxEntry>> loadTransportHeadsForPeer(
    String peerDeviceId,
  ) async {
    final db = await _open();
    final rows = await db
        .customSelect(
          '''
SELECT h.*
FROM transport_change_heads h
LEFT JOIN transport_peer_acks a
  ON a.peer_device_id = ? AND a.change_id = h.change_id
WHERE a.change_id IS NULL OR a.mutation_version <> h.mutation_version
ORDER BY CASE
  WHEN h.table_name = 'note_folders' THEN 0
  WHEN h.table_name = 'notes' THEN 1
  WHEN h.table_name = 'tasks' AND h.op <> 'delete' THEN 0
  WHEN h.table_name = 'tasks' THEN 9
  WHEN h.table_name = 'task_lists' AND h.op <> 'delete' THEN 1
  WHEN h.table_name = 'task_lists' THEN 9
  WHEN h.table_name = 'task_list_entries' AND h.op = 'delete' THEN 0
  WHEN h.table_name = 'task_list_entries' THEN 2
  WHEN h.table_name = 'knowledge_bases' AND h.op <> 'delete' THEN 0
  WHEN h.table_name = 'knowledge_categories' AND h.op <> 'delete' THEN 1
  WHEN h.table_name = 'knowledge_settings' AND h.op = 'delete' THEN 0
  WHEN h.table_name = 'knowledge_settings' THEN 2
  WHEN h.table_name = 'knowledge_entries' AND h.op <> 'delete' THEN 3
  WHEN h.table_name IN ('knowledge_sources', 'knowledge_explanations') AND h.op = 'delete' THEN 0
  WHEN h.table_name IN ('knowledge_sources', 'knowledge_explanations') THEN 4
  WHEN h.table_name = 'knowledge_entries' THEN 7
  WHEN h.table_name = 'knowledge_categories' THEN 8
  WHEN h.table_name = 'knowledge_bases' THEN 9
  WHEN h.table_name = 'note_page_tombstones' AND h.op = 'delete' THEN 2
  WHEN h.table_name = 'note_pages' THEN 3
  WHEN h.table_name = 'note_revisions' THEN 4
  WHEN h.table_name = 'note_page_heads' THEN 5
  WHEN h.table_name = 'note_page_tombstones' THEN 6
  WHEN h.table_name = 'resources' THEN 7
  ELSE 10
END, h.client_created_at, h.updated_at, h.table_name, h.record_id
''',
          variables: [Variable.withString(peerDeviceId)],
          readsFrom: {db.transportChangeHeadRows, db.transportPeerAckRows},
        )
        .get();
    return rows.map(_transportEntryFromRow).toList(growable: false);
  }

  Future<void> acknowledgeTransportHeads(
    String peerDeviceId,
    List<SyncOutboxEntry> entries,
  ) async {
    if (entries.isEmpty) return;
    final db = await _open();
    await db.transaction(() async {
      final now = DateTime.now().toUtc().toIso8601String();
      for (final entry in entries) {
        final head =
            await (db.select(db.transportChangeHeadRows)..where(
                  (row) =>
                      row.changeId.equals(entry.changeId) &
                      row.mutationVersion.equals(entry.mutationVersion),
                ))
                .getSingleOrNull();
        if (head == null) continue;
        await db
            .into(db.transportPeerAckRows)
            .insertOnConflictUpdate(
              TransportPeerAckRowsCompanion.insert(
                peerDeviceId: peerDeviceId,
                changeId: entry.changeId,
                mutationVersion: entry.mutationVersion,
                acknowledgedAt: now,
              ),
            );
      }
    });
  }

  Future<void> importLegacyLanTransportState(
    Iterable<String> appliedChangeIds,
    Map<String, Iterable<String>> peerAcknowledgements,
  ) async {
    final db = await _open();
    await db.transaction(() async {
      final now = DateTime.now().toUtc().toIso8601String();
      for (final changeId in appliedChangeIds.where((id) => id.isNotEmpty)) {
        await db
            .into(db.transportChangeReceiptRows)
            .insert(
              TransportChangeReceiptRowsCompanion.insert(
                changeId: changeId,
                payloadHash: '',
                source: 'lan',
                sourceScope: const Value('legacy-secret-store'),
                receivedAt: now,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
      for (final peer in peerAcknowledgements.entries) {
        for (final changeId in peer.value.where((id) => id.isNotEmpty)) {
          final head = await (db.select(
            db.transportChangeHeadRows,
          )..where((row) => row.changeId.equals(changeId))).getSingleOrNull();
          await db
              .into(db.transportPeerAckRows)
              .insertOnConflictUpdate(
                TransportPeerAckRowsCompanion.insert(
                  peerDeviceId: peer.key,
                  changeId: changeId,
                  mutationVersion: head?.mutationVersion ?? 0,
                  acknowledgedAt: now,
                ),
              );
        }
      }
    });
  }

  SyncOutboxEntry _transportEntryFromRow(QueryRow row) => SyncOutboxEntry(
    table: row.read<String>('table_name'),
    recordId: row.read<String>('record_id'),
    op: row.read<String>('op'),
    data: row.readNullable<String>('data_json') == null
        ? null
        : Map<String, dynamic>.from(
            jsonDecode(row.read<String>('data_json')) as Map,
          ),
    selectionData: row.readNullable<String>('selection_data_json') == null
        ? null
        : Map<String, dynamic>.from(
            jsonDecode(row.read<String>('selection_data_json')) as Map,
          ),
    changeId: row.read<String>('change_id'),
    deviceId: row.read<String>('device_id'),
    clientCreatedAt: DateTime.parse(row.read<String>('client_created_at')),
    mutationVersion: row.read<int>('mutation_version'),
    lineage: row.readNullable<String>('lineage'),
  );

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
        final routeScope = conflict.source == 'lan'
            ? await _eligibleCloudRoute(db, conflict.lineage)
            : null;
        final routeState = routeScope == null
            ? null
            : await (db.select(db.syncStateRows)
                    ..where((row) => row.scope.equals(routeScope)))
                  .getSingleOrNull();
        await _putOutbox(
          db,
          routeScope ?? 'lan:v1',
          conflict.table,
          conflict.recordId,
          conflict.op,
          conflict.op == 'upsert' ? remoteData : null,
          deviceId: routeState?.deviceId ?? conflict.deviceId,
          changeId: conflict.changeId,
          clientCreatedAt: DateTime.parse(conflict.clientCreatedAt),
          source: conflict.source,
          sourceScope: conflict.sourceScope,
          lineage: conflict.lineage,
          routeScope: routeScope,
        );
        if (conflict.source == 'lan' && conflict.sourceScope != null) {
          final head =
              await (db.select(db.transportChangeHeadRows)
                    ..where((row) => row.changeId.equals(conflict.changeId)))
                  .getSingle();
          await db
              .into(db.transportPeerAckRows)
              .insertOnConflictUpdate(
                TransportPeerAckRowsCompanion.insert(
                  peerDeviceId: conflict.sourceScope!,
                  changeId: conflict.changeId,
                  mutationVersion: head.mutationVersion,
                  acknowledgedAt: DateTime.now().toUtc().toIso8601String(),
                ),
              );
        }
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
    String? appliedSourcePeer,
    Map<String, dynamic>? knowledgeSettings,
  }) async {
    if (remote && (scope == null || scope.isEmpty)) {
      throw ArgumentError.value(scope, 'scope', 'remote scope is required');
    }
    final db = await _open();
    await db.transaction(() async {
      final orderedOps = remote
          ? _latestRemoteOperations(
              ops,
              reliableSequence: appliedSource != 'lan',
            )
          : ops;
      if (remote) {
        final materializedChangeIds = orderedOps
            .map((op) => op.change?.changeId)
            .whereType<String>()
            .toSet();
        for (final op in ops) {
          final change = op.change;
          if (change == null ||
              materializedChangeIds.contains(change.changeId)) {
            continue;
          }
          await _recordSupersededRemoteOperation(
            db,
            op,
            scope: scope!,
            source: appliedSource,
            sourceScope: appliedSourcePeer ?? scope,
            sourcePeer: appliedSourcePeer,
          );
        }
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
        if (remote && _legacyPlanningSyncTableNames.contains(op.table)) {
          throw StateError(
            'sync schema upgrade required: legacy planning table '
            '${op.table} is not supported by storage schema v15',
          );
        }
        final changeId = op.change?.changeId;
        final remoteScope = remote ? scope : null;
        if (remoteScope != null && changeId != null) {
          final payloadHash = _changePayloadHash(op);
          final receipt = await (db.select(
            db.transportChangeReceiptRows,
          )..where((row) => row.changeId.equals(changeId))).getSingleOrNull();
          if (receipt != null) {
            if (receipt.payloadHash.isNotEmpty &&
                receipt.payloadHash != payloadHash) {
              throw StateError('sync changeId was reused with another payload');
            }
            continue;
          }
        }
        final id = op.data!['id'] as String;
        if (!_syncTableNames.contains(op.table)) {
          throw StateError('unsupported remote sync table: ${op.table}');
        }
        if (op.op != 'upsert' && op.op != 'delete') {
          throw StateError('unsupported remote sync operation: ${op.op}');
        }
        if (id.isEmpty) {
          throw StateError('remote sync operation is missing record id');
        }
        final pendingScope = remoteScope == 'lan:v1'
            ? await _eligibleCloudRoute(db, op.change?.lineage)
            : remoteScope;
        final local = pendingScope != null && !_isNoteDagTable(op.table)
            ? await _pendingOutbox(db, pendingScope, op.table, id)
            : null;
        if (local != null) {
          final conflictScope = remoteScope!;
          final change = op.change;
          if (change == null) {
            throw StateError('remote conflict metadata is missing');
          }
          if (local.op == 'delete') continue;
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
                      row.scope.equals(conflictScope) &
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
                    scope: conflictScope,
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
                    source: Value(appliedSource),
                    sourceScope: Value(appliedSourcePeer ?? remoteScope),
                    lineage: Value(op.change?.lineage),
                    payloadHash: Value(_changePayloadHash(op)),
                  ),
                );
            await _recordTransportReceipt(
              db,
              op,
              source: appliedSource,
              sourceScope: appliedSourcePeer ?? remoteScope,
            );
            await _recordSourcePeerAck(db, appliedSourcePeer, change.changeId);
            await (db.delete(db.syncOutboxRows)..where(
                  (row) =>
                      row.scope.equals(conflictScope) &
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
                    source: Value(appliedSource),
                    sourceScope: Value(appliedSourcePeer ?? remoteScope),
                    lineage: Value(op.change?.lineage),
                    payloadHash: Value(_changePayloadHash(op)),
                  ),
                );
            await _recordTransportReceipt(
              db,
              op,
              source: appliedSource,
              sourceScope: appliedSourcePeer ?? remoteScope,
            );
            await _recordSourcePeerAck(db, appliedSourcePeer, change.changeId);
            continue;
          }
        }
        final selectionData = op.op == 'delete'
            ? await _selectionDataForRow(db, op.table, id)
            : op.data;
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
          case 'tasks':
            if (op.op == 'upsert' && op.data != null) {
              await upsertTaskRow(op.data!, transactionDb: db);
            } else if (op.op == 'delete') {
              await deleteTaskRow(op.data!['id'] as String, transactionDb: db);
            }
          case 'task_lists':
            if (op.op == 'upsert' && op.data != null) {
              await upsertTaskListRow(op.data!, transactionDb: db);
            } else if (op.op == 'delete') {
              await deleteTaskListRow(
                op.data!['id'] as String,
                transactionDb: db,
              );
            }
          case 'task_list_entries':
            if (op.op == 'upsert' && op.data != null) {
              await upsertTaskListEntryRow(op.data!, transactionDb: db);
            } else if (op.op == 'delete') {
              await deleteTaskListEntryRow(
                op.data!['id'] as String,
                transactionDb: db,
              );
            }
          case 'knowledge_bases':
            if (op.op == 'upsert' && op.data != null) {
              await upsertKnowledgeBaseRow(op.data!, transactionDb: db);
            } else if (op.op == 'delete') {
              await deleteKnowledgeBaseRow(
                op.data!['id'] as String,
                transactionDb: db,
              );
            }
          case 'knowledge_categories':
            if (op.op == 'upsert' && op.data != null) {
              await upsertKnowledgeCategoryRow(op.data!, transactionDb: db);
            } else if (op.op == 'delete') {
              await deleteKnowledgeCategoryRow(
                op.data!['id'] as String,
                transactionDb: db,
              );
            }
          case 'knowledge_entries':
            if (op.op == 'upsert' && op.data != null) {
              await upsertKnowledgeEntryRow(op.data!, transactionDb: db);
            } else if (op.op == 'delete') {
              await deleteKnowledgeEntryRow(
                op.data!['id'] as String,
                transactionDb: db,
              );
            }
          case 'knowledge_sources':
            if (op.op == 'upsert' && op.data != null) {
              await upsertKnowledgeSourceRow(op.data!, transactionDb: db);
            } else if (op.op == 'delete') {
              await deleteKnowledgeSourceRow(
                op.data!['id'] as String,
                transactionDb: db,
              );
            }
          case 'knowledge_explanations':
            if (op.op == 'upsert' && op.data != null) {
              await upsertKnowledgeExplanationRow(op.data!, transactionDb: db);
            } else if (op.op == 'delete') {
              await deleteKnowledgeExplanationRow(
                op.data!['id'] as String,
                transactionDb: db,
              );
            }
          case 'knowledge_settings':
            if (id != 'global') {
              throw StateError('knowledge_settings record id must be global');
            }
            if (op.op == 'upsert' && op.data != null) {
              await _upsertKnowledgeSettings(db, op.data!);
            } else if (op.op == 'delete') {
              await deleteKnowledgeSettings(transactionDb: db);
            }
          case 'calendar_events':
            if (op.op == 'upsert' && op.data != null) {
              await upsertCalendarEventRow(op.data!, transactionDb: db);
            } else if (op.op == 'delete') {
              await deleteCalendarEventRow(
                op.data!['id'] as String,
                transactionDb: db,
              );
            }
          case 'anniversaries':
            if (op.op == 'upsert' && op.data != null) {
              await upsertAnniversaryRow(op.data!, transactionDb: db);
            } else if (op.op == 'delete') {
              await deleteAnniversaryRow(
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
              selectionData: selectionData,
              deviceId: targetScope.deviceId,
            );
          }
        }
        if (remoteScope != null && changeId != null) {
          final routeScope = appliedSource == 'lan'
              ? await _eligibleCloudRoute(db, op.change?.lineage)
              : null;
          final targetDeviceId = routeScope == null
              ? null
              : (await (db.select(db.syncStateRows)
                          ..where((row) => row.scope.equals(routeScope)))
                        .getSingle())
                    .deviceId;
          await _putOutbox(
            db,
            routeScope ?? 'lan:v1',
            op.table,
            id,
            op.op,
            op.op == 'upsert' ? op.data : null,
            selectionData: selectionData,
            deviceId: targetDeviceId ?? op.change?.deviceId,
            changeId: changeId,
            clientCreatedAt: op.change?.clientCreatedAt,
            source: appliedSource,
            sourceScope: appliedSourcePeer ?? remoteScope,
            lineage:
                op.change?.lineage ?? await _meta(db, 'physical_dataset_id'),
            routeScope: routeScope,
          );
          await _recordTransportReceipt(
            db,
            op,
            source: appliedSource,
            sourceScope: appliedSourcePeer ?? remoteScope,
          );
          if (appliedSourcePeer != null) {
            final head = await (db.select(
              db.transportChangeHeadRows,
            )..where((row) => row.changeId.equals(changeId))).getSingle();
            await db
                .into(db.transportPeerAckRows)
                .insertOnConflictUpdate(
                  TransportPeerAckRowsCompanion.insert(
                    peerDeviceId: appliedSourcePeer,
                    changeId: changeId,
                    mutationVersion: head.mutationVersion,
                    acknowledgedAt: DateTime.now().toUtc().toIso8601String(),
                  ),
                );
          }
          await db
              .into(db.syncAppliedChangeRows)
              .insert(
                SyncAppliedChangeRowsCompanion.insert(
                  scope: remoteScope,
                  changeId: changeId,
                  source: appliedSource,
                  appliedAt: DateTime.now().toUtc().toIso8601String(),
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }
      }
      if (!remote && knowledgeSettings != null) {
        await _upsertKnowledgeSettings(db, knowledgeSettings);
      }
      if (remote && scope != null && nextSince != null) {
        await _setSyncSince(db, scope, nextSince);
      }
    });
  }

  Future<void> _recordTransportReceipt(
    StorageV2DriftDatabase db,
    SyncRemoteOperation op, {
    required String source,
    required String? sourceScope,
  }) async {
    final change = op.change;
    if (change == null) return;
    await db
        .into(db.transportChangeReceiptRows)
        .insert(
          TransportChangeReceiptRowsCompanion.insert(
            changeId: change.changeId,
            payloadHash: _changePayloadHash(op),
            source: source,
            sourceScope: Value(sourceScope),
            lineage: Value(change.lineage),
            receivedAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
  }

  Future<void> _recordSupersededRemoteOperation(
    StorageV2DriftDatabase db,
    SyncRemoteOperation op, {
    required String scope,
    required String source,
    required String? sourceScope,
    required String? sourcePeer,
  }) async {
    final change = op.change;
    if (change == null) {
      throw StateError('remote change metadata is missing');
    }
    final payloadHash = _changePayloadHash(op);
    final receipt = await (db.select(
      db.transportChangeReceiptRows,
    )..where((row) => row.changeId.equals(change.changeId))).getSingleOrNull();
    if (receipt != null) {
      if (receipt.payloadHash.isNotEmpty &&
          receipt.payloadHash != payloadHash) {
        throw StateError('sync changeId was reused with another payload');
      }
      return;
    }
    _validateRemoteOperation(op);
    await _recordTransportReceipt(
      db,
      op,
      source: source,
      sourceScope: sourceScope,
    );
    await _recordSourcePeerAck(db, sourcePeer, change.changeId);
    await db
        .into(db.syncAppliedChangeRows)
        .insert(
          SyncAppliedChangeRowsCompanion.insert(
            scope: scope,
            changeId: change.changeId,
            source: source,
            appliedAt: DateTime.now().toUtc().toIso8601String(),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> _recordSourcePeerAck(
    StorageV2DriftDatabase db,
    String? peerDeviceId,
    String changeId,
  ) async {
    if (peerDeviceId == null || peerDeviceId.isEmpty) return;
    await db
        .into(db.transportPeerAckRows)
        .insertOnConflictUpdate(
          TransportPeerAckRowsCompanion.insert(
            peerDeviceId: peerDeviceId,
            changeId: changeId,
            mutationVersion: 0,
            acknowledgedAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
  }

  Future<String?> _eligibleCloudRoute(
    StorageV2DriftDatabase db,
    String? incomingLineage,
  ) async {
    final datasetLineage = await _meta(db, 'physical_dataset_id');
    if (incomingLineage == null || incomingLineage != datasetLineage) {
      return null;
    }
    final states =
        await (db.select(db.syncStateRows)..where(
              (row) =>
                  row.initialized.equals(true) & row.capturesLocal.equals(true),
            ))
            .get();
    for (final state in states) {
      if (!state.scope.startsWith('lan:')) return state.scope;
    }
    return null;
  }

  String _changePayloadHash(SyncRemoteOperation op) => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'table': op.table,
            'op': op.op,
            'recordId': op.data?['id'],
            if (op.op == 'upsert') 'data': _canonicalJson(op.data),
          }),
        ),
      )
      .toString();

  Object? _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonicalJson(value[key])};
    }
    if (value is List) return value.map(_canonicalJson).toList();
    return value;
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
      'tasks' => op == 'delete' ? 9 : 0,
      'task_lists' => op == 'delete' ? 9 : 1,
      'task_list_entries' => op == 'delete' ? 0 : 2,
      'knowledge_bases' => op == 'delete' ? 9 : 0,
      'knowledge_categories' => op == 'delete' ? 8 : 1,
      'knowledge_settings' => op == 'delete' ? 0 : 2,
      'knowledge_entries' => op == 'delete' ? 7 : 3,
      'knowledge_sources' || 'knowledge_explanations' => op == 'delete' ? 0 : 4,
      'note_pages' => 3,
      'note_revisions' => 4,
      'note_page_heads' => 5,
      'resources' => 7,
      _ => 10,
    };
  }

  static List<SyncRemoteOperation> _latestRemoteOperations(
    List<SyncRemoteOperation> ops, {
    required bool reliableSequence,
  }) {
    final latestByIdentity = <String, SyncRemoteOperation>{};
    for (final op in ops) {
      final id = op.data?['id'];
      if (id is! String || id.isEmpty || op.change == null) {
        latestByIdentity['invalid:${latestByIdentity.length}'] = op;
        continue;
      }
      final identity = '${op.table}\u0000$id';
      final current = latestByIdentity[identity];
      if (current == null ||
          !reliableSequence ||
          op.change!.seq >= (current.change?.seq ?? -1)) {
        latestByIdentity[identity] = op;
      }
    }
    return latestByIdentity.values.toList();
  }

  static void _validateRemoteOperation(SyncRemoteOperation op) {
    if (_legacyPlanningSyncTableNames.contains(op.table)) {
      throw StateError(
        'sync schema upgrade required: legacy planning table '
        '${op.table} is not supported by storage schema v15',
      );
    }
    if (!_syncTableNames.contains(op.table)) {
      throw StateError('unsupported remote sync table: ${op.table}');
    }
    if (op.op != 'upsert' && op.op != 'delete') {
      throw StateError('unsupported remote sync operation: ${op.op}');
    }
    final id = op.data?['id'];
    if (id is! String || id.isEmpty) {
      throw StateError('remote sync operation is missing record id');
    }
  }

  Future<StorageV2DriftDatabase> _open() async {
    if (_isLeaseCurrent?.call() == false) {
      throw StateError('Storage database lease belongs to a retired dataset');
    }
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
      if (db.needsTransportHeadBackfill) {
        final lanState = await (db.select(
          db.syncStateRows,
        )..where((row) => row.scope.equals('lan:v1'))).getSingleOrNull();
        await _ensureTransportHeads(db, lanState?.deviceId ?? '');
      }
      await db._ensureCloudDataColumns();
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
  model_context_content TEXT,
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
CREATE TABLE IF NOT EXISTS tasks (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  note TEXT,
  planned_date TEXT,
  planned_time TEXT,
  due_date TEXT,
  due_time TEXT,
  completed_at TEXT,
  reminders_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS task_lists (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS task_list_entries (
  task_id TEXT PRIMARY KEY,
  list_id TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
  FOREIGN KEY (list_id) REFERENCES task_lists(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS knowledge_bases (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  enabled INTEGER NOT NULL DEFAULT 1,
  sort_order INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS knowledge_categories (
  id TEXT PRIMARY KEY,
  knowledge_base_id TEXT NOT NULL,
  name TEXT NOT NULL,
  alias TEXT NOT NULL UNIQUE CHECK (
    alias GLOB '[a-z]*' AND length(alias) BETWEEN 1 AND 32
    AND alias NOT GLOB '*[^a-z0-9_-]*'
  ),
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
  updated_at TEXT NOT NULL,
  FOREIGN KEY (knowledge_base_id) REFERENCES knowledge_bases(id) ON DELETE CASCADE
);
DROP INDEX IF EXISTS idx_knowledge_categories_default;
UPDATE knowledge_categories
SET is_default = 0
WHERE is_default = 1
  AND id <> COALESCE((
    SELECT id FROM knowledge_categories
    WHERE is_default = 1
    ORDER BY sort_order, created_at, id
    LIMIT 1
  ), '');
CREATE UNIQUE INDEX idx_knowledge_categories_default
  ON knowledge_categories(is_default) WHERE is_default = 1;
CREATE UNIQUE INDEX IF NOT EXISTS idx_knowledge_categories_alias
  ON knowledge_categories(alias);
CREATE TABLE IF NOT EXISTS knowledge_settings (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  default_knowledge_base_id TEXT,
  default_category_id TEXT,
  updated_at TEXT NOT NULL,
  CHECK ((default_knowledge_base_id IS NULL) = (default_category_id IS NULL)),
  FOREIGN KEY (default_knowledge_base_id) REFERENCES knowledge_bases(id) ON DELETE SET NULL,
  FOREIGN KEY (default_category_id) REFERENCES knowledge_categories(id) ON DELETE SET NULL
);
CREATE TABLE IF NOT EXISTS knowledge_entries (
  id TEXT PRIMARY KEY,
  knowledge_base_id TEXT NOT NULL,
  category_id TEXT,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  sort_order INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (knowledge_base_id) REFERENCES knowledge_bases(id) ON DELETE CASCADE,
  FOREIGN KEY (category_id) REFERENCES knowledge_categories(id) ON DELETE SET NULL
);
CREATE TABLE IF NOT EXISTS knowledge_sources (
  id TEXT PRIMARY KEY,
  knowledge_base_id TEXT NOT NULL,
  entry_id TEXT NOT NULL,
  title TEXT NOT NULL,
  url TEXT,
  note TEXT,
  sort_order INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (knowledge_base_id) REFERENCES knowledge_bases(id) ON DELETE CASCADE,
  FOREIGN KEY (entry_id) REFERENCES knowledge_entries(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS knowledge_explanations (
  id TEXT PRIMARY KEY,
  knowledge_base_id TEXT NOT NULL,
  entry_id TEXT NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (knowledge_base_id) REFERENCES knowledge_bases(id) ON DELETE CASCADE,
  FOREIGN KEY (entry_id) REFERENCES knowledge_entries(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS calendar_events (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  note TEXT,
  time_kind TEXT NOT NULL CHECK (time_kind IN ('timed', 'allDay')),
  start_at TEXT,
  end_at TEXT,
  start_date TEXT,
  end_date_exclusive TEXT,
  reminders_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS anniversaries (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  note TEXT,
  month INTEGER NOT NULL,
  day INTEGER NOT NULL,
  year INTEGER,
  recurrence TEXT NOT NULL CHECK (recurrence IN ('once', 'yearly')),
  show_year_count INTEGER NOT NULL,
  reminders_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS runs (
  id TEXT PRIMARY KEY,
  conversation_id TEXT,
  status TEXT NOT NULL CHECK (status IN ('queued', 'running', 'completed', 'failed', 'cancelled')),
  error_code TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT
);
CREATE TABLE IF NOT EXISTS turns (
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
  turn_index INTEGER NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
  error_code TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT
);
CREATE TABLE IF NOT EXISTS items (
  id TEXT PRIMARY KEY,
  turn_id TEXT NOT NULL REFERENCES turns(id) ON DELETE CASCADE,
  item_index INTEGER NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('message', 'reasoning', 'toolCall', 'toolResult')),
  status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
  payload_json TEXT NOT NULL,
  error_code TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT
);
CREATE TABLE IF NOT EXISTS tool_calls (
  id TEXT PRIMARY KEY,
  item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  tool_name TEXT NOT NULL,
  arguments_json TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
  result_json TEXT,
  error_code TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT
);
CREATE TABLE IF NOT EXISTS snapshots (
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
  turn_id TEXT REFERENCES turns(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  data_json TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS mcp_servers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  transport TEXT NOT NULL,
  command TEXT,
  url TEXT,
  arguments_json TEXT NOT NULL,
  environment_names_json TEXT NOT NULL,
  enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_turns_run_index ON turns(run_id, turn_index);
CREATE UNIQUE INDEX IF NOT EXISTS idx_items_turn_index ON items(turn_id, item_index);
CREATE INDEX IF NOT EXISTS idx_tool_calls_item ON tool_calls(item_id);
CREATE INDEX IF NOT EXISTS idx_snapshots_run_created ON snapshots(run_id, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_snapshots_permission_policy_run ON snapshots(run_id) WHERE kind = 'permission_policy';
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_attachments_message ON message_attachments(message_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_note_pages_note ON note_pages(note_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_note_revisions_page_created ON note_revisions(page_id, created_at);
CREATE INDEX IF NOT EXISTS idx_note_revisions_content_hash ON note_revisions(content_hash);
CREATE UNIQUE INDEX IF NOT EXISTS idx_note_page_heads_page ON note_page_heads(page_id);
CREATE INDEX IF NOT EXISTS idx_note_page_tombstones_page ON note_page_tombstones(page_id);
CREATE INDEX IF NOT EXISTS idx_task_list_entries_list ON task_list_entries(list_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_tasks_planned ON tasks(planned_date, planned_time);
CREATE INDEX IF NOT EXISTS idx_calendar_events_start ON calendar_events(start_at, start_date);
CREATE INDEX IF NOT EXISTS idx_resources_hash_size ON resources(sha256, size);
CREATE TABLE IF NOT EXISTS sync_outbox (
  scope TEXT NOT NULL,
  table_name TEXT NOT NULL,
  record_id TEXT NOT NULL,
  op TEXT NOT NULL,
  data_json TEXT,
  selection_data_json TEXT,
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
CREATE INDEX IF NOT EXISTS idx_sync_outbox_scope_updated_table_record ON sync_outbox(scope, updated_at, table_name, record_id);
CREATE INDEX IF NOT EXISTS idx_sync_outbox_scope_change_mutation ON sync_outbox(scope, change_id, mutation_version);
CREATE INDEX IF NOT EXISTS idx_sync_conflicts_scope_table_record ON sync_conflicts(scope, table_name, record_id);
CREATE TABLE IF NOT EXISTS sync_state (
  scope TEXT PRIMARY KEY,
  since INTEGER NOT NULL DEFAULT 0,
  initialized INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 0,
  captures_local INTEGER NOT NULL DEFAULT 0,
  device_id TEXT NOT NULL DEFAULT '',
  generation INTEGER NOT NULL DEFAULT 0,
  full_reseed_required INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sync_applied_changes (
  scope TEXT NOT NULL,
  change_id TEXT NOT NULL,
  source TEXT NOT NULL,
  applied_at TEXT NOT NULL,
  PRIMARY KEY (scope, change_id)
);
CREATE TABLE IF NOT EXISTS cloud_index_states (
  scope TEXT PRIMARY KEY,
  generation INTEGER NOT NULL DEFAULT 0,
  status_json TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS cloud_index_objects (
  scope TEXT NOT NULL,
  category TEXT NOT NULL,
  object_id TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  object_json TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL,
  PRIMARY KEY (scope, category, object_id)
);
CREATE TABLE IF NOT EXISTS cloud_index_category_stats (
  scope TEXT NOT NULL,
  category TEXT NOT NULL,
  object_count INTEGER NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (scope, category)
);
CREATE TABLE IF NOT EXISTS cloud_reseed_tasks (
  scope TEXT NOT NULL,
  operation_id TEXT NOT NULL,
  generation INTEGER NOT NULL,
  status TEXT NOT NULL,
  operation_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (scope, operation_id)
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
    final pending = await _meta(
      db,
      'data.model_configs.pendingManagedModelIdMigrations',
    );
    return {
      'models': rows.map((row) => jsonDecode(row.configJson)).toList(),
      if (pending != null)
        'pendingManagedModelIdMigrations': jsonDecode(pending),
    };
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
                if (row.modelContextContent != null)
                  'modelContextContent': row.modelContextContent,
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

  Future<Map<String, dynamic>> _loadTasks(StorageV2DriftDatabase db) async {
    final tasks =
        (await (db.select(
              db.taskRows,
            )..orderBy([(table) => OrderingTerm.desc(table.updatedAt)])).get())
            .map(
              (row) => {
                'id': row.id,
                'title': row.title,
                if (row.note != null) 'note': row.note,
                if (row.plannedDate != null) 'plannedDate': row.plannedDate,
                if (row.plannedTime != null) 'plannedTime': row.plannedTime,
                if (row.dueDate != null) 'dueDate': row.dueDate,
                if (row.dueTime != null) 'dueTime': row.dueTime,
                if (row.completedAt != null) 'completedAt': row.completedAt,
                'reminders': jsonDecode(row.remindersJson),
                'createdAt': row.createdAt,
                'updatedAt': row.updatedAt,
              },
            )
            .toList();
    final lists =
        (await (db.select(
              db.taskListRows,
            )..orderBy([(table) => OrderingTerm.asc(table.sortOrder)])).get())
            .map(
              (row) => {
                'id': row.id,
                'title': row.title,
                'sortOrder': row.sortOrder,
                'createdAt': row.createdAt,
                'updatedAt': row.updatedAt,
              },
            )
            .toList();
    final entries =
        (await (db.select(db.taskListEntryRows)..orderBy([
                  (table) => OrderingTerm.asc(table.listId),
                  (table) => OrderingTerm.asc(table.sortOrder),
                ]))
                .get())
            .map(
              (row) => {
                'id': row.taskId,
                'taskId': row.taskId,
                'listId': row.listId,
                'sortOrder': row.sortOrder,
                'updatedAt': row.updatedAt,
              },
            )
            .toList();
    return {'tasks': tasks, 'lists': lists, 'entries': entries};
  }

  Future<Map<String, dynamic>> _loadKnowledge(StorageV2DriftDatabase db) async {
    final settings = await (db.select(
      db.knowledgeSettingsRows,
    )..where((row) => row.id.equals(1))).getSingleOrNull();
    final bases =
        (await (db.select(
              db.knowledgeBaseRows,
            )..orderBy([(row) => OrderingTerm.asc(row.sortOrder)])).get())
            .map(
              (row) => {
                'id': row.id,
                'name': row.name,
                if (row.description != null) 'description': row.description,
                'enabled': row.enabled,
                'sortOrder': row.sortOrder,
                'createdAt': row.createdAt,
                'updatedAt': row.updatedAt,
              },
            )
            .toList();
    final categories =
        (await (db.select(db.knowledgeCategoryRows)..orderBy([
                  (row) => OrderingTerm.asc(row.knowledgeBaseId),
                  (row) => OrderingTerm.asc(row.sortOrder),
                ]))
                .get())
            .map(
              (row) => {
                'id': row.id,
                'knowledgeBaseId': row.knowledgeBaseId,
                'name': row.name,
                'alias': row.alias,
                if (row.description != null) 'description': row.description,
                'annotationRule': row.annotationRule,
                'explanationPrompt': row.explanationPrompt,
                'colorValue': row.colorValue,
                'autoAnnotate': row.autoAnnotate,
                if (row.modelConfigId != null)
                  'modelConfigId': row.modelConfigId,
                'isDefault': row.isDefault,
                'enabled': row.enabled,
                'sortOrder': row.sortOrder,
                'createdAt': row.createdAt,
                'updatedAt': row.updatedAt,
              },
            )
            .toList();
    final entries =
        (await (db.select(db.knowledgeEntryRows)..orderBy([
                  (row) => OrderingTerm.asc(row.knowledgeBaseId),
                  (row) => OrderingTerm.asc(row.sortOrder),
                ]))
                .get())
            .map(
              (row) => {
                'id': row.id,
                'knowledgeBaseId': row.knowledgeBaseId,
                if (row.categoryId != null) 'categoryId': row.categoryId,
                'title': row.title,
                'content': row.content,
                'enabled': row.enabled,
                'sortOrder': row.sortOrder,
                'createdAt': row.createdAt,
                'updatedAt': row.updatedAt,
              },
            )
            .toList();
    final sources =
        (await (db.select(db.knowledgeSourceRows)..orderBy([
                  (row) => OrderingTerm.asc(row.entryId),
                  (row) => OrderingTerm.asc(row.sortOrder),
                ]))
                .get())
            .map(
              (row) => {
                'id': row.id,
                'knowledgeBaseId': row.knowledgeBaseId,
                'entryId': row.entryId,
                'title': row.title,
                if (row.url != null) 'url': row.url,
                if (row.note != null) 'note': row.note,
                'sortOrder': row.sortOrder,
                'createdAt': row.createdAt,
                'updatedAt': row.updatedAt,
              },
            )
            .toList();
    final explanations =
        (await (db.select(db.knowledgeExplanationRows)..orderBy([
                  (row) => OrderingTerm.asc(row.entryId),
                  (row) => OrderingTerm.asc(row.sortOrder),
                ]))
                .get())
            .map(
              (row) => {
                'id': row.id,
                'knowledgeBaseId': row.knowledgeBaseId,
                'entryId': row.entryId,
                'title': row.title,
                'content': row.content,
                'sortOrder': row.sortOrder,
                'createdAt': row.createdAt,
                'updatedAt': row.updatedAt,
              },
            )
            .toList();
    return {
      if (settings != null)
        'settings': {
          if (settings.defaultKnowledgeBaseId != null)
            'defaultKnowledgeBaseId': settings.defaultKnowledgeBaseId,
          if (settings.defaultCategoryId != null)
            'defaultCategoryId': settings.defaultCategoryId,
          'updatedAt': settings.updatedAt,
        },
      'knowledgeBases': bases,
      'categories': categories,
      'entries': entries,
      'sources': sources,
      'explanations': explanations,
    };
  }

  Future<Map<String, dynamic>> _loadCalendar(StorageV2DriftDatabase db) async {
    final events =
        (await (db.select(db.calendarEventRows)..orderBy([
                  (table) => OrderingTerm.asc(table.startAt),
                  (table) => OrderingTerm.asc(table.startDate),
                ]))
                .get())
            .map(
              (row) => {
                'id': row.id,
                'title': row.title,
                if (row.note != null) 'note': row.note,
                'timeKind': row.timeKind,
                if (row.startAt != null) 'startAt': row.startAt,
                if (row.endAt != null) 'endAt': row.endAt,
                if (row.startDate != null) 'startDate': row.startDate,
                if (row.endDateExclusive != null)
                  'endDateExclusive': row.endDateExclusive,
                'reminders': jsonDecode(row.remindersJson),
                'createdAt': row.createdAt,
                'updatedAt': row.updatedAt,
              },
            )
            .toList();
    final anniversaries =
        (await (db.select(db.anniversaryRows)..orderBy([
                  (table) => OrderingTerm.asc(table.month),
                  (table) => OrderingTerm.asc(table.day),
                ]))
                .get())
            .map(
              (row) => {
                'id': row.id,
                'title': row.title,
                if (row.note != null) 'note': row.note,
                'month': row.month,
                'day': row.day,
                if (row.year != null) 'year': row.year,
                'recurrence': row.recurrence,
                'showYearCount': row.showYearCount != 0,
                'reminders': jsonDecode(row.remindersJson),
                'createdAt': row.createdAt,
                'updatedAt': row.updatedAt,
              },
            )
            .toList();
    return {'events': events, 'anniversaries': anniversaries};
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
    final pending = data['pendingManagedModelIdMigrations'];
    if (pending is Map && pending.isNotEmpty) {
      await _setMeta(
        db,
        'data.model_configs.pendingManagedModelIdMigrations',
        jsonEncode(pending),
      );
    } else {
      await _deleteMeta(
        db,
        'data.model_configs.pendingManagedModelIdMigrations',
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
              modelContextContent: Value(
                json['modelContextContent'] as String?,
              ),
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

  Future<void> _replaceTasks(
    StorageV2DriftDatabase db,
    Map<String, dynamic> data,
  ) async {
    await db.delete(db.taskListEntryRows).go();
    await db.delete(db.taskListRows).go();
    await db.delete(db.taskRows).go();
    final taskIds = <String>{};
    for (final item in data['tasks'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      if (id == null || id.isEmpty) continue;
      await upsertTaskRow(json, transactionDb: db);
      taskIds.add(id);
    }
    final listIds = <String>{};
    for (final item in data['lists'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      if (id == null || id.isEmpty) continue;
      await upsertTaskListRow(json, transactionDb: db);
      listIds.add(id);
    }
    for (final item in data['entries'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final taskId = json['taskId'] as String? ?? json['id'] as String?;
      final listId = json['listId'] as String?;
      if (taskId == null ||
          taskId.isEmpty ||
          listId == null ||
          !listIds.contains(listId) ||
          !taskIds.contains(taskId)) {
        continue;
      }
      await upsertTaskListEntryRow(json, transactionDb: db);
    }
  }

  Future<void> _replaceKnowledge(
    StorageV2DriftDatabase db,
    Map<String, dynamic> data,
  ) async {
    await db.delete(db.knowledgeSettingsRows).go();
    await db.delete(db.knowledgeSourceRows).go();
    await db.delete(db.knowledgeExplanationRows).go();
    await db.delete(db.knowledgeEntryRows).go();
    await db.delete(db.knowledgeCategoryRows).go();
    await db.delete(db.knowledgeBaseRows).go();
    final baseIds = <String>{};
    for (final item in data['knowledgeBases'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      if (id == null || id.isEmpty) continue;
      await upsertKnowledgeBaseRow(json, transactionDb: db);
      baseIds.add(id);
    }
    final categoryIds = <String>{};
    for (final item in data['categories'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      if (id == null || !baseIds.contains(json['knowledgeBaseId'])) continue;
      await upsertKnowledgeCategoryRow(json, transactionDb: db);
      categoryIds.add(id);
    }
    final entryBaseIds = <String, String>{};
    for (final item in data['entries'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['id'] as String?;
      if (id == null || !baseIds.contains(json['knowledgeBaseId'])) continue;
      if (json['categoryId'] != null &&
          !categoryIds.contains(json['categoryId'])) {
        json.remove('categoryId');
      }
      await upsertKnowledgeEntryRow(json, transactionDb: db);
      entryBaseIds[id] = json['knowledgeBaseId'] as String;
    }
    for (final item in data['sources'] as List<dynamic>? ?? const []) {
      if (item is Map &&
          entryBaseIds[item['entryId']] == item['knowledgeBaseId']) {
        await upsertKnowledgeSourceRow(
          Map<String, dynamic>.from(item),
          transactionDb: db,
        );
      }
    }
    for (final item in data['explanations'] as List<dynamic>? ?? const []) {
      if (item is Map &&
          entryBaseIds[item['entryId']] == item['knowledgeBaseId']) {
        await upsertKnowledgeExplanationRow(
          Map<String, dynamic>.from(item),
          transactionDb: db,
        );
      }
    }
    final rawSettings = data['settings'];
    if (rawSettings is Map) {
      await _upsertKnowledgeSettings(
        db,
        Map<String, dynamic>.from(rawSettings),
      );
    } else {
      await _deriveKnowledgeSettings(db);
    }
  }

  Future<void> _deriveKnowledgeSettings(StorageV2DriftDatabase db) async {
    final row = await db.customSelect('''
SELECT category.id AS category_id, category.knowledge_base_id AS base_id
FROM knowledge_categories AS category
JOIN knowledge_bases AS base ON base.id = category.knowledge_base_id
WHERE base.enabled = 1
  AND category.enabled = 1
  AND category.auto_annotate = 1
ORDER BY category.is_default DESC, base.sort_order, category.sort_order,
         category.created_at, category.id
LIMIT 1
''').getSingleOrNull();
    await _upsertKnowledgeSettings(db, {
      if (row != null) 'defaultKnowledgeBaseId': row.data['base_id'],
      if (row != null) 'defaultCategoryId': row.data['category_id'],
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _replaceCalendar(
    StorageV2DriftDatabase db,
    Map<String, dynamic> data,
  ) async {
    await db.delete(db.calendarEventRows).go();
    await db.delete(db.anniversaryRows).go();
    for (final item in data['events'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      await upsertCalendarEventRow(
        Map<String, dynamic>.from(item),
        transactionDb: db,
      );
    }
    for (final item in data['anniversaries'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      await upsertAnniversaryRow(
        Map<String, dynamic>.from(item),
        transactionDb: db,
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
    'tasks',
    'task_lists',
    'task_list_entries',
    'knowledge_bases',
    'knowledge_categories',
    'knowledge_entries',
    'knowledge_sources',
    'knowledge_explanations',
    'knowledge_settings',
    'calendar_events',
    'anniversaries',
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

  // v15 intentionally has no mixed-version planning sync compatibility.
  static const _legacyPlanningSyncTableNames = <String>{
    'schedules',
    'todo_lists',
    'todo_items',
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
    'tasks.json' => {'tasks', 'task_lists', 'task_list_entries'},
    'knowledge.json' => {
      'knowledge_bases',
      'knowledge_categories',
      'knowledge_entries',
      'knowledge_sources',
      'knowledge_explanations',
      'knowledge_settings',
    },
    'calendar.json' => {'calendar_events', 'anniversaries'},
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
    if (tables.any({'tasks', 'task_lists', 'task_list_entries'}.contains)) {
      final data = await _loadTasks(db);
      add('tasks', data['tasks'] as List);
      add('task_lists', data['lists'] as List);
      add('task_list_entries', data['entries'] as List);
    }
    if (tables.any(
      {
        'knowledge_bases',
        'knowledge_categories',
        'knowledge_entries',
        'knowledge_sources',
        'knowledge_explanations',
        'knowledge_settings',
      }.contains,
    )) {
      final data = await _loadKnowledge(db);
      add('knowledge_bases', data['knowledgeBases'] as List);
      add('knowledge_categories', data['categories'] as List);
      add('knowledge_entries', data['entries'] as List);
      add('knowledge_sources', data['sources'] as List);
      add('knowledge_explanations', data['explanations'] as List);
      final settings = data['settings'];
      if (settings is Map) {
        add('knowledge_settings', [
          {'id': 'global', ...Map<String, dynamic>.from(settings)},
        ]);
      }
    }
    if (tables.any({'calendar_events', 'anniversaries'}.contains)) {
      final data = await _loadCalendar(db);
      add('calendar_events', data['events'] as List);
      add('anniversaries', data['anniversaries'] as List);
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
            selectionData: oldRows[id],
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
    Map<String, dynamic>? selectionData,
    String? deviceId,
    String? changeId,
    DateTime? clientCreatedAt,
    int? mutationVersion,
    String source = 'local',
    String? sourceScope,
    String? lineage,
    String? routeScope,
  }) async {
    final dataJson = data == null ? null : jsonEncode(data);
    final selectionJson = selectionData == null
        ? null
        : jsonEncode(selectionData);
    final existingHead =
        await (db.select(db.transportChangeHeadRows)..where(
              (row) => row.table.equals(table) & row.recordId.equals(recordId),
            ))
            .getSingleOrNull();
    final sameLogicalMutation =
        changeId == null &&
        existingHead != null &&
        existingHead.op == op &&
        existingHead.dataJson == dataJson &&
        existingHead.selectionDataJson == selectionJson;
    final effectiveChangeId =
        changeId ?? (sameLogicalMutation ? existingHead.changeId : _uuid.v4());
    final createdAt =
        clientCreatedAt ??
        (sameLogicalMutation
            ? DateTime.parse(existingHead.clientCreatedAt)
            : DateTime.now().toUtc());
    final effectiveMutationVersion =
        mutationVersion ??
        (sameLogicalMutation
            ? existingHead.mutationVersion
            : (existingHead?.mutationVersion ?? 0) + 1);
    final effectiveLineage = lineage ?? await _meta(db, 'physical_dataset_id');
    await db
        .into(db.transportChangeHeadRows)
        .insertOnConflictUpdate(
          TransportChangeHeadRowsCompanion.insert(
            table: table,
            recordId: recordId,
            op: op,
            dataJson: Value(dataJson),
            selectionDataJson: Value(selectionJson),
            changeId: effectiveChangeId,
            deviceId: deviceId ?? existingHead?.deviceId ?? '',
            clientCreatedAt: createdAt.toUtc().toIso8601String(),
            mutationVersion: effectiveMutationVersion,
            source: source,
            sourceScope: Value(sourceScope),
            lineage: Value(effectiveLineage),
            routeScope: Value(routeScope),
            updatedAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
    if (scope.startsWith('lan:')) return;
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
    await db
        .into(db.syncOutboxRows)
        .insertOnConflictUpdate(
          SyncOutboxRowsCompanion.insert(
            scope: scope,
            table: table,
            recordId: recordId,
            op: op,
            dataJson: Value(dataJson),
            selectionDataJson: Value(selectionJson),
            changeId: effectiveChangeId,
            deviceId: effectiveDeviceId,
            clientCreatedAt: createdAt.toIso8601String(),
            mutationVersion:
                mutationVersion ?? (current?.mutationVersion ?? 0) + 1,
            updatedAt: createdAt.toIso8601String(),
          ),
        );
  }

  Future<void> _ensureTransportHeads(
    StorageV2DriftDatabase db,
    String deviceId,
  ) async {
    final existing = await db.select(db.transportChangeHeadRows).get();
    final existingRows = {
      for (final row in existing) (row.table, row.recordId),
    };
    final snapshot = await _syncSnapshot(db, _syncTableNames);
    for (final table in snapshot.entries) {
      for (final row in table.value.entries) {
        if (existingRows.contains((table.key, row.key))) continue;
        await _putOutbox(
          db,
          'lan:v1',
          table.key,
          row.key,
          'upsert',
          row.value,
          deviceId: deviceId,
        );
      }
    }
  }

  Future<Map<String, dynamic>?> selectionDataForChange(
    String table,
    String recordId,
    Map<String, dynamic>? data,
  ) async {
    if (data != null) return data;
    final db = await _open();
    return _selectionDataForRow(db, table, recordId);
  }

  Future<Map<String, dynamic>?> _selectionDataForRow(
    StorageV2DriftDatabase db,
    String table,
    String recordId,
  ) async {
    if (table != 'recycle_bin') return null;
    final row = await (db.select(
      db.recycleBinRows,
    )..where((item) => item.id.equals(recordId))).getSingleOrNull();
    if (row == null) return null;
    return {'owner': row.owner, 'category': row.category, 'type': row.type};
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
    if (table == 'tasks' ||
        table == 'task_lists' ||
        table == 'task_list_entries' ||
        table == 'knowledge_bases' ||
        table == 'knowledge_categories' ||
        table == 'knowledge_entries' ||
        table == 'knowledge_sources' ||
        table == 'knowledge_explanations' ||
        table == 'knowledge_settings' ||
        table == 'calendar_events' ||
        table == 'anniversaries') {
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
      case 'tasks':
        if (op == 'upsert') {
          await upsertTaskRow(data, transactionDb: db);
        } else {
          await deleteTaskRow(data['id'] as String, transactionDb: db);
        }
      case 'task_lists':
        if (op == 'upsert') {
          await upsertTaskListRow(data, transactionDb: db);
        } else {
          await deleteTaskListRow(data['id'] as String, transactionDb: db);
        }
      case 'task_list_entries':
        if (op == 'upsert') {
          await upsertTaskListEntryRow(data, transactionDb: db);
        } else {
          await deleteTaskListEntryRow(data['id'] as String, transactionDb: db);
        }
      case 'knowledge_bases':
        if (op == 'upsert') {
          await upsertKnowledgeBaseRow(data, transactionDb: db);
        } else {
          await deleteKnowledgeBaseRow(data['id'] as String, transactionDb: db);
        }
      case 'knowledge_categories':
        if (op == 'upsert') {
          await upsertKnowledgeCategoryRow(data, transactionDb: db);
        } else {
          await deleteKnowledgeCategoryRow(
            data['id'] as String,
            transactionDb: db,
          );
        }
      case 'knowledge_entries':
        if (op == 'upsert') {
          await upsertKnowledgeEntryRow(data, transactionDb: db);
        } else {
          await deleteKnowledgeEntryRow(
            data['id'] as String,
            transactionDb: db,
          );
        }
      case 'knowledge_sources':
        if (op == 'upsert') {
          await upsertKnowledgeSourceRow(data, transactionDb: db);
        } else {
          await deleteKnowledgeSourceRow(
            data['id'] as String,
            transactionDb: db,
          );
        }
      case 'knowledge_explanations':
        if (op == 'upsert') {
          await upsertKnowledgeExplanationRow(data, transactionDb: db);
        } else {
          await deleteKnowledgeExplanationRow(
            data['id'] as String,
            transactionDb: db,
          );
        }
      case 'knowledge_settings':
        if (data['id'] != 'global') {
          throw StateError('knowledge_settings record id must be global');
        }
        if (op == 'upsert') {
          await _upsertKnowledgeSettings(db, data);
        } else {
          await deleteKnowledgeSettings(transactionDb: db);
        }
      case 'calendar_events':
        if (op == 'upsert') {
          await upsertCalendarEventRow(data, transactionDb: db);
        } else {
          await deleteCalendarEventRow(data['id'] as String, transactionDb: db);
        }
      case 'anniversaries':
        if (op == 'upsert') {
          await upsertAnniversaryRow(data, transactionDb: db);
        } else {
          await deleteAnniversaryRow(data['id'] as String, transactionDb: db);
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
  final Map<String, dynamic>? selectionData;
  final String changeId;
  final String deviceId;
  final DateTime clientCreatedAt;
  final int mutationVersion;
  final String? lineage;

  const SyncOutboxEntry({
    required this.table,
    required this.recordId,
    required this.op,
    required this.data,
    this.selectionData,
    required this.changeId,
    required this.deviceId,
    required this.clientCreatedAt,
    required this.mutationVersion,
    this.lineage,
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
