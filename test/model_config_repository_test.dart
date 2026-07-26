import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/repositories/model_config_repository.dart';
import 'package:lynai/services/secret_store.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';

void main() {
  test(
    'pending managed ID migrations survive save, load, and ack save',
    () async {
      final root = await Directory.systemTemp.createTemp('lynai_model_repo_');
      final storage = StorageV2Service(rootDirectory: root);
      try {
        await StorageV2UpgradeService(storageV2: storage).ensureReady();
        final repository = ModelConfigRepository(
          storageV2: storage,
          secretStore: InMemorySecretStore(),
        );
        final model = ModelConfig(
          id: '__lynai_relay_chat__',
          name: 'LynAI',
          endpoint: 'https://api.example.com/relay',
          apiKey: '',
          modelName: 'model-a',
          apiType: '',
          priority: 0,
          managed: true,
        );
        const pending = {
          '__lynai_relay_provider-1_chat__': '__lynai_relay_chat__',
        };

        await repository.save(
          [model],
          usingStorageV2: true,
          pendingManagedModelIdMigrations: pending,
        );
        expect(
          (await repository.load()).pendingManagedModelIdMigrations,
          pending,
        );

        await repository.save([model], usingStorageV2: true);
        expect(
          (await repository.load()).pendingManagedModelIdMigrations,
          isEmpty,
        );
      } finally {
        await storage.close();
        await root.delete(recursive: true);
      }
    },
  );
}
