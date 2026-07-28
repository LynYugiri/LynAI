import 'package:shared_preferences/shared_preferences.dart';

import 'backend_uri.dart';

class DeviceSettingsService {
  static const _backendUrlKey = 'device.bootstrap.backend_url.v1';
  static const _configuredKey = 'device.bootstrap.backend_configured.v1';

  Future<String?> loadBackendUrl({required String defaultUrl}) async {
    final preferences = await SharedPreferences.getInstance();
    if (!preferences.getBool(_configuredKey).orFalse) {
      final normalized = normalizeBackendUri(defaultUrl);
      if (normalized.isEmpty) return null;
      await saveBackendUrl(normalized);
      return normalized;
    }
    return preferences.getString(_backendUrlKey);
  }

  Future<void> saveBackendUrl(String? value) async {
    final normalized = value == null ? '' : normalizeBackendUri(value);
    if (value != null && normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Invalid backend URL');
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_configuredKey, true);
    if (value == null) {
      await preferences.remove(_backendUrlKey);
    } else {
      await preferences.setString(_backendUrlKey, normalized);
    }
  }
}

extension on bool? {
  bool get orFalse => this ?? false;
}
