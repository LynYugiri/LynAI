import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/app_settings.dart';
import '../models/backup_models.dart';
import '../models/chat_role.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/model_config.dart';
import '../models/note.dart';
import '../models/schedule_item.dart';
import '../models/todo_list.dart';
import '../providers/conversation_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/file_name_utils.dart';

/// 负责 LynAI ZIP 备份的导出、读取、预览和导入。
///
/// 备份格式由 `manifest.json` 描述，业务数据按分区写入 JSON，应用私有目录
/// 中被引用的附件写入 `assets/`。导入时先恢复附件，再把旧设备路径重映射
/// 为当前设备路径，避免数据引用不可用文件。
class BackupService {
  BackupService({
    required this.settingsProvider,
    required this.modelConfigProvider,
    required this.conversationProvider,
    required this.featureProvider,
  });

  final SettingsProvider settingsProvider;
  final ModelConfigProvider modelConfigProvider;
  final ConversationProvider conversationProvider;
  final FeatureProvider featureProvider;
  final _uuid = const Uuid();

  static const currentSchemaVersion = 1;
  static const _backupType = 'lynai.backup';

  static Set<BackupSettingsPart> settingsPartsFromManifest(
    Map<String, dynamic> manifest,
    BackupData data,
  ) {
    final sections = manifest['sections'];
    final settings = sections is Map
        ? sections[BackupSection.settings.key]
        : null;
    final rawParts = settings is Map ? settings['parts'] : null;
    if (rawParts is List) {
      final parts = <BackupSettingsPart>{};
      for (final value in rawParts.whereType<String>()) {
        for (final part in BackupSettingsPart.values) {
          if (part.name == value) parts.add(part);
        }
      }
      return parts;
    }
    final parts = <BackupSettingsPart>{};
    if (data.modelConfigs?.isNotEmpty ?? false) {
      parts.add(BackupSettingsPart.apiConfigs);
    }
    if (data.appSettings != null) {
      parts.addAll(
        BackupSettingsPart.values.where(
          (part) => part != BackupSettingsPart.apiConfigs,
        ),
      );
    }
    return parts;
  }

  Future<File> exportZip(BackupSelection selection) async {
    final package = await PackageInfo.fromPlatform();
    final createdAt = DateTime.now();
    final archive = Archive();
    final sections = <String, dynamic>{};
    final assetRecords = <Map<String, dynamic>>[];
    final archivedAssetPaths = <String, String>{};
    final privateRoots = await _privateStorageRoots();

    void addJson(String path, Object value) {
      final bytes = utf8.encode(
        const JsonEncoder.withIndent('  ').convert(value),
      );
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    Future<void> addPrivateAsset(
      String? originalPath,
      String kind, {
      String? name,
    }) async {
      if (originalPath == null || originalPath.isEmpty) return;
      if (archivedAssetPaths.containsKey(originalPath)) return;
      final file = File(originalPath);
      if (!await file.exists()) return;
      if (!_isInPrivateStorage(file, privateRoots)) return;
      final safeName = safeStorageFileName(
        name ?? file.uri.pathSegments.last,
        fallback: 'asset',
      );
      final archivePath = 'assets/$kind/${assetRecords.length}_$safeName';
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
      archivedAssetPaths[originalPath] = archivePath;
      assetRecords.add({
        'kind': kind,
        'originalPath': originalPath,
        'archivePath': archivePath,
        'name': safeName,
      });
    }

    if (selection.contains(BackupSection.settings)) {
      final settings = settingsProvider.settings;
      final models =
          selection.settingsParts.contains(BackupSettingsPart.apiConfigs)
          ? modelConfigProvider.models
          : const <ModelConfig>[];
      addJson('settings.json', {
        'appSettings': _settingsToJson(settings, selection.settingsParts),
      });
      if (selection.settingsParts.contains(BackupSettingsPart.appearance)) {
        await addPrivateAsset(
          settings.backgroundImagePath,
          'backgrounds',
          name: 'background${_extensionFromPath(settings.backgroundImagePath)}',
        );
      }
      addJson('model_configs.json', {
        'models': models.map((model) => model.toJson()).toList(),
      });
      sections[BackupSection.settings.key] = {
        'enabled': true,
        'files': ['settings.json', 'model_configs.json'],
        'parts': selection.settingsParts.map((part) => part.name).toList(),
        'modelCount': models.length,
      };
    }
    if (selection.contains(BackupSection.conversations)) {
      final conversations = conversationProvider.conversations
          .where((item) => selection.conversationIds.contains(item.id))
          .toList();
      for (final conversation in conversations) {
        for (final message in conversation.messages) {
          for (final image in message.images) {
            await addPrivateAsset(
              image.path,
              'message_images',
              name: image.name,
            );
          }
        }
      }
      addJson('conversations.json', {
        'conversations': conversations.map((item) => item.toJson()).toList(),
      });
      sections[BackupSection.conversations.key] = {
        'enabled': true,
        'files': ['conversations.json'],
        'count': conversations.length,
      };
    }
    if (selection.contains(BackupSection.notes)) {
      final notes = featureProvider.notes
          .where((item) => selection.noteIds.contains(item.id))
          .toList();
      final noteIds = notes.map((item) => item.id).toSet();
      final folderIds = notes
          .map((item) => item.folderId)
          .whereType<String>()
          .toSet();
      final folders = featureProvider.noteFolders
          .where((item) => folderIds.contains(item.id))
          .toList();
      final revisions = featureProvider.noteRevisions
          .where((item) => noteIds.contains(item.noteId))
          .toList();
      addJson('notes/folders.json', {
        'folders': folders.map((item) => item.toJson()).toList(),
      });
      addJson('notes/notes.json', {
        'notes': notes.map((item) => item.toJson()).toList(),
      });
      addJson('notes/revisions.json', {
        'revisions': revisions.map((item) => item.toJson()).toList(),
      });
      sections[BackupSection.notes.key] = {
        'enabled': true,
        'files': [
          'notes/folders.json',
          'notes/notes.json',
          'notes/revisions.json',
        ],
        'folderCount': folders.length,
        'noteCount': notes.length,
        'revisionCount': revisions.length,
      };
    }
    if (selection.contains(BackupSection.schedules)) {
      final schedules = featureProvider.schedules
          .where((item) => selection.scheduleIds.contains(item.id))
          .toList();
      addJson('schedules.json', {
        'schedules': schedules.map((item) => item.toJson()).toList(),
      });
      sections[BackupSection.schedules.key] = {
        'enabled': true,
        'files': ['schedules.json'],
        'count': schedules.length,
      };
    }
    if (selection.contains(BackupSection.todoLists)) {
      final todoLists = featureProvider.todoLists
          .where((item) => selection.todoListIds.contains(item.id))
          .toList();
      addJson('todo_lists.json', {
        'todoLists': todoLists.map((item) => item.toJson()).toList(),
      });
      sections[BackupSection.todoLists.key] = {
        'enabled': true,
        'files': ['todo_lists.json'],
        'count': todoLists.length,
      };
    }

    addJson('manifest.json', {
      'type': _backupType,
      'schemaVersion': currentSchemaVersion,
      'appVersion': package.version,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'format': 'zip',
      'sections': sections,
      if (assetRecords.isNotEmpty) 'assets': assetRecords,
    });

    final dir = await getTemporaryDirectory();
    final name = 'lynai-${_formatFileDate(createdAt)}.zip';
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);
    return file;
  }

