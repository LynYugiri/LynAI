import 'agent_plan.dart';
import 'agent_working_memory.dart';
import 'message.dart';
import 'package:flutter/foundation.dart';

/// 一次对话保存的设置快照。
///
/// 历史对话不能只依赖全局设置，否则用户后来切换模型、提示词或 OCR 配置时，
/// 旧对话的上下文会被悄悄改变。这个模型把发送所需的设置固定在对话上。
class ConversationSettings {
  /// 对话使用的模型配置 ID。
  final String modelId;

  /// 对话使用的模型名称。
  final String? modelName;

  /// 是否启用了思考过程输出。
  final bool thinking;

  /// 选中的系统提示词模板 ID。
  final String? selectedSystemPromptId;

  /// 实际使用的系统提示词文本。
  final String systemPrompt;

  /// 语音转写使用的模型 ID。
  final String? speechModelId;

  /// 图片生成使用的模型 ID。
  final String? imageModelId;

  /// 是否启用了图片 OCR 识别。
  final bool imageOcrEnabled;

  /// 图片识别使用的模型 ID。
  final String? imageRecognitionModelId;

  /// 是否启用了图片识别功能。
  final bool imageRecognitionEnabled;

  /// 图片识别时使用的提示词文本。
  final String imageRecognitionPrompt;

  /// 图片生成使用的模型 ID。
  final String? imageGenerationModelId;

  /// 是否启用了图片生成工具。
  final bool imageGenerationEnabled;

  /// 是否启用 Agent 模式。
  final bool agentEnabled;

  /// 当前对话授予 Agent 的扩展权限。
  final List<String> agentGrantedPermissions;

  /// 创建一个对话设置快照实例。
  ConversationSettings({
    required this.modelId,
    this.modelName,
    this.thinking = true,
    this.selectedSystemPromptId,
    this.systemPrompt = 'You are a helpful assistant.',
    this.speechModelId,
    this.imageModelId,
    this.imageOcrEnabled = false,
    this.imageRecognitionModelId,
    this.imageRecognitionEnabled = false,
    this.imageRecognitionPrompt = '请根据下面的文件内容或识别结果回答。',
    this.imageGenerationModelId,
    this.imageGenerationEnabled = false,
    this.agentEnabled = false,
    this.agentGrantedPermissions = const [],
  });

  static const _sentinel = Object();

  /// 创建当前实例的副本，可选择性更新部分字段。
  ConversationSettings copyWith({
    String? modelId,
    Object? modelName = _sentinel,
    bool? thinking,
    Object? selectedSystemPromptId = _sentinel,
    String? systemPrompt,
    Object? speechModelId = _sentinel,
    Object? imageModelId = _sentinel,
    bool? imageOcrEnabled,
    Object? imageRecognitionModelId = _sentinel,
    bool? imageRecognitionEnabled,
    String? imageRecognitionPrompt,
    Object? imageGenerationModelId = _sentinel,
    bool? imageGenerationEnabled,
    bool? agentEnabled,
    List<String>? agentGrantedPermissions,
  }) {
    return ConversationSettings(
      modelId: modelId ?? this.modelId,
      modelName: identical(modelName, _sentinel)
          ? this.modelName
          : modelName as String?,
      thinking: thinking ?? this.thinking,
      selectedSystemPromptId: identical(selectedSystemPromptId, _sentinel)
          ? this.selectedSystemPromptId
          : selectedSystemPromptId as String?,
      systemPrompt: systemPrompt ?? this.systemPrompt,
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
      imageRecognitionPrompt:
          imageRecognitionPrompt ?? this.imageRecognitionPrompt,
      imageGenerationModelId: identical(imageGenerationModelId, _sentinel)
          ? this.imageGenerationModelId
          : imageGenerationModelId as String?,
      imageGenerationEnabled:
          imageGenerationEnabled ?? this.imageGenerationEnabled,
      agentEnabled: agentEnabled ?? this.agentEnabled,
      agentGrantedPermissions:
          agentGrantedPermissions ?? this.agentGrantedPermissions,
    );
  }

