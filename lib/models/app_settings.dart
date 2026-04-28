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

  AppSettings({
    required this.themeColor,
    this.backgroundImagePath,
    this.blurEnabled = false,
    this.blurAmount = 5.0,
    this.speechModelId,
    this.imageModelId,
    this.imagePrompt = 'Describe this file in Chinese',
  });

  factory AppSettings.defaults() {
    return AppSettings(
      themeColor: Colors.blue,
    );
  }

  AppSettings copyWith({
    Color? themeColor,
    String? backgroundImagePath,
    bool? blurEnabled,
    double? blurAmount,
    String? speechModelId,
    String? imageModelId,
    String? imagePrompt,
  }) {
    return AppSettings(
      themeColor: themeColor ?? this.themeColor,
      backgroundImagePath: backgroundImagePath ?? this.backgroundImagePath,
      blurEnabled: blurEnabled ?? this.blurEnabled,
      blurAmount: blurAmount ?? this.blurAmount,
      speechModelId: speechModelId ?? this.speechModelId,
      imageModelId: imageModelId ?? this.imageModelId,
      imagePrompt: imagePrompt ?? this.imagePrompt,
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
    };
  }
}
