import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/utils/ohos_speech.dart';
import 'package:lynai/utils/platform_info.dart';

/// 鸿蒙系统语音识别桥接的契约测试。
///
/// 原生实现见 `ohos/entry/src/main/ets/lynai/LynaiSpeech.ets`（Core Speech Kit）。
/// 通道是双向的：Dart 调 start/stop/cancel，原生通过同一通道回推
/// onPartial/onComplete/onError。这里固定两边的约定与失败语义，确保与其它平台的
/// `speech_to_text` 分支表现一致（只填输入框、不直接发送）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lynai/speech');
  const codec = StandardMethodCodec();
  late List<MethodCall> calls;

  void mockHandler(Future<Object?>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
  }

  /// 模拟原生侧回推事件。
  Future<void> emit(String method, Map<String, Object?> args) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );
  }

  setUp(() {
    calls = <MethodCall>[];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('start 传语言并回报成功', () async {
    mockHandler((call) async => <String, Object?>{'ok': true});
    final bridge = OhosSpeechBridge();

    final ok = await bridge.start(
      language: 'zh_CN',
      onText: (_) {},
      onError: (_) {},
      onDone: () {},
    );

    expect(ok, isTrue);
    expect(calls.single.method, 'start');
    expect(
      calls.single.arguments,
      <String, Object?>{'language': 'zh_CN'},
    );
    bridge.dispose();
  });

  test('start 失败返回 false（对应 initialize 失败路径）', () async {
    mockHandler(
      (call) async => <String, Object?>{'ok': false, 'error': '当前设备不支持系统语音识别'},
    );
    final bridge = OhosSpeechBridge();

    final ok = await bridge.start(
      language: 'zh_CN',
      onText: (_) {},
      onError: (_) {},
      onDone: () {},
    );

    expect(ok, isFalse);
    bridge.dispose();
  });

  test('onPartial 回填累计文本，onComplete 触发 done', () async {
    mockHandler((call) async => <String, Object?>{'ok': true});
    final bridge = OhosSpeechBridge();
    final texts = <String>[];
    var doneCount = 0;

    await bridge.start(
      language: 'zh_CN',
      onText: texts.add,
      onError: (_) {},
      onDone: () => doneCount++,
    );
    await emit('onPartial', <String, Object?>{'text': '你好'});
    await emit('onComplete', <String, Object?>{'text': '你好世界'});

    expect(texts, <String>['你好', '你好世界']);
    expect(doneCount, 1);
    expect(calls.map((call) => call.method), <String>['start']);
    bridge.dispose();
  });

  test('onError 回传文案并触发 done', () async {
    mockHandler((call) async => <String, Object?>{'ok': true});
    final bridge = OhosSpeechBridge();
    final errors = <String>[];
    var doneCount = 0;

    await bridge.start(
      language: 'zh_CN',
      onText: (_) {},
      onError: errors.add,
      onDone: () => doneCount++,
    );
    await emit('onError', <String, Object?>{'message': '识别失败（1002200002）'});

    expect(errors.single, contains('识别失败'));
    expect(doneCount, 1);
    bridge.dispose();
  });

  test('stop 与 cancel 使用各自的方法', () async {
    mockHandler((call) async => <String, Object?>{'ok': true});
    final bridge = OhosSpeechBridge();

    await bridge.stop();
    await bridge.cancel();

    expect(calls.map((call) => call.method), <String>['stop', 'cancel']);
    bridge.dispose();
  });

  test('dispose 之后不再回调到调用方', () async {
    mockHandler((call) async => <String, Object?>{'ok': true});
    final bridge = OhosSpeechBridge();
    final texts = <String>[];

    await bridge.start(
      language: 'zh_CN',
      onText: texts.add,
      onError: (_) {},
      onDone: () {},
    );
    bridge.dispose();
    await emit('onPartial', <String, Object?>{'text': '迟到的结果'});

    expect(texts, isEmpty);
  });

  test('能力开关：语音输入在支持的平台上一律开放', () {
    expect(OhosSpeechBridge.isSupported, isFalse, reason: '测试运行在桌面平台');
    expect(supportsVoiceInput, isTrue);
  });
}
