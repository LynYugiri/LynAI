/// 提供商配置中的一个可选子模型。
///
/// 一个 Provider 可能暴露多个模型名。子模型级参数优先于 Provider 级参数，
/// 并决定当前请求是否启用视觉、思考和工具能力。
class ModelEntry {
  final String name;
  final bool enabled;
  final bool supportsVision;
  final bool supportsThinking;
  final bool supportsTools;
  final int? maxTokens;
  final double? temperature;
  final double? topP;

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
  static const categoryChat = 'chat';
  static const categoryOcr = 'ocr';
  static const categorySpeech = 'speech';
  static const categoryImageGeneration = 'image_generation';

  final String id;
  final String name;
  final String category;
  final String endpoint;
  final String apiKey;
  final String modelName; // default/current model
  final String apiType;
  final int priority;
  final List<ModelEntry> models; // all models under this provider
  final int? maxTokens;
  final double? temperature;
  final double? topP;
  final Map<String, dynamic> extraParams;

  ModelConfig({
    required this.id,
    required this.name,
    this.category = categoryChat,
    required this.endpoint,
    required this.apiKey,
    required this.modelName,
    required this.apiType,
    required this.priority,
    this.maxTokens,
    this.temperature,
    this.topP,
    Map<String, dynamic>? extraParams,
    List<ModelEntry>? models,
  }) : extraParams = extraParams ?? {},
       models = models ?? [ModelEntry(name: modelName, enabled: true)];

  List<String> get enabledModelNames =>
      models.where((m) => m.enabled).map((m) => m.name).toList();

  bool get hasMultipleModels => models.length > 1;

  ModelEntry? get activeEntry {
    for (final entry in models) {
      if (entry.name == modelName) return entry;
    }
    if (models.isEmpty) return null;
    final enabled = models.where((m) => m.enabled);
    return enabled.isNotEmpty ? enabled.first : models.first;
  }

  int? get effectiveMaxTokens => activeEntry?.maxTokens ?? maxTokens;
  double? get effectiveTemperature => activeEntry?.temperature ?? temperature;
  double? get effectiveTopP => activeEntry?.topP ?? topP;
  bool get supportsVision => activeEntry?.supportsVision ?? true;
  bool get supportsThinking => activeEntry?.supportsThinking ?? true;
  bool get supportsTools => activeEntry?.supportsTools ?? true;

  ModelConfig copyWith({
    String? id,
    String? name,
    String? category,
    String? endpoint,
    String? apiKey,
    String? modelName,
    String? apiType,
    int? priority,
    Object? maxTokens = _sentinel,
    Object? temperature = _sentinel,
    Object? topP = _sentinel,
    Map<String, dynamic>? extraParams,
    List<ModelEntry>? models,
  }) {
    return ModelConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      endpoint: endpoint ?? this.endpoint,
      apiKey: apiKey ?? this.apiKey,
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
      extraParams: extraParams ?? this.extraParams,
      models: models ?? this.models,
    );
  }

  static const _sentinel = Object();

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
      apiKey: json['apiKey'] as String,
      modelName: modelName,
      apiType: json['apiType'] as String,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      maxTokens: maxTokens,
      temperature: temperature,
      topP: topP,
      extraParams: json['extraParams'] is Map
          ? Map<String, dynamic>.from(json['extraParams'])
          : {},
      models: entries,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'endpoint': endpoint,
      'apiKey': apiKey,
      'modelName': modelName,
      'apiType': apiType,
      'priority': priority,
      'models': models.map((m) => m.toJson()).toList(),
      if (maxTokens != null) 'maxTokens': maxTokens,
      if (temperature != null) 'temperature': temperature,
      if (topP != null) 'topP': topP,
      if (extraParams.isNotEmpty) 'extraParams': extraParams,
    };
  }
}
