import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_all/webview_all.dart';

/// Shared cleanup for webview_all desktop native overlays.
class WebViewDisposeUtils {
  const WebViewDisposeUtils._();

  static bool get _needsDesktopDispose {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  static Future<void> waitForNativeDetach() async {
    if (!_needsDesktopDispose) return;
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  static Future<void> disposeDesktop(WebViewController controller) async {
    if (!_needsDesktopDispose) return;
    try {
      final platform = controller.platform as dynamic;
      await platform.dispose();
    } catch (e) {
      debugPrint('释放桌面 WebView 失败: $e');
    }
  }
}
