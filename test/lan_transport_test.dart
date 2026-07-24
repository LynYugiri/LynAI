import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/lan_sync_coordinator.dart';
import 'package:lynai/services/lan_secure_transport.dart';

void main() {
  test('framed transport enforces body and frame limits', () {
    expect(
      () => LanSecureTransport.encodeFrame(
        type: 'changes',
        sessionId: 'session',
        counter: 1,
        purpose: 'sync',
        role: 'initiator',
        body: {'value': 'x' * 101},
        maxBodyBytes: 100,
      ),
      throwsA(isA<LanFrameException>()),
    );
    expect(
      () => LanSecureTransport.encodeFrame(
        type: 'changes',
        sessionId: 'session',
        counter: 1,
        purpose: 'sync',
        role: 'initiator',
        body: {'value': 'x' * 80},
        maxBodyBytes: 1000,
        maxFrameBytes: 64,
      ),
      throwsA(isA<LanFrameException>()),
    );
  });

  test('frame encoding preserves the existing JSON wire shape', () {
    final frame = LanSecureTransport.encodeFrame(
      type: 'blob-chunk',
      sessionId: 'session',
      counter: 3,
      purpose: 'sync',
      role: 'initiator',
      body: const {'sha256': 'abc', 'index': 2, 'bytes': 'AQI='},
    );
    final length = ByteData.sublistView(frame, 0, 4).getUint32(0);
    final decoded = jsonDecode(utf8.decode(frame.sublist(4)));

    expect(length, frame.length - 4);
    expect(decoded, {
      'type': 'blob-chunk',
      'sessionId': 'session',
      'counter': 3,
      'purpose': 'sync',
      'role': 'initiator',
      'body': const {'sha256': 'abc', 'index': 2, 'bytes': 'AQI='},
    });
  });

  test('bad ALPN is rejected before consuming a connection slot', () {
    expect(LanSyncCoordinator.admitsConnection(null, 0), isFalse);
    expect(LanSyncCoordinator.admitsConnection('http/1.1', 0), isFalse);
    expect(LanSyncCoordinator.admitsConnection('lynai-lan/1', 7), isTrue);
    expect(LanSyncCoordinator.admitsConnection('lynai-lan/1', 8), isFalse);
  });

  test('connection slot is released when transport cleanup fails', () async {
    var releases = 0;

    await expectLater(
      LanSyncCoordinator.closeAndReleaseConnection(
        close: () async => throw StateError('close failed'),
        release: () => releases++,
      ),
      throwsStateError,
    );

    expect(releases, 1);
  });

  test('outbound retries close every established connection once', () async {
    final connections = <_TestConnection>[];

    await expectLater(
      LanSyncCoordinator.runOutboundAttempts(
        const ['first', 'second'],
        connect: (address) async {
          final connection = _TestConnection(address);
          connections.add(connection);
          return connection;
        },
        run: (connection) async {
          throw StateError('injected ${connection.address} failure');
        },
        close: (connection) async => connection.closeCount++,
        failureMessage: 'all attempts failed',
      ),
      throwsStateError,
    );

    expect(connections.map((connection) => connection.closeCount), [1, 1]);
  });

  test('outbound success is closed and stops retries', () async {
    final connections = <_TestConnection>[];

    await LanSyncCoordinator.runOutboundAttempts(
      const ['first', 'second', 'unused'],
      connect: (address) async {
        final connection = _TestConnection(address);
        connections.add(connection);
        return connection;
      },
      run: (connection) async {
        if (connection.address == 'first') throw StateError('retry');
      },
      close: (connection) async => connection.closeCount++,
      failureMessage: 'all attempts failed',
    );

    expect(connections.map((connection) => connection.address), [
      'first',
      'second',
    ]);
    expect(connections.map((connection) => connection.closeCount), [1, 1]);
  });

  test(
    'outbound cleanup failure retries instead of reporting success',
    () async {
      final connections = <_TestConnection>[];

      await LanSyncCoordinator.runOutboundAttempts(
        const ['first', 'second'],
        connect: (address) async {
          final connection = _TestConnection(address);
          connections.add(connection);
          return connection;
        },
        run: (_) async {},
        close: (connection) async {
          connection.closeCount++;
          if (connection.address == 'first') throw StateError('close failed');
        },
        failureMessage: 'all attempts failed',
      );

      expect(connections.map((connection) => connection.closeCount), [1, 1]);
    },
  );

  test('64 MiB blob is split into bounded frames without allocation', () {
    const size = 64 * 1024 * 1024;
    final ranges = LanSecureTransport.blobChunkRanges(size).toList();

    expect(ranges.first, (0, LanSecureTransport.blobChunkBytes));
    expect(ranges.last.$2, size);
    expect(
      ranges.every(
        (range) => range.$2 - range.$1 <= LanSecureTransport.blobChunkBytes,
      ),
      isTrue,
    );
    expect(
      () => LanSecureTransport.blobChunkRanges(size + 1).toList(),
      throwsA(isA<LanFrameException>()),
    );
  });
}

class _TestConnection {
  _TestConnection(this.address);

  final String address;
  int closeCount = 0;
}
