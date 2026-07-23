part of '../feature_page.dart';

enum _CalendarMode { month, day, year }

class _SchedulePage extends StatefulWidget {
  const _SchedulePage();

  @override
  State<_SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<_SchedulePage> {
  static const _hourHeight = 56.0;
  static const _dayColumnWidth = 112.0;
  static const _timeColumnWidth = 52.0;
  static const _dayCount = 31;
  static const _dayHalf = _dayCount ~/ 2;
  static const _dayHeaderHeight = 58.0;

  final _verticalController = ScrollController(
    initialScrollOffset: 8 * _hourHeight,
  );
  final _horizontalController = ScrollController(
    initialScrollOffset: _dayHalf * _dayColumnWidth,
  );
  final _headerController = ScrollController(
    initialScrollOffset: _dayHalf * _dayColumnWidth,
  );
  final _summaryController = ScrollController(
    initialScrollOffset: _dayHalf * _dayColumnWidth,
  );
  bool _syncingScroll = false;
  bool _completedExpanded = false;
  bool _dayNeedsCenter = true;
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
    _summaryController.addListener(
      () => _syncHorizontalFrom(_summaryController),
    );
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    _headerController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  void _syncHorizontalFrom(ScrollController source) {
    if (_syncingScroll || !source.hasClients) return;
    _syncingScroll = true;
    for (final target in [
      _horizontalController,
      _headerController,
      _summaryController,
    ]) {
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

  @override
  Widget build(BuildContext context) {
    final calendar = context.watch<CalendarProvider>();
    final tasks = context.watch<TaskProvider>();
    return Column(
      children: [
        _header(),
        Expanded(
          child: switch (_mode) {
            _CalendarMode.month => _monthView(calendar, tasks),
            _CalendarMode.day => _dayView(calendar, tasks),
            _CalendarMode.year => _yearView(calendar, tasks),
          },
        ),
      ],
    );
  }

  Widget _header() {
    final compact = MediaQuery.sizeOf(context).width < 620;
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
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<_CalendarMode>(
          segments: const [
            ButtonSegment(value: _CalendarMode.month, label: Text('月')),
            ButtonSegment(value: _CalendarMode.day, label: Text('日')),
            ButtonSegment(value: _CalendarMode.year, label: Text('年')),
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
        _AddMenuButton(
          items: const [
            _AddMenuItem('event', Icons.event_outlined, '新建事件'),
            _AddMenuItem('task', Icons.task_alt, '新建任务'),
            _AddMenuItem('anniversary', Icons.cake_outlined, '新建纪念日'),
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
                const SizedBox(height: 10),
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
                onPressed: () => setState(() {
                  _focus = DateTime.now();
                  _selectedDate = _dateOnly(DateTime.now());
                }),
                icon: const Icon(Icons.today, size: 18),
                label: const Text('今天'),
              ),
              const Spacer(),
              if (selected != null)
                IconButton(
                  tooltip: '关闭日期详情',
                  onPressed: () => setState(() => _selectedDate = null),
                  icon: const Icon(Icons.close),
                ),
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
              );
            },
          ),
        ),
        if (selected != null)
          Expanded(
            child: _dateDetail(
              selected,
              _onDate(occurrences, selected),
              calendar,
              tasks,
            ),
          ),
      ],
    );
  }

