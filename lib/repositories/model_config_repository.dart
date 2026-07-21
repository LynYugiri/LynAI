import 'package:flutter/foundation.dart';

import '../models/model_config.dart';
import '../services/secret_store.dart';
import '../services/storage_v2_service.dart';

class ModelConfigLoadResult {
  const ModelConfigLoadResult({
    required this.models,
    required this.usingStorageV2,
    this.pendingManagedModelIdMigrations = const {},
  });

  final List<ModelConfig> models;
  final bool usingStorageV2;
  final Map<String, String> pendingManagedModelIdMigrations;
}

class ModelConfigRepository {
  factory ModelConfigRepository({
    StorageV2Service? storageV2,
    SecretStore? secretStore,
  }) {
    final storage = storageV2 ?? StorageV2Service();
    return ModelConfigRepository._(
      storage,
      secretStore ?? InMemorySecretStore(),
    );
  }

  ModelConfigRepository._(this._storageV2, this._secretStore);

  final StorageV2Service _storageV2;
  final SecretStore _secretStore;
  Set<String> _persistedSecretRefs = const {};

  Future<ModelConfigLoadResult> load() async {
    final json = await _storageV2.loadDataFile('model_configs.json');
    final rawModels = json['models'] as List<dynamic>? ?? const [];
    final models = <ModelConfig>[];
    var migratedPlaintext = false;
    for (final item in rawModels) {
      try {
        if (item is! Map) continue;
        final raw = Map<String, dynamic>.from(item);
        final id = raw['id'] as String;
        final expectedRef = ModelConfig.secretReferenceForId(id);
        final legacyApiKey = raw['apiKey'] as String? ?? '';
        var apiKey = legacyApiKey;
        if (legacyApiKey.isNotEmpty) {
          await _secretStore.write(expectedRef, legacyApiKey);
          migratedPlaintext = true;
        } else {
          apiKey = await _secretStore.read(expectedRef) ?? '';
        }
        raw
          ..remove('apiKey')
          ..['apiKeySecretRef'] = expectedRef;
        models.add(
          ModelConfig.fromJson(
            raw,
          ).copyWith(apiKey: apiKey, apiKeySecretRef: expectedRef),
        );
      } catch (e) {
        debugPrint('跳过损坏的模型配置: $e');
      }
    }
    _persistedSecretRefs = models.map((model) => model.apiKeySecretRef).toSet();
    if (migratedPlaintext) {
      await _storageV2.writeDataFile('model_configs.json', {
        'models': models.map((model) => model.toJson()).toList(),
        if (json['pendingManagedModelIdMigrations'] is Map)
          'pendingManagedModelIdMigrations':
              json['pendingManagedModelIdMigrations'],
      });
    }
    final pending = <String, String>{};
    final rawPending = json['pendingManagedModelIdMigrations'];
    if (rawPending is Map) {
      for (final entry in rawPending.entries) {
        if (entry.key is String && entry.value is String) {
          pending[entry.key as String] = entry.value as String;
        }
      }
    }
    return ModelConfigLoadResult(
      models: models,
      usingStorageV2: true,
      pendingManagedModelIdMigrations: pending,
    );
  }

  Future<void> save(
    List<ModelConfig> models, {
    required bool usingStorageV2,
    Map<String, String> pendingManagedModelIdMigrations = const {},
  }) async {
    final nextRefs = <String>{};
    for (final model in models) {
      final expectedRef = ModelConfig.secretReferenceForId(model.id);
      nextRefs.add(expectedRef);
      if (model.apiKey.isNotEmpty) {
        await _secretStore.write(expectedRef, model.apiKey);
      }
    }
    await _storageV2.writeDataFile('model_configs.json', {
      'models': models.map((model) {
        return model
            .copyWith(
              apiKeySecretRef: ModelConfig.secretReferenceForId(model.id),
            )
            .toJson();
      }).toList(),
      if (pendingManagedModelIdMigrations.isNotEmpty)
        'pendingManagedModelIdMigrations': pendingManagedModelIdMigrations,
    });
    for (final model in models.where((model) => model.apiKey.isEmpty)) {
      await _secretStore.delete(ModelConfig.secretReferenceForId(model.id));
    }
    for (final staleRef in _persistedSecretRefs.difference(nextRefs)) {
      await _secretStore.delete(staleRef);
    }
    _persistedSecretRefs = nextRefs;
  }
}
