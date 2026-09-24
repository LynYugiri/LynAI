import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/platform_info.dart';

/// 生成期间保持进程存活。
///
/// Android 走前台服务（`GenerationForegroundService` + 常驻通知），
/// 鸿蒙走长时任务（continuous task，`LynaiBackgroundService.ets`）。
/// 两端都只在「正在生成」期间启用，停止或结束时关闭。
class GenerationBackgroundService {
  const GenerationBackgroundService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('lynai/background_service');

  final MethodChannel _channel;

  Future<void> setActive(bool active) async {
    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.android || isOhosPlatform)) {
      return;
    }
    await _channel.invokeMethod<void>(
      active ? 'startGeneration' : 'stopGeneration',
    );
  }
}
