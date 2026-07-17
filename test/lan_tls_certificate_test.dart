import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/device_identity_service.dart';
import 'package:lynai/services/lan_tls_certificate_service.dart';
import 'package:lynai/services/secret_store.dart';

void main() {
  test(
    'certificate SPKI pin matches generated material and rejects mismatch',
    () async {
      final store = InMemorySecretStore();
      final service = LanTlsCertificateService(
        secretStore: store,
        identityService: DeviceIdentityService(secretStore: store),
      );
      final material = await service.loadOrCreate(now: DateTime.utc(2030));
      final certificate = CryptoUtils.getBytesFromPEMString(
        material.certificatePem,
      );
      expect(
        service.certificateMatchesSpki(certificate, material.spkiSha256),
        isTrue,
      );
      expect(service.certificateMatchesSpki(certificate, '0' * 64), isFalse);
      expect(
        service.certificateIsValidAt(certificate, DateTime.utc(2030)),
        isTrue,
      );
      final renewed = await service.loadOrCreate(
        now: DateTime.utc(2030, 3, 25),
      );
      expect(renewed.spkiSha256, material.spkiSha256);
    },
  );
}
