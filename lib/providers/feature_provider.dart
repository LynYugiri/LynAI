import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../models/schedule_item.dart';

class FeatureProvider extends ChangeNotifier {
  static const _scheduleKey = 'schedule_items';
  static const _notesKey = 'notes';
  static const _scheduleWidgetChannel = MethodChannel('lynai/schedule_widget');
  final _uuid = const Uuid();
  Future<void> _scheduleSaveQueue = Future.value();
  Future<void> _noteSaveQueue = Future.value();

  List<ScheduleItem> _schedules = [];
  List<Note> _notes = [];

  List<ScheduleItem> get schedules => List.unmodifiable(_schedules);
  List<Note> get notes => List.unmodifiable(_notes);

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
        _notes = notes..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      }
      notifyListeners();
    } catch (e) {
      debugPrint('加载功能数据失败: $e');
      _schedules = [];
      _notes = [];
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

  Future<String> addNote(String title) {
    return addNoteWithContent(title, '');
  }

  Future<String> addNoteWithContent(String title, String content) async {
    final now = DateTime.now();
    final note = Note(
      id: _uuid.v4(),
      title: title,
      content: content,
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
    _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
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
}
