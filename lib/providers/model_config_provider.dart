import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/model_config.dart';
import '../repositories/model_config_repository.dart';
import '../services/backend_client.dart';
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
  final ModelConfigRepository _repository;
  bool _usingStorageV2 = false;

  ModelConfigProvider({
    StorageV2Service? storageV2,
    ModelConfigRepository? repository,
  }) : _repository = repository ?? ModelConfigRepository(storageV2: storageV2);

  /// 所有模型配置，按分类和优先级排序。
  List<ModelConfig> get models => List.unmodifiable(_models);
  bool get usingStorageV2 => _usingStorageV2;

  Future<void> replaceModels(List<ModelConfig> models) async {
    _models = List<ModelConfig>.from(models)..sort(_compareModels);
    _queueSaveModels();
    await _saveQueue;
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
    try {
      final result = await _repository.load();
      _models = List<ModelConfig>.from(result.models)..sort(_compareModels);
      _usingStorageV2 = result.usingStorageV2;
      notifyListeners();
    } catch (e) {
      debugPrint('加载模型配置失败: $e');
      _models = [];
      notifyListeners();
    }
  }

  /// 把当前模型配置快照排入保存队列。
  void _queueSaveModels() {
    final snapshot = List<ModelConfig>.from(_models);
    _saveQueue = _saveQueue.then((_) => _saveModelsSnapshot(snapshot));
  }

  Future<void> _saveModelsSnapshot(List<ModelConfig> snapshot) async {
    try {
      await _repository.save(snapshot, usingStorageV2: _usingStorageV2);
    } catch (e) {
      debugPrint('保存模型配置失败: $e');
    }
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
    overrides[key] = value;
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
      await removeLynaiManagedProviders();
      return true;
    }

    var response = await backend.get('/relay/config');
    if (response.statusCode == 404) {
      response = await backend.get('/relay/models');
    }
    if (response.statusCode != 200) {
      debugPrint('同步 LynAI 模型失败: HTTP ${response.statusCode}');
      if (response.statusCode == 401) {
        await removeLynaiManagedProviders();
      }
      return false;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['data'] is! List) {
      debugPrint('同步 LynAI 模型失败: 响应格式错误');
      return false;
    }

    final grouped = _parseManagedGroups(decoded['data'] as List);
    final managedIds = grouped.map((group) => group.id).toSet();
    _models.removeWhere(
      (model) => model.managed && !managedIds.contains(model.id),
    );
    final endpoint =
        '${backend.backendUrl.replaceAll(RegExp(r'/+$'), '')}/relay';

    for (final group in grouped) {
      if (group.entries.isEmpty) continue;
      final id = group.id;
      final existingIndex = _models.indexWhere((model) => model.id == id);
      final existing = existingIndex == -1 ? null : _models[existingIndex];
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
        apiType: group.apiType,
        priority: existing?.priority ?? nextPriorityForCategory(group.category),
        maxTokens: group.maxTokens,
        temperature: group.temperature,
        topP: group.topP,
        extraParams: group.extraParams,
        models: modelEntries,
        managed: true,
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

  /// 调整模型优先级（上移或下移）
  void reorderModel(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _models.length) return;
    if (newIndex < 0 || newIndex >= _models.length) return;
    if (oldIndex == newIndex) return;
    final item = _models.removeAt(oldIndex);
    _models.insert(newIndex, item);
    // 更新所有模型的 priority
    for (int i = 0; i < _models.length; i++) {
      _models[i] = _models[i].copyWith(priority: i);
    }
    _queueSaveModels();
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

  List<_ManagedModelGroup> _parseManagedGroups(List data) {
    final groups = <String, _ManagedModelGroup>{};
    void addItem(Map item, {String? providerId, String? providerName}) {
      final modelId = item['id']?.toString().trim() ?? '';
      final apiType = (item['api_type'] ?? item['apiType'] ?? 'openai')
          .toString()
          .trim()
          .toLowerCase();
      final category = _normalizeCategory(item['category']?.toString());
      if (modelId.isEmpty || apiType.isEmpty) return;
      final groupProviderId =
          (providerId ?? item['providerId']?.toString() ?? apiType).trim();
      final displayProviderName = providerName?.trim().isNotEmpty == true
          ? providerName!.trim()
          : item['providerName']?.toString().trim() ?? '';
      final key = '$groupProviderId\x00$apiType\x00$category';
      final group = groups.putIfAbsent(
        key,
        () => _ManagedModelGroup(
          id: '$lynaiManagedIdPrefix${groupProviderId}_${apiType}_${category}__',
          name: displayProviderName.isNotEmpty
              ? 'LynAI $displayProviderName'
              : (apiType == 'openai' ? 'LynAI' : 'LynAI ($apiType)'),
          apiType: apiType,
          category: category,
        ),
      );
      final capabilities = item['capabilities'] is Map
          ? Map<String, dynamic>.from(item['capabilities'] as Map)
          : const <String, dynamic>{};
      final params = item['advancedParams'] is Map
          ? Map<String, dynamic>.from(item['advancedParams'] as Map)
          : const <String, dynamic>{};
      group.entries.add(
        ModelEntry(
          name: modelId,
          enabled: item['enabled'] != false,
          supportsVision: capabilities['vision'] as bool? ?? true,
          supportsThinking: capabilities['thinking'] as bool? ?? true,
          supportsTools: capabilities['tools'] as bool? ?? true,
          maxTokens: (params['maxTokens'] as num?)?.toInt(),
          temperature: (params['temperature'] as num?)?.toDouble(),
          topP: (params['topP'] as num?)?.toDouble(),
        ),
      );
      group.maxTokens ??= (params['maxTokens'] as num?)?.toInt();
      group.temperature ??= (params['temperature'] as num?)?.toDouble();
      group.topP ??= (params['topP'] as num?)?.toDouble();
      group.extraParams.addAll(params);
    }

    for (final item in data) {
      if (item is! Map) continue;
      final models = item['models'];
      if (models is List) {
        final providerId = item['id']?.toString();
        final providerName = item['name']?.toString();
        for (final model in models) {
          if (model is Map) {
            addItem(model, providerId: providerId, providerName: providerName);
          }
        }
      } else {
        addItem(item);
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
}

class _ManagedModelGroup {
  _ManagedModelGroup({
    required this.id,
    required this.name,
    required this.apiType,
    required this.category,
  });

  final String id;
  final String name;
  final String apiType;
  final String category;
  final List<ModelEntry> entries = [];
  final Map<String, dynamic> extraParams = {};
  int? maxTokens;
  double? temperature;
  double? topP;
}
