import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../models/schedule_item.dart';
import '../models/todo_list.dart';

class FeatureProvider extends ChangeNotifier {
  static const _scheduleKey = 'schedule_items';
  static const _notesKey = 'notes';
  static const _noteRevisionsKey = 'note_revisions';
  static const _noteFoldersKey = 'note_folders';
  static const _todoListsKey = 'todo_lists';
  static const _scheduleWidgetChannel = MethodChannel('lynai/schedule_widget');
  final _uuid = const Uuid();
  Future<void> _scheduleSaveQueue = Future.value();
  Future<void> _noteSaveQueue = Future.value();
  Future<void> _noteRevisionSaveQueue = Future.value();
  Future<void> _noteFolderSaveQueue = Future.value();
  Future<void> _todoListSaveQueue = Future.value();

  List<ScheduleItem> _schedules = [];
  List<Note> _notes = [];
  List<NoteRevision> _noteRevisions = [];
  List<NoteFolder> _noteFolders = [];
  List<TodoList> _todoLists = [];
  final Map<String, NoteEditProposal> _noteEditProposals = {};
  final Map<String, String> _noteRevisionContentCache = {};
  final Map<String, List<NoteRevision>> _noteTimelineCache = {};

  List<ScheduleItem> get schedules => List.unmodifiable(_schedules);
  List<Note> get notes => List.unmodifiable(_notes);
  List<NoteFolder> get noteFolders => List.unmodifiable(_noteFolders);
  List<TodoList> get todoLists => List.unmodifiable(_todoLists);
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
      _normalizeNoteRevisionState();
      _removeMissingNoteFolderReferences();
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
      notifyListeners();
    } catch (e) {
      debugPrint('加载功能数据失败: $e');
      _schedules = [];
      _notes = [];
      _noteRevisions = [];
      _noteFolders = [];
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
      await prefs.setString(
        _scheduleKey,
        jsonEncode(snapshot.map((e) => e.toJson()).toList()),
      );
      await _refreshScheduleWidget();
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

  Future<void> _saveNoteFoldersSnapshot(List<NoteFolder> snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
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
      await prefs.setString(
        _notesKey,
        jsonEncode(snapshot.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('保存笔记失败: $e');
    }
  }

  void _removeMissingNoteFolderReferences() {
    final folderIds = _noteFolders.map((folder) => folder.id).toSet();
    _notes = _notes.map((note) {
      final folderId = note.folderId;
      if (folderId == null || folderIds.contains(folderId)) return note;
      return note.copyWith(folderId: null, preserveUpdatedAt: true);
    }).toList();
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
  }) async {
    final schedule = ScheduleItem(
      id: _uuid.v4(),
      title: title,
      start: start,
      end: end,
      note: note,
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

  void _normalizeNoteRevisionState() {
    final revisionById = {
      for (final revision in _noteRevisions) revision.id: revision,
    };
    final validChainCache = <String, bool>{};

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
      return note.copyWith(currentRevisionId: null, preserveUpdatedAt: true);
    }).toList();
    _noteRevisionContentCache.clear();
    _noteTimelineCache.clear();
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
    _noteEditProposals.remove(note.id);
    _notes[index] = note.copyWith(
      content: content,
      currentRevisionId: revision.id,
    );
    await _queueSaveNoteRevisions();
    await _queueSaveNotes();
    notifyListeners();
    return revision;
  }

  Future<void> updateNote(Note note) async {
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index == -1) return;
    if (_notes[index].content != note.content) {
      _noteEditProposals.remove(note.id);
    }
    _notes[index] = note;
    await _queueSaveNotes();
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
    _noteEditProposals.remove(id);
    _noteRevisionContentCache.removeWhere(
      (revisionId, _) => deletedRevisionIds.contains(revisionId),
    );
    await _queueSaveNotes();
    await _queueSaveNoteRevisions();
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
    await _queueSaveNoteRevisions();
    notifyListeners();
    return true;
  }

  void setNoteEditProposal(NoteEditProposal proposal) {
    _noteEditProposals[proposal.noteId] = proposal;
    notifyListeners();
  }

  void removeNoteEditProposal(String noteId) {
    if (_noteEditProposals.remove(noteId) == null) return;
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
    await _queueSaveNoteFolders();
    notifyListeners();
  }

  Future<void> reorderNoteFolders(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _noteFolders.length) return;
    if (newIndex < 0 || newIndex > _noteFolders.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final folder = _noteFolders.removeAt(oldIndex);
    _noteFolders.insert(newIndex, folder);
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
