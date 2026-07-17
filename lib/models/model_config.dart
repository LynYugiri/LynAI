import 'dart:convert';

/// 提供商配置中的一个可选子模型。
///
/// 一个 Provider 可能暴露多个模型名。子模型级参数优先于 Provider 级参数，
/// 并决定当前请求是否启用视觉、思考和工具能力。
class ModelEntry {
  /// 子模型名称。
  final String name;

  /// 该子模型是否启用。
  final bool enabled;

  /// 该子模型是否支持视觉输入。
  final bool supportsVision;

  /// 该子模型是否支持思考过程输出。
  final bool supportsThinking;

  /// 该子模型是否支持工具调用。
  final bool supportsTools;

  /// 该子模型的最大 Token 数，为 null 时继承 Provider 级设置。
  final int? maxTokens;

  /// 该子模型的温度参数，为 null 时继承 Provider 级设置。
  final double? temperature;

  /// 该子模型的 Top-P 采样参数，为 null 时继承 Provider 级设置。
  final double? topP;

  /// 创建一个子模型配置实例。
  ModelEntry({
    required this.name,
    this.enabled = false,
    this.supportsVision = true,
    this.supportsThinking = true,
    this.supportsTools = true,
    this.maxTokens,
    this.temperature,
    this.topP,
  });

  /// 从 JSON 数据创建 [ModelEntry] 实例。
  factory ModelEntry.fromJson(Map<String, dynamic> json) {
    return ModelEntry(
      name: json['name'] as String,
      enabled: json['enabled'] as bool? ?? false,
      supportsVision: json['supportsVision'] as bool? ?? true,
      supportsThinking: json['supportsThinking'] as bool? ?? true,
      supportsTools: json['supportsTools'] as bool? ?? true,
      maxTokens: (json['maxTokens'] as num?)?.toInt(),
      temperature: (json['temperature'] as num?)?.toDouble(),
      topP: (json['topP'] as num?)?.toDouble(),
    );
  }

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() => {
    'name': name,
    'enabled': enabled,
    'supportsVision': supportsVision,
    'supportsThinking': supportsThinking,
    'supportsTools': supportsTools,
    if (maxTokens != null) 'maxTokens': maxTokens,
    if (temperature != null) 'temperature': temperature,
    if (topP != null) 'topP': topP,
  };

  /// 创建当前实例的副本，可选择性更新部分字段。
  ModelEntry copyWith({
    String? name,
    bool? enabled,
    bool? supportsVision,
    bool? supportsThinking,
    bool? supportsTools,
    Object? maxTokens = _sentinel,
    Object? temperature = _sentinel,
    Object? topP = _sentinel,
  }) {
    return ModelEntry(
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      supportsVision: supportsVision ?? this.supportsVision,
      supportsThinking: supportsThinking ?? this.supportsThinking,
      supportsTools: supportsTools ?? this.supportsTools,
      maxTokens: identical(maxTokens, _sentinel)
          ? this.maxTokens
          : maxTokens as int?,
      temperature: identical(temperature, _sentinel)
          ? this.temperature
          : temperature as double?,
      topP: identical(topP, _sentinel) ? this.topP : topP as double?,
    );
  }

  static const _sentinel = Object();
}

/// 一个模型提供商或接口配置。
///
/// `category` 决定配置用途：聊天、OCR、语音转写或图片生成。聊天配置可以
/// 通过 [models] 维护多个子模型，`modelName` 表示当前激活子模型。
class ModelConfig {
  /// 聊天类配置的类别常量。
  static const categoryChat = 'chat';

  /// OCR 类配置的类别常量。
  static const categoryOcr = 'ocr';

  /// 语音转写类配置的类别常量。
  static const categorySpeech = 'speech';

  /// 图片生成类配置的类别常量。
  static const categoryImageGeneration = 'image_generation';

  /// 所有支持的配置类别列表。
  static const supportedCategories = [
    categoryChat,
    categoryOcr,
    categorySpeech,
    categoryImageGeneration,
  ];

  /// 内置本地 OCR 的保留模型 ID（sentinel）。
  ///
  /// 该 ID 不对应持久化的 [ModelConfig]，仅用于在对话设置和 OCR 服务层
  /// 标识"使用 on-device ncnn + PPOCRv5 推理"。当 `imageModelId` 等于此
  /// 值时，OCR 路径跳过云端 API，直接调用本地推理。
  static const localOcrId = '__local_ppocrv5__';

  /// 配置唯一标识符。
  final String id;

  /// 配置显示名称。
  final String name;

  /// 配置类别，决定该配置的使用场景。
  final String category;

  /// API 端点地址。
  final String endpoint;

  /// API 密钥。
  final String apiKey;

  /// 平台安全存储中 API 密钥的非敏感引用。
  final String apiKeySecretRef;

  /// 当前激活的模型名称。
  final String modelName;

