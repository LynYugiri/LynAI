import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../services/storage_v2_service.dart';
import 'app_storage_state.dart';

class SettingsLoadResult {
  const SettingsLoadResult({
    required this.settings,
    required this.usingStorageV2,
  });

  final AppSettings settings;
  final bool usingStorageV2;
}

class SettingsRepository {
  factory SettingsRepository({
    StorageV2Service? storageV2,
    AppStorageStateRepository? storageState,
  }) {
    final storage = storageV2 ?? StorageV2Service();
    return SettingsRepository._(
      storage,
      storageState ?? AppStorageStateRepository(storageV2: storage),
    );
  }

  SettingsRepository._(this._storageV2, this._storageState);

  static const _storageKey = 'app_settings';

  final StorageV2Service _storageV2;
  final AppStorageStateRepository _storageState;

  Future<SettingsLoadResult> load(AppSettings fallback) async {
    final usingStorageV2 = await _storageState.isStorageV2Active();
    if (usingStorageV2) {
      final json = await _storageV2.loadDataFile('app_settings.json');
      final settings = json.isEmpty
          ? fallback
          : await _settingsFromStorageV2Json(json);
      return SettingsLoadResult(settings: settings, usingStorageV2: true);
    }
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString == null) {
      return SettingsLoadResult(settings: fallback, usingStorageV2: false);
    }
    return SettingsLoadResult(
      settings: AppSettings.fromJson(
        jsonDecode(jsonString) as Map<String, dynamic>,
      ),
      usingStorageV2: false,
    );
  }

  Future<void> save(
    AppSettings settings, {
    required bool usingStorageV2,
  }) async {
    if (usingStorageV2 || await _isStorageV2Active()) {
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
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(settings.toJson()));
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

  Future<bool> _isStorageV2Active() async {
    try {
      return await _storageState.isStorageV2Active();
    } catch (_) {
      return false;
    }
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
