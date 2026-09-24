import 'package:flutter/services.dart';

import 'platform_info.dart';

/// 鸿蒙上的系统扫码桥接（Scan Kit）。
///
/// Android/iOS 用 `mobile_scanner` 自绘扫码页；鸿蒙侧的 mobile_scanner 适配分支
/// 落后于当前 SDK，因此改调系统「统一扫码」界面（自带相机权限与相册入口）。
/// 原生实现见 `ohos/entry/src/main/ets/lynai/LynaiBarcode.ets`。
///
/// 调用方应在失败时回退到已有的「导入二维码图片」路径：Scan Kit 要求在有 UI
/// 的上下文里调用，任何约束导致的失败都不应该让配对流程卡住。
class OhosBarcodeBridge {
  OhosBarcodeBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('lynai/barcode');

  final MethodChannel _channel;

  /// 当前平台是否需要走鸿蒙实现。
  static bool get isSupported => isOhosPlatform;

  /// 调起系统扫码界面。
  ///
  /// 返回扫描到的文本；用户取消返回 null；其它失败抛出 [PlatformException]。
  Future<String?> scan() async {
    final response = await _channel.invokeMapMethod<String, dynamic>('scan');
    if (response == null) {
      throw PlatformException(code: 'no_response', message: '扫码失败');
    }
    if (response['ok'] == true) {
      final value = response['value'];
      return value is String && value.isNotEmpty ? value : null;
    }
    if (response['cancelled'] == true) return null;
    throw PlatformException(
      code: 'ohos_barcode_failed',
      message: response['error'] as String? ?? '扫码失败',
    );
  }
}
