import 'model_config.dart';

/// LynAI 插件配置 schema。
///
/// 插件用 `config.schema.json` 描述 `config.json` 的表单结构。这里故意不实现
/// 完整 JSON Schema，而是保留一组 LynAI 能稳定渲染和校验的字段类型，包括模型
/// 选择这种应用内专属控件。
class PluginConfigSchema {
  final String title;
  final String description;
  final List<PluginConfigFieldDefinition> fields;

  const PluginConfigSchema({
    required this.title,
    required this.description,
    required this.fields,
  });

  factory PluginConfigSchema.fromJson(Map<String, dynamic> json) {
    return PluginConfigSchema(
      title: json['title'] as String? ?? '插件配置',
      description: json['description'] as String? ?? '',
      fields: (json['fields'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => PluginConfigFieldDefinition.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Validates the schema definition itself, before it is used to validate
  /// user config values. This catches authoring mistakes that would otherwise
  /// render a misleading form or silently drop values on save.
  String? validateDefinition() {
    final keys = <String>{};
    for (final field in fields) {
      if (!keys.add(field.key)) return '配置 schema 字段重复: ${field.key}';
      final error = field.validateDefinition();
      if (error != null) return error;
    }
    return null;
  }

  Map<String, dynamic> applyDefaults(Map<String, dynamic> values) {
    final merged = Map<String, dynamic>.from(values);
    for (final field in fields) {
      if (!merged.containsKey(field.key) && field.defaultValue != null) {
        merged[field.key] = _cloneJsonValue(field.defaultValue);
      }
      if (merged[field.key] is Map &&
          field.type == PluginConfigFieldType.object) {
        merged[field.key] = field.applyObjectDefaults(
          Map<String, dynamic>.from(merged[field.key] as Map),
        );
      }
    }
    return merged;
  }

  List<PluginConfigValidationError> validateValues(
    Map<String, dynamic> values, {
    List<ModelConfig> models = const [],
  }) {
    final errors = <PluginConfigValidationError>[];
    for (final field in fields) {
      errors.addAll(field.validateValue(values[field.key], models: models));
    }
    return errors;
  }
}

class PluginConfigFieldDefinition {
  final String key;
  final PluginConfigFieldType type;
  final String title;
  final String description;
  final Object? defaultValue;
  final bool required;
  final String placeholder;
  final num? min;
  final num? max;
  final num? step;
  final int? minLength;
  final int? maxLength;
  final String pattern;
  final String patternMessage;
  final List<PluginConfigOptionDefinition> options;
  final String modelCategory;
  final PluginModelStoreMode modelStore;
  final List<String> modelCapabilities;
  final bool allowClear;
  final PluginConfigFieldDefinition? item;
  final List<PluginConfigFieldDefinition> fields;

  const PluginConfigFieldDefinition({
    required this.key,
    required this.type,
    required this.title,
    required this.description,
    this.defaultValue,
    required this.required,
    required this.placeholder,
    this.min,
    this.max,
    this.step,
    this.minLength,
    this.maxLength,
    required this.pattern,
    required this.patternMessage,
    required this.options,
    required this.modelCategory,
    required this.modelStore,
    required this.modelCapabilities,
    required this.allowClear,
    this.item,
    required this.fields,
  });

  bool get isAnonymousItem => key.isEmpty;

  String? validateDefinition({bool allowAnonymous = false}) {
    if (key.isEmpty && !allowAnonymous) return '配置 schema 字段缺少 key';
    if (type == PluginConfigFieldType.select && options.isEmpty) {
      return '配置 schema 字段 $key 缺少 options';
    }
    if (type == PluginConfigFieldType.multiSelect && options.isEmpty) {
      return '配置 schema 字段 $key 缺少 options';
    }
    if (type == PluginConfigFieldType.model &&
        !ModelConfig.supportedCategories.contains(modelCategory)) {
      return '配置 schema 字段 $key 使用了未知模型分类: $modelCategory';
    }
    if (type == PluginConfigFieldType.array && item == null) {
      return '配置 schema 字段 $key 缺少 item';
    }
    final nestedKeys = <String>{};
    for (final field in fields) {
      if (!nestedKeys.add(field.key)) {
        return '配置 schema 字段 $key.${field.key} 重复';
      }
      final error = field.validateDefinition();
      if (error != null) return error;
    }
    return item?.validateDefinition(allowAnonymous: true);
  }

  factory PluginConfigFieldDefinition.fromJson(Map<String, dynamic> json) {
    final type = PluginConfigFieldType.fromName(
      json['type'] as String? ?? 'string',
    );
    final item = json['item'] is Map
        ? PluginConfigFieldDefinition.fromJson(
            Map<String, dynamic>.from(json['item'] as Map),
          )
        : null;
    return PluginConfigFieldDefinition(
      key: json['key'] as String? ?? '',
      type: type,
      title: json['title'] as String? ?? json['key'] as String? ?? '',
      description: json['description'] as String? ?? '',
      defaultValue: json['default'],
      required: json['required'] as bool? ?? false,
      placeholder: json['placeholder'] as String? ?? '',
      min: json['min'] as num?,
      max: json['max'] as num?,
      step: json['step'] as num?,
      minLength: (json['minLength'] as num?)?.toInt(),
      maxLength: (json['maxLength'] as num?)?.toInt(),
      pattern: json['pattern'] as String? ?? '',
      patternMessage: json['patternMessage'] as String? ?? '',
      options: (json['options'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => PluginConfigOptionDefinition.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      modelCategory: json['category'] as String? ?? ModelConfig.categoryChat,
      modelStore: PluginModelStoreMode.fromName(
        json['store'] as String? ?? 'selection',
      ),
      modelCapabilities: (json['capabilities'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      allowClear: json['allowClear'] as bool? ?? true,
      item: item,
      fields: (json['fields'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => PluginConfigFieldDefinition.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
    );
  }

  Map<String, dynamic> applyObjectDefaults(Map<String, dynamic> values) {
    final merged = Map<String, dynamic>.from(values);
    for (final field in fields) {
      if (!merged.containsKey(field.key) && field.defaultValue != null) {
        merged[field.key] = _cloneJsonValue(field.defaultValue);
      }
      if (merged[field.key] is Map &&
          field.type == PluginConfigFieldType.object) {
        merged[field.key] = field.applyObjectDefaults(
          Map<String, dynamic>.from(merged[field.key] as Map),
        );
      }
    }
    return merged;
  }

  List<PluginConfigValidationError> validateValue(
    Object? value, {
    required List<ModelConfig> models,
    String? parentKey,
  }) {
    final fullKey = parentKey == null || key.isEmpty ? key : '$parentKey.$key';
    final errors = <PluginConfigValidationError>[];
    if (value == null || (value is String && value.isEmpty)) {
      if (required) {
        errors.add(
          PluginConfigValidationError(fullKey, '${titleOrKey(fullKey)}不能为空'),
        );
      }
      return errors;
    }

    switch (type) {
      case PluginConfigFieldType.boolean:
        if (value is! bool) errors.add(_typeError(fullKey, '布尔值'));
      case PluginConfigFieldType.string:
      case PluginConfigFieldType.text:
        if (value is! String) {
          errors.add(_typeError(fullKey, '字符串'));
        } else {
          _validateString(value, fullKey, errors);
        }
      case PluginConfigFieldType.number:
        if (value is! num) {
          errors.add(_typeError(fullKey, '数字'));
        } else {
          _validateNumber(value, fullKey, errors);
        }
      case PluginConfigFieldType.integer:
        if (value is! int) {
          errors.add(_typeError(fullKey, '整数'));
        } else {
          _validateNumber(value, fullKey, errors);
        }
      case PluginConfigFieldType.select:
        if (!_optionValuesEqualAny(value)) {
          errors.add(
            PluginConfigValidationError(
              fullKey,
              '${titleOrKey(fullKey)}必须从列表中选择',
            ),
          );
        }
      case PluginConfigFieldType.multiSelect:
        if (value is! List) {
          errors.add(_typeError(fullKey, '列表'));
        } else {
          for (final item in value) {
            if (!_optionValuesEqualAny(item)) {
              errors.add(
                PluginConfigValidationError(
                  fullKey,
                  '${titleOrKey(fullKey)}包含无效选项',
                ),
              );
              break;
            }
          }
        }
      case PluginConfigFieldType.model:
        _validateModel(value, fullKey, models, errors);
      case PluginConfigFieldType.array:
        if (value is! List) {
          errors.add(_typeError(fullKey, '列表'));
        } else if (item != null) {
          for (var i = 0; i < value.length; i++) {
            errors.addAll(
              item!.validateValue(
                value[i],
                models: models,
                parentKey: '$fullKey[$i]',
              ),
            );
          }
        }
      case PluginConfigFieldType.object:
        if (value is! Map) {
          errors.add(_typeError(fullKey, '对象'));
        } else {
          final map = Map<String, dynamic>.from(value);
          for (final field in fields) {
            errors.addAll(
              field.validateValue(
                map[field.key],
                models: models,
                parentKey: fullKey,
              ),
            );
          }
        }
    }
    return errors;
  }

  String titleOrKey(String fallback) => title.isNotEmpty ? title : fallback;

  PluginConfigValidationError _typeError(String key, String typeName) {
    return PluginConfigValidationError(key, '${titleOrKey(key)}必须是$typeName');
  }

  void _validateString(
    String value,
    String key,
    List<PluginConfigValidationError> errors,
  ) {
    if (minLength != null && value.length < minLength!) {
      errors.add(
        PluginConfigValidationError(key, '${titleOrKey(key)}长度不能小于 $minLength'),
      );
    }
    if (maxLength != null && value.length > maxLength!) {
      errors.add(
        PluginConfigValidationError(key, '${titleOrKey(key)}长度不能超过 $maxLength'),
      );
    }
    if (pattern.isNotEmpty && !RegExp(pattern).hasMatch(value)) {
      errors.add(
        PluginConfigValidationError(
          key,
          patternMessage.isNotEmpty
              ? patternMessage
              : '${titleOrKey(key)}格式不正确',
        ),
      );
    }
  }

  void _validateNumber(
    num value,
    String key,
    List<PluginConfigValidationError> errors,
  ) {
    if (min != null && value < min!) {
      errors.add(
        PluginConfigValidationError(key, '${titleOrKey(key)}不能小于 $min'),
      );
    }
    if (max != null && value > max!) {
      errors.add(
        PluginConfigValidationError(key, '${titleOrKey(key)}不能大于 $max'),
      );
    }
  }

  bool _optionValuesEqualAny(Object? value) {
    return options.any((option) => option.value == value);
  }

  void _validateModel(
    Object? value,
    String key,
    List<ModelConfig> models,
    List<PluginConfigValidationError> errors,
  ) {
    String? modelId;
    String? modelName;
    if (modelStore == PluginModelStoreMode.id) {
      if (value is! String) {
        errors.add(_typeError(key, '模型 ID'));
        return;
      }
      modelId = value;
    } else {
      if (value is! Map) {
        errors.add(_typeError(key, '模型选择对象'));
        return;
      }
      modelId = value['modelId'] as String?;
      modelName = value['modelName'] as String?;
    }
    if (modelId == null || modelId.isEmpty) {
      if (required) {
        errors.add(PluginConfigValidationError(key, '${titleOrKey(key)}不能为空'));
      }
      return;
    }
    final model = _findModel(models, modelId);
    if (model == null || model.category != modelCategory) {
      errors.add(
        PluginConfigValidationError(key, '${titleOrKey(key)}不存在或分类不匹配'),
      );
      return;
    }
    if (!_modelMatchesCapabilities(model, modelName)) {
      errors.add(PluginConfigValidationError(key, '${titleOrKey(key)}不满足能力要求'));
      return;
    }
    if (modelName != null && modelName.isNotEmpty) {
      final entry = model.models
          .where((item) => item.name == modelName)
          .firstOrNull;
      if (entry == null || !entry.enabled) {
        errors.add(
          PluginConfigValidationError(key, '${titleOrKey(key)}子模型不可用'),
        );
      }
    }
  }

  bool _modelMatchesCapabilities(ModelConfig model, String? modelName) {
    if (modelCapabilities.isEmpty) return true;
    final entry = modelName == null || modelName.isEmpty
        ? model.activeEntry
        : model.models.where((item) => item.name == modelName).firstOrNull;
    bool has(String capability) {
      return switch (capability) {
        'vision' => entry?.supportsVision ?? model.supportsVision,
        'thinking' => entry?.supportsThinking ?? model.supportsThinking,
        'tools' => entry?.supportsTools ?? model.supportsTools,
        _ => true,
      };
    }

    return modelCapabilities.every(has);
  }

  ModelConfig? _findModel(List<ModelConfig> models, String id) {
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }
}

/// `select` / `multiSelect` 的静态选项。
///
/// `value` 保持 JSON 原始类型，避免把数字和布尔选项误保存为字符串。
class PluginConfigOptionDefinition {
  final Object? value;
  final String label;

  const PluginConfigOptionDefinition({
    required this.value,
    required this.label,
  });

  factory PluginConfigOptionDefinition.fromJson(Map<String, dynamic> json) {
    final value = json['value'];
    return PluginConfigOptionDefinition(
      value: value,
      label: json['label'] as String? ?? value?.toString() ?? '',
    );
  }
}

class PluginConfigValidationError {
  final String key;
  final String message;

  const PluginConfigValidationError(this.key, this.message);
}

enum PluginConfigFieldType {
  boolean,
  string,
  text,
  number,
  integer,
  select,
  multiSelect,
  model,
  array,
  object;

  static PluginConfigFieldType fromName(String name) {
    return switch (name) {
      'boolean' => boolean,
      'text' => text,
      'number' => number,
      'integer' => integer,
      'select' => select,
      'multiSelect' => multiSelect,
      'model' => model,
      'array' => array,
      'object' => object,
      _ => string,
    };
  }
}

enum PluginModelStoreMode {
  id,
  selection;

  static PluginModelStoreMode fromName(String name) {
    return name == 'id' ? id : selection;
  }
}

Object? _cloneJsonValue(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List) return List<dynamic>.from(value);
  return value;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
