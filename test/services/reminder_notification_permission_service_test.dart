import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/calendar_platform_bridge.dart';
import 'package:lynai/services/reminder_notification_permission_service.dart';

void main() {
  test(
    'requests permission when an explicit save adds the first reminder',
    () async {
      final bridge = _RecordingCalendarPlatformBridge();

      await ReminderNotificationPermissionService.requestAfterExplicitSave(
        bridge: bridge,
        previousReminderCount: 0,
        savedReminderCount: 1,
      );

      expect(bridge.requestCount, 1);
    },
  );

  test('does not request when reminders remain absent', () async {
    final bridge = _RecordingCalendarPlatformBridge();

    await ReminderNotificationPermissionService.requestAfterExplicitSave(
      bridge: bridge,
      previousReminderCount: 0,
      savedReminderCount: 0,
    );

    expect(bridge.requestCount, 0);
  });

  test('does not request when the item already had reminders', () async {
    final bridge = _RecordingCalendarPlatformBridge();

    await ReminderNotificationPermissionService.requestAfterExplicitSave(
      bridge: bridge,
      previousReminderCount: 1,
      savedReminderCount: 2,
    );

    expect(bridge.requestCount, 0);
  });

  test('allows a missing bridge and swallows bridge failures', () async {
    await ReminderNotificationPermissionService.requestAfterExplicitSave(
      bridge: null,
      previousReminderCount: 0,
      savedReminderCount: 1,
    );

    final bridge = _RecordingCalendarPlatformBridge(shouldFail: true);
    await ReminderNotificationPermissionService.requestAfterExplicitSave(
      bridge: bridge,
      previousReminderCount: 0,
      savedReminderCount: 1,
    );

    expect(bridge.requestCount, 1);
  });
}

final class _RecordingCalendarPlatformBridge extends CalendarPlatformBridge {
  _RecordingCalendarPlatformBridge({this.shouldFail = false});

  final bool shouldFail;
  int requestCount = 0;

  @override
  Future<void> requestNotificationPermission() async {
    requestCount++;
    if (shouldFail) throw StateError('permission request failed');
  }
}
