import 'package:flutter/foundation.dart';

import '../models/note.dart';
import '../models/schedule_item.dart';
import '../models/todo_list.dart';
import '../services/storage_v2_service.dart';

/// 功能模块加载结果，包含日程、笔记、待办清单等多项数据。
class FeatureLoadResult {
  const FeatureLoadResult({
    required this.schedules,
    required this.notes,
    required this.noteFolders,
    required this.noteRevisions,
    required this.noteEditProposals,
    required this.todoLists,
    required this.pagesByNoteId,
    required this.activePageIds,
    required this.revisionContents,
    required this.pageHeads,
    required this.pageTombstones,
    required this.pageConflicts,
    required this.usingStorageV2,
  });

  final List<ScheduleItem> schedules;
  final List<Note> notes;
  final List<NoteFolder> noteFolders;
  final List<NoteRevision> noteRevisions;
  final List<NoteEditProposal> noteEditProposals;
  final List<TodoList> todoLists;
  final Map<String, List<StorageV2NotePage>> pagesByNoteId;
  final Map<String, String> activePageIds;
  final Map<String, NoteRevisionContent> revisionContents;
  final Map<String, NotePageHeads> pageHeads;
  final List<Map<String, dynamic>> pageTombstones;
  final Map<String, NotePageConflict> pageConflicts;
  final bool usingStorageV2;
}

/// 功能模块数据仓储，负责日程、笔记、待办清单等功能的持久化。
class FeatureRepository {
  factory FeatureRepository({StorageV2Service? storageV2}) {
    final storage = storageV2 ?? StorageV2Service();
    return FeatureRepository._(storage);
  }

  FeatureRepository._(this._storageV2);

  final StorageV2Service _storageV2;

  /// storage_v2 is the only app data store.
  Future<bool> isStorageV2Active() async => true;

  /// 读取指定笔记分页的文本内容。
  Future<String> readNotePage(StorageV2NotePage page) =>
      _storageV2.readNotePage(page);

  /// 写入指定笔记分页的文本内容。
  Future<void> writeNotePage(StorageV2NotePage page, String content) =>
      _storageV2.writeNotePage(page, content);

  /// 删除指定相对路径的文件。
  Future<void> deleteFile(String relativePath) =>
      _storageV2.deleteFile(relativePath);

  Future<String> storeNoteBlob(String content) =>
      _storageV2.storeNoteBlob(content);

  Future<String> readNoteBlob(String hash) => _storageV2.readNoteBlobText(hash);

  Future<List<int>> readNoteBlobBytes(String hash) =>
      _storageV2.readNoteBlob(hash);

  Future<void> installNoteBlob(String hash, List<int> bytes) =>
      _storageV2.installNoteBlob(hash, bytes);

  /// 加载所有功能模块数据，优先使用新版 V2 存储。
  Future<FeatureLoadResult> load() async {
    return _loadStorageV2();
  }

  /// 保存日程列表到当前激活的存储后端。
  Future<void> saveSchedules(
    List<ScheduleItem> schedules, {
    required bool usingStorageV2,
  }) async {
    await _storageV2.writeDataFile('schedules.json', {
      'schedules': schedules.map((item) => item.toJson()).toList(),
    });
  }

  /// 保存待办清单列表到当前激活的存储后端。
  Future<void> saveTodoLists(
    List<TodoList> lists, {
    required bool usingStorageV2,
  }) async {
    final todoLists = <Map<String, dynamic>>[];
    final todoItems = <Map<String, dynamic>>[];
    for (final list in lists) {
      todoLists.add({
        'id': list.id,
        'title': list.title,
        'createdAt': list.createdAt.toIso8601String(),
        'updatedAt': list.updatedAt.toIso8601String(),
      });
      for (var i = 0; i < list.items.length; i++) {
        final item = list.items[i];
        todoItems.add({
          'id': item.id,
          'listId': list.id,
          'text': item.text,
          'done': item.done,
          'sortOrder': i,
        });
      }
    }
    await _storageV2.writeDataFile('todo_lists.json', {
      'todoLists': todoLists,
      'todoItems': todoItems,
    });
  }

  /// Note metadata is persisted together by [_storageV2.writeNotesData].
  Future<void> saveNoteFoldersSnapshot(List<NoteFolder> folders) async {
    return;
  }

  /// Note metadata is persisted together by [_storageV2.writeNotesData].
  Future<void> saveNoteRevisionsSnapshot(List<NoteRevision> revisions) async {
    return;
  }

  /// Note metadata is persisted together by [_storageV2.writeNotesData].
  Future<void> saveNotesSnapshot(List<Note> notes) async {
    return;
  }

  /// Note metadata is persisted together by [_storageV2.writeNotesData].
  Future<void> saveNoteEditProposalsSnapshot(
    List<NoteEditProposal> proposals,
  ) async {
    return;
  }

  /// 以新版 V2 存储格式保存笔记数据。
  Future<void> saveStorageV2NotesData(Map<String, dynamic> data) {
    return _storageV2.writeNotesData(data);
  }

