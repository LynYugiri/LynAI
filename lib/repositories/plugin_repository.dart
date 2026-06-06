import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/plugin.dart'
    show InstalledPlugin, PluginFileEntry, PluginManifest, fileTypeFromPath;
import '../utils/plugin_path_utils.dart';

/// 插件文件系统仓储。
///
/// 负责把用户导入的 ZIP 插件复制到应用私有目录，并维护安装状态、插件设置和
/// 插件私有 storage。仓储层不解释权限，也不执行插件代码，只处理可信的本地
/// 文件布局和 JSON 持久化。
class PluginRepository {
  static const _stateFileName = 'installed_plugins.json';
  static const maxTextFileBytes = 512 * 1024;

  static const builtInPluginIds = ['status-dashboard', 'weather-query'];
  static const builtInPluginFiles = {
    'status-dashboard': [
      'plugin.json',
      'icon.svg',
      'defaults/main.lua',
      'defaults/status.html',
      'defaults/status.css',
    ],
    'weather-query': ['plugin.json', 'main.lua'],
  };

  final Directory? _rootOverride;

  PluginRepository({Directory? rootOverride}) : _rootOverride = rootOverride;

  /// 加载已安装插件列表，从 JSON 状态文件中读取。
  Future<List<InstalledPlugin>> loadInstalledPlugins() async {
    final file = await _stateFile();
    if (!await file.exists()) return const [];
    final String raw;
    try {
      raw = await file.readAsString();
    } catch (_) {
      return const [];
    }
    final data = jsonDecode(raw);
    final items = data is Map ? data['plugins'] as List? : null;
    return (items ?? const [])
        .whereType<Map>()
        .map(
          (item) => InstalledPlugin.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  /// 保存已安装插件列表到 JSON 状态文件。
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

  /// Installs a plugin from an already-unpacked directory.
  ///
  /// This is kept as an internal installation primitive for ZIP extraction and
  /// tests; the UI intentionally exposes ZIP import only.
  Future<InstalledPlugin> importDirectory(String sourcePath) async {
    final source = Directory(sourcePath);
    if (!await source.exists()) throw Exception('插件目录不存在');
    final manifest = await readManifest(source.path);
    final target = await _pluginDirectory(manifest.id);
    await _replaceDirectory(source, target);
    return _installedPlugin(manifest, target.path);
  }

  /// 用当前插件目录创建一个独立快照插件。
  Future<InstalledPlugin> createSnapshot(
    InstalledPlugin source,
    String snapshotId,
    String snapshotName,
    int snapshotIndex,
  ) async {
    final target = await _pluginDirectory(snapshotId);
    if (await target.exists()) throw Exception('插件已存在: $snapshotId');
    await _replaceDirectory(Directory(source.path), target);
    final manifest = source.manifest.copyWith(
      id: snapshotId,
      name: snapshotName,
      lynai: {
        ...source.manifest.lynai,
        'snapshotOf': source.id,
        'snapshotIndex': snapshotIndex,
      },
    );
    await _writeManifest(target.path, manifest);
    return _installedPlugin(manifest, target.path);
  }

  /// 修改快照插件的 id/name，并在 id 改变时同步重命名安装目录。
  Future<InstalledPlugin> updateSnapshotIdentity(
    InstalledPlugin plugin,
    String nextId,
    String nextName,
  ) async {
    if (!plugin.isSnapshot) throw Exception('只有快照插件可以修改 id/name');
    final id = nextId.trim();
    final name = nextName.trim();
    if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(id)) {
      throw Exception('插件 id 只能包含字母、数字、下划线、点和横线');
    }
    if (name.isEmpty) throw Exception('插件名称不能为空');
    final target = await _pluginDirectory(id);
    var path = plugin.path;
    if (id != plugin.id) {
      if (await target.exists()) throw Exception('插件已存在: $id');
      await Directory(plugin.path).rename(target.path);
      await renamePluginDataFiles(plugin.id, id);
      path = target.path;
    }
    final manifest = plugin.manifest.copyWith(id: id, name: name);
    await _writeManifest(path, manifest);
    return plugin.copyWith(manifest: manifest, path: path);
  }

  /// 用快照目录内容覆盖来源插件目录，但保留来源插件的 id/name。
  Future<InstalledPlugin> restoreSnapshotToSource(
    InstalledPlugin snapshot,
    InstalledPlugin source,
  ) async {
    if (!snapshot.isSnapshot || snapshot.manifest.snapshotOf != source.id) {
      throw Exception('快照来源不匹配');
    }
    final sourceManifest = source.manifest;
    await _replaceDirectory(Directory(snapshot.path), Directory(source.path));
    await _writeManifest(
      source.path,
      snapshot.manifest.copyWith(
        id: sourceManifest.id,
        name: sourceManifest.name,
        lynai: _withoutSnapshotMeta(snapshot.manifest.lynai),
      ),
    );
    return source.copyWith(
      manifest: await readManifest(source.path),
      path: source.path,
    );
  }

  /// 同步一个已解包的内置插件源码目录到安装目录。
  ///
  /// 与 [importDirectory] 不同，这个方法不会清空目标目录。它只覆盖源码目录中
  /// 明确提供的文件，用于升级内置插件的 plugin.json、defaults/ 和入口文件，
  /// 同时保留用户自定义的可编辑文件与配置。
  Future<InstalledPlugin> syncDirectory(String sourcePath) async {
    final source = Directory(sourcePath);
    if (!await source.exists()) throw Exception('插件目录不存在');
    final manifest = await readManifest(source.path);
    final target = await _pluginDirectory(manifest.id);
    if (!await target.exists()) {
      await _replaceDirectory(source, target);
    } else {
      await _clearSourceDirectories(source, target);
      await _copyDirectoryFiles(source, target);
    }
    return _installedPlugin(manifest, target.path);
  }

  /// 从 ZIP 压缩包导入并安装插件。
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
      return await importDirectory(source.path);
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  }