  Future<BackupArchiveData> readZip(File file) async {
    final decoded = ZipDecoder().decodeBytes(await file.readAsBytes());
    final files = {for (final file in decoded.files) file.name: file};
    final assetFiles = <String, List<int>>{};
    for (final entry in decoded.files) {
      final content = entry.content;
      if (entry.name.startsWith('assets/')) {
        assetFiles[entry.name] = List<int>.from(content);
      }
    }
    final warnings = <String>[];

    Map<String, dynamic>? readMap(String path) {
      final entry = files[path];
      if (entry == null) return null;
      try {
        return jsonDecode(utf8.decode(entry.content as List<int>))
            as Map<String, dynamic>;
      } catch (e) {
        warnings.add('$path 解析失败：$e');
        return null;
      }
    }

    final manifest = readMap('manifest.json');
    if (manifest == null) throw const FormatException('备份包缺少 manifest.json');
    if (manifest['type'] != _backupType) {
      throw const FormatException('这不是 LynAI 备份文件');
    }
    final schemaVersion = (manifest['schemaVersion'] as num?)?.toInt();
    if (schemaVersion == null || schemaVersion > currentSchemaVersion) {
      throw const FormatException('备份版本过高，当前应用无法导入');
    }

    final settingsJson = readMap('settings.json');
    final modelsJson = readMap('model_configs.json');
    final conversationsJson = readMap('conversations.json');
    final foldersJson = readMap('notes/folders.json');
    final notesJson = readMap('notes/notes.json');
    final revisionsJson = readMap('notes/revisions.json');
    final schedulesJson = readMap('schedules.json');
    final todoListsJson = readMap('todo_lists.json');

    return BackupArchiveData(
      manifest: manifest,
      warnings: warnings,
      data: BackupData(
        appSettings: _parseOne(
          _nonEmptyMap(settingsJson?['appSettings']),
          AppSettings.fromJson,
          warnings,
          '设置',
        ),
        modelConfigs: _parseList(
          modelsJson?['models'],
          ModelConfig.fromJson,
          warnings,
          '模型配置',
        ),
        conversations: _parseList(
          conversationsJson?['conversations'],
          Conversation.fromJson,
          warnings,
          '对话记录',
        ),
        noteFolders: _parseList(
          foldersJson?['folders'],
          NoteFolder.fromJson,
          warnings,
          '笔记文件夹',
        ),
        notes: _parseList(notesJson?['notes'], Note.fromJson, warnings, '笔记'),
        noteRevisions: _parseList(
          revisionsJson?['revisions'],
          NoteRevision.fromJson,
          warnings,
          '笔记修订',
        ),
        schedules: _parseList(
          schedulesJson?['schedules'],
          ScheduleItem.fromJson,
          warnings,
          '日程',
        ),
        todoLists: _parseList(
          todoListsJson?['todoLists'],
          TodoList.fromJson,
          warnings,
          '待办清单',
        ),
      ),
      assetFiles: assetFiles,
    );
  }

  BackupPreview preview(BackupArchiveData archive, BackupSelection selection) {
    final data = _filterData(archive.data, selection);
    return BackupPreview(
      archive: archive,
      warnings: archive.warnings,
      sections: BackupSection.values
          .where(
            (section) =>
                selection.sections.contains(section) &&
                data.hasSection(section),
          )
          .map(
            (section) => ImportSectionPreview(
              section: section,
              detail: _sectionDetail(section, data),
            ),
          )
          .toList(),
      conflicts: _findConflicts(data, selection),
    );
  }

  Future<ImportResult> importArchive(
    BackupArchiveData archive,
    ImportPlan plan,
  ) async {
    final filteredData = _filterData(archive.data, plan.selection);
    final restoredAssetPaths = await _restoreAssets(
      archive,
      _referencedAssetPaths(filteredData, plan.selection.settingsParts),
    );
    final data = _remapBackupAssetPaths(filteredData, restoredAssetPaths);
    var added = 0;
    var replaced = 0;
    var skipped = 0;
    final idMap = _ImportIdMap();

    try {
      if (plan.sections.contains(BackupSection.settings)) {
        final result = await _applySettings(data, plan, idMap);
        added += result.added;
        replaced += result.replaced;
        skipped += result.skipped;
      }
      if (plan.sections.contains(BackupSection.conversations)) {
        final result = await _applyConversations(data, plan, idMap);
        added += result.added;
        replaced += result.replaced;
        skipped += result.skipped;
      }
      if (plan.sections.contains(BackupSection.notes)) {
        final result = await _applyNotes(data, plan, idMap);
        added += result.added;
        replaced += result.replaced;
        skipped += result.skipped;
      }
      if (plan.sections.contains(BackupSection.schedules)) {
        final result = await _applySchedules(data, plan);
        added += result.added;
        replaced += result.replaced;
        skipped += result.skipped;
      }
      if (plan.sections.contains(BackupSection.todoLists)) {
        final result = await _applyTodoLists(data, plan);
        added += result.added;
        replaced += result.replaced;
        skipped += result.skipped;
      }

      return ImportResult(
        added: added,
        replaced: replaced,
        skipped: skipped,
        warnings: archive.warnings,
      );
    } finally {
      await _deleteUnreferencedRestoredAssets(
        restoredAssetPaths.values,
        archive.warnings,
      );
    }
  }

