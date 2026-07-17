import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class LanFrame {
  const LanFrame({
    required this.type,
    required this.sessionId,
    required this.counter,
    required this.purpose,
    required this.role,
    required this.body,
  });

  final String type;
  final String sessionId;
  final int counter;
  final String purpose;
  final String role;
  final Map<String, dynamic> body;
}

class LanFrameException implements Exception {
  const LanFrameException(this.message);

  final String message;

  @override
  String toString() => 'LanFrameException: $message';
}

class LanSecureTransport {
  static const blobChunkBytes = 384 * 1024;

  LanSecureTransport(
    this.socket, {
    this.maxFrameBytes = 1024 * 1024,
    this.maxPreAuthFrameBytes = 16 * 1024,
    this.maxBodyBytes = 768 * 1024,
    this.maxBlobBytes = 64 * 1024 * 1024,
    this.readTimeout = const Duration(seconds: 20),
    this.writeTimeout = const Duration(seconds: 20),
  }) : _iterator = StreamIterator(socket);

  final SecureSocket socket;
  final int maxFrameBytes;
  final int maxPreAuthFrameBytes;
  final int maxBodyBytes;
  final int maxBlobBytes;
  final Duration readTimeout;
  final Duration writeTimeout;
  final StreamIterator<Uint8List> _iterator;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  int _sentCounter = 0;
  int _receivedCounter = 0;
  bool _authenticated = false;
  String? _sessionId;
  String? _purpose;
  String? _localRole;
  String? _remoteRole;
  Future<void>? _closeFuture;

  void bindSession({
    required String sessionId,
    required String purpose,
    required String localRole,
    required String remoteRole,
  }) {
    if (_sessionId != null ||
        !_validToken(sessionId, 128) ||
        !_validToken(purpose, 32) ||
        !const {'initiator', 'responder'}.contains(localRole) ||
        !const {'initiator', 'responder'}.contains(remoteRole) ||
        localRole == remoteRole) {
      throw const LanFrameException('invalid immutable session binding');
    }
    _sessionId = sessionId;
    _purpose = purpose;
    _localRole = localRole;
    _remoteRole = remoteRole;
  }

  void markAuthenticated() {
    if (_sessionId == null) {
      throw const LanFrameException('session is not bound');
    }
    _authenticated = true;
  }

  static Uint8List encodeFrame({
    required String type,
    required String sessionId,
    required int counter,
    required String purpose,
    required String role,
    required Map<String, dynamic> body,
    int maxFrameBytes = 1024 * 1024,
    int maxBodyBytes = 768 * 1024,
    int maxBlobBytes = 64 * 1024 * 1024,
  }) {
    if (!_validToken(sessionId, 128) ||
        !_validToken(type, 64) ||
        !_validToken(purpose, 32) ||
        !const {'initiator', 'responder'}.contains(role)) {
      throw const LanFrameException('invalid frame metadata');
    }
    final bodyBytes = utf8.encode(jsonEncode(body));
    if (bodyBytes.length > maxBodyBytes) {
      throw LanFrameException('frame body exceeds $maxBodyBytes bytes');
    }
    final bytes = utf8.encode(
      jsonEncode({
        'type': type,
        'sessionId': sessionId,
        'counter': counter,
        'purpose': purpose,
        'role': role,
        'body': body,
      }),
    );
    if (bytes.length > maxFrameBytes) {
      throw LanFrameException('frame exceeds $maxFrameBytes bytes');
    }
    final header = ByteData(4)..setUint32(0, bytes.length, Endian.big);
    return Uint8List.fromList([...header.buffer.asUint8List(), ...bytes]);
  }

