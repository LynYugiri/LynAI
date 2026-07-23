import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/anniversary.dart';
import 'package:lynai/models/calendar_event.dart';
import 'package:lynai/models/local_date.dart';
import 'package:lynai/models/recycle_bin_item.dart';
import 'package:lynai/models/task.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/repositories/calendar_repository.dart';
import 'package:lynai/repositories/recycle_bin_repository.dart';

void main() {
  test(
    'mutations notify from memory before the serialized save completes',
    () async {
      final repository = _CalendarRepository();
      final provider = CalendarProvider(repository: repository);
      var notifications = 0;
      provider.addListener(() => notifications++);

      final add = provider.addEvent(
        title: 'Meeting',
        spec: TimedCalendarEventSpec(
          start: DateTime(2026, 8, 1, 10),
          end: DateTime(2026, 8, 1, 11),
        ),
      );

      expect(provider.events.single.title, 'Meeting');
      expect(notifications, 1);
      expect(repository.saveCalls, 0);
      repository.allowSave.complete();
      await add;
      expect(repository.saveCalls, 1);
    },
  );

  test(
    'delete and restore use recycle bin and preserve UUID payload',
    () async {
      final repository = _CalendarRepository()..allowSave.complete();
      final recycleBin = _RecycleBinRepository();
      final provider = CalendarProvider(
        repository: repository,
        recycleBinRepository: recycleBin,
      );
      final id = await provider.addAnniversary(
        title: 'Launch',
        spec: YearlyAnniversarySpec(month: 8, day: 2),
      );

      await provider.deleteAnniversary(id);

      expect(provider.anniversaries, isEmpty);
      final deleted = recycleBin.added.single;
      expect(deleted.type, RecycleBinItemTypes.anniversary);
      expect(deleted.payload['anniversary'], containsPair('id', id));

      await provider.restoreRecycleBinItem(deleted);
      expect(provider.anniversaries.single.id, id);
      expect(recycleBin.removed, [deleted.id]);
    },
  );

  test('load does not overwrite a concurrent mutation', () async {
    final repository = _CalendarRepository()..allowSave.complete();
    final loadResult = Completer<CalendarLoadResult>();
    repository.loadResult = loadResult.future;
    final provider = CalendarProvider(repository: repository);

    final load = provider.load();
    final id = await provider.addEvent(
      title: 'Concurrent event',
      spec: AllDayCalendarEventSpec(
        startDate: LocalDate(2026, 8, 1),
        endDateExclusive: LocalDate(2026, 8, 2),
      ),
    );
    loadResult.complete(
      const CalendarLoadResult(events: [], anniversaries: []),
    );
    await load;

    expect(provider.events.single.id, id);
  });

  test('failed recycle bin write leaves event in memory', () async {
    final repository = _CalendarRepository()..allowSave.complete();
    final recycleBin = _RecycleBinRepository()..addError = StateError('disk');
    final provider = CalendarProvider(
      repository: repository,
      recycleBinRepository: recycleBin,
    );
    final id = await provider.addEvent(
      title: 'Keep me',
      spec: AllDayCalendarEventSpec(
        startDate: LocalDate(2026, 8, 1),
        endDateExclusive: LocalDate(2026, 8, 2),
      ),
    );

    await expectLater(provider.deleteEvent(id), throwsStateError);

    expect(provider.events.single.id, id);
    expect(repository.events.single.id, id);
  });

  test('range occurrences include provider data and caller tasks', () async {
    final repository = _CalendarRepository()..allowSave.complete();
    final provider = CalendarProvider(repository: repository);
    await provider.addEvent(
      title: 'Event',
      spec: AllDayCalendarEventSpec(
        startDate: LocalDate(2026, 8, 1),
        endDateExclusive: LocalDate(2026, 8, 2),
      ),
    );
    final now = DateTime(2026, 7, 22, 8);
    final task = Task(
      id: 'task',
      title: 'Task',
      plannedDate: LocalDate(2026, 8, 1),
      createdAt: now,
      updatedAt: now,
    );

    final occurrences = provider.occurrencesInRange(
      startDate: LocalDate(2026, 8, 1),
      endDateExclusive: LocalDate(2026, 8, 2),
      tasks: [task],
      now: now,
    );

    expect(occurrences.map((value) => value.sourceId), containsAll(['task']));
    expect(occurrences.where((value) => value.title == 'Event'), hasLength(1));
  });
}

class _CalendarRepository implements CalendarRepository {
  final allowSave = Completer<void>();
  Future<CalendarLoadResult>? loadResult;
  int saveCalls = 0;
  List<CalendarEvent> events = const [];
  List<Anniversary> anniversaries = const [];

  @override
  Future<CalendarLoadResult> load() async =>
      loadResult ??
      CalendarLoadResult(events: events, anniversaries: anniversaries);

  @override
  Future<void> save({
    required List<CalendarEvent> events,
    required List<Anniversary> anniversaries,
  }) async {
    await allowSave.future;
    saveCalls++;
    this.events = events;
    this.anniversaries = anniversaries;
  }
}

class _RecycleBinRepository implements RecycleBinRepository {
  final List<RecycleBinItem> added = [];
  final List<String> removed = [];
  Object? addError;

  @override
  Future<void> add(RecycleBinItem item) async {
    if (addError case final error?) throw error;
    added.add(item);
  }

  @override
  Future<List<RecycleBinItem>> load() async => List.of(added);

  @override
  Future<void> remove(String id) async => removed.add(id);

  @override
  Future<void> save(List<RecycleBinItem> items) async {
    added
      ..clear()
      ..addAll(items);
  }
}
