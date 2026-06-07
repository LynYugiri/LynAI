import 'package:flutter/material.dart';
import 'chat_role.dart';
import 'system_prompt.dart';

/// 应用级设置快照。
///
/// 保存主题、背景、最近模型、OCR/文件识别开关、角色和系统提示词。
/// 这个对象会整体序列化到 SharedPreferences，因此新增字段必须提供默认值
/// 或旧数据 fallback。
class AppSettings {
  final Color themeColor;
  final Color baseThemeColor;
  final String? backgroundImagePath;
  final bool blurEnabled;
  final double blurAmount;
  final String? speechModelId;
  final String? imageModelId;
  final bool imageOcrEnabled;
  final String? imageRecognitionModelId;
  final bool imageRecognitionEnabled;
  final String? lastChatModelId;
  final String imageRecognitionPrompt;
  final String systemPrompt;
  final List<SystemPrompt> systemPrompts;
  final String? selectedSystemPromptId;
  final String themeMode;
  final List<ChatRole> roles;
  final List<ChatRoleGroup> roleGroups;
  final String currentRoleId;
  final String lastFeature;
  final String? lastSeenChangelogVersion;

  AppSettings({
    required this.themeColor,
    required this.baseThemeColor,
    this.backgroundImagePath,
    this.blurEnabled = false,
    this.blurAmount = 5.0,
    this.speechModelId,
    this.imageModelId,
    this.imageOcrEnabled = false,
    this.imageRecognitionModelId,
    this.imageRecognitionEnabled = false,
    this.lastChatModelId,
    this.imageRecognitionPrompt = '请根据下面的文件内容或识别结果回答。',
    this.systemPrompt = 'You are a helpful assistant.',
    this.systemPrompts = const [],
    this.selectedSystemPromptId,
    this.themeMode = 'system',
    List<ChatRole>? roles,
    this.roleGroups = const [],
    this.currentRoleId = ChatRole.defaultId,
    this.lastFeature = 'dashboard',
    this.lastSeenChangelogVersion,
  }) : roles = roles ?? [ChatRole.defaultRole()];

  factory AppSettings.defaults() {
    return AppSettings(themeColor: Colors.blue, baseThemeColor: Colors.blue);
  }

  static const _sentinel = Object();

