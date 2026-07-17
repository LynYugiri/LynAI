import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lynai/models/device_identity.dart';
import 'package:lynai/services/device_identity_service.dart';
import 'package:lynai/services/secret_store.dart';

void main() {
  test(
    'initialization is stable and device ID has the expected shape',
    () async {
      final store = InMemorySecretStore();
      final first = await DeviceIdentityService(
        secretStore: store,
      ).initialize();
      final second = await DeviceIdentityService(
        secretStore: store,
      ).initialize();

      expect(first.deviceId, matches(RegExp(r'^[a-z2-7]{52}$')));
      expect(first.deviceId, _base32(sha256.convert(first.publicKey).bytes));
      expect(first.publicKey, hasLength(32));
      expect(second.deviceId, first.deviceId);
      expect(second.publicKey, first.publicKey);
    },
  );

  test('sign creates a valid Ed25519 signature', () async {
    final service = DeviceIdentityService(secretStore: InMemorySecretStore());
    final identity = await service.initialize();
    final message = utf8.encode('signed payload');
    final signature = await service.sign(message);

    final valid = await Ed25519().verify(
      message,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(
          identity.publicKey,
          type: KeyPairType.ed25519,
        ),
      ),
    );
    expect(valid, isTrue);
  });

  test('account identities are scoped by backend origin and user ID', () async {
    final store = InMemorySecretStore();
    final service = DeviceIdentityService(secretStore: store);
    final firstScope = DeviceIdentityService.accountScope(
      'HTTPS://Example.com:443/api/path?ignored=1',
      ' user-1 ',
    );
    final equivalentScope = DeviceIdentityService.accountScope(
      'https://example.com/other',
      'user-1',
    );
    final otherUserScope = DeviceIdentityService.accountScope(
      'https://example.com',
      'user-2',
    );

    final first = await service.initialize(scope: firstScope);
    final equivalent = await DeviceIdentityService(
      secretStore: store,
    ).initialize(scope: equivalentScope);
    final otherUser = await service.initialize(scope: otherUserScope);

    expect(firstScope, 'account:https://example.com|user-1');
    expect(equivalent.deviceId, first.deviceId);
    expect(otherUser.deviceId, isNot(first.deviceId));
  });

  test('detects stored identity corruption instead of regenerating', () async {
    final store = InMemorySecretStore();
    await DeviceIdentityService(secretStore: store).initialize();
    await store.write(
      DeviceIdentityService.identityRecordSecretKey,
      'corrupted',
    );

    expect(
      DeviceIdentityService(secretStore: store).initialize,
      throwsA(isA<DeviceIdentityCorruptedException>()),
    );
  });

  test('migrates the legacy three-key identity into one record', () async {
    final source = InMemorySecretStore();
    final identity = await DeviceIdentityService(
      secretStore: source,
    ).initialize();
    final record =
        jsonDecode(
              (await source.read(
                DeviceIdentityService.identityRecordSecretKey,
              ))!,
            )
            as Map;
    final legacy = InMemorySecretStore({
      DeviceIdentityService.privateKeySecretKey: record['privateKey'] as String,
      DeviceIdentityService.publicKeySecretKey: record['publicKey'] as String,
      DeviceIdentityService.deviceIdSecretKey: record['deviceId'] as String,
    });

    final migrated = await DeviceIdentityService(
      secretStore: legacy,
    ).initialize();

    expect(migrated.deviceId, identity.deviceId);
    expect(
      await legacy.read(DeviceIdentityService.identityRecordSecretKey),
      isNotNull,
    );
    expect(
      await legacy.read(DeviceIdentityService.privateKeySecretKey),
      isNull,
    );
  });

  test('recovers a staged first write after restart', () async {
    final store = _FailingSecretStore(failWriteNumber: 2);
    await expectLater(
      DeviceIdentityService(secretStore: store).initialize(),
      throwsA(isA<StateError>()),
    );
    final staged = await store.read(
      DeviceIdentityService.identityStagingSecretKey,
    );
    expect(staged, isNotNull);

    store.failWriteNumber = null;
    final recovered = await DeviceIdentityService(
      secretStore: store,
    ).initialize();
    final decoded = jsonDecode(staged!) as Map;

    expect(recovered.deviceId, decoded['deviceId']);
    expect(
      await store.read(DeviceIdentityService.identityStagingSecretKey),
      isNull,
    );
  });

  test('valid committed identity wins over conflicting staging', () async {
    final store = InMemorySecretStore();
    final established = await DeviceIdentityService(
      secretStore: store,
    ).initialize();
    final otherStore = InMemorySecretStore();
    await DeviceIdentityService(secretStore: otherStore).initialize();
    await store.write(
      DeviceIdentityService.identityStagingSecretKey,
      (await otherStore.read(DeviceIdentityService.identityRecordSecretKey))!,
    );

    final restarted = await DeviceIdentityService(
      secretStore: store,
    ).initialize();

    expect(restarted.deviceId, established.deviceId);
  });
}

class _FailingSecretStore extends InMemorySecretStore {
  _FailingSecretStore({this.failWriteNumber});

  int? failWriteNumber;
  int _writes = 0;

  @override
  Future<void> write(String key, String value) async {
    _writes++;
    if (_writes == failWriteNumber) throw StateError('injected write failure');
    await super.write(key, value);
  }
}

String _base32(List<int> bytes) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
  final output = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final byte in bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      output.write(alphabet[(buffer >> bits) & 31]);
    }
  }
  if (bits > 0) output.write(alphabet[(buffer << (5 - bits)) & 31]);
  return output.toString();
}
