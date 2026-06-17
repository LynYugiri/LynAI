import 'dart:io';

import '../models/app_settings.dart';
import '../services/storage_v2_service.dart';

/// 设置加载结果，包含应用设置实例与存储版本标识。
class SettingsLoadResult {
  const SettingsLoadResult({
    required this.settings,
    required this.usingStorageV2,
  });

  final AppSettings settings;
  final bool usingStorageV2;
}

/// 应用设置仓储，负责加载和持久化用户偏好设置。
///
/// 包含背景图片资源同步功能。
class SettingsRepository {
  factory SettingsRepository({StorageV2Service? storageV2}) {
    final storage = storageV2 ?? StorageV2Service();
    return SettingsRepository._(storage);
  }

  SettingsRepository._(this._storageV2);

  final StorageV2Service _storageV2;

  /// 加载应用设置。
  ///
  /// 若存储中无数据则返回传入的默认值 [fallback]。
  Future<SettingsLoadResult> load(AppSettings fallback) async {
    final json = await _storageV2.loadDataFile('app_settings.json');
    final settings = json.isEmpty
        ? fallback
        : await _settingsFromStorageV2Json(json);
    return SettingsLoadResult(settings: settings, usingStorageV2: true);
  }

  /// 保存应用设置到当前激活的存储后端。
  ///
  /// 在新版 V2 存储模式下会同步背景图片资源 ID。
  Future<void> save(
    AppSettings settings, {
    required bool usingStorageV2,
  }) async {
    final next = settings.toJson();
    final nextStorage = <String, dynamic>{};
    try {
      final current = await _storageV2.loadDataFile('app_settings.json');
      final storage = current['storageV2'];
      if (storage is Map && storage.isNotEmpty) {
        nextStorage.addAll(Map<String, dynamic>.from(storage));
      }
    } catch (_) {
      // A missing or corrupt existing settings file should not block saving.
    }
    await _syncBackgroundResourceId(settings, nextStorage);
    if (nextStorage.isNotEmpty) next['storageV2'] = nextStorage;
    await _storageV2.writeDataFile('app_settings.json', next);
  }

  Future<AppSettings> _settingsFromStorageV2Json(
    Map<String, dynamic> json,
  ) async {
    var settings = AppSettings.fromJson(json);
    final storage = json['storageV2'];
    final backgroundResourceId = storage is Map
        ? storage['backgroundResourceId'] as String?
        : null;
    if (backgroundResourceId == null || backgroundResourceId.isEmpty) {
      return settings;
    }
    final resource = await _storageV2.findResourceById(backgroundResourceId);
    final path = resource == null
        ? null
        : await _storageV2.resourcePath(resource);
    if (path == null || path.isEmpty) return settings;
    return settings.copyWith(backgroundImagePath: path);
  }

  Future<void> _syncBackgroundResourceId(
    AppSettings settings,
    Map<String, dynamic> storage,
  ) async {
    // `backgroundImagePath` is the user-visible source of truth. The storage v2
    // resource id is only an index for restoring that file after migration or
    // backup, so keep it in sync instead of preserving stale metadata blindly.
    final path = settings.backgroundImagePath;
    if (path == null || path.isEmpty) {
      storage.remove('backgroundResourceId');
      return;
    }

    final currentId = storage['backgroundResourceId'] as String?;
    if (currentId != null && currentId.isNotEmpty) {
      final currentResource = await _storageV2.findResourceById(currentId);
      final currentPath = currentResource == null
          ? null
          : await _storageV2.resourcePath(currentResource);
      if (currentPath == path) return;
    }

    final file = File(path);
    if (!await file.exists()) {
      storage.remove('backgroundResourceId');
      return;
    }

    final resource = await _storageV2.importResourceFile(
      path,
      originalName: _fileNameFromPath(path),
      mimeType: _imageMimeType(path),
      role: 'background',
    );
    storage['backgroundResourceId'] = resource.id;
  }

  String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    final name = slash == -1 ? normalized : normalized.substring(slash + 1);
    return name.isEmpty ? 'background' : name;
  }

  String _imageMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    return 'application/octet-stream';
  }
}
