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

  /// 从 ZIP 字节内容导入并安装插件。
  Future<void> importZipBytes(List<int> bytes) async {
    final plugin = await _repository.importZipBytes(bytes);
    await _upsert(plugin);
  }

  /// 安装应用内置可信插件，并默认启用和授予其声明的全部权限。
  Future<InstalledPlugin> installTrustedBuiltIn(String pluginId) async {
    final plugin = await importBuiltIn(pluginId);
    return trustInstalledBuiltIn(plugin.id);
  }

  /// 将已安装的内置可信插件启用，并授予其声明的全部权限。
  Future<InstalledPlugin> trustInstalledBuiltIn(String pluginId) async {
    var plugin = pluginById(pluginId);
    if (plugin == null) throw Exception('插件不存在: $pluginId');
    await setEnabled(plugin.id, true);
    plugin = pluginById(pluginId);
    if (plugin == null) throw Exception('插件不存在: $pluginId');
    await setGrantedPermissions(
      plugin.id,
      plugin.manifest.permissions.toList(),
    );
    return pluginById(pluginId) ?? plugin;
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
        final previousToolIds = plugin.manifest.tools
            .map((tool) => tool.name)
            .toSet();
        final toolIds = manifest.tools.map((tool) => tool.name).toSet();
        final enabledTools = plugin.enabledTools
            .where(toolIds.contains)
            .toSet();
        enabledTools.addAll(toolIds.difference(previousToolIds));
        final previousFunctionIds = plugin.manifest.functions
            .map((function) => function.name)
            .toSet();
        final functionIds = manifest.functions
            .map((function) => function.name)
            .toSet();
        final enabledFunctions = plugin.enabledFunctions
            .where(functionIds.contains)
            .toSet();
        enabledFunctions.addAll(functionIds.difference(previousFunctionIds));
        final previousSkillIds = plugin.manifest.skills
            .map((skill) => skill.name)
            .toSet();
        final skillIds = manifest.skills.map((skill) => skill.name).toSet();
        final enabledSkills = plugin.enabledSkills
            .where(skillIds.contains)
            .toSet();
        enabledSkills.addAll(skillIds.difference(previousSkillIds));
        next.add(
          plugin.copyWith(
            manifest: manifest,
            grantedPermissions: granted,
            enabledFeaturePages: enabledPages,
            enabledTools: enabledTools.toList(growable: false),
            enabledFunctions: enabledFunctions.toList(growable: false),
            enabledSkills: enabledSkills.toList(growable: false),
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
    if (shouldEnable) _ensureNoEnabledPluginApiConflict(plugin);
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

  /// 启用或禁用插件的指定模型工具。
  Future<void> setToolEnabled(
    String pluginId,
    String toolName,
    bool enabled,
  ) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) return;
    final tools = plugin.enabledTools.toSet();
    if (enabled) {
      tools.add(toolName);
    } else {
      tools.remove(toolName);
    }
    final next = plugin.copyWith(enabledTools: tools.toList(growable: false));
    if (plugin.enabled) _ensureNoEnabledPluginApiConflict(next);
    await _replace(pluginId, next);
  }

  /// 启用或禁用插件的指定内部函数。
  Future<void> setFunctionEnabled(
    String pluginId,
    String functionName,
    bool enabled,
  ) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) return;
    final functions = plugin.enabledFunctions.toSet();
    if (enabled) {
      functions.add(functionName);
    } else {
      functions.remove(functionName);
    }
    final next = plugin.copyWith(
      enabledFunctions: functions.toList(growable: false),
    );
    if (plugin.enabled) _ensureNoEnabledPluginApiConflict(next);
    await _replace(pluginId, next);
  }

  /// 判断插件函数当前是否允许通过 plugin.func 调用。
  bool isFunctionEnabled(String pluginId, String functionName) {
    final plugin = pluginById(pluginId);
    if (plugin == null) return false;
    return plugin.enabledFunctions.contains(functionName);
  }

  /// 启用或禁用插件的指定 Skill。
  Future<void> setSkillEnabled(
    String pluginId,
    String skillName,
    bool enabled,
  ) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) return;
    final skills = plugin.enabledSkills.toSet();
    if (enabled) {
      skills.add(skillName);
    } else {
      skills.remove(skillName);
    }
    await _replace(
      pluginId,
      plugin.copyWith(enabledSkills: skills.toList(growable: false)),
    );
  }

  /// 判断插件 Skill 当前是否启用。
  bool isSkillEnabled(String pluginId, String skillName) {
    final plugin = pluginById(pluginId);
    if (plugin == null) return false;
    return plugin.enabledSkills.contains(skillName);
  }

  /// 修改插件在 UI 中显示的名称，不改写 plugin.json。
  Future<void> renameDisplayName(String pluginId, String name) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) throw Exception('插件不存在: $pluginId');
    final value = name.trim();
    await _replace(
      pluginId,
      plugin.copyWith(displayNameOverride: value.isEmpty ? null : value),
    );
  }

  /// 为当前插件创建一个默认禁用的独立快照，复制授权和功能页状态。
  Future<InstalledPlugin> createSnapshot(String pluginId) async {
    final source = pluginById(pluginId);
    if (source == null) throw Exception('插件不存在: $pluginId');
    final index = _nextSnapshotIndex(source.id);
    final snapshotId = '${source.id}-snapshot-$index';
    final snapshotName = '${source.displayName}-快照 #$index';
    final imported = await _repository.createSnapshot(
      source,
      snapshotId,
      snapshotName,
      index,
    );
    final snapshot = imported.copyWith(
      enabled: false,
      grantedPermissions: source.grantedPermissions.toList(growable: false),
      enabledFeaturePages: source.enabledFeaturePages.toList(growable: false),
      enabledTools: source.enabledTools.toList(growable: false),
      enabledFunctions: source.enabledFunctions.toList(growable: false),
      enabledSkills: source.enabledSkills.toList(growable: false),
    );
    _plugins = _sortPlugins([..._plugins, snapshot]);
    await _save();
    notifyListeners();
    return snapshot;
  }

  /// 修改快照插件自身 id/name。普通插件不允许执行此操作。
  Future<InstalledPlugin> updateSnapshotIdentity(
    String pluginId,
    String newId,
    String newName,
  ) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) throw Exception('插件不存在: $pluginId');
    if (newId != pluginId && pluginById(newId) != null) {
      throw Exception('插件已存在: $newId');
    }
    final updated = await _repository.updateSnapshotIdentity(
      plugin,
      newId,
      newName,
    );
    _renameCaches(pluginId, updated.id);
    _plugins = _sortPlugins(
      _plugins.map((item) => item.id == pluginId ? updated : item).toList(),
    );
    await _save();
    notifyListeners();
    return updated;
  }

  /// 用快照文件覆盖来源插件文件，保留来源插件当前名称、启用状态和授权状态。
  Future<InstalledPlugin> restoreSnapshotToSource(String snapshotId) async {
    final snapshot = pluginById(snapshotId);
    if (snapshot == null) throw Exception('插件不存在: $snapshotId');
    final sourceId = snapshot.manifest.snapshotOf;
    if (sourceId == null) throw Exception('插件不是快照: $snapshotId');
    final source = pluginById(sourceId);
    if (source == null) throw Exception('快照来源插件不存在: $sourceId');
    final restored = await _repository.restoreSnapshotToSource(
      snapshot,
      source,
    );
    final keptState = source.copyWith(manifest: restored.manifest);
    _configCache.remove(source.id);
    _schemaCache.remove(source.id);
    _bumpRenderVersion(source.id);
    await _replace(source.id, keptState);
    return keptState;
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

  /// 卸载指定插件。
  ///
  /// 语义别名，等价于 [deletePlugin]。供插件市场页使用，表达「从市场视角
  /// 移除已安装插件」的意图，与市场页的「安装」操作对称。
  Future<void> uninstall(String id) => deletePlugin(id);

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

  /// 将字节内容写入插件文件，适合上传二进制资源。
  Future<void> writeFileBytes(
    String pluginId,
    String path,
    List<int> bytes,
  ) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) throw Exception('插件不存在: $pluginId');
    await _repository.writePluginFileBytes(plugin, path, bytes);
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

  /// 删除所有用户自定义插件文件，回退到 defaults 出厂模板。
  Future<void> resetPluginDefaults(String pluginId) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) throw Exception('插件不存在: $pluginId');
    await _repository.resetPluginFilesToDefaults(plugin);
    _bumpRenderVersion(pluginId);
    notifyListeners();
  }

  /// 构建当前插件目录的 ZIP 字节内容。
  Future<Uint8List> buildPluginZipBytes(String pluginId) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) throw Exception('插件不存在: $pluginId');
    return _repository.buildPluginZipBytes(plugin);
  }

  /// 从应用资源包中导入内置插件。
  Future<InstalledPlugin> importBuiltIn(String pluginId) async {
    return _withBuiltInSource(pluginId, (sourceDir) async {
      final plugin = await _repository.importDirectory(sourceDir.path);
      await _upsert(plugin);
      return plugin;
    });
  }

  /// 从应用资源包同步内置插件源码，保留用户自定义文件和授权状态。
  Future<InstalledPlugin> syncBuiltIn(String pluginId) async {
    return _withBuiltInSource(pluginId, (sourceDir) async {
      final plugin = await _repository.syncDirectory(sourceDir.path);
      await _upsert(plugin);
      return pluginById(plugin.id) ?? plugin;
    });
  }

  /// 从应用资源包提取内置插件源码并执行操作，完成后清理临时目录。
  Future<T> _withBuiltInSource<T>(
    String pluginId,
    Future<T> Function(Directory sourceDir) action,
  ) async {
    final assetFiles = PluginRepository.builtInPluginFiles[pluginId];
    if (assetFiles == null || assetFiles.isEmpty) {
      throw Exception('内置插件资源不存在: $pluginId');
    }
    final prefix = 'assets/plugins/$pluginId/';

    final tempDir = await Directory.systemTemp.createTemp('lynai_builtin_');
    try {
      final sourceDir = Directory('${tempDir.path}/$pluginId');
      for (final relativePath in assetFiles) {
        final assetPath = '$prefix$relativePath';
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
      return await action(sourceDir);
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

  /// 递增插件的渲染版本号，触发 WebView 等依赖组件重建。
  void _bumpRenderVersion(String pluginId) {
    _renderVersions[pluginId] = renderVersion(pluginId) + 1;
  }

  /// 新增或更新插件，同名插件合并用户授权状态。
  Future<void> _upsert(InstalledPlugin imported) async {
    final current = pluginById(imported.id);
    final plugin = current == null
        ? _initialBuiltInPlugin(imported)
        : _mergeImported(imported, current);
    final next = [..._plugins.where((item) => item.id != plugin.id), plugin];
    _plugins = _sortPlugins(next);
    await _save();
    notifyListeners();
  }

  InstalledPlugin _initialBuiltInPlugin(InstalledPlugin imported) {
    if (!PluginRepository.builtInPluginIds.contains(imported.id)) {
      return imported;
    }
    final autoEnable = imported.manifest.lynai['autoEnable'] == true;
    final safeAutoEnable =
        autoEnable &&
        imported.manifest.permissions.isEmpty &&
        imported.manifest.tools.isEmpty &&
        imported.manifest.functions.isEmpty;
    return safeAutoEnable ? imported.copyWith(enabled: true) : imported;
  }

  /// 替换列表中指定 ID 的插件并保存。
  Future<void> _replace(String id, InstalledPlugin plugin) async {
    _plugins = _sortPlugins(
      _plugins.map((item) => item.id == id ? plugin : item).toList(),
    );
    await _save();
    notifyListeners();
  }

  /// 持久化当前插件列表到本地。
  Future<void> _save() => _repository.saveInstalledPlugins(_plugins);

  /// 导入插件与已有插件合并，保留用户的授权和启用状态配置。
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
      enabledTools: _mergeEnabledApiNames(
        previousNames: current.manifest.tools.map((tool) => tool.name).toSet(),
        nextNames: imported.manifest.tools.map((tool) => tool.name).toSet(),
        enabledNames: current.enabledTools.toSet(),
      ),
      enabledFunctions: _mergeEnabledApiNames(
        previousNames: current.manifest.functions
            .map((function) => function.name)
            .toSet(),
        nextNames: imported.manifest.functions
            .map((function) => function.name)
            .toSet(),
        enabledNames: current.enabledFunctions.toSet(),
      ),
      enabledSkills: _mergeEnabledApiNames(
        previousNames: current.manifest.skills
            .map((skill) => skill.name)
            .toSet(),
        nextNames: imported.manifest.skills.map((skill) => skill.name).toSet(),
        enabledNames: current.enabledSkills.toSet(),
      ),
      displayNameOverride: current.displayNameOverride,
    );
  }

  /// 合并新老插件的 API 启用列表，保留旧授权并自动启用新增 API。
  List<String> _mergeEnabledApiNames({
    required Set<String> previousNames,
    required Set<String> nextNames,
    required Set<String> enabledNames,
  }) {
    final retained = enabledNames.where(nextNames.contains).toSet();
    retained.addAll(nextNames.difference(previousNames));
    return retained.toList(growable: false);
  }

  /// 按显示名称字母序排列插件列表。
  List<InstalledPlugin> _sortPlugins(List<InstalledPlugin> plugins) {
    return plugins.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  /// 计算下一个快照插件的编号索引。
  int _nextSnapshotIndex(String sourceId) {
    var maxIndex = 0;
    final pattern = RegExp('^${RegExp.escape(sourceId)}-snapshot-(\\d+)\$');
    for (final plugin in _plugins) {
      if (plugin.manifest.snapshotOf == sourceId) {
        final value = plugin.manifest.lynai['snapshotIndex'];
        final index = value is int
            ? value
            : int.tryParse(value?.toString() ?? '');
        if (index != null && index > maxIndex) maxIndex = index;
      }
      final match = pattern.firstMatch(plugin.id);
      final index = match == null ? null : int.tryParse(match.group(1)!);
      if (index != null && index > maxIndex) maxIndex = index;
    }
    return maxIndex + 1;
  }

  /// 插件 ID 变更时迁移缓存中的键名。
  void _renameCaches(String oldId, String newId) {
    if (oldId == newId) return;
    void move<T>(Map<String, T> map) {
      final value = map.remove(oldId);
      if (value != null) map[newId] = value;
    }

    move(_settingsCache);
    move(_storageCache);
    move(_configCache);
    move(_schemaCache);
    final renderVersion = _renderVersions.remove(oldId);
    if (renderVersion != null) _renderVersions[newId] = renderVersion;
  }

  /// 确保新启用的插件不会与已启用插件的 API 名称冲突。
  void _ensureNoEnabledPluginApiConflict(InstalledPlugin target) {
    final targetEnabledTools = target.enabledTools.toSet();
    final targetTools = target.manifest.tools
        .map((tool) => tool.name.trim())
        .where((name) => name.isNotEmpty && targetEnabledTools.contains(name))
        .toSet();
    final targetEnabledFunctions = target.enabledFunctions.toSet();
    final targetFunctions = target.manifest.functions
        .map((function) => function.name.trim())
        .where(
          (name) => name.isNotEmpty && targetEnabledFunctions.contains(name),
        )
        .toSet();
    if (targetTools.isEmpty && targetFunctions.isEmpty) return;

    // 遍历所有已启用插件，检测 tool 和 function 名称冲突
    for (final plugin in _plugins) {
      if (plugin.id == target.id || !plugin.enabled || plugin.hasError) {
        continue;
      }
      final toolConflicts = plugin.manifest.tools
          .map((tool) => tool.name.trim())
          .where(
            (name) =>
                plugin.enabledTools.contains(name) &&
                targetTools.contains(name),
          )
          .toList(growable: false);
      final functionConflicts = plugin.manifest.functions
          .map((function) => function.name.trim())
          .where(
            (name) =>
                plugin.enabledFunctions.contains(name) &&
                targetFunctions.contains(name),
          )
          .toList(growable: false);
      if (toolConflicts.isEmpty && functionConflicts.isEmpty) continue;
      final parts = [
        if (toolConflicts.isNotEmpty) 'Tools: ${toolConflicts.join(', ')}',
        if (functionConflicts.isNotEmpty)
          'Functions: ${functionConflicts.join(', ')}',
      ];
      throw Exception(
        '插件 ${target.displayName} 与已启用插件 ${plugin.displayName} API 名称冲突：${parts.join('；')}',
      );
    }
  }
}
