import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/calendar_platform_projection.dart';
import 'package:lynai/services/calendar_platform_bridge.dart';

/// 日历平台桥的通道契约与平台门控测试。
///
/// 投影同步与通知权限请求在 Android / 鸿蒙上有实现（鸿蒙侧转成系统后台代理提醒），
/// 桌面与 Web 必须保持 no-op。注意 widget 测试里 `defaultTargetPlatform` 默认被
/// 当成 android（框架为 FLUTTER_TEST 做了兜底），因此桌面分支要用
/// `debugDefaultTargetPlatformOverride` 显式模拟。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lynai/calendar_platform');
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final projection = CalendarPlatformProjection(
    generatedAt: '2026-09-24T09:00',
    rangeStart: '2026-09-01',
    rangeEndExclusive: '2028-03-01',
    widgetOccurrences: const [],
    notificationTriggers: const [],
  );

  test('桌面平台上同步投影与请求权限都不触碰通道', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    const bridge = CalendarPlatformBridge();

    await bridge.syncProjection(projection);
    await bridge.requestNotificationPermission();

    expect(calls, isEmpty);
  });

  test('移动端上同步投影发送完整投影，权限请求单独发送', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const bridge = CalendarPlatformBridge();

    await bridge.syncProjection(projection);
    await bridge.requestNotificationPermission();

    expect(calls.map((call) => call.method), [
      'syncProjection',
      'requestNotificationPermission',
    ]);
    final args = calls.first.arguments as Map<Object?, Object?>;
    final payload = args['projection'] as Map<Object?, Object?>;
    expect(payload['version'], CalendarPlatformProjection.currentVersion);
    expect(payload['rangeStart'], '2026-09-01');
    expect(payload['notificationTriggers'], isEmpty);
    expect(calls.last.arguments, isNull);
  });
}