  /// 从 JSON 数据创建 [ConversationSettings] 实例。
  factory ConversationSettings.fromJson(
    Map<String, dynamic> json, {
    String fallbackModelId = '',
  }) {
    return ConversationSettings(
      modelId: json['modelId'] as String? ?? fallbackModelId,
      modelName: json['modelName'] as String?,
      thinking: json['thinking'] as bool? ?? true,
      selectedSystemPromptId: json['selectedSystemPromptId'] as String?,
      systemPrompt:
          json['systemPrompt'] as String? ?? 'You are a helpful assistant.',
      speechModelId: json['speechModelId'] as String?,
      imageModelId: json['imageModelId'] as String?,
      imageOcrEnabled: json['imageOcrEnabled'] as bool? ?? false,
      imageRecognitionModelId: json['imageRecognitionModelId'] as String?,
      imageRecognitionEnabled:
          json['imageRecognitionEnabled'] as bool? ?? false,
      imageRecognitionPrompt:
          json['imageRecognitionPrompt'] as String? ??
          json['imagePrompt'] as String? ??
          '请根据下面的文件内容或识别结果回答。',
      imageGenerationModelId: json['imageGenerationModelId'] as String?,
      imageGenerationEnabled: json['imageGenerationEnabled'] as bool? ?? false,
      agentEnabled: json['agentEnabled'] as bool? ?? false,
      agentGrantedPermissions:
          (json['agentGrantedPermissions'] as List<dynamic>? ?? const [])
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList(growable: false),
    );
  }

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() {
    return {
      'modelId': modelId,
      if (modelName != null && modelName!.isNotEmpty) 'modelName': modelName,
      'thinking': thinking,
      if (selectedSystemPromptId != null)
        'selectedSystemPromptId': selectedSystemPromptId,
      'systemPrompt': systemPrompt,
      if (speechModelId != null) 'speechModelId': speechModelId,
      if (imageModelId != null) 'imageModelId': imageModelId,
      'imageOcrEnabled': imageOcrEnabled,
      if (imageRecognitionModelId != null)
        'imageRecognitionModelId': imageRecognitionModelId,
      'imageRecognitionEnabled': imageRecognitionEnabled,
      'imageRecognitionPrompt': imageRecognitionPrompt,
      if (imageGenerationModelId != null)
        'imageGenerationModelId': imageGenerationModelId,
      'imageGenerationEnabled': imageGenerationEnabled,
      'agentEnabled': agentEnabled,
      if (agentGrantedPermissions.isNotEmpty)
        'agentGrantedPermissions': agentGrantedPermissions,
    };
  }
}

/// 对话数据模型
///
/// 代表一次完整的对话会话。
/// [id] 唯一标识一个对话
/// [title] 对话的摘要标题，用于在历史列表中展示
/// [messages] 对话中的所有消息列表
/// [modelId] 本次对话使用的 AI 模型ID
/// [createdAt] 对话创建时间
/// [updatedAt] 对话最后更新时间
/// 一条完整的对话记录。
///
/// [messages] 保存用户和 assistant 消息；[modelId] 与 [settings] 记录创建或
/// 最近发送时使用的模型上下文；[roleId] 用于历史页按角色分组。
class Conversation {
  static const _sentinel = Object();

  /// 对话唯一标识符。
  final String id;

  /// 对话摘要标题，用于在历史列表中展示。
  final String title;

  /// 对话中的所有消息列表。
  final List<Message> messages;

  /// 本次对话使用的 AI 模型配置 ID。
  final String modelId;

  /// 对话创建或最近发送时使用的设置快照。
  final ConversationSettings settings;

  /// 当前对话的 Agent 计划状态。
  final AgentPlan? agentPlan;

  /// 当前对话的 Agent 工作记忆。
  final AgentWorkingMemory? agentWorkingMemory;

  /// 对话所属角色 ID，用于历史页按角色分组。
  final String roleId;

  /// 对话创建时间。
  final DateTime createdAt;

  /// 对话最后更新时间。
  final DateTime updatedAt;

