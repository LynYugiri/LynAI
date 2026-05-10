import 'package:flutter/material.dart';

class ChatRole {
  static const defaultId = 'default';

  final String id;
  final String name;
  final String systemPrompt;
  final String? modelId;
  final Color? themeColor;

  const ChatRole({
    required this.id,
    required this.name,
    required this.systemPrompt,
    this.modelId,
    this.themeColor,
  });

  factory ChatRole.defaultRole() {
    return const ChatRole(
      id: defaultId,
      name: '默认',
      systemPrompt: 'You are a helpful assistant.',
    );
  }

  factory ChatRole.fromJson(Map<String, dynamic> json) {
    final colorValue = json['themeColor'] as int?;
    return ChatRole(
      id: json['id'] as String? ?? defaultId,
      name: json['name'] as String? ?? '默认',
      systemPrompt:
          json['systemPrompt'] as String? ?? 'You are a helpful assistant.',
      modelId: json['modelId'] as String?,
      themeColor: colorValue == null ? null : Color(colorValue),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'systemPrompt': systemPrompt,
      if (modelId != null) 'modelId': modelId,
      if (themeColor != null) 'themeColor': themeColor!.toARGB32(),
    };
  }

  ChatRole copyWith({
    String? name,
    String? systemPrompt,
    Object? modelId = _sentinel,
    Object? themeColor = _sentinel,
  }) {
    return ChatRole(
      id: id,
      name: name ?? this.name,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      modelId: identical(modelId, _sentinel)
          ? this.modelId
          : modelId as String?,
      themeColor: identical(themeColor, _sentinel)
          ? this.themeColor
          : themeColor as Color?,
    );
  }

  static const _sentinel = Object();
}
