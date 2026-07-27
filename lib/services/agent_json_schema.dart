class AgentJsonSchemaIssue {
  final String path;
  final String message;

  const AgentJsonSchemaIssue(this.path, this.message);

  @override
  String toString() => '$path: $message';
}

class AgentJsonSchemaValidation {
  final List<AgentJsonSchemaIssue> issues;

  AgentJsonSchemaValidation(Iterable<AgentJsonSchemaIssue> issues)
    : issues = List.unmodifiable(issues);

  bool get isValid => issues.isEmpty;
}

class AgentJsonSchemaValidator {
  static const _keywords = {
    'type',
    'properties',
    'required',
    'additionalProperties',
    'items',
    'enum',
    'const',
    'minimum',
    'maximum',
    'exclusiveMinimum',
    'exclusiveMaximum',
    'minLength',
    'maxLength',
    'pattern',
    'minItems',
    'maxItems',
    'uniqueItems',
    'minProperties',
    'maxProperties',
    'anyOf',
    'oneOf',
    'allOf',
    'not',
    'description',
    'title',
    'default',
  };

  const AgentJsonSchemaValidator();

  AgentJsonSchemaValidation validateSchema(Map<String, dynamic> schema) {
    final issues = <AgentJsonSchemaIssue>[];
    _validateSchemaNode(schema, r'$', issues);
    return AgentJsonSchemaValidation(issues);
  }

  AgentJsonSchemaValidation validate(
    Object? value,
    Map<String, dynamic> schema,
  ) {
    final schemaValidation = validateSchema(schema);
    if (!schemaValidation.isValid) return schemaValidation;
    final issues = <AgentJsonSchemaIssue>[];
    _validateValue(value, schema, r'$', issues);
    return AgentJsonSchemaValidation(issues);
  }

  void _validateSchemaNode(
    Map<String, dynamic> schema,
    String path,
    List<AgentJsonSchemaIssue> issues,
  ) {
    for (final keyword in schema.keys) {
      if (!_keywords.contains(keyword)) {
        issues.add(
          AgentJsonSchemaIssue(path, 'unsupported keyword "$keyword"'),
        );
      }
    }
    final type = schema['type'];
    if (type != null &&
        (type is! String ||
            !const {
              'null',
              'boolean',
              'integer',
              'number',
              'string',
              'array',
              'object',
            }.contains(type))) {
      issues.add(
        AgentJsonSchemaIssue('$path.type', 'must be a supported type'),
      );
    }
    final properties = schema['properties'];
    if (properties != null) {
      if (properties is! Map) {
        issues.add(
          AgentJsonSchemaIssue('$path.properties', 'must be an object'),
        );
      } else {
        for (final entry in properties.entries) {
          if (entry.value is! Map) {
            issues.add(
              AgentJsonSchemaIssue(
                '$path.properties.${entry.key}',
                'must be a schema object',
              ),
            );
          } else {
            _validateSchemaNode(
              Map<String, dynamic>.from(entry.value as Map),
              '$path.properties.${entry.key}',
              issues,
            );
          }
        }
      }
    }
    final required = schema['required'];
    if (required != null &&
        (required is! List || required.any((item) => item is! String))) {
      issues.add(
        AgentJsonSchemaIssue('$path.required', 'must be a string array'),
      );
    }
    final additional = schema['additionalProperties'];
    if (additional != null && additional is! bool && additional is! Map) {
      issues.add(
        AgentJsonSchemaIssue(
          '$path.additionalProperties',
          'must be a boolean or schema object',
        ),
      );
    } else if (additional is Map) {
      _validateSchemaNode(
        Map<String, dynamic>.from(additional),
        '$path.additionalProperties',
        issues,
      );
    }
    final items = schema['items'];
    if (items != null && items is! Map) {
      issues.add(
        AgentJsonSchemaIssue('$path.items', 'must be a schema object'),
      );
    } else if (items is Map) {
      _validateSchemaNode(
        Map<String, dynamic>.from(items),
        '$path.items',
        issues,
      );
    }
    for (final keyword in const ['anyOf', 'oneOf', 'allOf']) {
      final alternatives = schema[keyword];
      if (alternatives == null) continue;
      if (alternatives is! List || alternatives.isEmpty) {
        issues.add(AgentJsonSchemaIssue('$path.$keyword', 'must be non-empty'));
        continue;
      }
      for (var index = 0; index < alternatives.length; index++) {
        final alternative = alternatives[index];
        if (alternative is! Map) {
          issues.add(
            AgentJsonSchemaIssue(
              '$path.$keyword[$index]',
              'must be a schema object',
            ),
          );
        } else {
          _validateSchemaNode(
            Map<String, dynamic>.from(alternative),
            '$path.$keyword[$index]',
            issues,
          );
        }
      }
    }
    final not = schema['not'];
    if (not != null && not is! Map) {
      issues.add(AgentJsonSchemaIssue('$path.not', 'must be a schema object'));
    } else if (not is Map) {
      _validateSchemaNode(Map<String, dynamic>.from(not), '$path.not', issues);
    }
    _validateNumericKeyword(schema, 'minimum', path, issues);
    _validateNumericKeyword(schema, 'maximum', path, issues);
    _validateNumericKeyword(schema, 'exclusiveMinimum', path, issues);
    _validateNumericKeyword(schema, 'exclusiveMaximum', path, issues);
    for (final keyword in const [
      'minLength',
      'maxLength',
      'minItems',
      'maxItems',
      'minProperties',
      'maxProperties',
    ]) {
      final value = schema[keyword];
      if (value != null && (value is! int || value < 0)) {
        issues.add(
          AgentJsonSchemaIssue(
            '$path.$keyword',
            'must be a non-negative integer',
          ),
        );
      }
    }
    final pattern = schema['pattern'];
    if (pattern != null) {
      if (pattern is! String) {
        issues.add(AgentJsonSchemaIssue('$path.pattern', 'must be a string'));
      } else {
        try {
          RegExp(pattern);
        } on FormatException {
          issues.add(AgentJsonSchemaIssue('$path.pattern', 'is not valid'));
        }
      }
    }
  }