  Future<ImportResult> _applySettings(
    BackupData data,
    ImportPlan plan,
    _ImportIdMap idMap,
  ) async {
    var added = 0;
    var replaced = 0;
    var skipped = 0;
    final parts = plan.selection.settingsParts;
    final importingApi = parts.contains(BackupSettingsPart.apiConfigs);
    final importingAppSettings = parts.any(
      (part) => part != BackupSettingsPart.apiConfigs,
    );
    final incomingModels = importingApi ? data.modelConfigs : null;
    if (incomingModels != null) {
      if (plan.mode == ImportMode.replaceSection) {
        await modelConfigProvider.replaceModels(incomingModels);
        replaced += incomingModels.length;
      } else {
        final models = List<ModelConfig>.from(modelConfigProvider.models);
        for (final incoming in incomingModels) {
          final index = models.indexWhere((item) => item.id == incoming.id);
          if (index == -1) {
            models.add(incoming);
            added++;
          } else if (_sameJson(models[index], incoming)) {
            skipped++;
          } else if (plan.mode == ImportMode.addOnly) {
            skipped++;
          } else {
            final action = plan.actionFor(
              _conflictId(BackupSection.settings, incoming.id),
            );
            if (action == ImportConflictAction.replaceLocal) {
              models[index] = incoming;
              replaced++;
            } else if (action == ImportConflictAction.keepBoth) {
              final next = incoming.copyWith(id: _uuid.v4());
              idMap.modelIds[incoming.id] = next.id;
              models.add(next);
              added++;
            } else {
              skipped++;
            }
          }
        }
        await modelConfigProvider.replaceModels(models);
      }
    }

    final appSettings = importingAppSettings ? data.appSettings : null;
    if (appSettings != null) {
      final current = settingsProvider.settings;
      final mergedParts = _mergeSettingsParts(current, appSettings, parts);
      if (plan.mode == ImportMode.replaceSection) {
        await settingsProvider.replaceSettings(
          _repairSettingsReferences(_remapSettings(mergedParts, idMap)),
        );
        replaced++;
      } else if (_sameJson(current, mergedParts)) {
        skipped++;
      } else if (plan.mode == ImportMode.addOnly) {
        if (parts.contains(BackupSettingsPart.rolesAndPrompts)) {
          final merged = _appendMissingRolesAndPrompts(
            current,
            appSettings,
            idMap,
          );
          if (_sameJson(current, merged)) {
            skipped++;
          } else {
            await settingsProvider.replaceSettings(merged);
            added++;
          }
        } else {
          skipped++;
        }
      } else {
        final action = plan.actionFor(
          _conflictId(BackupSection.settings, 'appSettings'),
        );
        if (action == ImportConflictAction.replaceLocal) {
          await settingsProvider.replaceSettings(
            _repairSettingsReferences(_remapSettings(mergedParts, idMap)),
          );
          replaced++;
        } else if (action == ImportConflictAction.keepBoth) {
          await settingsProvider.replaceSettings(
            _repairSettingsReferences(
              _mergeSettingsWithImportedParts(
                current,
                appSettings,
                idMap,
                parts,
              ),
            ),
          );
          added++;
        } else {
          skipped++;
        }
      }
    }
    return ImportResult(added: added, replaced: replaced, skipped: skipped);
  }

  Future<ImportResult> _applyConversations(
    BackupData data,
    ImportPlan plan,
    _ImportIdMap idMap,
  ) async {
    final incomingItems = data.conversations;
    if (incomingItems == null) {
      return const ImportResult(added: 0, replaced: 0, skipped: 0);
    }
    if (plan.mode == ImportMode.replaceSection) {
      final incomingIds = incomingItems.map((item) => item.id).toSet();
      final items = conversationProvider.conversations
          .where((item) => !incomingIds.contains(item.id))
          .toList();
      items.addAll(
        incomingItems.map((item) => _remapConversation(item, idMap)),
      );
      await conversationProvider.replaceConversations(items);
      return ImportResult(added: 0, replaced: incomingItems.length, skipped: 0);
    }
    var added = 0;
    var replaced = 0;
    var skipped = 0;
    final items = List<Conversation>.from(conversationProvider.conversations);
    for (final raw in incomingItems) {
      final incoming = _remapConversation(raw, idMap);
      final index = items.indexWhere((item) => item.id == incoming.id);
      if (index == -1) {
        items.add(incoming);
        added++;
      } else if (_sameJson(items[index], incoming)) {
        skipped++;
      } else if (plan.mode == ImportMode.addOnly) {
        skipped++;
      } else {
        final action = plan.actionFor(
          _conflictId(BackupSection.conversations, raw.id),
        );
        if (action == ImportConflictAction.replaceLocal) {
          items[index] = incoming;
          replaced++;
        } else if (action == ImportConflictAction.keepBoth) {
          items.add(incoming.copyWith(id: _uuid.v4()));
          added++;
        } else {
          skipped++;
        }
      }
    }
    await conversationProvider.replaceConversations(items);
    return ImportResult(added: added, replaced: replaced, skipped: skipped);
  }

