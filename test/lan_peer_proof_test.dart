import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/device_identity_service.dart';
import 'package:lynai/services/lan_peer_proof_service.dart';
import 'package:lynai/services/secret_store.dart';

void main() {
  test('peer proof binds identity, session, and both nonces', () async {
    final identity = DeviceIdentityService(secretStore: InMemorySecretStore());
    final service = LanPeerProofService(identity);
    final local = await identity.initialize();
    final remoteIdentity = DeviceIdentityService(
      secretStore: InMemorySecretStore(),
    );
    final remote = await remoteIdentity.initialize();
    final proof = await service.create(
      sessionId: 'session',
      localNonce: 'local',
      remoteNonce: 'remote',
      purpose: 'sync',
      signerRole: 'initiator',
      initiatorDeviceId: local.deviceId,
      initiatorPublicKey: local.publicKey,
      responderDeviceId: remote.deviceId,
      responderPublicKey: remote.publicKey,
    );
    expect(
      await service.verify(
        proof,
        expectedSessionId: 'session',
        expectedLocalNonce: 'local',
        expectedRemoteNonce: 'remote',
        expectedPurpose: 'sync',
        expectedSignerRole: 'initiator',
        initiatorDeviceId: local.deviceId,
        initiatorPublicKey: local.publicKey,
        responderDeviceId: remote.deviceId,
        responderPublicKey: remote.publicKey,
      ),
      isTrue,
    );
    expect(
      await service.verify(
        proof,
        expectedSessionId: 'other',
        expectedLocalNonce: 'local',
        expectedRemoteNonce: 'remote',
        expectedPurpose: 'sync',
        expectedSignerRole: 'initiator',
        initiatorDeviceId: local.deviceId,
        initiatorPublicKey: local.publicKey,
        responderDeviceId: remote.deviceId,
        responderPublicKey: remote.publicKey,
      ),
      isFalse,
    );
    final initiatorSas = service.sas(
      sessionId: 'session',
      purpose: 'sync',
      initiatorDeviceId: local.deviceId,
      initiatorPublicKey: local.publicKey,
      initiatorNonce: 'local',
      responderDeviceId: remote.deviceId,
      responderPublicKey: remote.publicKey,
      responderNonce: 'remote',
    );
    final responderSas = service.sas(
      sessionId: 'session',
      purpose: 'sync',
      initiatorDeviceId: local.deviceId,
      initiatorPublicKey: local.publicKey,
      initiatorNonce: 'local',
      responderDeviceId: remote.deviceId,
      responderPublicKey: remote.publicKey,
      responderNonce: 'remote',
    );
    expect(initiatorSas, responderSas);
  });
}
