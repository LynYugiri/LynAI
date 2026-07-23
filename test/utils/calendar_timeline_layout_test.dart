import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/utils/calendar_timeline_layout.dart';

void main() {
  test('assigns overlapping intervals to separate lanes', () {
    final placements = layoutCalendarTimeline([
      const CalendarTimelineInterval(
        value: 'a',
        startMinute: 9 * 60,
        endMinute: 11 * 60,
      ),
      const CalendarTimelineInterval(
        value: 'b',
        startMinute: 10 * 60,
        endMinute: 12 * 60,
      ),
      const CalendarTimelineInterval(
        value: 'c',
        startMinute: 12 * 60,
        endMinute: 13 * 60,
      ),
    ]);

    expect(placements[0].lane, 0);
    expect(placements[1].lane, 1);
    expect(placements[0].laneCount, 2);
    expect(placements[1].laneCount, 2);
    expect(placements[2].lane, 0);
    expect(placements[2].laneCount, 1);
  });

  test('uses the peak lane count for a connected overlap group', () {
    final placements = layoutCalendarTimeline([
      const CalendarTimelineInterval(value: 'a', startMinute: 0, endMinute: 60),
      const CalendarTimelineInterval(
        value: 'b',
        startMinute: 30,
        endMinute: 90,
      ),
      const CalendarTimelineInterval(
        value: 'c',
        startMinute: 60,
        endMinute: 120,
      ),
    ]);

    expect(placements.map((value) => value.laneCount), everyElement(2));
    expect(placements.map((value) => value.lane), [0, 1, 0]);
  });
}
