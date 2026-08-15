import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/model_config.dart';
import '../repositories/model_config_repository.dart';
import '../services/backend_client.dart';
import '../services/secret_store.dart';
import '../services/storage_v2_service.dart';
import 'serialized_save_queue.dart';

/// 管理所有模型配置和分类内优先级。
///
/// 模型按 `category` 分组，再按 `priority` 升序排列。一个 [ModelConfig]
/// 表示一个提供商配置，内部可以包含多个可启用的子模型。
class ModelConfigProvider extends ChangeNotifier with SerializedSaveQueue {
  static const lynaiManagedIdPrefix = '__lynai_relay_';

  List<ModelConfig> _models = [];
  final _uuid = const Uuid();
  int _mutationGeneration = 0;
  int _managedSyncGeneration = 0;
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
      if (remaining[entry.key] == entry.value) remaining.remove(entry.key);
    }
    await _queueSaveModels(pendingMigrations: remaining);
    _pendingManagedModelIdMigrations
      ..clear()
      ..addAll(remaining);
  }

  Future<void> replaceModels(List<ModelConfig> models) async {
    _models = List<ModelConfig>.from(models);
    _normalizeManagedIds();
    _models.sort(_compareModels);
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
    final generation = _mutationGeneration;
    await flushPendingSaves();
    final result = await _repository.load();
    if (generation != _mutationGeneration) return;
    _models = List<ModelConfig>.from(result.models);
    _usingStorageV2 = result.usingStorageV2;
    _pendingManagedModelIdMigrations
      ..clear()
      ..addAll(result.pendingManagedModelIdMigrations);
    final normalized = _normalizeManagedIds();
    _models.sort(_compareModels);
    if (normalized) await _queueSaveModels(mutation: false);
    notifyListeners();
  }

  bool _normalizeManagedIds() {
    for (final entry in _pendingManagedModelIdMigrations.entries.toList()) {
      final category = _categoryFromManagedId(entry.value);
      if (category != null) {
        _pendingManagedModelIdMigrations[entry.key] =
            '$lynaiManagedIdPrefix${category}__';
      }
    }
    final unmanaged = <ModelConfig>[];
    final groups = <String, List<({ModelConfig model, int order})>>{};
    for (var i = 0; i < _models.length; i++) {
      final model = _models[i];
      if (!model.managed) {
        unmanaged.add(model);
        continue;
      }
      final category = _normalizeCategory(model.category);
      groups.putIfAbsent(category, () => []).add((model: model, order: i));
    }

    var changed = false;
    final normalizedManaged = <ModelConfig>[];
    for (final entry in groups.entries) {
      final category = entry.key;
      final targetId = '$lynaiManagedIdPrefix${category}__';
      final configs = entry.value;
      var base = configs.first;
      for (final candidate in configs.skip(1)) {
        final candidateExact = candidate.model.id == targetId;
        final baseExact = base.model.id == targetId;
        if (candidateExact && !baseExact ||
            candidateExact == baseExact &&
                candidate.model.priority < base.model.priority) {
          base = candidate;
        }
      }

      final ordered = [base, ...configs.where((item) => item != base)];
      final mergedEntries = <ModelEntry>[];
      final names = <String>{};
      for (final item in ordered) {
        for (final modelEntry in item.model.models) {
          if (names.add(modelEntry.name)) mergedEntries.add(modelEntry);
        }
        if (item.model.id != targetId) {
          _pendingManagedModelIdMigrations[item.model.id] = targetId;
          changed = true;
        }
      }
      final selected =
          mergedEntries.any(
            (modelEntry) => modelEntry.name == base.model.modelName,
          )
          ? base.model.modelName
          : _firstAvailableModelName(mergedEntries);
      final normalized = base.model.copyWith(
        id: targetId,
        name: 'LynAI',
        category: category,
        modelName: selected,
        apiType: '',
        managed: true,
        models: mergedEntries,
      );
      normalizedManaged.add(normalized);
      if (configs.length != 1 ||
          base.model.id != targetId ||
          base.model.name != 'LynAI' ||
          base.model.category != category ||
          base.model.modelName != selected ||
          !_sameModelEntries(base.model.models, mergedEntries)) {
        changed = true;
      }
    }
    if (changed) _models = [...unmanaged, ...normalizedManaged];
    return changed;
  }

  String _firstAvailableModelName(List<ModelEntry> entries) {
    for (final entry in entries) {
      if (entry.enabled) return entry.name;
    }
    return entries.isEmpty ? '' : entries.first.name;
  }

  String? _categoryFromManagedId(String id) {
    if (!id.startsWith(lynaiManagedIdPrefix) || !id.endsWith('__')) {
      return null;
    }
    for (final category in ModelConfig.supportedCategories) {
      if (id.endsWith('_${category}__')) return category;
    }
    return null;
  }

  bool _sameModelEntries(List<ModelEntry> left, List<ModelEntry> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (jsonEncode(left[i].toJson()) != jsonEncode(right[i].toJson())) {
        return false;
      }
    }
    return true;
  }

  /// 把当前模型配置快照排入保存队列。
  Future<void> _queueSaveModels({
    Map<String, String>? pendingMigrations,
    bool mutation = true,
  }) {
    if (mutation) _mutationGeneration++;
    final snapshot = List<ModelConfig>.from(_models);
    final migrationSnapshot = Map<String, String>.from(
      pendingMigrations ?? _pendingManagedModelIdMigrations,
    );
    return enqueueSave(
      () => _repository.save(
        snapshot,
        usingStorageV2: _usingStorageV2,
        pendingManagedModelIdMigrations: migrationSnapshot,
      ),
    );
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

  Future<bool> syncLynaiManagedModels(BackendClient backend) async {
    final generation = ++_managedSyncGeneration;
    final backendUrl = backend.backendUrl;
    final backendOrigin = backend.backendOrigin;
    final backendScope = backend.backendScope;
    final accessToken = backend.accessToken;
    if (!backend.isConnected || (accessToken ?? '').isEmpty) {
      return true;
    }

    late final http.Response response;
    try {
      response = await backend.get('/relay/config');
    } catch (error) {
      debugPrint('同步 LynAI 模型失败: $error');
      return false;
    }
    if (generation != _managedSyncGeneration ||
        !backend.isConnected ||
        backend.backendUrl != backendUrl ||
        backend.backendOrigin != backendOrigin ||
        backend.backendScope != backendScope ||
        backend.accessToken != accessToken) {
      return false;
    }
    if (response.statusCode != 200) {
      debugPrint('同步 LynAI 模型失败: HTTP ${response.statusCode}');
      return response.statusCode == 401;
    }

    late final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      debugPrint('同步 LynAI 模型失败: $error');
      return false;
    }
    if (decoded is! Map ||
        decoded['object'] != 'relay_config' ||
        decoded['schemaVersion'] != 4 ||
        decoded['data'] is! List) {
      debugPrint('同步 LynAI 模型失败: 响应格式错误');
      return false;
    }

    final grouped = _parseManagedGroups(decoded['data'] as List);
    if (grouped == null) {
      debugPrint('同步 LynAI 模型失败: 模型数据格式错误');
      return false;
    }
    final endpoint = '${backendUrl.replaceAll(RegExp(r'/+$'), '')}/relay';
    final previousManaged = _models
        .where((model) => model.managed)
        .toList(growable: false);
    for (final model in previousManaged) {
      final category = _normalizeCategory(model.category);
      final targetId = '$lynaiManagedIdPrefix${category}__';
      if (model.id != targetId) {
        _pendingManagedModelIdMigrations[model.id] = targetId;
      }
    }
    final nextManaged = <ModelConfig>[];
    for (final group in grouped) {
      if (group.entries.isEmpty) continue;
      final id = group.id;
      final modelEntries = group.entries;
      final candidates = <({ModelConfig model, int order})>[];
      for (var i = 0; i < previousManaged.length; i++) {
        final model = previousManaged[i];
        if (_normalizeCategory(model.category) != group.category) continue;
        candidates.add((model: model, order: i));
      }
      final existing = _selectManagedState(candidates, id, modelEntries);
      final existingModelName = existing?.modelName;
      final activeModel =
          existingModelName != null &&
              modelEntries.any((entry) => entry.name == existingModelName)
          ? existingModelName
          : modelEntries.first.name;
      nextManaged.add(
        ModelConfig(
          id: id,
          name: 'LynAI',
          category: group.category,
          endpoint: endpoint,
          apiKey: '',
          modelName: activeModel,
          apiType: '',
          priority:
              existing?.priority ?? nextPriorityForCategory(group.category),
          extraParams: group.extraParams,
          models: modelEntries,
          managed: true,
          disabledByUser: existing?.disabledByUser ?? false,
          userOverrides: existing?.userOverrides,
        ),
      );
    }
    final nextModels = [
      ..._models.where((model) => !model.managed),
      ...nextManaged,
    ]..sort(_compareModels);
    _models = nextModels;
    await _queueSaveModels();
    notifyListeners();
    return true;
  }

  ModelConfig? _selectManagedState(
    List<({ModelConfig model, int order})> candidates,
    String targetId,
    List<ModelEntry> entries,
  ) {
    if (candidates.isEmpty) return null;
    for (final candidate in candidates) {
      if (candidate.model.id == targetId) return candidate.model;
    }
    final names = entries.map((entry) => entry.name).toSet();
    candidates.sort((a, b) {
      final aSelectedExists = names.contains(a.model.modelName);
      final bSelectedExists = names.contains(b.model.modelName);
      if (aSelectedExists != bSelectedExists) return aSelectedExists ? -1 : 1;
      final priority = a.model.priority.compareTo(b.model.priority);
      return priority != 0 ? priority : a.order.compareTo(b.order);
    });
    return candidates.first.model;
  }

  Future<void> removeLynaiManagedModels() async {
    _managedSyncGeneration++;
    final before = _models.length;
    _models.removeWhere((model) => model.managed);
    if (_models.length == before) return;
    _queueSaveModels();
    await pendingSaveQueue;
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

  List<_ManagedModelGroup>? _parseManagedGroups(List data) {
    final groups = <String, _ManagedModelGroup>{};
    bool addItem(Map item) {
      final id = item['id'];
      final categoryValue = item['category'];
      final displayName = item['displayName'];
      final description = item['description'];
      final capabilitiesValue = item['capabilities'];
      final paramsValue = item['advancedParams'];
      final enabled = item['enabled'];
      final workflowValue = item['workflow'];
      if (id is! String ||
          id.trim().isEmpty ||
          categoryValue is! String ||
          displayName is! String ||
          description is! String ||
          capabilitiesValue is! Map ||
          paramsValue is! Map ||
          enabled is! bool ||
          (workflowValue != null && workflowValue is! String)) {
        return false;
      }
      final capabilities = Map<String, dynamic>.from(capabilitiesValue);
      final params = Map<String, dynamic>.from(paramsValue);
      if (!_validOptionalBool(capabilities['vision']) ||
          !_validOptionalBool(capabilities['thinking']) ||
          !_validOptionalBool(capabilities['tools']) ||
          !_validOptionalNum(params['maxTokens']) ||
          !_validOptionalNum(params['temperature']) ||
          !_validOptionalNum(params['topP']) ||
          !_validOptionalNum(params['contextWindow'])) {
        return false;
      }
      final modelId = id.trim();
      final category = _normalizeCategory(categoryValue);
      final group = groups.putIfAbsent(
        category,
        () => _ManagedModelGroup(
          id: '$lynaiManagedIdPrefix${category}__',
          category: category,
        ),
      );
      final workflow = workflowValue?.trim().isNotEmpty == true
          ? workflowValue!.trim()
          : '';
      group.entries.add(
        ModelEntry(
          name: modelId,
          enabled: enabled,
          supportsVision: capabilities['vision'] as bool? ?? false,
          supportsThinking: capabilities['thinking'] as bool? ?? false,
          supportsTools: capabilities['tools'] as bool? ?? false,
          maxTokens: (params['maxTokens'] as num?)?.toInt(),
          temperature: (params['temperature'] as num?)?.toDouble(),
          topP: (params['topP'] as num?)?.toDouble(),
          contextWindow: (params['contextWindow'] as num?)?.toInt(),
          workflow: workflow.isEmpty ? null : workflow,
        ),
      );
      return true;
    }

    for (final model in data) {
      if (model is! Map || !addItem(model)) return null;
    }
    return groups.values.where((group) => group.entries.isNotEmpty).toList();
  }

  bool _validOptionalBool(Object? value) => value == null || value is bool;

  bool _validOptionalNum(Object? value) => value == null || value is num;

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
  _ManagedModelGroup({required this.id, required this.category});

  final String id;
  final String category;
  final List<ModelEntry> entries = [];
  final Map<String, dynamic> extraParams = {};
}