  AppSettings copyWith({
    Color? themeColor,
    Color? baseThemeColor,
    Object? backgroundImagePath = _sentinel,
    bool? blurEnabled,
    double? blurAmount,
    Object? speechModelId = _sentinel,
    Object? imageModelId = _sentinel,
    bool? imageOcrEnabled,
    Object? imageRecognitionModelId = _sentinel,
    bool? imageRecognitionEnabled,
    Object? lastChatModelId = _sentinel,
    String? imageRecognitionPrompt,
    String? systemPrompt,
    List<SystemPrompt>? systemPrompts,
    Object? selectedSystemPromptId = _sentinel,
    String? themeMode,
    List<ChatRole>? roles,
    List<ChatRoleGroup>? roleGroups,
    String? currentRoleId,
    String? lastFeature,
    Object? lastSeenChangelogVersion = _sentinel,
  }) {
    return AppSettings(
      themeColor: themeColor ?? this.themeColor,
      baseThemeColor: baseThemeColor ?? this.baseThemeColor,
      backgroundImagePath: identical(backgroundImagePath, _sentinel)
          ? this.backgroundImagePath
          : backgroundImagePath as String?,
      blurEnabled: blurEnabled ?? this.blurEnabled,
      blurAmount: blurAmount ?? this.blurAmount,
      speechModelId: identical(speechModelId, _sentinel)
          ? this.speechModelId
          : speechModelId as String?,
      imageModelId: identical(imageModelId, _sentinel)
          ? this.imageModelId
          : imageModelId as String?,
      imageOcrEnabled: imageOcrEnabled ?? this.imageOcrEnabled,
      imageRecognitionModelId: identical(imageRecognitionModelId, _sentinel)
          ? this.imageRecognitionModelId
          : imageRecognitionModelId as String?,
      imageRecognitionEnabled:
          imageRecognitionEnabled ?? this.imageRecognitionEnabled,
      lastChatModelId: identical(lastChatModelId, _sentinel)
          ? this.lastChatModelId
          : lastChatModelId as String?,
      imageRecognitionPrompt:
          imageRecognitionPrompt ?? this.imageRecognitionPrompt,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      systemPrompts: systemPrompts ?? this.systemPrompts,
      selectedSystemPromptId: identical(selectedSystemPromptId, _sentinel)
          ? this.selectedSystemPromptId
          : selectedSystemPromptId as String?,
      themeMode: themeMode ?? this.themeMode,
      roles: roles ?? this.roles,
      roleGroups: roleGroups ?? this.roleGroups,
      currentRoleId: currentRoleId ?? this.currentRoleId,
      lastFeature: lastFeature ?? this.lastFeature,
      lastSeenChangelogVersion: identical(lastSeenChangelogVersion, _sentinel)
          ? this.lastSeenChangelogVersion
          : lastSeenChangelogVersion as String?,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final promptsJson = json['systemPrompts'] as List<dynamic>?;
    final prompts = <SystemPrompt>[];
    for (final item in promptsJson ?? const <dynamic>[]) {
      try {
        if (item is Map) {
          prompts.add(SystemPrompt.fromJson(Map<String, dynamic>.from(item)));
        }
      } catch (e) {
        debugPrint('跳过损坏的系统提示词: $e');
      }
    }
    final selectedId = json['selectedSystemPromptId'] as String?;
    final rolesJson = json['roles'] as List<dynamic>?;
    var roles = <ChatRole>[];
    for (final item in rolesJson ?? const <dynamic>[]) {
      try {
        if (item is Map) {
          roles.add(
            ChatRole.normalizeDefaultRole(
              ChatRole.fromJson(Map<String, dynamic>.from(item)),
            ),
          );
        }
      } catch (e) {
        debugPrint('跳过损坏的角色配置: $e');
      }
    }
    if (roles.every((r) => r.id != ChatRole.defaultId)) {
      roles = [ChatRole.defaultRole(), ...roles];
    }
    if (roles.isEmpty) roles = [ChatRole.defaultRole()];
    final validRoleIds = roles.map((role) => role.id).toSet();
    final groupsJson = json['roleGroups'] as List<dynamic>?;
    final roleGroups = <ChatRoleGroup>[];
    final usedGroupIds = <String>{};
    for (final item in groupsJson ?? const <dynamic>[]) {
      try {
        if (item is Map) {
          final group = ChatRoleGroup.fromJson(Map<String, dynamic>.from(item));
          if (group.id.isEmpty || group.name.trim().isEmpty) continue;
          if (!usedGroupIds.add(group.id)) continue;
          roleGroups.add(
            group.copyWith(
              name: group.name.trim(),
              roleIds: group.roleIds
                  .where(validRoleIds.contains)
                  .toSet()
                  .toList(),
            ),
          );
        }
      } catch (e) {
        debugPrint('跳过损坏的角色分组配置: $e');
      }
    }
    final currentRoleId =
        json['currentRoleId'] as String? ?? ChatRole.defaultId;
    Color defaultColor = Color(Colors.blue.toARGB32());
    Color themeColor = Color(
      json['themeColor'] as int? ?? defaultColor.toARGB32(),
    );
    Color baseThemeColor = Color(
      json['baseThemeColor'] as int? ?? themeColor.toARGB32(),
    );
    return AppSettings(
      themeColor: themeColor,
      baseThemeColor: baseThemeColor,
      backgroundImagePath: json['backgroundImagePath'] as String?,
      blurEnabled: json['blurEnabled'] as bool? ?? false,
      blurAmount: (json['blurAmount'] as num?)?.toDouble() ?? 5.0,
      speechModelId: json['speechModelId'] as String?,
      imageModelId: json['imageModelId'] as String?,
      imageOcrEnabled: json['imageOcrEnabled'] as bool? ?? false,
      imageRecognitionModelId: json['imageRecognitionModelId'] as String?,
      imageRecognitionEnabled:
          json['imageRecognitionEnabled'] as bool? ?? false,
      lastChatModelId: json['lastChatModelId'] as String?,
      imageRecognitionPrompt:
          json['imageRecognitionPrompt'] as String? ??
          json['imagePrompt'] as String? ??
          '请根据下面的文件内容或识别结果回答。',
      systemPrompt:
          json['systemPrompt'] as String? ?? 'You are a helpful assistant.',
      systemPrompts: prompts,
      selectedSystemPromptId: selectedId,
      themeMode: json['themeMode'] as String? ?? 'system',
      roles: roles,
      roleGroups: roleGroups,
      currentRoleId: roles.any((r) => r.id == currentRoleId)
          ? currentRoleId
          : ChatRole.defaultId,
      lastFeature: json['lastFeature'] as String? ?? 'dashboard',
      lastSeenChangelogVersion: json['lastSeenChangelogVersion'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'themeColor': themeColor.toARGB32(),
      'baseThemeColor': baseThemeColor.toARGB32(),
      'backgroundImagePath': backgroundImagePath,
      'blurEnabled': blurEnabled,
      'blurAmount': blurAmount,
      if (speechModelId != null) 'speechModelId': speechModelId,
      if (imageModelId != null) 'imageModelId': imageModelId,
      'imageOcrEnabled': imageOcrEnabled,
      if (imageRecognitionModelId != null)
        'imageRecognitionModelId': imageRecognitionModelId,
      'imageRecognitionEnabled': imageRecognitionEnabled,
      if (lastChatModelId != null) 'lastChatModelId': lastChatModelId,
      'imageRecognitionPrompt': imageRecognitionPrompt,
      'systemPrompt': systemPrompt,
      'systemPrompts': systemPrompts.map((e) => e.toJson()).toList(),
      if (selectedSystemPromptId != null)
        'selectedSystemPromptId': selectedSystemPromptId,
      'themeMode': themeMode,
      'roles': roles.map((e) => e.toJson()).toList(),
      'roleGroups': roleGroups.map((e) => e.toJson()).toList(),
      'currentRoleId': currentRoleId,
      'lastFeature': lastFeature,
      if (lastSeenChangelogVersion != null)
        'lastSeenChangelogVersion': lastSeenChangelogVersion,
    };
  }
}
