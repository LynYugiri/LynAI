import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';

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
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString != null) {
      final Map<String, dynamic> json =
          jsonDecode(jsonString) as Map<String, dynamic>;
      _settings = AppSettings.fromJson(json);
      notifyListeners();
    }
  }

  /// 将设置保存到 SharedPreferences
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_settings.toJson());
    await prefs.setString(_storageKey, jsonString);
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

  /// 设置语音转文字模型ID
  void setSpeechModelId(String? modelId) {
    _settings = _settings.copyWith(speechModelId: modelId);
    _saveSettings();
    notifyListeners();
  }

  /// 设置图片转述模型ID
  void setImageModelId(String? modelId) {
    _settings = _settings.copyWith(imageModelId: modelId);
    _saveSettings();
    notifyListeners();
  }

  /// 设置图片转述提示词
  void setImagePrompt(String prompt) {
    _settings = _settings.copyWith(imagePrompt: prompt);
    _saveSettings();
    notifyListeners();
  }
}

