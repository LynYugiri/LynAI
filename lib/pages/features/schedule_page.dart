part of '../feature_page.dart';

enum _CalendarMode { month, day, year }

class _SchedulePage extends StatefulWidget {
  const _SchedulePage();

  @override
  State<_SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<_SchedulePage> {
  static const _baseHourRowHeight = 56.0;
  static const _dayInitialHour = 8;
  static const _dayBaseColumnWidth = 72.0;
  static const _timeColumnWidth = 56.0;
  static const _dayHeaderHeight = 46.0;
  static const _minDayZoom = 0.7;
  static const _maxDayZoom = 1.8;
  static const _dayWindowSize = 61;
  static const _dayWindowHalf = _dayWindowSize ~/ 2;
  static const _dayWindowSlideBatch = 14;
  static const _dayWindowEdgeColumns = 4;

  final _dayScrollController = ScrollController(
    initialScrollOffset: _dayInitialHour * _baseHourRowHeight,
  );
  final _dayHorizontalController = ScrollController(
    initialScrollOffset: _dayWindowHalf * _dayBaseColumnWidth,
  );
  final _dayHeaderHorizontalController = ScrollController(
    initialScrollOffset: _dayWindowHalf * _dayBaseColumnWidth,
  );
  bool _syncingDayHorizontalScroll = false;
  bool _slidingDayWindow = false;
  bool _dayWindowNeedsFocusCentering = false;
  DateTime? _dayWindowStart;
  double _dayZoom = 1.0;
  double _dayScaleStartZoom = 1.0;
  double? _dayScaleStartDistance;
  final Map<int, Offset> _dayPointerPositions = {};

  _CalendarMode _mode = _CalendarMode.month;
  DateTime _focus = DateTime.now();
  DateTime? _selectedDate;
  bool _showMonthDetail = false;
  double _scheduleControlsCollapse = 0;

  @override
  void initState() {
    super.initState();
    _dayHorizontalController.addListener(() {
      _syncDayHorizontalScroll(
        _dayHorizontalController,
        _dayHeaderHorizontalController,
      );
      _maybeSlideDayWindow();
    });
    _dayHeaderHorizontalController.addListener(() {
      _syncDayHorizontalScroll(
        _dayHeaderHorizontalController,
        _dayHorizontalController,
      );
    });
  }

  @override
  void dispose() {
    _dayScrollController.dispose();
    _dayHorizontalController.dispose();
    _dayHeaderHorizontalController.dispose();
    super.dispose();
  }

  void _syncDayHorizontalScroll(
    ScrollController source,
    ScrollController target,
  ) {
    if (_syncingDayHorizontalScroll ||
        !source.hasClients ||
        !target.hasClients) {
      return;
    }
    _syncingDayHorizontalScroll = true;
    final targetPosition = target.position;
    final offset = source.offset.clamp(
      targetPosition.minScrollExtent,
      targetPosition.maxScrollExtent,
    );
    target.jumpTo(offset.toDouble());
    _syncingDayHorizontalScroll = false;
  }

  void _ensureDayWindow() {
    if (_dayWindowStart != null) return;
    _dayWindowStart = _dateOnly(
      _focus,
    ).subtract(const Duration(days: _dayWindowHalf));
    _dayWindowNeedsFocusCentering = true;
  }

  void _maybeSlideDayWindow() {
    if (_slidingDayWindow ||
        _mode != _CalendarMode.day ||
        !_dayHorizontalController.hasClients ||
        _dayWindowStart == null) {
      return;
    }
    final position = _dayHorizontalController.position;
    final dayColumnWidth = _baseDayColumnWidthForCurrentZoom;
    final threshold = _dayWindowEdgeColumns * dayColumnWidth;
    if (position.pixels <= threshold) {
      _slideDayWindow(-_dayWindowSlideBatch, _dayWindowSlideBatch);
    } else if (position.pixels >= position.maxScrollExtent - threshold) {
      _slideDayWindow(_dayWindowSlideBatch, -_dayWindowSlideBatch);
    }
  }

  double get _baseDayColumnWidthForCurrentZoom =>
      _dayBaseColumnWidth * _dayZoom;

  void _slideDayWindow(int startDeltaDays, int offsetDeltaColumns) {
    final start = _dayWindowStart;
    if (start == null) return;
    final offset = _dayHorizontalController.offset;
    final offsetDelta = offsetDeltaColumns * _baseDayColumnWidthForCurrentZoom;
    _slidingDayWindow = true;
    setState(() {
      _dayWindowStart = start.add(Duration(days: startDeltaDays));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_dayHorizontalController.hasClients) {
        _slidingDayWindow = false;
        return;
      }
      _jumpDayHorizontalTo(offset + offsetDelta);
      _slidingDayWindow = false;
    });
  }

