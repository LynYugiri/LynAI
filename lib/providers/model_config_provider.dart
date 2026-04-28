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

  /// 从 SharedPreferences 加载模型配置
  Future<void> loadModels() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString != null) {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      _models = jsonList
          .map((j) => ModelConfig.fromJson(j as Map<String, dynamic>))
          .toList();
      _models.sort((a, b) => a.priority.compareTo(b.priority));
      notifyListeners();
    }
  }

  /// 将模型配置保存到 SharedPreferences
  Future<void> _saveModels() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_models.map((m) => m.toJson()).toList());
    await prefs.setString(_storageKey, jsonString);
  }

  /// 添加新模型配置
  void addModel(ModelConfig config) {
    _models.add(config);
    _models.sort((a, b) => a.priority.compareTo(b.priority));
    _saveModels();
    notifyListeners();
  }

  /// 更新模型配置
  void updateModel(ModelConfig config) {
    final index = _models.indexWhere((m) => m.id == config.id);
    if (index == -1) return;
    _models[index] = config;
    _models.sort((a, b) => a.priority.compareTo(b.priority));
    _saveModels();
    notifyListeners();
  }

  /// 删除模型配置
  void deleteModel(String modelId) {
    _models.removeWhere((m) => m.id == modelId);
    _saveModels();
    notifyListeners();
  }

  /// 调整模型优先级（上移或下移）
  void reorderModel(int oldIndex, int newIndex) {
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

  /// 生成新的唯一ID
  String generateId() => _uuid.v4();
}

