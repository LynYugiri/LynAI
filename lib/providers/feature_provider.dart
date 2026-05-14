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
  static const _noteFoldersKey = 'note_folders';
  static const _todoListsKey = 'todo_lists';
  static const _scheduleWidgetChannel = MethodChannel('lynai/schedule_widget');
  final _uuid = const Uuid();
  Future<void> _scheduleSaveQueue = Future.value();
  Future<void> _noteSaveQueue = Future.value();
  Future<void> _noteFolderSaveQueue = Future.value();
  Future<void> _todoListSaveQueue = Future.value();

  List<ScheduleItem> _schedules = [];
  List<Note> _notes = [];
  List<NoteFolder> _noteFolders = [];
  List<TodoList> _todoLists = [];

  List<ScheduleItem> get schedules => List.unmodifiable(_schedules);
  List<Note> get notes => List.unmodifiable(_notes);
  List<NoteFolder> get noteFolders => List.unmodifiable(_noteFolders);
  List<TodoList> get todoLists => List.unmodifiable(_todoLists);

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
    final note = Note(
      id: _uuid.v4(),
      title: title,
      content: content,
      folderId: _noteFolders.any((f) => f.id == folderId) ? folderId : null,
      createdAt: now,
      updatedAt: now,
    );
    _notes.insert(0, note);
    await _queueSaveNotes();
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

  Future<void> updateNote(Note note) async {
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index == -1) return;
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
    await _queueSaveNotes();
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