  /// API 类型标识符，如 'openai'、'anthropic' 等。
  final String apiType;

  /// 配置优先级，数值越大优先级越高。
  final int priority;

  /// 該提供商下的所有子模型列表。
  final List<ModelEntry> models;

  /// Provider 级的最大 Token 数，可被子模型覆盖。
  final int? maxTokens;

  /// Provider 级的温度参数，可被子模型覆盖。
  final double? temperature;

  /// Provider 级的 Top-P 采样参数，可被子模型覆盖。
  final double? topP;

  /// 额外的自定义请求参数。
  final Map<String, dynamic> extraParams;

  /// 是否由 LynAI 托管同步。托管配置不可被用户改写 endpoint/API key。
  final bool managed;

  /// LynAI 后端中的真实 Relay Provider ID，用于精确选择同名模型的上游。
  final String? relayProviderId;

  /// LynAI Relay 内部协议版本。自定义 API 使用默认值 1。
  final int relayProtocolVersion;

  /// 用户是否在本机关闭了该托管配置。
  final bool disabledByUser;

  /// 用户对远端托管配置的逐字段覆盖值，优先级高于服务端下发值。
  final Map<String, dynamic> userOverrides;

  /// 用户是否明确允许将此非托管 Provider 的非秘密配置同步到云端。
  final bool cloudSyncEnabled;

  /// 创建一个模型配置实例。
  ModelConfig({
    required this.id,
    required this.name,
    this.category = categoryChat,
    required this.endpoint,
    required this.apiKey,
    String? apiKeySecretRef,
    required this.modelName,
    required this.apiType,
    required this.priority,
    this.maxTokens,
    this.temperature,
    this.topP,
    this.managed = false,
    this.relayProviderId,
    this.relayProtocolVersion = 1,
    this.disabledByUser = false,
    Map<String, dynamic>? extraParams,
    Map<String, dynamic>? userOverrides,
    List<ModelEntry>? models,
    this.cloudSyncEnabled = false,
  }) : apiKeySecretRef = apiKeySecretRef ?? secretReferenceForId(id),
       extraParams = extraParams ?? {},
       userOverrides = userOverrides ?? {},
       models = models ?? [ModelEntry(name: modelName, enabled: true)];

  /// 所有已启用的子模型名称列表。
  List<String> get enabledModelNames => disabledByUser
      ? const []
      : models.where((m) => m.enabled).map((m) => m.name).toList();

  /// 该提供商是否配置了多个子模型。
  bool get hasMultipleModels => models.length > 1;

  /// 当前激活的子模型配置项。
  ModelEntry? get activeEntry {
    for (final entry in models) {
      if (entry.name == modelName) return entry;
    }
    if (models.isEmpty) return null;
    final enabled = models.where((m) => m.enabled);
    return enabled.isNotEmpty ? enabled.first : models.first;
  }

  /// 生效的最大 Token 数，优先使用子模型设置。
  int? get effectiveMaxTokens =>
      (userOverrides['maxTokens'] as num?)?.toInt() ??
      activeEntry?.maxTokens ??
      maxTokens;

  /// 生效的温度参数，优先使用子模型设置。
  double? get effectiveTemperature =>
      (userOverrides['temperature'] as num?)?.toDouble() ??
      activeEntry?.temperature ??
      temperature;

  /// 生效的 Top-P 采样参数，优先使用子模型设置。
  double? get effectiveTopP =>
      (userOverrides['topP'] as num?)?.toDouble() ?? activeEntry?.topP ?? topP;

  /// 当前激活模型是否支持视觉输入。
  bool get supportsVision =>
      userOverrides['supportsVision'] as bool? ??
      activeEntry?.supportsVision ??
      true;

  /// 当前激活模型是否支持思考过程输出。
  bool get supportsThinking =>
      userOverrides['supportsThinking'] as bool? ??
      activeEntry?.supportsThinking ??
      true;

  /// 当前激活模型是否支持工具调用。
  bool get supportsTools =>
      userOverrides['supportsTools'] as bool? ??
      activeEntry?.supportsTools ??
      true;

