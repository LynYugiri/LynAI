import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/model_config.dart';
import '../repositories/model_config_repository.dart';
import '../services/backend_client.dart';
import '../services/secret_store.dart';
import '../services/storage_v2_service.dart';

/// 管理所有模型配置和分类内优先级。
///
/// 模型按 `category` 分组，再按 `priority` 升序排列。一个 [ModelConfig]
/// 表示一个提供商配置，内部可以包含多个可启用的子模型。
class ModelConfigProvider extends ChangeNotifier {
  static const lynaiManagedIdPrefix = '__lynai_relay_';

  List<ModelConfig> _models = [];
  final _uuid = const Uuid();
  Future<void> _saveQueue = Future.value();
  Future<void> _pendingSave = Future.value();
  final ModelConfigRepository _repository;
  bool _usingStorageV2 = false;
  final Map<String, String> _pendingManagedModelIdMigrations = {};

  ModelConfigProvider({
    StorageV2Service? storageV2,
    SecretStore? secretStore,
    ModelConfigRepository? repository,
  }) : _repository =
           repository ??
           ModelConfigRepository(
             storageV2: storageV2,
             secretStore: secretStore,
           );

  /// 所有模型配置，按分类和优先级排序。
  List<ModelConfig> get models => List.unmodifiable(_models);
  bool get usingStorageV2 => _usingStorageV2;

  Future<void> flushPendingSaves() => _pendingSave;

  /// 返回待处理的 managed ID 迁移。所有引用持久化成功后再确认。
  Map<String, String> peekManagedModelIdMigrations() {
    if (_pendingManagedModelIdMigrations.isEmpty) return const {};
    return Map<String, String>.unmodifiable(_pendingManagedModelIdMigrations);
  }

  Future<void> ackManagedModelIdMigrations(
    Map<String, String> migrations,
  ) async {
    final remaining = Map<String, String>.from(
      _pendingManagedModelIdMigrations,
    );
    for (final entry in migrations.entries) {
      if (remaining[entry.key] == entry.value) {
        remaining.remove(entry.key);
      }
    }
    await _queueSaveModels(pendingMigrations: remaining);
    _pendingManagedModelIdMigrations
      ..clear()
      ..addAll(remaining);
  }

  Future<void> replaceModels(List<ModelConfig> models) async {
    _models = List<ModelConfig>.from(models)..sort(_compareModels);
    await _queueSaveModels();
    notifyListeners();
  }

  List<ModelConfig> modelsByCategory(String category) {
    return _models.where((m) => m.category == category).toList(growable: false);
  }

  List<ModelConfig> enabledModelsByCategory(String category) {
    return modelsByCategory(
      category,
    ).where((m) => m.enabledModelNames.isNotEmpty).toList(growable: false);
  }

  int nextPriorityForCategory(String category) {
    final categoryModels = modelsByCategory(category);
    if (categoryModels.isEmpty) return 0;
    return categoryModels
            .map((m) => m.priority)
            .reduce((a, b) => a > b ? a : b) +
        1;
  }

  int _compareModels(ModelConfig a, ModelConfig b) {
    final categoryCompare = a.category.compareTo(b.category);
    if (categoryCompare != 0) return categoryCompare;
    return a.priority.compareTo(b.priority);
  }

  /// 从本地 repository 加载模型配置，单条坏配置会被跳过。
  Future<void> loadModels() async {
    final result = await _repository.load();
    _models = List<ModelConfig>.from(result.models)..sort(_compareModels);
    _usingStorageV2 = result.usingStorageV2;
    _pendingManagedModelIdMigrations.addAll(
      result.pendingManagedModelIdMigrations,
    );
    if (_normalizeManagedIds()) await _queueSaveModels();
    notifyListeners();
  }

  bool _normalizeManagedIds() {
    var changed = false;
    final normalized = <String, ModelConfig>{};
    for (final model in _models) {
      if (!model.managed) {
        normalized[model.id] = model;
        continue;
      }
      final providerId = model.relayProviderId?.trim();
      if (providerId == null || providerId.isEmpty) {
        normalized[model.id] = model;
        continue;
      }
      final target = '$lynaiManagedIdPrefix${providerId}_${model.category}__';
      if (model.id != target) {
        _pendingManagedModelIdMigrations[model.id] = target;
        changed = true;
      }
      normalized[target] = model.id == target
          ? model
          : model.copyWith(id: target);
    }
    if (changed) _models = normalized.values.toList()..sort(_compareModels);
    return changed;
  }

  /// 把当前模型配置快照排入保存队列。
  Future<void> _queueSaveModels({Map<String, String>? pendingMigrations}) {
    final snapshot = List<ModelConfig>.from(_models);
    final migrationSnapshot = Map<String, String>.from(
      pendingMigrations ?? _pendingManagedModelIdMigrations,
    );
    final operation = _saveQueue.then(
      (_) => _repository.save(
        snapshot,
        usingStorageV2: _usingStorageV2,
        pendingManagedModelIdMigrations: migrationSnapshot,
      ),
    );
    _pendingSave = operation;
    _saveQueue = operation.catchError((Object error) {
      debugPrint('保存模型配置失败: $error');
    });
    return operation;
  }

