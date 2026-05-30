import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/model_config.dart';
import '../services/storage_v2_service.dart';
import 'app_storage_state.dart';

class ModelConfigLoadResult {
  const ModelConfigLoadResult({
    required this.models,
    required this.usingStorageV2,
  });

  final List<ModelConfig> models;
  final bool usingStorageV2;
}

class ModelConfigRepository {
  factory ModelConfigRepository({
    StorageV2Service? storageV2,
    AppStorageStateRepository? storageState,
  }) {
    final storage = storageV2 ?? StorageV2Service();
    return ModelConfigRepository._(
      storage,
      storageState ?? AppStorageStateRepository(storageV2: storage),
    );
  }

  ModelConfigRepository._(this._storageV2, this._storageState);

  static const _storageKey = 'model_configs';

  final StorageV2Service _storageV2;
  final AppStorageStateRepository _storageState;

  Future<ModelConfigLoadResult> load() async {
    final usingStorageV2 = await _storageState.isStorageV2Active();
    if (usingStorageV2) {
      final json = await _storageV2.loadDataFile('model_configs.json');
      return ModelConfigLoadResult(
        models: _parseModels(json['models']),
        usingStorageV2: true,
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString == null) {
      return const ModelConfigLoadResult(models: [], usingStorageV2: false);
    }
    return ModelConfigLoadResult(
      models: _parseModels(jsonDecode(jsonString)),
      usingStorageV2: false,
    );
  }

  Future<void> save(
    List<ModelConfig> models, {
    required bool usingStorageV2,
  }) async {
    if (usingStorageV2 || await _storageState.isStorageV2Active()) {
      await _storageV2.writeDataFile('model_configs.json', {
        'models': models.map((model) => model.toJson()).toList(),
      });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(models.map((model) => model.toJson()).toList()),
    );
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
