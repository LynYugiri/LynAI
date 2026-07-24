import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/local_date.dart';
import 'package:lynai/models/task.dart';
import 'package:lynai/models/task_list.dart';
import 'package:lynai/pages/feature_page.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/repositories/task_repository.dart';
import 'package:provider/provider.dart';

import 'support/memory_repositories.dart';

void main() {
  testWidgets('Today is hidden when empty and visible when populated', (
    tester,
  ) async {
    final provider = _taskProvider();
    await _pumpTasks(tester, provider);

    expect(find.text('今日'), findsNothing);

    await provider.addTask(
      title: '今天截止',
      dueDate: LocalDate.fromDateTime(DateTime.now()),
    );
    await tester.pump();

    expect(find.text('今日'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '今日'));
    await tester.pumpAndSettle();
    expect(find.text('今天截止'), findsOneWidget);
  });

  testWidgets('deleting a list preserves its task in Inbox', (tester) async {
    final provider = _taskProvider();
    final listId = await provider.addList('工作');
    final taskId = await provider.addTask(title: '保留任务', listId: listId);
    await _pumpTasks(tester, provider);

    await tester.tap(find.text('工作'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('清单操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, '删除清单'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除清单'));
    await tester.pumpAndSettle();

    expect(provider.listById(listId), isNull);
    expect(provider.taskById(taskId), isNotNull);
    expect(provider.unlistedTasks.single.id, taskId);
    expect(find.text('保留任务'), findsOneWidget);
  });

  testWidgets('quick add creates a simple Inbox task', (tester) async {
    final provider = _taskProvider();
    await _pumpTasks(tester, provider);

    await tester.enterText(
      find.byKey(const ValueKey('task-quick-add')),
      '快速任务',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(provider.tasks.single.title, '快速任务');
    expect(provider.unlistedTasks.single.title, '快速任务');
    expect(find.text('快速任务'), findsOneWidget);
  });

  testWidgets('task checkbox completes the canonical task', (tester) async {
    final provider = _taskProvider();
    final taskId = await provider.addTask(title: '完成我');
    await _pumpTasks(tester, provider);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(provider.taskById(taskId)!.isCompleted, isTrue);
    expect(find.text('完成我'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '已完成'));
    await tester.pumpAndSettle();
    expect(find.text('完成我'), findsOneWidget);
  });
}

TaskProvider _taskProvider() {
  return TaskProvider(
    repository: _MemoryTaskRepository(),
    recycleBinRepository: MemoryRecycleBinRepository(),
  );
}

Future<void> _pumpTasks(WidgetTester tester, TaskProvider tasks) async {
  final settings = memorySettingsProvider();
  await settings.replaceSettings(
    settings.settings.copyWith(lastFeature: 'todos'),
  );
  await tester.binding.setSurfaceSize(const Size(500, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: tasks),
        ChangeNotifierProvider(create: (_) => CalendarProvider()),
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