  /// 读取并校验插件目录中的 plugin.json 清单文件。
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

  /// 删除指定插件的安装目录。
  Future<void> deletePluginDirectory(String pluginId) async {
    final dir = await _pluginDirectory(pluginId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// 返回插件在当前设备上的安装目录。
  Future<Directory> pluginDirectory(String pluginId) =>
      _pluginDirectory(pluginId);

  /// 用备份文件完整恢复指定插件目录。
  Future<void> restorePluginDirectory(
    String pluginId,
    Map<String, List<int>> files,
  ) async {
    final target = await _pluginDirectory(pluginId);
    if (await target.exists()) await target.delete(recursive: true);
    await target.create(recursive: true);
    for (final entry in files.entries) {
      final safePath = safePluginFilePath(target.path, entry.key);
      if (safePath == null) throw Exception('插件文件路径不安全: ${entry.key}');
      final file = File(safePath);
      await _ensureInsideRoot(
        target.path,
        file.parent.path,
        allowMissingLeaf: true,
      );
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsBytes(entry.value, flush: true);
    }
  }

  /// 加载插件的用户设置 JSON 数据。
  Future<Map<String, dynamic>> loadPluginSettings(String pluginId) async {
    final file = await _pluginSettingsFile(pluginId);
    if (!await file.exists()) return <String, dynamic>{};
    final data = jsonDecode(await file.readAsString());
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// 保存插件的用户设置 JSON 数据。
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

  /// 加载插件的私有存储 JSON 数据。
  Future<Map<String, dynamic>> loadPluginStorage(String pluginId) async {
    final file = await _pluginStorageFile(pluginId);
    if (!await file.exists()) return <String, dynamic>{};
    final data = jsonDecode(await file.readAsString());
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// 列出插件目录内所有文件及目录条目，跳过 defaults/ 目录。
  ///
  /// 对有 defaultPath 的可编辑文件，若根目录下不存在，则生成虚拟条目（isDefault:true），
  /// 代表出厂模板的透明回退。
  Future<List<PluginFileEntry>> listPluginFiles(
    InstalledPlugin plugin, {
    int maxDepth = 8,
  }) async {
    final root = Directory(plugin.path);
    if (!await root.exists()) throw Exception('插件目录不存在');
    final entries = <PluginFileEntry>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Link) continue;
      final relativePath = _relativePath(root.path, entity.path);
      if (relativePath.isEmpty) continue;
      if (relativePath.split('/').length > maxDepth) continue;
      if (_isDefaultPath(relativePath)) continue;
      if (_isHiddenCorePath(plugin, relativePath)) continue;
      final stat = await entity.stat();
      final isDirectory = entity is Directory;
      final isEditable =
          !isDirectory && _isEditablePluginFile(plugin, relativePath);
      final hasDef = !isDirectory && _hasDefaultPath(plugin, relativePath);
      entries.add(
        PluginFileEntry(
          path: relativePath,
          size: isDirectory ? 0 : stat.size,
          isDirectory: isDirectory,
          isEditable: isEditable,
          hasDefault: hasDef,
          isDefault: false,
          type: fileTypeFromPath(relativePath),
        ),
      );
    }
    for (final file in plugin.manifest.editableFiles) {
      if (file.defaultPath == null || file.defaultPath!.isEmpty) continue;
      if (_isHiddenCorePath(plugin, file.path)) continue;
      if (!entryExists(file.path, entries)) {
        entries.add(
          PluginFileEntry(
            path: file.path,
            size: 0,
            isDirectory: false,
            isEditable: true,
            hasDefault: true,
            isDefault: true,
            type: fileTypeFromPath(file.path),
          ),
        );
      }
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      if (a.isDefault != b.isDefault) return a.isDefault ? 1 : -1;
      return a.path.compareTo(b.path);
    });
    return entries;
  }

  /// 读取插件文本文件（仅限根目录下的真实文件）。
  ///
  /// 注意：不会回退读取 defaults/ 出厂模板。若文件不存在，直接抛出异常。
  /// 出厂模板仅由系统内部模块（Lua 运行时、功能页渲染）自行按需加载。
  Future<String> readPluginTextFile(
    String pluginPath,
    String relativePath, {
    int maxBytes = maxTextFileBytes,
  }) async {
    final safePath = safePluginFilePath(pluginPath, relativePath);
    if (safePath == null) throw Exception('插件文件路径不安全: $relativePath');
    final file = File(safePath);
    if (!await file.exists()) throw Exception('插件文件不存在: $relativePath');
    final stat = await file.stat();
    if (stat.size > maxBytes) throw Exception('文件过大，无法预览');
    return file.readAsString();
  }

  /// 读取插件文本文件的合并视图：优先根目录自定义文件，否则回退 defaults/ 模板。
  Future<String> readPluginOverlayTextFile(
    InstalledPlugin plugin,
    String relativePath, {
    int maxBytes = maxTextFileBytes,
  }) async {
    final normalized = _normalizeRelativePath(relativePath);
    if (normalized == null) throw Exception('插件文件路径不安全: $relativePath');
    if (_isProtectedPluginPath(plugin, normalized)) {
      throw Exception('插件受保护文件不可读取: $relativePath');
    }
    final file = File(safePluginFilePath(plugin.path, normalized)!);
    if (await file.exists()) {
      await _ensureInsideRoot(plugin.path, file.path);
      final stat = await file.stat();
      if (stat.size > maxBytes) throw Exception('文件过大，无法预览');
      return file.readAsString();
    }
    final defaultPath = defaultPathFor(plugin, normalized);
    if (defaultPath == null) throw Exception('插件文件不存在: $relativePath');
    final defaultSafePath = safePluginFilePath(plugin.path, defaultPath);
    if (defaultSafePath == null) throw Exception('插件文件路径不安全: $relativePath');
    final defaultFile = File(defaultSafePath);
    if (!await defaultFile.exists()) throw Exception('插件文件不存在: $relativePath');
    await _ensureInsideRoot(plugin.path, defaultFile.path);
    final stat = await defaultFile.stat();
    if (stat.size > maxBytes) throw Exception('文件过大，无法预览');
    return defaultFile.readAsString();
  }

  /// Returns whether a plugin-relative file exists without allowing path escape.
  Future<bool> pluginFileExists(String pluginPath, String relativePath) async {
    final safePath = safePluginFilePath(pluginPath, relativePath);
    if (safePath == null) throw Exception('插件文件路径不安全: $relativePath');
    final file = File(safePath);
    if (!await file.exists()) return false;
    await _ensureInsideRoot(pluginPath, file.path);
    return true;
  }

  /// Writes a plugin file only if the manifest or files:write permission
  /// declares it editable. Protected paths (defaults/、plugin.json) are
  /// always rejected.
  Future<void> writePluginTextFile(
    InstalledPlugin plugin,
    String relativePath,
    String content,
  ) async {
    if (!_isEditablePluginFile(plugin, relativePath)) {
      throw Exception('插件文件不可编辑: $relativePath');
    }
    if (_isProtectedPluginPath(plugin, relativePath)) {
      throw Exception('插件受保护文件不可覆盖: $relativePath');
    }
    final file = await _safeWritablePluginFile(plugin.path, relativePath);
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }

  /// 读取插件目录内的 JSON 文件并解析为 Map。
  Future<Map<String, dynamic>> readPluginJsonFile(
    String pluginPath,
    String relativePath,
  ) async {
    final text = await readPluginTextFile(pluginPath, relativePath);
    final data = jsonDecode(text);
    if (data is! Map) throw Exception('$relativePath 顶层必须是对象');
    return Map<String, dynamic>.from(data);
  }

  /// 将字节内容写入插件文件，适合上传图片、字体等非文本资源。
  Future<void> writePluginFileBytes(
    InstalledPlugin plugin,
    String relativePath,
    List<int> bytes,
  ) async {
    if (!_isEditablePluginFile(plugin, relativePath)) {
      throw Exception('插件文件不可编辑: $relativePath');
    }
    if (_isProtectedPluginPath(plugin, relativePath)) {
      throw Exception('插件受保护文件不可覆盖: $relativePath');
    }
    final file = await _safeWritablePluginFile(plugin.path, relativePath);
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  /// 将 Map 数据以 JSON 格式写入插件文件。
  Future<void> writePluginJsonFile(
    InstalledPlugin plugin,
    String relativePath,
    Map<String, dynamic> value,
  ) async {
    if (!_isConfigPath(plugin, relativePath)) {
      await writePluginTextFile(
        plugin,
        relativePath,
        const JsonEncoder.withIndent('  ').convert(value),
      );
      return;
    }
    if (_isProtectedPluginPath(plugin, relativePath, allowConfig: true)) {
      throw Exception('插件受保护文件不可覆盖: $relativePath');
    }
    final file = await _safeWritablePluginFile(plugin.path, relativePath);
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
  }

  /// 删除插件目录内的可编辑文件。
  Future<void> deletePluginFile(
    InstalledPlugin plugin,
    String relativePath,
  ) async {
    if (!_isEditablePluginFile(plugin, relativePath)) {
      throw Exception('插件文件不可删除: $relativePath');
    }
    if (_isProtectedPluginPath(plugin, relativePath)) {
      throw Exception('插件受保护文件不可删除: $relativePath');
    }
    final file = await _safeExistingPluginFile(plugin.path, relativePath);
    await file.delete();
  }

  /// 重命名插件目录内的可编辑文件。
  Future<void> renamePluginFile(
    InstalledPlugin plugin,
    String oldPath,
    String newPath,
  ) async {
    if (!_isEditablePluginFile(plugin, oldPath)) {
      throw Exception('插件文件不可重命名: $oldPath');
    }
    if (_isProtectedPluginPath(plugin, oldPath) ||
        _isProtectedPluginPath(plugin, newPath)) {
      throw Exception('插件受保护文件不可重命名');
    }
    final oldFile = await _safeExistingPluginFile(plugin.path, oldPath);
    final newSafe = safePluginFilePath(plugin.path, newPath);
    if (newSafe == null) throw Exception('目标路径不安全: $newPath');
    await _ensureInsideRoot(
      plugin.path,
      File(newSafe).parent.path,
      allowMissingLeaf: true,
    );
    if (!await File(newSafe).parent.exists()) {
      await File(newSafe).parent.create(recursive: true);
    }
    if (await File(newSafe).exists()) throw Exception('目标文件已存在: $newPath');
    await oldFile.rename(newSafe);
  }

  /// 删除插件中所有用户自定义文件，使其回退到出厂状态。
  Future<void> resetPluginFilesToDefaults(InstalledPlugin plugin) async {
    final root = Directory(plugin.path);
    if (!await root.exists()) throw Exception('插件目录不存在');
    final emptyDirs = <Directory>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      final relativePath = _relativePath(root.path, entity.path);
      if (relativePath.isEmpty) continue;
      if (entity is Directory) {
        if (!_isDefaultPath(relativePath)) emptyDirs.add(entity);
        continue;
      }
      if (entity is! File) continue;
      if (_isProtectedPluginPath(plugin, relativePath)) continue;
      await _ensureInsideRoot(plugin.path, entity.path);
      await entity.delete();
    }
    emptyDirs.sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final dir in emptyDirs) {
      if (await dir.exists() && await dir.list(followLinks: false).isEmpty) {
        await dir.delete();
      }
    }
  }

