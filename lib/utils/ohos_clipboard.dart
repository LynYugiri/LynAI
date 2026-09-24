import 'package:flutter/services.dart';

import 'platform_info.dart';

/// 鸿蒙上的系统剪贴板写入桥接。
///
/// 工程里的图片剪贴板原本由 `super_clipboard` 提供，而它没有鸿蒙实现；
/// 鸿蒙侧改走自有通道 `lynai/clipboard`（原生实现见
/// `ohos/entry/src/main/ets/lynai/LynaiClipboard.ets`），把图片解码成 PixelMap
/// 后以 `MIMETYPE_PIXELMAP` 记录写入系统剪贴板。
///
/// 只做写入：读取剪贴板需要 `ohos.permission.READ_PASTEBOARD`，该权限不向普通
/// 应用开放，因此鸿蒙上不提供「从剪贴板粘贴图片」，相关入口由
/// [supportsRichClipboard] 门控关闭。
class OhosClipboardBridge {
  OhosClipboardBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('lynai/clipboard');

  final MethodChannel _channel;

  /// 当前平台是否需要走鸿蒙实现。
  static bool get isSupported => isOhosPlatform;

  /// 写入图片；失败时抛出 [PlatformException]，调用方按既有方式提示用户。
  Future<void> copyImage(Uint8List bytes, {String mimeType = 'image/png'}) async {
    final response = await _channel.invokeMapMethod<String, dynamic>('copyImage', {
      'bytes': bytes,
      'mimeType': mimeType,
    });
    if (response == null) {
      throw PlatformException(code: 'no_response', message: '复制图片失败');
    }
    if (response['ok'] != true) {
      throw PlatformException(
        code: 'ohos_clipboard_failed',
        message: response['error'] as String? ?? '复制图片失败',
      );
    }
  }
}