  /// 创建一个对话实例。
  Conversation({
    required this.id,
    required this.title,
    required this.messages,
    required this.modelId,
    ConversationSettings? settings,
    this.agentPlan,
    this.agentWorkingMemory,
    this.roleId = 'default',
    required this.createdAt,
    required this.updatedAt,
  }) : settings = settings ?? ConversationSettings(modelId: modelId);

  /// 获取对话开头的一部分内容，用于在历史列表中预览
  String get preview {
    if (messages.isEmpty) return '';
    final first = messages.first;
    final raw = first.content;
    final clean = raw.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (clean.isEmpty && first.images.isNotEmpty) {
      final firstName = first.images.first.name;
      final suffix = first.images.length > 1
          ? ' 等 ${first.images.length} 个附件'
          : '';
      return '[附件] $firstName$suffix';
    }
    return clean.length > 80 ? '${clean.substring(0, 80)}...' : clean;
  }

  /// 从 JSON Map 创建 Conversation 实例
  factory Conversation.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final title = json['title'] as String?;
    final modelId = json['modelId'] as String?;
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    if (id == null ||
        id.isEmpty ||
        title == null ||
        modelId == null ||
        modelId.isEmpty ||
        createdAt == null ||
        updatedAt == null) {
      throw FormatException(
        'Malformed conversation${id != null && id.isNotEmpty ? ' $id' : ''}',
      );
    }
    final messages = <Message>[];
    for (final item in json['messages'] as List<dynamic>? ?? const []) {
      try {
        if (item is Map) {
          messages.add(Message.fromJson(Map<String, dynamic>.from(item)));
        }
      } catch (e) {
        debugPrint('跳过损坏的消息记录: $e');
      }
    }
    AgentPlan? agentPlan;
    final rawPlan = json['agentPlan'];
    if (rawPlan is Map) {
      try {
        final parsed = AgentPlan.fromJson(Map<String, dynamic>.from(rawPlan));
        if (parsed.id.isNotEmpty && parsed.items.isNotEmpty) {
          agentPlan = parsed;
        }
      } catch (e) {
        debugPrint('跳过损坏的 Agent 计划: $e');
      }
    }
    AgentWorkingMemory? agentWorkingMemory;
    final rawMemory = json['agentWorkingMemory'];
    if (rawMemory is Map) {
      try {
        final parsed = AgentWorkingMemory.fromJson(
          Map<String, dynamic>.from(rawMemory),
        );
        if (!parsed.isEmpty) agentWorkingMemory = parsed;
      } catch (e) {
        debugPrint('跳过损坏的 Agent 工作记忆: $e');
      }
    }
    return Conversation(
      id: id,
      title: title,
      messages: messages,
      modelId: modelId,
      settings: json['settings'] != null
          ? ConversationSettings.fromJson(
              json['settings'] as Map<String, dynamic>,
              fallbackModelId: modelId,
            )
          : ConversationSettings(modelId: modelId),
      agentPlan: agentPlan,
      agentWorkingMemory: agentWorkingMemory,
      roleId: json['roleId'] as String? ?? 'default',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// 将 Conversation 转换为 JSON Map，用于持久化存储
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'messages': messages.map((m) => m.toJson()).toList(),
      'modelId': modelId,
      'settings': settings.toJson(),
      if (agentPlan != null) 'agentPlan': agentPlan!.toJson(),
      if (agentWorkingMemory != null && !agentWorkingMemory!.isEmpty)
        'agentWorkingMemory': agentWorkingMemory!.toJson(),
      'roleId': roleId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 创建当前实例的副本，可选择性更新部分字段。
  Conversation copyWith({
    String? id,
    String? title,
    List<Message>? messages,
    String? modelId,
    ConversationSettings? settings,
    Object? agentPlan = _sentinel,
    Object? agentWorkingMemory = _sentinel,
    String? roleId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      modelId: modelId ?? this.modelId,
      settings: settings ?? this.settings,
      agentPlan: identical(agentPlan, _sentinel)
          ? this.agentPlan
          : agentPlan as AgentPlan?,
      agentWorkingMemory: identical(agentWorkingMemory, _sentinel)
          ? this.agentWorkingMemory
          : agentWorkingMemory as AgentWorkingMemory?,
      roleId: roleId ?? this.roleId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
