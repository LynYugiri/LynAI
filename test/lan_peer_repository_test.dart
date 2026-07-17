import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/lan_peer.dart';
import 'package:lynai/repositories/lan_peer_repository.dart';
import 'package:lynai/services/secret_store.dart';

void main() {
  test('pairing nonce is consumed atomically once', () async {
    final repository = LanPeerRepository(secretStore: InMemorySecretStore());
    final now = DateTime.utc(2030);
    await repository.savePairingSession(
      LanPairingSession(
        nonce: 'one-time-nonce',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 3)),
      ),
    );
    final results = await Future.wait([
      repository.consumePairingNonce('one-time-nonce', 'peer-a', now: now),
      repository.consumePairingNonce('one-time-nonce', 'peer-b', now: now),
    ]);
    expect(results.where((value) => value), hasLength(1));
  });

  test('dedup, per-peer acknowledgements, and revocation persist', () async {
    final store = InMemorySecretStore();
    final repository = LanPeerRepository(secretStore: store);
    expect(await repository.markChangeApplied('change-1'), isTrue);
    expect(await repository.markChangeApplied('change-1'), isFalse);
    await repository.acknowledgeChanges('peer-a', ['change-1']);
    expect(await repository.acknowledgedChangeIds('peer-a'), {'change-1'});
    expect(await repository.acknowledgedChangeIds('peer-b'), isEmpty);

    await repository.trustPeer(
      LanPeer(
        deviceId: 'device-a',
        publicKey: List.filled(32, 1),
        spkiSha256: 'a' * 64,
        displayName: 'Device A',
        trustedAt: DateTime.utc(2030),
        certificateExpiresAt: DateTime.utc(2030, 4),
      ),
    );
    await repository.revokePeer('device-a', now: DateTime.utc(2030, 1, 2));
    expect((await repository.peer('device-a'))!.revoked, isTrue);
  });

  test('certificate renewal updates metadata without changing trust', () async {
    final repository = LanPeerRepository(secretStore: InMemorySecretStore());
    final oldExpiry = DateTime.utc(2029);
    final newExpiry = DateTime.utc(2031);
    await repository.trustPeer(
      LanPeer(
        deviceId: 'device-a',
        publicKey: List.filled(32, 1),
        spkiSha256: 'a' * 64,
        displayName: 'Device A',
        trustedAt: DateTime.utc(2028),
        certificateExpiresAt: oldExpiry,
      ),
    );

    await repository.updateCertificateExpiry('device-a', newExpiry);
    final peer = (await repository.peer('device-a'))!;

    expect(peer.certificateExpiresAt, newExpiry);
    expect(peer.spkiSha256, 'a' * 64);
    expect(peer.revoked, isFalse);
  });
}