  Future<void> send(String type, Map<String, dynamic> body) async {
    final sessionId = _sessionId;
    final purpose = _purpose;
    final role = _localRole;
    if (sessionId == null || purpose == null || role == null) {
      throw const LanFrameException('session is not bound');
    }
    if (!_authenticated && _isBlobType(type)) {
      throw const LanFrameException('blob frame before authentication');
    }
    final bytes = encodeFrame(
      type: type,
      sessionId: sessionId,
      counter: ++_sentCounter,
      purpose: purpose,
      role: role,
      body: body,
      maxFrameBytes: maxFrameBytes,
      maxBodyBytes: maxBodyBytes,
      maxBlobBytes: maxBlobBytes,
    );
    socket.add(bytes);
    await socket.flush().timeout(writeTimeout);
  }

  Future<LanFrame> receive({
    required Set<String> expectedTypes,
    Set<String>? expectedPurposes,
  }) async {
    final header = await _readExact(4);
    final length = ByteData.sublistView(header).getUint32(0, Endian.big);
    final wireLimit = _authenticated ? maxFrameBytes : maxPreAuthFrameBytes;
    if (length <= 0 || length > wireLimit) {
      throw LanFrameException('invalid frame length: $length');
    }
    final bytes = await _readExact(length);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const LanFrameException('frame is not an object');
    }
    final frame = Map<String, dynamic>.from(decoded);
    if (frame.keys.toSet().difference(const {
          'type',
          'sessionId',
          'counter',
          'purpose',
          'role',
          'body',
        }).isNotEmpty ||
        frame.length != 6) {
      throw const LanFrameException('unexpected frame fields');
    }
    final type = frame['type'] as String? ?? '';
    final sessionId = frame['sessionId'] as String? ?? '';
    final counter = (frame['counter'] as num?)?.toInt() ?? 0;
    final purpose = frame['purpose'] as String? ?? '';
    final role = frame['role'] as String? ?? '';
    final body = frame['body'];
    if (_sessionId == null &&
        _validToken(sessionId, 128) &&
        _validToken(purpose, 32) &&
        (expectedPurposes?.contains(purpose) ?? true) &&
        const {'initiator', 'responder'}.contains(role)) {
      bindSession(
        sessionId: sessionId,
        purpose: purpose,
        localRole: role == 'initiator' ? 'responder' : 'initiator',
        remoteRole: role,
      );
    }
    if (!expectedTypes.contains(type) ||
        sessionId != _sessionId ||
        purpose != _purpose ||
        role != _remoteRole ||
        body is! Map ||
        (!_authenticated && _isBlobType(type)) ||
        counter != _receivedCounter + 1) {
      throw const LanFrameException('invalid frame metadata or counter');
    }
    _receivedCounter = counter;
    return LanFrame(
      type: type,
      sessionId: sessionId,
      counter: counter,
      purpose: purpose,
      role: role,
      body: Map<String, dynamic>.from(body),
    );
  }

  static bool _validToken(String value, int maxLength) =>
      value.isNotEmpty &&
      value.length <= maxLength &&
      RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value);

  static bool _isBlobType(String type) =>
      type == 'blob-start' || type == 'blob-chunk' || type == 'blob-end';

  static Iterable<(int, int)> blobChunkRanges(int length) sync* {
    if (length < 0 || length > 64 * 1024 * 1024) {
      throw const LanFrameException('invalid blob length');
    }
    for (var offset = 0; offset < length; offset += blobChunkBytes) {
      yield (offset, min(offset + blobChunkBytes, length));
    }
  }

  Future<Uint8List> _readExact(int length) async {
    while (_buffer.length < length) {
      final hasNext = await _iterator.moveNext().timeout(readTimeout);
      if (!hasNext) throw const LanFrameException('connection closed');
      _buffer.add(_iterator.current);
    }
    final all = _buffer.takeBytes();
    final result = Uint8List.sublistView(all, 0, length);
    if (all.length > length) _buffer.add(all.sublist(length));
    return Uint8List.fromList(result);
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    Object? cancelError;
    try {
      await _iterator.cancel();
    } catch (error) {
      cancelError = error;
    }
    await socket.close();
    if (cancelError != null) throw cancelError;
  }
}
