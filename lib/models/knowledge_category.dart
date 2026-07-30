const _knowledgeCategoryUnset = Object();

final knowledgeCategoryAliasPattern = RegExp(r'^[a-z][a-z0-9_-]{0,31}$');

const builtInProperNounKnowledgeBaseModelId =
    'builtin-proper-noun-knowledge-base';
const builtInProperNounCategoryModelId = 'builtin-proper-noun-category';
const properNounKnowledgeCategoryAlias = 'proper_noun';

bool isValidKnowledgeCategoryAlias(String value) =>
    knowledgeCategoryAliasPattern.hasMatch(value);

Map<String, String> normalizeKnowledgeCategoryAliases(
  Iterable<({String id, String alias})> categories,
) {
  final values = categories.toList(growable: false);
  final groups = <String, List<String>>{};
  for (final category in values) {
    groups.putIfAbsent(category.alias, () => []).add(category.id);
  }
  final result = <String, String>{
    for (final category in values) category.id: category.alias,
  };
  final used = values.map((category) => category.alias).toSet();
  final duplicateAliases = groups.entries
      .where((entry) => entry.value.length > 1)
      .toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  for (final entry in duplicateAliases) {
    final ids = entry.value..sort((a, b) {
      if (a == builtInProperNounCategoryModelId) return -1;
      if (b == builtInProperNounCategoryModelId) return 1;
      return a.compareTo(b);
    });
    for (final id in ids.skip(1)) {
      final alias = _availableKnowledgeCategoryAlias(entry.key, id, used);
      result[id] = alias;
      used.add(alias);
    }
  }
  return result;
}

String _availableKnowledgeCategoryAlias(
  String alias,
  String categoryId,
  Set<String> used,
) {
  final normalizedSuffix = categoryId
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final suffix = normalizedSuffix.isEmpty ? 'category' : normalizedSuffix;
  final stemLength = 32 - suffix.length.clamp(1, 23) - 1;
  final stem = alias.substring(0, alias.length.clamp(1, stemLength));
  var candidate = '${stem}_${suffix.substring(0, suffix.length.clamp(1, 23))}';
  var sequence = 2;
  while (used.contains(candidate)) {
    final marker = '_$sequence';
    candidate =
        '${stem.substring(0, (32 - marker.length).clamp(1, stem.length))}$marker';
    sequence++;
  }
  return candidate;
}

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
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
