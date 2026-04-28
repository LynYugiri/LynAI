/// AI 模型配置数据模型
///
/// 表示用户配置的一个 AI 模型。
/// [id] 唯一标识
/// [name] 用户自定义的模型显示名称
/// [endpoint] API 端点地址
/// [apiKey] API 密钥
/// [modelName] 实际的模型名称（如 gpt-4, llama3 等）
/// [apiType] API 接口类型，如 'openai' 或 'ollama'
/// [priority] 优先级，数字越小优先级越高，用于排序
/// [maxTokens] 最大输出 token 数，null 表示使用 API 默认值
/// [temperature] 采样温度，null 表示使用 API 默认值
/// [topP] 核采样参数，null 表示使用 API 默认值
/// [extraParams] 额外的自定义参数，key-value 对
class ModelConfig {
  final String id;
  final String name;
  final String endpoint;
  final String apiKey;
  final String modelName;
  final String apiType;
  final int priority;
  final int? maxTokens;
  final double? temperature;
  final double? topP;
  final Map<String, dynamic> extraParams;

  ModelConfig({
    required this.id,
    required this.name,
    required this.endpoint,
    required this.apiKey,
    required this.modelName,
    required this.apiType,
    required this.priority,
    this.maxTokens,
    this.temperature,
    this.topP,
    Map<String, dynamic>? extraParams,
  }) : extraParams = extraParams ?? {};

  ModelConfig copyWith({
    String? id,
    String? name,
    String? endpoint,
    String? apiKey,
    String? modelName,
    String? apiType,
    int? priority,
    int? maxTokens,
    double? temperature,
    double? topP,
    Map<String, dynamic>? extraParams,
  }) {
    return ModelConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      endpoint: endpoint ?? this.endpoint,
      apiKey: apiKey ?? this.apiKey,
      modelName: modelName ?? this.modelName,
      apiType: apiType ?? this.apiType,
      priority: priority ?? this.priority,
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      extraParams: extraParams ?? this.extraParams,
    );
  }

  factory ModelConfig.fromJson(Map<String, dynamic> json) {
    return ModelConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      endpoint: json['endpoint'] as String,
      apiKey: json['apiKey'] as String,
      modelName: json['modelName'] as String,
      apiType: json['apiType'] as String,
      priority: json['priority'] as int,
      maxTokens: json['maxTokens'] as int?,
      temperature: (json['temperature'] as num?)?.toDouble(),
      topP: (json['topP'] as num?)?.toDouble(),
      extraParams: json['extraParams'] != null
          ? Map<String, dynamic>.from(json['extraParams'] as Map)
          : {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'endpoint': endpoint,
      'apiKey': apiKey,
      'modelName': modelName,
      'apiType': apiType,
      'priority': priority,
      if (maxTokens != null) 'maxTokens': maxTokens,
      if (temperature != null) 'temperature': temperature,
      if (topP != null) 'topP': topP,
      if (extraParams.isNotEmpty) 'extraParams': extraParams,
    };
  }
}
