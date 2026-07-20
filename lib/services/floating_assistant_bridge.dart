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
  static const MethodChannel _translationChannel = MethodChannel(
    'lynai/screen_translation',
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

  Future<void> updateTranslationState(Map<String, dynamic> payload) {
    return _invoke('updateTranslationState', payload);
  }

  Future<List<Map<String, dynamic>>> captureOcrGroups() async {
    final response = await _invokeTranslationResult('captureAndRecognize');
    final result = response is Map ? response['result'] : null;
    final groups = result is Map ? result['groups'] : null;
    if (groups is! List) return const [];
    return groups
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
  }

  Future<void> replaceTranslations(Map<String, dynamic> payload) =>
      _invokeTranslation('showTranslations', payload);

  Future<void> clearTranslations() => _invokeTranslation('clearTranslations');

  Future<dynamic> _invokeTranslationResult(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    if (!isSupported) return null;
    try {
      return await _translationChannel.invokeMethod<dynamic>(
        method,
        arguments ?? const {},
      );
    } catch (e) {
      debugPrint('FloatingAssistantBridge.translation.$method failed: $e');
      return null;
    }
  }

  Future<void> _invokeTranslation(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    await _invokeTranslationResult(method, arguments);
  }

  Future<void> _invoke(String method, [Map<String, dynamic>? arguments]) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>(method, arguments ?? const {});
    } catch (e) {
      debugPrint('FloatingAssistantBridge.$method failed: $e');
    }
  }
}
