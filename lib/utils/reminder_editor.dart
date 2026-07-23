import 'package:uuid/uuid.dart';

import '../models/item_reminder.dart';
import '../models/local_time.dart';

/// Reconciles preset selections without replacing existing reminder identities.
List<ItemReminder> reconcilePresetReminders({
  required Iterable<ItemReminder> existing,
  required Set<int> selectedOffsets,
  required ItemReminderAnchor anchor,
  required bool dateOnly,
  String Function()? createId,
}) {
  final reminders = <ItemReminder>[];
  final retainedOffsets = <int>{};
  for (final reminder in existing) {
    if (!selectedOffsets.contains(reminder.offsetMinutes)) continue;
    retainedOffsets.add(reminder.offsetMinutes);
    reminders.add(
      reminder.copyWith(
        anchor: anchor,
        dateOnlyTime: dateOnly
            ? reminder.dateOnlyTime ?? LocalTime(9, 0)
            : null,
      ),
    );
  }

  final idFactory = createId ?? const Uuid().v4;
  for (final offset in selectedOffsets) {
    if (retainedOffsets.contains(offset)) continue;
    reminders.add(
      ItemReminder(
        id: idFactory(),
        anchor: anchor,
        offsetMinutes: offset,
        dateOnlyTime: dateOnly ? LocalTime(9, 0) : null,
      ),
    );
  }
  return reminders;
}
