import 'package:flutter/foundation.dart';

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
  bool _loading = false;

  List<InstalledPlugin> get plugins => List.unmodifiable(_plugins);
  bool get loading => _loading;
  int get enabledCount => _plugins.where((plugin) => plugin.enabled).length;

  InstalledPlugin? pluginById(String id) {
    for (final plugin in _plugins) {
      if (plugin.id == id) return plugin;
    }
    return null;
  }

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

  /// Installs an unpacked plugin directory.
  ///
  /// ZIP import uses this after extraction. The user-facing plugin manager does
  /// not expose directory import, so tests and internal import flows are the only
  /// callers that should use it.
  Future<void> importDirectory(String path) async {
    final plugin = await _repository.importDirectory(path);
    await _upsert(plugin);
  }

  Future<void> importZip(String path) async {
    final plugin = await _repository.importZip(path);
    await _upsert(plugin);
  }

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

  Future<void> setEnabled(String id, bool enabled) async {
    final plugin = pluginById(id);
    if (plugin == null) return;
    final shouldEnable = enabled && !plugin.hasError;
    await _replace(id, plugin.copyWith(enabled: shouldEnable));
  }

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

  Future<Map<String, dynamic>> loadSettings(String pluginId) async {
    final cached = _settingsCache[pluginId];
    if (cached != null) return Map<String, dynamic>.from(cached);
    final settings = await _repository.loadPluginSettings(pluginId);
    _settingsCache[pluginId] = settings;
    return Map<String, dynamic>.from(settings);
  }

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

  Future<Map<String, dynamic>> loadStorage(String pluginId) async {
    final cached = _storageCache[pluginId];
    if (cached != null) return Map<String, dynamic>.from(cached);
    final storage = await _repository.loadPluginStorage(pluginId);
    _storageCache[pluginId] = storage;
    return Map<String, dynamic>.from(storage);
  }

  Future<Object?> readStorageValue(String pluginId, String key) async {
    final storage = await loadStorage(pluginId);
    return storage[key];
  }

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

  Future<List<PluginFileEntry>> listFiles(String pluginId) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) throw Exception('插件不存在: $pluginId');
    return _repository.listPluginFiles(plugin);
  }

  Future<String> readFile(String pluginId, String path) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) throw Exception('插件不存在: $pluginId');
    return _repository.readPluginTextFile(plugin.path, path);
  }

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
    notifyListeners();
  }

  bool isEditableFile(String pluginId, String path) {
    final plugin = pluginById(pluginId);
    if (plugin == null) return false;
    return _repository.isEditablePluginFile(plugin, path);
  }

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

  Future<Map<String, dynamic>> loadConfigValues(String pluginId) async {
    final config = await loadConfig(pluginId);
    final schema = await loadConfigSchema(pluginId);
    return schema?.applyDefaults(config) ?? config;
  }

  Future<void> saveConfig(String pluginId, Map<String, dynamic> values) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) throw Exception('插件不存在: $pluginId');
    await _repository.writePluginJsonFile(
      plugin,
      plugin.manifest.config.path,
      values,
    );
    _configCache[pluginId] = Map<String, dynamic>.from(values);
    notifyListeners();
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
