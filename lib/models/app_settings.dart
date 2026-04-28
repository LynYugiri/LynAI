import 'package:flutter/material.dart';

/// 应用设置数据模型
///
/// 存储用户的应用偏好设置。
/// [themeColor] 自定义主题颜色
/// [backgroundImagePath] 背景图片的本地路径，null 表示未设置
/// [blurEnabled] 是否启用毛玻璃效果
/// [blurAmount] 模糊程度（0.0 - 20.0）
class AppSettings {
  final Color themeColor;
  final String? backgroundImagePath;
  final bool blurEnabled;
  final double blurAmount;

  AppSettings({
    required this.themeColor,
    this.backgroundImagePath,
    this.blurEnabled = false,
    this.blurAmount = 5.0,
  });

  /// 默认设置
  factory AppSettings.defaults() {
    return AppSettings(
      themeColor: Colors.blue,
      backgroundImagePath: null,
      blurEnabled: false,
      blurAmount: 5.0,
    );
  }

  /// 创建 AppSettings 的副本，可选地覆盖某些字段
  AppSettings copyWith({
    Color? themeColor,
    String? backgroundImagePath,
    bool? blurEnabled,
    double? blurAmount,
  }) {
    return AppSettings(
      themeColor: themeColor ?? this.themeColor,
      backgroundImagePath:
          backgroundImagePath ?? this.backgroundImagePath,
      blurEnabled: blurEnabled ?? this.blurEnabled,
      blurAmount: blurAmount ?? this.blurAmount,
    );
  }

  /// 从 JSON Map 创建 AppSettings 实例
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeColor: Color(json['themeColor'] as int),
      backgroundImagePath: json['backgroundImagePath'] as String?,
      blurEnabled: json['blurEnabled'] as bool? ?? false,
      blurAmount: (json['blurAmount'] as num?)?.toDouble() ?? 5.0,
    );
  }

  /// 将 AppSettings 转换为 JSON Map，用于持久化存储
  Map<String, dynamic> toJson() {
    return {
      'themeColor': themeColor.toARGB32(),
      'backgroundImagePath': backgroundImagePath,
      'blurEnabled': blurEnabled,
      'blurAmount': blurAmount,
    };
  }
}

