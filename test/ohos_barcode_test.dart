import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/utils/ohos_barcode.dart';
import 'package:lynai/utils/platform_info.dart';

/// 鸿蒙系统扫码桥接的契约测试。
///
/// 原生实现见 `ohos/entry/src/main/ets/lynai/LynaiBarcode.ets`：调起系统统一扫码
/// 界面（Scan Kit）。返回值语义要与应用内扫码页保持一致：取消返回 null，
/// 失败抛异常，让调用方回退到「导入配对码图片」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lynai/barcode');
  late List<MethodCall> calls;

  void mockHandler(Future<Object?>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(() {
    calls = <MethodCall>[];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('scan 返回二维码原文', () async {
    mockHandler(
      (call) async => <String, Object?>{'ok': true, 'value': 'lynai://pair?d=abc'},
    );

    expect(await OhosBarcodeBridge().scan(), 'lynai://pair?d=abc');
    expect(calls.single.method, 'scan');
    expect(calls.single.arguments, isNull);
  });

  test('用户取消返回 null', () async {
    mockHandler(
      (call) async => <String, Object?>{'ok': false, 'cancelled': true},
    );

    expect(await OhosBarcodeBridge().scan(), isNull);
  });

  test('识别不到内容按失败抛出，交给调用方回退', () async {
    mockHandler(
      (call) async => <String, Object?>{'ok': false, 'error': '未识别到二维码内容'},
    );

    await expectLater(OhosBarcodeBridge().scan(), throwsA(isA<PlatformException>()));
  });

  test('失败时抛 PlatformException 以便调用方回退', () async {
    mockHandler(
      (call) async => <String, Object?>{
        'ok': false,
        'error': 'startScanForResult: must be called in page context',
      },
    );

    await expectLater(
      OhosBarcodeBridge().scan(),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.message,
          'message',
          contains('page context'),
        ),
      ),
    );
  });

  test('没有返回值时视为失败', () async {
    mockHandler((call) async => null);

    await expectLater(OhosBarcodeBridge().scan(), throwsA(isA<PlatformException>()));
  });

  test('扫码能力：应用内扫码页或系统扫码 UI 任一可用即可直接扫码', () {
    expect(OhosBarcodeBridge.isSupported, isFalse, reason: '测试运行在桌面平台');
    expect(supportsSystemQrScan, isFalse);
    expect(canScanPairingCode, supportsQrScanner);
  });
}
