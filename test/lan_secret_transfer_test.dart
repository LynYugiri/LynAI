import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/repositories/model_config_repository.dart';
import 'package:lynai/services/lan_secret_transfer_service.dart';
import 'package:lynai/services/secret_store.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';

void main() {
  test('secret payload requires both one-use grants', () async {
    final store = InMemorySecretStore();
    final service = LanSecretTransferService(store);
    final model = ModelConfig(
      id: 'model-a',
      name: 'A',
      endpoint: 'https://example.test',
      apiKey: 'secret',
      modelName: 'a',
      apiType: 'openai',
      priority: 0,
    );
    final exported = await service.exportPayload([model]);
    expect(
      service.consumeAuthorization(
        peerDeviceId: 'peer-a',
        transferId: 'transfer-a',
        direction: 'send',
      ),
      isFalse,
    );
    service.authorize(
      peerDeviceId: 'peer-a',
      transferId: 'transfer-a',
      direction: 'send',
      now: DateTime.utc(2030),
    );
    expect(
      service.consumeAuthorization(
        peerDeviceId: 'peer-a',
        transferId: 'transfer-a',
        direction: 'receive',
        now: DateTime.utc(2030),
      ),
      isFalse,
    );
    expect(
      service.consumeAuthorization(
        peerDeviceId: 'peer-a',
        transferId: 'transfer-a',
        direction: 'send',
        now: DateTime.utc(2030),
      ),
      isTrue,
    );
    await service.importPayload(exported);
    expect(
      await store.read(ModelConfig.secretReferenceForId('model-a')),
      'secret',
    );
    expect(
      () => service.validatePayload({
        'device_identity.ed25519.private_key': 'forbidden',
      }),
      throwsFormatException,
    );
    expect(
      service.consumeAuthorization(
        peerDeviceId: 'peer-a',
        transferId: 'transfer-a',
        direction: 'send',
        now: DateTime.utc(2030),
      ),
      isFalse,
    );
  });

  test('forbidden and malformed secrets are rejected', () {
    final service = LanSecretTransferService(InMemorySecretStore());
    expect(
      () => service.validatePayload({
        'modelApiKeys': {'model': ''},
      }),
      throwsFormatException,
    );
    expect(
      () => service.validatePayload({
        'modelApiKeys': {'model': 'key'},
        'plugin_storage': {'token': 'nope'},
      }),
      throwsFormatException,
    );
  });

  test('received key reloads active models and survives later save', () async {
    final root = await Directory.systemTemp.createTemp('lynai_lan_secret_');
    final storage = StorageV2Service(rootDirectory: root);
    final secrets = InMemorySecretStore();
    try {
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
      final provider = ModelConfigProvider(
        repository: ModelConfigRepository(
          storageV2: storage,
          secretStore: secrets,
        ),
      );
      await provider.loadModels();
      await provider.replaceModels([
        ModelConfig(
          id: 'model-a',
          name: 'A',
          endpoint: 'https://example.test',
          apiKey: '',
          modelName: 'a',
          apiType: 'openai',
          priority: 0,
        ),
      ]);
      final transfer = LanSecretTransferService(
        secrets,
        onImported: () async {
          await provider.flushPendingSaves();
          await provider.loadModels();
        },
      );

      await transfer.importPayload({
        'modelApiKeys': {'model-a': 'received-secret'},
      });
      expect(provider.models.single.apiKey, 'received-secret');

      provider.updateModel(provider.models.single.copyWith(name: 'Updated'));
      await provider.flushPendingSaves();
      expect(
        await secrets.read(ModelConfig.secretReferenceForId('model-a')),
        'received-secret',
      );
    } finally {
      await storage.close();
      await root.delete(recursive: true);
    }
  });
}
