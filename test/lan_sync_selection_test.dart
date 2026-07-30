import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/lan_peer.dart';
import 'package:lynai/models/knowledge_category.dart';
import 'package:lynai/models/sync_change.dart';
import 'package:lynai/models/sync_data_selection.dart';
import 'package:lynai/repositories/lan_peer_repository.dart';
import 'package:lynai/services/device_identity_service.dart';
import 'package:lynai/services/lan_mdns_service.dart';
import 'package:lynai/services/lan_secret_transfer_service.dart';
import 'package:lynai/services/lan_secure_transport.dart';
import 'package:lynai/services/lan_sync_coordinator.dart';
import 'package:lynai/services/lan_sync_storage.dart';
import 'package:lynai/services/lan_tls_certificate_service.dart';
import 'package:lynai/services/secret_store.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:sqlite3/sqlite3.dart';

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

  test(
    'legacy knowledge_settings global is accepted inbound, applied and never outbound',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_lan_legacy_knowledge_settings_',
      );
      final storage = StorageV2Service(rootDirectory: root);
      final lan = LanSyncStorage(
        storage: storage,
        readPluginBlob: (_) async => const [],
        hasPluginBlob: (_) async => false,
        installPluginBlob: (_, _) async {},
      );
      try {
        await lan.activate('local-device');
        final change = {
          'changeId': 'legacy-settings-change',
          'deviceId': 'legacy-device',
          'clientCreatedAt': '2026-07-29T00:00:00Z',
          'table': 'knowledge_settings',
          'op': 'upsert',
          'recordId': 'global',
          'data': {
            'id': 'global',
            'defaultKnowledgeBaseId': 'base',
            'defaultCategoryId': 'category',
            'updatedAt': '2026-07-29T00:00:00Z',
          },
        };
        final secrets = InMemorySecretStore();
        final identity = DeviceIdentityService(secretStore: secrets);
        final coordinator = LanSyncCoordinator(
          identityService: identity,
          peerRepository: LanPeerRepository(
            secretStore: secrets,
            storage: storage,
          ),
          certificateService: LanTlsCertificateService(
            secretStore: secrets,
            identityService: identity,
          ),
          mdnsService: LanMdnsService(),
          syncStorage: lan,
          secretTransferService: LanSecretTransferService(secrets),
          confirmPairing: (_) async => const LanPairingDecision.rejected(),
          confirmPolicyProposal: (_, _, _) async => null,
          readModels: () => const [],
        );
        final transport = _FakeLanFrameTransport([
          _frame('manifest', {
            'changes': [change],
            'blobs': const [],
            'more': false,
          }),
          _frame('changes-end', const {}),
        ]);

        expect(
          await coordinator.receiveChangePageForTest(
            transport,
            'legacy-device',
            const SyncDataSelection({}),
          ),
          isFalse,
        );
        expect(transport.sent.map((item) => item.$1), ['blob-request', 'ack']);
        expect(transport.sent[0].$2['hashes'], isEmpty);
        expect(transport.sent[1].$2['changeIds'], ['legacy-settings-change']);

        expect(await lan.changesForPeer('other-device'), isEmpty);
        expect(await storage.syncSince(LanSyncStorage.scope), 0);
        final database = sqlite3.open('${root.path}/storage_v2/app.db');
        try {
          expect(
            database.select(
              "SELECT change_id FROM transport_change_receipts WHERE change_id = 'legacy-settings-change'",
            ),
            hasLength(1),
          );
          expect(
            database.select(
              "SELECT change_id FROM transport_peer_acks WHERE peer_device_id = 'legacy-device' AND change_id = 'legacy-settings-change'",
            ),
            hasLength(1),
          );
          expect(
            database.select(
              "SELECT change_id FROM transport_change_heads WHERE table_name = 'knowledge_settings'",
            ),
            hasLength(1),
          );
        } finally {
          database.close();
        }
      } finally {
        await storage.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test('legacy knowledge_settings non-global is rejected inbound', () {
    final change = SyncChange(
      seq: 1,
      changeId: 'legacy-settings-change',
      deviceId: 'legacy-device',
      clientCreatedAt: DateTime.utc(2026, 7, 29),
      table: 'knowledge_settings',
      op: 'upsert',
      recordId: 'not-global',
      data: const {'id': 'not-global'},
    );

    expect(
      () => LanSyncCoordinator.validateInboundChanges([change]),
      throwsStateError,
    );
  });

  test('LAN receive materializes a conflicting knowledge alias', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_lan_knowledge_alias_',
    );
    final storage = StorageV2Service(rootDirectory: root);
    final lan = LanSyncStorage(
      storage: storage,
      readPluginBlob: (_) async => const [],
      hasPluginBlob: (_) async => false,
      installPluginBlob: (_, _) async {},
    );
    try {
      await storage.writeDataFile('knowledge.json', {
        'knowledgeBases': [
          _knowledgeBase(
            builtInProperNounKnowledgeBaseModelId,
            'Built-in base',
          ),
        ],
        'categories': [
          _knowledgeCategory(
            builtInProperNounCategoryModelId,
            builtInProperNounKnowledgeBaseModelId,
            'Built-in category',
          ),
        ],
      });
      await lan.activate('local-device');
      final secrets = InMemorySecretStore();
      final identity = DeviceIdentityService(secretStore: secrets);
      final coordinator = LanSyncCoordinator(
        identityService: identity,
        peerRepository: LanPeerRepository(
          secretStore: secrets,
          storage: storage,
        ),
        certificateService: LanTlsCertificateService(
          secretStore: secrets,
          identityService: identity,
        ),
        mdnsService: LanMdnsService(),
        syncStorage: lan,
        secretTransferService: LanSecretTransferService(secrets),
        confirmPairing: (_) async => const LanPairingDecision.rejected(),
        confirmPolicyProposal: (_, _, _) async => null,
        readModels: () => const [],
      );
      final transport = _FakeLanFrameTransport([
        _frame('manifest', {
          'changes': [
            _lanChange(
              'lan-base-change',
              'knowledge_bases',
              'remote-base',
              _knowledgeBase('remote-base', 'Remote base'),
            ),
            _lanChange(
              'lan-category-change',
              'knowledge_categories',
              'remote-category',
              _knowledgeCategory(
                'remote-category',
                'remote-base',
                'Remote category',
                updatedAt: '2026-01-02T00:00:00Z',
              ),
            ),
          ],
          'blobs': const [],
          'more': false,
        }),
        _frame('changes-end', const {}),
      ]);

      await coordinator.receiveChangePageForTest(
        transport,
        'remote-device',
        const SyncDataSelection({SyncDataCategory.knowledge}),
      );

      final categories =
          ((await storage.loadDataFile('knowledge.json'))['categories'] as List)
              .cast<Map>();
      Map category(String id) =>
          categories.singleWhere((row) => row['id'] == id);
      expect(
        category(builtInProperNounCategoryModelId)['alias'],
        properNounKnowledgeCategoryAlias,
      );
      expect(
        category('remote-category'),
        containsPair('name', 'Remote category'),
      );
      expect(
        category('remote-category'),
        containsPair('knowledgeBaseId', 'remote-base'),
      );
      expect(
        category('remote-category'),
        containsPair('updatedAt', '2026-01-02T00:00:00Z'),
      );
      expect(
        category('remote-category')['alias'],
        'proper_noun_remote_category',
      );
      expect(await storage.syncSince(LanSyncStorage.scope), 0);
      final database = sqlite3.open('${root.path}/storage_v2/app.db');
      try {
        expect(
          database
              .select(
                "SELECT change_id FROM transport_change_receipts WHERE change_id IN ('lan-base-change', 'lan-category-change')",
              )
              .map((row) => row['change_id']),
          containsAll({'lan-base-change', 'lan-category-change'}),
        );
        expect(
          database
              .select(
                "SELECT change_id FROM transport_peer_acks WHERE peer_device_id = 'remote-device'",
              )
              .map((row) => row['change_id']),
          containsAll({'lan-base-change', 'lan-category-change'}),
        );
      } finally {
        database.close();
      }
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}

Map<String, dynamic> _knowledgeBase(String id, String name) => {
  'id': id,
  'name': name,
  'enabled': true,
  'sortOrder': 0,
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-01T00:00:00Z',
};

Map<String, dynamic> _knowledgeCategory(
  String id,
  String baseId,
  String name, {
  String updatedAt = '2026-01-01T00:00:00Z',
}) => {
  'id': id,
  'knowledgeBaseId': baseId,
  'name': name,
  'alias': properNounKnowledgeCategoryAlias,
  'annotationRule': 'remote rule',
  'explanationPrompt': 'remote prompt',
  'colorValue': 123,
  'autoAnnotate': true,
  'modelConfigId': 'remote-model',
  'enabled': true,
  'sortOrder': 7,
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': updatedAt,
};

Map<String, dynamic> _lanChange(
  String changeId,
  String table,
  String recordId,
  Map<String, dynamic> data,
) => {
  'changeId': changeId,
  'deviceId': 'remote-device',
  'clientCreatedAt': '2026-01-02T00:00:00Z',
  'table': table,
  'op': 'upsert',
  'recordId': recordId,
  'data': data,
};

LanFrame _frame(String type, Map<String, dynamic> body) => LanFrame(
  type: type,
  sessionId: 'session',
  counter: 1,
  purpose: 'sync',
  role: 'initiator',
  body: body,
);

class _FakeLanFrameTransport implements LanFrameTransport {
  _FakeLanFrameTransport(this.frames);

  final List<LanFrame> frames;
  final List<(String, Map<String, dynamic>)> sent = [];

  @override
  Future<LanFrame> receive({
    required Set<String> expectedTypes,
    Set<String>? expectedPurposes,
  }) async {
    final frame = frames.removeAt(0);
    if (!expectedTypes.contains(frame.type)) {
      throw StateError('unexpected test frame ${frame.type}');
    }
    return frame;
  }

  @override
  Future<void> send(String type, Map<String, dynamic> body) async {
    sent.add((type, body));
  }
}
