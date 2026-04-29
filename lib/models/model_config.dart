class ModelEntry {
  final String name;
  final bool enabled;

  ModelEntry({required this.name, this.enabled = false});

  factory ModelEntry.fromJson(Map<String, dynamic> json) {
    return ModelEntry(
      name: json['name'] as String,
      enabled: json['enabled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'enabled': enabled};

  ModelEntry copyWith({String? name, bool? enabled}) {
    return ModelEntry(
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
    );
  }
}

class ModelConfig {
  final String id;
  final String name;
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
    List<ModelEntry>? models,
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
      models: models ?? this.models,
    );
  }

  factory ModelConfig.fromJson(Map<String, dynamic> json) {
    List<ModelEntry> entries = [];
    if (json['models'] != null) {
      entries = (json['models'] as List)
          .map((m) => ModelEntry.fromJson(m as Map<String, dynamic>))
          .toList();
    } else if (json['modelName'] != null) {
      entries = [ModelEntry(name: json['modelName'] as String, enabled: true)];
    }

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
      models: entries,
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
      'models': models.map((m) => m.toJson()).toList(),
      if (maxTokens != null) 'maxTokens': maxTokens,
      if (temperature != null) 'temperature': temperature,
      if (topP != null) 'topP': topP,
      if (extraParams.isNotEmpty) 'extraParams': extraParams,
    };
  }
}
