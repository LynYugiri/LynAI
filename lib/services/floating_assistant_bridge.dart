import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FloatingAssistantBridge {
  FloatingAssistantBridge._();

  static final FloatingAssistantBridge instance = FloatingAssistantBridge._();
  static const MethodChannel _channel = MethodChannel(
    'lynai/floating_assistant',
  );

  bool get isSupported => Platform.isAndroid;

  void setHandler(Future<dynamic> Function(MethodCall call)? handler) {
    if (!isSupported) return;
    _channel.setMethodCallHandler(handler);
  }

  Future<void> configure(Map<String, dynamic> payload) {
    return _invoke('configure', payload);
  }

  Future<void> showBubble() => _invoke('showBubble');
  Future<void> hideBubble() => _invoke('hideBubble');

  Future<void> updateAgentPlan(Map<String, dynamic> payload) {
    return _invoke('updateAgentPlan', payload);
  }

  Future<void> updateChatState(Map<String, dynamic> payload) {
    return _invoke('updateChatState', payload);
  }

  Future<void> setTranslationRunning(bool running) {
    return _invoke('setTranslationRunning', {'running': running});
  }

  Future<void> clearTranslationBlocks() => _invoke('clearTranslationBlocks');

  Future<void> updateTranslationOverlay(
    Map<String, dynamic> payload,
  ) => _invoke('updateTranslationOverlay', payload);

  Future<void> clearTranslationOverlay() => _invoke('clearTranslationOverlay');

  Future<void> _invoke(String method, [Map<String, dynamic>? arguments]) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>(method, arguments ?? const {});
    } catch (e) {
      debugPrint('FloatingAssistantBridge.$method failed: $e');
    }
  }
}
