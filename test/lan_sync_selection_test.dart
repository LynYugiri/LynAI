import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/lan_peer.dart';
import 'package:lynai/models/sync_data_selection.dart';
import 'package:lynai/services/lan_sync_coordinator.dart';
import 'package:lynai/services/lan_sync_storage.dart';

void main() {
  test('selection serialization is stable and unknown values are ignored', () {
    final selection = SyncDataSelection.fromJson([
      'tasks',
      'conversations',
      'unknown',
    ]);

    expect(selection.toJson(), ['conversations', 'tasks']);
    expect(
      SyncDataSelection.fromJson(
        selection.toJson(),
      ).hasSameCategories(selection),
      isTrue,
    );
  });

  test('legacy peer without selection uses defaults', () {
    final peer = LanPeer.fromJson(
      jsonDecode(
              jsonEncode(
                LanPeer(
                  deviceId: 'device-a',
                  publicKey: List.filled(32, 1),
                  spkiSha256: 'a' * 64,
                  displayName: 'Device A',
                  trustedAt: DateTime.utc(2030),
                  certificateExpiresAt: DateTime.utc(2031),
                ).toJson(),
              ),
            )
            as Map<String, dynamic>
        ..remove('syncSelection'),
    );

    expect(
      peer.syncSelection.hasSameCategories(SyncDataSelection.defaults),
      isTrue,
    );
  });

  test('attachment metadata is allowed without static resource blobs', () {
    const selection = SyncDataSelection({SyncDataCategory.conversations});

    expect(
      SyncDataRegistry.allowsChange(selection, 'message_attachments', const {
        'resourceId': 'resource-a',
      }),
      isTrue,
    );
    expect(
      SyncDataRegistry.allowsChange(selection, 'resources', const {
        'role': 'message_attachment',
      }),
      isFalse,
    );
  });

  test('recycle-bin delete uses its preserved category for selection', () {
    const conversations = SyncDataSelection({SyncDataCategory.conversations});
    const notes = SyncDataSelection({SyncDataCategory.notes});
    const hint = {'category': 'conversations', 'type': 'conversation'};

    expect(
      SyncDataRegistry.allowsChange(
        conversations,
        'recycle_bin',
        SyncDataRegistry.selectionData(null, hint),
      ),
      isTrue,
    );
    expect(
      SyncDataRegistry.allowsChange(
        notes,
        'recycle_bin',
        SyncDataRegistry.selectionData(null, hint),
      ),
      isFalse,
    );
  });

  test('actual recycle-bin category values map to sync categories', () {
    expect(
      SyncDataRegistry.categoryForChange('recycle_bin', const {
        'category': 'todos',
        'type': 'task',
      }),
      SyncDataCategory.tasks,
    );
    expect(
      SyncDataRegistry.categoryForChange('recycle_bin', const {
        'category': 'plugin:demo:data',
        'type': 'plugin.data',
      }),
      SyncDataCategory.plugins,
    );
  });

  test('exact acknowledgement rejects duplicates and mismatched IDs', () {
    LanSyncCoordinator.validateExactAcknowledgement(
      const ['a', 'b'],
      const ['b', 'a'],
    );
    expect(
      () => LanSyncCoordinator.validateExactAcknowledgement(
        const ['a', 'b'],
        const ['a', 'a'],
      ),
      throwsStateError,
    );
    expect(
      () => LanSyncCoordinator.validateExactAcknowledgement(
        const ['a', 'b'],
        const ['a', 'c'],
      ),
      throwsStateError,
    );
  });

  test('LAN batching is deterministic and bounded', () {
    final batches = lanSyncBatches(List.generate(2501, (index) => index), 1000);

    expect(batches.map((batch) => batch.length), [1000, 1000, 501]);
    expect(
      batches.expand((batch) => batch),
      orderedEquals(List.generate(2501, (index) => index)),
    );
  });

  test(
    'LAN change parsing accepts optional lineage and rejects malformed rows',
    () {
      final valid = {
        'changeId': 'change-a',
        'deviceId': 'device-a',
        'clientCreatedAt': '2026-07-28T00:00:00Z',
        'table': 'tasks',
        'op': 'upsert',
        'recordId': 'task-a',
        'data': {'id': 'task-a'},
        'lineage': 'dataset-a',
      };
      expect(LanSyncCoordinator.parseLanChange(valid).lineage, 'dataset-a');
      expect(
        () => LanSyncCoordinator.parseLanChange({
          ...valid,
          'data': {'id': 'other'},
        }),
        throwsStateError,
      );
      expect(
        () => LanSyncCoordinator.parseLanChange({...valid, 'unknown': true}),
        throwsStateError,
      );
      expect(
        () => LanSyncCoordinator.parseLanChange({...valid, 'op': 'delete'}),
        throwsStateError,
      );
      expect(
        () => LanSyncCoordinator.parseLanChange({
          ...valid,
          'op': 'delete',
          'data': null,
        }),
        throwsStateError,
      );
    },
  );
}
