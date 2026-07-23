import 'calendar_platform_bridge.dart';

/// Requests notification permission after an explicit reminder-bearing save.
final class ReminderNotificationPermissionService {
  const ReminderNotificationPermissionService._();

  static Future<void> requestAfterExplicitSave({
    required CalendarPlatformBridge? bridge,
    required int previousReminderCount,
    required int savedReminderCount,
  }) async {
    if (bridge == null ||
        previousReminderCount != 0 ||
        savedReminderCount == 0) {
      return;
    }

    // 仅用户明确确认保存且从无提醒变为有提醒时请求；加载、同步和无关编辑不得调用。
    try {
      await bridge.requestNotificationPermission();
    } catch (_) {
      // Permission prompts are best-effort and must not affect persisted data.
    }
  }
}