  void _jumpDayHorizontalTo(double value) {
    if (!_dayHorizontalController.hasClients) return;
    final position = _dayHorizontalController.position;
    final target = value
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _syncingDayHorizontalScroll = true;
    _dayHorizontalController.jumpTo(target);
    if (_dayHeaderHorizontalController.hasClients) {
      final headerPosition = _dayHeaderHorizontalController.position;
      _dayHeaderHorizontalController.jumpTo(
        target
            .clamp(
              headerPosition.minScrollExtent,
              headerPosition.maxScrollExtent,
            )
            .toDouble(),
      );
    }
    _syncingDayHorizontalScroll = false;
  }

  Future<void> _animateDayHorizontalTo(double value) async {
    if (!_dayHorizontalController.hasClients) return;
    final position = _dayHorizontalController.position;
    final target = value
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    await _dayHorizontalController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _animateDayBy(int deltaDays) {
    _ensureDayWindow();
    if (!_dayHorizontalController.hasClients) {
      setState(() => _focus = _dateOnly(_focus.add(Duration(days: deltaDays))));
      return;
    }
    _animateDayHorizontalTo(
      _dayHorizontalController.offset +
          deltaDays * _baseDayColumnWidthForCurrentZoom,
    );
  }

  void _updateFocusFromDayViewport() {
    if (_mode != _CalendarMode.day ||
        _dayWindowStart == null ||
        !_dayHorizontalController.hasClients) {
      return;
    }
    final position = _dayHorizontalController.position;
    final center = position.pixels + position.viewportDimension / 2;
    final index = (center / _baseDayColumnWidthForCurrentZoom)
        .floor()
        .clamp(0, _dayWindowSize - 1)
        .toInt();
    final next = _dayWindowStart!.add(Duration(days: index));
    if (!_sameDate(next, _focus)) {
      setState(() => _focus = _dateOnly(next));
    }
  }

  void _goToNow() {
    final now = DateTime.now();
    final today = _dateOnly(now);
    _ensureDayWindow();
    final start = _dayWindowStart!;
    final index = today.difference(start).inDays;
    if (index < 0 || index >= _dayWindowSize) {
      setState(() {
        _focus = today;
        _dayWindowStart = today.subtract(const Duration(days: _dayWindowHalf));
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollDayToNow(now);
      });
    } else {
      setState(() => _focus = today);
      _scrollDayToNow(now);
    }
  }

  void _scrollDayToNow(DateTime now) {
    _scrollDayHorizontallyTo(_dateOnly(now));
    _scrollDayVerticallyTo(now);
  }

  void _scrollDayHorizontallyTo(DateTime date) {
    final target = _dayHorizontalTargetFor(date);
    if (target == null) return;
    _animateDayHorizontalTo(target);
  }

  void _jumpDayHorizontallyTo(DateTime date) {
    final target = _dayHorizontalTargetFor(date);
    if (target == null) return;
    _jumpDayHorizontalTo(target);
  }

  double? _dayHorizontalTargetFor(DateTime date) {
    final start = _dayWindowStart;
    if (start == null || !_dayHorizontalController.hasClients) return null;
    final index = _dateOnly(date).difference(start).inDays;
    if (index < 0 || index >= _dayWindowSize) return null;
    final position = _dayHorizontalController.position;
    final dayColumnWidth = _baseDayColumnWidthForCurrentZoom;
    return index * dayColumnWidth -
        (position.viewportDimension - dayColumnWidth) / 2;
  }

  void _scrollDayVerticallyTo(DateTime dateTime) {
    if (!_dayScrollController.hasClients) return;
    final position = _dayScrollController.position;
    final hourRowHeight = _baseHourRowHeight * _dayZoom;
    final top =
        dateTime.hour * hourRowHeight + dateTime.minute / 60 * hourRowHeight;
    final target = top - position.viewportDimension / 2;
    _dayScrollController.animateTo(
      target
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
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
    if (notification.metrics.axis == Axis.horizontal) {
      if (notification is ScrollEndNotification) {
        _updateFocusFromDayViewport();
      }
      return false;
    }
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
    final fp = context.watch<FeatureProvider>();
    return Column(
      children: [
        _scheduleHeader(context),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScheduleScroll,
            child: switch (_mode) {
              _CalendarMode.day => _dayView(fp.schedules),
              _CalendarMode.year => _yearView(fp.schedules),
              _ => _monthView(fp.schedules),
            },
          ),
        ),
      ],
    );
  }

