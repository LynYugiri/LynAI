final class CalendarTimelineInterval<T> {
  const CalendarTimelineInterval({
    required this.value,
    required this.startMinute,
    required this.endMinute,
  });

  final T value;
  final int startMinute;
  final int endMinute;
}

final class CalendarTimelinePlacement<T> {
  const CalendarTimelinePlacement({
    required this.value,
    required this.startMinute,
    required this.endMinute,
    required this.lane,
    required this.laneCount,
  });

  final T value;
  final int startMinute;
  final int endMinute;
  final int lane;
  final int laneCount;
}

List<CalendarTimelinePlacement<T>> layoutCalendarTimeline<T>(
  Iterable<CalendarTimelineInterval<T>> intervals,
) {
  final sorted = intervals.toList()
    ..sort((a, b) {
      final startOrder = a.startMinute.compareTo(b.startMinute);
      if (startOrder != 0) return startOrder;
      return b.endMinute.compareTo(a.endMinute);
    });
  final result = <CalendarTimelinePlacement<T>>[];
  var groupStart = 0;
  while (groupStart < sorted.length) {
    var groupEnd = groupStart + 1;
    var latestEnd = sorted[groupStart].endMinute;
    while (groupEnd < sorted.length &&
        sorted[groupEnd].startMinute < latestEnd) {
      latestEnd = latestEnd < sorted[groupEnd].endMinute
          ? sorted[groupEnd].endMinute
          : latestEnd;
      groupEnd++;
    }

    final laneEnds = <int>[];
    final assigned = <(CalendarTimelineInterval<T>, int)>[];
    for (final interval in sorted.sublist(groupStart, groupEnd)) {
      var lane = laneEnds.indexWhere((end) => end <= interval.startMinute);
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(interval.endMinute);
      } else {
        laneEnds[lane] = interval.endMinute;
      }
      assigned.add((interval, lane));
    }
    // 同一重叠连通组共享 lane 总数，避免块在横向互相覆盖。
    for (final (interval, lane) in assigned) {
      result.add(
        CalendarTimelinePlacement(
          value: interval.value,
          startMinute: interval.startMinute,
          endMinute: interval.endMinute,
          lane: lane,
          laneCount: laneEnds.length,
        ),
      );
    }
    groupStart = groupEnd;
  }
  return result;
}
