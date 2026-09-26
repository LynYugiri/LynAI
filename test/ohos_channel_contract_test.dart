import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 鸿蒙原生通道契约测试。
///
/// 鸿蒙侧的原生实现分散在 `ohos/entry/src/main/ets/lynai/*.ets`，通道名靠字符串
/// 约定；一旦 Dart 侧改名而 ArkTS 侧没跟上（或反过来），只有在真机上才会暴露成
/// `MissingPluginException`。这里把契约固化下来：
/// - 已在鸿蒙实现的通道，名字必须同时出现在 Dart 与 ArkTS 两侧；
/// - ArkTS 里不允许出现 Dart 侧从未使用的「孤儿通道」；
/// - 明文列出的 Android 专有通道不计入（它们由平台判定门控，不进入鸿蒙）。
void main() {
  /// 鸿蒙已实现（并已由 Dart 侧按平台门控调用）的通道。
  const ohosImplementedChannels = <String>{
    'lynai/background_service',
    'lynai/barcode',
    'lynai/calendar_platform',
    'lynai/clipboard',
    'lynai/file_picker',
    'lynai/native_tools',
    'lynai/secure_storage',
    'lynai/speech',
  };

  /// 只在 Android 上注册的通道：Dart 侧由 `Platform.isAndroid` /
  /// `defaultTargetPlatform == TargetPlatform.android` 门控，鸿蒙不会调用。
  const androidOnlyChannels = <String>{
    'lynai/device_control',
    'lynai/floating_assistant',
    'lynai/on_device_llm',
    'lynai/screen_translation',
    'lynai/scroll_capture',
  };

  Set<String> channelsInDirectory(String path, Pattern pattern) {
    final directory = Directory(path);
    expect(directory.existsSync(), isTrue, reason: '$path 不存在');
    final channels = <String>{};
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in pattern.allMatches(source)) {
        channels.add(match.group(1)!);
      }
    }
    return channels;
  }

  test('Dart 侧使用的 lynai 通道都能归类', () {
    final dartChannels = channelsInDirectory(
      'lib',
      RegExp(r"MethodChannel\(\s*'((?:lynai)/[^']+)'"),
    );
    expect(dartChannels, isNotEmpty);
    final unclassified = dartChannels
        .difference(ohosImplementedChannels)
        .difference(androidOnlyChannels);
    expect(
      unclassified,
      isEmpty,
      reason: '新增通道需要同时在鸿蒙侧实现，或加入 Android 专有清单',
    );
  });

  test('鸿蒙通道名字与 Dart 侧一致', () {
    final dartSource = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    final arkTsFiles = Directory('ohos/entry/src/main/ets/lynai')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.ets'))
        .toList();
    final arkTsSource = arkTsFiles
        .map((file) => file.readAsStringSync())
        .join('\n');

    for (final channel in ohosImplementedChannels) {
      expect(
        dartSource.contains("'$channel'"),
        isTrue,
        reason: 'Dart 侧不再使用 $channel，需要同步清理鸿蒙实现',
      );
      expect(
        arkTsSource.contains("'$channel'"),
        isTrue,
        reason: '鸿蒙侧缺少 $channel 的实现',
      );
    }

    // 反向检查：ArkTS 侧不能出现 Dart 侧从未使用、也不在 Android 专有清单里的
    // 孤儿通道——否则新通道只在鸿蒙注册，谁都不会调用也无人发现。
    final arkTsChannels = <String>{};
    final channelPattern = RegExp(r"'(lynai/[a-z0-9_]+)'");
    for (final file in arkTsFiles) {
      for (final match in channelPattern.allMatches(file.readAsStringSync())) {
        arkTsChannels.add(match.group(1)!);
      }
    }
    expect(arkTsChannels, isNotEmpty);
    expect(
      arkTsChannels
          .difference(ohosImplementedChannels)
          .difference(androidOnlyChannels),
      isEmpty,
      reason: 'ArkTS 侧的通道必须在 Dart 侧有调用方，或加入 Android 专有清单',
    );
  });

  test('安全存储通道的方法与 Dart 调用保持一致', () {
    final arkTs = File(
      'ohos/entry/src/main/ets/lynai/LynaiSecureStorage.ets',
    ).readAsStringSync();
    for (final method in const ['read', 'write', 'delete']) {
      expect(
        arkTs.contains("case '$method':"),
        isTrue,
        reason: 'LynaiSecureStorage 缺少 $method 分支',
      );
    }
    final dart = File('lib/services/secret_store.dart').readAsStringSync();
    for (final method in const ['read', 'write', 'delete']) {
      expect(
        dart.contains("'$method'"),
        isTrue,
        reason: 'OhosAssetSecretStore 没有调用 $method',
      );
    }
  });

  test('文件选择通道的方法与 Dart 调用保持一致', () {
    final arkTs = File(
      'ohos/entry/src/main/ets/lynai/LynaiFilePicker.ets',
    ).readAsStringSync();
    for (final method in const ['pickFiles', 'saveFile']) {
      expect(
        arkTs.contains("case '$method':"),
        isTrue,
        reason: 'LynaiFilePicker 缺少 $method 分支',
      );
    }
    final dart = File('lib/utils/ohos_file_picker.dart').readAsStringSync();
    for (final method in const ['pickFiles', 'saveFile']) {
      expect(dart.contains("'$method'"), isTrue);
    }
  });
}
