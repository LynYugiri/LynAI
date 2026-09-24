import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/utils/ohos_clipboard.dart';
import 'package:lynai/utils/platform_info.dart';

/// 鸿蒙剪贴板写入桥接的契约测试。
///
/// 鸿蒙侧写入剪贴板不需要权限（原生实现见
/// `ohos/entry/src/main/ets/lynai/LynaiClipboard.ets`，写入 MIMETYPE_PIXELMAP
/// 记录）；读取需要 `ohos.permission.READ_PASTEBOARD`，不向普通应用开放，
/// 因此这里同时固定「只写不读」的能力边界。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lynai/clipboard');
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

  test('copyImage 传字节与 mime 类型', () async {
    mockHandler((call) async => <String, Object?>{'ok': true});

    await OhosClipboardBridge().copyImage(
      Uint8List.fromList(const [137, 80, 78, 71]),
      mimeType: 'image/png',
    );

    expect(calls.single.method, 'copyImage');
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['mimeType'], 'image/png');
    expect(args['bytes'], isA<Uint8List>());
  });

  test('原生失败时抛出 PlatformException 并带出错误文案', () async {
    mockHandler(
      (call) async => <String, Object?>{'ok': false, 'error': '复制图片失败: 解码失败'},
    );

    await expectLater(
      OhosClipboardBridge().copyImage(Uint8List.fromList(const [1, 2, 3])),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.message,
          'message',
          contains('解码失败'),
        ),
      ),
    );
  });

  test('没有返回值时视为失败', () async {
    mockHandler((call) async => null);

    await expectLater(
      OhosClipboardBridge().copyImage(Uint8List.fromList(const [1])),
      throwsA(isA<PlatformException>()),
    );
  });

  test('能力边界：可写图片剪贴板，但不支持读取（粘贴）', () {
    expect(OhosClipboardBridge.isSupported, isFalse, reason: '测试运行在桌面平台');
    // 所有平台都能把图片写入剪贴板。
    expect(supportsImageClipboardWrite, isTrue);
    // 非鸿蒙平台仍走 super_clipboard 的完整读写能力。
    expect(supportsRichClipboard, isTrue);
  });
}
