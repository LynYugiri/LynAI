import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GenerationBackgroundService {
  const GenerationBackgroundService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('lynai/background_service');

  final MethodChannel _channel;

  Future<void> setActive(bool active) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>(
      active ? 'startGeneration' : 'stopGeneration',
    );
  }
}
