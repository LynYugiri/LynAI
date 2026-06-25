import 'package:flutter/material.dart';
import 'chat_role.dart';
import 'system_prompt.dart';
import '../services/lynai_permission_definitions.dart';

class FloatingAssistantSettings {
  static const screenContextManual = 'manual';
  static const screenContextDisabled = 'disabled';
  static const voiceInputSystem = 'system';
  static const voiceInputServer = 'server';
  static const voiceInputDisabled = 'disabled';
  static const mangaLayoutAuto = 'auto';
  static const mangaLayoutHorizontal = 'horizontal';
  static const mangaLayoutVertical = 'vertical';
  static const mangaOverlayAuto = 'auto';
  static const mangaOverlayLight = 'light';
  static const mangaOverlayDark = 'dark';
  static const mangaOverlayStroke = 'stroke';

  final bool enabled;
  final bool showBubbleInBackground;
  final bool showAgentPlan;
  final bool allowScreenContext;
  final String screenContextMode;
  final String voiceInputMode;
  final bool showMangaTranslationAction;
  final String mangaTargetLanguage;
  final String mangaLayoutMode;
  final String mangaOverlayStyle;
  final double mangaOverlayOpacity;
  final List<String> blockedPackages;
  final int bubbleX;
  final int bubbleY;
  final int panelX;
  final int panelY;
  final int panelWidth;
  final int panelHeight;
  final String? translationModelId;

  static const defaultPosition = -1;

  const FloatingAssistantSettings({
    this.enabled = false,
    this.showBubbleInBackground = true,
    this.showAgentPlan = true,
    this.allowScreenContext = false,
    this.screenContextMode = screenContextManual,
    this.voiceInputMode = voiceInputSystem,
    this.showMangaTranslationAction = true,
    this.mangaTargetLanguage = 'zh-CN',
    this.mangaLayoutMode = mangaLayoutAuto,
    this.mangaOverlayStyle = mangaOverlayAuto,
    this.mangaOverlayOpacity = 0.92,
    this.blockedPackages = const [],
    this.bubbleX = defaultPosition,
    this.bubbleY = defaultPosition,
    this.panelX = defaultPosition,
    this.panelY = defaultPosition,
    this.panelWidth = defaultPosition,
    this.panelHeight = defaultPosition,
    this.translationModelId,
  });

