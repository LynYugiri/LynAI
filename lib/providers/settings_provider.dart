import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/app_settings.dart';
import '../models/chat_role.dart';
import '../models/conversation.dart';
import '../models/model_config.dart';
import '../models/system_prompt.dart';
import '../repositories/settings_repository.dart';
import '../services/storage_v2_service.dart';

/// 管理应用级设置、角色、系统提示词和最近使用模型。
///
/// 设置是跨页面共享的 UI 状态。修改后立即通知界面，并把不可变快照排入
/// 串行保存队列；这样快速切换主题、角色或模型时不会出现旧设置覆盖新设置。
class SettingsProvider extends ChangeNotifier {
  AppSettings _settings = AppSettings.defaults();
  Future<void> _saveQueue = Future.value();
  final SettingsRepository _repository;
  bool _usingStorageV2 = false;

  SettingsProvider({
    StorageV2Service? storageV2,
    SettingsRepository? repository,
  }) : _repository = repository ?? SettingsRepository(storageV2: storageV2);

  AppSettings get settings => _settings;
  bool get usingStorageV2 => _usingStorageV2;

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

  /// 从本地 repository 加载设置。
  ///
  /// 角色和提示词的单条坏数据由 [AppSettings.fromJson] 跳过；顶层结构损坏
  /// 时回退默认设置，保证应用仍可启动。
  Future<void> loadSettings() async {
    try {
      final result = await _repository.load(_settings);
      _settings = result.settings;
      _usingStorageV2 = result.usingStorageV2;
      notifyListeners();
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
        .where((m) => m.enabledModelNames.isNotEmpty)
        .toList(growable: false);
    final speechModels = models
        .where((m) => m.category == ModelConfig.categorySpeech)
        .where((m) => m.enabledModelNames.isNotEmpty)
        .toList(growable: false);
    final ocrModels = models
        .where((m) => m.category == ModelConfig.categoryOcr)
        .where((m) => m.enabledModelNames.isNotEmpty)
        .toList(growable: false);
    final imageGenerationModels = models
        .where((m) => m.category == ModelConfig.categoryImageGeneration)
        .where((m) => m.enabledModelNames.isNotEmpty)
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
    final nextImageGenerationId = _firstValidModelId(
      _settings.imageGenerationModelId,
      imageGenerationModels,
    );
    final nextLastChatId = _firstValidModelId(
      _settings.lastChatModelId,
      chatModels,
    );
    final validChatIds = chatModels.map((model) => model.id).toSet();
    var rolesChanged = false;
    final nextRoles = _settings.roles
        .map((role) {
          final modelId = role.modelId;
          if (modelId == null ||
              modelId.isEmpty ||
              validChatIds.contains(modelId)) {
            return role;
          }
          rolesChanged = true;
          return role.copyWith(modelId: null, modelName: null);
        })
        .toList(growable: false);

    if (nextSpeechId == _settings.speechModelId &&
        nextOcrId == _settings.imageModelId &&
        nextImageRecognitionId == _settings.imageRecognitionModelId &&
        nextImageGenerationId == _settings.imageGenerationModelId &&
        nextLastChatId == _settings.lastChatModelId &&
        !rolesChanged) {
      return;
    }

    _settings = _settings.copyWith(
      speechModelId: nextSpeechId,
      imageModelId: nextOcrId,
      imageRecognitionModelId: nextImageRecognitionId,
      imageGenerationModelId: nextImageGenerationId,
      lastChatModelId: nextLastChatId,
      roles: nextRoles,
    );
    _queueSaveSettings();
    notifyListeners();
  }

  /// 将设置快照排入保存队列。
  void _queueSaveSettings() {
    final snapshot = _settings;
    _saveQueue = _saveQueue.then((_) => _saveSettingsSnapshot(snapshot));
  }

  Future<void> _saveSettingsSnapshot(AppSettings snapshot) async {
    try {
      await _repository.save(snapshot, usingStorageV2: _usingStorageV2);
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
    String? modelName,
    Color? themeColor,
    List<String> groupIds = const [],
  }) {
    final id = const Uuid().v4();
    final role = ChatRole(
      id: id,
      name: name,
      description: description,
      systemPrompt: systemPrompt,
      modelId: modelId,
      modelName: modelName,
      themeColor: themeColor,
    );
    final prompt = SystemPrompt(id: id, title: name, content: systemPrompt);
    final groups = _roleGroupsWithMembership(
      _settings.roleGroups,
      id,
      groupIds,
    );
    _settings = _settings.copyWith(
      roles: [..._settings.roles, role],
      roleGroups: groups,
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
    String? modelName,
    Color? themeColor,
    List<String>? groupIds,
  }) {
    final roles = _settings.roles.map((role) {
      return role.id == id
          ? role.copyWith(
              name: name,
              description: description,
              systemPrompt: systemPrompt,
              modelId: modelId,
              modelName: modelName,
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
    var nextSettings = _settings.copyWith(
      roles: roles,
      systemPrompts: prompts,
      roleGroups: groupIds == null
          ? _settings.roleGroups
          : _roleGroupsWithMembership(_settings.roleGroups, id, groupIds),
    );
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
    final now = DateTime.now();
    final groups = _settings.roleGroups.map((group) {
      if (!group.roleIds.contains(id)) return group;
      return group.copyWith(
        roleIds: group.roleIds.where((roleId) => roleId != id).toList(),
        updatedAt: now,
      );
    }).toList();
    final prompts = _settings.systemPrompts
        .where((prompt) => prompt.id != id)
        .toList();
    final deletingCurrent = _settings.currentRoleId == id;
    final defaultRole = ChatRole.defaultRole();
    var nextSettings = _settings.copyWith(
      roles: roles.isEmpty ? [ChatRole.defaultRole()] : roles,
      roleGroups: groups,
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

  String addRoleGroup(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    final now = DateTime.now();
    final id = const Uuid().v4();
    final group = ChatRoleGroup(
      id: id,
      name: trimmed,
      createdAt: now,
      updatedAt: now,
    );
    _settings = _settings.copyWith(
      roleGroups: [..._settings.roleGroups, group],
    );
    _queueSaveSettings();
    notifyListeners();
    return id;
  }

  void updateRoleGroup(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    var changed = false;
    final now = DateTime.now();
    final groups = _settings.roleGroups.map((group) {
      if (group.id != id) return group;
      changed = true;
      return group.copyWith(name: trimmed, updatedAt: now);
    }).toList();
    if (!changed) return;
    _settings = _settings.copyWith(roleGroups: groups);
    _queueSaveSettings();
    notifyListeners();
  }

  void deleteRoleGroup(String id) {
    final groups = _settings.roleGroups
        .where((group) => group.id != id)
        .toList();
    if (groups.length == _settings.roleGroups.length) return;
    _settings = _settings.copyWith(roleGroups: groups);
    _queueSaveSettings();
    notifyListeners();
  }

  void setRoleGroups(String roleId, List<String> groupIds) {
    if (!_settings.roles.any((role) => role.id == roleId)) return;
    _settings = _settings.copyWith(
      roleGroups: _roleGroupsWithMembership(
        _settings.roleGroups,
        roleId,
        groupIds,
      ),
    );
    _queueSaveSettings();
    notifyListeners();
  }

  List<ChatRoleGroup> groupsForRole(String roleId) {
    return _settings.roleGroups
        .where((group) => group.roleIds.contains(roleId))
        .toList(growable: false);
  }

  List<ChatRole> rolesInGroup(String groupId) {
    final group = _settings.roleGroups.firstWhere(
      (group) => group.id == groupId,
      orElse: () => ChatRoleGroup(
        id: '',
        name: '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
    if (group.id.isEmpty) return const [];
    final roleById = {for (final role in _settings.roles) role.id: role};
    return group.roleIds
        .map((id) => roleById[id])
        .whereType<ChatRole>()
        .toList(growable: false);
  }

  List<ChatRole> ungroupedRoles() {
    final grouped = _settings.roleGroups
        .expand((group) => group.roleIds)
        .toSet();
    return _settings.roles
        .where((role) => !grouped.contains(role.id))
        .toList(growable: false);
  }

  List<ChatRoleGroup> _roleGroupsWithMembership(
    List<ChatRoleGroup> groups,
    String roleId,
    List<String> groupIds,
  ) {
    final selected = groupIds.toSet();
    final now = DateTime.now();
    return groups.map((group) {
      final ids = group.roleIds.toSet();
      final before = ids.contains(roleId);
      if (selected.contains(group.id)) {
        ids.add(roleId);
      } else {
        ids.remove(roleId);
      }
      final next = ids.toList();
      if (before == ids.contains(roleId) &&
          next.length == group.roleIds.length) {
        return group;
      }
      return group.copyWith(roleIds: next, updatedAt: now);
    }).toList();
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

  /// 设置图片生成模型配置ID
  void setImageGenerationModelId(String? modelId) {
    _settings = _settings.copyWith(imageGenerationModelId: modelId);
    _queueSaveSettings();
    notifyListeners();
  }

  /// 设置图片生成工具是否启用
  void setImageGenerationEnabled(bool enabled) {
    _settings = _settings.copyWith(imageGenerationEnabled: enabled);
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

  void updateFloatingAssistant(FloatingAssistantSettings settings) {
    _settings = _settings.copyWith(floatingAssistant: settings);
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
      imageGenerationModelId: settings.imageGenerationModelId,
      imageGenerationEnabled: settings.imageGenerationEnabled,
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

  /// 更新后端连接地址。传入 null 断开连接。
  void updateBackendUrl(String? url) {
    _settings = _settings.copyWith(backendUrl: url);
    _queueSaveSettings();
    notifyListeners();
  }
}
