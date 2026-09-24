import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// 平台判定与平台能力开关。
///
/// 鸿蒙（HarmonyOS / OpenHarmony，下文简称 OHOS）使用
/// [openharmony-sig/flutter_flutter](https://gitcode.com/openharmony-sig/flutter_flutter)
/// 分支的 Flutter SDK 构建。该分支给 `dart:io` 的 `Platform` 增加了
/// `Platform.isOhos`，并给 `TargetPlatform` 增加了 `TargetPlatform.ohos`；
/// 但上游 Flutter stable 没有这两个符号，直接引用会让同一份源码在
/// Android/iOS/桌面/Web 上**无法编译**。
///
/// 因此本文件用两套 SDK 都能编译的方式做判定：
/// - 平台判定统一走 `Platform.operatingSystem` 字符串比较（OHOS 引擎返回
///   `'ohos'`，上游返回 `'android'`/`'ios'`/`'linux'`/`'macos'`/`'windows'`）。
/// - 能力开关只使用各平台都存在的 API；需要 OHOS 分支时用
///   [isOhosPlatform] 而不是 `TargetPlatform.ohos`。
///
/// Web 上访问 `Platform` 会抛 `UnsupportedError`，所以所有判定都先检查
/// [kIsWeb]，保证 Web 目标仍可编译并在运行时安全返回 `false`。

/// 是否运行在浏览器（Web）目标上。
bool get isWebPlatform => kIsWeb;

/// 是否运行在鸿蒙（HarmonyOS / OpenHarmony）设备上。
bool get isOhosPlatform => !kIsWeb && Platform.operatingSystem == 'ohos';

/// 是否运行在 Android 上。
bool get isAndroidPlatform => !kIsWeb && Platform.isAndroid;

/// 是否运行在 iOS 上。
bool get isIOSPlatform => !kIsWeb && Platform.isIOS;

/// 是否运行在 Linux 上。
bool get isLinuxPlatform => !kIsWeb && Platform.isLinux;

/// 是否运行在 macOS 上。
bool get isMacOSPlatform => !kIsWeb && Platform.isMacOS;

/// 是否运行在 Windows 上。
bool get isWindowsPlatform => !kIsWeb && Platform.isWindows;

/// 是否运行在 Fuchsia 上。
bool get isFuchsiaPlatform => !kIsWeb && Platform.isFuchsia;

/// 是否为移动端语义平台：Android、iOS 或鸿蒙。
///
/// 用于软键盘处理、图库保存、移动端选择器等触屏/移动语义分支；
/// 桌面端（Linux/macOS/Windows）与 Web 返回 `false`。
bool get isMobilePlatform =>
    isAndroidPlatform || isIOSPlatform || isOhosPlatform;

/// 是否为桌面端平台：Linux、macOS 或 Windows。
///
/// 鸿蒙与 Web 返回 `false`。
bool get isDesktopPlatform =>
    isLinuxPlatform || isMacOSPlatform || isWindowsPlatform;

/// 是否支持 `super_clipboard` 富剪贴板（图片读写）。
///
/// `super_clipboard` 依赖的 `super_native_extensions` 没有鸿蒙实现，且它在
/// 未知平台上会直接抛 `UnimplementedError`（`currentPlatform` 只覆盖
/// Android/iOS/Linux/macOS/Windows/Web），所以鸿蒙上必须完全绕开该 API，
/// 图片保存改走图库通道。
///
/// 注意这是 [supportsRichClipboard] 的**读取**语义：它同时决定「能否从剪贴板
/// 读取图片」。鸿蒙的剪贴板读取需要 `ohos.permission.READ_PASTEBOARD`，该权限
/// 不向普通应用开放，因此鸿蒙上仍不提供粘贴图片；只写不读的
/// [supportsImageClipboardWrite] 则是可用的（鸿蒙写入剪贴板不需要权限）。
bool get supportsRichClipboard => !isOhosPlatform;

/// 是否能把图片写入系统剪贴板。
///
/// 桌面端由 `super_clipboard` 提供，鸿蒙端由 `lynai/clipboard` 通道写入
/// PixelMap 记录，其余平台沿用各自实现，因此所有平台都支持。
bool get supportsImageClipboardWrite => true;

/// 是否支持 `bonsoir` 的 mDNS 广播与发现（局域网同步的设备发现）。
///
/// `bonsoir` 没有鸿蒙实现，调用会抛 `MissingPluginException`。
/// 鸿蒙上仍需保留手动导入/扫描配对码的配对路径。
bool get supportsMdnsDiscovery => !isOhosPlatform;

/// 是否支持用 `mobile_scanner` 在应用内自绘扫码页。
///
/// 鸿蒙侧的 `mobile_scanner` 适配版本落后于当前 SDK 版本，暂未纳入依赖。
bool get supportsQrScanner => isAndroidPlatform || isIOSPlatform;

/// 是否支持调起系统扫码界面（鸿蒙统一扫码服务 Scan Kit）。
bool get supportsSystemQrScan => isOhosPlatform;

/// 是否能直接扫码读取配对码（应用内扫码页或系统扫码 UI）。
///
/// 为 false 时走「导入配对码图片」的等价路径。
bool get canScanPairingCode => supportsQrScanner || supportsSystemQrScan;

/// 是否支持语音输入。
///
/// Android/iOS 用 `speech_to_text` 的系统识别，鸿蒙用系统基础语音服务
/// （Core Speech Kit，设备侧离线识别，见 `lynai/speech` 通道）；
/// 配置了语音转文字模型时各平台都改走录音 + 服务端转写。
/// 缺少对应实现的平台返回 false，语音入口不展示。
bool get supportsVoiceInput => true;

/// 面向用户的平台展示名，用于「关于」页等界面文案。
///
/// 未识别的平台返回 `'Unknown'`，不使用会随 SDK 变化的枚举值。
String get platformDisplayName {
  if (kIsWeb) return 'Web';
  if (isOhosPlatform) return 'HarmonyOS';
  if (isAndroidPlatform) return 'Android';
  if (isIOSPlatform) return 'iOS';
  if (isMacOSPlatform) return 'macOS';
  if (isLinuxPlatform) return 'Linux';
  if (isWindowsPlatform) return 'Windows';
  if (isFuchsiaPlatform) return 'Fuchsia';
  return 'Unknown';
}

/// 设备注册 / 同步上报使用的规范化平台标识。
///
/// 后端 `devices.platform` 列约束为 `^[a-z0-9._-]{1,32}$`，`'ohos'` 满足约束，
/// 无需后端改动。Web 与未识别平台返回 `'unknown'`。
String get devicePlatformId {
  if (kIsWeb) return 'web';
  if (isOhosPlatform) return 'ohos';
  if (isAndroidPlatform) return 'android';
  if (isIOSPlatform) return 'ios';
  if (isMacOSPlatform) return 'macos';
  if (isWindowsPlatform) return 'windows';
  if (isLinuxPlatform) return 'linux';
  return 'unknown';
}
