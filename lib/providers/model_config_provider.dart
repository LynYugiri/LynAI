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

    final response = await backend.get('/relay/models');
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

    final grouped = <String, List<String>>{};
    for (final item in decoded['data'] as List) {
      if (item is! Map) continue;
      final id = item['id']?.toString().trim() ?? '';
      final apiType =
          (item['api_type']?.toString().trim().toLowerCase() ?? 'openai');
      if (id.isEmpty || apiType.isEmpty) continue;
      grouped.putIfAbsent(apiType, () => <String>[]);
      if (!grouped[apiType]!.contains(id)) {
        grouped[apiType]!.add(id);
      }
    }

    final managedIds = grouped.keys.map(_lynaiManagedId).toSet();
    _models.removeWhere(
      (model) => model.managed && !managedIds.contains(model.id),
    );
    final endpoint =
        '${backend.backendUrl.replaceAll(RegExp(r'/+$'), '')}/relay';

    for (final entry in grouped.entries) {
      if (entry.value.isEmpty) continue;
      final apiType = entry.key;
      final id = _lynaiManagedId(apiType);
      final existingIndex = _models.indexWhere((model) => model.id == id);
      final existing = existingIndex == -1 ? null : _models[existingIndex];
      final modelEntries = entry.value
          .map((name) => ModelEntry(name: name, enabled: true))
          .toList(growable: false);
      final activeModel =
          existing?.modelName != null &&
              entry.value.contains(existing!.modelName)
          ? existing.modelName
          : entry.value.first;
      final config = ModelConfig(
        id: id,
        name: apiType == 'openai' ? 'LynAI' : 'LynAI ($apiType)',
        category: ModelConfig.categoryChat,
        endpoint: endpoint,
        apiKey: '',
        modelName: activeModel,
        apiType: apiType,
        priority:
            existing?.priority ??
            nextPriorityForCategory(ModelConfig.categoryChat),
        models: modelEntries,
        managed: true,
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

  static String _lynaiManagedId(String apiType) =>
      '$lynaiManagedIdPrefix${apiType}__';
}
