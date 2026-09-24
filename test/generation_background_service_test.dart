import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/generation_background_service.dart';

/// 生成期后台存活的平台门控测试。
///
/// Android 走前台服务、鸿蒙走长时任务（`LynaiBackgroundService.ets`），
/// 其它平台必须是 no-op。鸿蒙分支依赖真实的 `Platform.operatingSystem == 'ohos'`
/// （不随 `debugDefaultTargetPlatformOverride` 改变），因此只能在鸿蒙设备上验证；
/// 这里固定的是「非 Android 平台不受影响」这一既有行为。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lynai/test_generation_background');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
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

  test('non-Android platforms are no-op', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await const GenerationBackgroundService(channel: channel).setActive(true);
    expect(calls, isEmpty);
  });

  test('Android invokes start and stop methods', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const service = GenerationBackgroundService(channel: channel);
    await service.setActive(true);
    await service.setActive(false);
    expect(calls.map((call) => call.method), [
      'startGeneration',
      'stopGeneration',
    ]);
  });
}
