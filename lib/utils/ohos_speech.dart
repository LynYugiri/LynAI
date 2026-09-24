import 'package:flutter/services.dart';

import 'platform_info.dart';

/// 鸿蒙上的系统语音识别桥接（Core Speech Kit）。
///
/// Android/iOS 走 `speech_to_text`（部分结果实时回调），鸿蒙侧改用系统基础语音
/// 服务的离线识别：`recognitionMode: 0` 由系统负责录音，应用只处理结果回调。
/// 原生实现见 `ohos/entry/src/main/ets/lynai/LynaiSpeech.ets`。
///
/// 通道是双向的：Dart 侧调用 [start] / [stop] / [cancel]，原生侧通过同一通道
/// 回推 `onPartial`（当前累计文本）、`onComplete`（最终文本）与 `onError`。
class OhosSpeechBridge {
  OhosSpeechBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('lynai/speech') {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final MethodChannel _channel;

  /// 当前平台是否需要走鸿蒙实现。
  static bool get isSupported => isOhosPlatform;

  void Function(String text)? _onText;
  void Function(String message)? _onError;
  void Function()? _onDone;

  Future<Object?> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onPartial':
        _onText?.call(_stringArg(call, 'text'));
        break;
      case 'onComplete':
        _onText?.call(_stringArg(call, 'text'));
        _onDone?.call();
        break;
      case 'onError':
        _onError?.call(_stringArg(call, 'message'));
        _onDone?.call();
        break;
    }
    return null;
  }

  static String _stringArg(MethodCall call, String key) {
    final args = call.arguments;
    if (args is Map) {
      final value = args[key];
      if (value is String) return value;
    }
    return '';
  }

  /// 开始识别。
  ///
  /// 返回 false 表示设备不支持或引擎初始化失败——调用方按既有的
  /// 「语音功能初始化失败」提示处理，与其它平台 `initialize()` 失败一致。
  Future<bool> start({
    required String language,
    required void Function(String text) onText,
    required void Function(String message) onError,
    required void Function() onDone,
  }) async {
    _onText = onText;
    _onError = onError;
    _onDone = onDone;
    final response = await _channel.invokeMapMethod<String, dynamic>('start', {
      'language': language,
    });
    if (response == null || response['ok'] != true) {
      _clearCallbacks();
      return false;
    }
    return true;
  }

  /// 结束输入并等待最终结果（对应长按结束）。
  Future<void> stop() async {
    await _channel.invokeMethod<void>('stop');
  }

  /// 取消本次识别。
  Future<void> cancel() async {
    _clearCallbacks();
    await _channel.invokeMethod<void>('cancel');
  }

  /// 释放回调引用，避免页面销毁后仍被原生事件唤醒。
  void dispose() {
    _clearCallbacks();
  }

  void _clearCallbacks() {
    _onText = null;
    _onError = null;
    _onDone = null;
  }
}
