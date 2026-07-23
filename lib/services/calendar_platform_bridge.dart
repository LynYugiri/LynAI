import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/calendar_platform_projection.dart';

/// Android 日历平台桥；同步投影与通知权限请求严格分离。
class CalendarPlatformBridge {
  const CalendarPlatformBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('lynai/calendar_platform');

  final MethodChannel _channel;

  Future<void> syncProjection(CalendarPlatformProjection projection) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('syncProjection', {
      'projection': projection.toJson(),
    });
  }

  /// 只能由明确的用户操作调用；投影同步绝不隐式弹出通知权限。
  Future<void> requestNotificationPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('requestNotificationPermission');
  }
}