  void _validateNumericKeyword(
    Map<String, dynamic> schema,
    String keyword,
    String path,
    List<AgentJsonSchemaIssue> issues,
  ) {
    if (schema[keyword] != null && schema[keyword] is! num) {
      issues.add(AgentJsonSchemaIssue('$path.$keyword', 'must be a number'));
    }
  }

  void _validateValue(
    Object? value,
    Map<String, dynamic> schema,
    String path,
    List<AgentJsonSchemaIssue> issues,
  ) {
    final allOf = schema['allOf'];
    if (allOf is List) {
      for (final alternative in allOf) {
        _validateValue(
          value,
          Map<String, dynamic>.from(alternative as Map),
          path,
          issues,
        );
      }
    }
    final anyOf = schema['anyOf'];
    if (anyOf is List && !_matchesAny(value, anyOf)) {
      issues.add(
        AgentJsonSchemaIssue(path, 'does not match any allowed schema'),
      );
      return;
    }
    final oneOf = schema['oneOf'];
    if (oneOf is List && _matchCount(value, oneOf) != 1) {
      issues.add(AgentJsonSchemaIssue(path, 'must match exactly one schema'));
      return;
    }
    final not = schema['not'];
    if (not is Map && _matches(value, Map<String, dynamic>.from(not))) {
      issues.add(AgentJsonSchemaIssue(path, 'matches a forbidden schema'));
      return;
    }
    if (schema.containsKey('const') && value != schema['const']) {
      issues.add(AgentJsonSchemaIssue(path, 'must equal ${schema['const']}'));
    }
    final allowed = schema['enum'];
    if (allowed is List && !allowed.contains(value)) {
      issues.add(AgentJsonSchemaIssue(path, 'must be one of $allowed'));
    }
    final type = schema['type'] as String?;
    if (type != null && !_hasType(value, type)) {
      issues.add(AgentJsonSchemaIssue(path, 'expected $type'));
      return;
    }
    if (value is Map) {
      _validateObject(value, schema, path, issues);
    } else if (value is List) {
      _validateArray(value, schema, path, issues);
    } else if (value is String) {
      _validateString(value, schema, path, issues);
    } else if (value is num && value is! bool) {
      _validateNumber(value, schema, path, issues);
    }
  }

