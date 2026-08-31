import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/anniversary.dart';
import '../../models/calendar_event.dart';
import '../../models/calendar_occurrence.dart';
import '../../models/item_reminder.dart';
import '../../models/local_date.dart';
import '../../models/local_time.dart';
import '../../models/task.dart';
import '../../providers/calendar_provider.dart';
import '../../providers/task_provider.dart';
import '../../services/calendar_platform_bridge.dart';
import '../../services/reminder_notification_permission_service.dart';
import '../../utils/calendar_timeline_layout.dart';
import 'feature_shell.dart';
import 'todo_lists_page.dart';
import '../../utils/reminder_editor.dart';

enum _CalendarMode { month, day, year }

/// 日程表页。
///
/// 月历、日视图与年览切换，整合任务与纪念日。
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => SchedulePageState();
}

/// [SchedulePage] 的状态。
class SchedulePageState extends State<SchedulePage> {
  static const _hourHeight = 56.0;
  static const _dayColumnWidth = 112.0;
  static const _timeColumnWidth = 52.0;
  static const _dayCount = 31;
  static const _dayHalf = _dayCount ~/ 2;
  static const _dayHeaderHeight = 58.0;
  static const _minDayZoom = 0.7;
  static const _maxDayZoom = 1.8;

  final _verticalController = ScrollController(
    initialScrollOffset: 8 * _hourHeight,
  );
  final _horizontalController = ScrollController(
    initialScrollOffset: _dayHalf * _dayColumnWidth,
  );
  final _headerController = ScrollController(
    initialScrollOffset: _dayHalf * _dayColumnWidth,
  );
  bool _syncingScroll = false;
  bool _completedExpanded = false;
  bool _dayNeedsCenter = true;
  double _dayZoom = 1.0;
  double _dayScaleStartZoom = 1.0;
  double? _dayScaleStartDistance;
  final Map<int, Offset> _dayPointerPositions = {};
  double _scheduleControlsCollapse = 0;
  _CalendarMode _mode = _CalendarMode.month;
  DateTime _focus = DateTime.now();
  DateTime? _selectedDate;
  DateTime? _dayWindowStart;

  @override
  void initState() {
    super.initState();
    _horizontalController.addListener(() {
      _syncHorizontalFrom(_horizontalController);
      _updateDayFocus();
    });
    _headerController.addListener(() => _syncHorizontalFrom(_headerController));
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    _headerController.dispose();
    super.dispose();
  }

  void _syncHorizontalFrom(ScrollController source) {
    if (_syncingScroll || !source.hasClients) return;
    _syncingScroll = true;
    for (final target in [_horizontalController, _headerController]) {
      if (identical(source, target) || !target.hasClients) continue;
      target.jumpTo(
        source.offset
            .clamp(
              target.position.minScrollExtent,
              target.position.maxScrollExtent,
            )
            .toDouble(),
      );
    }
    _syncingScroll = false;
  }

  void _setDayZoom(double value) {
    final next = value.clamp(_minDayZoom, _maxDayZoom).toDouble();
    if ((next - _dayZoom).abs() < 0.01) return;
    setState(() => _dayZoom = next);
  }

