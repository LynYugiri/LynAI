import 'package:flutter/material.dart';
import 'system_prompt.dart';

/// 应用设置数据模型
///
/// 存储用户的应用偏好设置。
class AppSettings {
  final Color themeColor;
  final String? backgroundImagePath;
  final bool blurEnabled;
  final double blurAmount;
  final String? speechModelId;
  final String? imageModelId;
  final String imagePrompt;
  final String systemPrompt;
  final List<SystemPrompt> systemPrompts;
  final String? selectedSystemPromptId;
  final String themeMode;

  AppSettings({
    required this.themeColor,
    this.backgroundImagePath,
    this.blurEnabled = false,
    this.blurAmount = 5.0,
    this.speechModelId,
    this.imageModelId,
    this.imagePrompt = 'Describe this file in Chinese',
    this.systemPrompt = 'You are a helpful assistant.',
    this.systemPrompts = const [],
    this.selectedSystemPromptId,
    this.themeMode = 'system',
  });

  factory AppSettings.defaults() {
    return AppSettings(
      themeColor: Colors.blue,
    );
  }

  static const _sentinel = Object();

  AppSettings copyWith({
    Color? themeColor,
    Object? backgroundImagePath = _sentinel,
    bool? blurEnabled,
    double? blurAmount,
    Object? speechModelId = _sentinel,
    Object? imageModelId = _sentinel,
    String? imagePrompt,
    String? systemPrompt,
    List<SystemPrompt>? systemPrompts,
    Object? selectedSystemPromptId = _sentinel,
    String? themeMode,
  }) {
    return AppSettings(
      themeColor: themeColor ?? this.themeColor,
      backgroundImagePath: identical(backgroundImagePath, _sentinel) ? this.backgroundImagePath : backgroundImagePath as String?,
      blurEnabled: blurEnabled ?? this.blurEnabled,
      blurAmount: blurAmount ?? this.blurAmount,
      speechModelId: identical(speechModelId, _sentinel) ? this.speechModelId : speechModelId as String?,
      imageModelId: identical(imageModelId, _sentinel) ? this.imageModelId : imageModelId as String?,
      imagePrompt: imagePrompt ?? this.imagePrompt,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      systemPrompts: systemPrompts ?? this.systemPrompts,
      selectedSystemPromptId: identical(selectedSystemPromptId, _sentinel) ? this.selectedSystemPromptId : selectedSystemPromptId as String?,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final promptsJson = json['systemPrompts'] as List<dynamic>?;
    final prompts = promptsJson != null
        ? promptsJson.map((e) => SystemPrompt.fromJson(e as Map<String, dynamic>)).toList()
        : <SystemPrompt>[];
    final selectedId = json['selectedSystemPromptId'] as String?;
    return AppSettings(
      themeColor: Color(json['themeColor'] as int),
      backgroundImagePath: json['backgroundImagePath'] as String?,
      blurEnabled: json['blurEnabled'] as bool? ?? false,
      blurAmount: (json['blurAmount'] as num?)?.toDouble() ?? 5.0,
      speechModelId: json['speechModelId'] as String?,
      imageModelId: json['imageModelId'] as String?,
      imagePrompt: json['imagePrompt'] as String? ?? 'Describe this file in Chinese',
      systemPrompt: json['systemPrompt'] as String? ?? 'You are a helpful assistant.',
      systemPrompts: prompts,
      selectedSystemPromptId: selectedId,
      themeMode: json['themeMode'] as String? ?? 'system',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'themeColor': themeColor.toARGB32(),
      'backgroundImagePath': backgroundImagePath,
      'blurEnabled': blurEnabled,
      'blurAmount': blurAmount,
      if (speechModelId != null) 'speechModelId': speechModelId,
      if (imageModelId != null) 'imageModelId': imageModelId,
      'imagePrompt': imagePrompt,
      'systemPrompt': systemPrompt,
      'systemPrompts': systemPrompts.map((e) => e.toJson()).toList(),
      if (selectedSystemPromptId != null) 'selectedSystemPromptId': selectedSystemPromptId,
      'themeMode': themeMode,
    };
  }
}
