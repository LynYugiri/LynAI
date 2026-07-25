import 'dart:convert';
import 'dart:io';

import 'device_identity_service.dart';
import 'secret_store.dart';

class LanDeviceProfileService {
  LanDeviceProfileService({
    required SecretStore secretStore,
    required DeviceIdentityService identityService,
  }) : _secretStore = secretStore,
       _identityService = identityService;

  static const _displayNameKey = 'lan.device_display_name.v1';

  final SecretStore _secretStore;
  final DeviceIdentityService _identityService;

  Future<String> displayName() async {
    final saved = await _secretStore.read(_displayNameKey);
    if (saved != null && _valid(saved)) return saved;
    final identity = await _identityService.initialize();
    String host;
    try {
      host = Platform.localHostname.trim();
    } catch (_) {
      host = '';
    }
    final generated = _valid(host)
        ? host
        : 'LynAI-${identity.deviceId.substring(identity.deviceId.length - 4).toUpperCase()}';
    await _secretStore.write(_displayNameKey, generated);
    return generated;
  }

  Future<String> updateDisplayName(String value) async {
    final normalized = value.trim();
    if (!_valid(normalized)) {
      throw ArgumentError.value(value, 'value', '设备名称必须为 1 至 64 个 UTF-8 字节');
    }
    await _secretStore.write(_displayNameKey, normalized);
    return normalized;
  }

  bool _valid(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed != value || trimmed.contains('\u0000')) {
      return false;
    }
    return utf8.encode(trimmed).length <= 64;
  }
}
