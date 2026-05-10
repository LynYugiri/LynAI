import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/app_settings.dart';
import '../models/conversation.dart';
import '../models/system_prompt.dart';

/// 设置状态管理
///
/// 管理应用的所有设置项，包括主题颜色、背景图片、毛玻璃效果等。
/// 设置变更后自动持久化到 SharedPreferences。
class SettingsProvider extends ChangeNotifier {
  AppSettings _settings = AppSettings.defaults();
  static const _storageKey = 'app_settings';

  AppSettings get settings => _settings;

  /// 从 SharedPreferences 加载设置
  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null) {
        final Map<String, dynamic> json =
            jsonDecode(jsonString) as Map<String, dynamic>;
        _settings = AppSettings.fromJson(json);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('加载设置失败: $e');
      _settings = AppSettings.defaults();
    }
  }

  /// 将设置保存到 SharedPreferences
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(_settings.toJson());
      await prefs.setString(_storageKey, jsonString);
    } catch (e) {
      debugPrint('保存设置失败: $e');
    }
  }

  /// 更新主题颜色
  void setThemeColor(Color color) {
    _settings = _settings.copyWith(themeColor: color);
    _saveSettings();
    notifyListeners();
  }

  /// 设置背景图片路径
  void setBackgroundImage(String? path) {
    _settings = _settings.copyWith(backgroundImagePath: path);
    _saveSettings();
    notifyListeners();
  }

  /// 设置毛玻璃效果开关
  void setBlurEnabled(bool enabled) {
    _settings = _settings.copyWith(blurEnabled: enabled);
    _saveSettings();
    notifyListeners();
  }

  /// 设置模糊程度
  void setBlurAmount(double amount) {
    _settings = _settings.copyWith(blurAmount: amount);
    _saveSettings();
    notifyListeners();
  }

  /// 设置语音转文字接口配置ID
  void setSpeechModelId(String? modelId) {
    _settings = _settings.copyWith(speechModelId: modelId);
    _saveSettings();
    notifyListeners();
  }

  /// 设置 OCR 接口配置ID
  void setImageModelId(String? modelId) {
    _settings = _settings.copyWith(imageModelId: modelId);
    _saveSettings();
    notifyListeners();
  }

  /// 设置图片识别模型配置ID
  void setImageRecognitionModelId(String? modelId) {
    _settings = _settings.copyWith(imageRecognitionModelId: modelId);
    _saveSettings();
    notifyListeners();
  }

  /// 设置图片识别是否启用
  void setImageRecognitionEnabled(bool enabled) {
    _settings = _settings.copyWith(imageRecognitionEnabled: enabled);
    _saveSettings();
    notifyListeners();
  }

  /// 记录新对话默认使用的 Chat 模型配置ID
  void setLastChatModelId(String? modelId) {
    _settings = _settings.copyWith(lastChatModelId: modelId);
    _saveSettings();
    notifyListeners();
  }

  /// 设置图片识别结果发送给 Chat 时使用的提示词
  void setImageRecognitionPrompt(String prompt) {
    _settings = _settings.copyWith(imageRecognitionPrompt: prompt);
    _saveSettings();
    notifyListeners();
  }

  /// 设置系统提示词
  void setSystemPrompt(String prompt) {
    _settings = _settings.copyWith(systemPrompt: prompt);
    _saveSettings();
    notifyListeners();
  }

  /// 添加系统提示词模板
  String addSystemPrompt(String title, String content) {
    final id = const Uuid().v4();
    final prompt = SystemPrompt(id: id, title: title, content: content);
    final list = List<SystemPrompt>.from(_settings.systemPrompts)..add(prompt);
    _settings = _settings.copyWith(
      systemPrompts: list,
      selectedSystemPromptId: id,
    );
    _saveSettings();
    notifyListeners();
    return id;
  }

  /// 更新系统提示词模板
  void updateSystemPrompt(String id, String title, String content) {
    final list = _settings.systemPrompts.map((p) {
      return p.id == id ? p.copyWith(title: title, content: content) : p;
    }).toList();
    _settings = _settings.copyWith(systemPrompts: list);
    _saveSettings();
    notifyListeners();
  }

  /// 删除系统提示词模板
  void deleteSystemPrompt(String id) {
    final list = _settings.systemPrompts.where((p) => p.id != id).toList();
    String? newSelected = _settings.selectedSystemPromptId;
    if (newSelected == id) {
      newSelected = null;
    }
    _settings = _settings.copyWith(
      systemPrompts: list,
      selectedSystemPromptId: newSelected,
    );
    _saveSettings();
    notifyListeners();
  }

  /// 选择当前使用的系统提示词
  void selectSystemPrompt(String? id) {
    _settings = _settings.copyWith(selectedSystemPromptId: id);
    _saveSettings();
    notifyListeners();
  }

  /// 获取当前生效的系统提示词内容
  String get effectiveSystemPrompt {
    return effectiveSystemPromptFor(
      _settings.selectedSystemPromptId,
      _settings.systemPrompt,
    );
  }

  String effectiveSystemPromptFor(String? selectedId, String fallback) {
    if (selectedId != null) {
      for (final prompt in _settings.systemPrompts) {
        if (prompt.id == selectedId) return prompt.content;
      }
    }
    return fallback;
  }

  void applyConversationSettings(ConversationSettings settings) {
    _settings = _settings.copyWith(
      speechModelId: settings.speechModelId,
      imageModelId: settings.imageModelId,
      imageRecognitionModelId: settings.imageRecognitionModelId,
      imageRecognitionEnabled: settings.imageRecognitionEnabled,
      imageRecognitionPrompt: settings.imageRecognitionPrompt,
      systemPrompt: settings.systemPrompt,
      selectedSystemPromptId: settings.selectedSystemPromptId,
      lastChatModelId: settings.modelId,
    );
    _saveSettings();
    notifyListeners();
  }

  /// 设置主题模式
  void setThemeMode(String mode) {
    _settings = _settings.copyWith(themeMode: mode);
    _saveSettings();
    notifyListeners();
  }

  /// 获取主题模式字符串
  String get themeMode => _settings.themeMode;

  /// 获取 ThemeMode 枚举值
  ThemeMode get themeModeEnum {
    switch (_settings.themeMode) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }
}
