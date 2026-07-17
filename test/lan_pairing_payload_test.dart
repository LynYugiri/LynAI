import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/device_identity_service.dart';
import 'package:lynai/services/lan_pairing_payload_codec.dart';
import 'package:lynai/services/secret_store.dart';

void main() {
  test(
    'pairing payload round trips and rejects tampering and expiry',
    () async {
      final identity = DeviceIdentityService(
        secretStore: InMemorySecretStore(),
      );
      final codec = LanPairingPayloadCodec();
      final now = DateTime.utc(2030, 1, 1);
      final encoded = await codec.create(
        identityService: identity,
        spkiSha256: 'a' * 64,
        certificateExpiresAt: now.add(const Duration(days: 30)),
        nonce: 'nonce-that-is-long-enough-123',
        addresses: const ['192.168.1.2', 'fd00::1'],
        port: 42319,
        expiresAt: now.add(const Duration(minutes: 3)),
      );
      final decoded = await codec.decodeAndVerify(encoded, now: now);
      expect(decoded.port, 42319);
      expect(decoded.addresses, ['192.168.1.2', 'fd00::1']);

      final last = encoded.codeUnitAt(encoded.length - 1);
      final tampered =
          encoded.substring(0, encoded.length - 1) +
          String.fromCharCode(last == 65 ? 66 : 65);
      await expectLater(
        codec.decodeAndVerify(tampered, now: now),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        codec.decodeAndVerify(
          encoded,
          now: now.add(const Duration(minutes: 4)),
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'pairing payload enforces size, address count, and LAN literals',
    () async {
      final codec = LanPairingPayloadCodec();
      final identity = DeviceIdentityService(
        secretStore: InMemorySecretStore(),
      );
      final now = DateTime.utc(2030);
      Future<String> create(List<String> addresses) => codec.create(
        identityService: identity,
        spkiSha256: 'a' * 64,
        certificateExpiresAt: now.add(const Duration(days: 1)),
        nonce: 'nonce-that-is-long-enough-123',
        addresses: addresses,
        port: 1234,
        expiresAt: now.add(const Duration(minutes: 1)),
      );

      await expectLater(create(const ['8.8.8.8']), throwsFormatException);
      await expectLater(create(const ['example.test']), throwsFormatException);
      await expectLater(
        create(List.generate(9, (index) => '192.168.1.${index + 1}')),
        throwsFormatException,
      );
      await expectLater(
        codec.decodeAndVerify(
          '${LanPairingPayloadCodec.uriPrefix}${'a' * LanPairingPayloadCodec.maxEncodedBytes}',
        ),
        throwsFormatException,
      );
    },
  );
}
