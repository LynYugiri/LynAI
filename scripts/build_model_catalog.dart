// 生成内置的模型目录快照（models.dev）。
//
// 用法（在 lynai/ 包根目录执行，需要网络）：
//
//   dart run scripts/build_model_catalog.dart
//
// 产出 `assets/model_catalog/catalog.json`：只保留
// `defaultModelCatalogProviderIds` 里的 provider，并按
// `lib/models/model_catalog.dart` 的规则裁剪字段（去掉 description/cost 等），
// 让快照可以随包分发、离线兜底。字段与后端 `/models/catalog` 完全一致，
// 客户端用同一个 codec 解析。
//
// 版本发布时重跑一次并把结果提交进仓库；不要把整份 api.json（约 4.9 MB）
// 直接放进 assets。

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:lynai/models/model_catalog.dart';

const _remoteUrl = 'https://models.dev/api.json';
const _outputPath = 'assets/model_catalog/catalog.json';

Future<void> main(List<String> args) async {
  final verbose = args.contains('--verbose');
  stdout.writeln('拉取 $_remoteUrl ...');
  final response = await http
      .get(Uri.parse(_remoteUrl), headers: const {'Accept': 'application/json'})
      .timeout(const Duration(seconds: 60));
  if (response.statusCode != 200) {
    stderr.writeln('拉取失败: HTTP ${response.statusCode}');
    exitCode = 1;
    return;
  }
  final raw = jsonDecode(utf8.decode(response.bodyBytes));
  if (raw is! Map) {
    stderr.writeln('上游返回的顶层 JSON 不是 object');
    exitCode = 1;
    return;
  }
  final document = ModelCatalogDocument.tryParseModelsDevApi(
    raw,
    providerFilter: defaultModelCatalogProviderIds.toSet(),
    fetchedAt: DateTime.now().toUtc(),
  );
  if (document == null) {
    stderr.writeln('裁剪后的目录为空，拒绝覆盖快照');
    exitCode = 1;
    return;
  }
  final missing = defaultModelCatalogProviderIds
      .where((id) => !document.providers.containsKey(id))
      .toList(growable: false);
  if (missing.isNotEmpty) {
    stdout.writeln('注意：上游缺少这些 provider，快照里会没有它们：$missing');
  }
  final encoded = document.encode();
  final file = File(_outputPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(encoded, flush: true);
  final models = document.providers.values.fold<int>(
    0,
    (total, provider) => total + provider.models.length,
  );
  stdout.writeln(
    '写入 $_outputPath：${document.providers.length} 个 provider / $models 个模型 / '
    '${encoded.length} 字节',
  );
  if (verbose) {
    for (final provider in document.providers.values) {
      stdout.writeln('  ${provider.id}: ${provider.models.length}');
    }
  }
}