  void _validateObject(
    Map value,
    Map<String, dynamic> schema,
    String path,
    List<AgentJsonSchemaIssue> issues,
  ) {
    final min = schema['minProperties'] as int?;
    final max = schema['maxProperties'] as int?;
    if (min != null && value.length < min) {
      issues.add(
        AgentJsonSchemaIssue(path, 'must have at least $min properties'),
      );
    }
    if (max != null && value.length > max) {
      issues.add(
        AgentJsonSchemaIssue(path, 'must have at most $max properties'),
      );
    }
    final required = (schema['required'] as List?)?.cast<String>() ?? const [];
    for (final name in required) {
      if (!value.containsKey(name)) {
        issues.add(AgentJsonSchemaIssue('$path.$name', 'is required'));
      }
    }
    final properties = schema['properties'] as Map? ?? const {};
    final additional = schema['additionalProperties'];
    for (final entry in value.entries) {
      final name = entry.key.toString();
      final propertySchema = properties[name];
      if (propertySchema is Map) {
        _validateValue(
          entry.value,
          Map<String, dynamic>.from(propertySchema),
          '$path.$name',
          issues,
        );
      } else if (additional == false) {
        issues.add(AgentJsonSchemaIssue('$path.$name', 'is not allowed'));
      } else if (additional is Map) {
        _validateValue(
          entry.value,
          Map<String, dynamic>.from(additional),
          '$path.$name',
          issues,
        );
      }
    }
  }

  void _validateArray(
    List value,
    Map<String, dynamic> schema,
    String path,
    List<AgentJsonSchemaIssue> issues,
  ) {
    final min = schema['minItems'] as int?;
    final max = schema['maxItems'] as int?;
    if (min != null && value.length < min) {
      issues.add(
        AgentJsonSchemaIssue(path, 'must contain at least $min items'),
      );
    }
    if (max != null && value.length > max) {
      issues.add(AgentJsonSchemaIssue(path, 'must contain at most $max items'));
    }
    if (schema['uniqueItems'] == true && value.toSet().length != value.length) {
      issues.add(AgentJsonSchemaIssue(path, 'items must be unique'));
    }
    final items = schema['items'];
    if (items is Map) {
      for (var index = 0; index < value.length; index++) {
        _validateValue(
          value[index],
          Map<String, dynamic>.from(items),
          '$path[$index]',
          issues,
        );
      }
    }
  }

  void _validateString(
    String value,
    Map<String, dynamic> schema,
    String path,
    List<AgentJsonSchemaIssue> issues,
  ) {
    final min = schema['minLength'] as int?;
    final max = schema['maxLength'] as int?;
    if (min != null && value.length < min) {
      issues.add(
        AgentJsonSchemaIssue(path, 'must be at least $min characters'),
      );
    }
    if (max != null && value.length > max) {
      issues.add(AgentJsonSchemaIssue(path, 'must be at most $max characters'));
    }
    final pattern = schema['pattern'] as String?;
    if (pattern != null && !RegExp(pattern).hasMatch(value)) {
      issues.add(AgentJsonSchemaIssue(path, 'does not match required pattern'));
    }
  }

  void _validateNumber(
    num value,
    Map<String, dynamic> schema,
    String path,
    List<AgentJsonSchemaIssue> issues,
  ) {
    final minimum = schema['minimum'] as num?;
    final maximum = schema['maximum'] as num?;
    final exclusiveMinimum = schema['exclusiveMinimum'] as num?;
    final exclusiveMaximum = schema['exclusiveMaximum'] as num?;
    if (minimum != null && value < minimum) {
      issues.add(AgentJsonSchemaIssue(path, 'must be at least $minimum'));
    }
    if (maximum != null && value > maximum) {
      issues.add(AgentJsonSchemaIssue(path, 'must be at most $maximum'));
    }
    if (exclusiveMinimum != null && value <= exclusiveMinimum) {
      issues.add(
        AgentJsonSchemaIssue(path, 'must be greater than $exclusiveMinimum'),
      );
    }
    if (exclusiveMaximum != null && value >= exclusiveMaximum) {
      issues.add(
        AgentJsonSchemaIssue(path, 'must be less than $exclusiveMaximum'),
      );
    }
  }

  bool _hasType(Object? value, String type) => switch (type) {
    'null' => value == null,
    'boolean' => value is bool,
    'integer' =>
      value is int || (value is num && value == value.roundToDouble()),
    'number' => value is num && value is! bool,
    'string' => value is String,
    'array' => value is List,
    'object' => value is Map,
    _ => false,
  };

  bool _matchesAny(Object? value, List schemas) =>
      _matchCount(value, schemas) > 0;

  int _matchCount(Object? value, List schemas) {
    return schemas.where((schema) {
      return _matches(value, Map<String, dynamic>.from(schema as Map));
    }).length;
  }

  bool _matches(Object? value, Map<String, dynamic> schema) {
    final issues = <AgentJsonSchemaIssue>[];
    _validateValue(value, schema, r'$', issues);
    return issues.isEmpty;
  }
}