  /// 创建当前实例的副本，可选择性更新部分字段。
  ModelConfig copyWith({
    String? id,
    String? name,
    String? category,
    String? endpoint,
    String? apiKey,
    Object? apiKeySecretRef = _sentinel,
    String? modelName,
    String? apiType,
    int? priority,
    Object? maxTokens = _sentinel,
    Object? temperature = _sentinel,
    Object? topP = _sentinel,
    bool? managed,
    Object? relayProviderId = _sentinel,
    int? relayProtocolVersion,
    bool? disabledByUser,
    Map<String, dynamic>? extraParams,
    Map<String, dynamic>? userOverrides,
    List<ModelEntry>? models,
    bool? cloudSyncEnabled,
  }) {
    return ModelConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      endpoint: endpoint ?? this.endpoint,
      apiKey: apiKey ?? this.apiKey,
      apiKeySecretRef: identical(apiKeySecretRef, _sentinel)
          ? (id != null && id != this.id
                ? secretReferenceForId(id)
                : this.apiKeySecretRef)
          : apiKeySecretRef as String?,
      modelName: modelName ?? this.modelName,
      apiType: apiType ?? this.apiType,
      priority: priority ?? this.priority,
      maxTokens: identical(maxTokens, _sentinel)
          ? this.maxTokens
          : maxTokens as int?,
      temperature: identical(temperature, _sentinel)
          ? this.temperature
          : temperature as double?,
      topP: identical(topP, _sentinel) ? this.topP : topP as double?,
      managed: managed ?? this.managed,
      relayProviderId: identical(relayProviderId, _sentinel)
          ? this.relayProviderId
          : relayProviderId as String?,
      relayProtocolVersion: relayProtocolVersion ?? this.relayProtocolVersion,
      disabledByUser: disabledByUser ?? this.disabledByUser,
      extraParams: extraParams ?? this.extraParams,
      userOverrides: userOverrides ?? this.userOverrides,
      models: models ?? this.models,
      cloudSyncEnabled: cloudSyncEnabled ?? this.cloudSyncEnabled,
    );
  }

  static const _sentinel = Object();

  /// 从 JSON 数据创建 [ModelConfig] 实例。
  factory ModelConfig.fromJson(Map<String, dynamic> json) {
    List<ModelEntry> entries = [];
    if (json['models'] != null) {
      entries = (json['models'] as List<dynamic>? ?? const [])
          .map((m) => ModelEntry.fromJson(m as Map<String, dynamic>))
          .toList();
    } else if (json['modelName'] != null) {
      entries = [ModelEntry(name: json['modelName'] as String, enabled: true)];
    }
    String? firstEnabledModelName() {
      for (final entry in entries) {
        if (entry.enabled) return entry.name;
      }
      return entries.isEmpty ? null : entries.first.name;
    }

    final modelName =
        json['modelName'] as String? ?? firstEnabledModelName() ?? '';
    final category = json['category'] as String? ?? categoryChat;
    final maxTokens = (json['maxTokens'] as num?)?.toInt();
    final temperature = (json['temperature'] as num?)?.toDouble();
    final topP = (json['topP'] as num?)?.toDouble();
    if (category == categoryChat) {
      entries = entries
          .map(
            (entry) => entry.copyWith(
              maxTokens: entry.maxTokens ?? maxTokens,
              temperature: entry.temperature ?? temperature,
              topP: entry.topP ?? topP,
            ),
          )
          .toList();
    }

    return ModelConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      category: category,
      endpoint: json['endpoint'] as String,
      apiKey: json['apiKey'] as String? ?? '',
      apiKeySecretRef:
          json['apiKeySecretRef'] as String? ??
          secretReferenceForId(json['id'] as String),
      modelName: modelName,
      apiType: json['apiType'] as String,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      maxTokens: maxTokens,
      temperature: temperature,
      topP: topP,
      managed: json['managed'] == true,
      relayProviderId: json['relayProviderId'] as String?,
      relayProtocolVersion:
          (json['relayProtocolVersion'] as num?)?.toInt() ?? 1,
      disabledByUser: json['disabledByUser'] == true,
      extraParams: json['extraParams'] is Map
          ? Map<String, dynamic>.from(json['extraParams'])
          : {},
      userOverrides: json['userOverrides'] is Map
          ? Map<String, dynamic>.from(json['userOverrides'])
          : {},
      models: entries,
      cloudSyncEnabled: json['cloudSyncEnabled'] == true,
    );
  }

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'endpoint': endpoint,
      'apiKeySecretRef': apiKeySecretRef,
      'modelName': modelName,
      'apiType': apiType,
      'priority': priority,
      'models': models.map((m) => m.toJson()).toList(),
      if (maxTokens != null) 'maxTokens': maxTokens,
      if (temperature != null) 'temperature': temperature,
      if (topP != null) 'topP': topP,
      if (managed) 'managed': managed,
      if (relayProviderId != null) 'relayProviderId': relayProviderId,
      if (relayProtocolVersion != 1)
        'relayProtocolVersion': relayProtocolVersion,
      if (disabledByUser) 'disabledByUser': disabledByUser,
      if (extraParams.isNotEmpty) 'extraParams': extraParams,
      if (userOverrides.isNotEmpty) 'userOverrides': userOverrides,
      if (cloudSyncEnabled) 'cloudSyncEnabled': true,
    };
  }

  /// Returns the only valid secure-storage reference for a model ID.
  static String secretReferenceForId(String id) {
    final encoded = base64UrlEncode(utf8.encode(id)).replaceAll('=', '');
    return 'lynai.model-api-key.v1.$encoded';
  }
}
