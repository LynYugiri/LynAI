import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lynai/models/cloud_data.dart';
import 'package:lynai/models/sync_change.dart';
import 'package:lynai/services/cloud_management_coordinator.dart';
import 'package:lynai/services/lan_sync_coordinator.dart';
import 'package:lynai/services/sync_service.dart';

void main() {
  test(
    'canonical sync v1 fixture matches client encoders and parsers',
    () async {
      final fixture = Map<String, dynamic>.from(
        jsonDecode(await File('doc/fixtures/sync-v1.json').readAsString())
            as Map,
      );

      final crypto = _map(fixture['cryptography']);
      final message = RemoteSyncService.buildSyncRequestMessage(
        protocolVersion: 1,
        userId: crypto['userId'] as String,
        sessionId: crypto['sessionId'] as String,
        deviceId: crypto['deviceId'] as String,
        requestId: crypto['requestId'] as String,
        timestamp: crypto['timestampMs'] as int,
        method: 'POST',
        target: crypto['canonicalTarget'] as String,
        bodySha256: _hex(crypto['bodySha256'] as String),
        expectedGeneration: crypto['expectedGeneration'] as int,
      );
      final keyPair = await Ed25519().newKeyPairFromSeed(
        _hex(crypto['seedHex'] as String),
      );
      final signature = await Ed25519().sign(message, keyPair: keyPair);
      expect(_hexString(message), crypto['messageHex']);
      expect(
        base64UrlEncode(signature.bytes).replaceAll('=', ''),
        crypto['signatureBase64Url'],
      );

      final upload = _map(fixture['upload']);
      final request = _map(upload['request']);
      final changes = (request['changes'] as List)
          .map((raw) {
            final change = _map(raw);
            return SyncChangeRecord(
              changeId: change['changeId'] as String,
              deviceId: 'local-audit-only',
              clientCreatedAt: DateTime.parse(
                change['clientCreatedAt'] as String,
              ),
              mutationVersion: 1,
              table: change['table'] as String,
              op: change['op'] as String,
              recordId: change['recordId'] as String,
              data: change['data'] == null ? null : _map(change['data']),
            );
          })
          .toList(growable: false);
      final body = RemoteSyncService.encodeChangesRequest(
        changes,
        generation: request['expectedGeneration'] as int,
      );
      expect(utf8.decode(body), upload['exactBodyUtf8']);
      expect(sha256.convert(body).toString(), upload['bodySha256']);
      expect(
        (_map(jsonDecode(utf8.decode(body)))['changes'] as List)
            .cast<Map>()
            .every((change) => !change.containsKey('deviceId')),
        isTrue,
      );

      final status = CloudIndexStatus.fromJson(_map(fixture['status']));
      expect(status.generation, 1);
      expect(status.indexRevision, 2);
      expect(status.capabilities.operationAck, isTrue);
      expect(status.capabilities.webSearch, isFalse);
      final pull = _map(fixture['pullPage']);
      final pulledChanges = (pull['changes'] as List)
          .map((raw) => SyncChange.fromJson(_map(raw)))
          .toList(growable: false);
      expect(pulledChanges.map((change) => change.seq), [1, 2]);
      expect(pull['nextSince'], pulledChanges.last.seq);
      expect(pull['globalLatestSeq'], pull['latestSeq']);

      final purgeOperation = CloudManagementOperation.fromJson(
        _map(_map(_map(fixture['selectivePurge'])['result'])['operation']),
      );
      expect(purgeOperation.kind, 'selective');
      expect(purgeOperation.generation, 2);
      expect(purgeOperation.indexRevision, 3);
      final ack = _map(fixture['operationAck']);
      expect(
        CloudManagementCoordinator.requestIdForAck(
          ack['scope'] as String,
          purgeOperation,
          purgeOperation.generation,
        ),
        ack['requestId'],
      );
      expect(_map(ack['request'])['operationId'], purgeOperation.id);

      final conflicts = _map(fixture['conflicts']);
      expect(
        _map(_map(conflicts['generation'])['body'])['code'],
        'generation_mismatch',
      );
      expect(
        _map(_map(conflicts['replay'])['body'])['code'],
        'replay_conflict',
      );
      expect(
        _map(_map(conflicts['indexRevision'])['body'])['code'],
        'index_revision_conflict',
      );
      final blob = _map(
        (_map(_map(fixture['blobs'])['listPage'])['blobs'] as List).single,
      );
      expect(BlobInfo.fromJson(blob).size, 17);
      expect(
        blob['sha256'],
        sha256.convert(utf8.encode('sync fixture blob')).toString(),
      );

      final lanChange = LanSyncCoordinator.parseLanChange(
        _map(
          _map(_map(fixture['clientOnlyExtensions'])['lanLineage'])['change'],
        ),
      );
      expect(lanChange.lineage, 'dataset-fixture-1');
      expect(request.toString(), isNot(contains('lineage')));
    },
  );
}

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map);

List<int> _hex(String value) => [
  for (var offset = 0; offset < value.length; offset += 2)
    int.parse(value.substring(offset, offset + 2), radix: 16),
];

String _hexString(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