  /// 导出当前插件安装目录为 ZIP 文件。
  Future<void> exportPluginZip(
    InstalledPlugin plugin,
    String targetPath,
  ) async {
    final archive = Archive();
    final root = Directory(plugin.path);
    if (!await root.exists()) throw Exception('插件目录不存在');
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relativePath = _relativePath(root.path, entity.path);
      if (relativePath.isEmpty) continue;
      final bytes = await entity.readAsBytes();
      archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
    }
    final bytes = ZipEncoder().encode(archive);
    final file = File(targetPath);
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  /// 保存插件的私有存储 JSON 数据。
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

  /// 修改插件 ID 时迁移与 ID 绑定的设置和私有存储文件。
  Future<void> renamePluginDataFiles(String oldId, String newId) async {
    if (oldId == newId) return;
    await _renameDataFile(
      await _pluginSettingsFile(oldId),
      await _pluginSettingsFile(newId),
    );
    await _renameDataFile(
      await _pluginStorageFile(oldId),
      await _pluginStorageFile(newId),
    );
  }

  /// 判断插件相对路径对应的文件是否可编辑。
  bool isEditablePluginFile(InstalledPlugin plugin, String relativePath) {
    return _isEditablePluginFile(plugin, relativePath);
  }

  /// 获取可编辑文件对应的默认模板路径。
  String? defaultPathFor(InstalledPlugin plugin, String relativePath) {
    final normalized = _normalizeRelativePath(relativePath);
    if (normalized == null) return null;
    for (final file in plugin.manifest.editableFiles) {
      final fileNorm = _normalizeRelativePath(file.path);
      if (fileNorm == normalized && file.defaultPath != null) {
        return file.defaultPath!;
      }
    }
    return null;
  }

