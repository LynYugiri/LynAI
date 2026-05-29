import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../models/schedule_item.dart';
import '../models/todo_list.dart';
import '../services/storage_migration_service.dart';
import '../services/storage_v2_service.dart';
import '../utils/file_name_utils.dart';

/// 管理功能页数据：日程、笔记、笔记修订、文件夹、修改建议和待办清单。
///
/// 这些数据共享一个 Provider，是因为工具调用和备份导入经常需要跨功能区
/// 读写。每个分区仍然使用独立存储键和独立保存队列，避免无关更新互相阻塞。
class FeatureProvider extends ChangeNotifier {
  static const _scheduleKey = 'schedule_items';
  static const _notesKey = 'notes';
  static const _noteRevisionsKey = 'note_revisions';
  static const _noteFoldersKey = 'note_folders';
  static const _noteEditProposalsKey = 'note_edit_proposals';
  static const _todoListsKey = 'todo_lists';
  static const _scheduleWidgetChannel = MethodChannel('lynai/schedule_widget');
  final _uuid = const Uuid();
  Future<void> _scheduleSaveQueue = Future.value();
  Future<void> _noteSaveQueue = Future.value();
  Future<void> _noteRevisionSaveQueue = Future.value();
  Future<void> _noteFolderSaveQueue = Future.value();
  Future<void> _noteEditProposalSaveQueue = Future.value();
  Future<void> _todoListSaveQueue = Future.value();

  List<ScheduleItem> _schedules = [];
  List<Note> _notes = [];
  List<NoteRevision> _noteRevisions = [];
  List<NoteFolder> _noteFolders = [];
  List<TodoList> _todoLists = [];
  final Map<String, NoteEditProposal> _noteEditProposals = {};
  final Map<String, String> _noteRevisionContentCache = {};
  final Map<String, List<NoteRevision>> _noteTimelineCache = {};
  bool _usingStorageV2 = false;
  final StorageV2Service _storageV2;
  Map<String, List<StorageV2NotePage>> _storageV2PagesByNoteId = {};
  Map<String, String> _activeStorageV2PageIds = {};

  FeatureProvider({StorageV2Service? storageV2})
    : _storageV2 = storageV2 ?? StorageV2Service();

  List<ScheduleItem> get schedules => List.unmodifiable(_schedules);
  List<Note> get notes => List.unmodifiable(_notes);
  List<NoteRevision> get noteRevisions => List.unmodifiable(_noteRevisions);
  List<NoteFolder> get noteFolders => List.unmodifiable(_noteFolders);
  List<TodoList> get todoLists => List.unmodifiable(_todoLists);
  bool get usingStorageV2 => _usingStorageV2;

  List<StorageV2NotePage> notePages(String noteId) {
    return List.unmodifiable(_storageV2PagesByNoteId[noteId] ?? const []);
  }

  StorageV2NotePage? activeNotePage(String noteId) {
    final pages = _storageV2PagesByNoteId[noteId] ?? const [];
    if (pages.isEmpty) return null;
    final activeId = _activeStorageV2PageIds[noteId];
    return pages.firstWhere(
      (page) => page.id == activeId,
      orElse: () => pages.first,
    );
  }

