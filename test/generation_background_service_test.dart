import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/generation_background_service.dart';

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
