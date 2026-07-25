import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/device_identity_service.dart';
import 'package:lynai/services/lan_device_profile_service.dart';
import 'package:lynai/services/secret_store.dart';

void main() {
  test('LAN device name is stable and user editable', () async {
    final store = InMemorySecretStore();
    final service = LanDeviceProfileService(
      secretStore: store,
      identityService: DeviceIdentityService(secretStore: store),
    );

    final initial = await service.displayName();
    expect(initial, isNotEmpty);
    expect(await service.displayName(), initial);

    expect(await service.updateDisplayName('Workstation'), 'Workstation');
    expect(await service.displayName(), 'Workstation');
  });

  test('LAN device name rejects empty and oversized UTF-8 values', () async {
    final store = InMemorySecretStore();
    final service = LanDeviceProfileService(
      secretStore: store,
      identityService: DeviceIdentityService(secretStore: store),
    );

    expect(() => service.updateDisplayName('  '), throwsArgumentError);
    expect(() => service.updateDisplayName('猫' * 22), throwsArgumentError);
  });
}