  Future<ImportResult> _applyNotes(
    BackupData data,
    ImportPlan plan,
    _ImportIdMap idMap,
  ) async {
    final incomingFolders = data.noteFolders ?? const <NoteFolder>[];
    final incomingNotes = data.notes ?? const <Note>[];
    final incomingRevisions = data.noteRevisions ?? const <NoteRevision>[];
    if (plan.mode == ImportMode.replaceSection) {
      final incomingNoteIds = incomingNotes.map((item) => item.id).toSet();
      final incomingFolderIds = incomingFolders.map((item) => item.id).toSet();
      final incomingRevisionIds = incomingRevisions
          .map((item) => item.id)
          .toSet();
      final folders = featureProvider.noteFolders
          .where((item) => !incomingFolderIds.contains(item.id))
          .toList();
      final notes = featureProvider.notes
          .where((item) => !incomingNoteIds.contains(item.id))
          .toList();
      final revisions = featureProvider.noteRevisions
          .where(
            (item) =>
                !incomingNoteIds.contains(item.noteId) &&
                !incomingRevisionIds.contains(item.id),
          )
          .toList();
      folders.addAll(incomingFolders);
      notes.addAll(incomingNotes);
      revisions.addAll(incomingRevisions);
      await featureProvider.replaceFeatureData(
        noteFolders: folders,
        notes: notes,
        noteRevisions: revisions,
      );
      return ImportResult(
        added: 0,
        replaced:
            incomingFolders.length +
            incomingNotes.length +
            incomingRevisions.length,
        skipped: 0,
      );
    }

    var added = 0;
    var replaced = 0;
    var skipped = 0;
    final folders = List<NoteFolder>.from(featureProvider.noteFolders);
    final notes = List<Note>.from(featureProvider.notes);
    final revisions = List<NoteRevision>.from(featureProvider.noteRevisions);

    for (final incoming in incomingFolders) {
      final index = folders.indexWhere((item) => item.id == incoming.id);
      if (index == -1) {
        folders.add(incoming);
        added++;
      } else if (_sameJson(folders[index], incoming)) {
        skipped++;
      } else if (plan.mode == ImportMode.addOnly) {
        skipped++;
      } else {
        final action = plan.actionFor(
          _conflictId(BackupSection.notes, 'folder:${incoming.id}'),
        );
        if (action == ImportConflictAction.replaceLocal) {
          folders[index] = incoming;
          replaced++;
        } else if (action == ImportConflictAction.keepBoth) {
          final next = incoming.copyWith(id: _uuid.v4());
          idMap.noteFolderIds[incoming.id] = next.id;
          folders.add(next);
          added++;
        } else {
          skipped++;
        }
      }
    }

    for (final incoming in incomingNotes) {
      final remapped = _remapNote(incoming, idMap);
      final index = notes.indexWhere((item) => item.id == incoming.id);
      if (index == -1) {
        notes.add(remapped);
        added++;
      } else if (_sameJson(notes[index], remapped)) {
        skipped++;
      } else if (plan.mode == ImportMode.addOnly) {
        skipped++;
      } else {
        final action = plan.actionFor(
          _conflictId(BackupSection.notes, 'note:${incoming.id}'),
        );
        if (action == ImportConflictAction.replaceLocal) {
          notes[index] = remapped;
          replaced++;
        } else if (action == ImportConflictAction.keepBoth) {
          final newNoteId = _uuid.v4();
          idMap.noteIds[incoming.id] = newNoteId;
          for (final revision in incomingRevisions.where(
            (item) => item.noteId == incoming.id,
          )) {
            idMap.noteRevisionIds.putIfAbsent(revision.id, _uuid.v4);
          }
          notes.add(_remapNote(incoming, idMap).copyWith(id: newNoteId));
          added++;
        } else {
          skipped++;
        }
      }
    }

    for (final incoming in incomingRevisions) {
      final remapped = _remapRevision(incoming, idMap);
      if (idMap.noteRevisionIds.containsKey(incoming.id)) {
        revisions.add(remapped);
        added++;
        continue;
      }
      final index = revisions.indexWhere((item) => item.id == incoming.id);
      if (index == -1) {
        revisions.add(remapped);
        added++;
      } else if (_sameJson(revisions[index], remapped)) {
        skipped++;
      } else if (plan.mode == ImportMode.addOnly) {
        skipped++;
      } else {
        final action = plan.actionFor(
          _conflictId(BackupSection.notes, 'revision:${incoming.id}'),
        );
        if (action == ImportConflictAction.replaceLocal) {
          revisions[index] = remapped;
          replaced++;
        } else if (action == ImportConflictAction.keepBoth) {
          revisions.add(
            _remapRevision(incoming, idMap).copyWith(id: _uuid.v4()),
          );
          added++;
        } else {
          skipped++;
        }
      }
    }

    await featureProvider.replaceFeatureData(
      noteFolders: folders,
      notes: notes,
      noteRevisions: revisions,
    );
    return ImportResult(added: added, replaced: replaced, skipped: skipped);
  }

  Future<ImportResult> _applySchedules(BackupData data, ImportPlan plan) async {
    final incomingItems = data.schedules;
    if (incomingItems == null) {
      return const ImportResult(added: 0, replaced: 0, skipped: 0);
    }
    if (plan.mode == ImportMode.replaceSection) {
      final incomingIds = incomingItems.map((item) => item.id).toSet();
      final items = featureProvider.schedules
          .where((item) => !incomingIds.contains(item.id))
          .toList();
      items.addAll(incomingItems);
      await featureProvider.replaceFeatureData(schedules: items);
      return ImportResult(added: 0, replaced: incomingItems.length, skipped: 0);
    }
    var added = 0;
    var replaced = 0;
    var skipped = 0;
    final items = List<ScheduleItem>.from(featureProvider.schedules);
    for (final incoming in incomingItems) {
      final index = items.indexWhere((item) => item.id == incoming.id);
      if (index == -1) {
        items.add(incoming);
        added++;
      } else if (_sameJson(items[index], incoming)) {
        skipped++;
      } else if (plan.mode == ImportMode.addOnly) {
        skipped++;
      } else {
        final action = plan.actionFor(
          _conflictId(BackupSection.schedules, incoming.id),
        );
        if (action == ImportConflictAction.replaceLocal) {
          items[index] = incoming;
          replaced++;
        } else if (action == ImportConflictAction.keepBoth) {
          items.add(incoming.copyWith(id: _uuid.v4()));
          added++;
        } else {
          skipped++;
        }
      }
    }
    await featureProvider.replaceFeatureData(schedules: items);
    return ImportResult(added: added, replaced: replaced, skipped: skipped);
  }

  Future<ImportResult> _applyTodoLists(BackupData data, ImportPlan plan) async {
    final incomingItems = data.todoLists;
    if (incomingItems == null) {
      return const ImportResult(added: 0, replaced: 0, skipped: 0);
    }
    if (plan.mode == ImportMode.replaceSection) {
      final incomingIds = incomingItems.map((item) => item.id).toSet();
      final items = featureProvider.todoLists
          .where((item) => !incomingIds.contains(item.id))
          .toList();
      items.addAll(incomingItems);
      await featureProvider.replaceFeatureData(todoLists: items);
      return ImportResult(added: 0, replaced: incomingItems.length, skipped: 0);
    }
    var added = 0;
    var replaced = 0;
    var skipped = 0;
    final items = List<TodoList>.from(featureProvider.todoLists);
    for (final incoming in incomingItems) {
      final index = items.indexWhere((item) => item.id == incoming.id);
      if (index == -1) {
        items.add(incoming);
        added++;
      } else if (_sameJson(items[index], incoming)) {
        skipped++;
      } else if (plan.mode == ImportMode.addOnly) {
        skipped++;
      } else {
        final action = plan.actionFor(
          _conflictId(BackupSection.todoLists, incoming.id),
        );
        if (action == ImportConflictAction.replaceLocal) {
          items[index] = incoming;
          replaced++;
        } else if (action == ImportConflictAction.keepBoth) {
          items.add(incoming.copyWith(id: _uuid.v4()));
          added++;
        } else {
          skipped++;
        }
      }
    }
    await featureProvider.replaceFeatureData(todoLists: items);
    return ImportResult(added: added, replaced: replaced, skipped: skipped);
  }