  Future<String> noteExportContent(String noteId) async {
    final note = getNote(noteId);
    if (note == null) return '';
    if (!_usingStorageV2) return note.content;
    final pages = _storageV2PagesByNoteId[noteId] ?? const [];
    if (pages.isEmpty) return note.content;
    final buffer = StringBuffer();
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      if (i > 0) buffer.writeln('\n\n---\n');
      buffer.writeln('<!-- page: ${page.title} -->\n');
      buffer.write(await _storageV2.readNotePage(page));
    }
    return buffer.toString();
  }

  Future<List<StorageV2PageExport>> notePageExports(String noteId) async {
    final note = getNote(noteId);
    if (note == null) return const [];
    if (!_usingStorageV2) {
      return [
        StorageV2PageExport(
          fileName: '${safeExportFileName(note.title, fallback: 'note')}.md',
          title: note.title,
          content: note.content,
        ),
      ];
    }
    final pages = _storageV2PagesByNoteId[noteId] ?? const [];
    final used = <String>{};
    final exports = <StorageV2PageExport>[];
    for (final page in pages) {
      var fileName = page.fileName.isEmpty
          ? '${safeExportFileName(page.title, fallback: 'page')}.md'
          : page.fileName;
      if (used.contains(fileName)) {
        final base = safeExportFileName(page.title, fallback: 'page');
        var i = 1;
        while (used.contains('${base}_$i.md')) {
          i++;
        }
        fileName = '${base}_$i.md';
      }
      used.add(fileName);
      exports.add(
        StorageV2PageExport(
          fileName: fileName,
          title: page.title,
          content: await _storageV2.readNotePage(page),
        ),
      );
    }
    return exports;
  }

  /// 批量替换一个或多个功能分区。
  ///
  /// 主要供备份导入使用。未传入的分区保持不变；传入的分区会立即替换内存
  /// 状态并等待对应保存队列完成后再通知 UI。
  Future<void> replaceFeatureData({
    List<ScheduleItem>? schedules,
    List<NoteFolder>? noteFolders,
    List<Note>? notes,
    List<NoteRevision>? noteRevisions,
    List<TodoList>? todoLists,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final storageV2Active = await _storageV2ActiveForSave(prefs);
    final saveTasks = <Future<void>>[];
    if (schedules != null) {
      _schedules = List<ScheduleItem>.from(schedules)
        ..sort((a, b) => a.start.compareTo(b.start));
      saveTasks.add(_queueSaveSchedules());
    }
    if (noteFolders != null) {
      _noteFolders = List<NoteFolder>.from(noteFolders);
      saveTasks.add(_queueSaveNoteFolders());
    }
    if (notes != null) {
      _notes = List<Note>.from(notes);
      saveTasks.add(_queueSaveNotes());
    }
    if (noteRevisions != null) {
      _noteRevisions = List<NoteRevision>.from(noteRevisions);
      _noteRevisionContentCache.clear();
      _noteTimelineCache.clear();
      saveTasks.add(_queueSaveNoteRevisions());
    }
    if (todoLists != null) {
      _todoLists = List<TodoList>.from(todoLists);
      saveTasks.add(_queueSaveTodoLists());
    }
    if (storageV2Active &&
        (noteFolders != null || notes != null || noteRevisions != null)) {
      _usingStorageV2 = true;
      await _syncStorageV2NoteFilesWithNotes();
      saveTasks.add(_persistStorageV2NotesData());
    }
    await Future.wait(saveTasks);
    notifyListeners();
  }

  NoteEditProposal? getNoteEditProposal(String noteId) {
    return _noteEditProposals[noteId];
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scheduleJson = prefs.getString(_scheduleKey);
      if (scheduleJson != null) {
        final items = jsonDecode(scheduleJson) as List<dynamic>;
        final schedules = <ScheduleItem>[];
        for (final item in items) {
          try {
            schedules.add(ScheduleItem.fromJson(item as Map<String, dynamic>));
          } catch (e) {
            debugPrint('跳过损坏的日程记录: $e');
          }
        }
        _schedules = schedules..sort((a, b) => a.start.compareTo(b.start));
      }
      await _refreshScheduleWidget();
      await _rescheduleScheduleNotifications();
      final notesJson = prefs.getString(_notesKey);
      if (notesJson != null) {
        final items = jsonDecode(notesJson) as List<dynamic>;
        final notes = <Note>[];
        for (final item in items) {
          try {
            notes.add(Note.fromJson(item as Map<String, dynamic>));
          } catch (e) {
            debugPrint('跳过损坏的笔记记录: $e');
          }
        }
        _notes = notes;
      }
      final noteFoldersJson = prefs.getString(_noteFoldersKey);
      if (noteFoldersJson != null) {
        final items = jsonDecode(noteFoldersJson) as List<dynamic>;
        final folders = <NoteFolder>[];
        for (final item in items) {
          try {
            folders.add(NoteFolder.fromJson(item as Map<String, dynamic>));
          } catch (e) {
            debugPrint('跳过损坏的笔记文件夹记录: $e');
          }
        }
        _noteFolders = folders;
      }
      final noteRevisionsJson = prefs.getString(_noteRevisionsKey);
      if (noteRevisionsJson != null) {
        final items = jsonDecode(noteRevisionsJson) as List<dynamic>;
        final revisions = <NoteRevision>[];
        for (final item in items) {
          try {
            revisions.add(NoteRevision.fromJson(item as Map<String, dynamic>));
          } catch (e) {
            debugPrint('跳过损坏的笔记时间线记录: $e');
          }
        }
        _noteRevisions = revisions;
      }
      final normalizedRevisions = _normalizeNoteRevisionState();
      final cleanedFolderRefs = _removeMissingNoteFolderReferences();
      if (normalizedRevisions) {
        await _queueSaveNoteRevisions();
      }
      if (normalizedRevisions || cleanedFolderRefs) {
        await _queueSaveNotes();
      }
      final noteEditProposalsJson = prefs.getString(_noteEditProposalsKey);
      if (noteEditProposalsJson != null) {
        final items = jsonDecode(noteEditProposalsJson) as List<dynamic>;
        _noteEditProposals.clear();
        for (final item in items) {
          try {
            final proposal = NoteEditProposal.fromJson(
              item as Map<String, dynamic>,
            );
            if (_isUsableNoteEditProposal(proposal)) {
              _noteEditProposals[proposal.noteId] = proposal;
            }
          } catch (e) {
            debugPrint('跳过损坏的笔记修改建议记录: $e');
          }
        }
      }
      final todoListsJson = prefs.getString(_todoListsKey);
      if (todoListsJson != null) {
        final items = jsonDecode(todoListsJson) as List<dynamic>;
        final todoLists = <TodoList>[];
        for (final item in items) {
          try {
            todoLists.add(TodoList.fromJson(item as Map<String, dynamic>));
          } catch (e) {
            debugPrint('跳过损坏的待办清单记录: $e');
          }
        }
        _todoLists = todoLists;
      }
      if ((prefs.getInt('storage_schema_version') ?? 1) >=
          StorageMigrationService.currentSchemaVersion) {
        try {
          await _loadStorageV2FeatureData();
          await _loadStorageV2Notes();
        } catch (e) {
          debugPrint('加载新版笔记存储失败，保留旧版笔记数据: $e');
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('加载功能数据失败: $e');
      _schedules = [];
      _notes = [];
      _noteRevisions = [];
      _noteFolders = [];
      _noteEditProposals.clear();
      _todoLists = [];
      notifyListeners();
    }
  }

  Future<void> _queueSaveSchedules() {
    final snapshot = List<ScheduleItem>.from(_schedules);
    _scheduleSaveQueue = _scheduleSaveQueue.then(
      (_) => _saveSchedulesSnapshot(snapshot),
    );
    return _scheduleSaveQueue;
  }

  Future<void> _saveSchedulesSnapshot(List<ScheduleItem> snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storageV2Active = await _storageV2ActiveForSave(prefs);
      if (_usingStorageV2 || storageV2Active) {
        _usingStorageV2 = _usingStorageV2 || storageV2Active;
        await _storageV2.writeDataFile('schedules.json', {
          'schedules': snapshot.map((e) => e.toJson()).toList(),
        });
        await _refreshScheduleWidget();
        await _rescheduleScheduleNotifications();
        return;
      }
      await prefs.setString(
        _scheduleKey,
        jsonEncode(snapshot.map((e) => e.toJson()).toList()),
      );
      await _refreshScheduleWidget();
      await _rescheduleScheduleNotifications();
    } catch (e) {
      debugPrint('保存日程失败: $e');
    }
  }

  Future<void> _refreshScheduleWidget() async {
    if (!Platform.isAndroid) return;
    try {
      await _scheduleWidgetChannel.invokeMethod<void>('refresh');
    } catch (e) {
      debugPrint('刷新日程小组件失败: $e');
    }
  }

  Future<void> _rescheduleScheduleNotifications() async {
    if (!Platform.isAndroid) return;
    try {
      await _scheduleWidgetChannel.invokeMethod<void>(
        'rescheduleNotifications',
      );
    } catch (e) {
      debugPrint('重新安排日程通知失败: $e');
    }
  }

  Future<bool> _storageV2ActiveForSave(SharedPreferences prefs) async {
    return (prefs.getInt('storage_schema_version') ?? 1) >=
            StorageMigrationService.currentSchemaVersion &&
        await _storageV2.exists();
  }

  Future<void> _queueSaveNotes() {
    final snapshot = List<Note>.from(_notes);
    _noteSaveQueue = _noteSaveQueue.then((_) => _saveNotesSnapshot(snapshot));
    return _noteSaveQueue;
  }

  Future<void> _queueSaveNoteFolders() {
    final snapshot = List<NoteFolder>.from(_noteFolders);
    _noteFolderSaveQueue = _noteFolderSaveQueue.then(
      (_) => _saveNoteFoldersSnapshot(snapshot),
    );
    return _noteFolderSaveQueue;
  }

  Future<void> _queueSaveNoteRevisions() {
    final snapshot = List<NoteRevision>.from(_noteRevisions);
    _noteRevisionSaveQueue = _noteRevisionSaveQueue.then(
      (_) => _saveNoteRevisionsSnapshot(snapshot),
    );
    return _noteRevisionSaveQueue;
  }

  Future<void> _queueSaveNoteEditProposals() {
    final snapshot = List<NoteEditProposal>.from(_noteEditProposals.values);
    _noteEditProposalSaveQueue = _noteEditProposalSaveQueue.then(
      (_) => _saveNoteEditProposalsSnapshot(snapshot),
    );
    return _noteEditProposalSaveQueue;
  }

  Future<void> _saveNoteFoldersSnapshot(List<NoteFolder> snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (await _storageV2ActiveForSave(prefs)) return;
      await prefs.setString(
        _noteFoldersKey,
        jsonEncode(snapshot.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('保存笔记文件夹失败: $e');
    }
  }

  Future<void> _saveNoteRevisionsSnapshot(List<NoteRevision> snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (await _storageV2ActiveForSave(prefs)) return;
      await prefs.setString(
        _noteRevisionsKey,
        jsonEncode(snapshot.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('保存笔记时间线失败: $e');
    }
  }

  Future<void> _saveNotesSnapshot(List<Note> snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (await _storageV2ActiveForSave(prefs)) return;
      await prefs.setString(
        _notesKey,
        jsonEncode(snapshot.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('保存笔记失败: $e');
    }
  }

  Future<void> _saveNoteEditProposalsSnapshot(
    List<NoteEditProposal> snapshot,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (await _storageV2ActiveForSave(prefs)) return;
      await prefs.setString(
        _noteEditProposalsKey,
        jsonEncode(snapshot.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('保存笔记修改建议失败: $e');
    }
  }

  bool _isUsableNoteEditProposal(NoteEditProposal proposal) {
    if (proposal.blocks.isEmpty || proposal.baseContentHash.isEmpty) {
      return false;
    }
    final note = getNote(proposal.noteId);
    if (note == null) return false;
    final baseRevisionId = proposal.baseRevisionId;
    if (baseRevisionId != null) {
      final revision = getNoteRevision(baseRevisionId);
      if (revision == null || revision.noteId != proposal.noteId) return false;
    }
    return true;
  }

  bool _removeMissingNoteFolderReferences() {
    final folderIds = _noteFolders.map((folder) => folder.id).toSet();
    var changed = false;
    _notes = _notes.map((note) {
      final folderId = note.folderId;
      if (folderId == null || folderIds.contains(folderId)) return note;
      changed = true;
      return note.copyWith(folderId: null, preserveUpdatedAt: true);
    }).toList();
    return changed;
  }

  Future<void> _loadStorageV2FeatureData() async {
    if (!await _storageV2.exists()) return;
    try {
      final schedulesJson = await _storageV2.loadDataFile('schedules.json');
      final schedules = <ScheduleItem>[];
      for (final item
          in schedulesJson['schedules'] as List<dynamic>? ?? const []) {
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
      _schedules = schedules..sort((a, b) => a.start.compareTo(b.start));
    } catch (e) {
      debugPrint('加载新版日程失败: $e');
    }

    try {
      final todoJson = await _storageV2.loadDataFile('todo_lists.json');
      final itemsByListId = <String, List<TodoItem>>{};
      for (final item in todoJson['todoItems'] as List<dynamic>? ?? const []) {
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
      for (final item in todoJson['todoLists'] as List<dynamic>? ?? const []) {
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
      _todoLists = lists;
    } catch (e) {
      debugPrint('加载新版待办清单失败: $e');
    }
  }

  Future<void> _loadStorageV2Notes() async {
    if (!await _storageV2.exists()) return;
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
    _storageV2PagesByNoteId = {};
    for (final page in pages) {
      (_storageV2PagesByNoteId[page.noteId] ??= []).add(page);
    }

    final notes = <Note>[];
    _activeStorageV2PageIds = {};
    for (final item in data['notes'] as List<dynamic>? ?? const []) {
      try {
        if (item is! Map) continue;
        final json = Map<String, dynamic>.from(item);
        final id = json['id'] as String;
        final notePages = _storageV2PagesByNoteId[id] ?? const [];
        final currentPageId = json['currentPageId'] as String?;
        final page = notePages.firstWhere(
          (page) => page.id == currentPageId,
          orElse: () => notePages.isEmpty
              ? throw const FormatException('note has no pages')
              : notePages.first,
        );
        _activeStorageV2PageIds[id] = page.id;
        notes.add(
          Note(
            id: id,
            title: json['title'] as String? ?? '',
            content: await _storageV2.readNotePage(page),
            currentRevisionId: json['currentRevisionId'] as String?,
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

    final proposals = <String, NoteEditProposal>{};
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
    for (final item in data['editProposals'] as List<dynamic>? ?? const []) {
      try {
        if (item is! Map) continue;
        final json = Map<String, dynamic>.from(item);
        final proposal = NoteEditProposal(
          id: json['id'] as String,
          noteId: json['noteId'] as String,
          baseRevisionId: json['baseRevisionId'] as String?,
          baseContentHash: json['baseContentHash'] as String? ?? '',
          createdAt: DateTime.parse(json['createdAt'] as String),
          blocks: blocksByProposal[json['id'] as String] ?? const [],
        );
        if (proposal.blocks.isNotEmpty && proposal.baseContentHash.isNotEmpty) {
          proposals[proposal.noteId] = proposal;
        }
      } catch (e) {
        debugPrint('跳过损坏的新版笔记建议记录: $e');
      }
    }

    _usingStorageV2 = true;
    _noteFolders = folders;
    _notes = notes;
    _noteRevisions = revisions;
    _noteEditProposals
      ..clear()
      ..addAll(proposals);
    _noteRevisionContentCache.clear();
    _noteTimelineCache.clear();
    _normalizeNoteRevisionState();
    _removeMissingNoteFolderReferences();
  }

  Future<void> selectNotePage(String noteId, String pageId) async {
    if (!_usingStorageV2) return;
    final pages = _storageV2PagesByNoteId[noteId] ?? const [];
    final page = pages.firstWhere(
      (page) => page.id == pageId,
      orElse: () => throw StateError('分页不存在'),
    );
    final index = _notes.indexWhere((note) => note.id == noteId);
    if (index == -1) return;
    final content = await _storageV2.readNotePage(page);
    _activeStorageV2PageIds[noteId] = page.id;
    _notes[index] = _notes[index].copyWith(
      content: content,
      preserveUpdatedAt: true,
    );
    await _persistStorageV2NotesData();
    notifyListeners();
  }

  Future<String?> addNotePage(String noteId, String title) async {
    if (!_usingStorageV2) return null;
    final note = getNote(noteId);
    if (note == null) return null;
    final pages = _storageV2PagesByNoteId[noteId] ??= [];
    final usedFileNames = pages.map((page) => page.fileName).toSet();
    final base = safeExportFileName(title, fallback: 'page');
    var fileName = '$base.md';
    var suffix = 1;
    while (usedFileNames.contains(fileName)) {
      fileName = '${base}_$suffix.md';
      suffix++;
    }
    final now = DateTime.now();
    final page = StorageV2NotePage(
      id: '${noteId}_page_${_uuid.v4()}',
      noteId: noteId,
      title: title.isEmpty ? '新分页' : title,
      fileName: fileName,
      relativePath: 'notes/$noteId/$fileName',
      sortOrder: pages.length,
      createdAt: now,
      updatedAt: now,
    );
    pages.add(page);
    _activeStorageV2PageIds[noteId] = page.id;
    final content = '# ${page.title}\n';
    await _storageV2.writeNotePage(page, content);
    final index = _notes.indexWhere((item) => item.id == noteId);
    if (index != -1) {
      _notes[index] = note.copyWith(content: content);
    }
    await _persistStorageV2NotesData();
    await _queueSaveNotes();
    notifyListeners();
    return page.id;
  }

  Future<void> renameNotePage(
    String noteId,
    String pageId,
    String title,
  ) async {
    if (!_usingStorageV2) return;
    final pages = _storageV2PagesByNoteId[noteId];
    if (pages == null) return;
    final index = pages.indexWhere((page) => page.id == pageId);
    if (index == -1) return;
    final page = pages[index];
    pages[index] = StorageV2NotePage(
      id: page.id,
      noteId: page.noteId,
      title: title.isEmpty ? page.title : title,
      fileName: page.fileName,
      relativePath: page.relativePath,
      sortOrder: page.sortOrder,
      createdAt: page.createdAt,
      updatedAt: DateTime.now(),
    );
    await _persistStorageV2NotesData();
    notifyListeners();
  }

  Future<bool> deleteNotePage(String noteId, String pageId) async {
    if (!_usingStorageV2) return false;
    final pages = _storageV2PagesByNoteId[noteId];
    if (pages == null || pages.length <= 1) return false;
    final index = pages.indexWhere((page) => page.id == pageId);
    if (index == -1) return false;
    final removed = pages.removeAt(index);
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      pages[i] = StorageV2NotePage(
        id: page.id,
        noteId: page.noteId,
        title: page.title,
        fileName: page.fileName,
        relativePath: page.relativePath,
        sortOrder: i,
        createdAt: page.createdAt,
        updatedAt: page.updatedAt,
      );
    }
    if (_activeStorageV2PageIds[noteId] == pageId) {
      _activeStorageV2PageIds[noteId] = pages.first.id;
      final noteIndex = _notes.indexWhere((note) => note.id == noteId);
      if (noteIndex != -1) {
        _notes[noteIndex] = _notes[noteIndex].copyWith(
          content: await _storageV2.readNotePage(pages.first),
          preserveUpdatedAt: true,
        );
      }
    }
    _noteEditProposals.remove(noteId);
    try {
      await _storageV2.deleteFile(removed.relativePath);
    } catch (_) {}
    await _persistStorageV2NotesData();
    await _queueSaveNotes();
    await _queueSaveNoteRevisions();
    notifyListeners();
    return true;
  }

  Future<void> _persistStorageV2CurrentPageContent(
    String noteId,
    String content,
  ) async {
    if (!_usingStorageV2) return;
    final page = activeNotePage(noteId);
    if (page == null) return;
    await _storageV2.writeNotePage(page, content);
    final pages = _storageV2PagesByNoteId[noteId];
    if (pages == null) return;
    final index = pages.indexWhere((item) => item.id == page.id);
    if (index == -1) return;
    pages[index] = StorageV2NotePage(
      id: page.id,
      noteId: page.noteId,
      title: page.title,
      fileName: page.fileName,
      relativePath: page.relativePath,
      sortOrder: page.sortOrder,
      createdAt: page.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _syncStorageV2NoteFilesWithNotes() async {
    final noteIds = _notes.map((note) => note.id).toSet();
    _storageV2PagesByNoteId.removeWhere(
      (noteId, _) => !noteIds.contains(noteId),
    );
    _activeStorageV2PageIds.removeWhere(
      (noteId, _) => !noteIds.contains(noteId),
    );
    for (final note in _notes) {
      final pages = _storageV2PagesByNoteId[note.id];
      StorageV2NotePage page;
      if (pages == null || pages.isEmpty) {
        final now = DateTime.now();
        final fileName =
            '${safeExportFileName(note.title, fallback: 'note')}.md';
        page = StorageV2NotePage(
          id: '${note.id}_page_0',
          noteId: note.id,
          title: note.title.isEmpty ? '未命名分页' : note.title,
          fileName: fileName,
          relativePath: 'notes/${note.id}/$fileName',
          sortOrder: 0,
          createdAt: note.createdAt,
          updatedAt: now,
        );
        _storageV2PagesByNoteId[note.id] = [page];
      } else {
        final activeId = _activeStorageV2PageIds[note.id];
        page = pages.firstWhere(
          (item) => item.id == activeId,
          orElse: () => pages.first,
        );
      }
      _activeStorageV2PageIds[note.id] = page.id;
      await _storageV2.writeNotePage(page, note.content);
    }
  }

  Future<void> _persistStorageV2NotesData() async {
    if (!_usingStorageV2) return;
    final proposalRows = <Map<String, dynamic>>[];
    final proposalBlockRows = <Map<String, dynamic>>[];
    for (final proposal in _noteEditProposals.values) {
      proposalRows.add({
        'id': proposal.id,
        'noteId': proposal.noteId,
        'pageId': _activeStorageV2PageIds[proposal.noteId],
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
    final data = <String, dynamic>{
      'folders': _noteFolders.map((folder) => folder.toJson()).toList(),
      'notes': _notes.map((note) {
        return {
          'id': note.id,
          'title': note.title,
          if (note.folderId != null) 'folderId': note.folderId,
          if (note.currentRevisionId != null)
            'currentRevisionId': note.currentRevisionId,
          'currentPageId': _activeStorageV2PageIds[note.id],
          'createdAt': note.createdAt.toIso8601String(),
          'updatedAt': note.updatedAt.toIso8601String(),
          'wrap': note.wrap,
        };
      }).toList(),
      'pages': _storageV2PagesByNoteId.values
          .expand((pages) => pages)
          .map((page) => page.toJson())
          .toList(),
      'revisions': _noteRevisions.map((revision) {
        return {
          'id': revision.id,
          'noteId': revision.noteId,
          'pageId': _activeStorageV2PageIds[revision.noteId],
          if (revision.parentRevisionId != null)
            'parentRevisionId': revision.parentRevisionId,
          'savedAt': revision.savedAt.toIso8601String(),
          'deltaStart': revision.delta.start,
          'deletedText': revision.delta.deletedText,
          'insertedText': revision.delta.insertedText,
        };
      }).toList(),
      'editProposals': proposalRows,
      'editBlocks': proposalBlockRows,
    };
    await _storageV2.writeNotesData(data);
  }

  Future<void> _queueSaveTodoLists() {
    final snapshot = List<TodoList>.from(_todoLists);
    _todoListSaveQueue = _todoListSaveQueue.then(
      (_) => _saveTodoListsSnapshot(snapshot),
    );
    return _todoListSaveQueue;
  }

  Future<void> _saveTodoListsSnapshot(List<TodoList> snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storageV2Active = await _storageV2ActiveForSave(prefs);
      if (_usingStorageV2 || storageV2Active) {
        _usingStorageV2 = _usingStorageV2 || storageV2Active;
        final todoLists = <Map<String, dynamic>>[];
        final todoItems = <Map<String, dynamic>>[];
        for (final list in snapshot) {
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
      await prefs.setString(
        _todoListsKey,
        jsonEncode(snapshot.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('保存待办清单失败: $e');
    }
  }

  Future<String> addSchedule(
    String title,
    DateTime start,
    DateTime end, {
    String? note,
    String kind = ScheduleItem.kindSchedule,
  }) async {
    final effectiveEnd = kind == ScheduleItem.kindTask
        ? start.add(const Duration(minutes: 1))
        : end;
    final schedule = ScheduleItem(
      id: _uuid.v4(),
      title: title,
      start: start,
      end: effectiveEnd,
      note: note,
      kind: kind,
    );
    _schedules.add(schedule);
    _schedules.sort((a, b) => a.start.compareTo(b.start));
    await _queueSaveSchedules();
    notifyListeners();
    return schedule.id;
  }

  Future<void> updateSchedule(ScheduleItem schedule) async {
    final index = _schedules.indexWhere((s) => s.id == schedule.id);
    if (index == -1) return;
    _schedules[index] = schedule;
    _schedules.sort((a, b) => a.start.compareTo(b.start));
    await _queueSaveSchedules();
    notifyListeners();
  }

  Future<void> deleteSchedule(String id) async {
    final before = _schedules.length;
    _schedules.removeWhere((s) => s.id == id);
    if (_schedules.length == before) return;
    await _queueSaveSchedules();
    notifyListeners();
  }

  ScheduleItem? getSchedule(String id) {
    try {
      return _schedules.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<String> addNote(String title, {String? folderId}) {
    return addNoteWithContent(title, '', folderId: folderId);
  }

  Future<String> addNoteWithContent(
    String title,
    String content, {
    String? folderId,
  }) async {
    final now = DateTime.now();
    final initialRevision = content.isEmpty
        ? null
        : NoteRevision(
            id: _uuid.v4(),
            noteId: '',
            parentRevisionId: null,
            savedAt: now,
            delta: NoteTextDelta.between('', content),
          );
    final note = Note(
      id: _uuid.v4(),
      title: title,
      content: content,
      currentRevisionId: initialRevision?.id,
      folderId: _noteFolders.any((f) => f.id == folderId) ? folderId : null,
      createdAt: now,
      updatedAt: now,
    );
    if (initialRevision != null) {
      _noteRevisions.insert(
        0,
        NoteRevision(
          id: initialRevision.id,
          noteId: note.id,
          parentRevisionId: null,
          savedAt: now,
          delta: initialRevision.delta,
        ),
      );
      _noteRevisionContentCache[initialRevision.id] = content;
    }
    _notes.insert(0, note);
    if (_usingStorageV2) {
      final pageId = '${note.id}_page_0';
      final fileName = '${safeExportFileName(title, fallback: 'note')}.md';
      final page = StorageV2NotePage(
        id: pageId,
        noteId: note.id,
        title: title.isEmpty ? '未命名分页' : title,
        fileName: fileName,
        relativePath: 'notes/${note.id}/$fileName',
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      );
      _storageV2PagesByNoteId[note.id] = [page];
      _activeStorageV2PageIds[note.id] = pageId;
      await _storageV2.writeNotePage(page, content);
      await _persistStorageV2NotesData();
    }
    await _queueSaveNotes();
    if (initialRevision != null) await _queueSaveNoteRevisions();
    notifyListeners();
    return note.id;
  }

  Note? getNote(String id) {
    try {
      return _notes.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }

  NoteRevision? getNoteRevision(String revisionId) {
    try {
      return _noteRevisions.firstWhere((revision) => revision.id == revisionId);
    } catch (_) {
      return null;
    }
  }

  List<NoteRevision> getNoteTimeline(String noteId) {
    final cached = _noteTimelineCache[noteId];
    if (cached != null) return List.unmodifiable(cached);
    final revisions = _noteRevisions
        .where((revision) => revision.noteId == noteId)
        .toList();
    revisions.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    _noteTimelineCache[noteId] = List.unmodifiable(revisions);
    return List.unmodifiable(revisions);
  }

  Set<String> getNoteCurrentRevisionPath(String noteId) {
    final note = getNote(noteId);
    final currentRevisionId = note?.currentRevisionId;
    if (currentRevisionId == null) return const <String>{};
    final path = <String>{};
    String? revisionId = currentRevisionId;
    while (revisionId != null && path.add(revisionId)) {
      final revision = getNoteRevision(revisionId);
      if (revision == null || revision.noteId != noteId) break;
      revisionId = revision.parentRevisionId;
    }
    return path;
  }

  String getNoteContentAtRevision(String noteId, String? revisionId) {
    if (revisionId == null) {
      return getNote(noteId)?.content ?? '';
    }
    return _getNoteContentAtRevision(noteId, revisionId, <String>{});
  }

  String _getNoteContentAtRevision(
    String noteId,
    String revisionId,
    Set<String> visited,
  ) {
    if (!visited.add(revisionId)) return '';
    final cached = _noteRevisionContentCache[revisionId];
    if (cached != null) return cached;
    final revision = getNoteRevision(revisionId);
    if (revision == null || revision.noteId != noteId) return '';
    final parentContent = revision.parentRevisionId == null
        ? ''
        : _getNoteContentAtRevision(
            noteId,
            revision.parentRevisionId!,
            visited,
          );
    final content = revision.delta.apply(parentContent);
    _noteRevisionContentCache[revisionId] = content;
    return content;
  }

  bool _normalizeNoteRevisionState() {
    final revisionById = {
      for (final revision in _noteRevisions) revision.id: revision,
    };
    final validChainCache = <String, bool>{};
    final previousRevisionCount = _noteRevisions.length;
    var notesChanged = false;

    bool hasValidChain(String revisionId, Set<String> visiting) {
      final cached = validChainCache[revisionId];
      if (cached != null) return cached;
      final revision = revisionById[revisionId];
      if (revision == null) return validChainCache[revisionId] = false;
      if (!visiting.add(revisionId)) return validChainCache[revisionId] = false;
      final parentId = revision.parentRevisionId;
      if (parentId == null) {
        visiting.remove(revisionId);
        return validChainCache[revisionId] = true;
      }
      final parent = revisionById[parentId];
      final valid =
          parent != null &&
          parent.noteId == revision.noteId &&
          hasValidChain(parentId, visiting);
      visiting.remove(revisionId);
      return validChainCache[revisionId] = valid;
    }

    _noteRevisions = _noteRevisions
        .where((revision) => hasValidChain(revision.id, <String>{}))
        .toList();
    final validRevisionIds = _noteRevisions
        .map((revision) => revision.id)
        .toSet();
    _notes = _notes.map((note) {
      final currentRevisionId = note.currentRevisionId;
      if (currentRevisionId == null ||
          validRevisionIds.contains(currentRevisionId)) {
        return note;
      }
      notesChanged = true;
      return note.copyWith(currentRevisionId: null, preserveUpdatedAt: true);
    }).toList();
    _noteRevisionContentCache.clear();
    _noteTimelineCache.clear();
    return _noteRevisions.length != previousRevisionCount || notesChanged;
  }

  void _clearNoteTimelineCache(String noteId) {
    _noteTimelineCache.remove(noteId);
  }

  Future<NoteRevision?> saveNoteContent(
    String noteId,
    String content, {
    String? baseRevisionId,
  }) async {
    final index = _notes.indexWhere((note) => note.id == noteId);
    if (index == -1) return null;
    final note = _notes[index];
    final requestedParentRevisionId = baseRevisionId ?? note.currentRevisionId;
    final requestedParent = requestedParentRevisionId == null
        ? null
        : getNoteRevision(requestedParentRevisionId);
    var parentRevisionId =
        requestedParent != null && requestedParent.noteId == noteId
        ? requestedParentRevisionId
        : note.currentRevisionId;
    var baseContent = parentRevisionId == null
        ? note.content
        : getNoteContentAtRevision(noteId, parentRevisionId);
    NoteRevision? bootstrappedRoot;

    if (parentRevisionId == null && note.content.isNotEmpty) {
      final now = DateTime.now();
      final rootRevision = NoteRevision(
        id: _uuid.v4(),
        noteId: note.id,
        parentRevisionId: null,
        savedAt: now,
        delta: NoteTextDelta.between('', note.content),
      );
      bootstrappedRoot = rootRevision;
      _noteRevisions.insert(0, rootRevision);
      _noteRevisionContentCache[rootRevision.id] = note.content;
      _clearNoteTimelineCache(note.id);
      parentRevisionId = rootRevision.id;
      baseContent = note.content;
      _notes[index] = note.copyWith(
        currentRevisionId: rootRevision.id,
        preserveUpdatedAt: true,
      );
    }

    final currentRevisionId = _notes[index].currentRevisionId;
    if (baseRevisionId == currentRevisionId && note.content == content) {
      if (bootstrappedRoot != null) {
        await _persistStorageV2NotesData();
        await _queueSaveNoteRevisions();
        await _queueSaveNotes();
        notifyListeners();
      }
      return currentRevisionId == null
          ? null
          : getNoteRevision(currentRevisionId);
    }
    if (baseRevisionId != null &&
        baseContent == content &&
        currentRevisionId == baseRevisionId) {
      return getNoteRevision(baseRevisionId);
    }
    if (baseRevisionId == null &&
        currentRevisionId != null &&
        baseContent == content) {
      if (bootstrappedRoot != null) {
        await _persistStorageV2NotesData();
        await _queueSaveNoteRevisions();
        await _queueSaveNotes();
        notifyListeners();
      }
      return getNoteRevision(currentRevisionId);
    }

    final now = DateTime.now();
    final revision = NoteRevision(
      id: _uuid.v4(),
      noteId: note.id,
      parentRevisionId: parentRevisionId,
      savedAt: now,
      delta: NoteTextDelta.between(baseContent, content),
    );
    _noteRevisions.insert(0, revision);
    _noteRevisionContentCache[revision.id] = content;
    _clearNoteTimelineCache(note.id);
    final removedProposal = _noteEditProposals.remove(note.id) != null;
    _notes[index] = note.copyWith(
      content: content,
      currentRevisionId: revision.id,
    );
    await _persistStorageV2CurrentPageContent(note.id, content);
    await _persistStorageV2NotesData();
    await _queueSaveNoteRevisions();
    await _queueSaveNotes();
    if (removedProposal) await _queueSaveNoteEditProposals();
    notifyListeners();
    return revision;
  }

  Future<void> updateNote(Note note) async {
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index == -1) return;
    final contentChanged = _notes[index].content != note.content;
    final removedProposal =
        contentChanged && _noteEditProposals.remove(note.id) != null;
    _notes[index] = note;
    if (contentChanged) {
      await _persistStorageV2CurrentPageContent(note.id, note.content);
    }
    await _persistStorageV2NotesData();
    await _queueSaveNotes();
    if (removedProposal) await _queueSaveNoteEditProposals();
    notifyListeners();
  }

  Future<void> reorderNotesInFolder(
    String? folderId,
    int oldIndex,
    int newIndex,
  ) async {
    final indexes = <int>[];
    for (var i = 0; i < _notes.length; i++) {
      if (_notes[i].folderId == folderId) indexes.add(i);
    }
    if (oldIndex < 0 || oldIndex >= indexes.length) return;
    if (newIndex < 0 || newIndex > indexes.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final folderNotes = indexes.map((i) => _notes[i]).toList();
    final note = folderNotes.removeAt(oldIndex);
    folderNotes.insert(newIndex, note);
    for (var i = 0; i < indexes.length; i++) {
      _notes[indexes[i]] = folderNotes[i];
    }
    await _persistStorageV2NotesData();
    await _queueSaveNotes();
    notifyListeners();
  }

  Future<void> deleteNote(String id) async {
    final before = _notes.length;
    _notes.removeWhere((n) => n.id == id);
    if (_notes.length == before) return;
    final deletedRevisionIds = _noteRevisions
        .where((revision) => revision.noteId == id)
        .map((revision) => revision.id)
        .toSet();
    _noteRevisions.removeWhere((revision) => revision.noteId == id);
    _clearNoteTimelineCache(id);
    final removedProposal = _noteEditProposals.remove(id) != null;
    _noteRevisionContentCache.removeWhere(
      (revisionId, _) => deletedRevisionIds.contains(revisionId),
    );
    _storageV2PagesByNoteId.remove(id);
    _activeStorageV2PageIds.remove(id);
    await _persistStorageV2NotesData();
    await _queueSaveNotes();
    await _queueSaveNoteRevisions();
    if (removedProposal) await _queueSaveNoteEditProposals();
    notifyListeners();
  }

  Future<NoteRevision?> restoreNoteRevision(
    String noteId,
    String revisionId,
  ) async {
    final revision = getNoteRevision(revisionId);
    if (revision == null || revision.noteId != noteId) return null;
    final content = getNoteContentAtRevision(noteId, revisionId);
    return saveNoteContent(noteId, content, baseRevisionId: revisionId);
  }

  Future<bool> deleteNoteRevision(String noteId, String revisionId) async {
    final revision = getNoteRevision(revisionId);
    if (revision == null || revision.noteId != noteId) return false;
    if (getNoteCurrentRevisionPath(noteId).contains(revisionId)) return false;
    return _deleteNoteRevisionSet(noteId, {revisionId});
  }

  int countNoteBranchRevisions(String noteId, String parentRevisionId) {
    final currentPath = getNoteCurrentRevisionPath(noteId);
    final branchRoots = _noteRevisions
        .where(
          (revision) =>
              revision.noteId == noteId &&
              revision.parentRevisionId == parentRevisionId &&
              !currentPath.contains(revision.id),
        )
        .map((revision) => revision.id)
        .toSet();
    if (branchRoots.isEmpty) return 0;
    return _collectRevisionDescendants(noteId, branchRoots).length;
  }

  Future<int> deleteNoteBranchesFromRevision(
    String noteId,
    String parentRevisionId,
  ) async {
    final parent = getNoteRevision(parentRevisionId);
    if (parent == null || parent.noteId != noteId) return 0;
    final currentPath = getNoteCurrentRevisionPath(noteId);
    final branchRoots = _noteRevisions
        .where(
          (revision) =>
              revision.noteId == noteId &&
              revision.parentRevisionId == parentRevisionId &&
              !currentPath.contains(revision.id),
        )
        .map((revision) => revision.id)
        .toSet();
    if (branchRoots.isEmpty) return 0;
    final descendants = _collectRevisionDescendants(noteId, branchRoots);
    final deleted = await _deleteNoteRevisionSet(noteId, descendants);
    return deleted ? descendants.length : 0;
  }

  Set<String> _collectRevisionDescendants(String noteId, Set<String> roots) {
    final descendants = <String>{...roots};
    var changed = true;
    while (changed) {
      changed = false;
      for (final item in _noteRevisions) {
        final parentId = item.parentRevisionId;
        if (item.noteId == noteId &&
            parentId != null &&
            descendants.contains(parentId) &&
            descendants.add(item.id)) {
          changed = true;
        }
      }
    }
    return descendants;
  }

  Future<bool> _deleteNoteRevisionSet(
    String noteId,
    Set<String> revisionIds,
  ) async {
    if (revisionIds.isEmpty) return false;
    final currentPath = getNoteCurrentRevisionPath(noteId);
    if (revisionIds.any(currentPath.contains)) return false;
    final descendants = _collectRevisionDescendants(noteId, revisionIds);
    if (descendants.any(currentPath.contains)) return false;
    _noteRevisions.removeWhere((item) => descendants.contains(item.id));
    _noteRevisionContentCache.removeWhere((id, _) => descendants.contains(id));
    _clearNoteTimelineCache(noteId);
    await _persistStorageV2NotesData();
    await _queueSaveNoteRevisions();
    notifyListeners();
    return true;
  }

  Future<void> setNoteEditProposal(NoteEditProposal proposal) async {
    _noteEditProposals[proposal.noteId] = proposal;
    await _persistStorageV2NotesData();
    await _queueSaveNoteEditProposals();
    notifyListeners();
  }

  Future<void> removeNoteEditProposal(String noteId) async {
    if (_noteEditProposals.remove(noteId) == null) return;
    await _persistStorageV2NotesData();
    await _queueSaveNoteEditProposals();
    notifyListeners();
  }

  Future<String> addNoteFolder(String title) async {
    final now = DateTime.now();
    final folder = NoteFolder(
      id: _uuid.v4(),
      title: title,
      createdAt: now,
      updatedAt: now,
    );
    _noteFolders.insert(0, folder);
    await _persistStorageV2NotesData();
    await _queueSaveNoteFolders();
    notifyListeners();
    return folder.id;
  }

  NoteFolder? getNoteFolder(String id) {
    try {
      return _noteFolders.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateNoteFolder(NoteFolder folder) async {
    final index = _noteFolders.indexWhere((f) => f.id == folder.id);
    if (index == -1) return;
    _noteFolders[index] = folder;
    await _persistStorageV2NotesData();
    await _queueSaveNoteFolders();
    notifyListeners();
  }

  Future<void> reorderNoteFolders(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _noteFolders.length) return;
    if (newIndex < 0 || newIndex > _noteFolders.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final folder = _noteFolders.removeAt(oldIndex);
    _noteFolders.insert(newIndex, folder);
    await _persistStorageV2NotesData();
    await _queueSaveNoteFolders();
    notifyListeners();
  }

  Future<void> deleteNoteFolder(String id) async {
    final before = _noteFolders.length;
    _noteFolders.removeWhere((f) => f.id == id);
    if (_noteFolders.length == before) return;
    _notes = _notes
        .map(
          (note) => note.folderId == id ? note.copyWith(folderId: null) : note,
        )
        .toList();
    await _persistStorageV2NotesData();
    await _queueSaveNoteFolders();
    await _queueSaveNotes();
    notifyListeners();
  }

  Future<String> addTodoList(String title) {
    return addTodoListWithItems(title, <TodoItem>[]);
  }

  Future<String> addTodoListWithItems(
    String title,
    List<TodoItem> items,
  ) async {
    final now = DateTime.now();
    final list = TodoList(
      id: _uuid.v4(),
      title: title,
      items: items,
      createdAt: now,
      updatedAt: now,
    );
    _todoLists.insert(0, list);
    await _queueSaveTodoLists();
    notifyListeners();
    return list.id;
  }

  TodoList? getTodoList(String id) {
    try {
      return _todoLists.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateTodoList(TodoList list) async {
    final index = _todoLists.indexWhere((n) => n.id == list.id);
    if (index == -1) return;
    _todoLists[index] = list;
    await _queueSaveTodoLists();
    notifyListeners();
  }

  Future<void> reorderTodoLists(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _todoLists.length) return;
    if (newIndex < 0 || newIndex > _todoLists.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _todoLists.removeAt(oldIndex);
    _todoLists.insert(newIndex, item);
    await _queueSaveTodoLists();
    notifyListeners();
  }

  Future<void> deleteTodoList(String id) async {
    final before = _todoLists.length;
    _todoLists.removeWhere((n) => n.id == id);
    if (_todoLists.length == before) return;
    await _queueSaveTodoLists();
    notifyListeners();
  }
}

class StorageV2PageExport {
  final String fileName;
  final String title;
  final String content;

  const StorageV2PageExport({
    required this.fileName,
    required this.title,
    required this.content,
  });
}
