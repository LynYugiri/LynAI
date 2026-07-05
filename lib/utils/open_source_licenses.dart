import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _licenseAssets = [
  (packages: ['LynAI'], assetPath: 'LICENSE'),
  (
    packages: ['LynAI third-party notices'],
    assetPath: 'THIRD_PARTY_NOTICES.md',
  ),
  (packages: ['lua_dardo'], assetPath: 'third_party/lua_dardo/LICENSE'),
  (
    packages: ['webview_all_linux'],
    assetPath: 'third_party/webview_all_linux/LICENSE',
  ),
  (
    packages: ['webview_all_windows'],
    assetPath: 'third_party/webview_all_windows/LICENSE',
  ),
];

/// 注册项目自身及本地 third_party 依赖的许可信息。
Future<void> registerOpenSourceLicenses() async {
  for (final item in _licenseAssets) {
    final text = await rootBundle.loadString(item.assetPath);
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(item.packages, text);
    });
  }
}
