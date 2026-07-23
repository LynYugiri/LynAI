import 'dart:io';

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
      expect(material.serverContext, returnsNormally);
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

  test('generated material completes a real TLS 1.3 handshake', () async {
    final store = InMemorySecretStore();
    final service = LanTlsCertificateService(
      secretStore: store,
      identityService: DeviceIdentityService(secretStore: store),
    );
    final material = await service.loadOrCreate();
    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      material.serverContext(),
      supportedProtocols: const ['lynai-lan/1'],
    );
    final accepted = server.first;
    final client = await SecureSocket.connect(
      InternetAddress.loopbackIPv4,
      server.port,
      context: SecurityContext(withTrustedRoots: false)
        ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3,
      supportedProtocols: const ['lynai-lan/1'],
      onBadCertificate: (certificate) =>
          service.certificateMatchesSpki(certificate.der, material.spkiSha256),
    );
    final peer = await accepted;
    expect(client.selectedProtocol, 'lynai-lan/1');
    expect(peer.selectedProtocol, 'lynai-lan/1');
    await client.close();
    await peer.close();
    await server.close();
  });

  test('legacy P-256 certificate is reissued with the same SPKI', () async {
    final store = InMemorySecretStore();
    final identityService = DeviceIdentityService(secretStore: store);
    final identity = await identityService.initialize();
    final pair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
    final privateKey = pair.privateKey as ECPrivateKey;
    final publicKey = pair.publicKey as ECPublicKey;
    final privatePem = CryptoUtils.encodeEcPrivateKeyToPem(privateKey);
    final csr = X509Utils.generateEccCsrPem(
      {'CN': 'LynAI ${identity.deviceId.substring(0, 12)}'},
      privateKey,
      publicKey,
      san: const ['lynai.local'],
    );
    final legacyCertificate = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      90,
      sans: const ['lynai.local'],
      keyUsage: const [KeyUsage.DIGITAL_SIGNATURE, KeyUsage.KEY_AGREEMENT],
      extKeyUsage: const [
        ExtendedKeyUsage.SERVER_AUTH,
        ExtendedKeyUsage.CLIENT_AUTH,
      ],
    );
    final legacyParsed = X509Utils.x509CertificateFromPem(legacyCertificate);
    final legacySpki = legacyParsed
        .tbsCertificate!
        .subjectPublicKeyInfo
        .sha256Thumbprint!
        .toLowerCase();
    await store.write('lan.tls.certificate.pem', legacyCertificate);
    await store.write('lan.tls.private_key.pem', privatePem);
    await store.write(
      'lan.tls.expires_at',
      legacyParsed.tbsCertificate!.validity.notAfter.toIso8601String(),
    );

    final material = await LanTlsCertificateService(
      secretStore: store,
      identityService: identityService,
    ).loadOrCreate();

    expect(material.spkiSha256, legacySpki);
    expect(material.certificatePem, isNot(legacyCertificate));
    expect(material.serverContext, returnsNormally);
  });

  test('concurrent initialization returns one certificate identity', () async {
    final store = InMemorySecretStore();
    final service = LanTlsCertificateService(
      secretStore: store,
      identityService: DeviceIdentityService(secretStore: store),
    );

    final materials = await Future.wait(
      List.generate(8, (_) => service.loadOrCreate()),
    );

    expect(
      materials.map((material) => material.spkiSha256).toSet(),
      hasLength(1),
    );
    expect(
      materials.map((material) => material.certificatePem).toSet(),
      hasLength(1),
    );
    expect(materials.first.serverContext, returnsNormally);
  });
}
