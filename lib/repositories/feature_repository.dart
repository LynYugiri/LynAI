import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/note.dart';
import '../models/schedule_item.dart';
import '../models/todo_list.dart';
import '../services/storage_v2_service.dart';
import 'app_storage_state.dart';

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
  final bool usingStorageV2;
}

/// 功能模块数据仓储，负责日程、笔记、待办清单等功能的持久化。
///
/// 支持旧版 SharedPreferences 与新版存储 V2 两种模式，
/// 提供各功能模块的加载与保存接口。
class FeatureRepository {
  factory FeatureRepository({
    StorageV2Service? storageV2,
    AppStorageStateRepository? storageState,
  }) {
    final storage = storageV2 ?? StorageV2Service();
    return FeatureRepository._(
      storage,
      storageState ?? AppStorageStateRepository(storageV2: storage),
    );
  }

  FeatureRepository._(this._storageV2, this._storageState);

  static const _scheduleKey = 'schedule_items';
  static const _notesKey = 'notes';
  static const _noteRevisionsKey = 'note_revisions';
  static const _noteFoldersKey = 'note_folders';
  static const _noteEditProposalsKey = 'note_edit_proposals';
  static const _todoListsKey = 'todo_lists';

  final StorageV2Service _storageV2;
  final AppStorageStateRepository _storageState;

  /// 判断当前是否激活了新版存储 V2。
  Future<bool> isStorageV2Active() => _storageState.isStorageV2Active();

  /// 读取指定笔记分页的文本内容。
  Future<String> readNotePage(StorageV2NotePage page) =>
      _storageV2.readNotePage(page);
  /// 写入指定笔记分页的文本内容。
  Future<void> writeNotePage(StorageV2NotePage page, String content) =>
      _storageV2.writeNotePage(page, content);
  /// 删除指定相对路径的文件。
  Future<void> deleteFile(String relativePath) =>
      _storageV2.deleteFile(relativePath);

  /// 加载所有功能模块数据，优先使用新版 V2 存储。
  Future<FeatureLoadResult> load() async {
    final legacy = await _loadLegacy();
    if (!await isStorageV2Active()) return legacy;
    try {
      final storage = await _loadStorageV2(legacy);
      return storage;
    } catch (e) {
      debugPrint('加载新版笔记存储失败，保留旧版笔记数据: $e');
      return legacy;
    }
  }

  /// 保存日程列表到当前激活的存储后端。
  Future<void> saveSchedules(
    List<ScheduleItem> schedules, {
    required bool usingStorageV2,
  }) async {
    if (usingStorageV2 || await isStorageV2Active()) {
      await _storageV2.writeDataFile('schedules.json', {
        'schedules': schedules.map((item) => item.toJson()).toList(),
      });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _scheduleKey,
      jsonEncode(schedules.map((item) => item.toJson()).toList()),
    );
  }

  /// 保存待办清单列表到当前激活的存储后端。
  Future<void> saveTodoLists(
    List<TodoList> lists, {
    required bool usingStorageV2,
  }) async {
    if (usingStorageV2 || await isStorageV2Active()) {
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
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _todoListsKey,
      jsonEncode(lists.map((item) => item.toJson()).toList()),
    );
  }

