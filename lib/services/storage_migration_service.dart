import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/conversation_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/file_name_utils.dart';
import 'storage_v2_database.dart';

/// One-shot migration from the legacy SharedPreferences JSON store into a
/// durable v2 layout: structured table snapshots plus note/resource files.
///
/// The app still reads legacy providers after this migration. The generated
/// `storage_v2` tree is the stable import source for the later repository/Drift
/// cutover, and gives users a safe, inspectable migration step today.
class StorageMigrationService {
  StorageMigrationService({
    required this.settingsProvider,
    required this.modelConfigProvider,
    required this.conversationProvider,
    required this.featureProvider,
    Directory? rootDirectory,
    SharedPreferences? preferences,
    Future<void> Function()? afterActivateStorageForTest,
  }) : _rootDirectory = rootDirectory,
       _preferences = preferences,
       _afterActivateStorageForTest = afterActivateStorageForTest;

  /// Version of the app-level storage_v2 directory layout.
  ///
  /// This is separate from the internal Drift database schema version in
  /// [StorageV2DriftDatabase].
  static const currentSchemaVersion = 2;
  static const _schemaVersionKey = 'storage_schema_version';
  static const _statusKey = 'storage_migration_status';
  static const _completedAtKey = 'storage_migration_completed_at';
  static const _reportKey = 'storage_migration_report';
  static const _legacyStatusNone = '未迁移';

  final SettingsProvider settingsProvider;
  final ModelConfigProvider modelConfigProvider;
  final ConversationProvider conversationProvider;
  final FeatureProvider featureProvider;
  final Directory? _rootDirectory;
  final SharedPreferences? _preferences;
  final Future<void> Function()? _afterActivateStorageForTest;

