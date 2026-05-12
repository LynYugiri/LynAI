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

  ModelConfig copyWith({
    String? id,
    String? name,
    String? category,
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
      category: category ?? this.category,
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
    String? firstEnabledModelName() {
      for (final entry in entries) {
        if (entry.enabled) return entry.name;
      }
      return entries.isEmpty ? null : entries.first.name;
    }

    final modelName =
        json['modelName'] as String? ?? firstEnabledModelName() ?? '';

    return ModelConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String? ?? categoryChat,
      endpoint: json['endpoint'] as String,
      apiKey: json['apiKey'] as String,
      modelName: modelName,
      apiType: json['apiType'] as String,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      maxTokens: (json['maxTokens'] as num?)?.toInt(),
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
