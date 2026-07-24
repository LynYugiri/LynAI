import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/anniversary.dart';
import 'package:lynai/models/calendar_event.dart';
import 'package:lynai/models/task.dart';
import 'package:lynai/models/task_list.dart';
import 'package:lynai/pages/data_management_page.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/roleplay_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/providers/sync_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/repositories/calendar_repository.dart';
import 'package:lynai/repositories/task_repository.dart';
import 'package:provider/provider.dart';

import 'support/memory_repositories.dart';

void main() {
  testWidgets('planning selections have Material ink and typed callbacks', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 24, 10);
    final tasks = TaskProvider(
      repository: _MemoryTaskRepository(),
      recycleBinRepository: MemoryRecycleBinRepository(),
    );
    final calendar = CalendarProvider(
      repository: _MemoryCalendarRepository(),
      recycleBinRepository: MemoryRecycleBinRepository(),
    );
    await tasks.replaceAll(
      tasks: [Task(id: 'task', title: '测试任务', createdAt: now, updatedAt: now)],
      lists: const [],
      entries: const [],
    );
    await calendar.replaceAll(
      events: [
        CalendarEvent(
          id: 'event',
          title: '测试事件',
          spec: TimedCalendarEventSpec(
            start: now,
            end: now.add(const Duration(hours: 1)),
          ),
          createdAt: now,
          updatedAt: now,
        ),
      ],
      anniversaries: const [],
    );

    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => memorySettingsProvider(),
          ),
          ChangeNotifierProvider<ModelConfigProvider>(
            create: (_) => memoryModelConfigProvider(),
          ),
          ChangeNotifierProvider<ConversationProvider>(
            create: (_) => memoryConversationProvider(),
          ),
          ChangeNotifierProvider(create: (_) => FeatureProvider()),
          ChangeNotifierProvider<RoleplayProvider>(
            create: (_) => memoryRoleplayProvider(),
          ),
          ChangeNotifierProvider.value(value: tasks),
          ChangeNotifierProvider.value(value: calendar),
          ChangeNotifierProvider(create: (_) => PluginProvider()),
          ChangeNotifierProvider(create: (_) => SyncProvider()),
        ],
        child: const MaterialApp(home: DataManagementPage()),
      ),
    );
    await tester.pumpAndSettle();

    await _expandAndToggle(tester, section: '任务', item: '测试任务');
    await _expandAndToggle(tester, section: '日历', item: '测试事件');

    expect(tester.takeException(), isNull);
  });
}

Future<void> _expandAndToggle(
  WidgetTester tester, {
  required String section,
  required String item,
}) async {
  final sectionFinder = find.widgetWithText(ExpansionTile, section);
  await tester.scrollUntilVisible(
    sectionFinder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(sectionFinder);
  await tester.pumpAndSettle();

  final itemFinder = find.widgetWithText(CheckboxListTile, item);
  await tester.scrollUntilVisible(
    itemFinder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  expect(
    find.ancestor(of: itemFinder, matching: find.byType(Material)),
    findsWidgets,
  );
  await tester.tap(itemFinder);
  await tester.pumpAndSettle();
}

final class _MemoryTaskRepository implements TaskRepository {
  @override
  Future<TaskLoadResult> load() async {
    return const TaskLoadResult(tasks: [], lists: [], entries: []);
  }

  @override
  Future<void> replace({
    required List<Task> tasks,
    required List<TaskList> lists,
    required List<TaskListEntry> entries,
  }) async {}

  @override
  Future<void> saveChanges({
    Iterable<Task> upsertTasks = const [],
    Iterable<String> deleteTaskIds = const [],
    Iterable<TaskList> upsertLists = const [],
    Iterable<String> deleteListIds = const [],
    Iterable<TaskListEntry> upsertEntries = const [],
    Iterable<String> deleteEntryTaskIds = const [],
  }) async {}
}

final class _MemoryCalendarRepository implements CalendarRepository {
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
