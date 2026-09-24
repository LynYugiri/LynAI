import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/secret_store.dart';
import 'package:lynai/utils/platform_info.dart';

/// 鸿蒙关键资产存储桥接的契约测试。
///
/// 原生实现见 `ohos/entry/src/main/ets/lynai/LynaiSecureStorage.ets`：密钥写入
/// Asset Store Kit 时以别名索引、密文由 HUKS 保护。这里固定 Dart 侧的方法名、
/// 参数与返回值语义，并确认默认组合根在非鸿蒙平台上仍选中原有实现。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lynai/secure_storage');
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

  test('read 传 key 并返回原生明文', () async {
    mockHandler((call) async => 'sk-test-123');

    final value = await OhosAssetSecretStore().read('model_api_key');

    expect(value, 'sk-test-123');
    expect(calls.single.method, 'read');
    expect(calls.single.arguments, <String, Object?>{'key': 'model_api_key'});
  });

  test('read 在关键资产不存在时返回 null', () async {
    mockHandler((call) async => null);

    expect(await OhosAssetSecretStore().read('missing'), isNull);
  });

  test('write 传 key 与 value', () async {
    mockHandler((call) async => null);

    await OhosAssetSecretStore().write('model_api_key', 'sk-abc');

    expect(calls.single.method, 'write');
    expect(calls.single.arguments, <String, Object?>{
      'key': 'model_api_key',
      'value': 'sk-abc',
    });
  });

  test('delete 只传 key', () async {
    mockHandler((call) async => null);

    await OhosAssetSecretStore().delete('model_api_key');

    expect(calls.single.method, 'delete');
    expect(calls.single.arguments, <String, Object?>{'key': 'model_api_key'});
  });

  test('原生失败时向上抛出 PlatformException', () async {
    mockHandler(
      (call) async => throw PlatformException(
        code: 'secure_storage_write_failed',
        message: '关键资产长度上限 1024 字节',
      ),
    );

    await expectLater(
      OhosAssetSecretStore().write('k', 'v'),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.message,
          'message',
          contains('1024'),
        ),
      ),
    );
  });

  test('默认组合根在非鸿蒙平台仍使用 flutter_secure_storage', () {
    expect(isOhosPlatform, isFalse);
    expect(createDefaultSecretStore(), isA<FlutterSecureSecretStore>());
  });
}
