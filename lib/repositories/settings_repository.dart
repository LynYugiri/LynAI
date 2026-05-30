import 'dart:convert';

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
    if (usingStorageV2 || await _storageState.isStorageV2Active()) {
      await _storageV2.writeDataFile('app_settings.json', settings.toJson());
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
}