  /// 添加一个模型配置并按分类优先级重新排序。
  void addModel(ModelConfig config) {
    _models.add(config);
    _models.sort(_compareModels);
    _queueSaveModels();
    notifyListeners();
  }

  /// 更新模型配置
  void updateModel(ModelConfig config) {
    final index = _models.indexWhere((m) => m.id == config.id);
    if (index == -1) return;
    if (_models[index].managed) return;
    _models[index] = config;
    _models.sort(_compareModels);
    _queueSaveModels();
    notifyListeners();
  }

  void setManagedUserOverride(String modelId, String key, dynamic value) {
    final index = _models.indexWhere((m) => m.id == modelId && m.managed);
    if (index == -1) return;
    final overrides = Map<String, dynamic>.from(_models[index].userOverrides);
    if (_managedCapabilityKeys.contains(key) && value != false) {
      overrides.remove(key);
    } else {
      overrides[key] = value;
    }
    _models[index] = _models[index].copyWith(userOverrides: overrides);
    _queueSaveModels();
    notifyListeners();
  }

  void clearManagedUserOverride(String modelId, String key) {
    final index = _models.indexWhere((m) => m.id == modelId && m.managed);
    if (index == -1) return;
    final overrides = Map<String, dynamic>.from(_models[index].userOverrides)
      ..remove(key);
    _models[index] = _models[index].copyWith(userOverrides: overrides);
    _queueSaveModels();
    notifyListeners();
  }

  void setManagedDisabled(String modelId, bool disabled) {
    final index = _models.indexWhere((m) => m.id == modelId && m.managed);
    if (index == -1) return;
    _models[index] = _models[index].copyWith(disabledByUser: disabled);
    _queueSaveModels();
    notifyListeners();
  }

  /// 删除模型配置
  void deleteModel(String modelId) {
    if (_models.any((model) => model.id == modelId && model.managed)) return;
    final before = _models.length;
    _models.removeWhere((m) => m.id == modelId);
    if (_models.length == before) return;
    _queueSaveModels();
    notifyListeners();
  }

  Future<bool> syncLynaiManagedProvider(BackendClient backend) async {
    if (!backend.isConnected || (backend.accessToken ?? '').isEmpty) {
      return true;
    }

    final response = await backend.get('/relay/config');
    if (response.statusCode != 200) {
      debugPrint('同步 LynAI 模型失败: HTTP ${response.statusCode}');
      return response.statusCode == 401;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map ||
        decoded['schemaVersion'] != 3 ||
        decoded['data'] is! List) {
      debugPrint('同步 LynAI 模型失败: 响应格式错误');
      return false;
    }

    final grouped = _parseManagedGroups(decoded['data'] as List);
    final managedIds = grouped.map((group) => group.id).toSet();
    final previousManaged = List<ModelConfig>.from(
      _models.where((model) => model.managed),
    );
    _models.removeWhere(
      (model) => model.managed && !managedIds.contains(model.id),
    );
    final endpoint =
        '${backend.backendUrl.replaceAll(RegExp(r'/+$'), '')}/relay';

    for (final group in grouped) {
      if (group.entries.isEmpty) continue;
      final id = group.id;
      final existingIndex = _models.indexWhere((model) => model.id == id);
      final legacyConfigs = _legacyManagedConfigs(previousManaged, group);
      final existing = existingIndex == -1
          ? (legacyConfigs.isEmpty ? null : legacyConfigs.first)
          : _models[existingIndex];
      for (final legacy in legacyConfigs) {
        if (legacy.id != id) {
          _pendingManagedModelIdMigrations[legacy.id] = id;
        }
      }
      final modelEntries = group.entries;
      final existingModelName = existing?.modelName;
      final activeModel =
          existingModelName != null &&
              modelEntries.any((entry) => entry.name == existingModelName)
          ? existingModelName
          : modelEntries.first.name;
      final config = ModelConfig(
        id: id,
        name: group.name,
        category: group.category,
        endpoint: endpoint,
        apiKey: '',
        modelName: activeModel,
        apiType: '',
        priority: existing?.priority ?? nextPriorityForCategory(group.category),
        extraParams: group.extraParams,
        models: modelEntries,
        managed: true,
        relayProviderId: group.providerId,
        disabledByUser: existing?.disabledByUser ?? false,
        userOverrides: existing?.userOverrides,
      );
      if (existingIndex == -1) {
        _models.add(config);
      } else {
        _models[existingIndex] = config;
      }
    }

    _models.sort(_compareModels);
    _queueSaveModels();
    await _saveQueue;
    notifyListeners();
    return true;
  }