  Future<StorageMigrationState> loadState() async {
    final prefs = await _prefs();
    final schemaVersion = prefs.getInt(_schemaVersionKey) ?? 1;
    final status = prefs.getString(_statusKey) ?? 'notStarted';
    final reportJson = prefs.getString(_reportKey);
    StorageMigrationReport? report;
    if (reportJson != null) {
      try {
        report = StorageMigrationReport.fromJson(
          jsonDecode(reportJson) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    return StorageMigrationState(
      schemaVersion: schemaVersion,
      status: status,
      completedAt: prefs.getString(_completedAtKey),
      report: report,
    );
  }

  Future<StorageMigrationReport> migrate({bool force = false}) async {
    final prefs = await _prefs();
    final current = prefs.getInt(_schemaVersionKey) ?? 1;
    if (!force && current >= currentSchemaVersion) {
      final reportJson = prefs.getString(_reportKey);
      if (reportJson != null) {
        return StorageMigrationReport.fromJson(
          jsonDecode(reportJson) as Map<String, dynamic>,
        );
      }
      throw StateError('数据已经迁移到新版存储');
    }

    final startedAt = DateTime.now();
    await prefs.setString(_statusKey, 'running');
    final root = await _root();
    final staging = Directory('${root.path}/storage_v2_staging');
    final target = Directory('${root.path}/storage_v2');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);

    final warnings = <String>[];
    try {
      final dataDir = Directory('${staging.path}/data');
      final notesDir = Directory('${staging.path}/notes');
      final assetsDir = Directory('${staging.path}/assets');
      await dataDir.create(recursive: true);
      await notesDir.create(recursive: true);
      await assetsDir.create(recursive: true);

      final resources = _ResourceCollector(assetsDir, warnings);
      final messageAttachments = <Map<String, dynamic>>[];
      final conversations = <Map<String, dynamic>>[];
      final messages = <Map<String, dynamic>>[];

      for (final conversation in conversationProvider.conversations) {
        conversations.add({
          'id': conversation.id,
          'title': conversation.title,
          'modelId': conversation.modelId,
          'settings': conversation.settings.toJson(),
          'roleId': conversation.roleId,
          'createdAt': conversation.createdAt.toIso8601String(),
          'updatedAt': conversation.updatedAt.toIso8601String(),
        });
        for (var i = 0; i < conversation.messages.length; i++) {
          final message = conversation.messages[i];
          messages.add({
            'id': message.id,
            'conversationId': conversation.id,
            'role': message.role,
            'content': message.content,
            if (message.thinkingContent != null &&
                message.thinkingContent!.isNotEmpty)
              'thinkingContent': message.thinkingContent,
            'timestamp': message.timestamp.toIso8601String(),
            'sortOrder': i,
          });
          for (var j = 0; j < message.images.length; j++) {
            final attachment = message.images[j];
            final resource = await resources.importLegacyFile(
              attachment.path,
              originalName: attachment.name,
              mimeType: attachment.mimeType,
              role: attachment.isImage ? 'message_image' : 'message_attachment',
            );
            messageAttachments.add({
              'id': '${message.id}_attachment_$j',
              'messageId': message.id,
              'resourceId': resource.id,
              'displayName': attachment.name,
              'mimeType': attachment.mimeType,
              'size': attachment.size,
              'sortOrder': j,
            });
          }
        }
      }

      final settings = settingsProvider.settings;
      String? backgroundResourceId;
      if (settings.backgroundImagePath != null &&
          settings.backgroundImagePath!.isNotEmpty) {
        final bg = await resources.importLegacyFile(
          settings.backgroundImagePath!,
          originalName: File(
            settings.backgroundImagePath!,
          ).uri.pathSegments.last,
          mimeType: _mimeTypeFromName(settings.backgroundImagePath!),
          role: 'background',
        );
        backgroundResourceId = bg.id;
      }

      final noteRows = <Map<String, dynamic>>[];
      final notePageRows = <Map<String, dynamic>>[];
      for (final note in featureProvider.notes) {
        final pageId = '${note.id}_page_0';
        final fileName = _uniqueFileName(
          safeExportFileName(note.title, fallback: 'note'),
          'md',
          const <String>{},
        );
        final noteDirectoryName = safeStorageSegment(note.id, fallback: 'note');
        final noteDir = Directory('${notesDir.path}/$noteDirectoryName');
        await noteDir.create(recursive: true);
        await File(
          '${noteDir.path}/$fileName',
        ).writeAsString(note.content, flush: true);
        noteRows.add({
          'id': note.id,
          'title': note.title,
          if (note.folderId != null) 'folderId': note.folderId,
          if (note.currentRevisionId != null)
            'currentRevisionId': note.currentRevisionId,
          'currentPageId': pageId,
          'createdAt': note.createdAt.toIso8601String(),
          'updatedAt': note.updatedAt.toIso8601String(),
          'wrap': note.wrap,
        });
        notePageRows.add({
          'id': pageId,
          'noteId': note.id,
          'title': note.title.isEmpty ? '未命名分页' : note.title,
          'fileName': fileName,
          'relativePath': 'notes/$noteDirectoryName/$fileName',
          if (note.currentRevisionId != null)
            'currentRevisionId': note.currentRevisionId,
          'sortOrder': 0,
          'createdAt': note.createdAt.toIso8601String(),
          'updatedAt': note.updatedAt.toIso8601String(),
        });
      }

      final pageIdByNoteId = {
        for (final note in featureProvider.notes) note.id: '${note.id}_page_0',
      };
      final revisionRows = featureProvider.noteRevisions.map((revision) {
        return {
          'id': revision.id,
          'noteId': revision.noteId,
          'pageId': pageIdByNoteId[revision.noteId],
          if (revision.parentRevisionId != null)
            'parentRevisionId': revision.parentRevisionId,
          'savedAt': revision.savedAt.toIso8601String(),
          'deltaStart': revision.delta.start,
          'deletedText': revision.delta.deletedText,
          'insertedText': revision.delta.insertedText,
        };
      }).toList();

      final proposalRows = <Map<String, dynamic>>[];
      final proposalBlockRows = <Map<String, dynamic>>[];
      for (final note in featureProvider.notes) {
        final proposal = featureProvider.getNoteEditProposal(note.id);
        if (proposal == null) continue;
        proposalRows.add({
          'id': proposal.id,
          'noteId': proposal.noteId,
          'pageId': pageIdByNoteId[proposal.noteId],
          if (proposal.baseRevisionId != null)
            'baseRevisionId': proposal.baseRevisionId,
          'baseContentHash': proposal.baseContentHash,
          'createdAt': proposal.createdAt.toIso8601String(),
        });
        for (var i = 0; i < proposal.blocks.length; i++) {
          final block = proposal.blocks[i];
          proposalBlockRows.add({
            'id': block.id,
            'proposalId': proposal.id,
            'startLine': block.startLine,
            'deleteCount': block.deleteCount,
            'deletedLines': block.deletedLines,
            'insertLines': block.insertLines,
            'sortOrder': i,
          });
        }
      }

      final todoListRows = <Map<String, dynamic>>[];
      final todoItemRows = <Map<String, dynamic>>[];
      for (final list in featureProvider.todoLists) {
        todoListRows.add({
          'id': list.id,
          'title': list.title,
          'createdAt': list.createdAt.toIso8601String(),
          'updatedAt': list.updatedAt.toIso8601String(),
        });
        for (var i = 0; i < list.items.length; i++) {
          final item = list.items[i];
          todoItemRows.add({
            'id': item.id,
            'listId': list.id,
            'text': item.text,
            'done': item.done,
            'sortOrder': i,
          });
        }
      }

      final settingsJson = settings.toJson()
        ..['storageV2'] = {'backgroundResourceId': ?backgroundResourceId};
      await _writeJson(dataDir, 'app_settings.json', settingsJson);
      await _writeJson(dataDir, 'model_configs.json', {
        'models': modelConfigProvider.models.map((e) => e.toJson()).toList(),
      });
      await _writeJson(dataDir, 'conversations.json', {
        'conversations': conversations,
        'messages': messages,
        'messageAttachments': messageAttachments,
      });
      await _writeJson(dataDir, 'notes.json', {
        'folders': featureProvider.noteFolders.map((e) => e.toJson()).toList(),
        'notes': noteRows,
        'pages': notePageRows,
        'revisions': revisionRows,
        'editProposals': proposalRows,
        'editBlocks': proposalBlockRows,
      });
      await _writeJson(dataDir, 'schedules.json', {
        'schedules': featureProvider.schedules.map((e) => e.toJson()).toList(),
      });
      await _writeJson(dataDir, 'todo_lists.json', {
        'todoLists': todoListRows,
        'todoItems': todoItemRows,
      });
      await _writeJson(dataDir, 'resources.json', {
        'resources': resources.records.map((e) => e.toJson()).toList(),
      });

      final completedAt = DateTime.now();
      final report = StorageMigrationReport(
        rootPath: target.path,
        startedAt: startedAt,
        completedAt: completedAt,
        conversations: conversations.length,
        messages: messages.length,
        messageAttachments: messageAttachments.length,
        resources: resources.records.length,
        duplicatedResources: resources.duplicateCount,
        missingResources: resources.missingCount,
        noteFolders: featureProvider.noteFolders.length,
        notes: noteRows.length,
        notePages: notePageRows.length,
        noteRevisions: revisionRows.length,
        noteEditProposals: proposalRows.length,
        schedules: featureProvider.schedules.length,
        todoLists: todoListRows.length,
        todoItems: todoItemRows.length,
        warnings: warnings,
      );
      await _writeJson(Directory(staging.path), 'manifest.json', {
        'type': 'lynai.storage_v2',
        'schemaVersion': currentSchemaVersion,
        'createdAt': completedAt.toUtc().toIso8601String(),
        'layout': {
          'database': 'app.db',
          'legacyData': 'data/*.json',
          'notes': 'notes/{noteId}/{pageFile}.md',
          'assets': 'assets/{kind}/{sha256Prefix}/{sha256}_{name}',
        },
        'report': report.toJson(),
      });

      final stagingDatabase = StorageV2Database(staging);
      try {
        await stagingDatabase.importDataFiles(overwrite: true);
      } finally {
        await stagingDatabase.close();
      }

      final backup = Directory(
        '${root.path}/storage_v2_backup_${DateTime.now().microsecondsSinceEpoch}',
      );
      var targetMovedToBackup = false;
      var stagingMovedToTarget = false;
      try {
        if (await target.exists()) {
          await target.rename(backup.path);
          targetMovedToBackup = true;
        }
        await staging.rename(target.path);
        stagingMovedToTarget = true;
        await _afterActivateStorageForTest?.call();

        await prefs.setInt(_schemaVersionKey, currentSchemaVersion);
        await prefs.setString(_statusKey, 'completed');
        await prefs.setString(_completedAtKey, completedAt.toIso8601String());
        await prefs.setString(_reportKey, jsonEncode(report.toJson()));
        await _removeLegacyLargeData(prefs);
        if (await backup.exists()) await backup.delete(recursive: true);
        return report;
      } catch (_) {
        if (stagingMovedToTarget && await target.exists()) {
          await target.delete(recursive: true);
        }
        if (targetMovedToBackup && await backup.exists()) {
          await backup.rename(target.path);
        }
        rethrow;
      }
    } catch (e) {
      await prefs.setString(_statusKey, 'failed');
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> _removeLegacyLargeData(SharedPreferences prefs) async {
    const legacyKeys = [
      'conversations',
      'model_configs',
      'schedule_items',
      'notes',
      'note_revisions',
      'note_folders',
      'note_edit_proposals',
      'todo_lists',
    ];
    for (final key in legacyKeys) {
      await prefs.remove(key);
    }
  }

  Future<Directory> _root() async {
    final root = _rootDirectory ?? await getApplicationDocumentsDirectory();
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  Future<SharedPreferences> _prefs() async {
    final preferences = _preferences;
    if (preferences != null) return preferences;
    return SharedPreferences.getInstance();
  }

  static Future<void> _writeJson(
    Directory directory,
    String name,
    Object value,
  ) async {
    if (!await directory.exists()) await directory.create(recursive: true);
    await File('${directory.path}/$name').writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
  }
}

class StorageMigrationState {
  final int schemaVersion;
  final String status;
  final String? completedAt;
  final StorageMigrationReport? report;

  const StorageMigrationState({
    required this.schemaVersion,
    required this.status,
    this.completedAt,
    this.report,
  });

  bool get completed =>
      schemaVersion >= StorageMigrationService.currentSchemaVersion &&
      status == 'completed';

  String get label {
    if (completed) return '新版存储已就绪';
    if (status == 'running') return '迁移中';
    if (status == 'failed') return '上次迁移失败';
    return StorageMigrationService._legacyStatusNone;
  }
}

class StorageMigrationReport {
  final String rootPath;
  final DateTime startedAt;
  final DateTime completedAt;
  final int conversations;
  final int messages;
  final int messageAttachments;
  final int resources;
  final int duplicatedResources;
  final int missingResources;
  final int noteFolders;
  final int notes;
  final int notePages;
  final int noteRevisions;
  final int noteEditProposals;
  final int schedules;
  final int todoLists;
  final int todoItems;
  final List<String> warnings;

  const StorageMigrationReport({
    required this.rootPath,
    required this.startedAt,
    required this.completedAt,
    required this.conversations,
    required this.messages,
    required this.messageAttachments,
    required this.resources,
    required this.duplicatedResources,
    required this.missingResources,
    required this.noteFolders,
    required this.notes,
    required this.notePages,
    required this.noteRevisions,
    required this.noteEditProposals,
    required this.schedules,
    required this.todoLists,
    required this.todoItems,
    this.warnings = const [],
  });

  factory StorageMigrationReport.fromJson(Map<String, dynamic> json) {
    return StorageMigrationReport(
      rootPath: json['rootPath'] as String? ?? '',
      startedAt: DateTime.parse(json['startedAt'] as String),
      completedAt: DateTime.parse(json['completedAt'] as String),
      conversations: json['conversations'] as int? ?? 0,
      messages: json['messages'] as int? ?? 0,
      messageAttachments: json['messageAttachments'] as int? ?? 0,
      resources: json['resources'] as int? ?? 0,
      duplicatedResources: json['duplicatedResources'] as int? ?? 0,
      missingResources: json['missingResources'] as int? ?? 0,
      noteFolders: json['noteFolders'] as int? ?? 0,
      notes: json['notes'] as int? ?? 0,
      notePages: json['notePages'] as int? ?? 0,
      noteRevisions: json['noteRevisions'] as int? ?? 0,
      noteEditProposals: json['noteEditProposals'] as int? ?? 0,
      schedules: json['schedules'] as int? ?? 0,
      todoLists: json['todoLists'] as int? ?? 0,
      todoItems: json['todoItems'] as int? ?? 0,
      warnings: (json['warnings'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'rootPath': rootPath,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'conversations': conversations,
    'messages': messages,
    'messageAttachments': messageAttachments,
    'resources': resources,
    'duplicatedResources': duplicatedResources,
    'missingResources': missingResources,
    'noteFolders': noteFolders,
    'notes': notes,
    'notePages': notePages,
    'noteRevisions': noteRevisions,
    'noteEditProposals': noteEditProposals,
    'schedules': schedules,
    'todoLists': todoLists,
    'todoItems': todoItems,
    'warnings': warnings,
  };

  String get summary {
    return '对话 $conversations，消息 $messages，笔记 $notes，分页 $notePages，资源 $resources，缺失资源 $missingResources';
  }
}

class _ResourceCollector {
  _ResourceCollector(this.assetsDir, this.warnings);

  final Directory assetsDir;
  final List<String> warnings;
  final Map<String, _ResourceRecord> _byHashAndSize = {};
  final List<_ResourceRecord> records = [];
  int duplicateCount = 0;
  int missingCount = 0;

  Future<_ResourceRecord> importLegacyFile(
    String path, {
    required String originalName,
    required String mimeType,
    required String role,
  }) async {
    if (path.isEmpty) {
      return _missing(path, originalName, mimeType, role);
    }
    final file = File(path);
    if (!await file.exists()) {
      warnings.add('资源缺失：$originalName ($path)');
      return _missing(path, originalName, mimeType, role);
    }
    final bytes = await file.readAsBytes();
    final hash = sha256.convert(bytes).toString();
    final key = '$hash:${bytes.length}';
    final existing = _byHashAndSize[key];
    if (existing != null) {
      duplicateCount++;
      return existing;
    }
    final kind = _resourceKind(mimeType, role);
    final safeName = safeExportFileName(originalName, fallback: 'asset');
    final prefix = hash.substring(0, 2);
    final storedName = '${hash}_$safeName';
    final relativePath = 'assets/$kind/$prefix/$storedName';
    final targetDir = Directory('${assetsDir.path}/$kind/$prefix');
    await targetDir.create(recursive: true);
    await File(
      '${targetDir.path}/$storedName',
    ).writeAsBytes(bytes, flush: true);
    final record = _ResourceRecord(
      id: 'res_${hash.substring(0, 32)}',
      kind: kind,
      role: role,
      originalPath: path,
      originalName: originalName,
      relativePath: relativePath,
      mimeType: mimeType,
      size: bytes.length,
      sha256Hash: hash,
      missing: false,
    );
    _byHashAndSize[key] = record;
    records.add(record);
    return record;
  }

  _ResourceRecord _missing(
    String path,
    String originalName,
    String mimeType,
    String role,
  ) {
    missingCount++;
    final hash = sha256.convert(utf8.encode('$path|$originalName')).toString();
    final record = _ResourceRecord(
      id: 'missing_${hash.substring(0, 32)}',
      kind: _resourceKind(mimeType, role),
      role: role,
      originalPath: path,
      originalName: originalName,
      relativePath: null,
      mimeType: mimeType,
      size: 0,
      sha256Hash: null,
      missing: true,
    );
    records.add(record);
    return record;
  }
}

class _ResourceRecord {
  final String id;
  final String kind;
  final String role;
  final String originalPath;
  final String originalName;
  final String? relativePath;
  final String mimeType;
  final int size;
  final String? sha256Hash;
  final bool missing;

  const _ResourceRecord({
    required this.id,
    required this.kind,
    required this.role,
    required this.originalPath,
    required this.originalName,
    required this.relativePath,
    required this.mimeType,
    required this.size,
    required this.sha256Hash,
    required this.missing,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'role': role,
    'originalPath': originalPath,
    'originalName': originalName,
    if (relativePath != null) 'relativePath': relativePath,
    'mimeType': mimeType,
    'size': size,
    if (sha256Hash != null) 'sha256': sha256Hash,
    'missing': missing,
  };
}

String _resourceKind(String mimeType, String role) {
  if (role == 'background') return 'backgrounds';
  if (mimeType.startsWith('image/')) return 'images';
  if (mimeType.startsWith('audio/')) return 'audio';
  if (mimeType.startsWith('video/')) return 'video';
  if (mimeType == 'application/octet-stream') return 'unknown';
  return 'documents';
}

String _mimeTypeFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.txt') || lower.endsWith('.md')) return 'text/plain';
  if (lower.endsWith('.json')) return 'application/json';
  if (lower.endsWith('.csv')) return 'text/csv';
  return 'application/octet-stream';
}

String _uniqueFileName(String base, String extension, Set<String> used) {
  final safeBase = safeExportFileName(base, fallback: 'page');
  var candidate = '$safeBase.$extension';
  var index = 1;
  while (used.contains(candidate)) {
    candidate = '${safeBase}_$index.$extension';
    index++;
  }
  return candidate;
}