  /// 同步判断插件相对路径对应的文件是否存在。
  bool pluginFileExistsSync(String pluginPath, String relativePath) {
    final safePath = safePluginFilePath(pluginPath, relativePath);
    if (safePath == null) return false;
    return File(safePath).existsSync();
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
      enabledTools: manifest.tools.map((tool) => tool.name).toList(),
      enabledFunctions: manifest.functions
          .map((function) => function.name)
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
    await _copyDirectoryFiles(source, target);
  }

  Future<void> _writeManifest(
    String pluginPath,
    PluginManifest manifest,
  ) async {
    final file = File('$pluginPath/plugin.json');
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      flush: true,
    );
  }

  Future<void> _renameDataFile(File source, File target) async {
    if (!await source.exists()) return;
    if (!await target.parent.exists()) {
      await target.parent.create(recursive: true);
    }
    if (await target.exists()) await target.delete();
    await source.rename(target.path);
  }

  Map<String, dynamic> _withoutSnapshotMeta(Map<String, dynamic> lynai) {
    final next = Map<String, dynamic>.from(lynai);
    next.remove('snapshotOf');
    next.remove('snapshotIndex');
    return next;
  }

  Future<void> _copyDirectoryFiles(Directory source, Directory target) async {
    if (!await target.exists()) await target.create(recursive: true);
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

  Future<void> _clearSourceDirectories(
    Directory source,
    Directory target,
  ) async {
    await for (final entity in source.list(
      recursive: false,
      followLinks: false,
    )) {
      if (entity is! Directory) continue;
      final relativePath = _relativePath(source.path, entity.path);
      if (relativePath.isEmpty) continue;
      final targetPath = safePluginFilePath(target.path, relativePath);
      if (targetPath == null) continue;
      final targetDir = Directory(targetPath);
      if (await targetDir.exists()) await targetDir.delete(recursive: true);
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
    final override = _rootOverride;
    if (override != null) return override;
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

  Future<File> _safeExistingPluginFile(
    String pluginPath,
    String relativePath,
  ) async {
    final safePath = safePluginFilePath(pluginPath, relativePath);
    if (safePath == null) throw Exception('插件文件路径不安全: $relativePath');
    final file = File(safePath);
    if (!await file.exists()) throw Exception('插件文件不存在: $relativePath');
    await _ensureInsideRoot(pluginPath, file.path);
    return file;
  }

  Future<File> _safeWritablePluginFile(
    String pluginPath,
    String relativePath,
  ) async {
    final safePath = safePluginFilePath(pluginPath, relativePath);
    if (safePath == null) throw Exception('插件文件路径不安全: $relativePath');
    final file = File(safePath);
    await _ensureInsideRoot(
      pluginPath,
      file.parent.path,
      allowMissingLeaf: true,
    );
    return file;
  }

  Future<void> _ensureInsideRoot(
    String pluginPath,
    String path, {
    bool allowMissingLeaf = false,
  }) async {
    final root = await Directory(pluginPath).resolveSymbolicLinks();
    final target = allowMissingLeaf
        ? await (await _nearestExistingDirectory(path)).resolveSymbolicLinks()
        : await File(path).resolveSymbolicLinks();
    final normalizedRoot = root
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    final normalizedTarget = target.replaceAll('\\', '/');
    if (normalizedTarget != normalizedRoot &&
        !normalizedTarget.startsWith('$normalizedRoot/')) {
      throw Exception('插件文件越界');
    }
  }

  Future<Directory> _nearestExistingDirectory(String path) async {
    var directory = Directory(path);
    while (!await directory.exists()) {
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
    return directory;
  }

  bool _isProtectedPath(String relativePath) {
    final normalized = _normalizeRelativePath(relativePath);
    if (normalized == null) return true;
    if (normalized == 'plugin.json') return true;
    if (normalized.startsWith('defaults/')) return true;
    return false;
  }

  bool _isProtectedPluginPath(
    InstalledPlugin plugin,
    String relativePath, {
    bool allowConfig = false,
  }) {
    final normalized = _normalizeRelativePath(relativePath);
    if (normalized == null) return true;
    if (_isProtectedPath(normalized)) return true;
    if (!allowConfig && _isConfigPath(plugin, normalized)) return true;
    return normalized == _normalizeRelativePath(plugin.manifest.entry);
  }

  bool _isHiddenCorePath(InstalledPlugin plugin, String relativePath) {
    final normalized = _normalizeRelativePath(relativePath);
    if (normalized == null) return true;
    if (normalized == 'plugin.json') return true;
    if (_isConfigPath(plugin, normalized)) return true;
    return normalized == _normalizeRelativePath(plugin.manifest.entry);
  }

  bool _isConfigPath(InstalledPlugin plugin, String relativePath) {
    final normalized = _normalizeRelativePath(relativePath);
    if (normalized == null) return false;
    return normalized == _normalizeRelativePath(plugin.manifest.config.path) ||
        normalized == _normalizeRelativePath(plugin.manifest.config.schema);
  }

  bool _isDefaultPath(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    return normalized.startsWith('defaults/');
  }

  /// 判断指定路径对应的非默认文件条目是否已存在于列表中。
  bool entryExists(String path, List<PluginFileEntry> entries) {
    final normalized = _normalizeRelativePath(path);
    if (normalized == null) return false;
    return entries.any(
      (e) => !e.isDefault && _normalizeRelativePath(e.path) == normalized,
    );
  }

  bool _isEditablePluginFile(InstalledPlugin plugin, String relativePath) {
    final normalized = _normalizeRelativePath(relativePath);
    if (normalized == null) return false;
    if (_isProtectedPath(normalized)) return false;
    if (normalized == _normalizeRelativePath(plugin.manifest.entry)) {
      return false;
    }
    if (_isConfigPath(plugin, normalized)) return false;
    if (plugin.manifest.editableFiles.any(
      (file) => normalized == _normalizeRelativePath(file.path),
    )) {
      return true;
    }
    return plugin.grantedPermissions.contains('files:write');
  }

  bool _hasDefaultPath(InstalledPlugin plugin, String relativePath) {
    final normalized = _normalizeRelativePath(relativePath);
    if (normalized == null) return false;
    return plugin.manifest.editableFiles.any(
      (file) =>
          file.defaultPath != null &&
          file.defaultPath!.isNotEmpty &&
          normalized == _normalizeRelativePath(file.path),
    );
  }

  String? _normalizeRelativePath(String path) {
    final safe = safePluginFilePath('/tmp/plugin_root', path);
    if (safe == null) return null;
    return _relativePath('/tmp/plugin_root', safe);
  }
}