  /// 以旧版 SharedPreferences 格式保存笔记文件夹列表。
  Future<void> saveLegacyNoteFolders(List<NoteFolder> folders) async {
    if (await isStorageV2Active()) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _noteFoldersKey,
      jsonEncode(folders.map((item) => item.toJson()).toList()),
    );
  }

  /// 以旧版 SharedPreferences 格式保存笔记时间线记录。
  Future<void> saveLegacyNoteRevisions(List<NoteRevision> revisions) async {
    if (await isStorageV2Active()) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _noteRevisionsKey,
      jsonEncode(revisions.map((item) => item.toJson()).toList()),
    );
  }

  /// 以旧版 SharedPreferences 格式保存笔记列表。
  Future<void> saveLegacyNotes(List<Note> notes) async {
    if (await isStorageV2Active()) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _notesKey,
      jsonEncode(notes.map((item) => item.toJson()).toList()),
    );
  }

  /// 以旧版 SharedPreferences 格式保存笔记修改建议列表。
  Future<void> saveLegacyNoteEditProposals(
    List<NoteEditProposal> proposals,
  ) async {
    if (await isStorageV2Active()) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _noteEditProposalsKey,
      jsonEncode(proposals.map((item) => item.toJson()).toList()),
    );
  }

  /// 以新版 V2 存储格式保存笔记数据。
  Future<void> saveStorageV2NotesData(Map<String, dynamic> data) {
    return _storageV2.writeNotesData(data);
  }

  Future<FeatureLoadResult> _loadLegacy() async {
    final prefs = await SharedPreferences.getInstance();
    return FeatureLoadResult(
      schedules: _parseList(
        prefs.getString(_scheduleKey),
        ScheduleItem.fromJson,
        '日程记录',
      )..sort((a, b) => a.start.compareTo(b.start)),
      notes: _parseList(prefs.getString(_notesKey), Note.fromJson, '笔记记录'),
      noteFolders: _parseList(
        prefs.getString(_noteFoldersKey),
        NoteFolder.fromJson,
        '笔记文件夹记录',
      ),
      noteRevisions: _parseList(
        prefs.getString(_noteRevisionsKey),
        NoteRevision.fromJson,
        '笔记时间线记录',
      ),
      noteEditProposals: _parseList(
        prefs.getString(_noteEditProposalsKey),
        NoteEditProposal.fromJson,
        '笔记修改建议记录',
      ),
      todoLists: _parseList(
        prefs.getString(_todoListsKey),
        TodoList.fromJson,
        '待办清单记录',
      ),
      pagesByNoteId: const {},
      activePageIds: const {},
      usingStorageV2: false,
    );
  }

  Future<FeatureLoadResult> _loadStorageV2(FeatureLoadResult fallback) async {
    final schedules = await _loadStorageV2Schedules(fallback.schedules);
    final todoLists = await _loadStorageV2TodoLists(fallback.todoLists);
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
      usingStorageV2: true,
    );
  }

  Future<List<ScheduleItem>> _loadStorageV2Schedules(
    List<ScheduleItem> fallback,
  ) async {
    try {
      final data = await _storageV2.loadDataFile('schedules.json');
      final schedules = <ScheduleItem>[];
      for (final item in data['schedules'] as List<dynamic>? ?? const []) {
        try {
          if (item is Map) {
            schedules.add(
              ScheduleItem.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        } catch (e) {
          debugPrint('跳过损坏的新版日程记录: $e');
        }
      }
      return schedules..sort((a, b) => a.start.compareTo(b.start));
    } catch (e) {
      debugPrint('加载新版日程失败: $e');
      return fallback;
    }
  }

  Future<List<TodoList>> _loadStorageV2TodoLists(
    List<TodoList> fallback,
  ) async {
    try {
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
    } catch (e) {
      debugPrint('加载新版待办清单失败: $e');
      return fallback;
    }
  }

  Future<_StorageV2NotesLoadResult> _loadStorageV2Notes() async {
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
    for (final item in data['revisions'] as List<dynamic>? ?? const []) {
      try {
        if (item is! Map) continue;
        final json = Map<String, dynamic>.from(item);
        revisions.add(
          NoteRevision(
            id: json['id'] as String,
            noteId: json['noteId'] as String,
            pageId: json['pageId'] as String?,
            parentRevisionId: json['parentRevisionId'] as String?,
            savedAt: DateTime.parse(json['savedAt'] as String),
            delta: NoteTextDelta(
              start: json['deltaStart'] as int? ?? 0,
              deletedText: json['deletedText'] as String? ?? '',
              insertedText: json['insertedText'] as String? ?? '',
            ),
          ),
        );
      } catch (e) {
        debugPrint('跳过损坏的新版笔记时间线记录: $e');
      }
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
            startLine: json['startLine'] as int? ?? 1,
            deleteCount: json['deleteCount'] as int? ?? 0,
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
    );
  }

  static List<T> _parseList<T>(
    String? jsonString,
    T Function(Map<String, dynamic>) parser,
    String label,
  ) {
    if (jsonString == null) return [];
    List<dynamic> items;
    try {
      items = jsonDecode(jsonString) as List<dynamic>;
    } catch (e) {
      debugPrint('解析$label 列表失败: $e');
      return [];
    }
    final parsed = <T>[];
    for (final item in items) {
      try {
        parsed.add(parser(item as Map<String, dynamic>));
      } catch (e) {
        debugPrint('跳过损坏的$label: $e');
      }
    }
    return parsed;
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
  });

  final List<NoteFolder> folders;
  final List<Note> notes;
  final List<NoteRevision> revisions;
  final List<NoteEditProposal> proposals;
  final Map<String, List<StorageV2NotePage>> pagesByNoteId;
  final Map<String, String> activePageIds;
}
