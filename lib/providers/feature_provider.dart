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
    final prefs = await SharedPreferences.getInstance();
    final scheduleJson = prefs.getString(_scheduleKey);
    if (scheduleJson != null) {
      _schedules = (jsonDecode(scheduleJson) as List<dynamic>)
          .map((e) => ScheduleItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final notesJson = prefs.getString(_notesKey);
    if (notesJson != null) {
      _notes = (jsonDecode(notesJson) as List<dynamic>)
          .map((e) => Note.fromJson(e as Map<String, dynamic>))
          .toList();
      _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    notifyListeners();
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

  void addSchedule(String title, DateTime start, DateTime end, {String? note}) {
    _schedules.add(
      ScheduleItem(
        id: _uuid.v4(),
        title: title,
        start: start,
        end: end,
        note: note,
      ),
    );
    _schedules.sort((a, b) => a.start.compareTo(b.start));
    _saveSchedules();
    notifyListeners();
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

  String addNote(String title) {
    final now = DateTime.now();
    final note = Note(
      id: _uuid.v4(),
      title: title,
      content: '',
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