  Widget _scheduleHeader(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 560;
    final progress = _scheduleControlsCollapse;
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
              ignoring: progress > 0.6,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<_CalendarMode>(
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
                    onSelectionChanged: (v) => _setCalendarMode(v.first),
                  ),
                  const SizedBox(width: 8),
                  _AddMenuButton(
                    items: const [
                      _AddMenuItem('schedule', Icons.event, '新建日程'),
                      _AddMenuItem('task', Icons.flag_outlined, '新建任务'),
                    ],
                    onSelected: (value) => value == 'task'
                        ? _newScheduleItem(ScheduleItem.kindTask)
                        : _newScheduleItem(ScheduleItem.kindSchedule),
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
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: compact
          ? Column(
              children: [
                _dateNavigator(context),
                SizedBox(height: 10 * (1 - progress)),
                Align(alignment: Alignment.centerRight, child: controls),
              ],
            )
          : Row(
              children: [
                Expanded(child: _dateNavigator(context)),
                controls,
              ],
            ),
    );
  }

  Widget _dateNavigator(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _move(-1),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _focusLabel(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _modeLabel(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton.filledTonal(
          icon: const Icon(Icons.chevron_right),
          onPressed: () => _move(1),
        ),
      ],
    );
  }

  void _setCalendarMode(_CalendarMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      if (mode == _CalendarMode.day) {
        _dayWindowStart = null;
      }
    });
  }

  void _move(int delta) {
    if (_mode == _CalendarMode.day) {
      _animateDayBy(delta);
      return;
    }
    setState(() {
      _focus = switch (_mode) {
        _CalendarMode.year => DateTime(_focus.year + delta, 1, 1),
        _ => DateTime(_focus.year, _focus.month + delta, 1),
      };
      if (_mode == _CalendarMode.month) {
        final daysInMonth = DateTime(_focus.year, _focus.month + 1, 0).day;
        final selectedDay = _selectedDate?.day ?? _focus.day;
        final clampedDay = selectedDay.clamp(1, daysInMonth);
        _selectedDate = _showMonthDetail
            ? DateTime(_focus.year, _focus.month, clampedDay)
            : null;
      } else if (_mode == _CalendarMode.year) {
        _selectedDate = null;
        _showMonthDetail = false;
      }
    });
  }

  String _focusLabel() {
    return switch (_mode) {
      _CalendarMode.day => '${_focus.year}-${_focus.month}-${_focus.day}',
      _CalendarMode.year => '${_focus.year}',
      _ => '${_focus.year}-${_focus.month}',
    };
  }

  String _modeLabel() {
    return switch (_mode) {
      _CalendarMode.day => '周日程时间轴',
      _CalendarMode.year => '全年总览',
      _ => '月历总览',
    };
  }

  Widget _monthView(List<ScheduleItem> items) {
    final first = DateTime(_focus.year, _focus.month, 1);
    final days = DateTime(_focus.year, _focus.month + 1, 0).day;
    final offset = first.weekday - 1;
    final total = ((offset + days + 6) ~/ 7) * 7;
    final selectedDate = _selectedDate;
    final selectedItems = selectedDate == null
        ? <ScheduleItem>[]
        : _itemsOnDate(items, selectedDate);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              Text(
                '${_focus.year} 年 ${_focus.month} 月',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() {
                  final now = DateTime.now();
                  _focus = DateTime(now.year, now.month, 1);
                  _selectedDate = _dateOnly(now);
                  _showMonthDetail = true;
                }),
                icon: const Icon(Icons.today, size: 18),
                label: const Text('今天'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(
            children: const ['一', '二', '三', '四', '五', '六', '日']
                .map(
                  (e) => Expanded(
                    child: Center(
                      child: Text(
                        e,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        SizedBox(
          height: _showMonthDetail ? 244 : 0,
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
            ),
            itemCount: total,
            itemBuilder: (context, index) {
              if (index < offset || index >= offset + days) {
                return const SizedBox.shrink();
              }
              final day = index - offset + 1;
              final date = DateTime(_focus.year, _focus.month, day);
              final dayItems = _itemsOnDate(items, date);
              final today = _sameDate(date, DateTime.now());
              final selected =
                  selectedDate != null && _sameDate(date, selectedDate);
              return _monthDayCell(context, date, dayItems, today, selected);
            },
          ),
        ),
        if (!_showMonthDetail)
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
              ),
              itemCount: total,
              itemBuilder: (context, index) {
                if (index < offset || index >= offset + days) {
                  return const SizedBox.shrink();
                }
                final day = index - offset + 1;
                final date = DateTime(_focus.year, _focus.month, day);
                final dayItems = _itemsOnDate(items, date);
                final today = _sameDate(date, DateTime.now());
                final selected =
                    selectedDate != null && _sameDate(date, selectedDate);
                return _monthDayCell(context, date, dayItems, today, selected);
              },
            ),
          ),
        if (_showMonthDetail && selectedDate != null) ...[
          const SizedBox(height: 4),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${selectedDate.day}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${selectedDate.year}-${selectedDate.month}-${selectedDate.day}',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_weekdayName(selectedDate.weekday)} | ${selectedItems.length} 条事项',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭日程摘要',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _selectedDate = null;
                          _showMonthDetail = false;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (selectedItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '这一天没有事项',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    ...selectedItems.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () => _openScheduleEditor(item),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.16),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _timeLabelForDate(item, selectedDate),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                                if ((item.note ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    item.note!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _monthDayCell(
    BuildContext context,
    DateTime date,
    List<ScheduleItem> dayItems,
    bool today,
    bool selected,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.9)
          : today
          ? scheme.primaryContainer.withValues(alpha: 0.55)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.9)
                : today
                ? scheme.primary.withValues(alpha: 0.55)
                : scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: InkWell(
          onTap: () => setState(() {
            _selectedDate = _dateOnly(date);
            _showMonthDetail = true;
          }),
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primary
                            : today
                            ? scheme.primary.withValues(alpha: 0.85)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: selected || today ? scheme.onPrimary : null,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (dayItems.isNotEmpty)
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
              if (dayItems.isNotEmpty)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Text(
                    '${dayItems.length}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayView(List<ScheduleItem> items) {
    _ensureDayWindow();
    if (_dayWindowNeedsFocusCentering) {
      _dayWindowNeedsFocusCentering = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _jumpDayHorizontallyTo(_focus);
      });
    }
    final windowStart = _dayWindowStart!;
    final days = List.generate(
      _dayWindowSize,
      (i) => windowStart.add(Duration(days: i)),
    );
    final scheme = Theme.of(context).colorScheme;
    final hourRowHeight = _baseHourRowHeight * _dayZoom;
    final dayColumnWidth = _dayBaseColumnWidth * _dayZoom;
    final timelineHeight = 24 * hourRowHeight;
    final timelineWidth = days.length * dayColumnWidth;
    final now = DateTime.now();
    final showNow = days.any((date) => _sameDate(date, now));

    return Listener(
      onPointerSignal: _handleDayPointerSignal,
      onPointerDown: _handleDayPointerDown,
      onPointerMove: _handleDayPointerMove,
      onPointerUp: _handleDayPointerEnd,
      onPointerCancel: _handleDayPointerEnd,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Column(
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
                            controller: _dayHeaderHorizontalController,
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: days
                                  .map(
                                    (date) => _dayHeaderCell(
                                      date,
                                      scheme,
                                      width: dayColumnWidth,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _dayScrollController,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: _timeColumnWidth,
                            height: timelineHeight,
                            child: Stack(
                              children: [
                                for (var h = 0; h < 24; h++)
                                  Positioned(
                                    top: h * hourRowHeight,
                                    left: 0,
                                    right: 0,
                                    child: SizedBox(
                                      height: hourRowHeight,
                                      child: Align(
                                        alignment: Alignment.topCenter,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Text(
                                            '${h.toString().padLeft(2, '0')}:00',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (showNow)
                                  _nowTimeLabel(
                                    now,
                                    scheme,
                                    hourRowHeight: hourRowHeight,
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              controller: _dayHorizontalController,
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: timelineWidth,
                                height: timelineHeight,
                                child: Stack(
                                  children: [
                                    for (var h = 0; h < 24; h++)
                                      Positioned(
                                        top: h * hourRowHeight,
                                        left: 0,
                                        right: 0,
                                        child: Divider(
                                          height: 1,
                                          color: scheme.outlineVariant
                                              .withValues(alpha: 0.45),
                                        ),
                                      ),
                                    for (var i = 0; i < days.length; i++)
                                      Positioned(
                                        left: i * dayColumnWidth,
                                        top: 0,
                                        width: dayColumnWidth,
                                        height: timelineHeight,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            border: Border(
                                              left: BorderSide(
                                                color: scheme.outlineVariant
                                                    .withValues(alpha: 0.35),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    for (var i = 0; i < days.length; i++)
                                      ..._itemsOnDate(items, days[i]).map(
                                        (item) => _dayScheduleBlock(
                                          item,
                                          days[i],
                                          scheme,
                                          hourRowHeight: hourRowHeight,
                                          left: i * dayColumnWidth + 2,
                                          width: dayColumnWidth - 4,
                                        ),
                                      ),
                                    for (var i = 0; i < days.length; i++)
                                      if (_sameDate(days[i], now))
                                        _nowLine(
                                          now,
                                          scheme,
                                          left: i * dayColumnWidth,
                                          width: dayColumnWidth,
                                          hourRowHeight: hourRowHeight,
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
              Positioned(
                right: 12,
                bottom: 12,
                child: _backToNowButton(scheme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _backToNowButton(ColorScheme scheme) {
    return Material(
      color: scheme.primaryContainer,
      elevation: 3,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: _goToNow,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.my_location,
                size: 18,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                '现在',
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayHeaderCell(
    DateTime date,
    ColorScheme scheme, {
    required double width,
  }) {
    final today = _sameDate(date, DateTime.now());
    final focused = _sameDate(date, _focus);
    return InkWell(
      onTap: () => setState(() => _focus = _dateOnly(date)),
      child: Container(
        width: width,
        height: _dayHeaderHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: focused ? scheme.primary.withValues(alpha: 0.08) : null,
          border: Border(
            left: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _weekdayName(date.weekday),
              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
            ),
            Text(
              '${date.month}/${date.day}',
              style: TextStyle(
                fontWeight: today ? FontWeight.w800 : FontWeight.w600,
                color: today ? scheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nowTimeLabel(
    DateTime now,
    ColorScheme scheme, {
    required double hourRowHeight,
  }) {
    final top = now.hour * hourRowHeight + now.minute / 60 * hourRowHeight;
    return Positioned(
      top: (top - 8).clamp(0, 24 * hourRowHeight - 16).toDouble(),
      left: 0,
      right: 4,
      height: 16,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '现在',
              style: TextStyle(
                fontSize: 9.5,
                height: 1.1,
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _nowLine(
    DateTime now,
    ColorScheme scheme, {
    required double left,
    required double width,
    required double hourRowHeight,
  }) {
    final top = now.hour * hourRowHeight + now.minute / 60 * hourRowHeight;
    return Positioned(
      top: top,
      left: left,
      width: width,
      child: IgnorePointer(
        child: Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: scheme.error,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Container(
                height: 1.6,
                color: scheme.error.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayScheduleBlock(
    ScheduleItem item,
    DateTime date,
    ColorScheme scheme, {
    required double hourRowHeight,
    double? left,
    double? width,
  }) {
    final visibleStart = _visibleStartForDate(item, date);
    final visibleEnd = _visibleEndForDate(item, date);
    final top =
        visibleStart.hour * hourRowHeight +
        visibleStart.minute / 60 * hourRowHeight;
    final height =
        (visibleEnd.difference(visibleStart).inMinutes / 60 * hourRowHeight)
            .clamp(26, 24 * hourRowHeight)
            .toDouble();
    final maxLines = ((height - 8) / 13.5).floor().clamp(1, 20);

    return Positioned(
      top: top,
      left: left ?? 2,
      right: width == null ? 2 : null,
      width: width,
      height: height,
      child: InkWell(
        onTap: () => _openScheduleEditor(item),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
          ),
          child: Text(
            '${_timeLabelForDate(item, date)}  ${item.title}',
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, height: 1.25),
          ),
        ),
      ),
    );
  }

  Widget _yearView(List<ScheduleItem> items) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: 12,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final month = i + 1;
        final monthStart = DateTime(_focus.year, month, 1);
        final monthEnd = DateTime(_focus.year, month + 1, 1);
        final monthItems = items
            .where((e) => _itemOverlapsRange(e, monthStart, monthEnd))
            .toList();
        final count = monthItems.length;
        return Material(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() {
              _focus = DateTime(_focus.year, month, 1);
              _selectedDate = null;
              _mode = _CalendarMode.month;
            }),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            '$month',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$month 月',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              count == 0 ? '这个月没有事项' : '共 $count 条事项',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  if (monthItems.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final chipWidth = (constraints.maxWidth - 6) / 2;
                        return Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: monthItems.take(6).map((item) {
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _focus = DateTime(
                                    _focus.year,
                                    month,
                                    _visibleStartForDate(item, monthStart).day,
                                  );
                                  _selectedDate = DateTime(
                                    _focus.year,
                                    month,
                                    _visibleStartForDate(item, monthStart).day,
                                  );
                                  _mode = _CalendarMode.month;
                                });
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: SizedBox(
                                width: chipWidth.clamp(128.0, 260.0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Text(
                                    '${_visibleStartForDate(item, monthStart).month}/${_visibleStartForDate(item, monthStart).day} ${item.title}',
                                    style: const TextStyle(fontSize: 11),
                                    maxLines: 2,
                                    softWrap: true,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<ScheduleItem> _itemsOnDate(List<ScheduleItem> items, DateTime date) {
    final dayStart = _dateOnly(date);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return items.where((e) => _itemOverlapsRange(e, dayStart, dayEnd)).toList();
  }

  bool _itemOverlapsRange(ScheduleItem item, DateTime from, DateTime to) {
    if (item.isTask) {
      return !item.start.isBefore(from) && item.start.isBefore(to);
    }
    return item.start.isBefore(to) && item.end.isAfter(from);
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _weekdayName(int weekday) =>
      const ['一', '二', '三', '四', '五', '六', '日'][weekday - 1];

  String _time(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  String _timeRangeForDate(ScheduleItem item, DateTime date) {
    final visibleStart = _visibleStartForDate(item, date);
    final visibleEnd = _visibleEndForDate(item, date);
    return '${_time(visibleStart)} - ${_time(visibleEnd)}';
  }

  String _timeLabelForDate(ScheduleItem item, DateTime date) {
    if (item.isTask) return '任务 ${_time(item.start)}';
    return _timeRangeForDate(item, date);
  }

  DateTime _visibleStartForDate(ScheduleItem item, DateTime date) {
    final dayStart = _dateOnly(date);
    return item.start.isAfter(dayStart) ? item.start : dayStart;
  }

  DateTime _visibleEndForDate(ScheduleItem item, DateTime date) {
    final dayEnd = _dateOnly(date).add(const Duration(days: 1));
    return item.end.isBefore(dayEnd) ? item.end : dayEnd;
  }

  Future<void> _newScheduleItem(String kind) async {
    final isTask = kind == ScheduleItem.kindTask;
    final titleCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final baseDate = _mode == _CalendarMode.month
        ? _selectedDate ?? _dateOnly(_focus)
        : _focus;
    var start = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      DateTime.now().hour,
    );
    var end = start.add(const Duration(hours: 1));
    DateTime selectedDate = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
    );
    TimeOfDay startTime = TimeOfDay.fromDateTime(start);
    TimeOfDay endTime = TimeOfDay.fromDateTime(end);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          return AlertDialog(
            title: Text(isTask ? '新建任务' : '新建日程'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => Navigator.pop(ctx, true),
                    decoration: const InputDecoration(
                      labelText: '标题',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '备注（可选）',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('日期'),
                    subtitle: Text(
                      '${selectedDate.year}-${selectedDate.month}-${selectedDate.day}',
                    ),
                    trailing: const Icon(Icons.date_range),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: selectedDate,
                      );
                      if (date != null) {
                        setDialog(() {
                          selectedDate = date;
                          start = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            startTime.hour,
                            startTime.minute,
                          );
                          end = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            endTime.hour,
                            endTime.minute,
                          );
                        });
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('开始时间'),
                    subtitle: Text(_time(start)),
                    trailing: const Icon(Icons.schedule),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: ctx,
                        initialTime: startTime,
                      );
                      if (time != null) {
                        setDialog(() {
                          startTime = time;
                          start = DateTime(
                            selectedDate.year,
                            selectedDate.month,
                            selectedDate.day,
                            time.hour,
                            time.minute,
                          );
                          if (!end.isAfter(start)) {
                            end = start.add(const Duration(hours: 1));
                            endTime = TimeOfDay.fromDateTime(end);
                          }
                        });
                      }
                    },
                  ),
                  if (!isTask) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('结束时间'),
                      subtitle: Text(_time(end)),
                      trailing: const Icon(Icons.schedule_outlined),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: ctx,
                          initialTime: endTime,
                        );
                        if (time != null) {
                          setDialog(() {
                            endTime = time;
                            end = DateTime(
                              selectedDate.year,
                              selectedDate.month,
                              selectedDate.day,
                              time.hour,
                              time.minute,
                            );
                            if (!end.isAfter(start)) {
                              end = start.add(const Duration(hours: 1));
                              endTime = TimeOfDay.fromDateTime(end);
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '时长：${(end.difference(start).inMinutes / 60).toStringAsFixed(1)} 小时',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    final title = titleCtrl.text.trim();
    final note = noteCtrl.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      titleCtrl.dispose();
      noteCtrl.dispose();
    });
    if (!mounted || result != true || title.isEmpty) return;
    await context.read<FeatureProvider>().addSchedule(
      title,
      start,
      end,
      note: note.isEmpty ? null : note,
      kind: kind,
    );
  }

  Future<void> _openScheduleEditor(ScheduleItem schedule) async {
    final fp = context.read<FeatureProvider>();
    final titleCtrl = TextEditingController(text: schedule.title);
    final noteCtrl = TextEditingController(text: schedule.note ?? '');
    final isTask = schedule.isTask;
    var start = schedule.start;
    var end = schedule.end;
    DateTime selectedDate = DateTime(
      schedule.start.year,
      schedule.start.month,
      schedule.start.day,
    );
    TimeOfDay startTime = TimeOfDay.fromDateTime(start);
    TimeOfDay endTime = TimeOfDay.fromDateTime(end);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => Navigator.pop(ctx, 'save'),
                    decoration: const InputDecoration(
                      labelText: '标题',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '备注（可选）',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('日期'),
                    subtitle: Text(
                      '${selectedDate.year}-${selectedDate.month}-${selectedDate.day}',
                    ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: selectedDate,
                      );
                      if (date != null) {
                        setDialog(() {
                          selectedDate = date;
                          start = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            startTime.hour,
                            startTime.minute,
                          );
                          end = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            endTime.hour,
                            endTime.minute,
                          );
                        });
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('开始时间'),
                    subtitle: Text(_time(start)),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: ctx,
                        initialTime: startTime,
                      );
                      if (time != null) {
                        setDialog(() {
                          startTime = time;
                          start = DateTime(
                            selectedDate.year,
                            selectedDate.month,
                            selectedDate.day,
                            time.hour,
                            time.minute,
                          );
                          if (!end.isAfter(start)) {
                            end = start.add(const Duration(hours: 1));
                            endTime = TimeOfDay.fromDateTime(end);
                          }
                        });
                      }
                    },
                  ),
                  if (!isTask)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('结束时间'),
                      subtitle: Text(_time(end)),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: ctx,
                          initialTime: endTime,
                        );
                        if (time != null) {
                          setDialog(() {
                            endTime = time;
                            end = DateTime(
                              selectedDate.year,
                              selectedDate.month,
                              selectedDate.day,
                              time.hour,
                              time.minute,
                            );
                            if (!end.isAfter(start)) {
                              end = start.add(const Duration(hours: 1));
                              endTime = TimeOfDay.fromDateTime(end);
                            }
                          });
                        }
                      },
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(ctx, 'save'),
                        icon: const Icon(Icons.save),
                        label: const Text('保存'),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: () => Navigator.pop(ctx, 'delete'),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('删除'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (!mounted || action == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        titleCtrl.dispose();
        noteCtrl.dispose();
      });
      return;
    }
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(isTask ? '删除任务' : '删除日程'),
          content: Text('确定删除 "${schedule.title}" 吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await fp.deleteSchedule(schedule.id);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        titleCtrl.dispose();
        noteCtrl.dispose();
      });
      return;
    }
    final title = titleCtrl.text.trim();
    final note = noteCtrl.text.trim();
    await fp.updateSchedule(
      schedule.copyWith(
        title: title.isEmpty ? schedule.title : title,
        start: start,
        end: isTask ? start.add(const Duration(minutes: 1)) : end,
        note: note.isEmpty ? null : note,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      titleCtrl.dispose();
      noteCtrl.dispose();
    });
  }
}
