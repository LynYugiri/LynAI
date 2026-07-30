import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/anniversary.dart';
import 'package:lynai/models/calendar_event.dart';
import 'package:lynai/models/local_date.dart';
import 'package:lynai/pages/feature_page.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/repositories/calendar_repository.dart';
import 'package:provider/provider.dart';

import 'support/memory_repositories.dart';

void main() {
  testWidgets('opening an existing calendar item does not focus its title', (
    tester,
  ) async {
    final today = LocalDate.fromDateTime(DateTime.now());
    final calendar = _calendarProvider();
    await calendar.replaceAll(
      events: [
        CalendarEvent(
          id: 'event-1',
          title: '查看事件',
          spec: AllDayCalendarEventSpec(
            startDate: today,
            endDateExclusive: today.addDays(1),
          ),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
      anniversaries: const [],
    );
    await _pumpSchedule(tester, calendar);

    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看事件'));
    await tester.pumpAndSettle();

    await _expectTitleFocusRequiresTap(tester);
  });

  testWidgets('opening an existing anniversary does not focus its title', (
    tester,
  ) async {
    final today = LocalDate.fromDateTime(DateTime.now());
    final calendar = _calendarProvider();
    await calendar.replaceAll(
      events: const [],
      anniversaries: [
        Anniversary(
          id: 'anniversary-1',
          title: '查看纪念日',
          spec: OnceAnniversarySpec(date: today),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
    );
    await _pumpSchedule(tester, calendar);

    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看纪念日'));
    await tester.pumpAndSettle();

    await _expectTitleFocusRequiresTap(tester);
  });
}

Future<void> _expectTitleFocusRequiresTap(WidgetTester tester) async {
  final titleField = find.widgetWithText(TextField, '标题');
  final editableFinder = find.descendant(
    of: titleField,
    matching: find.byType(EditableText),
  );
  expect(
    tester.widget<EditableText>(editableFinder).focusNode.hasFocus,
    isFalse,
  );
  expect(tester.testTextInput.isVisible, isFalse);

  await tester.tap(titleField);
  await tester.pump();
  expect(
    tester.widget<EditableText>(editableFinder).focusNode.hasFocus,
    isTrue,
  );
  expect(tester.testTextInput.isVisible, isTrue);
}

CalendarProvider _calendarProvider() {
  return CalendarProvider(
    repository: _MemoryCalendarRepository(),
    recycleBinRepository: MemoryRecycleBinRepository(),
  );
}

Future<void> _pumpSchedule(
  WidgetTester tester,
  CalendarProvider calendar,
) async {
  final settings = memorySettingsProvider();
  await settings.replaceSettings(
    settings.settings.copyWith(lastFeature: 'schedule'),
  );
  await tester.binding.setSurfaceSize(const Size(500, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: calendar),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
        ChangeNotifierProvider(create: (_) => FeatureProvider()),
        ChangeNotifierProvider(create: (_) => PluginProvider()),
      ],
      child: MaterialApp(
        home: FeaturePage(onConversationTap: (_) {}, onRoleChanged: () {}),
      ),
    ),
  );
  await tester.pump();
}

final class _MemoryCalendarRepository extends CalendarRepository {
  @override
  Future<CalendarLoadResult> load() async {
    return const CalendarLoadResult(events: [], anniversaries: []);
  }

  @override
  Future<void> replace({
    required List<CalendarEvent> events,
    required List<Anniversary> anniversaries,
  }) async {}

  @override
  Future<void> saveChanges({
    Iterable<CalendarEvent> upsertEvents = const [],
    Iterable<String> deleteEventIds = const [],
    Iterable<Anniversary> upsertAnniversaries = const [],
    Iterable<String> deleteAnniversaryIds = const [],
  }) async {}
}
