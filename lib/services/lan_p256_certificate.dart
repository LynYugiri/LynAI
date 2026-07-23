import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/asn1/primitives/asn1_bit_string.dart';
import 'package:pointycastle/asn1/primitives/asn1_boolean.dart';
import 'package:pointycastle/asn1/primitives/asn1_ia5_string.dart';
import 'package:pointycastle/asn1/primitives/asn1_integer.dart';
import 'package:pointycastle/asn1/primitives/asn1_object_identifier.dart';
import 'package:pointycastle/asn1/primitives/asn1_octet_string.dart';
import 'package:pointycastle/asn1/primitives/asn1_printable_string.dart';
import 'package:pointycastle/asn1/primitives/asn1_sequence.dart';
import 'package:pointycastle/asn1/primitives/asn1_set.dart';
import 'package:pointycastle/asn1/primitives/asn1_utc_time.dart';

const _ecdsaWithSha256 = [1, 2, 840, 10045, 4, 3, 2];
const _ecPublicKey = [1, 2, 840, 10045, 2, 1];
const _prime256v1 = [1, 2, 840, 10045, 3, 1, 7];
const _commonName = [2, 5, 4, 3];
const _basicConstraints = [2, 5, 29, 19];
const _keyUsage = [2, 5, 29, 15];
const _extendedKeyUsage = [2, 5, 29, 37];
const _subjectAlternativeName = [2, 5, 29, 17];
const _serverAuth = [1, 3, 6, 1, 5, 5, 7, 3, 1];
const _clientAuth = [1, 3, 6, 1, 5, 5, 7, 3, 2];

String generateLanP256Certificate({
  required ECPrivateKey privateKey,
  required ECPublicKey publicKey,
  required String commonName,
  required DateTime notBefore,
  required DateTime notAfter,
}) {
  final signatureAlgorithm = _algorithmIdentifier(_ecdsaWithSha256);
  final name = ASN1Sequence(
    elements: [
      ASN1Set(
        elements: [
          ASN1Sequence(
            elements: [
              ASN1ObjectIdentifier(_commonName),
              ASN1PrintableString(stringValue: commonName),
            ],
          ),
        ],
      ),
    ],
  );
  final subjectPublicKeyInfo = ASN1Sequence(
    elements: [
      ASN1Sequence(
        elements: [
          ASN1ObjectIdentifier(_ecPublicKey),
          ASN1ObjectIdentifier(_prime256v1),
        ],
      ),
      _bitString(publicKey.Q!.getEncoded(false)),
    ],
  );
  final extensions = ASN1Sequence(
    elements: [
      _extension(
        _basicConstraints,
        ASN1Sequence(elements: const []).encode(),
        critical: true,
      ),
      _extension(
        _keyUsage,
        _bitString(const [0x88], unusedBits: 3).encode(),
        critical: true,
      ),
      _extension(
        _extendedKeyUsage,
        ASN1Sequence(
          elements: [
            ASN1ObjectIdentifier(_serverAuth),
            ASN1ObjectIdentifier(_clientAuth),
          ],
        ).encode(),
      ),
      _extension(
        _subjectAlternativeName,
        ASN1Sequence(
          elements: [ASN1IA5String(stringValue: 'lynai.local', tag: 0x82)],
        ).encode(),
      ),
    ],
  );
  final tbsCertificate = ASN1Sequence(
    elements: [
      ASN1Sequence(tag: 0xa0, elements: [ASN1Integer.fromtInt(2)]),
      ASN1Integer(_serialNumber()),
      signatureAlgorithm,
      name,
      ASN1Sequence(
        elements: [
          ASN1UtcTime(notBefore.toUtc()),
          ASN1UtcTime(notAfter.toUtc()),
        ],
      ),
      name,
      subjectPublicKeyInfo,
      ASN1Sequence(tag: 0xa3, elements: [extensions]),
    ],
  );
  final signature = X509Utils.eccSign(
    tbsCertificate.encode(),
    privateKey,
    'SHA-256',
  );
  final encodedSignature = ASN1Sequence(
    elements: [ASN1Integer(signature.r), ASN1Integer(signature.s)],
  ).encode();
  final certificate = ASN1Sequence(
    elements: [
      tbsCertificate,
      _algorithmIdentifier(_ecdsaWithSha256),
      _bitString(encodedSignature),
    ],
  ).encode();
  final body = base64Encode(
    certificate,
  ).replaceAllMapped(RegExp(r'.{1,64}'), (match) => '${match.group(0)}\n');
  return '-----BEGIN CERTIFICATE-----\n$body-----END CERTIFICATE-----';
}

ASN1Sequence _algorithmIdentifier(List<int> oid) =>
    ASN1Sequence(elements: [ASN1ObjectIdentifier(oid)]);

ASN1Sequence _extension(
  List<int> oid,
  Uint8List value, {
  bool critical = false,
}) => ASN1Sequence(
  elements: [
    ASN1ObjectIdentifier(oid),
    if (critical) ASN1Boolean(true),
    ASN1OctetString(octets: value),
  ],
);

ASN1BitString _bitString(List<int> bytes, {int unusedBits = 0}) =>
    ASN1BitString(stringValues: bytes)..unusedbits = unusedBits;

BigInt _serialNumber() {
  final random = Random.secure();
  final bytes = Uint8List(16);
  for (var index = 0; index < bytes.length; index++) {
    bytes[index] = random.nextInt(256);
  }
  bytes[0] &= 0x7f;
  bytes[0] |= 0x01;
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}
