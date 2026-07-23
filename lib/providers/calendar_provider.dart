import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/anniversary.dart';
import '../models/calendar_event.dart';
import '../models/calendar_occurrence.dart';
import '../models/item_reminder.dart';
import '../models/local_date.dart';
import '../models/recycle_bin_item.dart';
import '../models/task.dart';
import '../repositories/calendar_repository.dart';
import '../repositories/recycle_bin_repository.dart';
import '../services/calendar_occurrence_service.dart';
import '../services/storage_v2_service.dart';

/// 日历事件和纪念日的唯一内存权威。
class CalendarProvider extends ChangeNotifier {
  CalendarProvider({
    StorageV2Service? storageV2,
    CalendarRepository? repository,
    RecycleBinRepository? recycleBinRepository,
    CalendarOccurrenceService occurrenceService =
        const CalendarOccurrenceService(),
    DateTime Function()? now,
  }) : _repository = repository ?? CalendarRepository(storageV2: storageV2),
       _recycleBinRepository =
           recycleBinRepository ?? RecycleBinRepository(storageV2: storageV2),
       _occurrenceService = occurrenceService,
       _now = now ?? DateTime.now;

  final CalendarRepository _repository;
  final RecycleBinRepository _recycleBinRepository;
  final CalendarOccurrenceService _occurrenceService;
  final DateTime Function() _now;
  final Uuid _uuid = const Uuid();

  List<CalendarEvent> _events = const [];
  List<Anniversary> _anniversaries = const [];
  Future<void> _saveQueue = Future.value();
  Future<void> _pendingSave = Future.value();
  bool _loading = false;
  int _mutationGeneration = 0;

  /// 完整日历快照成功持久化后触发；平台投影协调器据此串行同步。
  VoidCallback? onSnapshotPersisted;

  List<CalendarEvent> get events => List.unmodifiable(_events);
  List<Anniversary> get anniversaries => List.unmodifiable(_anniversaries);
  bool get loading => _loading;