  List<ImportConflict> _findConflicts(
    BackupData data,
    BackupSelection selection,
  ) {
    final conflicts = <ImportConflict>[];
    final sections = selection.sections;
    if (sections.contains(BackupSection.settings)) {
      final parts = selection.settingsParts;
      final incomingSettings =
          parts.any((part) => part != BackupSettingsPart.apiConfigs)
          ? data.appSettings
          : null;
      if (incomingSettings != null &&
          !_sameJson(
            settingsProvider.settings,
            _mergeSettingsParts(
              settingsProvider.settings,
              incomingSettings,
              parts,
            ),
          )) {
        conflicts.add(
          ImportConflict(
            id: _conflictId(BackupSection.settings, 'appSettings'),
            section: BackupSection.settings,
            title: '应用设置',
            localSummary: '当前本机设置',
            incomingSummary: '备份中的设置',
          ),
        );
      }
      final incomingModels = parts.contains(BackupSettingsPart.apiConfigs)
          ? data.modelConfigs ?? const <ModelConfig>[]
          : const <ModelConfig>[];
      for (final incoming in incomingModels) {
        final local = _findById(modelConfigProvider.models, incoming.id);
        if (local != null && !_sameJson(local, incoming)) {
          conflicts.add(
            ImportConflict(
              id: _conflictId(BackupSection.settings, incoming.id),
              section: BackupSection.settings,
              title: '模型配置：${incoming.name}',
              localSummary: _formatModel(local),
              incomingSummary: _formatModel(incoming),
            ),
          );
        }
      }
    }
    if (sections.contains(BackupSection.conversations)) {
      for (final incoming in data.conversations ?? const <Conversation>[]) {
        final local = _findById(
          conversationProvider.conversations,
          incoming.id,
        );
        if (local != null && !_sameJson(local, incoming)) {
          conflicts.add(
            ImportConflict(
              id: _conflictId(BackupSection.conversations, incoming.id),
              section: BackupSection.conversations,
              title: incoming.title,
              localSummary: _formatUpdated(local.updatedAt),
              incomingSummary: _formatUpdated(incoming.updatedAt),
            ),
          );
        }
      }
    }
    if (sections.contains(BackupSection.notes)) {
      for (final incoming in data.noteFolders ?? const <NoteFolder>[]) {
        final local = _findById(featureProvider.noteFolders, incoming.id);
        if (local != null && !_sameJson(local, incoming)) {
          conflicts.add(
            ImportConflict(
              id: _conflictId(BackupSection.notes, 'folder:${incoming.id}'),
              section: BackupSection.notes,
              title: '文件夹：${incoming.title}',
              localSummary: _formatUpdated(local.updatedAt),
              incomingSummary: _formatUpdated(incoming.updatedAt),
            ),
          );
        }
      }
      for (final incoming in data.notes ?? const <Note>[]) {
        final local = _findById(featureProvider.notes, incoming.id);
        if (local != null && !_sameJson(local, incoming)) {
          conflicts.add(
            ImportConflict(
              id: _conflictId(BackupSection.notes, 'note:${incoming.id}'),
              section: BackupSection.notes,
              title: '笔记：${incoming.title}',
              localSummary: _formatUpdated(local.updatedAt),
              incomingSummary: _formatUpdated(incoming.updatedAt),
            ),
          );
        }
      }
      for (final incoming in data.noteRevisions ?? const <NoteRevision>[]) {
        final local = _findById(featureProvider.noteRevisions, incoming.id);
        if (local != null && !_sameJson(local, incoming)) {
          conflicts.add(
            ImportConflict(
              id: _conflictId(BackupSection.notes, 'revision:${incoming.id}'),
              section: BackupSection.notes,
              title: '笔记修订：${incoming.id}',
              localSummary: _formatUpdated(local.savedAt),
              incomingSummary: _formatUpdated(incoming.savedAt),
            ),
          );
        }
      }
    }
    if (sections.contains(BackupSection.schedules)) {
      for (final incoming in data.schedules ?? const <ScheduleItem>[]) {
        final local = _findById(featureProvider.schedules, incoming.id);
        if (local != null && !_sameJson(local, incoming)) {
          conflicts.add(
            ImportConflict(
              id: _conflictId(BackupSection.schedules, incoming.id),
              section: BackupSection.schedules,
              title: incoming.title,
              localSummary: _formatRange(local.start, local.end),
              incomingSummary: _formatRange(incoming.start, incoming.end),
            ),
          );
        }
      }
    }
    if (sections.contains(BackupSection.todoLists)) {
      for (final incoming in data.todoLists ?? const <TodoList>[]) {
        final local = _findById(featureProvider.todoLists, incoming.id);
        if (local != null && !_sameJson(local, incoming)) {
          conflicts.add(
            ImportConflict(
              id: _conflictId(BackupSection.todoLists, incoming.id),
              section: BackupSection.todoLists,
              title: incoming.title,
              localSummary:
                  '${local.items.length} 项，${_formatUpdated(local.updatedAt)}',
              incomingSummary:
                  '${incoming.items.length} 项，${_formatUpdated(incoming.updatedAt)}',
            ),
          );
        }
      }
    }
    return conflicts;
  }

  AppSettings _mergeSettings(
    AppSettings local,
    AppSettings incoming,
    _ImportIdMap idMap,
  ) {
    final usedRoleIds = local.roles.map((item) => item.id).toSet();
    final roles = [...local.roles];
    for (final role in incoming.roles) {
      if (role.id == ChatRole.defaultId) continue;
      final next = usedRoleIds.contains(role.id)
          ? role.copyWith(id: _newUniqueId(usedRoleIds))
          : role;
      idMap.roleIds[role.id] = next.id;
      roles.add(_remapRole(next, idMap));
      usedRoleIds.add(next.id);
    }
    final usedPromptIds = local.systemPrompts.map((item) => item.id).toSet();
    final prompts = [...local.systemPrompts];
    for (final prompt in incoming.systemPrompts) {
      final mappedId = idMap.roleIds[prompt.id];
      final needsNewId = usedPromptIds.contains(prompt.id);
      final nextId =
          mappedId ?? (needsNewId ? _newUniqueId(usedPromptIds) : prompt.id);
      final next = prompt.copyWith(id: nextId);
      idMap.systemPromptIds[prompt.id] = next.id;
      prompts.add(next);
      usedPromptIds.add(next.id);
    }
    return local.copyWith(roles: roles, systemPrompts: prompts);
  }