  Future<void> removeLynaiManagedProviders() async {
    final before = _models.length;
    _models.removeWhere((model) => model.managed);
    if (_models.length == before) return;
    _queueSaveModels();
    await _saveQueue;
    notifyListeners();
  }

  void reorderModelsInCategory(String category, int oldIndex, int newIndex) {
    final categoryModels = _models
        .where((m) => m.category == category)
        .toList();
    if (oldIndex < 0 || oldIndex >= categoryModels.length) return;
    if (newIndex < 0 || newIndex >= categoryModels.length) return;
    if (oldIndex == newIndex) return;
    final item = categoryModels.removeAt(oldIndex);
    categoryModels.insert(newIndex, item);

    var categoryIndex = 0;
    for (var i = 0; i < _models.length; i++) {
      if (_models[i].category != category) continue;
      _models[i] = categoryModels[categoryIndex].copyWith(
        priority: categoryIndex,
      );
      categoryIndex++;
    }
    _models.sort(_compareModels);
    _queueSaveModels();
    notifyListeners();
  }

  /// 生成新的唯一ID
  String generateId() => _uuid.v4();

  List<ModelConfig> _legacyManagedConfigs(
    List<ModelConfig> previousManaged,
    _ManagedModelGroup group,
  ) {
    return previousManaged
        .where(
          (model) =>
              model.id != group.id &&
              model.relayProviderId == group.providerId &&
              model.category == group.category,
        )
        .toList(growable: false);
  }

  List<_ManagedModelGroup> _parseManagedGroups(List data) {
    final groups = <String, _ManagedModelGroup>{};
    void addItem(
      Map item, {
      required String providerId,
      required String providerName,
      required String providerCategory,
      String? providerWorkflow,
    }) {
      final modelId = item['id']?.toString().trim() ?? '';
      final category = _normalizeCategory(
        item['category']?.toString() ?? providerCategory,
      );
      if (modelId.isEmpty || providerId.isEmpty) return;
      final key = '$providerId\x00$category';
      final group = groups.putIfAbsent(
        key,
        () => _ManagedModelGroup(
          id: '$lynaiManagedIdPrefix${providerId}_${category}__',
          providerId: providerId,
          name: providerName.isNotEmpty ? 'LynAI $providerName' : 'LynAI',
          category: category,
        ),
      );
      final capabilities = item['capabilities'] is Map
          ? Map<String, dynamic>.from(item['capabilities'] as Map)
          : const <String, dynamic>{};
      final params = item['advancedParams'] is Map
          ? Map<String, dynamic>.from(item['advancedParams'] as Map)
          : const <String, dynamic>{};
      final workflow = item['workflow']?.toString().trim().isNotEmpty == true
          ? item['workflow'].toString().trim()
          : providerWorkflow?.trim() ?? '';
      group.entries.add(
        ModelEntry(
          name: modelId,
          enabled: item['enabled'] != false,
          supportsVision: capabilities['vision'] as bool? ?? false,
          supportsThinking: capabilities['thinking'] as bool? ?? false,
          supportsTools: capabilities['tools'] as bool? ?? false,
          maxTokens: (params['maxTokens'] as num?)?.toInt(),
          temperature: (params['temperature'] as num?)?.toDouble(),
          topP: (params['topP'] as num?)?.toDouble(),
          workflow: workflow.isEmpty ? null : workflow,
        ),
      );
    }

    for (final provider in data) {
      if (provider is! Map || provider['models'] is! List) continue;
      final providerId = provider['providerId']?.toString().trim() ?? '';
      if (providerId.isEmpty) continue;
      final providerName = provider['name']?.toString().trim() ?? '';
      final providerCategory = provider['category']?.toString() ?? '';
      final providerWorkflow = provider['workflow']?.toString();
      for (final model in provider['models'] as List) {
        if (model is Map) {
          addItem(
            model,
            providerId: providerId,
            providerName: providerName,
            providerCategory: providerCategory,
            providerWorkflow: providerWorkflow,
          );
        }
      }
    }
    return groups.values.where((group) => group.entries.isNotEmpty).toList();
  }

  String _normalizeCategory(String? value) {
    switch ((value ?? '').trim()) {
      case ModelConfig.categoryOcr:
        return ModelConfig.categoryOcr;
      case ModelConfig.categorySpeech:
        return ModelConfig.categorySpeech;
      case ModelConfig.categoryImageGeneration:
        return ModelConfig.categoryImageGeneration;
      default:
        return ModelConfig.categoryChat;
    }
  }

  static const _managedCapabilityKeys = {
    'supportsVision',
    'supportsThinking',
    'supportsTools',
  };
}

class _ManagedModelGroup {
  _ManagedModelGroup({
    required this.id,
    required this.providerId,
    required this.name,
    required this.category,
  });

  final String id;
  final String providerId;
  final String name;
  final String category;
  final List<ModelEntry> entries = [];
  final Map<String, dynamic> extraParams = {};
}