  Future<void> load() async {
    final generation = _mutationGeneration;
    await flushPendingSaves();
    _loading = true;
    notifyListeners();
    try {
      final result = await _repository.load();
      if (generation != _mutationGeneration) return;
      _events = List.of(result.events);
      _anniversaries = List.of(result.anniversaries);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 用完整日历分区快照同步替换内存和持久化数据。
  Future<void> replaceAll({
    required List<CalendarEvent> events,
    required List<Anniversary> anniversaries,
  }) async {
    _mutationGeneration++;
    _events = List.of(events);
    _anniversaries = List.of(anniversaries);
    notifyListeners();
    await _queueSave();
  }

  CalendarEvent? getEvent(String id) =>
      _firstWhereOrNull(_events, (event) => event.id == id);

  Anniversary? getAnniversary(String id) =>
      _firstWhereOrNull(_anniversaries, (anniversary) => anniversary.id == id);

  Future<String> addEvent({
    required String title,
    String? note,
    required CalendarEventSpec spec,
    List<ItemReminder> reminders = const [],
  }) async {
    _mutationGeneration++;
    final now = _now();
    final event = CalendarEvent(
      id: _uuid.v4(),
      title: title,
      note: note,
      spec: spec,
      reminders: reminders,
      createdAt: now,
      updatedAt: now,
    );
    _events = [..._events, event];
    notifyListeners();
    await _queueSave();
    return event.id;
  }

  Future<void> updateEvent(CalendarEvent event) async {
    final index = _events.indexWhere((value) => value.id == event.id);
    if (index == -1) return;
    _mutationGeneration++;
    final updated = event.copyWith(
      createdAt: _events[index].createdAt,
      updatedAt: _now(),
    );
    _events = [..._events]..[index] = updated;
    notifyListeners();
    await _queueSave();
  }

  Future<void> deleteEvent(String id) async {
    final event = getEvent(id);
    if (event == null) return;
    await _recycleBinRepository.add(
      RecycleBinItem(
        owner: RecycleBinOwners.core,
        category: RecycleBinCategories.calendar,
        type: RecycleBinItemTypes.calendarEvent,
        title: event.title.isEmpty ? '未命名事件' : event.title,
        preview: event.note ?? '',
        payload: {'event': event.toJson()},
      ),
    );
    _mutationGeneration++;
    _events = _events.where((value) => value.id != id).toList();
    notifyListeners();
    await _queueSave();
  }

  Future<void> restoreEvent(
    CalendarEvent event, {
    String? recycleBinItemId,
  }) async {
    if (_events.any((value) => value.id == event.id)) return;
    _mutationGeneration++;
    _events = [..._events, event];
    notifyListeners();
    await _queueSave(
      afterSave: recycleBinItemId == null
          ? null
          : () => _recycleBinRepository.remove(recycleBinItemId),
    );
  }

  Future<String> addAnniversary({
    required String title,
    String? note,
    required AnniversarySpec spec,
    bool showYearCount = false,
    List<ItemReminder> reminders = const [],
  }) async {
    _mutationGeneration++;
    final now = _now();
    final anniversary = Anniversary(
      id: _uuid.v4(),
      title: title,
      note: note,
      spec: spec,
      showYearCount: showYearCount,
      reminders: reminders,
      createdAt: now,
      updatedAt: now,
    );
    _anniversaries = [..._anniversaries, anniversary];
    notifyListeners();
    await _queueSave();
    return anniversary.id;
  }

  Future<void> updateAnniversary(Anniversary anniversary) async {
    final index = _anniversaries.indexWhere(
      (value) => value.id == anniversary.id,
    );
    if (index == -1) return;
    _mutationGeneration++;
    final updated = anniversary.copyWith(
      createdAt: _anniversaries[index].createdAt,
      updatedAt: _now(),
    );
    _anniversaries = [..._anniversaries]..[index] = updated;
    notifyListeners();
    await _queueSave();
  }

  Future<void> deleteAnniversary(String id) async {
    final anniversary = getAnniversary(id);
    if (anniversary == null) return;
    await _recycleBinRepository.add(
      RecycleBinItem(
        owner: RecycleBinOwners.core,
        category: RecycleBinCategories.calendar,
        type: RecycleBinItemTypes.anniversary,
        title: anniversary.title.isEmpty ? '未命名纪念日' : anniversary.title,
        preview: anniversary.note ?? '',
        payload: {'anniversary': anniversary.toJson()},
      ),
    );
    _mutationGeneration++;
    _anniversaries = _anniversaries.where((value) => value.id != id).toList();
    notifyListeners();
    await _queueSave();
  }

  Future<void> restoreAnniversary(
    Anniversary anniversary, {
    String? recycleBinItemId,
  }) async {
    if (_anniversaries.any((value) => value.id == anniversary.id)) return;
    _mutationGeneration++;
    _anniversaries = [..._anniversaries, anniversary];
    notifyListeners();
    await _queueSave(
      afterSave: recycleBinItemId == null
          ? null
          : () => _recycleBinRepository.remove(recycleBinItemId),
    );
  }

  Future<void> restoreRecycleBinItem(RecycleBinItem item) async {
    switch (item.type) {
      case RecycleBinItemTypes.calendarEvent:
        final raw = item.payload['event'];
        if (raw is! Map) throw const FormatException('回收站日历事件损坏');
        await restoreEvent(
          CalendarEvent.fromJson(Map<String, dynamic>.from(raw)),
          recycleBinItemId: item.id,
        );
      case RecycleBinItemTypes.anniversary:
        final raw = item.payload['anniversary'];
        if (raw is! Map) throw const FormatException('回收站纪念日损坏');
        await restoreAnniversary(
          Anniversary.fromJson(Map<String, dynamic>.from(raw)),
          recycleBinItemId: item.id,
        );
      default:
        throw ArgumentError.value(item.type, 'item.type', '不是日历回收站项目');
    }
  }

  /// 发生记录只是事件、纪念日和调用方任务的范围投影，不反向持久化。
  List<CalendarOccurrence> occurrencesInRange({
    required LocalDate startDate,
    required LocalDate endDateExclusive,
    Iterable<Task> tasks = const [],
    DateTime? now,
  }) {
    return _occurrenceService.project(
      startDate: startDate,
      endDateExclusive: endDateExclusive,
      events: _events,
      tasks: tasks,
      anniversaries: _anniversaries,
      now: now,
    );
  }

  Future<void> flushPendingSaves() => _pendingSave;

  Future<void> _queueSave({
    Future<void> Function()? beforeSave,
    Future<void> Function()? afterSave,
  }) {
    final events = List<CalendarEvent>.of(_events);
    final anniversaries = List<Anniversary>.of(_anniversaries);
    final operation = _saveQueue.then((_) async {
      await beforeSave?.call();
      await _repository.save(events: events, anniversaries: anniversaries);
      await afterSave?.call();
      onSnapshotPersisted?.call();
    });
    _pendingSave = operation;
    _saveQueue = operation.catchError((Object error) {
      debugPrint('保存日历分区失败: $error');
    });
    return operation;
  }
}

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}
