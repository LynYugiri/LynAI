import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/plugin.dart';
import '../models/plugin_config_schema.dart';
import '../repositories/plugin_repository.dart';

/// 管理插件安装状态、权限授权、功能页开关和插件私有配置。
///
/// Provider 只保存插件元数据和用户授权，不执行 Lua/WebView 代码。具体运行时
/// 通过这里查询启用状态和读写插件私有 storage，确保 UI、工具和 WebView Bridge
/// 共用同一套权限状态。
class PluginProvider extends ChangeNotifier {
  PluginProvider({PluginRepository? repository})
    : _repository = repository ?? PluginRepository();

  final PluginRepository _repository;
  List<InstalledPlugin> _plugins = const [];
  final Map<String, Map<String, dynamic>> _settingsCache = {};
  final Map<String, Map<String, dynamic>> _storageCache = {};
  final Map<String, Map<String, dynamic>> _configCache = {};
  final Map<String, PluginConfigSchema?> _schemaCache = {};
  final Map<String, int> _renderVersions = {};
  bool _loading = false;

  /// 返回当前已安装的插件列表（不可修改）。
  List<InstalledPlugin> get plugins => List.unmodifiable(_plugins);

  /// 插件列表是否正在加载中。
  bool get loading => _loading;

  /// 返回当前已启用插件的数量。
  int get enabledCount => _plugins.where((plugin) => plugin.enabled).length;

  /// 返回插件 WebView 渲染资源版本，插件文件变化时递增。
  int renderVersion(String pluginId) => _renderVersions[pluginId] ?? 0;

  /// 根据插件 ID 查找已安装的插件，未找到则返回 null。
  InstalledPlugin? pluginById(String id) {
    for (final plugin in _plugins) {
      if (plugin.id == id) return plugin;
    }
    return null;
  }

