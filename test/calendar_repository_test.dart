import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/anniversary.dart';
import 'package:lynai/models/calendar_event.dart';
import 'package:lynai/models/local_date.dart';
import 'package:lynai/repositories/calendar_repository.dart';
import 'package:lynai/services/storage_v2_service.dart';

void main() {
  test(
    'CalendarRepository saves and loads the exact calendar partition',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_calendar_repo_',
      );
      final storage = StorageV2Service(rootDirectory: root);
      try {
        final repository = CalendarRepository(storageV2: storage);
        final now = DateTime(2026, 7, 22, 8);
        final events = [
          CalendarEvent(
            id: 'event',
            title: 'Holiday',
            spec: AllDayCalendarEventSpec(
              startDate: LocalDate(2026, 8, 1),
              endDateExclusive: LocalDate(2026, 8, 3),
            ),
            createdAt: now,
            updatedAt: now,
          ),
        ];
        final anniversaries = [
          Anniversary(
            id: 'anniversary',
            title: 'Launch',
            spec: YearlyAnniversarySpec(month: 8, day: 2, sourceYear: 2020),
            showYearCount: true,
            createdAt: now,
            updatedAt: now,
          ),
        ];

        await repository.replace(events: events, anniversaries: anniversaries);

        final raw = await storage.loadDataFile(CalendarRepository.fileName);
        expect(raw.keys, unorderedEquals(['events', 'anniversaries']));
        expect(
          (raw['events'] as List).single,
          containsPair('timeKind', 'allDay'),
        );
        expect(
          (raw['events'] as List).single,
          containsPair('endDateExclusive', '2026-08-03'),
        );
        expect((raw['events'] as List).single, isNot(contains('spec')));
        expect(
          (raw['anniversaries'] as List).single,
          containsPair('recurrence', 'yearly'),
        );

        final loaded = await repository.load();
        expect(loaded.events.single.toJson(), events.single.toJson());
        expect(
          loaded.anniversaries.single.toJson(),
          anniversaries.single.toJson(),
        );

        await repository.saveChanges(
          upsertEvents: [events.single.copyWith(title: 'Updated')],
          deleteAnniversaryIds: [anniversaries.single.id],
        );
        final incrementallyLoaded = await repository.load();
        expect(incrementallyLoaded.events.single.title, 'Updated');
        expect(incrementallyLoaded.anniversaries, isEmpty);
      } finally {
        await storage.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );
}
