import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/model_config.dart';

/// 模型配置状态管理
///
/// 管理所有 AI 模型配置的增删改查和优先级排序。
/// 模型按 priority 升序排列（数字越小优先级越高）。
class ModelConfigProvider extends ChangeNotifier {
  List<ModelConfig> _models = [];
  final _uuid = const Uuid();
  static const _storageKey = 'model_configs';

  /// 获取所有模型配置（按优先级升序）
  List<ModelConfig> get models => List.unmodifiable(_models);

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

  /// 从 SharedPreferences 加载模型配置
  Future<void> loadModels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        final models = <ModelConfig>[];
        for (final item in jsonList) {
          try {
            models.add(ModelConfig.fromJson(item as Map<String, dynamic>));
          } catch (e) {
            debugPrint('跳过损坏的模型配置: $e');
          }
        }
        _models = models;
        _models.sort(_compareModels);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('加载模型配置失败: $e');
      _models = [];
      notifyListeners();
    }
  }

  /// 将模型配置保存到 SharedPreferences
  Future<void> _saveModels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(_models.map((m) => m.toJson()).toList());
      await prefs.setString(_storageKey, jsonString);
    } catch (e) {
      debugPrint('保存模型配置失败: $e');
    }
  }

  /// 添加新模型配置
  void addModel(ModelConfig config) {
    _models.add(config);
    _models.sort(_compareModels);
    _saveModels();
    notifyListeners();
  }

  /// 更新模型配置
  void updateModel(ModelConfig config) {
    final index = _models.indexWhere((m) => m.id == config.id);
    if (index == -1) return;
    _models[index] = config;
    _models.sort(_compareModels);
    _saveModels();
    notifyListeners();
  }

  /// 删除模型配置
  void deleteModel(String modelId) {
    final before = _models.length;
    _models.removeWhere((m) => m.id == modelId);
    if (_models.length == before) return;
    _saveModels();
    notifyListeners();
  }

  /// 调整模型优先级（上移或下移）
  void reorderModel(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _models.length) return;
    if (newIndex < 0 || newIndex > _models.length) return;
    if (oldIndex == newIndex) return;
    if (oldIndex < newIndex) newIndex--;
    final item = _models.removeAt(oldIndex);
    _models.insert(newIndex, item);
    // 更新所有模型的 priority
    for (int i = 0; i < _models.length; i++) {
      _models[i] = _models[i].copyWith(priority: i);
    }
    _saveModels();
    notifyListeners();
  }

  void reorderModelsInCategory(String category, int oldIndex, int newIndex) {
    final categoryModels = _models
        .where((m) => m.category == category)
        .toList();
    if (oldIndex < 0 || oldIndex >= categoryModels.length) return;
    if (newIndex < 0 || newIndex > categoryModels.length) return;
    if (oldIndex == newIndex) return;
    if (oldIndex < newIndex) newIndex--;
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
    _saveModels();
    notifyListeners();
  }

  /// 生成新的唯一ID
  String generateId() => _uuid.v4();
}