  AppSettings _mergeSettingsWithImportedParts(
    AppSettings local,
    AppSettings incoming,
    _ImportIdMap idMap,
    Set<BackupSettingsPart> parts,
  ) {
    var merged = _mergeSettingsParts(
      local,
      incoming,
      parts.difference({BackupSettingsPart.rolesAndPrompts}),
    );
    if (parts.contains(BackupSettingsPart.rolesAndPrompts)) {
      merged = _mergeSettings(merged, incoming, idMap);
    }
    return merged;
  }

  AppSettings _appendMissingRolesAndPrompts(
    AppSettings local,
    AppSettings incoming,
    _ImportIdMap idMap,
  ) {
    final roleIds = local.roles.map((item) => item.id).toSet();
    final promptIds = local.systemPrompts.map((item) => item.id).toSet();
    final roles = [...local.roles];
    final prompts = [...local.systemPrompts];
    for (final role in incoming.roles) {
      if (role.id == ChatRole.defaultId || roleIds.contains(role.id)) continue;
      roles.add(_remapRole(role, idMap));
      roleIds.add(role.id);
      idMap.roleIds.putIfAbsent(role.id, () => role.id);
    }
    for (final prompt in incoming.systemPrompts) {
      if (promptIds.contains(prompt.id)) continue;
      final nextId = idMap.roleIds[prompt.id] ?? prompt.id;
      idMap.systemPromptIds.putIfAbsent(prompt.id, () => nextId);
      prompts.add(prompt.copyWith(id: nextId));
      promptIds.add(nextId);
    }
    return local.copyWith(roles: roles, systemPrompts: prompts);
  }

  AppSettings _mergeSettingsParts(
    AppSettings local,
    AppSettings incoming,
    Set<BackupSettingsPart> parts,
  ) {
    var next = local;
    if (parts.contains(BackupSettingsPart.appearance)) {
      next = next.copyWith(
        themeColor: incoming.themeColor,
        baseThemeColor: incoming.baseThemeColor,
        backgroundImagePath: incoming.backgroundImagePath,
        blurEnabled: incoming.blurEnabled,
        blurAmount: incoming.blurAmount,
        themeMode: incoming.themeMode,
      );
    }
    if (parts.contains(BackupSettingsPart.conversationSettings)) {
      next = next.copyWith(
        speechModelId: incoming.speechModelId,
        imageModelId: incoming.imageModelId,
        imageOcrEnabled: incoming.imageOcrEnabled,
        imageRecognitionModelId: incoming.imageRecognitionModelId,
        imageRecognitionEnabled: incoming.imageRecognitionEnabled,
        lastChatModelId: incoming.lastChatModelId,
        imageRecognitionPrompt: incoming.imageRecognitionPrompt,
        systemPrompt: incoming.systemPrompt,
        selectedSystemPromptId: incoming.selectedSystemPromptId,
        lastFeature: incoming.lastFeature,
      );
    }
    if (parts.contains(BackupSettingsPart.rolesAndPrompts)) {
      next = next.copyWith(
        roles: incoming.roles,
        currentRoleId: incoming.currentRoleId,
        systemPrompts: incoming.systemPrompts,
        selectedSystemPromptId: incoming.selectedSystemPromptId,
      );
    }
    return next;
  }

  AppSettings _remapSettings(AppSettings settings, _ImportIdMap idMap) {
    final roles = settings.roles
        .map((role) => _remapRole(role, idMap))
        .toList();
    final prompts = settings.systemPrompts.map((prompt) {
      return prompt.copyWith(
        id: idMap.systemPromptIds[prompt.id] ?? idMap.roleIds[prompt.id],
      );
    }).toList();
    return settings.copyWith(
      roles: roles,
      systemPrompts: prompts,
      currentRoleId:
          idMap.roleIds[settings.currentRoleId] ?? settings.currentRoleId,
      selectedSystemPromptId: settings.selectedSystemPromptId == null
          ? null
          : idMap.systemPromptIds[settings.selectedSystemPromptId] ??
                idMap.roleIds[settings.selectedSystemPromptId] ??
                settings.selectedSystemPromptId,
      speechModelId: _remapNullable(settings.speechModelId, idMap.modelIds),
      imageModelId: _remapNullable(settings.imageModelId, idMap.modelIds),
      imageRecognitionModelId: _remapNullable(
        settings.imageRecognitionModelId,
        idMap.modelIds,
      ),
      lastChatModelId: _remapNullable(settings.lastChatModelId, idMap.modelIds),
    );
  }

  AppSettings _repairSettingsReferences(AppSettings settings) {
    final modelIds = modelConfigProvider.models.map((item) => item.id).toSet();
    final roleIds = settings.roles.map((item) => item.id).toSet();
    final promptIds = settings.systemPrompts.map((item) => item.id).toSet();
    return settings.copyWith(
      speechModelId: _keepExistingId(settings.speechModelId, modelIds),
      imageModelId: _keepExistingId(settings.imageModelId, modelIds),
      imageRecognitionModelId: _keepExistingId(
        settings.imageRecognitionModelId,
        modelIds,
      ),
      lastChatModelId: _keepExistingId(settings.lastChatModelId, modelIds),
      currentRoleId: roleIds.contains(settings.currentRoleId)
          ? settings.currentRoleId
          : ChatRole.defaultId,
      selectedSystemPromptId: _keepExistingId(
        settings.selectedSystemPromptId,
        promptIds,
      ),
    );
  }

  static String? _keepExistingId(String? id, Set<String> validIds) {
    if (id == null || validIds.contains(id)) return id;
    return null;
  }

  String _newUniqueId(Set<String> usedIds) {
    var id = _uuid.v4();
    while (usedIds.contains(id)) {
      id = _uuid.v4();
    }
    return id;
  }

  ChatRole _remapRole(ChatRole role, _ImportIdMap idMap) {
    return role.copyWith(modelId: _remapNullable(role.modelId, idMap.modelIds));
  }

