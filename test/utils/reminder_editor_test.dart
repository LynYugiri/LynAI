import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/item_reminder.dart';
import 'package:lynai/models/local_time.dart';
import 'package:lynai/utils/reminder_editor.dart';

void main() {
  test('unrelated edits preserve reminder IDs and custom date-only times', () {
    final reminders = reconcilePresetReminders(
      existing: [
        ItemReminder(
          id: 'imported',
          anchor: ItemReminderAnchor.eventStart,
          offsetMinutes: -30,
          dateOnlyTime: LocalTime(14, 45),
        ),
      ],
      selectedOffsets: {-30},
      anchor: ItemReminderAnchor.eventStart,
      dateOnly: true,
      createId: () => fail('no ID should be created'),
    );

    expect(reminders.single.id, 'imported');
    expect(reminders.single.dateOnlyTime, LocalTime(14, 45));
  });

  test(
    'deselects only removed reminders and creates IDs only for additions',
    () {
      var nextId = 0;
      final reminders = reconcilePresetReminders(
        existing: [
          ItemReminder(
            id: 'keep',
            anchor: ItemReminderAnchor.anniversaryDate,
            offsetMinutes: -10,
            dateOnlyTime: LocalTime(8, 0),
          ),
          ItemReminder(
            id: 'remove',
            anchor: ItemReminderAnchor.anniversaryDate,
            offsetMinutes: -30,
            dateOnlyTime: LocalTime(7, 0),
          ),
        ],
        selectedOffsets: {-10, -60},
        anchor: ItemReminderAnchor.anniversaryDate,
        dateOnly: true,
        createId: () => 'new-${nextId++}',
      );

      expect(reminders.map((value) => value.id), ['keep', 'new-0']);
      expect(reminders.first.dateOnlyTime, LocalTime(8, 0));
      expect(reminders.last.dateOnlyTime, LocalTime(9, 0));
      expect(nextId, 1);
    },
  );

  test(
    'switching to a timed event clears date-only time without changing ID',
    () {
      final reminders = reconcilePresetReminders(
        existing: [
          ItemReminder(
            id: 'same',
            anchor: ItemReminderAnchor.eventStart,
            offsetMinutes: 0,
            dateOnlyTime: LocalTime(13, 20),
          ),
        ],
        selectedOffsets: {0},
        anchor: ItemReminderAnchor.eventStart,
        dateOnly: false,
      );

      expect(reminders.single.id, 'same');
      expect(reminders.single.dateOnlyTime, isNull);
    },
  );
}
