import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/utils/ohos_file_picker.dart';

/// 鸿蒙文件选择桥接的契约测试。
///
/// 原生实现见 `ohos/entry/src/main/ets/lynai/LynaiFilePicker.ets`；这里用
/// mock channel 固定「Dart 侧如何解析原生返回值」，保证鸿蒙分支的失败/取消
/// 语义与非鸿蒙平台的 file_picker 一致。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lynai/file_picker');
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

  test('pickFiles 解析沙箱路径、文件名与大小', () async {
    mockHandler(
      (call) async => <String, Object?>{
        'ok': true,
        'files': <Object?>[
          <String, Object?>{
            'name': '报告.pdf',
            'path': '/data/cache/lynai_pick/1_报告.pdf',
            'size': 2048,
          },
        ],
      },
    );

    final files = await OhosFilePicker().pickFiles(
      type: 'any',
      allowedExtensions: const ['pdf'],
      allowMultiple: true,
    );

    expect(files, hasLength(1));
    expect(files.single.name, '报告.pdf');
    expect(files.single.path, '/data/cache/lynai_pick/1_报告.pdf');
    expect(files.single.size, 2048);

    expect(calls.single.method, 'pickFiles');
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['type'], 'any');
    expect(args['allowedExtensions'], <String>['pdf']);
    expect(args['allowMultiple'], isTrue);
  });

  test('pickFiles 在用户取消时返回空列表', () async {
    mockHandler(
      (call) async => <String, Object?>{'ok': true, 'files': <Object?>[]},
    );

    expect(await OhosFilePicker().pickFiles(), isEmpty);
  });

  test('pickFiles 忽略缺少路径的条目', () async {
    mockHandler(
      (call) async => <String, Object?>{
        'ok': true,
        'files': <Object?>[
          <String, Object?>{'name': '坏条目', 'size': 1},
        ],
      },
    );

    expect(await OhosFilePicker().pickFiles(), isEmpty);
  });

  test('pickFiles 把原生失败转成 PlatformException', () async {
    mockHandler(
      (call) async => <String, Object?>{'ok': false, 'error': '选择文件失败: 权限拒绝'},
    );

    await expectLater(
      OhosFilePicker().pickFiles(),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.message,
          'message',
          contains('权限拒绝'),
        ),
      ),
    );
  });

  test('saveFile 传字节并返回沙箱副本路径', () async {
    mockHandler(
      (call) async => <String, Object?>{
        'ok': true,
        'path': '/data/cache/lynai_pick/2_backup.zip',
      },
    );

    final path = await OhosFilePicker().saveFile(
      fileName: 'backup.zip',
      bytes: Uint8List.fromList(const [1, 2, 3]),
    );

    expect(path, '/data/cache/lynai_pick/2_backup.zip');
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['fileName'], 'backup.zip');
    expect(args['bytes'], isA<Uint8List>());
  });

  test('saveFile 用户取消时返回 null（与其它平台一致）', () async {
    mockHandler(
      (call) async => <String, Object?>{'ok': true, 'cancelled': true},
    );

    final path = await OhosFilePicker().saveFile(
      fileName: 'backup.zip',
      bytes: Uint8List.fromList(const [1, 2, 3]),
    );

    expect(path, isNull);
  });

  test('saveFile 失败时抛 PlatformException', () async {
    mockHandler(
      (call) async => <String, Object?>{
        'ok': false,
        'error': '写入文件失败: 空间不足',
      },
    );

    await expectLater(
      OhosFilePicker().saveFile(
        fileName: 'backup.zip',
        bytes: Uint8List.fromList(const [1]),
      ),
      throwsA(isA<PlatformException>()),
    );
  });

  test('非鸿蒙平台不启用该实现', () {
    expect(OhosFilePicker.isSupported, isFalse);
  });
}