  Conversation _remapConversation(
    Conversation conversation,
    _ImportIdMap idMap,
  ) {
    final settings = conversation.settings.copyWith(
      modelId:
          idMap.modelIds[conversation.settings.modelId] ??
          conversation.settings.modelId,
      selectedSystemPromptId: _remapNullable(
        conversation.settings.selectedSystemPromptId,
        idMap.systemPromptIds,
      ),
      speechModelId: _remapNullable(
        conversation.settings.speechModelId,
        idMap.modelIds,
      ),
      imageModelId: _remapNullable(
        conversation.settings.imageModelId,
        idMap.modelIds,
      ),
      imageRecognitionModelId: _remapNullable(
        conversation.settings.imageRecognitionModelId,
        idMap.modelIds,
      ),
    );
    return conversation.copyWith(
      modelId: idMap.modelIds[conversation.modelId] ?? conversation.modelId,
      settings: settings,
      roleId: idMap.roleIds[conversation.roleId] ?? conversation.roleId,
    );
  }

  Note _remapNote(Note note, _ImportIdMap idMap) {
    return note.copyWith(
      id: idMap.noteIds[note.id],
      folderId: _remapNullable(note.folderId, idMap.noteFolderIds),
      currentRevisionId: _remapNullable(
        note.currentRevisionId,
        idMap.noteRevisionIds,
      ),
      preserveUpdatedAt: true,
    );
  }

  NoteRevision _remapRevision(NoteRevision revision, _ImportIdMap idMap) {
    return revision.copyWith(
      id: idMap.noteRevisionIds[revision.id],
      noteId: idMap.noteIds[revision.noteId] ?? revision.noteId,
      parentRevisionId: _remapNullable(
        revision.parentRevisionId,
        idMap.noteRevisionIds,
      ),
    );
  }

  static String? _remapNullable(String? id, Map<String, String> map) {
    if (id == null) return null;
    return map[id] ?? id;
  }

  Future<Map<String, String>> _restoreAssets(
    BackupArchiveData archive,
    Set<String> neededOriginalPaths,
  ) async {
    if (neededOriginalPaths.isEmpty) return {};
    final records = archive.manifest['assets'];
    if (records is! List) return {};
    final dir = await getApplicationDocumentsDirectory();
    final restored = <String, String>{};
    for (final raw in records) {
      if (raw is! Map) continue;
      final originalPath = raw['originalPath'] as String?;
      final archivePath = raw['archivePath'] as String?;
      if (originalPath == null ||
          archivePath == null ||
          !neededOriginalPaths.contains(originalPath)) {
        continue;
      }
      final bytes = archive.assetFiles[archivePath];
      if (bytes == null) {
        archive.warnings.add('资源文件缺失：$archivePath');
        restored[originalPath] = '';
        continue;
      }
      final kind = raw['kind'] as String? ?? 'assets';
      final targetFolder = kind == 'backgrounds'
          ? 'backgrounds'
          : 'message_images';
      final targetDir = Directory('${dir.path}/$targetFolder');
      if (!await targetDir.exists()) await targetDir.create(recursive: true);
      final name = safeStorageFileName(
        raw['name'] as String? ?? File(originalPath).uri.pathSegments.last,
        fallback: 'asset',
      );
      final file = File(
        '${targetDir.path}/${DateTime.now().microsecondsSinceEpoch}_$name',
      );
      await file.writeAsBytes(bytes, flush: true);
      restored[originalPath] = file.path;
    }
    return restored;
  }

