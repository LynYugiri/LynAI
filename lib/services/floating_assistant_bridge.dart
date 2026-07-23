import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TranslationBridgeException implements Exception {
  const TranslationBridgeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

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
    if (response == null) return const [];
    final result = response['result'];
    final groups = result is Map ? result['groups'] : null;
    if (groups is! List) {
      throw const TranslationBridgeException(
        'invalid_capture_result',
        'Screen capture returned an invalid OCR result',
      );
    }
    return groups
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
  }

  Future<void> replaceTranslations(Map<String, dynamic> payload) =>
      _invokeTranslation('showTranslations', payload);

  Future<void> clearTranslations() => _invokeTranslation('clearTranslations');

  Future<Map<dynamic, dynamic>?> _invokeTranslationResult(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    if (!isSupported) return null;
    try {
      final response = await _translationChannel.invokeMethod<dynamic>(
        method,
        arguments ?? const {},
      );
      if (response is! Map) {
        throw TranslationBridgeException(
          'invalid_native_result',
          '$method returned an invalid native result',
        );
      }
      if (response['ok'] == true) return response;
      final error = response['error'];
      final code = error is Map
          ? error['code']?.toString() ?? 'translation_failed'
          : 'translation_failed';
      final message = error is Map
          ? error['message']?.toString() ?? '$method failed'
          : error?.toString() ?? '$method failed';
      throw TranslationBridgeException(code, message);
    } catch (e) {
      debugPrint('FloatingAssistantBridge.translation.$method failed: $e');
      rethrow;
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
