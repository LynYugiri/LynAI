import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/plugin.dart';

/// 插件文件系统仓储。
///
/// 负责把用户导入的目录或 ZIP 复制到应用私有目录，并维护安装状态、插件设置和
/// 插件私有 storage。仓储层不解释权限，也不执行插件代码，只处理可信的本地
/// 文件布局和 JSON 持久化。
class PluginRepository {
  static const _stateFileName = 'installed_plugins.json';

  Future<List<InstalledPlugin>> loadInstalledPlugins() async {
    final file = await _stateFile();
    if (!await file.exists()) return const [];
    final data = jsonDecode(await file.readAsString());
    final items = data is Map ? data['plugins'] as List? : null;
    return (items ?? const [])
        .whereType<Map>()
        .map(
          (item) => InstalledPlugin.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> saveInstalledPlugins(List<InstalledPlugin> plugins) async {
    final file = await _stateFile();
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'plugins': plugins.map((item) => item.toJson()).toList()}),
      flush: true,
    );
  }

  Future<InstalledPlugin> importDirectory(String sourcePath) async {
    final source = Directory(sourcePath);
    if (!await source.exists()) throw Exception('插件目录不存在');
    final manifest = await readManifest(source.path);
    final target = await _pluginDirectory(manifest.id);
    await _replaceDirectory(source, target);
    return _installedPlugin(manifest, target.path);
  }

  Future<InstalledPlugin> importZip(String zipPath) async {
    final file = File(zipPath);
    if (!await file.exists()) throw Exception('插件压缩包不存在');
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final root = await Directory.systemTemp.createTemp('lynai_plugin_import_');
    try {
      for (final item in archive) {
        final safeName = _safeArchivePath(item.name);
        if (safeName == null || safeName.isEmpty) continue;
        final target = File('${root.path}/$safeName');
        if (item.isFile) {
          if (!await target.parent.exists()) {
            await target.parent.create(recursive: true);
          }
          await target.writeAsBytes(item.content as List<int>, flush: true);
        } else {
          await Directory(target.path).create(recursive: true);
        }
      }
      final source = await _findManifestDirectory(root);
      if (source == null) throw Exception('压缩包内未找到 plugin.json');
      return importDirectory(source.path);
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  }

  Future<PluginManifest> readManifest(String pluginPath) async {
    final file = File('$pluginPath/plugin.json');
    if (!await file.exists()) throw Exception('插件缺少 plugin.json');
    final data = jsonDecode(await file.readAsString());
    if (data is! Map) throw Exception('plugin.json 顶层必须是对象');
    final manifest = PluginManifest.fromJson(Map<String, dynamic>.from(data));
    final error = manifest.validate();
    if (error != null) throw Exception(error);
    return manifest;
  }

  Future<void> deletePluginDirectory(String pluginId) async {
    final dir = await _pluginDirectory(pluginId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<Map<String, dynamic>> loadPluginSettings(String pluginId) async {
    final file = await _pluginSettingsFile(pluginId);
    if (!await file.exists()) return <String, dynamic>{};
    final data = jsonDecode(await file.readAsString());
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<void> savePluginSettings(
    String pluginId,
    Map<String, dynamic> settings,
  ) async {
    final file = await _pluginSettingsFile(pluginId);
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings),
      flush: true,
    );
  }

  Future<Map<String, dynamic>> loadPluginStorage(String pluginId) async {
    final file = await _pluginStorageFile(pluginId);
    if (!await file.exists()) return <String, dynamic>{};
    final data = jsonDecode(await file.readAsString());
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<void> savePluginStorage(
    String pluginId,
    Map<String, dynamic> storage,
  ) async {
    final file = await _pluginStorageFile(pluginId);
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(storage),
      flush: true,
    );
  }

  InstalledPlugin _installedPlugin(PluginManifest manifest, String path) {
    return InstalledPlugin(
      manifest: manifest,
      path: path,
      enabled: false,
      grantedPermissions: const [],
      enabledFeaturePages: manifest.featurePages
          .map((page) => page.id)
          .toList(),
    );
  }

  Future<Directory?> _findManifestDirectory(Directory root) async {
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && _fileName(entity.path) == 'plugin.json') {
        return entity.parent;
      }
    }
    return null;
  }

  Future<void> _replaceDirectory(Directory source, Directory target) async {
    if (await target.exists()) await target.delete(recursive: true);
    await target.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final relativePath = _relativePath(source.path, entity.path);
      if (relativePath.isEmpty) continue;
      final targetPath = '${target.path}/$relativePath';
      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
      } else if (entity is File) {
        final targetFile = File(targetPath);
        if (!await targetFile.parent.exists()) {
          await targetFile.parent.create(recursive: true);
        }
        await entity.copy(targetFile.path);
      }
    }
  }

  String? _safeArchivePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty && part != '.')
        .toList();
    if (parts.any((part) => part == '..')) return null;
    return parts.join('/');
  }

  Future<File> _stateFile() async {
    final root = await _pluginsRoot();
    return File('${root.path}/$_stateFileName');
  }

  Future<File> _pluginSettingsFile(String pluginId) async {
    final root = await _pluginsRoot();
    return File('${root.path}/settings/$pluginId.json');
  }

  Future<File> _pluginStorageFile(String pluginId) async {
    final root = await _pluginsRoot();
    return File('${root.path}/storage/$pluginId.json');
  }

  Future<Directory> _pluginDirectory(String pluginId) async {
    final root = await _pluginsRoot();
    return Directory('${root.path}/installed/$pluginId');
  }

  Future<Directory> _pluginsRoot() async {
    final dir = await getApplicationSupportDirectory();
    return Directory('${dir.path}/plugins');
  }

  String _relativePath(String root, String path) {
    final normalizedRoot = root
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    final normalizedPath = path.replaceAll('\\', '/');
    if (!normalizedPath.startsWith('$normalizedRoot/')) return '';
    return normalizedPath.substring(normalizedRoot.length + 1);
  }

  String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index == -1 ? normalized : normalized.substring(index + 1);
  }
}
