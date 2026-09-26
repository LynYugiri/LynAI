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
///
/// 通道回调只能按「通道名」注册一次，而一个聊天页持有一个桥接实例，且
/// `HomePage` 的 `IndexedStack` 与插件 AI 工作区会同时存在多个聊天页。因此这里
/// 只在首次使用时安装一个静态回调入口，并把事件派发给**当前正在识别**的实例：
/// 后打开的页面不会抢走、也不会在关闭时摘掉其它页面的回调。
class OhosSpeechBridge {
  OhosSpeechBridge({MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel('lynai/speech'),
      _supported = supported ?? isOhosPlatform;

  final MethodChannel _channel;
  final bool _supported;

  /// 当前平台是否需要走鸿蒙实现（调用方判断入口是否展示时使用）。
  static bool get isSupported => isOhosPlatform;

  /// 本实例是否可用：非鸿蒙平台上所有方法都是空操作，不会触碰平台通道。
  bool get isAvailable => _supported;

  /// 正在接收原生回调的实例。
  static OhosSpeechBridge? _active;
  static bool _handlerInstalled = false;

  void Function(String text)? _onText;
  void Function(String message)? _onError;
  void Function()? _onDone;

  static void _ensureHandler(MethodChannel channel) {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    channel.setMethodCallHandler(_dispatchNativeCall);
  }

  static Future<Object?> _dispatchNativeCall(MethodCall call) async {
    final target = _active;
    if (target == null) return null;
    return target._handleNativeCall(call);
  }

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
    if (!_supported) {
      _clearCallbacks();
      return false;
    }
    _ensureHandler(_channel);
    _active = this;
    final response = await _invokeMap('start', {'language': language});
    if (response == null || response['ok'] != true) {
      _clearCallbacks();
      _releaseSession();
      return false;
    }
    return true;
  }

  /// 结束输入并等待最终结果（对应长按结束）。
  Future<void> stop() async {
    if (!_supported) return;
    await _invoke('stop');
    _releaseSession();
  }

  /// 取消本次识别。
  Future<void> cancel() async {
    _clearCallbacks();
    _releaseSession();
    if (!_supported) return;
    await _invoke('cancel');
  }

  /// 释放回调引用，避免页面销毁后仍被原生事件唤醒。
  void dispose() {
    _clearCallbacks();
    _releaseSession();
  }

  /// 只有当前会话的持有者才能结束会话：别的页面正在识别时不要把它清掉。
  void _releaseSession() {
    if (identical(_active, this)) _active = null;
  }

  void _clearCallbacks() {
    _onText = null;
    _onError = null;
    _onDone = null;
  }

  Future<Map<String, dynamic>?> _invokeMap(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>(
        method,
        arguments,
      );
    } on MissingPluginException {
      // 平台判定与实际实现不一致（例如自制构建缺少该通道）时不向上抛：
      // 调用方只需要知道本次识别没有成功。
      return null;
    }
  }

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // 同上：非鸿蒙实现或缺少通道时静默跳过。
    }
  }
}
