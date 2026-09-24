import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/utils/platform_info.dart';

/// 平台判定与能力开关的回归测试。
///
/// 测试进程运行在宿主平台上（CI 为 Linux，本地可能是 macOS/Windows），
/// 因此这里断言的是「非鸿蒙平台」的既有行为：判定结果必须与直接使用
/// `dart:io` 的 `Platform` / `defaultTargetPlatform` 语义一致，
/// 鸿蒙分支不会在其它平台上被误触发。
void main() {
  group('平台判定', () {
    test('非鸿蒙平台上 isOhosPlatform 为 false', () {
      expect(isOhosPlatform, isFalse);
      expect(isWebPlatform, isFalse);
    });

    test('与 dart:io Platform 的判定保持一致', () {
      expect(isAndroidPlatform, Platform.isAndroid);
      expect(isIOSPlatform, Platform.isIOS);
      expect(isLinuxPlatform, Platform.isLinux);
      expect(isMacOSPlatform, Platform.isMacOS);
      expect(isWindowsPlatform, Platform.isWindows);
      expect(isFuchsiaPlatform, Platform.isFuchsia);
    });

    test('移动端与桌面端互斥且覆盖当前平台', () {
      expect(isMobilePlatform && isDesktopPlatform, isFalse);
      final currentIsDesktop =
          Platform.isLinux || Platform.isMacOS || Platform.isWindows;
      expect(isDesktopPlatform, currentIsDesktop);
      final currentIsMobile =
          Platform.isAndroid || Platform.isIOS || Platform.operatingSystem == 'ohos';
      expect(isMobilePlatform, currentIsMobile);
    });

    test('平台展示名与设备上报标识跟随当前平台', () {
      final expectedName = Platform.isAndroid
          ? 'Android'
          : Platform.isIOS
          ? 'iOS'
          : Platform.isMacOS
          ? 'macOS'
          : Platform.isLinux
          ? 'Linux'
          : Platform.isWindows
          ? 'Windows'
          : Platform.isFuchsia
          ? 'Fuchsia'
          : 'Unknown';
      expect(platformDisplayName, expectedName);

      // 后端 devices.platform 约束为 ^[a-z0-9._-]{1,32}$。
      expect(devicePlatformId, matches(RegExp(r'^[a-z0-9._-]{1,32}$')));
    });
  });

  group('能力开关', () {
    test('非鸿蒙平台上不关闭既有能力', () {
      expect(supportsRichClipboard, isTrue);
      expect(supportsMdnsDiscovery, isTrue);
      expect(supportsVoiceInput, isTrue);
    });

    test('扫码能力只在 Android/iOS 上开放', () {
      expect(
        supportsQrScanner,
        Platform.isAndroid || Platform.isIOS,
      );
    });
  });
}