  Future<void> _deleteUnreferencedRestoredAssets(
    Iterable<String> restoredPaths,
    List<String> warnings,
  ) async {
    final restored = restoredPaths.map(_normalizePath).toSet();
    if (restored.isEmpty) return;

    final referenced = <String>{};
    final backgroundPath = settingsProvider.settings.backgroundImagePath;
    if (backgroundPath != null && backgroundPath.isNotEmpty) {
      referenced.add(_normalizePath(backgroundPath));
    }
    for (final conversation in conversationProvider.conversations) {
      for (final message in conversation.messages) {
        for (final image in message.images) {
          if (image.path.isNotEmpty) referenced.add(_normalizePath(image.path));
        }
      }
    }

    for (final path in restored.difference(referenced)) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        warnings.add('清理未使用资源失败：$path，$e');
      }
    }
  }

  static Set<String> _referencedAssetPaths(
    BackupData data,
    Set<BackupSettingsPart> settingsParts,
  ) {
    final paths = <String>{};
    if (settingsParts.contains(BackupSettingsPart.appearance)) {
      final path = data.appSettings?.backgroundImagePath;
      if (path != null && path.isNotEmpty) paths.add(path);
    }
    for (final conversation in data.conversations ?? const <Conversation>[]) {
      for (final message in conversation.messages) {
        for (final image in message.images) {
          if (image.path.isNotEmpty) paths.add(image.path);
        }
      }
    }
    return paths;
  }

  static BackupData _remapBackupAssetPaths(
    BackupData data,
    Map<String, String> assetPaths,
  ) {
    if (assetPaths.isEmpty) return data;
    final appSettings = data.appSettings;
    final backgroundPath = appSettings?.backgroundImagePath;
    final mappedBackgroundPath = backgroundPath == null
        ? null
        : assetPaths[backgroundPath];
    return BackupData(
      appSettings: appSettings?.copyWith(
        backgroundImagePath: mappedBackgroundPath == null
            ? backgroundPath
            : mappedBackgroundPath.isEmpty
            ? null
            : mappedBackgroundPath,
      ),
      modelConfigs: data.modelConfigs,
      conversations: data.conversations
          ?.map(
            (conversation) =>
                _remapConversationAssetPaths(conversation, assetPaths),
          )
          .toList(),
      noteFolders: data.noteFolders,
      notes: data.notes,
      noteRevisions: data.noteRevisions,
      schedules: data.schedules,
      todoLists: data.todoLists,
    );
  }

  static Conversation _remapConversationAssetPaths(
    Conversation conversation,
    Map<String, String> assetPaths,
  ) {
    final messages = conversation.messages.map((message) {
      final images = message.images
          .map((image) {
            if (!assetPaths.containsKey(image.path)) return image;
            final path = assetPaths[image.path];
            return path == null || path.isEmpty
                ? image
                : MessageImage(
                    path: path,
                    name: image.name,
                    size: image.size,
                    mimeType: image.mimeType,
                  );
          })
          .where(
            (image) =>
                !assetPaths.containsKey(image.path) ||
                assetPaths[image.path] != '',
          )
          .toList();
      return Message(
        id: message.id,
        role: message.role,
        content: message.content,
        images: images,
        thinkingContent: message.thinkingContent,
        timestamp: message.timestamp,
      );
    }).toList();
    return conversation.copyWith(messages: messages);
  }

  static Future<List<Directory>> _privateStorageRoots() async {
    final roots = <Directory>[await getApplicationDocumentsDirectory()];
    try {
      roots.add(await getApplicationSupportDirectory());
    } catch (_) {
      // Some platforms may not expose an application support directory.
    }
    return roots;
  }

  static bool _isInPrivateStorage(File file, List<Directory> roots) {
    final path = _normalizePath(file.absolute.path);
    for (final root in roots) {
      final rootPath = _normalizePath(root.absolute.path);
      if (path == rootPath || path.startsWith('$rootPath/')) return true;
    }
    return false;
  }

  static String _normalizePath(String path) => path.replaceAll('\\', '/');

  static String _extensionFromPath(String? path) {
    if (path == null || path.isEmpty) return '';
    final name = path.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot);
  }

  static BackupData _filterData(BackupData data, BackupSelection selection) {
    final notes = data.notes
        ?.where((item) => selection.noteIds.contains(item.id))
        .toList();
    final noteIds = notes?.map((item) => item.id).toSet() ?? const <String>{};
    final folderIds =
        notes?.map((item) => item.folderId).whereType<String>().toSet() ??
        const <String>{};
    return BackupData(
      appSettings: data.appSettings,
      modelConfigs: data.modelConfigs,
      conversations: data.conversations
          ?.where((item) => selection.conversationIds.contains(item.id))
          .toList(),
      noteFolders: data.noteFolders
          ?.where((item) => folderIds.contains(item.id))
          .toList(),
      notes: notes,
      noteRevisions: data.noteRevisions
          ?.where((item) => noteIds.contains(item.noteId))
          .toList(),
      schedules: data.schedules
          ?.where((item) => selection.scheduleIds.contains(item.id))
          .toList(),
      todoLists: data.todoLists
          ?.where((item) => selection.todoListIds.contains(item.id))
          .toList(),
    );
  }

  static Map<String, dynamic> _settingsToJson(
    AppSettings settings,
    Set<BackupSettingsPart> parts,
  ) {
    final json = <String, dynamic>{};
    if (parts.contains(BackupSettingsPart.appearance)) {
      json.addAll({
        'themeColor': settings.themeColor.toARGB32(),
        'baseThemeColor': settings.baseThemeColor.toARGB32(),
        'backgroundImagePath': settings.backgroundImagePath,
        'blurEnabled': settings.blurEnabled,
        'blurAmount': settings.blurAmount,
        'themeMode': settings.themeMode,
      });
    }
    if (parts.contains(BackupSettingsPart.conversationSettings)) {
      json.addAll({
        if (settings.speechModelId != null)
          'speechModelId': settings.speechModelId,
        if (settings.imageModelId != null)
          'imageModelId': settings.imageModelId,
        'imageOcrEnabled': settings.imageOcrEnabled,
        if (settings.imageRecognitionModelId != null)
          'imageRecognitionModelId': settings.imageRecognitionModelId,
        'imageRecognitionEnabled': settings.imageRecognitionEnabled,
        if (settings.lastChatModelId != null)
          'lastChatModelId': settings.lastChatModelId,
        'imageRecognitionPrompt': settings.imageRecognitionPrompt,
        'systemPrompt': settings.systemPrompt,
        if (settings.selectedSystemPromptId != null)
          'selectedSystemPromptId': settings.selectedSystemPromptId,
        'lastFeature': settings.lastFeature,
      });
    }
    if (parts.contains(BackupSettingsPart.rolesAndPrompts)) {
      json.addAll({
        'roles': settings.roles.map((item) => item.toJson()).toList(),
        'currentRoleId': settings.currentRoleId,
        'systemPrompts': settings.systemPrompts
            .map((item) => item.toJson())
            .toList(),
        if (settings.selectedSystemPromptId != null)
          'selectedSystemPromptId': settings.selectedSystemPromptId,
      });
    }
    return json;
  }

  static T? _findById<T>(Iterable<T> items, String id) {
    for (final item in items) {
      final itemId = (item as dynamic).id as String;
      if (itemId == id) return item;
    }
    return null;
  }

  static bool _sameJson(dynamic a, dynamic b) {
    return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
  }

  static String _conflictId(BackupSection section, String id) =>
      '${section.key}:$id';

  static String _sectionDetail(BackupSection section, BackupData data) {
    switch (section) {
      case BackupSection.settings:
        return '${data.modelConfigs?.length ?? 0} 个模型配置';
      case BackupSection.conversations:
        return '${data.conversations?.length ?? 0} 条对话';
      case BackupSection.notes:
        return '${data.notes?.length ?? 0} 篇笔记，${data.noteFolders?.length ?? 0} 个文件夹';
      case BackupSection.schedules:
        return '${data.schedules?.length ?? 0} 条日程';
      case BackupSection.todoLists:
        return '${data.todoLists?.length ?? 0} 个清单';
    }
  }

  static String _formatFileDate(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}-${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }

  static String _formatUpdated(DateTime value) => '更新时间 ${_formatTime(value)}';

  static String _formatRange(DateTime start, DateTime end) {
    return '${_formatTime(start)} - ${_formatTime(end)}';
  }

  static String _formatTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }

  static String _formatModel(ModelConfig model) {
    return '${model.name} / ${model.apiType} / ${model.modelName}';
  }

  static T? _parseOne<T>(
    Object? value,
    T Function(Map<String, dynamic>) parser,
    List<String> warnings,
    String label,
  ) {
    if (value == null) return null;
    try {
      return parser(Map<String, dynamic>.from(value as Map));
    } catch (e) {
      warnings.add('$label 解析失败：$e');
      return null;
    }
  }

  static Object? _nonEmptyMap(Object? value) {
    if (value is Map && value.isEmpty) return null;
    return value;
  }

  static List<T>? _parseList<T>(
    Object? value,
    T Function(Map<String, dynamic>) parser,
    List<String> warnings,
    String label,
  ) {
    if (value == null) return null;
    if (value is! List) {
      warnings.add('$label 格式不是列表');
      return const [];
    }
    final items = <T>[];
    for (final item in value) {
      try {
        items.add(parser(Map<String, dynamic>.from(item as Map)));
      } catch (e) {
        warnings.add('跳过损坏的$label：$e');
      }
    }
    return items;
  }
}

class _ImportIdMap {
  final modelIds = <String, String>{};
  final roleIds = <String, String>{};
  final systemPromptIds = <String, String>{};
  final noteFolderIds = <String, String>{};
  final noteIds = <String, String>{};
  final noteRevisionIds = <String, String>{};
}
