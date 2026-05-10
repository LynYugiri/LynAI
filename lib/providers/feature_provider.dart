import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../models/schedule_item.dart';

class FeatureProvider extends ChangeNotifier {
  static const _scheduleKey = 'schedule_items';
  static const _notesKey = 'notes';
  final _uuid = const Uuid();

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

  Future<void> _saveSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _scheduleKey,
      jsonEncode(_schedules.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _notesKey,
      jsonEncode(_notes.map((e) => e.toJson()).toList()),
    );
  }

  String addSchedule(
    String title,
    DateTime start,
    DateTime end, {
    String? note,
  }) {
    final schedule = ScheduleItem(
      id: _uuid.v4(),
      title: title,
      start: start,
      end: end,
      note: note,
    );
    _schedules.add(schedule);
    _schedules.sort((a, b) => a.start.compareTo(b.start));
    _saveSchedules();
    notifyListeners();
    return schedule.id;
  }

  void updateSchedule(ScheduleItem schedule) {
    final index = _schedules.indexWhere((s) => s.id == schedule.id);
    if (index == -1) return;
    _schedules[index] = schedule;
    _schedules.sort((a, b) => a.start.compareTo(b.start));
    _saveSchedules();
    notifyListeners();
  }

  void deleteSchedule(String id) {
    final before = _schedules.length;
    _schedules.removeWhere((s) => s.id == id);
    if (_schedules.length == before) return;
    _saveSchedules();
    notifyListeners();
  }

  ScheduleItem? getSchedule(String id) {
    try {
      return _schedules.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  String addNote(String title) {
    return addNoteWithContent(title, '');
  }

  String addNoteWithContent(String title, String content) {
    final now = DateTime.now();
    final note = Note(
      id: _uuid.v4(),
      title: title,
      content: content,
      createdAt: now,
      updatedAt: now,
    );
    _notes.insert(0, note);
    _saveNotes();
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

  void updateNote(Note note) {
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index == -1) return;
    _notes[index] = note;
    _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _saveNotes();
    notifyListeners();
  }

  void deleteNote(String id) {
    _notes.removeWhere((n) => n.id == id);
    _saveNotes();
    notifyListeners();
  }
}