  void _handleDayPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      if (event is! PointerScrollEvent) return;
      final delta = event.scrollDelta.dy < 0 ? 0.08 : -0.08;
      _setDayZoom(_dayZoom + delta);
    });
  }

  void _handleDayPointerDown(PointerDownEvent event) {
    _dayPointerPositions[event.pointer] = event.localPosition;
    if (_dayPointerPositions.length == 2) {
      _dayScaleStartZoom = _dayZoom;
      _dayScaleStartDistance = _dayPointerDistance();
    }
  }

  void _handleDayPointerMove(PointerMoveEvent event) {
    if (!_dayPointerPositions.containsKey(event.pointer)) return;
    _dayPointerPositions[event.pointer] = event.localPosition;
    final startDistance = _dayScaleStartDistance;
    final currentDistance = _dayPointerDistance();
    if (_dayPointerPositions.length < 2 ||
        startDistance == null ||
        startDistance <= 0 ||
        currentDistance == null) {
      return;
    }
    _setDayZoom(_dayScaleStartZoom * currentDistance / startDistance);
  }

  void _handleDayPointerEnd(PointerEvent event) {
    _dayPointerPositions.remove(event.pointer);
    if (_dayPointerPositions.length < 2) {
      _dayScaleStartDistance = null;
      _dayScaleStartZoom = _dayZoom;
    } else {
      _dayScaleStartDistance = _dayPointerDistance();
      _dayScaleStartZoom = _dayZoom;
    }
  }

  double? _dayPointerDistance() {
    if (_dayPointerPositions.length < 2) return null;
    final values = _dayPointerPositions.values.take(2).toList();
    return (values[0] - values[1]).distance;
  }

  bool _onScheduleScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta;
      if (delta == null || delta == 0) return false;
      final next = (_scheduleControlsCollapse + delta / 72).clamp(0.0, 1.0);
      if ((next - _scheduleControlsCollapse).abs() >= 0.01) {
        setState(() => _scheduleControlsCollapse = next);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final calendar = context.watch<CalendarProvider>();
    final tasks = context.watch<TaskProvider>();
    return Column(
      children: [
        _header(),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScheduleScroll,
            child: switch (_mode) {
              _CalendarMode.month => _monthView(calendar, tasks),
              _CalendarMode.day => _dayView(calendar, tasks),
              _CalendarMode.year => _yearView(calendar, tasks),
            },
          ),
        ),
      ],
    );
  }

  Widget _header() {
    final compact = MediaQuery.sizeOf(context).width < 620;
    final progress = _scheduleControlsCollapse;
    final navigator = Row(
      children: [
        IconButton.filledTonal(
          onPressed: () => _move(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                switch (_mode) {
                  _CalendarMode.month => '${_focus.year} 年 ${_focus.month} 月',
                  _CalendarMode.day =>
                    '${_focus.year}-${_two(_focus.month)}-${_two(_focus.day)}',
                  _CalendarMode.year => '${_focus.year} 年',
                },
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(switch (_mode) {
                _CalendarMode.month => '月历总览',
                _CalendarMode.day => '日程时间轴',
                _CalendarMode.year => '全年总览',
              }, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: () => _move(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
    final controls = ClipRect(
      child: Align(
        alignment: Alignment.centerRight,
        widthFactor: compact ? 1 : 1 - progress,
        heightFactor: compact ? 1 - progress : 1,
        child: Opacity(
          opacity: 1 - progress,
          child: Transform.translate(
            offset: Offset(0, -12 * progress),
            child: IgnorePointer(
              key: const ValueKey('schedule-controls'),
              ignoring: progress > 0.6,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<_CalendarMode>(
                    key: const ValueKey('calendar-mode-switch'),
                    segments: const [
                      ButtonSegment(
                        value: _CalendarMode.month,
                        label: Text('月'),
                      ),
                      ButtonSegment(value: _CalendarMode.day, label: Text('日')),
                      ButtonSegment(
                        value: _CalendarMode.year,
                        label: Text('年'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (value) => setState(() {
                      _mode = value.first;
                      if (_mode == _CalendarMode.day) {
                        _dayWindowStart = _dateOnly(
                          _focus,
                        ).subtract(const Duration(days: _dayHalf));
                        _dayNeedsCenter = true;
                      }
                    }),
                  ),
                  const SizedBox(width: 8),
                  AddMenuButton(
                    items: const [
                      AddMenuItem('event', Icons.event_outlined, '新建事件'),
                      AddMenuItem('task', Icons.task_alt, '新建任务'),
                      AddMenuItem('anniversary', Icons.cake_outlined, '新建纪念日'),
                    ],
                    onSelected: (value) {
                      switch (value) {
                        case 'event':
                          _openEventEditor();
                        case 'task':
                          _openTaskEditor();
                        case 'anniversary':
                          _openAnniversaryEditor();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: compact
          ? Column(
              children: [
                navigator,
                SizedBox(height: 10 * (1 - progress)),
                Align(alignment: Alignment.centerRight, child: controls),
              ],
            )
          : Row(
              children: [
                Expanded(child: navigator),
                controls,
              ],
            ),
    );
  }

  void _move(int delta) {
    setState(() {
      _focus = switch (_mode) {
        _CalendarMode.month => DateTime(_focus.year, _focus.month + delta, 1),
        _CalendarMode.day => _focus.add(Duration(days: delta)),
        _CalendarMode.year => DateTime(_focus.year + delta, 1, 1),
      };
      if (_mode != _CalendarMode.month) _selectedDate = null;
      if (_mode == _CalendarMode.day &&
          (_dayWindowStart == null ||
              _focus.isBefore(_dayWindowStart!) ||
              !_focus.isBefore(
                _dayWindowStart!.add(const Duration(days: _dayCount)),
              ))) {
        _dayWindowStart = _dateOnly(
          _focus,
        ).subtract(const Duration(days: _dayHalf));
      }
      if (_mode == _CalendarMode.day) _dayNeedsCenter = true;
    });
    if (_mode == _CalendarMode.day) _centerFocusedDay();
  }

  List<CalendarOccurrence> _occurrences(
    CalendarProvider calendar,
    TaskProvider tasks,
    DateTime start,
    DateTime endExclusive,
  ) {
    // occurrence 仅是 canonical 源对象在半开日期区间内的投影，不在页面保存副本。
    return calendar.occurrencesInRange(
      startDate: LocalDate.fromDateTime(start),
      endDateExclusive: LocalDate.fromDateTime(endExclusive),
      tasks: tasks.tasks,
    );
  }

  List<CalendarOccurrence> _onDate(
    List<CalendarOccurrence> occurrences,
    DateTime date,
  ) {
    final localDate = LocalDate.fromDateTime(date);
    return occurrences.where((value) => _occursOn(value, localDate)).toList();
  }

  bool _occursOn(CalendarOccurrence occurrence, LocalDate date) {
    if (occurrence.kind != CalendarOccurrenceKind.event) {
      return occurrence.date == date;
    }
    final end = occurrence.endDateExclusive ?? occurrence.date.addDays(1);
    return occurrence.date.compareTo(date) <= 0 && date.compareTo(end) < 0;
  }

  Widget _monthView(CalendarProvider calendar, TaskProvider tasks) {
    final monthStart = DateTime(_focus.year, _focus.month, 1);
    final monthEnd = DateTime(_focus.year, _focus.month + 1, 1);
    final occurrences = _occurrences(calendar, tasks, monthStart, monthEnd);
    final leading = monthStart.weekday - 1;
    final days = monthEnd.subtract(const Duration(days: 1)).day;
    final total = ((leading + days + 6) ~/ 7) * 7;
    final selected = _selectedDate;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () {
                  final now = DateTime.now();
                  setState(() {
                    _focus = DateTime(now.year, now.month, 1);
                  });
                  _openDaySheet(_dateOnly(now), calendar, tasks);
                },
                icon: const Icon(Icons.today, size: 18),
                label: const Text('今天'),
              ),
              const Spacer(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: const ['一', '二', '三', '四', '五', '六', '日']
                .map(
                  (value) => Expanded(
                    child: Center(
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: total,
            itemBuilder: (context, index) {
              if (index < leading || index >= leading + days) {
                return const SizedBox.shrink();
              }
              final date = DateTime(
                _focus.year,
                _focus.month,
                index - leading + 1,
              );
              return _monthCell(
                date,
                _onDate(occurrences, date),
                selected != null && _sameDate(selected, date),
                calendar,
                tasks,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _monthCell(
    DateTime date,
    List<CalendarOccurrence> occurrences,
    bool selected,
    CalendarProvider calendar,
    TaskProvider tasks,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final today = _sameDate(date, DateTime.now());
    final hasCalendar = occurrences.any(
      (value) =>
          value.kind == CalendarOccurrenceKind.event ||
          value.kind == CalendarOccurrenceKind.anniversary,
    );
    final hasIncompleteTask = occurrences.any(
      (value) => _isTask(value) && !value.isCompleted,
    );
    return Material(
      color: selected
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () => _openDaySheet(date, calendar, tasks),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected || today ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: today ? scheme.primary : null,
                  ),
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (hasCalendar || hasIncompleteTask)
                    _marker(
                      scheme.error,
                      key: const ValueKey('month-date-dot'),
                    ),
                ],
              ),
              if (occurrences.isNotEmpty)
                Text(
                  '${occurrences.length}',
                  style: const TextStyle(fontSize: 9),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _marker(Color color, {Key? key}) => Container(
    key: key,
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Future<void> _openDaySheet(
    DateTime date,
    CalendarProvider calendar,
    TaskProvider tasks,
  ) async {
    final day = _dateOnly(date);
    setState(() => _selectedDate = day);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) =>
          _daySheetContent(sheetContext, day, calendar, tasks),
    );
    if (!mounted) return;
    final selected = _selectedDate;
    if (selected != null && _sameDate(selected, day)) {
      setState(() => _selectedDate = null);
    }
  }

  Widget _daySheetContent(
    BuildContext sheetContext,
    DateTime date,
    CalendarProvider calendar,
    TaskProvider tasks,
  ) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
          ),
          child: ListenableBuilder(
            listenable: Listenable.merge([calendar, tasks]),
            builder: (context, _) {
              final dayStart = _dateOnly(date);
              final occurrences = _occurrences(
                calendar,
                tasks,
                dayStart,
                dayStart.add(const Duration(days: 1)),
              );
              final visible = occurrences
                  .where((value) => !_isTask(value) || !value.isCompleted)
                  .toList();
              final completed = occurrences
                  .where((value) => _isTask(value) && value.isCompleted)
                  .toList();
              return ListView(
                shrinkWrap: true,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${date.year}-${_two(date.month)}-${_two(date.day)}  周${_weekday(date.weekday)}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  if (visible.isEmpty && completed.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(child: Text('这一天没有事项')),
                    ),
                  ...visible.map(
                    (value) => _occurrenceTile(
                      value,
                      calendar,
                      tasks,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _editOccurrence(value, calendar, tasks);
                      },
                    ),
                  ),
                  if (completed.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      initiallyExpanded: _completedExpanded,
                      onExpansionChanged: (value) => _completedExpanded = value,
                      title: Text('已完成 (${completed.length})'),
                      children: completed
                          .map(
                            (value) => _occurrenceTile(
                              value,
                              calendar,
                              tasks,
                              onTap: () {
                                Navigator.of(sheetContext).pop();
                                _editOccurrence(value, calendar, tasks);
                              },
                            ),
                          )
                          .toList(),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _occurrenceTile(
    CalendarOccurrence occurrence,
    CalendarProvider calendar,
    TaskProvider tasks, {
    VoidCallback? onTap,
  }) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: _isTask(occurrence)
          ? Checkbox(
              value: occurrence.isCompleted,
              onChanged: (_) => occurrence.isCompleted
                  ? tasks.uncompleteTask(occurrence.sourceId)
                  : tasks.completeTask(occurrence.sourceId),
            )
          : Icon(
              occurrence.kind == CalendarOccurrenceKind.anniversary
                  ? Icons.cake_outlined
                  : Icons.event_outlined,
            ),
      title: Text(
        occurrence.title,
        style: TextStyle(
          decoration: occurrence.isCompleted
              ? TextDecoration.lineThrough
              : null,
        ),
      ),
      subtitle: Text(_occurrenceSubtitle(occurrence)),
      onTap: onTap ?? () => _editOccurrence(occurrence, calendar, tasks),
    );
  }

  Widget _dayView(CalendarProvider calendar, TaskProvider tasks) {
    final windowStart = _dayWindowStart ??= _dateOnly(
      _focus,
    ).subtract(const Duration(days: _dayHalf));
    final windowEnd = windowStart.add(const Duration(days: _dayCount));
    final occurrences = _occurrences(calendar, tasks, windowStart, windowEnd);
    final days = List.generate(
      _dayCount,
      (index) => windowStart.add(Duration(days: index)),
    );
    final scheme = Theme.of(context).colorScheme;
    final hourRowHeight = _hourHeight * _dayZoom;
    final dayColumnWidth = _dayColumnWidth * _dayZoom;
    final timelineHeight = 24 * hourRowHeight;
    final timelineWidth = _dayCount * dayColumnWidth;
    if (_dayNeedsCenter) {
      _dayNeedsCenter = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _horizontalController.hasClients) {
          _centerFocusedDay(jump: true);
        }
      });
    }
    return Listener(
      onPointerSignal: _handleDayPointerSignal,
      onPointerDown: _handleDayPointerDown,
      onPointerMove: _handleDayPointerMove,
      onPointerUp: _handleDayPointerEnd,
      onPointerCancel: _handleDayPointerEnd,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            children: [
              SizedBox(
                height: _dayHeaderHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: _timeColumnWidth,
                      child: Center(
                        child: Text(
                          '${(_dayZoom * 100).round()}%',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _headerController,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: days.map((date) {
                            final values = _onDate(occurrences, date);
                            final hasIncompleteTask = values.any(
                              (value) => _isTask(value) && !value.isCompleted,
                            );
                            return InkWell(
                              onTap: () => setState(() => _focus = date),
                              child: Container(
                                width: dayColumnWidth,
                                height: _dayHeaderHeight,
                                decoration: BoxDecoration(
                                  color: _sameDate(date, _focus)
                                      ? scheme.primaryContainer
                                      : null,
                                  border: Border(
                                    left: BorderSide(
                                      color: scheme.outlineVariant,
                                    ),
                                    bottom: BorderSide(
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('周${_weekday(date.weekday)}'),
                                        Text(
                                          '${date.month}/${date.day}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (hasIncompleteTask)
                                      Positioned(
                                        right: 8,
                                        top: 8,
                                        child: _marker(scheme.error),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _verticalController,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: _timeColumnWidth,
                        height: timelineHeight,
                        child: Stack(
                          children: [
                            for (var hour = 0; hour < 24; hour++)
                              Positioned(
                                top: hour * hourRowHeight,
                                right: 4,
                                child: Text(
                                  '${_two(hour)}:00',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _horizontalController,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: timelineWidth,
                            height: timelineHeight,
                            child: Stack(
                              children: [
                                for (var hour = 0; hour < 24; hour++)
                                  Positioned(
                                    top: hour * hourRowHeight,
                                    left: 0,
                                    right: 0,
                                    child: Divider(
                                      height: 1,
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                                for (
                                  var index = 0;
                                  index < days.length;
                                  index++
                                )
                                  Positioned(
                                    left: index * dayColumnWidth,
                                    top: 0,
                                    width: dayColumnWidth,
                                    height: timelineHeight,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          left: BorderSide(
                                            color: scheme.outlineVariant,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                for (
                                  var index = 0;
                                  index < days.length;
                                  index++
                                )
                                  ..._timelineBlocks(
                                    days[index],
                                    _onDate(occurrences, days[index]),
                                    index,
                                    calendar,
                                    tasks,
                                    hourRowHeight: hourRowHeight,
                                    dayColumnWidth: dayColumnWidth,
                                  ),
                                for (
                                  var index = 0;
                                  index < days.length;
                                  index++
                                )
                                  ..._dayTopChips(
                                    days[index],
                                    _onDate(occurrences, days[index]),
                                    index,
                                    calendar,
                                    tasks,
                                    dayColumnWidth: dayColumnWidth,
                                  ),
                                if (days.any(
                                  (value) => _sameDate(value, DateTime.now()),
                                ))
                                  _nowLine(
                                    days,
                                    DateTime.now(),
                                    scheme,
                                    hourRowHeight: hourRowHeight,
                                    dayColumnWidth: dayColumnWidth,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _dayTopChips(
    DateTime date,
    List<CalendarOccurrence> occurrences,
    int dayIndex,
    CalendarProvider calendar,
    TaskProvider tasks, {
    required double dayColumnWidth,
  }) {
    final values = occurrences
        .where((value) {
          return value.kind == CalendarOccurrenceKind.anniversary ||
              value.isAllDay ||
              _isTask(value);
        })
        .take(3)
        .toList();
    final scheme = Theme.of(context).colorScheme;
    return [
      for (var index = 0; index < values.length; index++)
        Positioned(
          left: dayIndex * dayColumnWidth + 3,
          top: 4 + index * 20.0,
          width: dayColumnWidth - 8,
          height: 18,
          child: _dayTopChip(values[index], calendar, tasks, scheme),
        ),
    ];
  }

  Widget _dayTopChip(
    CalendarOccurrence occurrence,
    CalendarProvider calendar,
    TaskProvider tasks,
    ColorScheme scheme,
  ) {
    final task = _isTask(occurrence);
    return Material(
      color: task ? scheme.errorContainer : scheme.primaryContainer,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: () => _editOccurrence(occurrence, calendar, tasks),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_occurrenceIconText(occurrence)} ${occurrence.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                color: task
                    ? scheme.onErrorContainer
                    : scheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _timelineBlocks(
    DateTime date,
    List<CalendarOccurrence> occurrences,
    int dayIndex,
    CalendarProvider calendar,
    TaskProvider tasks, {
    required double hourRowHeight,
    required double dayColumnWidth,
  }) {
    final timed = occurrences.where((value) {
      if (value.kind == CalendarOccurrenceKind.anniversary) return false;
      if (_isTask(value)) {
        final task = tasks.taskById(value.sourceId);
        return task?.plannedDate == LocalDate.fromDateTime(date) &&
            task?.plannedTime != null;
      }
      return !value.isAllDay;
    }).toList();
    final intervals = timed.map((value) {
      final range = _visibleMinutes(value, LocalDate.fromDateTime(date));
      final task = tasks.taskById(value.sourceId);
      final startMinute = _isTask(value) && task?.plannedTime != null
          ? _minuteOf(task!.plannedTime!)
          : range.$1;
      return CalendarTimelineInterval(
        value: value,
        startMinute: startMinute,
        endMinute: _isTask(value) ? startMinute + 30 : range.$2,
      );
    });
    return layoutCalendarTimeline(intervals).map((placement) {
      final laneWidth = (dayColumnWidth - 6) / placement.laneCount;
      final top = placement.startMinute / 60 * hourRowHeight;
      final height =
          ((placement.endMinute - placement.startMinute) / 60 * hourRowHeight)
              .clamp(24.0, 24 * hourRowHeight)
              .toDouble();
      final occurrence = placement.value;
      final task = _isTask(occurrence);
      final scheme = Theme.of(context).colorScheme;
      return Positioned(
        left: dayIndex * dayColumnWidth + 3 + placement.lane * laneWidth,
        top: top,
        width: laneWidth - 2,
        height: height,
        child: Material(
          color: task ? scheme.errorContainer : scheme.primaryContainer,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: () => _editOccurrence(occurrence, calendar, tasks),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                '${_timeText(occurrence.startTime)} ${occurrence.title}',
                maxLines: (height / 13).floor().clamp(1, 8),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9.5, height: 1.2),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  (int, int) _visibleMinutes(CalendarOccurrence occurrence, LocalDate date) {
    if (_isTask(occurrence)) {
      final start = _minuteOf(occurrence.startTime!);
      final end = occurrence.endTime == null
          ? start + 30
          : _minuteOf(occurrence.endTime!);
      return (start, end <= start ? start + 30 : end);
    }
    final startsToday = occurrence.date == date;
    final endExclusive =
        occurrence.endDateExclusive ?? occurrence.date.addDays(1);
    final endsToday = endExclusive == date.addDays(1);
    final start = startsToday ? _minuteOf(occurrence.startTime!) : 0;
    var end = endsToday && occurrence.endTime != null
        ? _minuteOf(occurrence.endTime!)
        : 24 * 60;
    if (end <= start) end = 24 * 60;
    // 跨日定时事件按当天可见区间裁剪，lane 计算只处理该日片段。
    return (start, end);
  }

  Widget _nowLine(
    List<DateTime> days,
    DateTime now,
    ColorScheme scheme, {
    required double hourRowHeight,
    required double dayColumnWidth,
  }) {
    final index = days.indexWhere((value) => _sameDate(value, now));
    return Positioned(
      left: index * dayColumnWidth,
      top: (now.hour * 60 + now.minute) / 60 * hourRowHeight,
      width: dayColumnWidth,
      child: Container(height: 2, color: scheme.error),
    );
  }

  void _updateDayFocus() {
    if (_mode != _CalendarMode.day || !_horizontalController.hasClients) return;
    final dayColumnWidth = _dayColumnWidth * _dayZoom;
    final center =
        _horizontalController.offset +
        _horizontalController.position.viewportDimension / 2;
    final index = (center / dayColumnWidth).floor().clamp(0, _dayCount - 1);
    final start = _dayWindowStart;
    if (start == null) return;
    final next = start.add(Duration(days: index));
    if (!_sameDate(next, _focus)) setState(() => _focus = next);
  }

  void _centerFocusedDay({bool jump = false}) {
    if (!_horizontalController.hasClients) return;
    final start = _dayWindowStart;
    if (start == null) return;
    final dayColumnWidth = _dayColumnWidth * _dayZoom;
    final index = _dateOnly(_focus).difference(start).inDays;
    if (index < 0 || index >= _dayCount) return;
    final target =
        index * dayColumnWidth -
        (_horizontalController.position.viewportDimension - dayColumnWidth) / 2;
    if (jump) {
      _horizontalController.jumpTo(
        target.clamp(0, _horizontalController.position.maxScrollExtent),
      );
    } else {
      _horizontalController.animateTo(
        target.clamp(0, _horizontalController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _yearView(CalendarProvider calendar, TaskProvider tasks) {
    final yearStart = DateTime(_focus.year, 1, 1);
    final yearEnd = DateTime(_focus.year + 1, 1, 1);
    final occurrences = _occurrences(calendar, tasks, yearStart, yearEnd);
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.sizeOf(context).width >= 900 ? 3 : 1,
        childAspectRatio: MediaQuery.sizeOf(context).width >= 900 ? 1.65 : 3.3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: 12,
      itemBuilder: (context, index) {
        final month = index + 1;
        final values = occurrences.where((value) {
          final monthStart = LocalDate(_focus.year, month, 1);
          final monthEnd = LocalDate.fromDateTime(
            DateTime(_focus.year, month + 1, 1),
          );
          return _occursInRange(value, monthStart, monthEnd);
        }).toList();
        final incomplete = values
            .where((value) => _isTask(value) && !value.isCompleted)
            .length;
        return Material(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() {
              _focus = DateTime(_focus.year, month, 1);
              _mode = _CalendarMode.month;
            }),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$month 月',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text('${values.length} 条事项'),
                  if (incomplete > 0)
                    Text(
                      '$incomplete 个未完成任务',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    values.take(3).map((value) => value.title).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _occursInRange(
    CalendarOccurrence occurrence,
    LocalDate start,
    LocalDate end,
  ) {
    final occurrenceEnd =
        occurrence.endDateExclusive ?? occurrence.date.addDays(1);
    return occurrence.date.compareTo(end) < 0 &&
        start.compareTo(occurrenceEnd) < 0;
  }

  Future<void> _editOccurrence(
    CalendarOccurrence occurrence,
    CalendarProvider calendar,
    TaskProvider tasks,
  ) async {
    switch (occurrence.kind) {
      case CalendarOccurrenceKind.event:
        await _openEventEditor(calendar.getEvent(occurrence.sourceId));
      case CalendarOccurrenceKind.anniversary:
        await _openAnniversaryEditor(
          calendar.getAnniversary(occurrence.sourceId),
        );
      case CalendarOccurrenceKind.taskPlanned:
      case CalendarOccurrenceKind.taskDue:
      case CalendarOccurrenceKind.taskPlannedAndDue:
        await _openTaskEditor(tasks.taskById(occurrence.sourceId));
    }
  }

  Future<void> _openEventEditor([CalendarEvent? event]) async {
    final provider = context.read<CalendarProvider>();
    final title = TextEditingController(text: event?.title ?? '');
    final note = TextEditingController(text: event?.note ?? '');
    final base = _selectedDate ?? _focus;
    var allDay = event?.spec is AllDayCalendarEventSpec;
    var startDate = switch (event?.spec) {
      TimedCalendarEventSpec value => _dateOnly(value.start),
      AllDayCalendarEventSpec value => value.startDate.atStartOfDay(),
      _ => _dateOnly(base),
    };
    var endDate = switch (event?.spec) {
      TimedCalendarEventSpec value => _dateOnly(value.end),
      AllDayCalendarEventSpec value =>
        value.endDateExclusive.addDays(-1).atStartOfDay(),
      _ => _dateOnly(base),
    };
    var startTime = switch (event?.spec) {
      TimedCalendarEventSpec value => TimeOfDay.fromDateTime(value.start),
      _ => TimeOfDay.fromDateTime(DateTime.now()),
    };
    var endTime = switch (event?.spec) {
      TimedCalendarEventSpec value => TimeOfDay.fromDateTime(value.end),
      _ => TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1))),
    };
    var reminderOffsets =
        event?.reminders.map((value) => value.offsetMinutes).toSet() ?? <int>{};
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => _editorSheet(
          context,
          title: event == null ? '新建事件' : '编辑事件',
          titleController: title,
          noteController: note,
          onDelete: event == null
              ? null
              : () => Navigator.pop(context, 'delete'),
          onSave: () => Navigator.pop(context, 'save'),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('全天事件'),
              value: allDay,
              onChanged: (value) => setSheet(() => allDay = value),
            ),
            _dateTile(context, '开始日期', startDate, (value) {
              setSheet(() {
                startDate = value;
                if (endDate.isBefore(startDate)) endDate = startDate;
              });
            }),
            if (!allDay)
              _timeTile(context, '开始时间', startTime, (value) {
                setSheet(() => startTime = value);
              }),
            _dateTile(context, '结束日期', endDate, (value) {
              setSheet(
                () => endDate = value.isBefore(startDate) ? startDate : value,
              );
            }),
            if (!allDay)
              _timeTile(context, '结束时间', endTime, (value) {
                setSheet(() => endTime = value);
              }),
            _reminderPicker(
              reminderOffsets,
              allDay: allDay,
              onChanged: (value) => setSheet(() => reminderOffsets = value),
            ),
          ],
        ),
      ),
    );
    final titleText = title.text.trim();
    final noteText = note.text.trim();
    title.dispose();
    note.dispose();
    if (!mounted || action == null) return;
    if (action == 'delete' && event != null) {
      await provider.deleteEvent(event.id);
      return;
    }
    if (titleText.isEmpty) return;
    CalendarEventSpec spec;
    if (allDay) {
      spec = AllDayCalendarEventSpec(
        startDate: LocalDate.fromDateTime(startDate),
        endDateExclusive: LocalDate.fromDateTime(endDate).addDays(1),
      );
    } else {
      final start = _combine(startDate, startTime);
      var end = _combine(endDate, endTime);
      if (!end.isAfter(start)) end = start.add(const Duration(hours: 1));
      spec = TimedCalendarEventSpec(start: start, end: end);
    }
    final reminders = reconcilePresetReminders(
      existing: event?.reminders ?? const [],
      selectedOffsets: reminderOffsets,
      anchor: ItemReminderAnchor.eventStart,
      dateOnly: allDay,
    );
    final calendarBridge = context.read<CalendarPlatformBridge?>();
    if (event == null) {
      await provider.addEvent(
        title: titleText,
        note: noteText.isEmpty ? null : noteText,
        spec: spec,
        reminders: reminders,
      );
    } else {
      await provider.updateEvent(
        event.copyWith(
          title: titleText,
          note: noteText.isEmpty ? null : noteText,
          spec: spec,
          reminders: reminders,
        ),
      );
    }
    await ReminderNotificationPermissionService.requestAfterExplicitSave(
      bridge: calendarBridge,
      previousReminderCount: event?.reminders.length ?? 0,
      savedReminderCount: reminders.length,
    );
  }

  Future<void> _openTaskEditor([Task? task]) async {
    final base = _selectedDate ?? _focus;
    await openCanonicalTaskEditor(
      context,
      task: task,
      initialPlannedDate: task == null ? LocalDate.fromDateTime(base) : null,
    );
  }

  Future<void> _openAnniversaryEditor([Anniversary? anniversary]) async {
    final provider = context.read<CalendarProvider>();
    final title = TextEditingController(text: anniversary?.title ?? '');
    final note = TextEditingController(text: anniversary?.note ?? '');
    final initialDate = switch (anniversary?.spec) {
      OnceAnniversarySpec value => value.date.atStartOfDay(),
      YearlyAnniversarySpec value => DateTime(2000, value.month, value.day),
      _ => _selectedDate ?? _focus,
    };
    var yearly = anniversary?.spec is YearlyAnniversarySpec;
    var date = initialDate;
    var hasSourceYear =
        anniversary?.spec is YearlyAnniversarySpec &&
        (anniversary!.spec as YearlyAnniversarySpec).sourceYear != null;
    var sourceYear = switch (anniversary?.spec) {
      YearlyAnniversarySpec value => value.sourceYear ?? initialDate.year,
      _ => initialDate.year,
    };
    var showYearCount = anniversary?.showYearCount ?? false;
    var reminderOffsets =
        anniversary?.reminders.map((value) => value.offsetMinutes).toSet() ??
        <int>{};
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => _editorSheet(
          context,
          title: anniversary == null ? '新建纪念日' : '编辑纪念日',
          titleController: title,
          noteController: note,
          onDelete: anniversary == null
              ? null
              : () => Navigator.pop(context, 'delete'),
          onSave: () => Navigator.pop(context, 'save'),
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('仅一次')),
                ButtonSegment(value: true, label: Text('每年')),
              ],
              selected: {yearly},
              onSelectionChanged: (value) =>
                  setSheet(() => yearly = value.first),
            ),
            _dateTile(context, yearly ? '月日' : '日期', date, (value) {
              setSheet(() => date = value);
            }),
            if (yearly)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('记录来源年份'),
                value: hasSourceYear,
                onChanged: (value) => setSheet(() {
                  hasSourceYear = value;
                  if (!value) showYearCount = false;
                }),
              ),
            if (yearly && hasSourceYear)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('来源年份'),
                subtitle: Text('$sourceYear'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => setSheet(() => sourceYear--),
                      icon: const Icon(Icons.remove),
                    ),
                    IconButton(
                      onPressed: () => setSheet(() => sourceYear++),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
            if (yearly && hasSourceYear)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('显示周年数'),
                value: showYearCount,
                onChanged: (value) => setSheet(() => showYearCount = value),
              ),
            if (yearly && date.month == 2 && date.day == 29)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline),
                title: Text('非闰年按 2 月 28 日显示'),
              ),
            _reminderPicker(
              reminderOffsets,
              allDay: true,
              onChanged: (value) => setSheet(() => reminderOffsets = value),
            ),
          ],
        ),
      ),
    );
    final titleText = title.text.trim();
    final noteText = note.text.trim();
    title.dispose();
    note.dispose();
    if (!mounted || action == null) return;
    if (action == 'delete' && anniversary != null) {
      await provider.deleteAnniversary(anniversary.id);
      return;
    }
    if (titleText.isEmpty) return;
    final spec = yearly
        ? YearlyAnniversarySpec(
            month: date.month,
            day: date.day,
            sourceYear: hasSourceYear ? sourceYear : null,
          )
        : OnceAnniversarySpec(date: LocalDate.fromDateTime(date));
    final reminders = reconcilePresetReminders(
      existing: anniversary?.reminders ?? const [],
      selectedOffsets: reminderOffsets,
      anchor: ItemReminderAnchor.anniversaryDate,
      dateOnly: true,
    );
    final calendarBridge = context.read<CalendarPlatformBridge?>();
    if (anniversary == null) {
      await provider.addAnniversary(
        title: titleText,
        note: noteText.isEmpty ? null : noteText,
        spec: spec,
        showYearCount: yearly && hasSourceYear && showYearCount,
        reminders: reminders,
      );
    } else {
      await provider.updateAnniversary(
        anniversary.copyWith(
          title: titleText,
          note: noteText.isEmpty ? null : noteText,
          spec: spec,
          showYearCount: yearly && hasSourceYear && showYearCount,
          reminders: reminders,
        ),
      );
    }
    await ReminderNotificationPermissionService.requestAfterExplicitSave(
      bridge: calendarBridge,
      previousReminderCount: anniversary?.reminders.length ?? 0,
      savedReminderCount: reminders.length,
    );
  }

  Widget _editorSheet(
    BuildContext context, {
    required String title,
    required TextEditingController titleController,
    required TextEditingController noteController,
    required List<Widget> children,
    required VoidCallback onSave,
    VoidCallback? onDelete,
  }) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: '标题',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              ...children,
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('保存'),
                  ),
                  if (onDelete != null) ...[
                    const SizedBox(width: 10),
                    TextButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('删除'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateTile(
    BuildContext context,
    String label,
    DateTime value,
    ValueChanged<DateTime> onChanged,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text('${value.year}-${_two(value.month)}-${_two(value.day)}'),
      trailing: const Icon(Icons.date_range_outlined),
      onTap: () async {
        final selected = await showDatePicker(
          context: context,
          firstDate: DateTime(1900),
          lastDate: DateTime(2200),
          initialDate: value,
        );
        if (selected != null) onChanged(selected);
      },
    );
  }

  Widget _timeTile(
    BuildContext context,
    String label,
    TimeOfDay value,
    ValueChanged<TimeOfDay> onChanged,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value.format(context)),
      trailing: const Icon(Icons.schedule),
      onTap: () async {
        final selected = await showTimePicker(
          context: context,
          initialTime: value,
        );
        if (selected != null) onChanged(selected);
      },
    );
  }

  Widget _reminderPicker(
    Set<int> selected, {
    required bool allDay,
    required ValueChanged<Set<int>> onChanged,
  }) {
    const choices = <int, String>{
      0: '准时',
      -10: '提前 10 分钟',
      -30: '提前 30 分钟',
      -60: '提前 1 小时',
      -1440: '提前 1 天',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('提醒', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        Wrap(
          spacing: 6,
          children: choices.entries.map((entry) {
            return FilterChip(
              label: Text(entry.value),
              selected: selected.contains(entry.key),
              onSelected: (enabled) {
                final next = Set<int>.of(selected);
                enabled ? next.add(entry.key) : next.remove(entry.key);
                onChanged(next);
              },
            );
          }).toList(),
        ),
        if (allDay && selected.isNotEmpty)
          const Text('日期型提醒默认在当天 09:00 触发', style: TextStyle(fontSize: 12)),
      ],
    );
  }

  String _occurrenceSubtitle(CalendarOccurrence occurrence) {
    if (occurrence.kind == CalendarOccurrenceKind.anniversary) return '纪念日';
    if (_isTask(occurrence)) {
      final kind = switch (occurrence.kind) {
        CalendarOccurrenceKind.taskPlanned => '计划',
        CalendarOccurrenceKind.taskDue => '截止',
        _ => '计划 / 截止',
      };
      return occurrence.startTime == null
          ? kind
          : '$kind ${_timeText(occurrence.startTime)}';
    }
    if (occurrence.isAllDay) return '全天 / 跨日事件';
    return '${_timeText(occurrence.startTime)} - ${_timeText(occurrence.endTime)}';
  }

  String _occurrenceIconText(CalendarOccurrence occurrence) {
    if (occurrence.kind == CalendarOccurrenceKind.anniversary) return '纪';
    if (_isTask(occurrence)) return occurrence.isCompleted ? '✓' : '任';
    return '事';
  }

  bool _isTask(CalendarOccurrence occurrence) {
    return occurrence.kind == CalendarOccurrenceKind.taskPlanned ||
        occurrence.kind == CalendarOccurrenceKind.taskDue ||
        occurrence.kind == CalendarOccurrenceKind.taskPlannedAndDue;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static bool _sameDate(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  static DateTime _combine(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  static int _minuteOf(LocalTime value) => value.hour * 60 + value.minute;

  static String _timeText(LocalTime? value) =>
      value == null ? '' : '${_two(value.hour)}:${_two(value.minute)}';

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _weekday(int value) =>
      const ['一', '二', '三', '四', '五', '六', '日'][value - 1];
}
