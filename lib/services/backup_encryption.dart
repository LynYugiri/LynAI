import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class BackupDecryptionException implements Exception {
  const BackupDecryptionException();

  @override
  String toString() => '密码错误或备份文件已损坏';
}

class BackupEncryption {
  static const magic = 'LYNAIBK1';
  static const version = 1;
  static const defaultMemoryKiB = 19 * 1024;
  static const defaultIterations = 2;
  static const defaultParallelism = 1;
  static const minMemoryKiB = 19 * 1024;
  static const maxMemoryKiB = 256 * 1024;
  static const minIterations = 2;
  static const maxIterations = 10;
  static const maxParallelism = 4;
  static const maxPasswordBytes = 1024;
  static const maxPlaintextBytes = 512 * 1024 * 1024;
  static const _fixedHeaderLength = 44;
  static const _saltLength = 16;
  static const _nonceLength = 24;
  static const _tagLength = 16;
  static const maxEnvelopeBytes =
      _fixedHeaderLength +
      _saltLength +
      _nonceLength +
      maxPlaintextBytes +
      _tagLength;

  const BackupEncryption({
    this.memoryKiB = defaultMemoryKiB,
    this.iterations = defaultIterations,
    this.parallelism = defaultParallelism,
    Random? random,
  }) : _random = random;

  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final Random? _random;

  static bool isEncrypted(List<int> bytes) {
    if (bytes.length < magic.length) return false;
    for (var index = 0; index < magic.length; index++) {
      if (bytes[index] != magic.codeUnitAt(index)) return false;
    }
    return true;
  }

  Future<Uint8List> encrypt(List<int> plaintext, String password) async {
    _validatePassword(password);
    _validateParameters(memoryKiB, iterations, parallelism);
    if (plaintext.length > maxPlaintextBytes) {
      throw const FormatException('备份明文体积超过限制');
    }
    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final header = _header(
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      plaintextLength: plaintext.length,
      ciphertextLength: plaintext.length,
      salt: salt,
      nonce: nonce,
    );
    final key = await _deriveKey(
      password,
      salt,
      memoryKiB,
      iterations,
      parallelism,
    );
    final box = await Xchacha20.poly1305Aead().encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
      aad: header,
    );
    return Uint8List.fromList([...header, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<Uint8List> decrypt(List<int> envelope, String password) async {
    try {
      _validatePassword(password);
      if (envelope.length > maxEnvelopeBytes) throw const FormatException();
      if (envelope.length <
          _fixedHeaderLength + _saltLength + _nonceLength + _tagLength) {
        throw const FormatException();
      }
      final bytes = Uint8List.fromList(envelope);
      if (!isEncrypted(bytes)) throw const FormatException();
      final data = ByteData.sublistView(bytes);
      final parsedVersion = data.getUint16(8);
      final flags = data.getUint16(10);
      final memory = data.getUint32(12);
      final parsedIterations = data.getUint32(16);
      final parsedParallelism = data.getUint16(20);
      final saltLength = data.getUint16(22);
      final nonceLength = data.getUint16(24);
      final tagLength = data.getUint16(26);
      final plaintextLength = data.getUint64(28);
      final ciphertextLength = data.getUint64(36);
      if (parsedVersion != version ||
          flags != 0 ||
          saltLength != _saltLength ||
          nonceLength != _nonceLength ||
          tagLength != _tagLength ||
          plaintextLength > maxPlaintextBytes ||
          ciphertextLength != plaintextLength) {
        throw const FormatException();
      }
      _validateParameters(memory, parsedIterations, parsedParallelism);
      final headerLength = _fixedHeaderLength + saltLength + nonceLength;
      final expectedLength = headerLength + ciphertextLength + tagLength;
      if (expectedLength != bytes.length) throw const FormatException();
      final salt = bytes.sublist(
        _fixedHeaderLength,
        _fixedHeaderLength + saltLength,
      );
      final nonce = bytes.sublist(
        _fixedHeaderLength + saltLength,
        headerLength,
      );
      final cipherTextEnd = headerLength + ciphertextLength.toInt();
      final cipherText = bytes.sublist(headerLength, cipherTextEnd);
      final tag = bytes.sublist(cipherTextEnd);
      final key = await _deriveKey(
        password,
        salt,
        memory,
        parsedIterations,
        parsedParallelism,
      );
      final plaintext = await Xchacha20.poly1305Aead().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
        secretKey: key,
        aad: bytes.sublist(0, headerLength),
      );
      if (plaintext.length != plaintextLength) throw const FormatException();
      return Uint8List.fromList(plaintext);
    } catch (_) {
      throw const BackupDecryptionException();
    }
  }

  Uint8List _header({
    required int memoryKiB,
    required int iterations,
    required int parallelism,
    required int plaintextLength,
    required int ciphertextLength,
    required List<int> salt,
    required List<int> nonce,
  }) {
    final header = Uint8List(_fixedHeaderLength + salt.length + nonce.length);
    header.setRange(0, magic.length, ascii.encode(magic));
    final data = ByteData.sublistView(header);
    data
      ..setUint16(8, version)
      ..setUint16(10, 0)
      ..setUint32(12, memoryKiB)
      ..setUint32(16, iterations)
      ..setUint16(20, parallelism)
      ..setUint16(22, salt.length)
      ..setUint16(24, nonce.length)
      ..setUint16(26, _tagLength)
      ..setUint64(28, plaintextLength)
      ..setUint64(36, ciphertextLength);
    header
      ..setRange(_fixedHeaderLength, _fixedHeaderLength + salt.length, salt)
      ..setRange(_fixedHeaderLength + salt.length, header.length, nonce);
    return header;
  }

  Future<SecretKey> _deriveKey(
    String password,
    List<int> salt,
    int memory,
    int iterations,
    int parallelism,
  ) {
    return Argon2id(
      parallelism: parallelism,
      memory: memory,
      iterations: iterations,
      hashLength: 32,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  }

  Uint8List _randomBytes(int length) {
    final random = _random ?? Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static void _validatePassword(String password) {
    final bytes = utf8.encode(password);
    if (bytes.isEmpty || bytes.length > maxPasswordBytes) {
      throw const FormatException('备份密码长度无效');
    }
  }

  static void _validateParameters(int memory, int iterations, int parallelism) {
    if (memory < minMemoryKiB ||
        memory > maxMemoryKiB ||
        iterations < minIterations ||
        iterations > maxIterations ||
        parallelism < 1 ||
        parallelism > maxParallelism ||
        memory < parallelism * 8) {
      throw const FormatException('Argon2id 参数超出限制');
    }
  }
}