  Widget _monthCell(
    DateTime date,
    List<CalendarOccurrence> occurrences,
    bool selected,
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
        onTap: () => setState(() => _selectedDate = date),
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
                  if (hasCalendar) _marker(scheme.primary),
                  if (hasCalendar && hasIncompleteTask)
                    const SizedBox(width: 4),
                  if (hasIncompleteTask) _marker(scheme.error),
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

  Widget _marker(Color color) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Widget _dateDetail(
    DateTime date,
    List<CalendarOccurrence> occurrences,
    CalendarProvider calendar,
    TaskProvider tasks,
  ) {
    final anniversaries = occurrences
        .where((value) => value.kind == CalendarOccurrenceKind.anniversary)
        .toList();
    final allDay = occurrences.where((value) {
      return value.kind == CalendarOccurrenceKind.event &&
          (value.isAllDay || value.endDateExclusive != value.date.addDays(1));
    }).toList();
    final timed = occurrences.where((value) {
      return value.kind == CalendarOccurrenceKind.event &&
          !allDay.contains(value);
    }).toList();
    final incomplete = occurrences
        .where((value) => _isTask(value) && !value.isCompleted)
        .toList();
    final completed = occurrences
        .where((value) => _isTask(value) && value.isCompleted)
        .toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            '${date.year}-${_two(date.month)}-${_two(date.day)}  周${_weekday(date.weekday)}',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (occurrences.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Text('这一天没有事项')),
            ),
          _detailGroup(
            '纪念日',
            Icons.cake_outlined,
            anniversaries,
            calendar,
            tasks,
          ),
          _detailGroup('全天 / 跨日', Icons.event_note, allDay, calendar, tasks),
          _detailGroup('定时事件', Icons.schedule, timed, calendar, tasks),
          _detailGroup('未完成任务', Icons.task_alt, incomplete, calendar, tasks),
          if (completed.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: _completedExpanded,
              onExpansionChanged: (value) => _completedExpanded = value,
              title: Text('已完成 (${completed.length})'),
              children: completed
                  .map((value) => _occurrenceTile(value, calendar, tasks))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _detailGroup(
    String title,
    IconData icon,
    List<CalendarOccurrence> values,
    CalendarProvider calendar,
    TaskProvider tasks,
  ) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          ...values.map((value) => _occurrenceTile(value, calendar, tasks)),
        ],
      ),
    );
  }

  Widget _occurrenceTile(
    CalendarOccurrence occurrence,
    CalendarProvider calendar,
    TaskProvider tasks,
  ) {
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
      onTap: () => _editOccurrence(occurrence, calendar, tasks),
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
    final timelineHeight = 24 * _hourHeight;
    if (_dayNeedsCenter) {
      _dayNeedsCenter = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _horizontalController.hasClients) {
          _centerFocusedDay(jump: true);
        }
      });
    }
    return Padding(
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
                  const SizedBox(width: _timeColumnWidth),
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
                              width: _dayColumnWidth,
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
            _daySummaryRow(days, occurrences, calendar, tasks),
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
                              top: hour * _hourHeight,
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
                          width: _dayCount * _dayColumnWidth,
                          height: timelineHeight,
                          child: Stack(
                            children: [
                              for (var hour = 0; hour < 24; hour++)
                                Positioned(
                                  top: hour * _hourHeight,
                                  left: 0,
                                  right: 0,
                                  child: Divider(
                                    height: 1,
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                              for (var index = 0; index < days.length; index++)
                                Positioned(
                                  left: index * _dayColumnWidth,
                                  top: 0,
                                  width: _dayColumnWidth,
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
                              for (var index = 0; index < days.length; index++)
                                ..._timelineBlocks(
                                  days[index],
                                  _onDate(occurrences, days[index]),
                                  index,
                                  calendar,
                                  tasks,
                                ),
                              if (days.any(
                                (value) => _sameDate(value, DateTime.now()),
                              ))
                                _nowLine(days, DateTime.now(), scheme),
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
    );
  }

  Widget _daySummaryRow(
    List<DateTime> days,
    List<CalendarOccurrence> occurrences,
    CalendarProvider calendar,
    TaskProvider tasks,
  ) {
    return SizedBox(
      height: 76,
      child: Row(
        children: [
          const SizedBox(
            width: _timeColumnWidth,
            child: Center(child: Text('全天')),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _summaryController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: days.map((date) {
                  final values = _onDate(occurrences, date).where((value) {
                    return value.kind == CalendarOccurrenceKind.anniversary ||
                        value.isAllDay ||
                        _isTask(value);
                  }).toList();
                  return Container(
                    width: _dayColumnWidth,
                    height: 76,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        bottom: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: values.isEmpty
                        ? null
                        : ListView(
                            children: values.take(3).map((value) {
                              return InkWell(
                                onTap: () =>
                                    _editOccurrence(value, calendar, tasks),
                                child: Text(
                                  '${_occurrenceIconText(value)} ${value.title}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10),
                                ),
                              );
                            }).toList(),
                          ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _timelineBlocks(
    DateTime date,
    List<CalendarOccurrence> occurrences,
    int dayIndex,
    CalendarProvider calendar,
    TaskProvider tasks,
  ) {
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
      final laneWidth = (_dayColumnWidth - 6) / placement.laneCount;
      final top = placement.startMinute / 60 * _hourHeight;
      final height =
          ((placement.endMinute - placement.startMinute) / 60 * _hourHeight)
              .clamp(24.0, 24 * _hourHeight)
              .toDouble();
      final occurrence = placement.value;
      final task = _isTask(occurrence);
      final scheme = Theme.of(context).colorScheme;
      return Positioned(
        left: dayIndex * _dayColumnWidth + 3 + placement.lane * laneWidth,
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

  Widget _nowLine(List<DateTime> days, DateTime now, ColorScheme scheme) {
    final index = days.indexWhere((value) => _sameDate(value, now));
    return Positioned(
      left: index * _dayColumnWidth,
      top: (now.hour * 60 + now.minute) / 60 * _hourHeight,
      width: _dayColumnWidth,
      child: Container(height: 2, color: scheme.error),
    );
  }

  void _updateDayFocus() {
    if (_mode != _CalendarMode.day || !_horizontalController.hasClients) return;
    final center =
        _horizontalController.offset +
        _horizontalController.position.viewportDimension / 2;
    final index = (center / _dayColumnWidth).floor().clamp(0, _dayCount - 1);
    final start = _dayWindowStart;
    if (start == null) return;
    final next = start.add(Duration(days: index));
    if (!_sameDate(next, _focus)) setState(() => _focus = next);
  }

  void _centerFocusedDay({bool jump = false}) {
    if (!_horizontalController.hasClients) return;
    final start = _dayWindowStart;
    if (start == null) return;
    final index = _dateOnly(_focus).difference(start).inDays;
    if (index < 0 || index >= _dayCount) return;
    final target =
        index * _dayColumnWidth -
        (_horizontalController.position.viewportDimension - _dayColumnWidth) /
            2;
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
    final provider = context.read<TaskProvider>();
    final title = TextEditingController(text: task?.title ?? '');
    final note = TextEditingController(text: task?.note ?? '');
    final base = _selectedDate ?? _focus;
    DateTime? plannedDate =
        task?.plannedDate?.atStartOfDay() ?? _dateOnly(base);
    TimeOfDay? plannedTime = task?.plannedTime == null
        ? null
        : TimeOfDay(
            hour: task!.plannedTime!.hour,
            minute: task.plannedTime!.minute,
          );
    DateTime? dueDate = task?.dueDate?.atStartOfDay();
    TimeOfDay? dueTime = task?.dueTime == null
        ? null
        : TimeOfDay(hour: task!.dueTime!.hour, minute: task.dueTime!.minute);
    var completed = task?.isCompleted ?? false;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => _editorSheet(
          context,
          title: task == null ? '新建任务' : '编辑任务',
          titleController: title,
          noteController: note,
          onDelete: task == null
              ? null
              : () => Navigator.pop(context, 'delete'),
          onSave: () => Navigator.pop(context, 'save'),
          children: [
            if (task != null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('已完成'),
                value: completed,
                onChanged: (value) =>
                    setSheet(() => completed = value ?? false),
              ),
            _optionalDateTile(context, '计划日期', plannedDate, (value) {
              setSheet(() {
                plannedDate = value;
                if (value == null) plannedTime = null;
              });
            }),
            if (plannedDate != null)
              _optionalTimeTile(context, '计划时间', plannedTime, (value) {
                setSheet(() => plannedTime = value);
              }),
            _optionalDateTile(context, '截止日期', dueDate, (value) {
              setSheet(() {
                dueDate = value;
                if (value == null) dueTime = null;
              });
            }),
            if (dueDate != null)
              _optionalTimeTile(context, '截止时间', dueTime, (value) {
                setSheet(() => dueTime = value);
              }),
          ],
        ),
      ),
    );
    final titleText = title.text.trim();
    final noteText = note.text.trim();
    title.dispose();
    note.dispose();
    if (!mounted || action == null) return;
    if (action == 'delete' && task != null) {
      await provider.deleteTask(task.id);
      return;
    }
    if (titleText.isEmpty) return;
    final plannedLocalDate = plannedDate == null
        ? null
        : LocalDate.fromDateTime(plannedDate!);
    final dueLocalDate = dueDate == null
        ? null
        : LocalDate.fromDateTime(dueDate!);
    final plannedLocalTime = plannedTime == null
        ? null
        : LocalTime(plannedTime!.hour, plannedTime!.minute);
    final dueLocalTime = dueTime == null
        ? null
        : LocalTime(dueTime!.hour, dueTime!.minute);
    if (task == null) {
      await provider.addTask(
        title: titleText,
        note: noteText.isEmpty ? null : noteText,
        plannedDate: plannedLocalDate,
        plannedTime: plannedLocalTime,
        dueDate: dueLocalDate,
        dueTime: dueLocalTime,
      );
    } else {
      await provider.updateTask(
        task.copyWith(
          title: titleText,
          note: noteText.isEmpty ? null : noteText,
          plannedDate: plannedLocalDate,
          plannedTime: plannedLocalTime,
          dueDate: dueLocalDate,
          dueTime: dueLocalTime,
          completedAt: completed ? task.completedAt ?? DateTime.now() : null,
        ),
      );
    }
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
                autofocus: true,
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

  Widget _optionalDateTile(
    BuildContext context,
    String label,
    DateTime? value,
    ValueChanged<DateTime?> onChanged,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(
        value == null
            ? '未设置'
            : '${value.year}-${_two(value.month)}-${_two(value.day)}',
      ),
      trailing: value == null
          ? const Icon(Icons.add)
          : IconButton(
              tooltip: '清除',
              onPressed: () => onChanged(null),
              icon: const Icon(Icons.close),
            ),
      onTap: () async {
        final selected = await showDatePicker(
          context: context,
          firstDate: DateTime(1900),
          lastDate: DateTime(2200),
          initialDate: value ?? _dateOnly(DateTime.now()),
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

  Widget _optionalTimeTile(
    BuildContext context,
    String label,
    TimeOfDay? value,
    ValueChanged<TimeOfDay?> onChanged,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value?.format(context) ?? '未设置'),
      trailing: value == null
          ? const Icon(Icons.add_alarm_outlined)
          : IconButton(
              tooltip: '清除',
              onPressed: () => onChanged(null),
              icon: const Icon(Icons.close),
            ),
      onTap: () async {
        final selected = await showTimePicker(
          context: context,
          initialTime: value ?? TimeOfDay.now(),
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
