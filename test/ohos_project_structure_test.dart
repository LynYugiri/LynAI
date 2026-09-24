import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 鸿蒙工程的结构一致性测试（默认依赖集下运行，不需要鸿蒙 SDK）。
///
/// `ohos/` 里的清单、资源与 ArkTS 文件之间靠字符串引用，写错只有在
/// hvigor 构建或真机上才会暴露。这里把几类互相关联的约定固化下来：
/// - `module.json5` 引用的源文件、资源、profile 都必须存在；
/// - `form_config.json` 必填字段齐全，`src` 指向真实卡片文件，默认尺寸在支持列表内；
/// - 每个 `Lynai*.ets` 插件都必须在 `EntryAbility` 里注册（防止新增插件漏注册）；
/// - `AppScope/app.json5` 的包名与 Android 的 applicationId 保持一致。
void main() {
  /// 去掉整行注释与尾随逗号后的 JSON5 文本（工程里的 .json5 只用到这两种扩展）。
  Map<String, dynamic> parseJson5(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path 不存在');
    final buffer = StringBuffer();
    for (final line in file.readAsLinesSync()) {
      if (line.trimLeft().startsWith('//')) continue;
      buffer.writeln(line);
    }
    final text = buffer
        .toString()
        .replaceAllMapped(RegExp(r',(\s*[}\]])'), (match) => match.group(1)!);
    return jsonDecode(text) as Map<String, dynamic>;
  }

  final moduleRoot = 'ohos/entry/src/main';
  final baseResources = '$moduleRoot/resources/base';

  test('module.json5 引用的源文件与资源都存在', () {
    final manifest = parseJson5('$moduleRoot/module.json5');
    final module = manifest['module'] as Map<String, dynamic>;

    final references = <String>[];
    for (final ability in module['abilities'] as List<dynamic>) {
      references.add((ability as Map<String, dynamic>)['srcEntry'] as String);
    }
    for (final extension in (module['extensionAbilities'] as List<dynamic>? ?? [])) {
      final entry = extension as Map<String, dynamic>;
      references.add(entry['srcEntry'] as String);
      for (final metadata in (entry['metadata'] as List<dynamic>? ?? [])) {
        references.add(
          ((metadata as Map<String, dynamic>)['resource'] as String),
        );
      }
    }

    for (final reference in references) {
      if (reference.startsWith(r'$profile:')) {
        final name = reference.substring(r'$profile:'.length);
        final candidate = File('$baseResources/profile/$name.json');
        expect(
          candidate.existsSync(),
          isTrue,
          reason: 'module.json5 引用了不存在的 profile: $reference',
        );
        continue;
      }
      final file = File('$moduleRoot/$reference'.replaceAll('./', '/'));
      expect(
        file.existsSync(),
        isTrue,
        reason: 'module.json5 引用了不存在的源文件: $reference',
      );
    }

    // 权限声明里 user_grant 的项必须带 reason 与 usedScene。
    for (final permission in (module['requestPermissions'] as List<dynamic>)) {
      final entry = permission as Map<String, dynamic>;
      final name = entry['name'] as String;
      expect(name, startsWith('ohos.permission.'));
      if (entry.containsKey('reason')) {
        final reason = entry['reason'] as String;
        expect(reason, startsWith(r'$string:'), reason: '$name 的 reason 必须是字符串资源');
        expect(
          entry['usedScene'],
          isNotNull,
          reason: '$name 声明了 reason 就必须声明 usedScene',
        );
      }
    }
  });

  test(r'module.json5 里的 $string/$media/$color 引用都能解析', () {
    final raw = File('$moduleRoot/module.json5').readAsStringSync();
    final strings = (jsonDecode(
      File('$baseResources/element/string.json').readAsStringSync(),
    ) as Map<String, dynamic>)['string'] as List<dynamic>;
    final stringNames = strings
        .map((item) => (item as Map<String, dynamic>)['name'] as String)
        .toSet();
    final colors = (jsonDecode(
      File('$baseResources/element/color.json').readAsStringSync(),
    ) as Map<String, dynamic>)['color'] as List<dynamic>;
    final colorNames = colors
        .map((item) => (item as Map<String, dynamic>)['name'] as String)
        .toSet();

    for (final match in RegExp(r'\$string:([A-Za-z0-9_]+)').allMatches(raw)) {
      expect(
        stringNames,
        contains(match.group(1)),
        reason: 'module.json5 引用了不存在的字符串资源 ${match.group(1)}',
      );
    }
    for (final match in RegExp(r'\$color:([A-Za-z0-9_]+)').allMatches(raw)) {
      expect(
        colorNames,
        contains(match.group(1)),
        reason: 'module.json5 引用了不存在的颜色资源 ${match.group(1)}',
      );
    }
    for (final match in RegExp(r'\$media:([A-Za-z0-9_]+)').allMatches(raw)) {
      expect(
        File('$baseResources/media/${match.group(1)}.png').existsSync(),
        isTrue,
        reason: 'module.json5 引用了不存在的图片资源 ${match.group(1)}',
      );
    }
  });

  test('服务卡片配置完整且指向真实卡片文件', () {
    final config = jsonDecode(
      File('$baseResources/profile/form_config.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final forms = config['forms'] as List<dynamic>;
    expect(forms, isNotEmpty);

    for (final form in forms) {
      final entry = form as Map<String, dynamic>;
      for (final key in const [
        'name',
        'isDefault',
        'supportDimensions',
        'defaultDimension',
        'updateEnabled',
      ]) {
        expect(entry.containsKey(key), isTrue, reason: 'form_config 缺少必填字段 $key');
      }
      final dimensions = (entry['supportDimensions'] as List<dynamic>).cast<String>();
      expect(
        dimensions,
        contains(entry['defaultDimension']),
        reason: 'defaultDimension 必须在 supportDimensions 内',
      );
      final src = entry['src'] as String;
      expect(
        File('$moduleRoot/$src'.replaceAll('./', '/')).existsSync(),
        isTrue,
        reason: '卡片页面不存在: $src',
      );
      expect(entry['uiSyntax'], 'arkts');
    }
  });

  test('每个 Lynai 插件都在 EntryAbility 中注册', () {
    final pluginDir = Directory('ohos/entry/src/main/ets/lynai');
    final plugins = pluginDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.ets'))
        .map((file) => file.uri.pathSegments.last.replaceAll('.ets', ''))
        .where((name) => name.startsWith('Lynai'))
        .toList()
      ..sort();
    expect(plugins, isNotEmpty);

    final ability = File(
      'ohos/entry/src/main/ets/entryability/EntryAbility.ets',
    ).readAsStringSync();
    for (final plugin in plugins) {
      expect(
        ability.contains("import { $plugin }"),
        isTrue,
        reason: 'EntryAbility 没有 import $plugin',
      );
      expect(
        ability.contains('$plugin.register('),
        isTrue,
        reason: 'EntryAbility 没有注册 $plugin',
      );
    }
  });

  test('syscap 受限的 API 调用前都做了能力探测', () {
    // 这些 API 会被编译器标为 “not supported on all devices”：缺能力的设备上调用
    // 会抛异常，而异常从 onMethodCall 抛出会越过 Dart 侧的回退分支，因此约定
    // 调用前必须用 SysCapUtils 探测一次。
    const restrictedApis = <String>[
      'backgroundTaskManager.',
      'scanBarcode.',
      'scanCore.',
    ];
    final guarded = <String>[];

    for (final file in Directory(
      'ohos/entry/src/main/ets/lynai',
    ).listSync().whereType<File>()) {
      if (!file.path.endsWith('.ets')) continue;
      final source = file.readAsStringSync();
      if (!restrictedApis.any(source.contains)) continue;
      final name = file.uri.pathSegments.last;
      guarded.add(name);
      expect(
        source,
        contains("from './SysCapUtils'"),
        reason: '$name 使用了 syscap 受限 API，但没有引入 SysCapUtils',
      );
      expect(
        RegExp(r'sysCaps?Available\(').hasMatch(source),
        isTrue,
        reason: '$name 使用了 syscap 受限 API，但没有调用能力探测',
      );
    }

    expect(
      guarded,
      isNotEmpty,
      reason: '至少有扫码（Scan Kit）与长时任务两个插件受此约束',
    );
  });

  test('SysCapUtils 的 syscap 常量与 ArkTS 引用一一对应', () {
    final utils = File(
      'ohos/entry/src/main/ets/lynai/SysCapUtils.ts',
    ).readAsStringSync();
    final constants = RegExp(
      r"export const (SYSCAP_[A-Z_]+): string\s*=\s*'([^']+)'",
    ).allMatches(utils).map((match) => MapEntry(match.group(1)!, match.group(2)!)).toList();
    final names = constants.map((entry) => entry.key).toList();
    expect(names, isNotEmpty, reason: 'SysCapUtils 应导出 syscap 常量');

    for (final entry in constants) {
      expect(
        entry.value,
        startsWith('SystemCapability.'),
        reason: '${entry.key} 的取值不是合法的 syscap：${entry.value}',
      );
    }

    for (final file in Directory(
      'ohos/entry/src/main/ets/lynai',
    ).listSync().whereType<File>()) {
      if (!file.path.endsWith('.ets')) continue;
      final source = file.readAsStringSync();
      for (final match in RegExp(r'\b(SYSCAP_[A-Z_]+)\b').allMatches(source)) {
        expect(
          names,
          contains(match.group(1)),
          reason: '${file.uri.pathSegments.last} 引用了未定义的 ${match.group(1)}',
        );
      }
    }
  });

  test('鸿蒙包名与 Android applicationId 一致', () {
    final app = parseJson5('ohos/AppScope/app.json5');
    final bundleName =
        (app['app'] as Map<String, dynamic>)['bundleName'] as String;

    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final match = RegExp(
      r'applicationId\s*=\s*"([^"]+)"',
    ).firstMatch(gradle);
    expect(match, isNotNull, reason: '未能从 android/app/build.gradle.kts 读到 applicationId');
    expect(
      bundleName,
      match!.group(1),
      reason: '鸿蒙包名应与 Android applicationId 保持一致',
    );
  });
}
