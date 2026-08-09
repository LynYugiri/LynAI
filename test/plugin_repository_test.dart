import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/repositories/plugin_repository.dart';

String _manifestJson({
  String id = 'demo',
  String? entry,
  List<Map<String, dynamic>> editableFiles = const [],
}) {
  return jsonEncode({
    'id': id,
    'name': id,
    'version': '1.0.0',
    'author': 'LynAI',
    'description': '测试插件',
    'entry': ?entry,
    'tools': [
      {
        'name': 'ping',
        'description': '测试工具',
        'handler': 'ping',
        'parameters': {
          'type': 'object',
          'properties': {'p': {'type': 'string'}},
        },
      },
    ],
    if (editableFiles.isNotEmpty) 'editableFiles': editableFiles,
  });
}

List<int> _pluginZip(String id, {String? entry}) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('plugin.json', _manifestJson(id: id, entry: entry)))
    ..addFile(ArchiveFile.string(entry ?? 'main.lua', 'print("hi")'));
  return ZipEncoder().encode(archive);
}

List<int> _zipWith(List<ArchiveFile> files) {
  final archive = Archive();
  for (final file in files) {
    archive.addFile(file);
  }
  return ZipEncoder().encode(archive);
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lynai_plugin_repo_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  PluginRepository repo() => PluginRepository(rootOverride: root);

  test('imports a valid plugin zip and reads back manifest', () async {
    final plugin = await repo().importZipBytes(_pluginZip('demo', entry: 'main.lua'));
    expect(plugin.id, 'demo');
    expect(plugin.path, isNotEmpty);
    expect(await File('${plugin.path}/plugin.json').exists(), isTrue);

    final manifest = await repo().readManifest(plugin.path);
    expect(manifest.id, 'demo');
    expect(manifest.tools, hasLength(1));
  });

  test('rejects zip with unsafe path traversal', () async {
    final bytes = _zipWith([
      ArchiveFile.string('../escape.txt', 'x'),
      ArchiveFile.string('plugin.json', _manifestJson()),
    ]);
    expect(
      () => repo().importZipBytes(bytes),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects zip without plugin.json', () async {
    final bytes = _zipWith([ArchiveFile.string('readme.txt', 'hi')]);
    expect(
      () => repo().importZipBytes(bytes),
      throwsA(isA<Exception>()),
    );
  });

  test('persists and reloads installed plugin list', () async {
    final r = repo();
    final plugin = await r.importZipBytes(_pluginZip('demo'));
    await r.saveInstalledPlugins([plugin]);
    final reloaded = await repo().loadInstalledPlugins();
    expect(reloaded.map((p) => p.id), ['demo']);
  });

  test('builtInPluginIds and builtInPluginFiles stay consistent', () {
    for (final id in PluginRepository.builtInPluginIds) {
      expect(
        PluginRepository.builtInPluginFiles,
        contains(id),
        reason: '$id 缺少文件清单',
      );
      expect(
        PluginRepository.builtInPluginFiles[id],
        contains('plugin.json'),
        reason: '$id 清单缺少 plugin.json',
      );
    }
  });

  test('builtInPluginFiles reference the built-in asset directories', () async {
    for (final id in PluginRepository.builtInPluginIds) {
      final files = PluginRepository.builtInPluginFiles[id]!;
      for (final relative in files) {
        final asset = File(
          '${Directory.current.path}/assets/plugins/$id/$relative',
        );
        expect(
          await asset.exists(),
          isTrue,
          reason: 'assets/plugins/$id/$relative 缺失，与 builtInPluginFiles 不一致',
        );
      }
    }
  });

  test('plugin directory is scoped under the repository root', () async {
    final plugin = await repo().importZipBytes(_pluginZip('demo'));
    final rootResolved = await root.resolveSymbolicLinks();
    final pluginResolved = await File(plugin.path).resolveSymbolicLinks();
    expect(pluginResolved.startsWith(rootResolved), isTrue);
  });

  test('rejects oversized zip input', () async {
    final bytes = List<int>.filled(PluginRepository.maxPluginZipInputBytes + 1, 0);
    expect(
      () => repo().importZipBytes(bytes),
      throwsA(isA<FormatException>()),
    );
  });
}