  Future<FeatureLoadResult> _loadStorageV2() async {
    final schedules = await _loadStorageV2Schedules();
    final todoLists = await _loadStorageV2TodoLists();
    final notes = await _loadStorageV2Notes();
    return FeatureLoadResult(
      schedules: schedules,
      notes: notes.notes,
      noteFolders: notes.folders,
      noteRevisions: notes.revisions,
      noteEditProposals: notes.proposals,
      todoLists: todoLists,
      pagesByNoteId: notes.pagesByNoteId,
      activePageIds: notes.activePageIds,
      revisionContents: notes.revisionContents,
      pageHeads: notes.pageHeads,
      pageTombstones: notes.pageTombstones,
      pageConflicts: notes.pageConflicts,
      usingStorageV2: true,
    );
  }

  Future<List<ScheduleItem>> _loadStorageV2Schedules() async {
    final data = await _storageV2.loadDataFile('schedules.json');
    final schedules = <ScheduleItem>[];
    for (final item in data['schedules'] as List<dynamic>? ?? const []) {
      try {
        if (item is Map) {
          schedules.add(ScheduleItem.fromJson(Map<String, dynamic>.from(item)));
        }
      } catch (e) {
        debugPrint('跳过损坏的新版日程记录: $e');
      }
    }
    return schedules..sort((a, b) => a.start.compareTo(b.start));
  }

  Future<List<TodoList>> _loadStorageV2TodoLists() async {
    final data = await _storageV2.loadDataFile('todo_lists.json');
    final itemsByListId = <String, List<TodoItem>>{};
    for (final item in data['todoItems'] as List<dynamic>? ?? const []) {
      try {
        if (item is! Map) continue;
        final json = Map<String, dynamic>.from(item);
        final listId = json['listId'] as String;
        (itemsByListId[listId] ??= []).add(
          TodoItem(
            id: json['id'] as String,
            text: json['text'] as String? ?? '',
            done: json['done'] as bool? ?? false,
            updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
          ),
        );
      } catch (e) {
        debugPrint('跳过损坏的新版待办项记录: $e');
      }
    }
    final lists = <TodoList>[];
    for (final item in data['todoLists'] as List<dynamic>? ?? const []) {
      try {
        if (item is! Map) continue;
        final json = Map<String, dynamic>.from(item);
        final id = json['id'] as String;
        lists.add(
          TodoList(
            id: id,
            title: json['title'] as String? ?? '',
            items: itemsByListId[id] ?? const [],
            createdAt: DateTime.parse(json['createdAt'] as String),
            updatedAt: DateTime.parse(json['updatedAt'] as String),
          ),
        );
      } catch (e) {
        debugPrint('跳过损坏的新版待办清单记录: $e');
      }
    }
    return lists;
  }

