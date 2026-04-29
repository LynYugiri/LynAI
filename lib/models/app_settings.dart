import 'package:flutter/material.dart';

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
  final String themeMode;

  AppSettings({
    required this.themeColor,
    this.backgroundImagePath,
    this.blurEnabled = false,
    this.blurAmount = 5.0,
    this.speechModelId,
    this.imageModelId,
    this.imagePrompt = 'Describe this file in Chinese',
    this.themeMode = 'light',
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
      themeMode: themeMode ?? this.themeMode,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeColor: Color(json['themeColor'] as int),
      backgroundImagePath: json['backgroundImagePath'] as String?,
      blurEnabled: json['blurEnabled'] as bool? ?? false,
      blurAmount: (json['blurAmount'] as num?)?.toDouble() ?? 5.0,
      speechModelId: json['speechModelId'] as String?,
      imageModelId: json['imageModelId'] as String?,
      imagePrompt: json['imagePrompt'] as String? ?? 'Describe this file in Chinese',
      themeMode: json['themeMode'] as String? ?? 'light',
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
      'themeMode': themeMode,
    };
  }
}
