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
class ModelConfig {
  final String id;
  final String name;
  final String endpoint;
  final String apiKey;
  final String modelName;
  final String apiType; // 'openai', 'ollama' 等
  final int priority;

  ModelConfig({
    required this.id,
    required this.name,
    required this.endpoint,
    required this.apiKey,
    required this.modelName,
    required this.apiType,
    required this.priority,
  });

  /// 创建 ModelConfig 的副本，可选地覆盖某些字段
  ModelConfig copyWith({
    String? id,
    String? name,
    String? endpoint,
    String? apiKey,
    String? modelName,
    String? apiType,
    int? priority,
  }) {
    return ModelConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      endpoint: endpoint ?? this.endpoint,
      apiKey: apiKey ?? this.apiKey,
      modelName: modelName ?? this.modelName,
      apiType: apiType ?? this.apiType,
      priority: priority ?? this.priority,
    );
  }

  /// 从 JSON Map 创建 ModelConfig 实例
  factory ModelConfig.fromJson(Map<String, dynamic> json) {
    return ModelConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      endpoint: json['endpoint'] as String,
      apiKey: json['apiKey'] as String,
      modelName: json['modelName'] as String,
      apiType: json['apiType'] as String,
      priority: json['priority'] as int,
    );
  }

  /// 将 ModelConfig 转换为 JSON Map，用于持久化存储
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'endpoint': endpoint,
      'apiKey': apiKey,
      'modelName': modelName,
      'apiType': apiType,
      'priority': priority,
    };
  }
}