  factory FloatingAssistantSettings.fromJson(Object? raw) {
    if (raw is! Map) return const FloatingAssistantSettings();
    final json = Map<String, dynamic>.from(raw);
    return FloatingAssistantSettings(
      enabled: json['enabled'] as bool? ?? false,
      showBubbleInBackground: json['showBubbleInBackground'] as bool? ?? true,
      showAgentPlan: json['showAgentPlan'] as bool? ?? true,
      allowScreenContext: json['allowScreenContext'] as bool? ?? false,
      screenContextMode: _enumString(json['screenContextMode'], const {
        screenContextManual,
        screenContextDisabled,
      }, screenContextManual),
      voiceInputMode: _enumString(json['voiceInputMode'], const {
        voiceInputSystem,
        voiceInputServer,
        voiceInputDisabled,
      }, voiceInputSystem),
      showMangaTranslationAction:
          json['showMangaTranslationAction'] as bool? ?? true,
      mangaTargetLanguage:
          (json['mangaTargetLanguage'] as String?)?.trim().isNotEmpty == true
          ? (json['mangaTargetLanguage'] as String).trim()
          : 'zh-CN',
      mangaLayoutMode: _enumString(json['mangaLayoutMode'], const {
        mangaLayoutAuto,
        mangaLayoutHorizontal,
        mangaLayoutVertical,
      }, mangaLayoutAuto),
      mangaOverlayStyle: _enumString(json['mangaOverlayStyle'], const {
        mangaOverlayAuto,
        mangaOverlayLight,
        mangaOverlayDark,
        mangaOverlayStroke,
      }, mangaOverlayAuto),
      mangaOverlayOpacity:
          ((json['mangaOverlayOpacity'] as num?)?.toDouble() ?? 0.92).clamp(
            0.2,
            1.0,
          ),
      blockedPackages: (json['blockedPackages'] as List<dynamic>? ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(growable: false),
      bubbleX: (json['bubbleX'] as num?)?.toInt() ?? defaultPosition,
      bubbleY: (json['bubbleY'] as num?)?.toInt() ?? defaultPosition,
      panelX: (json['panelX'] as num?)?.toInt() ?? defaultPosition,
      panelY: (json['panelY'] as num?)?.toInt() ?? defaultPosition,
      panelWidth: (json['panelWidth'] as num?)?.toInt() ?? defaultPosition,
      panelHeight: (json['panelHeight'] as num?)?.toInt() ?? defaultPosition,
      translationModelId: (json['translationModelId'] as String?)
          ?.trim()
          .isEmpty == true
          ? null
          : json['translationModelId'] as String?,
    );
  }

  FloatingAssistantSettings copyWith({
    bool? enabled,
    bool? showBubbleInBackground,
    bool? showAgentPlan,
    bool? allowScreenContext,
    String? screenContextMode,
    String? voiceInputMode,
    bool? showMangaTranslationAction,
    String? mangaTargetLanguage,
    String? mangaLayoutMode,
    String? mangaOverlayStyle,
    double? mangaOverlayOpacity,
    List<String>? blockedPackages,
    int? bubbleX,
    int? bubbleY,
    int? panelX,
    int? panelY,
    int? panelWidth,
    int? panelHeight,
    String? translationModelId,
    bool clearTranslationModel = false,
  }) {
    return FloatingAssistantSettings(
      enabled: enabled ?? this.enabled,
      showBubbleInBackground:
          showBubbleInBackground ?? this.showBubbleInBackground,
      showAgentPlan: showAgentPlan ?? this.showAgentPlan,
      allowScreenContext: allowScreenContext ?? this.allowScreenContext,
      screenContextMode: screenContextMode ?? this.screenContextMode,
      voiceInputMode: voiceInputMode ?? this.voiceInputMode,
      showMangaTranslationAction:
          showMangaTranslationAction ?? this.showMangaTranslationAction,
      mangaTargetLanguage: mangaTargetLanguage ?? this.mangaTargetLanguage,
      mangaLayoutMode: mangaLayoutMode ?? this.mangaLayoutMode,
      mangaOverlayStyle: mangaOverlayStyle ?? this.mangaOverlayStyle,
      mangaOverlayOpacity: mangaOverlayOpacity ?? this.mangaOverlayOpacity,
      blockedPackages: blockedPackages ?? this.blockedPackages,
      bubbleX: bubbleX ?? this.bubbleX,
      bubbleY: bubbleY ?? this.bubbleY,
      panelX: panelX ?? this.panelX,
      panelY: panelY ?? this.panelY,
      panelWidth: panelWidth ?? this.panelWidth,
      panelHeight: panelHeight ?? this.panelHeight,
      translationModelId: clearTranslationModel
          ? null
          : translationModelId ?? this.translationModelId,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'showBubbleInBackground': showBubbleInBackground,
        'showAgentPlan': showAgentPlan,
        'allowScreenContext': allowScreenContext,
        'screenContextMode': screenContextMode,
        'voiceInputMode': voiceInputMode,
        'showMangaTranslationAction': showMangaTranslationAction,
        'mangaTargetLanguage': mangaTargetLanguage,
        'mangaLayoutMode': mangaLayoutMode,
        'mangaOverlayStyle': mangaOverlayStyle,
        'mangaOverlayOpacity': mangaOverlayOpacity,
        'blockedPackages': blockedPackages,
        'bubbleX': bubbleX,
        'bubbleY': bubbleY,
        'panelX': panelX,
        'panelY': panelY,
        'panelWidth': panelWidth,
        'panelHeight': panelHeight,
        'translationModelId': translationModelId,
      };

  static String _enumString(Object? raw, Set<String> allowed, String fallback) {
    final value = raw?.toString();
    if (value != null && allowed.contains(value)) return value;
    return fallback;
  }
}

/// 应用级设置快照。
///
/// 保存主题、背景、最近模型、OCR/文件识别开关、角色和系统提示词。
/// 这个对象会整体序列化到 storage_v2，因此新增字段必须提供默认值
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
  final String? imageGenerationModelId;
  final bool imageGenerationEnabled;
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
  final List<String> agentGrantedPermissions;
  final FloatingAssistantSettings floatingAssistant;

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
    this.imageGenerationModelId,
    this.imageGenerationEnabled = false,
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
    this.agentGrantedPermissions = LynAIPermissions.defaultAgent,
    this.floatingAssistant = const FloatingAssistantSettings(),
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
    Object? imageGenerationModelId = _sentinel,
    bool? imageGenerationEnabled,
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
    List<String>? agentGrantedPermissions,
    FloatingAssistantSettings? floatingAssistant,
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
      imageGenerationModelId: identical(imageGenerationModelId, _sentinel)
          ? this.imageGenerationModelId
          : imageGenerationModelId as String?,
      imageGenerationEnabled:
          imageGenerationEnabled ?? this.imageGenerationEnabled,
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
      agentGrantedPermissions:
          agentGrantedPermissions ?? this.agentGrantedPermissions,
      floatingAssistant: floatingAssistant ?? this.floatingAssistant,
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
      imageGenerationModelId: json['imageGenerationModelId'] as String?,
      imageGenerationEnabled: json['imageGenerationEnabled'] as bool? ?? false,
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
      agentGrantedPermissions: _agentPermissionsFromJson(
        json['agentGrantedPermissions'],
      ),
      floatingAssistant: FloatingAssistantSettings.fromJson(
        json['floatingAssistant'],
      ),
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
      if (imageGenerationModelId != null)
        'imageGenerationModelId': imageGenerationModelId,
      'imageGenerationEnabled': imageGenerationEnabled,
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
      'agentGrantedPermissions': agentGrantedPermissions,
      'floatingAssistant': floatingAssistant.toJson(),
    };
  }

  static List<String> _agentPermissionsFromJson(Object? raw) {
    final restored = raw is List
        ? raw
              .map((item) => item.toString())
              .where((item) => LynAIPermissions.agentAssignable.contains(item))
              .toSet()
        : <String>{};
    return LynAIPermissions.defaultAgent
        .where(
          (permission) =>
              raw == null ||
              restored.contains(permission) ||
              permission.startsWith('device:'),
        )
        .toList(growable: false);
  }
}
