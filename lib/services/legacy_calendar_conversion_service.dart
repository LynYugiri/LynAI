import '../models/calendar_event.dart';
import '../models/local_date.dart';
import '../models/local_time.dart';
import '../models/schedule_item.dart';
import '../models/task.dart';
import '../models/task_list.dart' as domain;
import '../models/todo_list.dart' as legacy;

/// 旧待办清单转换后的独立领域对象集合。
final class LegacyTodoListConversion {
  /// 新任务清单元数据。
  final domain.TaskList taskList;

  /// 从旧清单项转换的任务。
  final List<Task> tasks;

  /// 保留旧清单顺序的归属条目。
  final List<domain.TaskListEntry> entries;

  /// 创建转换结果。
  LegacyTodoListConversion({
    required this.taskList,
    required List<Task> tasks,
    required List<domain.TaskListEntry> entries,
  }) : tasks = List.unmodifiable(tasks),
       entries = List.unmodifiable(entries);
}

/// 将旧日程和待办模型转换为新领域模型的无状态辅助服务。
final class LegacyCalendarConversionService {
  const LegacyCalendarConversionService();

  /// 将旧普通日程转换为定时日历事件。
  CalendarEvent calendarEventFromSchedule(ScheduleItem item) {
    if (item.isTask) {
      throw ArgumentError.value(item.kind, 'item.kind', '任务日程不能转换为事件');
    }
    return CalendarEvent(
      id: item.id,
      title: item.title,
      note: item.note,
      spec: TimedCalendarEventSpec(start: item.start, end: item.end),
      createdAt: item.start,
      updatedAt: item.start,
    );
  }

  /// 将旧任务日程转换为任务，并丢弃用于占位的一分钟结束时刻。
  Task taskFromSchedule(ScheduleItem item) {
    if (!item.isTask) {
      throw ArgumentError.value(item.kind, 'item.kind', '普通日程不能转换为任务');
    }
    return Task(
      id: item.id,
      title: item.title,
      note: item.note,
      plannedDate: LocalDate.fromDateTime(item.start),
      plannedTime: LocalTime.fromDateTime(item.start),
      createdAt: item.start,
      updatedAt: item.start,
    );
  }

  /// 将单个旧待办项转换为任务。
  Task taskFromTodoItem(
    legacy.TodoItem item, {
    required DateTime createdAt,
    DateTime? fallbackUpdatedAt,
  }) {
    final updatedAt = item.updatedAt ?? fallbackUpdatedAt ?? createdAt;
    return Task(
      id: item.id,
      title: item.text,
      completedAt: item.done ? updatedAt : null,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// 将旧嵌入式待办清单拆分为清单元数据、任务和归属条目。
  LegacyTodoListConversion todoList(legacy.TodoList list) {
    final tasks = <Task>[];
    final entries = <domain.TaskListEntry>[];
    for (var index = 0; index < list.items.length; index++) {
      final item = list.items[index];
      tasks.add(
        taskFromTodoItem(
          item,
          createdAt: list.createdAt,
          fallbackUpdatedAt: list.updatedAt,
        ),
      );
      entries.add(
        domain.TaskListEntry(
          taskListId: list.id,
          taskId: item.id,
          position: index,
          updatedAt: item.updatedAt ?? list.updatedAt,
        ),
      );
    }
    return LegacyTodoListConversion(
      taskList: domain.TaskList(
        id: list.id,
        title: list.title,
        sortOrder: 0,
        createdAt: list.createdAt,
        updatedAt: list.updatedAt,
      ),
      tasks: tasks,
      entries: entries,
    );
  }
}
