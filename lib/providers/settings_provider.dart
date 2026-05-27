import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/app_settings.dart';
import '../models/chat_role.dart';
import '../models/conversation.dart';
import '../models/model_config.dart';
import '../models/system_prompt.dart';

/// 管理应用级设置、角色、系统提示词和最近使用模型。
///
/// 设置是跨页面共享的 UI 状态。修改后立即通知界面，并把不可变快照排入
/// 串行保存队列；这样快速切换主题、角色或模型时不会出现旧设置覆盖新设置。
class SettingsProvider extends ChangeNotifier {
  AppSettings _settings = AppSettings.defaults();
  static const _storageKey = 'app_settings';
  Future<void> _saveQueue = Future.value();

  AppSettings get settings => _settings;

  Future<void> replaceSettings(AppSettings settings) async {
    _settings = settings;
    _queueSaveSettings();
    await _saveQueue;
    notifyListeners();
  }

  ChatRole get currentRole {
    return _settings.roles.firstWhere(
      (r) => r.id == _settings.currentRoleId,
      orElse: ChatRole.defaultRole,
    );
  }

  /// 从 SharedPreferences 加载设置。
  ///
  /// 角色和提示词的单条坏数据由 [AppSettings.fromJson] 跳过；顶层结构损坏
  /// 时回退默认设置，保证应用仍可启动。
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
      notifyListeners();
    }
  }

  /// 修复已删除或不存在的模型配置引用。
  ///
  /// 如果当前选中的配置已被删除或不存在，则自动回填同类第一个可用配置。
  void repairMediaModelSelections(List<ModelConfig> models) {
    final chatModels = models
        .where((m) => m.category == ModelConfig.categoryChat)
        .toList(growable: false);
    final speechModels = models
        .where((m) => m.category == ModelConfig.categorySpeech)
        .toList(growable: false);
    final ocrModels = models
        .where((m) => m.category == ModelConfig.categoryOcr)
        .toList(growable: false);

    final nextSpeechId = _firstValidModelId(
      _settings.speechModelId,
      speechModels,
    );
    final nextOcrId = _firstValidModelId(_settings.imageModelId, ocrModels);
    final nextImageRecognitionId = _firstValidModelId(
      _settings.imageRecognitionModelId,
      chatModels,
    );
    final nextLastChatId = _firstValidModelId(
      _settings.lastChatModelId,
      chatModels,
    );

    if (nextSpeechId == _settings.speechModelId &&
        nextOcrId == _settings.imageModelId &&
        nextImageRecognitionId == _settings.imageRecognitionModelId &&
        nextLastChatId == _settings.lastChatModelId) {
      return;
    }

    _settings = _settings.copyWith(
      speechModelId: nextSpeechId,
      imageModelId: nextOcrId,
      imageRecognitionModelId: nextImageRecognitionId,
      lastChatModelId: nextLastChatId,
    );
    _queueSaveSettings();
    notifyListeners();
  }

  /// 将设置保存到 SharedPreferences
  void _queueSaveSettings() {
    final snapshot = _settings;
    _saveQueue = _saveQueue.then((_) => _saveSettingsSnapshot(snapshot));
  }

  Future<void> _saveSettingsSnapshot(AppSettings snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(snapshot.toJson());
      await prefs.setString(_storageKey, jsonString);
    } catch (e) {
      debugPrint('保存设置失败: $e');
    }
  }

  /// 更新主题颜色
  void setThemeColor(Color color) {
    _settings = _settings.copyWith(themeColor: color, baseThemeColor: color);
    _queueSaveSettings();
    notifyListeners();
  }

  void setLastFeature(String feature) {
    _settings = _settings.copyWith(lastFeature: feature);
    _queueSaveSettings();
    notifyListeners();
  }

  String addRole({
    required String name,
    String description = '',
    required String systemPrompt,
    String? modelId,
    Color? themeColor,
  }) {
    final id = const Uuid().v4();
    final role = ChatRole(
      id: id,
      name: name,
      description: description,
      systemPrompt: systemPrompt,
      modelId: modelId,
      themeColor: themeColor,
    );
    final prompt = SystemPrompt(id: id, title: name, content: systemPrompt);
    _settings = _settings.copyWith(
      roles: [..._settings.roles, role],
      systemPrompts: [..._settings.systemPrompts, prompt],
    );
    _queueSaveSettings();
    notifyListeners();
    return id;
  }

  void updateRole({
    required String id,
    required String name,
    String description = '',
    required String systemPrompt,
    String? modelId,
    Color? themeColor,
  }) {
    final roles = _settings.roles.map((role) {
      return role.id == id
          ? role.copyWith(
              name: name,
              description: description,
              systemPrompt: systemPrompt,
              modelId: modelId,
              themeColor: themeColor,
            )
          : role;
    }).toList();
    final prompts = _settings.systemPrompts.map((prompt) {
      return prompt.id == id
          ? prompt.copyWith(title: name, content: systemPrompt)
          : prompt;
    }).toList();
    final isCurrent = _settings.currentRoleId == id;
    var nextSettings = _settings.copyWith(roles: roles, systemPrompts: prompts);
    if (isCurrent) {
      nextSettings = nextSettings.copyWith(
        systemPrompt: systemPrompt,
        lastChatModelId: modelId ?? nextSettings.lastChatModelId,
        themeColor: themeColor ?? nextSettings.baseThemeColor,
      );
    }
    _settings = nextSettings;
    _queueSaveSettings();
    notifyListeners();
  }

  void deleteRole(String id) {
    if (id == ChatRole.defaultId) return;
    final roles = _settings.roles.where((role) => role.id != id).toList();
    final prompts = _settings.systemPrompts
        .where((prompt) => prompt.id != id)
        .toList();
    final deletingCurrent = _settings.currentRoleId == id;
    final defaultRole = ChatRole.defaultRole();
    var nextSettings = _settings.copyWith(
      roles: roles.isEmpty ? [ChatRole.defaultRole()] : roles,
      systemPrompts: prompts,
      currentRoleId: deletingCurrent
          ? ChatRole.defaultId
          : _settings.currentRoleId,
      selectedSystemPromptId: _settings.selectedSystemPromptId == id
          ? null
          : _settings.selectedSystemPromptId,
    );
    if (deletingCurrent) {
      nextSettings = nextSettings.copyWith(
        systemPrompt: defaultRole.systemPrompt,
      );
    }
    _settings = nextSettings;
    _queueSaveSettings();
    notifyListeners();
  }

  void selectRole(String roleId) {
    final role = _settings.roles.firstWhere(
      (r) => r.id == roleId,
      orElse: ChatRole.defaultRole,
    );
    final selectedPromptId = role.id == ChatRole.defaultId ? null : role.id;
    _settings = _settings.copyWith(
      currentRoleId: role.id,
      systemPrompt: role.systemPrompt,
      selectedSystemPromptId: selectedPromptId,
      lastChatModelId: role.modelId ?? _settings.lastChatModelId,
      themeColor: role.themeColor ?? _settings.baseThemeColor,
    );
    _queueSaveSettings();
    notifyListeners();
  }

  /// 设置背景图片路径
  void setBackgroundImage(String? path) {
    _settings = _settings.copyWith(backgroundImagePath: path);
    _queueSaveSettings();
    notifyListeners();
  }

  /// 设置毛玻璃效果开关
  void setBlurEnabled(bool enabled) {
    _settings = _settings.copyWith(blurEnabled: enabled);
    _queueSaveSettings();
    notifyListeners();
  }

  /// 设置模糊程度
  void setBlurAmount(double amount) {
    _settings = _settings.copyWith(blurAmount: amount);
    _queueSaveSettings();
    notifyListeners();
  }

  /// 设置语音转文字接口配置ID
  void setSpeechModelId(String? modelId) {
    _settings = _settings.copyWith(speechModelId: modelId);
    _queueSaveSettings();
    notifyListeners();
  }

  /// 设置 OCR 接口配置ID
  void setImageModelId(String? modelId) {
    _settings = _settings.copyWith(imageModelId: modelId);
    _queueSaveSettings();
    notifyListeners();
  }

  void setImageOcrEnabled(bool enabled) {
    _settings = _settings.copyWith(imageOcrEnabled: enabled);
    _queueSaveSettings();
    notifyListeners();
  }

  /// 设置文件识别模型配置ID
  void setImageRecognitionModelId(String? modelId) {
    _settings = _settings.copyWith(imageRecognitionModelId: modelId);
    _queueSaveSettings();
    notifyListeners();
  }

  /// 设置文件识别是否启用
  void setImageRecognitionEnabled(bool enabled) {
    _settings = _settings.copyWith(imageRecognitionEnabled: enabled);
    _queueSaveSettings();
    notifyListeners();
  }

  /// 记录新对话默认使用的 Chat 模型配置ID
  void setLastChatModelId(String? modelId) {
    _settings = _settings.copyWith(lastChatModelId: modelId);
    _queueSaveSettings();
    notifyListeners();
  }

  /// 设置文件识别结果发送给 Chat 时使用的提示词
  void setImageRecognitionPrompt(String prompt) {
    _settings = _settings.copyWith(imageRecognitionPrompt: prompt);
    _queueSaveSettings();
    notifyListeners();
  }

  String? _firstValidModelId(String? currentId, List<ModelConfig> models) {
    if (currentId != null && currentId.isNotEmpty) {
      final exists = models.any((m) => m.id == currentId);
      if (exists) return currentId;
    }
    return models.isEmpty ? null : models.first.id;
  }

  /// 设置系统提示词
  void setSystemPrompt(String prompt) {
    _settings = _settings.copyWith(systemPrompt: prompt);
    _queueSaveSettings();
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
    _queueSaveSettings();
    notifyListeners();
    return id;
  }

  /// 更新系统提示词模板
  void updateSystemPrompt(String id, String title, String content) {
    final list = _settings.systemPrompts.map((p) {
      return p.id == id ? p.copyWith(title: title, content: content) : p;
    }).toList();
    final roles = _settings.roles.map((role) {
      return role.id == id
          ? role.copyWith(name: title, systemPrompt: content)
          : role;
    }).toList();
    final isCurrentRolePrompt = _settings.currentRoleId == id;
    _settings = _settings.copyWith(
      systemPrompts: list,
      roles: roles,
      systemPrompt: isCurrentRolePrompt ? content : _settings.systemPrompt,
    );
    _queueSaveSettings();
    notifyListeners();
  }

  /// 删除系统提示词模板
  void deleteSystemPrompt(String id) {
    if (_settings.roles.any((role) => role.id == id)) {
      deleteRole(id);
      return;
    }
    final list = _settings.systemPrompts.where((p) => p.id != id).toList();
    String? newSelected = _settings.selectedSystemPromptId;
    if (newSelected == id) {
      newSelected = null;
    }
    _settings = _settings.copyWith(
      systemPrompts: list,
      selectedSystemPromptId: newSelected,
    );
    _queueSaveSettings();
    notifyListeners();
  }

  /// 选择当前使用的系统提示词
  void selectSystemPrompt(String? id) {
    _settings = _settings.copyWith(selectedSystemPromptId: id);
    _queueSaveSettings();
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
      imageOcrEnabled: settings.imageOcrEnabled,
      imageRecognitionModelId: settings.imageRecognitionModelId,
      imageRecognitionEnabled: settings.imageRecognitionEnabled,
      imageRecognitionPrompt: settings.imageRecognitionPrompt,
      systemPrompt: settings.systemPrompt,
      selectedSystemPromptId: settings.selectedSystemPromptId,
      lastChatModelId: settings.modelId,
    );
    _queueSaveSettings();
    notifyListeners();
  }

  /// 设置主题模式
  void setThemeMode(String mode) {
    _settings = _settings.copyWith(themeMode: mode);
    _queueSaveSettings();
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
