import 'package:flutter/foundation.dart';

import '../models/model_config.dart';
import '../services/storage_v2_service.dart';

class ModelConfigLoadResult {
  const ModelConfigLoadResult({
    required this.models,
    required this.usingStorageV2,
  });

  final List<ModelConfig> models;
  final bool usingStorageV2;
}

class ModelConfigRepository {
  factory ModelConfigRepository({StorageV2Service? storageV2}) {
    final storage = storageV2 ?? StorageV2Service();
    return ModelConfigRepository._(storage);
  }

  ModelConfigRepository._(this._storageV2);

  final StorageV2Service _storageV2;

  Future<ModelConfigLoadResult> load() async {
    final json = await _storageV2.loadDataFile('model_configs.json');
    return ModelConfigLoadResult(
      models: _parseModels(json['models']),
      usingStorageV2: true,
    );
  }

  Future<void> save(
    List<ModelConfig> models, {
    required bool usingStorageV2,
  }) async {
    await _storageV2.writeDataFile('model_configs.json', {
      'models': models.map((model) => model.toJson()).toList(),
    });
  }

  static List<ModelConfig> _parseModels(Object? raw) {
    final models = <ModelConfig>[];
    for (final item in raw as List<dynamic>? ?? const []) {
      try {
        if (item is Map) {
          models.add(ModelConfig.fromJson(Map<String, dynamic>.from(item)));
        }
      } catch (e) {
        debugPrint('跳过损坏的模型配置: $e');
      }
    }
    return models;
  }
}