  /// 从仓库加载所有已安装插件并刷新其清单。
  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _plugins = await _repository.loadInstalledPlugins();
      await refreshManifests(save: true);
    } catch (e) {
      debugPrint('加载插件失败: $e');
      _plugins = const [];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 导入解压后的插件目录并安装。
  ///
  /// ZIP import uses this after extraction. The user-facing plugin manager does
  /// not expose directory import, so tests and internal import flows are the only
  /// callers that should use it.
  Future<void> importDirectory(String path) async {
    final plugin = await _repository.importDirectory(path);
    await _upsert(plugin);
  }

  /// 从 ZIP 文件导入并安装插件。
  Future<void> importZip(String path) async {
    final plugin = await _repository.importZip(path);
    await _upsert(plugin);
  }

  /// 刷新所有插件的清单文件，可选是否持久化保存。
  Future<void> refreshManifests({bool save = false}) async {
    final next = <InstalledPlugin>[];
    for (final plugin in _plugins) {
      try {
        final manifest = await _repository.readManifest(plugin.path);
        final granted = plugin.grantedPermissions
            .where(manifest.permissions.contains)
            .toList(growable: false);
        final pageIds = manifest.featurePages.map((page) => page.id).toSet();
        final enabledPages = plugin.enabledFeaturePages
            .where(pageIds.contains)
            .toList(growable: false);
        next.add(
          plugin.copyWith(
            manifest: manifest,
            grantedPermissions: granted,
            enabledFeaturePages: enabledPages,
            loadError: null,
          ),
        );
      } catch (e) {
        next.add(plugin.copyWith(enabled: false, loadError: '$e'));
      }
    }
    _plugins = _sortPlugins(next);
    if (save) await _save();
    notifyListeners();
  }

  /// 启用或禁用指定插件（有加载错误的插件无法启用）。
  Future<void> setEnabled(String id, bool enabled) async {
    final plugin = pluginById(id);
    if (plugin == null) return;
    final shouldEnable = enabled && !plugin.hasError;
    await _replace(id, plugin.copyWith(enabled: shouldEnable));
  }

  /// 设置插件已授权的权限列表，自动过滤非法权限。
  Future<void> setGrantedPermissions(
    String id,
    List<String> permissions,
  ) async {
    final plugin = pluginById(id);
    if (plugin == null) return;
    final allowed = plugin.manifest.permissions.toSet();
    await _replace(
      id,
      plugin.copyWith(
        grantedPermissions: permissions
            .where(allowed.contains)
            .toSet()
            .toList(growable: false),
      ),
    );
  }

  /// 启用或禁用插件的指定功能页。
  Future<void> setFeaturePageEnabled(
    String pluginId,
    String pageId,
    bool enabled,
  ) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) return;
    final pages = plugin.enabledFeaturePages.toSet();
    if (enabled) {
      pages.add(pageId);
    } else {
      pages.remove(pageId);
    }
    await _replace(
      pluginId,
      plugin.copyWith(enabledFeaturePages: pages.toList(growable: false)),
    );
  }

  /// 删除指定插件及其所有缓存数据和文件。
  Future<void> deletePlugin(String id) async {
    _plugins = _plugins.where((plugin) => plugin.id != id).toList();
    _settingsCache.remove(id);
    _storageCache.remove(id);
    _configCache.remove(id);
    _schemaCache.remove(id);
    await _repository.deletePluginDirectory(id);
    await _save();
    notifyListeners();
  }

  /// 加载指定插件的设置数据（带缓存）。
  Future<Map<String, dynamic>> loadSettings(String pluginId) async {
    final cached = _settingsCache[pluginId];
    if (cached != null) return Map<String, dynamic>.from(cached);
    final settings = await _repository.loadPluginSettings(pluginId);
    _settingsCache[pluginId] = settings;
    return Map<String, dynamic>.from(settings);
  }

  /// 更新插件的单个设置项并持久化保存。
  Future<void> updateSetting(String pluginId, String key, Object? value) async {
    final settings = await loadSettings(pluginId);
    if (value == null) {
      settings.remove(key);
    } else {
      settings[key] = value;
    }
    _settingsCache[pluginId] = settings;
    await _repository.savePluginSettings(pluginId, settings);
    notifyListeners();
  }

  /// 加载指定插件的私有存储数据（带缓存）。
  Future<Map<String, dynamic>> loadStorage(String pluginId) async {
    final cached = _storageCache[pluginId];
    if (cached != null) return Map<String, dynamic>.from(cached);
    final storage = await _repository.loadPluginStorage(pluginId);
    _storageCache[pluginId] = storage;
    return Map<String, dynamic>.from(storage);
  }

  /// 读取插件存储中的单个键值。
  Future<Object?> readStorageValue(String pluginId, String key) async {
    final storage = await loadStorage(pluginId);
    return storage[key];
  }

  /// 写入或删除插件存储中的单个键值。
  Future<void> writeStorageValue(
    String pluginId,
    String key,
    Object? value,
  ) async {
    final storage = await loadStorage(pluginId);
    if (value == null) {
      storage.remove(key);
    } else {
      storage[key] = value;
    }
    _storageCache[pluginId] = storage;
    await _repository.savePluginStorage(pluginId, storage);
  }

  /// 列出指定插件目录下的所有可编辑文件。
  Future<List<PluginFileEntry>> listFiles(String pluginId) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) throw Exception('插件不存在: $pluginId');
    return _repository.listPluginFiles(plugin);
  }

  /// 读取插件目录中指定路径的文本文件内容。
  Future<String> readFile(String pluginId, String path) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) throw Exception('插件不存在: $pluginId');
    return _repository.readPluginOverlayTextFile(plugin, path);
  }

  /// 将文本内容写入插件的可编辑文件中。
  Future<void> writeEditableFile(
    String pluginId,
    String path,
    String content,
  ) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) throw Exception('插件不存在: $pluginId');
    await _repository.writePluginTextFile(plugin, path, content);
    if (path == plugin.manifest.config.path) _configCache.remove(pluginId);
    if (path == plugin.manifest.config.schema) _schemaCache.remove(pluginId);
    _bumpRenderVersion(pluginId);
    notifyListeners();
  }

  /// 判断指定路径是否为插件的可编辑文件。
  bool isEditableFile(String pluginId, String path) {
    final plugin = pluginById(pluginId);
    if (plugin == null) return false;
    return _repository.isEditablePluginFile(plugin, path);
  }

  /// 删除插件目录中的指定文件。
  Future<void> deleteFile(String pluginId, String path) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) throw Exception('插件不存在: $pluginId');
    await _repository.deletePluginFile(plugin, path);
    if (path == plugin.manifest.config.path) _configCache.remove(pluginId);
    if (path == plugin.manifest.config.schema) _schemaCache.remove(pluginId);
    _bumpRenderVersion(pluginId);
    notifyListeners();
  }

  /// 重命名插件目录中的指定文件。
  Future<void> renameFile(
    String pluginId,
    String oldPath,
    String newPath,
  ) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) throw Exception('插件不存在: $pluginId');
    await _repository.renamePluginFile(plugin, oldPath, newPath);
    _bumpRenderVersion(pluginId);
    notifyListeners();
  }

  /// 从应用资源包中导入内置插件。
  Future<InstalledPlugin> importBuiltIn(String pluginId) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final prefix = 'assets/plugins/$pluginId/';
    final assets = manifest
        .listAssets()
        .where((path) => path.startsWith(prefix))
        .toList(growable: false);
    if (assets.isEmpty) throw Exception('内置插件资源不存在: $pluginId');

    final tempDir = await Directory.systemTemp.createTemp('lynai_builtin_');
    try {
      final sourceDir = Directory('${tempDir.path}/$pluginId');
      for (final assetPath in assets) {
        final relativePath = assetPath.substring(prefix.length);
        if (relativePath.isEmpty) continue;
        final data = await rootBundle.load(assetPath);
        final file = File('${sourceDir.path}/$relativePath');
        if (!await file.parent.exists()) {
          await file.parent.create(recursive: true);
        }
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      final plugin = await _repository.importDirectory(sourceDir.path);
      await _upsert(plugin);
      return plugin;
    } finally {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    }
  }

  /// 同步检查指定 ID 的插件是否存在。
  bool pluginExistsSync(String pluginId) {
    return _plugins.any((p) => p.id == pluginId);
  }

  /// 获取插件指定相对路径对应的默认文件路径。
  String? defaultPathFor(String pluginId, String relativePath) {
    final plugin = pluginById(pluginId);
    if (plugin == null) return null;
    return _repository.defaultPathFor(plugin, relativePath);
  }

  /// 同步检查插件中指定相对路径的文件是否存在。
  bool pluginFileExistsSync(String pluginId, String relativePath) {
    final plugin = pluginById(pluginId);
    if (plugin == null) return false;
    return _repository.pluginFileExistsSync(plugin.path, relativePath);
  }

  /// 加载插件的自定义配置文件内容（带缓存）。
  Future<Map<String, dynamic>> loadConfig(String pluginId) async {
    final cached = _configCache[pluginId];
    if (cached != null) return Map<String, dynamic>.from(cached);
    final plugin = pluginById(pluginId);
    if (plugin == null) throw Exception('插件不存在: $pluginId');
    if (!await _repository.pluginFileExists(
      plugin.path,
      plugin.manifest.config.path,
    )) {
      _configCache[pluginId] = <String, dynamic>{};
      return <String, dynamic>{};
    }
    final config = await _repository.readPluginJsonFile(
      plugin.path,
      plugin.manifest.config.path,
    );
    _configCache[pluginId] = config;
    return Map<String, dynamic>.from(config);
  }

  /// 加载插件的配置 Schema 定义（带缓存）。
  Future<PluginConfigSchema?> loadConfigSchema(String pluginId) async {
    if (_schemaCache.containsKey(pluginId)) return _schemaCache[pluginId];
    final plugin = pluginById(pluginId);
    if (plugin == null) throw Exception('插件不存在: $pluginId');
    if (!await _repository.pluginFileExists(
      plugin.path,
      plugin.manifest.config.schema,
    )) {
      _schemaCache[pluginId] = null;
      return null;
    }
    final data = await _repository.readPluginJsonFile(
      plugin.path,
      plugin.manifest.config.schema,
    );
    final schema = PluginConfigSchema.fromJson(data);
    final error = schema.validateDefinition();
    if (error != null) throw Exception(error);
    _schemaCache[pluginId] = schema;
    return schema;
  }

  /// 加载插件的配置值并应用 Schema 默认值。
  Future<Map<String, dynamic>> loadConfigValues(String pluginId) async {
    final config = await loadConfig(pluginId);
    final schema = await loadConfigSchema(pluginId);
    return schema?.applyDefaults(config) ?? config;
  }

  /// 保存插件的配置文件并刷新缓存。
  Future<void> saveConfig(String pluginId, Map<String, dynamic> values) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) throw Exception('插件不存在: $pluginId');
    await _repository.writePluginJsonFile(
      plugin,
      plugin.manifest.config.path,
      values,
    );
    _configCache[pluginId] = Map<String, dynamic>.from(values);
    _bumpRenderVersion(pluginId);
    notifyListeners();
  }

  void _bumpRenderVersion(String pluginId) {
    _renderVersions[pluginId] = renderVersion(pluginId) + 1;
  }

  Future<void> _upsert(InstalledPlugin imported) async {
    final current = pluginById(imported.id);
    final plugin = current == null
        ? imported
        : _mergeImported(imported, current);
    final next = [..._plugins.where((item) => item.id != plugin.id), plugin];
    _plugins = _sortPlugins(next);
    await _save();
    notifyListeners();
  }

  Future<void> _replace(String id, InstalledPlugin plugin) async {
    _plugins = _sortPlugins(
      _plugins.map((item) => item.id == id ? plugin : item).toList(),
    );
    await _save();
    notifyListeners();
  }

  Future<void> _save() => _repository.saveInstalledPlugins(_plugins);

  InstalledPlugin _mergeImported(
    InstalledPlugin imported,
    InstalledPlugin current,
  ) {
    final nextPageIds = imported.manifest.featurePages
        .map((page) => page.id)
        .toSet();
    final retainedEnabledPages = current.enabledFeaturePages
        .where(nextPageIds.contains)
        .toSet();
    final previousPageIds = current.manifest.featurePages
        .map((page) => page.id)
        .toSet();
    retainedEnabledPages.addAll(nextPageIds.difference(previousPageIds));
    return imported.copyWith(
      enabled: current.enabled,
      grantedPermissions: current.grantedPermissions
          .where(imported.manifest.permissions.contains)
          .toList(growable: false),
      enabledFeaturePages: retainedEnabledPages.toList(growable: false),
    );
  }

  List<InstalledPlugin> _sortPlugins(List<InstalledPlugin> plugins) {
    return plugins.toList()
      ..sort((a, b) => a.manifest.name.compareTo(b.manifest.name));
  }
}