  Future<_StorageV2NotesLoadResult> _loadStorageV2Notes() async {
    await _storageV2.recoverNoteMaterialization();
    final data = await _storageV2.loadNotesData();
    final folders = <NoteFolder>[];
    for (final item in data['folders'] as List<dynamic>? ?? const []) {
      try {
        if (item is Map) {
          folders.add(NoteFolder.fromJson(Map<String, dynamic>.from(item)));
        }
      } catch (e) {
        debugPrint('跳过损坏的新版笔记文件夹记录: $e');
      }
    }

    final pages = <StorageV2NotePage>[];
    for (final item in data['pages'] as List<dynamic>? ?? const []) {
      try {
        if (item is Map) {
          pages.add(
            StorageV2NotePage.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      } catch (e) {
        debugPrint('跳过损坏的新版分页记录: $e');
      }
    }
    pages.sort((a, b) {
      final noteCompare = a.noteId.compareTo(b.noteId);
      if (noteCompare != 0) return noteCompare;
      return a.sortOrder.compareTo(b.sortOrder);
    });
    final pagesByNoteId = <String, List<StorageV2NotePage>>{};
    for (final page in pages) {
      (pagesByNoteId[page.noteId] ??= []).add(page);
    }

    final notes = <Note>[];
    final activePageIds = <String, String>{};
    for (final item in data['notes'] as List<dynamic>? ?? const []) {
      try {
        if (item is! Map) continue;
        final json = Map<String, dynamic>.from(item);
        final id = json['id'] as String;
        final notePages = pagesByNoteId[id] ?? const [];
        final currentPageId = json['currentPageId'] as String?;
        final page = notePages.firstWhere(
          (page) => page.id == currentPageId,
          orElse: () => notePages.isEmpty
              ? throw const FormatException('note has no pages')
              : notePages.first,
        );
        activePageIds[id] = page.id;
        notes.add(
          Note(
            id: id,
            title: json['title'] as String? ?? '',
            content: await _storageV2.readNotePage(page),
            currentRevisionId:
                page.currentRevisionId ?? json['currentRevisionId'] as String?,
            folderId: json['folderId'] as String?,
            createdAt: DateTime.parse(json['createdAt'] as String),
            updatedAt: DateTime.parse(json['updatedAt'] as String),
            wrap: json['wrap'] as bool? ?? true,
          ),
        );
      } catch (e) {
        debugPrint('跳过损坏的新版笔记记录: $e');
      }
    }

    final revisions = <NoteRevision>[];
    final revisionContents = <String, NoteRevisionContent>{};
    for (final item in data['revisions'] as List<dynamic>? ?? const []) {
      try {
        if (item is! Map) continue;
        final json = Map<String, dynamic>.from(item);
        final revision = NoteRevision.fromJson(json);
        revisions.add(revision);
        if (revision.contentHash.isNotEmpty) {
          try {
            revisionContents[revision.id] = NoteRevisionContent.loaded(
              await _storageV2.readNoteBlobText(revision.contentHash),
            );
          } catch (e) {
            revisionContents[revision.id] = const NoteRevisionContent.missing();
            debugPrint('笔记时间线正文 blob 缺失 ${revision.contentHash}: $e');
          }
        }
      } catch (e) {
        debugPrint('跳过损坏的新版笔记时间线记录: $e');
      }
    }

    final pageHeads = <String, NotePageHeads>{};
    for (final item in data['pageHeads'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final pageId = json['pageId'] as String?;
      if (pageId == null) continue;
      pageHeads[pageId] = NotePageHeads(
        pageId: pageId,
        headIds: (json['headIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toSet(),
        selectedHeadId: json['selectedHeadId'] as String?,
      );
    }
    final pageTombstones = <Map<String, dynamic>>[];
    for (final item in data['pageTombstones'] as List<dynamic>? ?? const []) {
      try {
        if (item is Map) {
          final json = Map<String, dynamic>.from(item);
          json['id'] as String;
          json['pageId'] as String;
          json['revisionId'] as String;
          pageTombstones.add(json);
        }
      } catch (e) {
        debugPrint('跳过损坏的分页删除标记: $e');
      }
    }
    final pageConflicts = <String, NotePageConflict>{};
    for (final item in data['pageConflicts'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final pageId = json['pageId'] as String?;
      if (pageId == null) continue;
      final headIds = (json['headIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList();
      if (headIds.length < 2) continue;
      pageConflicts[pageId] = NotePageConflict(
        pageId: pageId,
        headIds: headIds,
        localHeadId: json['localHeadId'] as String? ?? headIds.first,
        incomingHeadId: json['incomingHeadId'] as String? ?? headIds[1],
        commonAncestorId: json['commonAncestorId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
    }

    final blocksByProposal = <String, List<NoteEditBlock>>{};
    for (final item in data['editBlocks'] as List<dynamic>? ?? const []) {
      try {
        if (item is! Map) continue;
        final json = Map<String, dynamic>.from(item);
        final proposalId = json['proposalId'] as String;
        (blocksByProposal[proposalId] ??= []).add(
          NoteEditBlock(
            id: json['id'] as String,
            startLine: (json['startLine'] as num?)?.toInt() ?? 1,
            deleteCount: (json['deleteCount'] as num?)?.toInt() ?? 0,
            deletedLines: (json['deletedLines'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toList(),
            insertLines: (json['insertLines'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toList(),
          ),
        );
      } catch (e) {
        debugPrint('跳过损坏的新版笔记建议块记录: $e');
      }
    }
    final proposals = <NoteEditProposal>[];
    for (final item in data['editProposals'] as List<dynamic>? ?? const []) {
      try {
        if (item is! Map) continue;
        final json = Map<String, dynamic>.from(item);
        proposals.add(
          NoteEditProposal(
            id: json['id'] as String,
            noteId: json['noteId'] as String,
            pageId: json['pageId'] as String?,
            baseRevisionId: json['baseRevisionId'] as String?,
            baseContentHash: json['baseContentHash'] as String? ?? '',
            createdAt: DateTime.parse(json['createdAt'] as String),
            blocks: blocksByProposal[json['id'] as String] ?? const [],
          ),
        );
      } catch (e) {
        debugPrint('跳过损坏的新版笔记建议记录: $e');
      }
    }

    return _StorageV2NotesLoadResult(
      folders: folders,
      notes: notes,
      revisions: revisions,
      proposals: proposals,
      pagesByNoteId: pagesByNoteId,
      activePageIds: activePageIds,
      revisionContents: revisionContents,
      pageHeads: pageHeads,
      pageTombstones: pageTombstones,
      pageConflicts: pageConflicts,
    );
  }
}

class _StorageV2NotesLoadResult {
  const _StorageV2NotesLoadResult({
    required this.folders,
    required this.notes,
    required this.revisions,
    required this.proposals,
    required this.pagesByNoteId,
    required this.activePageIds,
    required this.revisionContents,
    required this.pageHeads,
    required this.pageTombstones,
    required this.pageConflicts,
  });

  final List<NoteFolder> folders;
  final List<Note> notes;
  final List<NoteRevision> revisions;
  final List<NoteEditProposal> proposals;
  final Map<String, List<StorageV2NotePage>> pagesByNoteId;
  final Map<String, String> activePageIds;
  final Map<String, NoteRevisionContent> revisionContents;
  final Map<String, NotePageHeads> pageHeads;
  final List<Map<String, dynamic>> pageTombstones;
  final Map<String, NotePageConflict> pageConflicts;
}
