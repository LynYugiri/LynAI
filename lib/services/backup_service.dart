import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/app_settings.dart';
import '../models/agent_trace.dart';
import '../models/backup_models.dart';
import '../models/chat_role.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/model_config.dart';
import '../models/note.dart';
import '../models/plugin.dart';
import '../models/roleplay.dart';
import '../models/schedule_item.dart';
import '../models/todo_list.dart';
import '../providers/conversation_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/roleplay_provider.dart';
import '../providers/settings_provider.dart';
import '../repositories/plugin_repository.dart';
import 'storage_v2_service.dart';
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
    required this.roleplayProvider,
    this.pluginProvider,
    PluginRepository? pluginRepository,
    this.storageV2,
    Future<String> Function()? appVersionLoader,
  }) : _pluginRepository = pluginRepository ?? PluginRepository(),
       _appVersionLoader = appVersionLoader;

  final SettingsProvider settingsProvider;
  final ModelConfigProvider modelConfigProvider;
  final ConversationProvider conversationProvider;
  final FeatureProvider featureProvider;
  final RoleplayProvider roleplayProvider;
  final PluginProvider? pluginProvider;
  final StorageV2Service? storageV2;
  final PluginRepository _pluginRepository;
  final Future<String> Function()? _appVersionLoader;
  final _uuid = const Uuid();

  static const currentSchemaVersion = 4;
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

  Future<Uint8List> exportZipBytes(BackupSelection selection) async {
    final appVersion = _appVersionLoader == null
        ? (await PackageInfo.fromPlatform()).version
        : await _appVersionLoader();
    final createdAt = DateTime.now();
    final archive = Archive();
    final sections = <String, dynamic>{};
    final assetRecords = <Map<String, dynamic>>[];
    final archivedAssetPaths = <String, String>{};
    List<Directory>? privateRoots;

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
      privateRoots ??= await _privateStorageRoots();
      if (!_isInPrivateStorage(file, privateRoots!)) return;
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
      final settingsJson = _settingsToJson(settings, selection.settingsParts);
      if (settingsProvider.usingStorageV2 && storageV2 != null) {
        try {
          final current = await storageV2!.loadDataFile('app_settings.json');
          final storageSub = current['storageV2'];
          if (storageSub is Map && storageSub.isNotEmpty) {
            settingsJson['storageV2'] = Map<String, dynamic>.from(storageSub);
          }
        } catch (_) {}
      }
      addJson('settings.json', {'appSettings': settingsJson});
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
      final usingV2 = conversationProvider.usingStorageV2;
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
      if (usingV2) {
        final convRows = <Map<String, dynamic>>[];
        final msgRows = <Map<String, dynamic>>[];
        final attRows = <Map<String, dynamic>>[];
        for (final conversation in conversations) {
          convRows.add({
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
            msgRows.add({
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
              final image = message.images[j];
              attRows.add({
                'id': '${message.id}_attachment_$j',
                'messageId': message.id,
                'displayName': image.name,
                'name': image.name,
                'mimeType': image.mimeType,
                'size': image.size,
                'path': image.path,
                'legacyPath': image.path,
                'sortOrder': j,
              });
            }
          }
        }
        addJson('conversations.json', {
          'conversations': convRows,
          'messages': msgRows,
          'messageAttachments': attRows,
        });
      } else {
        addJson('conversations.json', {
          'conversations': conversations.map((item) => item.toJson()).toList(),
        });
      }
      sections[BackupSection.conversations.key] = {
        'enabled': true,
        'files': ['conversations.json'],
        if (usingV2) 'format': 'storage_v2',
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
      final proposals = featureProvider.noteEditProposals
          .where((item) => noteIds.contains(item.noteId))
          .toList();
      addJson('notes/folders.json', {
        'folders': folders.map((item) => item.toJson()).toList(),
      });
      final exportedNotes = <Map<String, dynamic>>[];
      for (final note in notes) {
        exportedNotes.add(note.toJson());
      }
      addJson('notes/notes.json', {'notes': exportedNotes});
      final noteFiles = [
        'notes/folders.json',
        'notes/notes.json',
        'notes/revisions.json',
      ];
      var pageCount = 0;
      if (featureProvider.usingStorageV2) {
        final pages = <Map<String, dynamic>>[];
        for (final note in notes) {
          for (final page in featureProvider.notePages(note.id)) {
            final contentPath = _notePageContentPath(page.id);
            final bytes = utf8.encode(
              await featureProvider.readNotePageContent(page),
            );
            archive.addFile(ArchiveFile(contentPath, bytes.length, bytes));
            pages.add({...page.toJson(), 'contentPath': contentPath});
            pageCount++;
          }
        }
        addJson('notes/pages.json', {'pages': pages});
        final proposalRows = <Map<String, dynamic>>[];
        final blockRows = <Map<String, dynamic>>[];
        for (final proposal in proposals) {
          proposalRows.add({
            'id': proposal.id,
            'noteId': proposal.noteId,
            if (proposal.pageId != null) 'pageId': proposal.pageId,
            if (proposal.baseRevisionId != null)
              'baseRevisionId': proposal.baseRevisionId,
            'baseContentHash': proposal.baseContentHash,
            'createdAt': proposal.createdAt.toIso8601String(),
          });
          for (var i = 0; i < proposal.blocks.length; i++) {
            final block = proposal.blocks[i];
            blockRows.add({
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
        addJson('notes/edit_proposals.json', {'proposals': proposalRows});
        addJson('notes/edit_blocks.json', {'blocks': blockRows});
        noteFiles.addAll([
          'notes/pages.json',
          'notes/edit_proposals.json',
          'notes/edit_blocks.json',
        ]);
      }
      if (featureProvider.usingStorageV2) {
        final flatRevisions = revisions.map((revision) {
          return {
            'id': revision.id,
            'noteId': revision.noteId,
            if (revision.pageId != null) 'pageId': revision.pageId,
            if (revision.parentRevisionId != null)
              'parentRevisionId': revision.parentRevisionId,
            'savedAt': revision.savedAt.toIso8601String(),
            'deltaStart': revision.delta.start,
            'deletedText': revision.delta.deletedText,
            'insertedText': revision.delta.insertedText,
          };
        }).toList();
        addJson('notes/revisions.json', {'revisions': flatRevisions});
      } else {
        addJson('notes/revisions.json', {
          'revisions': revisions.map((item) => item.toJson()).toList(),
        });
      }
      sections[BackupSection.notes.key] = {
        'enabled': true,
        'files': noteFiles,
        if (featureProvider.usingStorageV2) 'storage': 'storage_v2',
        'folderCount': folders.length,
        'noteCount': notes.length,
        if (featureProvider.usingStorageV2) 'pageCount': pageCount,
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
      final usingV2 = featureProvider.usingStorageV2;
      if (usingV2) {
        final listRows = <Map<String, dynamic>>[];
        final itemRows = <Map<String, dynamic>>[];
        for (final list in todoLists) {
          listRows.add({
            'id': list.id,
            'title': list.title,
            'createdAt': list.createdAt.toIso8601String(),
            'updatedAt': list.updatedAt.toIso8601String(),
          });
          for (var i = 0; i < list.items.length; i++) {
            final item = list.items[i];
            itemRows.add({
              'id': item.id,
              'listId': list.id,
              'text': item.text,
              'done': item.done,
              'sortOrder': i,
            });
          }
        }
        addJson('todo_lists.json', {
          'todoLists': listRows,
          'todoItems': itemRows,
        });
      } else {
        addJson('todo_lists.json', {
          'todoLists': todoLists.map((item) => item.toJson()).toList(),
        });
      }
      sections[BackupSection.todoLists.key] = {
        'enabled': true,
        'files': ['todo_lists.json'],
        if (usingV2) 'format': 'storage_v2',
        'count': todoLists.length,
      };
    }
    if (selection.contains(BackupSection.roleplay)) {
      final scenarios = roleplayProvider.scenarios
          .where((item) => selection.roleplaySessionIds.contains(item.id))
          .toList();
      final scenarioIds = scenarios.map((item) => item.id).toSet();
      final threads = roleplayProvider.threads
          .where((item) => scenarioIds.contains(item.scenarioId))
          .toList();
      addJson('roleplay_scenarios.json', {
        'scenarios': scenarios.map((item) => item.toJson()).toList(),
      });
      addJson('roleplay_threads.json', {
        'threads': threads.map((item) => item.toJson()).toList(),
      });
      sections[BackupSection.roleplay.key] = {
        'enabled': true,
        'files': ['roleplay_scenarios.json', 'roleplay_threads.json'],
        'count': scenarios.length,
      };
    }
    if (selection.contains(BackupSection.plugins) && pluginProvider != null) {
      final plugins = pluginProvider!.plugins
          .where((item) => selection.pluginIds.contains(item.id))
          .toList();
      final pluginData = <BackupPluginData>[];
      for (final plugin in plugins) {
        final pluginSegment = safeStorageSegment(plugin.id, fallback: 'plugin');
        final files = <BackupPluginFile>[];
        final root = Directory(plugin.path);
        if (await root.exists()) {
          await for (final entity in root.list(
            recursive: true,
            followLinks: false,
          )) {
            if (entity is! File) continue;
            final relativePath = _relativePath(root.path, entity.path);
            if (relativePath.isEmpty ||
                !_isSafePluginRelativePath(relativePath)) {
              continue;
            }
            final archivePath =
                'plugins/installed/$pluginSegment/$relativePath';
            final bytes = await entity.readAsBytes();
            archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
            files.add(
              BackupPluginFile(path: relativePath, archivePath: archivePath),
            );
          }
        }
        pluginData.add(
          BackupPluginData(
            plugin: plugin.copyWith(path: ''),
            settings: await pluginProvider!.loadSettings(plugin.id),
            storage: await pluginProvider!.loadStorage(plugin.id),
            files: files,
          ),
        );
      }
      addJson('plugins/installed_plugins.json', {
        'plugins': pluginData.map((item) => item.toJson()).toList(),
      });
      sections[BackupSection.plugins.key] = {
        'enabled': true,
        'files': ['plugins/installed_plugins.json'],
        'count': pluginData.length,
      };
    }

    final exportedResources = await _collectExportResources(
      selection,
      archivedAssetPaths,
      assetRecords,
    );
    if (exportedResources.isNotEmpty) {
      addJson('resources.json', {'resources': exportedResources});
    }

    addJson('manifest.json', {
      'type': _backupType,
      'schemaVersion': currentSchemaVersion,
      'appVersion': appVersion,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'format': 'zip',
      'sections': sections,
      if (assetRecords.isNotEmpty) 'assets': assetRecords,
      if (exportedResources.isNotEmpty) 'resourcesFile': 'resources.json',
    });

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<BackupArchiveData> readZipBytes(List<int> bytes) async {
    final decoded = ZipDecoder().decodeBytes(bytes);
    final files = <String, ArchiveFile>{};
    final assetFiles = <String, List<int>>{};
    final pluginFiles = <String, List<int>>{};
    for (final entry in decoded.files) {
      _validateArchiveEntryPath(entry.name);
      if (entry.name.endsWith('/')) continue;
      if (files.containsKey(entry.name)) {
        throw FormatException('备份包包含重复文件：${entry.name}');
      }
      files[entry.name] = entry;
      final content = entry.content;
      if (entry.name.startsWith('assets/')) {
        assetFiles[entry.name] = List<int>.from(content);
      }
      if (entry.name.startsWith('plugins/installed/')) {
        pluginFiles[entry.name] = List<int>.from(content);
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
    final schemaVersion = (manifest['schemaVersion'] as num?)?.toInt() ?? 1;
    if (schemaVersion > currentSchemaVersion) {
      throw const FormatException('备份版本过高，当前应用无法导入');
    }

    final settingsJson = readMap('settings.json');
    final modelsJson = readMap('model_configs.json');
    final conversationsJson = readMap('conversations.json');
    final foldersJson = readMap('notes/folders.json');
    final notesJson = readMap('notes/notes.json');
    final pagesJson = readMap('notes/pages.json');
    final revisionsJson = readMap('notes/revisions.json');
    final proposalsJson = readMap('notes/edit_proposals.json');
    final blocksJson = readMap('notes/edit_blocks.json');
    final schedulesJson = readMap('schedules.json');
    final todoListsJson = readMap('todo_lists.json');
    final roleplayJson = readMap('roleplay_scenarios.json');
    final roleplayThreadsJson = readMap('roleplay_threads.json');
    final pluginsJson = readMap('plugins/installed_plugins.json');
    final resourcesJson = readMap('resources.json');

    final conversations = _parseConversations(
      conversationsJson,
      schemaVersion,
      warnings,
    );
    final todoLists = _parseTodoLists(todoListsJson, schemaVersion, warnings);
    final noteEditProposals = _parseNoteEditProposals(
      proposalsJson,
      blocksJson,
      schemaVersion,
      warnings,
    );
    final notePages = _parseRawMapList(pagesJson?['pages'], warnings, '笔记分页');
    final pageContents = <String, String>{};
    for (final page in notePages ?? const <Map<String, dynamic>>[]) {
      final id = page['id'] as String?;
      final path = page['contentPath'] as String?;
      if (path != null && !_isSafeArchivePath(path)) {
        warnings.add('笔记分页正文路径不安全：$path');
        continue;
      }
      final entry = path == null ? null : files[path];
      if (id == null || id.isEmpty || path == null) continue;
      if (entry == null) {
        warnings.add('笔记分页正文缺失：$path');
        continue;
      }
      try {
        pageContents[id] = utf8.decode(entry.content as List<int>);
      } catch (e) {
        warnings.add('笔记分页正文解析失败：$path，$e');
      }
    }

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
        conversations: conversations,
        noteFolders: _parseList(
          foldersJson?['folders'],
          NoteFolder.fromJson,
          warnings,
          '笔记文件夹',
        ),
        notes: _parseList(notesJson?['notes'], Note.fromJson, warnings, '笔记'),
        notePages: notePages,
        notePageContents: pageContents.isEmpty ? null : pageContents,
        noteRevisions: _parseList(
          revisionsJson?['revisions'],
          NoteRevision.fromJson,
          warnings,
          '笔记修订',
        ),
        noteEditProposals: noteEditProposals,
        schedules: _parseList(
          schedulesJson?['schedules'],
          ScheduleItem.fromJson,
          warnings,
          '日程',
        ),
        todoLists: todoLists,
        roleplaySessions: _parseList(
          roleplayJson?['scenarios'],
          RoleplayScenario.fromJson,
          warnings,
          '情景演绎',
        ),
        roleplayThreads: _parseList(
          roleplayThreadsJson?['threads'],
          RoleplayThread.fromJson,
          warnings,
          '演绎对话',
        ),
        plugins: _parseList(
          pluginsJson?['plugins'],
          BackupPluginData.fromJson,
          warnings,
          '插件',
        ),
      ),
      assetFiles: assetFiles,
      pluginFiles: pluginFiles,
      resources: _parseRawMapList(resourcesJson?['resources'], warnings, '资源'),
    );
  }

  static List<Conversation>? _parseConversations(
    Map<String, dynamic>? json,
    int schemaVersion,
    List<String> warnings,
  ) {
    if (json == null) return null;
    if (json['messages'] is List && json['conversations'] is List) {
      return _parseConversationsFlat(json, warnings);
    }
    return _parseList(
      json['conversations'],
      Conversation.fromJson,
      warnings,
      '对话记录',
    );
  }

  static List<Conversation>? _parseConversationsFlat(
    Map<String, dynamic> json,
    List<String> warnings,
  ) {
    final attachmentsByMessageId = <String, List<MessageImage>>{};
    for (final item
        in json['messageAttachments'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      try {
        final raw = Map<String, dynamic>.from(item);
        final messageId = raw['messageId'] as String?;
        if (messageId == null) continue;
        (attachmentsByMessageId[messageId] ??= []).add(
          MessageImage(
            path: raw['path'] as String? ?? raw['legacyPath'] as String? ?? '',
            name:
                raw['displayName'] as String? ??
                raw['name'] as String? ??
                'file',
            size: raw['size'] as int? ?? 0,
            mimeType: raw['mimeType'] as String? ?? 'application/octet-stream',
          ),
        );
      } catch (e) {
        warnings.add('跳过损坏的附件记录: $e');
      }
    }

    final messagesByConvId = <String, List<_FlatMessageRow>>{};
    for (final item in json['messages'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      try {
        final raw = Map<String, dynamic>.from(item);
        final convId = raw['conversationId'] as String?;
        if (convId == null) continue;
        final msgId = raw['id'] as String;
        final timestamp = DateTime.tryParse(raw['timestamp'] as String? ?? '');
        if (timestamp == null) throw const FormatException('Invalid timestamp');
        (messagesByConvId[convId] ??= []).add(
          _FlatMessageRow(
            message: Message(
              id: msgId,
              role: raw['role'] as String,
              content: raw['content'] as String? ?? '',
              images: attachmentsByMessageId[msgId] ?? const [],
              thinkingContent: raw['thinkingContent'] as String?,
              agentTrace: raw['agentTrace'] is Map
                  ? AgentTrace.fromJson(
                      Map<String, dynamic>.from(raw['agentTrace'] as Map),
                    )
                  : null,
              timestamp: timestamp,
            ),
            sortOrder: (raw['sortOrder'] as num?)?.toInt(),
          ),
        );
      } catch (e) {
        warnings.add('跳过损坏的扁平消息记录: $e');
      }
    }

    final conversations = <Conversation>[];
    for (final item in json['conversations'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      try {
        final raw = Map<String, dynamic>.from(item);
        final id = raw['id'] as String;
        final rows = List<_FlatMessageRow>.from(
          messagesByConvId[id] ?? const [],
        );
        rows.sort((a, b) {
          final oa = a.sortOrder;
          final ob = b.sortOrder;
          if (oa != null && ob != null) return oa.compareTo(ob);
          if (oa != null) return -1;
          if (ob != null) return 1;
          return a.message.timestamp.compareTo(b.message.timestamp);
        });
        conversations.add(
          Conversation(
            id: id,
            title: raw['title'] as String? ?? '',
            messages: rows.map((r) => r.message).toList(),
            modelId: raw['modelId'] as String? ?? '',
            settings: raw['settings'] is Map
                ? ConversationSettings.fromJson(
                    Map<String, dynamic>.from(raw['settings'] as Map),
                    fallbackModelId: raw['modelId'] as String? ?? '',
                  )
                : null,
            roleId: raw['roleId'] as String? ?? 'default',
            createdAt: DateTime.parse(raw['createdAt'] as String),
            updatedAt: DateTime.parse(raw['updatedAt'] as String),
          ),
        );
      } catch (e) {
        warnings.add('跳过损坏的扁平对话记录: $e');
      }
    }
    return conversations;
  }

  static List<TodoList>? _parseTodoLists(
    Map<String, dynamic>? json,
    int schemaVersion,
    List<String> warnings,
  ) {
    if (json == null) return null;
    if (json['todoItems'] is List && json['todoLists'] is List) {
      return _parseTodoListsFlat(json, warnings);
    }
    return _parseList(json['todoLists'], TodoList.fromJson, warnings, '待办清单');
  }

  static List<TodoList>? _parseTodoListsFlat(
    Map<String, dynamic> json,
    List<String> warnings,
  ) {
    final itemsByListId = <String, List<TodoItem>>{};
    for (final item in json['todoItems'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      try {
        final raw = Map<String, dynamic>.from(item);
        final listId = raw['listId'] as String;
        (itemsByListId[listId] ??= []).add(
          TodoItem(
            id: raw['id'] as String,
            text: raw['text'] as String? ?? '',
            done: raw['done'] as bool? ?? false,
          ),
        );
      } catch (e) {
        warnings.add('跳过损坏的扁平待办项: $e');
      }
    }
    final lists = <TodoList>[];
    for (final item in json['todoLists'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      try {
        final raw = Map<String, dynamic>.from(item);
        final id = raw['id'] as String;
        lists.add(
          TodoList(
            id: id,
            title: raw['title'] as String? ?? '',
            items: List<TodoItem>.from(itemsByListId[id] ?? const []),
            createdAt: DateTime.parse(raw['createdAt'] as String),
            updatedAt: DateTime.parse(raw['updatedAt'] as String),
          ),
        );
      } catch (e) {
        warnings.add('跳过损坏的扁平待办清单: $e');
      }
    }
    return lists;
  }

  static List<NoteEditProposal>? _parseNoteEditProposals(
    Map<String, dynamic>? proposalsJson,
    Map<String, dynamic>? blocksJson,
    int schemaVersion,
    List<String> warnings,
  ) {
    if (proposalsJson == null) return null;
    if (blocksJson?['blocks'] is List) {
      return _parseNoteEditProposalsFlat(proposalsJson, blocksJson!, warnings);
    }
    return _parseList(
      proposalsJson['proposals'],
      NoteEditProposal.fromJson,
      warnings,
      '笔记修改建议',
    );
  }

  static List<NoteEditProposal>? _parseNoteEditProposalsFlat(
    Map<String, dynamic> proposalsJson,
    Map<String, dynamic> blocksJson,
    List<String> warnings,
  ) {
    final blocksByProposal = <String, List<NoteEditBlock>>{};
    for (final item in blocksJson['blocks'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      try {
        final raw = Map<String, dynamic>.from(item);
        final proposalId = raw['proposalId'] as String;
        (blocksByProposal[proposalId] ??= []).add(
          NoteEditBlock(
            id: raw['id'] as String,
            startLine: raw['startLine'] as int? ?? 1,
            deleteCount: raw['deleteCount'] as int? ?? 0,
            deletedLines: (raw['deletedLines'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toList(),
            insertLines: (raw['insertLines'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toList(),
          ),
        );
      } catch (e) {
        warnings.add('跳过损坏的扁平编辑块: $e');
      }
    }
    final proposals = <NoteEditProposal>[];
    for (final item
        in proposalsJson['proposals'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      try {
        final raw = Map<String, dynamic>.from(item);
        proposals.add(
          NoteEditProposal(
            id: raw['id'] as String,
            noteId: raw['noteId'] as String,
            pageId: raw['pageId'] as String?,
            baseRevisionId: raw['baseRevisionId'] as String?,
            baseContentHash: raw['baseContentHash'] as String? ?? '',
            createdAt: DateTime.parse(raw['createdAt'] as String),
            blocks: blocksByProposal[raw['id'] as String] ?? const [],
          ),
        );
      } catch (e) {
        warnings.add('跳过损坏的扁平编辑建议: $e');
      }
    }
    return proposals;
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
    await _mergeBackupResources(archive, restoredAssetPaths);
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
      if (plan.sections.contains(BackupSection.roleplay)) {
        final result = await _applyRoleplay(data, plan, idMap);
        added += result.added;
        replaced += result.replaced;
        skipped += result.skipped;
      }
      if (plan.sections.contains(BackupSection.plugins)) {
        final result = await _applyPlugins(data, plan, archive.pluginFiles);
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
          items.add(_copyConversationWithNewIds(incoming));
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
    if (featureProvider.usingStorageV2 && data.notePages != null) {
      return _applyStorageV2Notes(data, plan, idMap);
    }
    if (data.notePages != null || data.noteEditProposals != null) {
      throw StateError('备份包含新版分页和修改建议，但当前存储模式不支持导入。请先执行存储迁移。');
    }
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

  Future<ImportResult> _applyStorageV2Notes(
    BackupData data,
    ImportPlan plan,
    _ImportIdMap idMap,
  ) async {
    final incomingFolders = data.noteFolders ?? const <NoteFolder>[];
    final incomingNotes = data.notes ?? const <Note>[];
    final incomingRevisions = data.noteRevisions ?? const <NoteRevision>[];
    final incomingProposals =
        data.noteEditProposals ?? const <NoteEditProposal>[];
    final incomingPages = (data.notePages ?? const <Map<String, dynamic>>[])
        .map(StorageV2NotePage.fromJson)
        .toList();
    final incomingPageContents =
        data.notePageContents ?? const <String, String>{};
    var added = 0;
    var replaced = 0;
    var skipped = 0;
    final replacingSection = plan.mode == ImportMode.replaceSection;
    final folders = List<NoteFolder>.from(featureProvider.noteFolders);
    final notes = List<Note>.from(featureProvider.notes);
    final revisions = List<NoteRevision>.from(featureProvider.noteRevisions);
    final proposals = List<NoteEditProposal>.from(
      featureProvider.noteEditProposals,
    );
    final pages = <StorageV2NotePage>[];
    final pageContents = <String, String>{};
    final acceptedOriginalNoteIds = <String>{};
    final usedRelativePaths = <String>{};

    for (final note in featureProvider.notes) {
      for (final page in featureProvider.notePages(note.id)) {
        pages.add(page);
        usedRelativePaths.add(page.relativePath);
        pageContents[page.id] = await featureProvider.readNotePageContent(page);
      }
    }

    if (replacingSection) {
      final incomingFolderIds = incomingFolders.map((item) => item.id).toSet();
      final incomingNoteIds = incomingNotes.map((item) => item.id).toSet();
      final incomingRevisionIds = incomingRevisions
          .map((item) => item.id)
          .toSet();
      final incomingProposalIds = incomingProposals
          .map((item) => item.id)
          .toSet();
      folders.removeWhere((item) => incomingFolderIds.contains(item.id));
      notes.removeWhere((item) => incomingNoteIds.contains(item.id));
      revisions.removeWhere(
        (item) =>
            incomingNoteIds.contains(item.noteId) ||
            incomingRevisionIds.contains(item.id),
      );
      proposals.removeWhere((item) => incomingProposalIds.contains(item.id));
      final removedPages = pages
          .where((item) => incomingNoteIds.contains(item.noteId))
          .toList();
      for (final page in removedPages) {
        usedRelativePaths.remove(page.relativePath);
        pageContents.remove(page.id);
      }
      pages.removeWhere((item) => incomingNoteIds.contains(item.noteId));
    }

    for (final incoming in incomingFolders) {
      final index = folders.indexWhere((item) => item.id == incoming.id);
      if (index == -1) {
        folders.add(incoming);
        idMap.noteFolderIds[incoming.id] = incoming.id;
      } else if (plan.mode != ImportMode.addOnly) {
        final action = plan.actionFor(
          _conflictId(BackupSection.notes, 'folder:${incoming.id}'),
        );
        if (action == ImportConflictAction.keepBoth) {
          final nextId = _uuid.v4();
          idMap.noteFolderIds[incoming.id] = nextId;
          folders.add(incoming.copyWith(id: nextId));
        } else if (action == ImportConflictAction.replaceLocal ||
            replacingSection) {
          folders[index] = incoming;
          idMap.noteFolderIds[incoming.id] = incoming.id;
        }
      }
    }

    for (final incoming in incomingNotes) {
      final index = notes.indexWhere((item) => item.id == incoming.id);
      if (index == -1) {
        idMap.noteIds[incoming.id] = incoming.id;
        notes.add(_remapNote(incoming, idMap));
        acceptedOriginalNoteIds.add(incoming.id);
        added++;
      } else if (!replacingSection && _sameJson(notes[index], incoming)) {
        skipped++;
      } else if (plan.mode == ImportMode.addOnly) {
        skipped++;
      } else {
        final action = replacingSection
            ? ImportConflictAction.replaceLocal
            : plan.actionFor(
                _conflictId(BackupSection.notes, 'note:${incoming.id}'),
              );
        if (action == ImportConflictAction.replaceLocal) {
          idMap.noteIds[incoming.id] = incoming.id;
          notes[index] = _remapNote(incoming, idMap);
          acceptedOriginalNoteIds.add(incoming.id);
          replaced++;
        } else if (action == ImportConflictAction.keepBoth) {
          idMap.noteIds[incoming.id] = _uuid.v4();
          notes.add(_remapNote(incoming, idMap));
          acceptedOriginalNoteIds.add(incoming.id);
          added++;
        } else {
          skipped++;
        }
      }
    }

    for (final revision in incomingRevisions.where(
      (item) => acceptedOriginalNoteIds.contains(item.noteId),
    )) {
      idMap.noteRevisionIds.putIfAbsent(revision.id, () {
        final remappedNoteId = idMap.noteIds[revision.noteId];
        return remappedNoteId == revision.noteId ? revision.id : _uuid.v4();
      });
    }
    for (final page in incomingPages.where(
      (item) => acceptedOriginalNoteIds.contains(item.noteId),
    )) {
      idMap.notePageIds.putIfAbsent(page.id, () {
        final remappedNoteId = idMap.noteIds[page.noteId];
        return remappedNoteId == page.noteId ? page.id : _uuid.v4();
      });
    }

    for (final incoming in incomingNotes.where(
      (item) => acceptedOriginalNoteIds.contains(item.id),
    )) {
      final remapped = _remapNote(incoming, idMap);
      final index = notes.indexWhere((item) => item.id == remapped.id);
      if (index != -1) notes[index] = remapped;
    }

    final acceptedNoteIds = acceptedOriginalNoteIds
        .map((id) => idMap.noteIds[id])
        .whereType<String>()
        .toSet();
    final removedPages = pages
        .where((item) => acceptedNoteIds.contains(item.noteId))
        .toList();
    for (final page in removedPages) {
      usedRelativePaths.remove(page.relativePath);
    }
    revisions.removeWhere((item) => acceptedNoteIds.contains(item.noteId));
    revisions.addAll(
      incomingRevisions
          .where((item) => acceptedOriginalNoteIds.contains(item.noteId))
          .map((item) => _remapStorageV2Revision(item, idMap)),
    );
    proposals.removeWhere((item) => acceptedNoteIds.contains(item.noteId));
    proposals.addAll(
      incomingProposals
          .where((item) => acceptedOriginalNoteIds.contains(item.noteId))
          .map((item) => _remapStorageV2Proposal(item, idMap)),
    );
    pages.removeWhere((item) => acceptedNoteIds.contains(item.noteId));
    pageContents.removeWhere(
      (pageId, _) => pages.every((page) => page.id != pageId),
    );
    for (final page in incomingPages.where(
      (item) => acceptedOriginalNoteIds.contains(item.noteId),
    )) {
      final content = incomingPageContents[page.id];
      if (content == null) {
        throw FormatException('笔记分页正文缺失：${page.title} (${page.id})');
      }
      final nextPage = _remapStorageV2Page(page, idMap, usedRelativePaths);
      pages.add(nextPage);
      pageContents[nextPage.id] = content;
    }

    await featureProvider.replaceStorageV2NotesData(
      noteFolders: folders,
      notes: notes,
      pages: pages,
      pageContents: pageContents,
      noteRevisions: revisions,
      noteEditProposals: proposals,
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
          items.add(_copyTodoListWithNewIds(incoming));
          added++;
        } else {
          skipped++;
        }
      }
    }
    await featureProvider.replaceFeatureData(todoLists: items);
    return ImportResult(added: added, replaced: replaced, skipped: skipped);
  }

  Future<ImportResult> _applyRoleplay(
    BackupData data,
    ImportPlan plan,
    _ImportIdMap idMap,
  ) async {
    final incomingScenarios = data.roleplaySessions;
    final incomingThreads = data.roleplayThreads;
    if (incomingScenarios == null && incomingThreads == null) {
      return const ImportResult(added: 0, replaced: 0, skipped: 0);
    }
    final scenarios = incomingScenarios ?? const <RoleplayScenario>[];
    final threads = incomingThreads ?? const <RoleplayThread>[];
    if (plan.mode == ImportMode.replaceSection) {
      final incomingIds = scenarios.map((item) => item.id).toSet();
      final nextScenarios = roleplayProvider.scenarios
          .where((item) => !incomingIds.contains(item.id))
          .toList();
      final nextThreads = roleplayProvider.threads
          .where((item) => !incomingIds.contains(item.scenarioId))
          .toList();
      nextScenarios.addAll(
        scenarios.map((item) => _remapRoleplayScenario(item, idMap)),
      );
      nextThreads.addAll(
        threads.map((item) => _remapRoleplayThread(item, idMap)),
      );
      await roleplayProvider.replaceData(
        scenarios: nextScenarios,
        threads: nextThreads,
      );
      return ImportResult(added: 0, replaced: scenarios.length, skipped: 0);
    }
    var added = 0;
    var replaced = 0;
    var skipped = 0;
    final nextScenarios = List<RoleplayScenario>.from(
      roleplayProvider.scenarios,
    );
    final nextThreads = List<RoleplayThread>.from(roleplayProvider.threads);
    for (final incoming in scenarios) {
      final index = nextScenarios.indexWhere((item) => item.id == incoming.id);
      if (index == -1) {
        nextScenarios.add(_remapRoleplayScenario(incoming, idMap));
        added++;
      } else if (_sameJson(nextScenarios[index], incoming)) {
        skipped++;
      } else if (plan.mode == ImportMode.addOnly) {
        skipped++;
      } else {
        final action = plan.actionFor(
          _conflictId(BackupSection.roleplay, incoming.id),
        );
        if (action == ImportConflictAction.replaceLocal) {
          nextScenarios[index] = _remapRoleplayScenario(incoming, idMap);
          replaced++;
        } else if (action == ImportConflictAction.keepBoth) {
          nextScenarios.add(_copyRoleplayScenarioWithNewIds(incoming));
          added++;
        } else {
          skipped++;
        }
      }
    }
    for (final incoming in threads) {
      if (!nextThreads.any((item) => item.id == incoming.id)) {
        nextThreads.add(_remapRoleplayThread(incoming, idMap));
      }
    }
    await roleplayProvider.replaceData(
      scenarios: nextScenarios,
      threads: nextThreads,
    );
    return ImportResult(added: added, replaced: replaced, skipped: skipped);
  }

  Future<ImportResult> _applyPlugins(
    BackupData data,
    ImportPlan plan,
    Map<String, List<int>> pluginFiles,
  ) async {
    final incomingItems = data.plugins;
    if (incomingItems == null) {
      return const ImportResult(added: 0, replaced: 0, skipped: 0);
    }
    final currentPlugins =
        pluginProvider?.plugins ??
        await _pluginRepository.loadInstalledPlugins();
    final nextPlugins = List<InstalledPlugin>.from(currentPlugins);
    var added = 0;
    var replaced = 0;
    var skipped = 0;

    for (final incoming in incomingItems) {
      final pluginId = incoming.plugin.id;
      if (pluginId.isEmpty) {
        skipped++;
        continue;
      }
      final index = nextPlugins.indexWhere((item) => item.id == pluginId);
      final exists = index != -1;
      if (exists && plan.mode == ImportMode.addOnly) {
        skipped++;
        continue;
      }
      if (exists && plan.mode == ImportMode.merge) {
        final action = plan.actionFor(
          _conflictId(BackupSection.plugins, pluginId),
        );
        if (action != ImportConflictAction.replaceLocal) {
          skipped++;
          continue;
        }
      }
      final restoredFiles = <String, List<int>>{};
      var missingFile = false;
      for (final file in incoming.files) {
        if (!_isSafePluginRelativePath(file.path) ||
            !_isSafeArchivePath(file.archivePath)) {
          throw FormatException('插件备份文件路径不安全：${file.path}');
        }
        final bytes = pluginFiles[file.archivePath];
        if (bytes == null) {
          missingFile = true;
          break;
        }
        restoredFiles[file.path] = bytes;
      }
      if (missingFile) {
        skipped++;
        continue;
      }
      await _pluginRepository.restorePluginDirectory(pluginId, restoredFiles);
      final pluginDir = await _pluginRepository.pluginDirectory(pluginId);
      await _pluginRepository.savePluginSettings(pluginId, incoming.settings);
      await _pluginRepository.savePluginStorage(pluginId, incoming.storage);
      final restored = incoming.plugin.copyWith(path: pluginDir.path);
      if (exists) {
        nextPlugins[index] = restored;
        replaced++;
      } else {
        nextPlugins.add(restored);
        added++;
      }
    }

    await _pluginRepository.saveInstalledPlugins(nextPlugins);
    await pluginProvider?.load();
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
    if (sections.contains(BackupSection.roleplay)) {
      for (final incoming
          in data.roleplaySessions ?? const <RoleplayScenario>[]) {
        final local = _findById(roleplayProvider.scenarios, incoming.id);
        if (local != null && !_sameJson(local, incoming)) {
          conflicts.add(
            ImportConflict(
              id: _conflictId(BackupSection.roleplay, incoming.id),
              section: BackupSection.roleplay,
              title: incoming.title,
              localSummary: _formatUpdated(local.updatedAt),
              incomingSummary: _formatUpdated(incoming.updatedAt),
            ),
          );
        }
      }
    }
    if (sections.contains(BackupSection.plugins)) {
      final localPlugins = pluginProvider?.plugins ?? const <InstalledPlugin>[];
      for (final incoming in data.plugins ?? const <BackupPluginData>[]) {
        final local = _findById(localPlugins, incoming.plugin.id);
        if (local != null) {
          conflicts.add(
            ImportConflict(
              id: _conflictId(BackupSection.plugins, incoming.plugin.id),
              section: BackupSection.plugins,
              title: incoming.plugin.manifest.name,
              localSummary: '版本 ${local.manifest.version}',
              incomingSummary: '版本 ${incoming.plugin.manifest.version}',
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
    final groups = _mergeRoleGroups(
      local.roleGroups,
      incoming.roleGroups,
      idMap,
    );
    return local.copyWith(
      roles: roles,
      roleGroups: groups,
      systemPrompts: prompts,
    );
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
    final groups = _appendMissingRoleGroups(
      local.roleGroups,
      incoming.roleGroups,
      idMap,
    );
    return local.copyWith(
      roles: roles,
      roleGroups: groups,
      systemPrompts: prompts,
    );
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
        roleGroups: incoming.roleGroups,
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
    final groups = settings.roleGroups.map((group) {
      return group.copyWith(
        roleIds: group.roleIds
            .map((id) => idMap.roleIds[id] ?? id)
            .toSet()
            .toList(),
      );
    }).toList();
    return settings.copyWith(
      roles: roles,
      roleGroups: groups,
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
    final repairedGroups = settings.roleGroups.map((group) {
      return group.copyWith(
        roleIds: group.roleIds.where(roleIds.contains).toSet().toList(),
      );
    }).toList();
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
      roleGroups: repairedGroups,
    );
  }

  List<ChatRoleGroup> _mergeRoleGroups(
    List<ChatRoleGroup> local,
    List<ChatRoleGroup> incoming,
    _ImportIdMap idMap,
  ) {
    final usedIds = local.map((item) => item.id).toSet();
    final groups = [...local];
    for (final group in incoming) {
      final next = usedIds.contains(group.id)
          ? group.copyWith(id: _newUniqueId(usedIds))
          : group;
      usedIds.add(next.id);
      groups.add(_remapRoleGroup(next, idMap));
    }
    return groups;
  }

  List<ChatRoleGroup> _appendMissingRoleGroups(
    List<ChatRoleGroup> local,
    List<ChatRoleGroup> incoming,
    _ImportIdMap idMap,
  ) {
    final usedIds = local.map((item) => item.id).toSet();
    final groups = [...local];
    for (final group in incoming) {
      if (usedIds.contains(group.id)) {
        final index = groups.indexWhere((item) => item.id == group.id);
        if (index != -1) {
          final localGroup = groups[index];
          final roleIds = {
            ...localGroup.roleIds,
            ..._remapRoleGroup(group, idMap).roleIds,
          }.toList();
          if (roleIds.length != localGroup.roleIds.length) {
            groups[index] = localGroup.copyWith(
              roleIds: roleIds,
              updatedAt: DateTime.now(),
            );
          }
        }
        continue;
      }
      usedIds.add(group.id);
      groups.add(_remapRoleGroup(group, idMap));
    }
    return groups;
  }

  ChatRoleGroup _remapRoleGroup(ChatRoleGroup group, _ImportIdMap idMap) {
    return group.copyWith(
      roleIds: group.roleIds
          .map((id) => idMap.roleIds[id] ?? id)
          .toSet()
          .toList(),
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

  Conversation _copyConversationWithNewIds(Conversation conversation) {
    return conversation.copyWith(
      id: _uuid.v4(),
      messages: conversation.messages
          .map(
            (message) => Message(
              id: _uuid.v4(),
              role: message.role,
              content: message.content,
              images: message.images,
              thinkingContent: message.thinkingContent,
              agentTrace: message.agentTrace,
              timestamp: message.timestamp,
            ),
          )
          .toList(growable: false),
    );
  }

  TodoList _copyTodoListWithNewIds(TodoList list) {
    return list.copyWith(
      id: _uuid.v4(),
      items: list.items
          .map((item) => item.copyWith(id: _uuid.v4()))
          .toList(growable: false),
    );
  }

  RoleplayScenario _copyRoleplayScenarioWithNewIds(RoleplayScenario scenario) {
    final now = DateTime.now();
    return RoleplayScenario(
      id: _uuid.v4(),
      title: scenario.title,
      description: scenario.description,
      scenario: scenario.scenario,
      director: scenario.director,
      defaultPlayer: scenario.defaultPlayer.copyWith(id: _uuid.v4()),
      defaultParticipants: scenario.defaultParticipants
          .map((item) => item.copyWith(id: _uuid.v4()))
          .toList(),
      defaultGroups: scenario.defaultGroups
          .map(
            (item) => RoleplayParticipantGroup(
              id: _uuid.v4(),
              name: item.name,
              createdAt: now,
              updatedAt: now,
            ),
          )
          .toList(),
      maxAutoTurns: scenario.maxAutoTurns,
      pinned: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  RoleplayScenario _remapRoleplayScenario(
    RoleplayScenario scenario,
    _ImportIdMap idMap,
  ) {
    return scenario.copyWith(
      director: _remapRoleplayDirector(scenario.director, idMap),
      defaultPlayer: _remapRoleplayParticipant(scenario.defaultPlayer, idMap),
      defaultParticipants: scenario.defaultParticipants
          .map((item) => _remapRoleplayParticipant(item, idMap))
          .toList(),
    );
  }

  RoleplayThread _remapRoleplayThread(
    RoleplayThread thread,
    _ImportIdMap idMap,
  ) {
    return thread.copyWith(
      director: _remapRoleplayDirector(thread.director, idMap),
      participants: thread.participants
          .map((item) => _remapRoleplayParticipant(item, idMap))
          .toList(),
    );
  }

  RoleplayDirector _remapRoleplayDirector(
    RoleplayDirector director,
    _ImportIdMap idMap,
  ) {
    return director.copyWith(
      model: director.model.copyWith(
        modelId: _remapNullable(director.model.modelId, idMap.modelIds),
      ),
    );
  }

  RoleplayParticipant _remapRoleplayParticipant(
    RoleplayParticipant participant,
    _ImportIdMap idMap,
  ) {
    final sourceRoleId = participant.sourceRoleId;
    return participant.copyWith(
      sourceRoleId: sourceRoleId == null
          ? null
          : idMap.roleIds[sourceRoleId] ?? sourceRoleId,
      model: participant.model.copyWith(
        modelId: _remapNullable(participant.model.modelId, idMap.modelIds),
      ),
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

  NoteRevision _remapStorageV2Revision(
    NoteRevision revision,
    _ImportIdMap idMap,
  ) {
    return revision.copyWith(
      id: idMap.noteRevisionIds[revision.id],
      noteId: idMap.noteIds[revision.noteId] ?? revision.noteId,
      pageId: _remapNullable(revision.pageId, idMap.notePageIds),
      parentRevisionId: _remapNullable(
        revision.parentRevisionId,
        idMap.noteRevisionIds,
      ),
    );
  }

  NoteEditProposal _remapStorageV2Proposal(
    NoteEditProposal proposal,
    _ImportIdMap idMap,
  ) {
    final nextProposalId = idMap.noteProposalIds.putIfAbsent(
      proposal.id,
      () => _uuid.v4(),
    );
    return NoteEditProposal(
      id: nextProposalId,
      noteId: idMap.noteIds[proposal.noteId] ?? proposal.noteId,
      pageId: _remapNullable(proposal.pageId, idMap.notePageIds),
      baseRevisionId: _remapNullable(
        proposal.baseRevisionId,
        idMap.noteRevisionIds,
      ),
      baseContentHash: proposal.baseContentHash,
      createdAt: proposal.createdAt,
      blocks: proposal.blocks
          .map((block) {
            return NoteEditBlock(
              id: idMap.noteEditBlockIds.putIfAbsent(block.id, _uuid.v4),
              startLine: block.startLine,
              deleteCount: block.deleteCount,
              deletedLines: block.deletedLines,
              insertLines: block.insertLines,
            );
          })
          .toList(growable: false),
    );
  }

  StorageV2NotePage _remapStorageV2Page(
    StorageV2NotePage page,
    _ImportIdMap idMap,
    Set<String> usedRelativePaths,
  ) {
    final noteId = idMap.noteIds[page.noteId] ?? page.noteId;
    final pageId = idMap.notePageIds[page.id] ?? page.id;
    final fileName = _uniqueStorageV2PageFileName(page, usedRelativePaths);
    final relativePath = _uniqueStorageV2PagePath(
      noteId,
      fileName,
      usedRelativePaths,
    );
    return StorageV2NotePage(
      id: pageId,
      noteId: noteId,
      title: page.title,
      fileName: relativePath.split('/').last,
      relativePath: relativePath,
      currentRevisionId: _remapNullable(
        page.currentRevisionId,
        idMap.noteRevisionIds,
      ),
      sortOrder: page.sortOrder,
      createdAt: page.createdAt,
      updatedAt: page.updatedAt,
    );
  }

  static String _uniqueStorageV2PageFileName(
    StorageV2NotePage page,
    Set<String> usedRelativePaths,
  ) {
    final rawName = page.fileName.isEmpty
        ? '${safeExportFileName(page.title, fallback: 'page')}.md'
        : safeStorageFileName(page.fileName, fallback: 'page.md');
    final hasExtension = rawName.split('/').last.contains('.');
    final name = hasExtension ? rawName : '$rawName.md';
    if (!usedRelativePaths.any((path) => path.endsWith('/$name'))) return name;
    final dot = name.lastIndexOf('.');
    final base = dot <= 0 ? name : name.substring(0, dot);
    final extension = dot <= 0 ? '.md' : name.substring(dot);
    var suffix = 1;
    var next = '${base}_$suffix$extension';
    while (usedRelativePaths.any((path) => path.endsWith('/$next'))) {
      suffix++;
      next = '${base}_$suffix$extension';
    }
    return next;
  }

  static String _uniqueStorageV2PagePath(
    String noteId,
    String fileName,
    Set<String> usedRelativePaths,
  ) {
    final noteDirectoryName = safeStorageSegment(noteId, fallback: 'note');
    final safeName = safeStorageFileName(fileName, fallback: 'page.md');
    final dot = safeName.lastIndexOf('.');
    final base = dot <= 0 ? safeName : safeName.substring(0, dot);
    final extension = dot <= 0 ? '.md' : safeName.substring(dot);
    var path = 'notes/$noteDirectoryName/$safeName';
    var suffix = 1;
    while (usedRelativePaths.contains(path)) {
      path = 'notes/$noteDirectoryName/${base}_$suffix$extension';
      suffix++;
    }
    usedRelativePaths.add(path);
    return path;
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
    final dir = await StorageV2Service.defaultBaseDirectory();
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

  Future<void> _mergeBackupResources(
    BackupArchiveData archive,
    Map<String, String> restoredAssetPaths,
  ) async {
    if (storageV2 == null) return;
    if (!featureProvider.usingStorageV2) return;
    final resources = archive.resources;
    if (resources == null || resources.isEmpty) return;
    List<StorageV2Resource> existing;
    try {
      existing = await storageV2!.loadResources();
    } catch (_) {
      return;
    }
    var changed = false;
    for (final raw in resources) {
      try {
        final resource = StorageV2Resource.fromJson(raw);
        if (existing.any((r) => r.id == resource.id)) continue;
        existing.add(resource);
        changed = true;
      } catch (_) {}
    }
    if (!changed) return;
    try {
      await storageV2!.writeDataFile('resources.json', {
        'resources': existing.map((r) => r.toJson()).toList(),
      });
    } catch (e) {
      archive.warnings.add('合并资源列表失败: $e');
    }
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
      notePages: data.notePages,
      notePageContents: data.notePageContents,
      noteRevisions: data.noteRevisions,
      noteEditProposals: data.noteEditProposals,
      schedules: data.schedules,
      todoLists: data.todoLists,
      roleplaySessions: data.roleplaySessions,
      roleplayThreads: data.roleplayThreads,
      plugins: data.plugins,
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
        agentTrace: message.agentTrace,
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

  static String _relativePath(String root, String path) {
    final normalizedRoot = _normalizePath(root).replaceAll(RegExp(r'/+$'), '');
    final normalizedPath = _normalizePath(path);
    if (!normalizedPath.startsWith('$normalizedRoot/')) return '';
    return normalizedPath.substring(normalizedRoot.length + 1);
  }

  static bool _isSafePluginRelativePath(String path) {
    if (!_isSafeArchivePath(path)) return false;
    final normalized = path.replaceAll('\\', '/');
    return normalized != 'plugin.json' || normalized.split('/').length == 1;
  }

  static void _validateArchiveEntryPath(String path) {
    if (!_isSafeArchivePath(path, allowDirectory: true)) {
      throw FormatException('备份包包含不安全路径：$path');
    }
  }

  static bool _isSafeArchivePath(String path, {bool allowDirectory = false}) {
    if (path.isEmpty || path.contains('\\') || path.startsWith('/')) {
      return false;
    }
    if (RegExp(r'^[A-Za-z]:').hasMatch(path)) return false;
    final normalized = allowDirectory && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    if (normalized.isEmpty) return false;
    final parts = normalized.split('/');
    return parts.every(
      (part) => part.isNotEmpty && part != '.' && part != '..',
    );
  }

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
    final filteredPages = data.notePages
        ?.where((item) => noteIds.contains(item['noteId']))
        .toList();
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
      notePages: filteredPages,
      notePageContents: data.notePageContents == null
          ? null
          : Map.fromEntries(
              data.notePageContents!.entries.where(
                (entry) =>
                    filteredPages?.any((page) => page['id'] == entry.key) ??
                    false,
              ),
            ),
      noteRevisions: data.noteRevisions
          ?.where((item) => noteIds.contains(item.noteId))
          .toList(),
      noteEditProposals: data.noteEditProposals
          ?.where((item) => noteIds.contains(item.noteId))
          .toList(),
      schedules: data.schedules
          ?.where((item) => selection.scheduleIds.contains(item.id))
          .toList(),
      todoLists: data.todoLists
          ?.where((item) => selection.todoListIds.contains(item.id))
          .toList(),
      roleplaySessions: data.roleplaySessions
          ?.where((item) => selection.roleplaySessionIds.contains(item.id))
          .toList(),
      roleplayThreads: data.roleplayThreads
          ?.where(
            (item) => selection.roleplaySessionIds.contains(item.scenarioId),
          )
          .toList(),
      plugins: data.plugins
          ?.where((item) => selection.pluginIds.contains(item.plugin.id))
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
        'roleGroups': settings.roleGroups.map((item) => item.toJson()).toList(),
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
        final pageCount = data.notePages?.length;
        final pageDetail = pageCount == null ? '' : '，$pageCount 个分页';
        return '${data.notes?.length ?? 0} 篇笔记$pageDetail，${data.noteFolders?.length ?? 0} 个文件夹';
      case BackupSection.schedules:
        return '${data.schedules?.length ?? 0} 条日程';
      case BackupSection.todoLists:
        return '${data.todoLists?.length ?? 0} 个清单';
      case BackupSection.roleplay:
        return '${data.roleplaySessions?.length ?? 0} 个情景，${data.roleplayThreads?.length ?? 0} 次演绎';
      case BackupSection.plugins:
        return '${data.plugins?.length ?? 0} 个插件';
    }
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

  static List<Map<String, dynamic>>? _parseRawMapList(
    Object? value,
    List<String> warnings,
    String label,
  ) {
    if (value == null) return null;
    if (value is! List) {
      warnings.add('$label 格式不是列表');
      return const [];
    }
    final items = <Map<String, dynamic>>[];
    for (final item in value) {
      try {
        if (item is Map) items.add(Map<String, dynamic>.from(item));
      } catch (e) {
        warnings.add('$label 解析失败：$e');
      }
    }
    return items;
  }

  static String _notePageContentPath(String pageId) {
    return 'notes/page_contents/${safeStorageSegment(pageId, fallback: 'page')}.md';
  }

  Future<List<Map<String, dynamic>>> _collectExportResources(
    BackupSelection selection,
    Map<String, String> archivedAssetPaths,
    List<Map<String, dynamic>> assetRecords,
  ) async {
    if (storageV2 == null) return [];
    if (!featureProvider.usingStorageV2) return [];
    List<StorageV2Resource> existing;
    try {
      existing = await storageV2!.loadResources();
    } catch (_) {
      return [];
    }
    final items = <Map<String, dynamic>>[];
    final seenIds = <String>{};
    for (final record in assetRecords) {
      final originalPath = record['originalPath'] as String? ?? '';
      if (originalPath.isEmpty) continue;
      final matched = existing.where(
        (res) =>
            !res.missing &&
            _normalizePath(res.originalPath) == _normalizePath(originalPath),
      );
      if (matched.isNotEmpty) {
        final resource = matched.first;
        if (seenIds.add(resource.id)) {
          items.add(resource.toJson());
        }
        record['resourceId'] = resource.id;
        record['sha256'] = resource.sha256Hash;
      } else {
        try {
          final file = File(originalPath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final hash = sha256.convert(bytes).toString();
            final dup = existing.where(
              (res) => !res.missing && res.sha256Hash == hash,
            );
            if (dup.isNotEmpty) {
              record['resourceId'] = dup.first.id;
              record['sha256'] = hash;
              if (seenIds.add(dup.first.id)) {
                items.add(dup.first.toJson());
              }
            } else {
              final safeName = safeStorageFileName(
                record['name'] as String? ?? 'asset',
                fallback: 'asset',
              );
              final kind = record['kind'] as String? ?? 'unknown';
              final prefix = hash.substring(0, 2);
              final relativePath = 'assets/$kind/$prefix/${hash}_$safeName';
              final resource = StorageV2Resource(
                id: 'res_${hash.substring(0, 32)}',
                kind: kind,
                role: record['kind'] as String? ?? 'unknown',
                originalPath: originalPath,
                originalName: safeName,
                relativePath: relativePath,
                mimeType: record['mimeType'] as String? ?? '',
                size: bytes.length,
                sha256Hash: hash,
                missing: false,
              );
              record['resourceId'] = resource.id;
              record['sha256'] = hash;
              if (seenIds.add(resource.id)) {
                items.add(resource.toJson());
              }
            }
          }
        } catch (_) {}
      }
    }
    return items;
  }
}

class _FlatMessageRow {
  const _FlatMessageRow({required this.message, required this.sortOrder});

  final Message message;
  final int? sortOrder;
}

class _ImportIdMap {
  final modelIds = <String, String>{};
  final roleIds = <String, String>{};
  final systemPromptIds = <String, String>{};
  final noteFolderIds = <String, String>{};
  final noteIds = <String, String>{};
  final notePageIds = <String, String>{};
  final noteRevisionIds = <String, String>{};
  final noteProposalIds = <String, String>{};
  final noteEditBlockIds = <String, String>{};
}
