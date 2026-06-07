import 'package:flutter/material.dart';

class ChatRole {
  static const defaultId = 'default';
  static const legacyDefaultSystemPrompt = 'You are a helpful assistant.';
  static const defaultSystemPrompt =
      'You are a helpful assistant. Never print or expose DSML, XML-style tool tags, pseudo tool calls, or raw function-calling markup to the user. When tools are available, use only the native OpenAI tool-calling interface. If tool calling is unavailable or disallowed, reply in plain natural language instead of simulating a tool call in text.';

  final String id;
  final String name;
  final String description;
  final String systemPrompt;
  final String? modelId;
  final String? modelName;
  final Color? themeColor;

  const ChatRole({
    required this.id,
    required this.name,
    this.description = '',
    required this.systemPrompt,
    this.modelId,
    this.modelName,
    this.themeColor,
  });

  factory ChatRole.defaultRole() {
    return const ChatRole(
      id: defaultId,
      name: '默认',
      description: '通用助手',
      systemPrompt: defaultSystemPrompt,
    );
  }

  factory ChatRole.fromJson(Map<String, dynamic> json) {
    final colorValue = json['themeColor'] as int?;
    return ChatRole(
      id: json['id'] as String? ?? defaultId,
      name: json['name'] as String? ?? '默认',
      description: json['description'] as String? ?? '',
      systemPrompt:
          json['systemPrompt'] as String? ?? defaultSystemPrompt,
      modelId: json['modelId'] as String?,
      modelName: json['modelName'] as String?,
      themeColor: colorValue == null ? null : Color(colorValue),
    );
  }

  static ChatRole normalizeDefaultRole(ChatRole role) {
    if (role.id != defaultId) return role;
    final prompt = role.systemPrompt.trim();
    if (prompt.isEmpty || prompt == legacyDefaultSystemPrompt) {
      return role.copyWith(systemPrompt: defaultSystemPrompt);
    }
    return role;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (description.isNotEmpty) 'description': description,
      'systemPrompt': systemPrompt,
      if (modelId != null) 'modelId': modelId,
      if (modelName != null && modelName!.isNotEmpty) 'modelName': modelName,
      if (themeColor != null) 'themeColor': themeColor!.toARGB32(),
    };
  }

  ChatRole copyWith({
    String? id,
    String? name,
    String? description,
    String? systemPrompt,
    Object? modelId = _sentinel,
    Object? modelName = _sentinel,
    Object? themeColor = _sentinel,
  }) {
    return ChatRole(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      modelId: identical(modelId, _sentinel)
          ? this.modelId
          : modelId as String?,
      modelName: identical(modelName, _sentinel)
          ? this.modelName
          : modelName as String?,
      themeColor: identical(themeColor, _sentinel)
          ? this.themeColor
          : themeColor as Color?,
    );
  }

  static const _sentinel = Object();
}

class ChatRoleGroup {
  final String id;
  final String name;
  final List<String> roleIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ChatRoleGroup({
    required this.id,
    required this.name,
    this.roleIds = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatRoleGroup.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return ChatRoleGroup(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      roleIds: (json['roleIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'roleIds': roleIds,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  ChatRoleGroup copyWith({
    String? id,
    String? name,
    List<String>? roleIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatRoleGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      roleIds: roleIds ?? this.roleIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
