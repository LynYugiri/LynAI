import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/anniversary.dart';
import 'package:lynai/models/calendar_event.dart';
import 'package:lynai/models/local_date.dart';
import 'package:lynai/pages/feature_page.dart';
import 'package:lynai/pages/features/schedule_page.dart';
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
    await _switchToMonth(tester);

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
    await _switchToMonth(tester);

    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看纪念日'));
    await tester.pumpAndSettle();

    await _expectTitleFocusRequiresTap(tester);
  });

  testWidgets('tapping a month date opens a bottom sheet without group rows', (
    tester,
  ) async {
    final calendar = _calendarProvider();
    await calendar.replaceAll(
      events: [_allDayEvent('event-1', '查看事件')],
      anniversaries: const [],
    );
    await _pumpSchedule(tester, calendar);
    await _switchToMonth(tester);

    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('查看事件'), findsOneWidget);
    expect(find.text('全天 / 跨日'), findsNothing);
  });

  testWidgets('month date with calendar items shows a single red dot', (
    tester,
  ) async {
    final calendar = _calendarProvider();
    await calendar.replaceAll(
      events: [_allDayEvent('event-1', '查看事件')],
      anniversaries: const [],
    );
    await _pumpSchedule(tester, calendar);
    await _switchToMonth(tester);

    final dotFinder = find.byKey(const ValueKey('month-date-dot'));
    expect(dotFinder, findsOneWidget);
    final scheme = Theme.of(tester.element(dotFinder)).colorScheme;
    final dot = tester.widget<Container>(dotFinder);
    expect((dot.decoration! as BoxDecoration).color, scheme.error);
  });

  testWidgets(
    'day view shows all-day items as top chips without a summary row',
    (tester) async {
      final calendar = _calendarProvider();
      await calendar.replaceAll(
        events: [_allDayEvent('event-1', '查看事件')],
        anniversaries: const [],
      );
      await _pumpSchedule(tester, calendar);

      await _switchToDay(tester);

      expect(find.text('全天'), findsNothing);
      expect(find.text('事 查看事件'), findsOneWidget);
    },
  );

  testWidgets('pinching the day view changes the zoom indicator', (
    tester,
  ) async {
    final calendar = _calendarProvider();
    await calendar.replaceAll(events: const [], anniversaries: const []);
    await _pumpSchedule(tester, calendar);

    await _switchToDay(tester);
    expect(find.text('100%'), findsOneWidget);

    final center = tester.getCenter(find.byType(SchedulePage));
    final first = await tester.startGesture(
      center.translate(-30, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center.translate(30, 0),
      pointer: 2,
    );
    await tester.pump();
    await first.moveBy(const Offset(-60, 0));
    await second.moveBy(const Offset(60, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    expect(find.text('100%'), findsNothing);
    expect(find.text('180%'), findsOneWidget);
  });

  testWidgets('ctrl + wheel over the timeline zooms instead of scrolling', (
    tester,
  ) async {
    final calendar = _calendarProvider();
    await calendar.replaceAll(events: const [], anniversaries: const []);
    await _pumpSchedule(tester, calendar);

    expect(find.text('100%'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.text('08:00')));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -200)));
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(find.text('100%'), findsNothing);
    expect(find.text('108%'), findsOneWidget);
  });

  testWidgets('scrolling day view up collapses controls and keeps navigator', (
    tester,
  ) async {
    final calendar = _calendarProvider();
    await calendar.replaceAll(events: const [], anniversaries: const []);
    await _pumpSchedule(tester, calendar);

    final controlsFinder = find.byKey(const ValueKey('schedule-controls'));
    final prevFinder = find.byKey(const ValueKey('schedule-prev'));
    final nextFinder = find.byKey(const ValueKey('schedule-next'));
    expect(tester.widget<IgnorePointer>(controlsFinder).ignoring, isFalse);
    expect(tester.widget<IgnorePointer>(prevFinder).ignoring, isFalse);
    expect(tester.widget<IgnorePointer>(nextFinder).ignoring, isFalse);

    await tester.drag(find.text('08:00'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(controlsFinder).ignoring, isTrue);
    expect(tester.widget<IgnorePointer>(prevFinder).ignoring, isTrue);
    expect(tester.widget<IgnorePointer>(nextFinder).ignoring, isTrue);
    expect(find.text(_dayTitle(DateTime.now())), findsOneWidget);

    await tester.drag(find.text('16:00'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(controlsFinder).ignoring, isFalse);
    expect(tester.widget<IgnorePointer>(prevFinder).ignoring, isFalse);
    expect(tester.widget<IgnorePointer>(nextFinder).ignoring, isFalse);
  });

  testWidgets('schedule page opens in the day timeline view by default', (
    tester,
  ) async {
    final calendar = _calendarProvider();
    await calendar.replaceAll(events: const [], anniversaries: const []);
    await _pumpSchedule(tester, calendar);

    expect(find.text('日程时间轴'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('月历总览'), findsNothing);
  });
}

Future<void> _switchToDay(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey('calendar-mode-switch')),
      matching: find.text('日'),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _switchToMonth(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey('calendar-mode-switch')),
      matching: find.text('月'),
    ),
  );
  await tester.pumpAndSettle();
}

CalendarEvent _allDayEvent(String id, String title) {
  final today = LocalDate.fromDateTime(DateTime.now());
  return CalendarEvent(
    id: id,
    title: title,
    spec: AllDayCalendarEventSpec(
      startDate: today,
      endDateExclusive: today.addDays(1),
    ),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

String _dayTitle(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

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
      child: MaterialApp(home: FeaturePage(onConversationTap: (_) {})),
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
