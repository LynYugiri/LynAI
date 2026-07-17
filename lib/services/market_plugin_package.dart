import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/plugin_market_entry.dart';
import '../repositories/plugin_repository.dart';
import 'bounded_zip_decoder.dart';

/// Validates market metadata before the ZIP reaches the atomic installer.
void validateMarketPluginPackage(List<int> bytes, MarketPluginEntry entry) {
  if (bytes.length > PluginRepository.maxPluginZipInputBytes) {
    throw const FormatException('市场插件 ZIP 超过 32 MiB 输入上限');
  }
  final expectedHash = entry.sha256?.trim().toLowerCase() ?? '';
  if (expectedHash.isNotEmpty &&
      sha256.convert(bytes).toString() != expectedHash) {
    throw const FormatException('下载的插件 ZIP SHA-256 校验失败');
  }

  final archive = decodeBoundedZip(
    bytes,
    limits: const BoundedZipLimits(
      maxEntries: 1024,
      maxEntryBytes: 16 * 1024 * 1024,
      maxTotalBytes: 64 * 1024 * 1024,
    ),
    archiveLabel: '市场插件压缩包',
  );
  final manifests = archive
      .where(
        (item) =>
            item.isFile &&
            (item.name == 'plugin.json' || item.name.endsWith('/plugin.json')),
      )
      .toList(growable: false);
  if (manifests.length != 1 || manifests.single.name != 'plugin.json') {
    throw const FormatException('市场插件 ZIP 必须包含唯一根目录 plugin.json');
  }
  final data = jsonDecode(utf8.decode(manifests.single.content as List<int>));
  if (data is! Map || data['id'] != entry.id) {
    throw FormatException('市场插件 ZIP 的 manifest ID 与 ${entry.id} 不匹配');
  }
}
