import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:basic_utils/basic_utils.dart';

import '../models/lan_pairing_payload.dart';
import 'device_identity_service.dart';
import 'lan_pairing_payload_codec.dart';
import 'secret_store.dart';

class LanTlsMaterial {
  const LanTlsMaterial({
    required this.certificatePem,
    required String privateKeyPem,
    required this.spkiSha256,
    required this.expiresAt,
  }) : _privateKeyPem = privateKeyPem;

  final String certificatePem;
  final String _privateKeyPem;
  final String spkiSha256;
  final DateTime expiresAt;

  SecurityContext serverContext() {
    final context = SecurityContext(withTrustedRoots: false)
      ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3
      ..useCertificateChainBytes(utf8.encode(certificatePem))
      ..usePrivateKeyBytes(utf8.encode(_privateKeyPem))
      ..setAlpnProtocols(const ['lynai-lan/1'], true);
    return context;
  }
}

class LanTlsCertificateService {
  LanTlsCertificateService({
    required SecretStore secretStore,
    required DeviceIdentityService identityService,
    LanPairingPayloadCodec? codec,
  }) : _secretStore = secretStore,
       _identityService = identityService,
       _codec = codec ?? LanPairingPayloadCodec();

  static const _certificateKey = 'lan.tls.certificate.pem';
  static const _privateKeyKey = 'lan.tls.private_key.pem';
  static const _expiresKey = 'lan.tls.expires_at';
  static const _rotationLead = Duration(days: 7);
  static const _validityDays = 90;

  final SecretStore _secretStore;
  final DeviceIdentityService _identityService;
  final LanPairingPayloadCodec _codec;

  Future<LanTlsMaterial> loadOrCreate({DateTime? now}) async {
    final clock = (now ?? DateTime.now()).toUtc();
    final stored = await Future.wait([
      _secretStore.read(_certificateKey),
      _secretStore.read(_privateKeyKey),
      _secretStore.read(_expiresKey),
    ]);
    final expires = DateTime.tryParse(stored[2] ?? '');
    if (stored[0] != null &&
        stored[1] != null &&
        expires != null &&
        _certificateIsValid(stored[0]!, clock) &&
        expires.isAfter(clock.add(_rotationLead))) {
      return _material(stored[0]!, stored[1]!);
    }
    return _create(clock, existingPrivateKeyPem: stored[1]);
  }

  Future<LanTlsBinding> createBinding(String nonce) async {
    final material = await loadOrCreate();
    return _codec.createBinding(
      identityService: _identityService,
      spkiSha256: material.spkiSha256,
      certificateExpiresAt: material.expiresAt,
      pairingNonce: nonce,
    );
  }

  String spkiSha256FromCertificateDer(List<int> der) {
    final pem = X509Utils.formatKeyString(
      base64Encode(der),
      '-----BEGIN CERTIFICATE-----',
      '-----END CERTIFICATE-----',
    );
    return X509Utils.x509CertificateFromPem(
      pem,
    ).tbsCertificate!.subjectPublicKeyInfo.sha256Thumbprint!.toLowerCase();
  }

  bool certificateMatchesSpki(List<int> der, String expectedSpkiSha256) =>
      spkiSha256FromCertificateDer(der) == expectedSpkiSha256.toLowerCase();

  Future<LanTlsMaterial> _create(
    DateTime now, {
    String? existingPrivateKeyPem,
  }) async {
    final pair = existingPrivateKeyPem == null
        ? CryptoUtils.generateEcKeyPair(curve: 'prime256v1')
        : null;
    final privateKey = existingPrivateKeyPem == null
        ? pair!.privateKey as ECPrivateKey
        : CryptoUtils.ecPrivateKeyFromPem(existingPrivateKeyPem);
    final publicKey = existingPrivateKeyPem == null
        ? pair!.publicKey as ECPublicKey
        : ECPublicKey(
            privateKey.parameters!.G * privateKey.d!,
            privateKey.parameters,
          );
    final identity = await _identityService.initialize();
    final csr = X509Utils.generateEccCsrPem(
      {'CN': 'LynAI ${identity.deviceId.substring(0, 12)}'},
      privateKey,
      publicKey,
      san: const ['lynai.local'],
    );
    final certificate = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      _validityDays,
      sans: const ['lynai.local'],
      keyUsage: const [KeyUsage.DIGITAL_SIGNATURE, KeyUsage.KEY_AGREEMENT],
      extKeyUsage: const [
        ExtendedKeyUsage.SERVER_AUTH,
        ExtendedKeyUsage.CLIENT_AUTH,
      ],
      serialNumber: _serialNumber(),
      notBefore: now.subtract(const Duration(minutes: 5)),
    );
    final privatePem =
        existingPrivateKeyPem ??
        CryptoUtils.encodeEcPrivateKeyToPem(privateKey);
    final parsed = X509Utils.x509CertificateFromPem(certificate);
    final expires = parsed.tbsCertificate!.validity.notAfter.toUtc();
    await _secretStore.write(_certificateKey, certificate);
    await _secretStore.write(_privateKeyKey, privatePem);
    await _secretStore.write(_expiresKey, expires.toIso8601String());
    return _material(certificate, privatePem);
  }

  LanTlsMaterial _material(String certificate, String privateKey) {
    final parsed = X509Utils.x509CertificateFromPem(certificate);
    return LanTlsMaterial(
      certificatePem: certificate,
      privateKeyPem: privateKey,
      spkiSha256: parsed.tbsCertificate!.subjectPublicKeyInfo.sha256Thumbprint!
          .toLowerCase(),
      expiresAt: parsed.tbsCertificate!.validity.notAfter.toUtc(),
    );
  }

  bool certificateIsValidAt(List<int> der, DateTime now) {
    try {
      final pem = X509Utils.formatKeyString(
        base64Encode(der),
        '-----BEGIN CERTIFICATE-----',
        '-----END CERTIFICATE-----',
      );
      return _certificateIsValid(pem, now.toUtc());
    } catch (_) {
      return false;
    }
  }

  DateTime certificateExpiresAt(List<int> der) {
    final pem = X509Utils.formatKeyString(
      base64Encode(der),
      '-----BEGIN CERTIFICATE-----',
      '-----END CERTIFICATE-----',
    );
    return X509Utils.x509CertificateFromPem(
      pem,
    ).tbsCertificate!.validity.notAfter.toUtc();
  }

  bool _certificateIsValid(String pem, DateTime now) {
    try {
      final validity = X509Utils.x509CertificateFromPem(
        pem,
      ).tbsCertificate!.validity;
      return !now.isBefore(validity.notBefore.toUtc()) &&
          now.isBefore(validity.notAfter.toUtc());
    } catch (_) {
      return false;
    }
  }

  String _serialNumber() {
    final random = Random.secure();
    var value = BigInt.zero;
    for (var index = 0; index < 16; index++) {
      value = (value << 8) | BigInt.from(random.nextInt(256));
    }
    return value.toString();
  }
}
