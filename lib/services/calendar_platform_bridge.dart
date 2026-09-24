import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/calendar_platform_projection.dart';
import '../utils/platform_info.dart';

/// 日历平台桥；同步投影与通知权限请求严格分离。
///
/// Android 侧由 `CalendarProjectionStore` + `ScheduleNotificationReceiver`
/// 落库并重排通知；鸿蒙侧由 `LynaiCalendarPlatform.ets` 转成系统后台代理提醒
/// （reminderAgentManager），因为普通应用无法自行安排定时通知。
class CalendarPlatformBridge {
  const CalendarPlatformBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('lynai/calendar_platform');

  final MethodChannel _channel;

  /// 只有具备平台实现的移动端才同步投影；桌面与 Web 保持 no-op。
  bool get _isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || isOhosPlatform);

  Future<void> syncProjection(CalendarPlatformProjection projection) async {
    if (!_isSupported) return;
    await _channel.invokeMethod<void>('syncProjection', {
      'projection': projection.toJson(),
    });
  }

  /// 只能由明确的用户操作调用；投影同步绝不隐式弹出通知权限。
  Future<void> requestNotificationPermission() async {
    if (!_isSupported) return;
    await _channel.invokeMethod<void>('requestNotificationPermission');
  }
}
