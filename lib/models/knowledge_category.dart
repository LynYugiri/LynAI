const _knowledgeCategoryUnset = Object();

final knowledgeCategoryAliasPattern = RegExp(r'^[a-z][a-z0-9_-]{0,31}$');

bool isValidKnowledgeCategoryAlias(String value) =>
    knowledgeCategoryAliasPattern.hasMatch(value);

final class KnowledgeCategory {
  KnowledgeCategory({
    required this.id,
    required this.knowledgeBaseId,
    required this.name,
    required this.alias,
    this.description,
    this.annotationRule = '',
    this.explanationPrompt = '',
    this.colorValue = 0,
    this.autoAnnotate = false,
    this.modelConfigId,
    required this.isDefault,
    required this.enabled,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  }) {
    if (!isValidKnowledgeCategoryAlias(alias)) {
      throw ArgumentError.value(alias, 'alias', '类别别名格式无效');
    }
  }

  final String id;
  final String knowledgeBaseId;
  final String name;
  final String alias;
  final String? description;
  final String annotationRule;
  final String explanationPrompt;
  final int colorValue;
  final bool autoAnnotate;
  final String? modelConfigId;
  final bool isDefault;
  final bool enabled;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory KnowledgeCategory.fromJson(Map<String, dynamic> json) =>
      KnowledgeCategory(
        id: json['id'] as String,
        knowledgeBaseId: json['knowledgeBaseId'] as String,
        name: json['name'] as String,
        alias: json['alias'] as String,
        description: json['description'] as String?,
        annotationRule: json['annotationRule'] as String? ?? '',
        explanationPrompt: json['explanationPrompt'] as String? ?? '',
        colorValue: (json['colorValue'] as num?)?.toInt() ?? 0,
        autoAnnotate: json['autoAnnotate'] as bool? ?? false,
        modelConfigId: json['modelConfigId'] as String?,
        isDefault: json['isDefault'] as bool? ?? false,
        enabled: json['enabled'] as bool? ?? true,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'knowledgeBaseId': knowledgeBaseId,
    'name': name,
    'alias': alias,
    if (description != null) 'description': description,
    'annotationRule': annotationRule,
    'explanationPrompt': explanationPrompt,
    'colorValue': colorValue,
    'autoAnnotate': autoAnnotate,
    if (modelConfigId != null) 'modelConfigId': modelConfigId,
    'isDefault': isDefault,
    'enabled': enabled,
    'sortOrder': sortOrder,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  KnowledgeCategory copyWith({
    String? id,
    String? knowledgeBaseId,
    String? name,
    String? alias,
    Object? description = _knowledgeCategoryUnset,
    String? annotationRule,
    String? explanationPrompt,
    int? colorValue,
    bool? autoAnnotate,
    Object? modelConfigId = _knowledgeCategoryUnset,
    bool? isDefault,
    bool? enabled,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => KnowledgeCategory(
    id: id ?? this.id,
    knowledgeBaseId: knowledgeBaseId ?? this.knowledgeBaseId,
    name: name ?? this.name,
    alias: alias ?? this.alias,
    description: identical(description, _knowledgeCategoryUnset)
        ? this.description
        : description as String?,
    annotationRule: annotationRule ?? this.annotationRule,
    explanationPrompt: explanationPrompt ?? this.explanationPrompt,
    colorValue: colorValue ?? this.colorValue,
    autoAnnotate: autoAnnotate ?? this.autoAnnotate,
    modelConfigId: identical(modelConfigId, _knowledgeCategoryUnset)
        ? this.modelConfigId
        : modelConfigId as String?,
    isDefault: isDefault ?? this.isDefault,
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
