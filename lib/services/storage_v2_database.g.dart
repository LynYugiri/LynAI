// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'storage_v2_database.dart';

// ignore_for_file: type=lint
class $StorageMetaTable extends StorageMeta
    with TableInfo<$StorageMetaTable, StorageMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StorageMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'storage_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<StorageMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  StorageMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StorageMetaData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $StorageMetaTable createAlias(String alias) {
    return $StorageMetaTable(attachedDatabase, alias);
  }
}

class StorageMetaData extends DataClass implements Insertable<StorageMetaData> {
  final String key;
  final String value;
  const StorageMetaData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  StorageMetaCompanion toCompanion(bool nullToAbsent) {
    return StorageMetaCompanion(key: Value(key), value: Value(value));
  }

  factory StorageMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StorageMetaData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  StorageMetaData copyWith({String? key, String? value}) =>
      StorageMetaData(key: key ?? this.key, value: value ?? this.value);
  StorageMetaData copyWithCompanion(StorageMetaCompanion data) {
    return StorageMetaData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StorageMetaData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StorageMetaData &&
          other.key == this.key &&
          other.value == this.value);
}

class StorageMetaCompanion extends UpdateCompanion<StorageMetaData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const StorageMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StorageMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<StorageMetaData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StorageMetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return StorageMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StorageMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsRowsTable extends AppSettingsRows
    with TableInfo<$AppSettingsRowsTable, AppSettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _settingsJsonMeta = const VerificationMeta(
    'settingsJson',
  );
  @override
  late final GeneratedColumn<String> settingsJson = GeneratedColumn<String>(
    'settings_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, settingsJson, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSettingsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('settings_json')) {
      context.handle(
        _settingsJsonMeta,
        settingsJson.isAcceptableOrUnknown(
          data['settings_json']!,
          _settingsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_settingsJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppSettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSettingsRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      settingsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}settings_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AppSettingsRowsTable createAlias(String alias) {
    return $AppSettingsRowsTable(attachedDatabase, alias);
  }
}

class AppSettingsRow extends DataClass implements Insertable<AppSettingsRow> {
  final int id;
  final String settingsJson;
  final String updatedAt;
  const AppSettingsRow({
    required this.id,
    required this.settingsJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['settings_json'] = Variable<String>(settingsJson);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  AppSettingsRowsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsRowsCompanion(
      id: Value(id),
      settingsJson: Value(settingsJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppSettingsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSettingsRow(
      id: serializer.fromJson<int>(json['id']),
      settingsJson: serializer.fromJson<String>(json['settingsJson']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'settingsJson': serializer.toJson<String>(settingsJson),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  AppSettingsRow copyWith({int? id, String? settingsJson, String? updatedAt}) =>
      AppSettingsRow(
        id: id ?? this.id,
        settingsJson: settingsJson ?? this.settingsJson,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  AppSettingsRow copyWithCompanion(AppSettingsRowsCompanion data) {
    return AppSettingsRow(
      id: data.id.present ? data.id.value : this.id,
      settingsJson: data.settingsJson.present
          ? data.settingsJson.value
          : this.settingsJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsRow(')
          ..write('id: $id, ')
          ..write('settingsJson: $settingsJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, settingsJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSettingsRow &&
          other.id == this.id &&
          other.settingsJson == this.settingsJson &&
          other.updatedAt == this.updatedAt);
}

class AppSettingsRowsCompanion extends UpdateCompanion<AppSettingsRow> {
  final Value<int> id;
  final Value<String> settingsJson;
  final Value<String> updatedAt;
  const AppSettingsRowsCompanion({
    this.id = const Value.absent(),
    this.settingsJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  AppSettingsRowsCompanion.insert({
    this.id = const Value.absent(),
    required String settingsJson,
    required String updatedAt,
  }) : settingsJson = Value(settingsJson),
       updatedAt = Value(updatedAt);
  static Insertable<AppSettingsRow> custom({
    Expression<int>? id,
    Expression<String>? settingsJson,
    Expression<String>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (settingsJson != null) 'settings_json': settingsJson,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  AppSettingsRowsCompanion copyWith({
    Value<int>? id,
    Value<String>? settingsJson,
    Value<String>? updatedAt,
  }) {
    return AppSettingsRowsCompanion(
      id: id ?? this.id,
      settingsJson: settingsJson ?? this.settingsJson,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (settingsJson.present) {
      map['settings_json'] = Variable<String>(settingsJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsRowsCompanion(')
          ..write('id: $id, ')
          ..write('settingsJson: $settingsJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ModelConfigRowsTable extends ModelConfigRows
    with TableInfo<$ModelConfigRowsTable, ModelConfigRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ModelConfigRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _configJsonMeta = const VerificationMeta(
    'configJson',
  );
  @override
  late final GeneratedColumn<String> configJson = GeneratedColumn<String>(
    'config_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<int> enabled = GeneratedColumn<int>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    configJson,
    category,
    enabled,
    priority,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'model_configs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ModelConfigRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('config_json')) {
      context.handle(
        _configJsonMeta,
        configJson.isAcceptableOrUnknown(data['config_json']!, _configJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_configJsonMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    } else if (isInserting) {
      context.missing(_enabledMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    } else if (isInserting) {
      context.missing(_priorityMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ModelConfigRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ModelConfigRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      configJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_json'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}enabled'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ModelConfigRowsTable createAlias(String alias) {
    return $ModelConfigRowsTable(attachedDatabase, alias);
  }
}

class ModelConfigRow extends DataClass implements Insertable<ModelConfigRow> {
  final String id;
  final String configJson;
  final String category;
  final int enabled;
  final int priority;
  final String updatedAt;
  const ModelConfigRow({
    required this.id,
    required this.configJson,
    required this.category,
    required this.enabled,
    required this.priority,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['config_json'] = Variable<String>(configJson);
    map['category'] = Variable<String>(category);
    map['enabled'] = Variable<int>(enabled);
    map['priority'] = Variable<int>(priority);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  ModelConfigRowsCompanion toCompanion(bool nullToAbsent) {
    return ModelConfigRowsCompanion(
      id: Value(id),
      configJson: Value(configJson),
      category: Value(category),
      enabled: Value(enabled),
      priority: Value(priority),
      updatedAt: Value(updatedAt),
    );
  }

  factory ModelConfigRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ModelConfigRow(
      id: serializer.fromJson<String>(json['id']),
      configJson: serializer.fromJson<String>(json['configJson']),
      category: serializer.fromJson<String>(json['category']),
      enabled: serializer.fromJson<int>(json['enabled']),
      priority: serializer.fromJson<int>(json['priority']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'configJson': serializer.toJson<String>(configJson),
      'category': serializer.toJson<String>(category),
      'enabled': serializer.toJson<int>(enabled),
      'priority': serializer.toJson<int>(priority),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  ModelConfigRow copyWith({
    String? id,
    String? configJson,
    String? category,
    int? enabled,
    int? priority,
    String? updatedAt,
  }) => ModelConfigRow(
    id: id ?? this.id,
    configJson: configJson ?? this.configJson,
    category: category ?? this.category,
    enabled: enabled ?? this.enabled,
    priority: priority ?? this.priority,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ModelConfigRow copyWithCompanion(ModelConfigRowsCompanion data) {
    return ModelConfigRow(
      id: data.id.present ? data.id.value : this.id,
      configJson: data.configJson.present
          ? data.configJson.value
          : this.configJson,
      category: data.category.present ? data.category.value : this.category,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      priority: data.priority.present ? data.priority.value : this.priority,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ModelConfigRow(')
          ..write('id: $id, ')
          ..write('configJson: $configJson, ')
          ..write('category: $category, ')
          ..write('enabled: $enabled, ')
          ..write('priority: $priority, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, configJson, category, enabled, priority, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ModelConfigRow &&
          other.id == this.id &&
          other.configJson == this.configJson &&
          other.category == this.category &&
          other.enabled == this.enabled &&
          other.priority == this.priority &&
          other.updatedAt == this.updatedAt);
}

class ModelConfigRowsCompanion extends UpdateCompanion<ModelConfigRow> {
  final Value<String> id;
  final Value<String> configJson;
  final Value<String> category;
  final Value<int> enabled;
  final Value<int> priority;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const ModelConfigRowsCompanion({
    this.id = const Value.absent(),
    this.configJson = const Value.absent(),
    this.category = const Value.absent(),
    this.enabled = const Value.absent(),
    this.priority = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ModelConfigRowsCompanion.insert({
    required String id,
    required String configJson,
    required String category,
    required int enabled,
    required int priority,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       configJson = Value(configJson),
       category = Value(category),
       enabled = Value(enabled),
       priority = Value(priority),
       updatedAt = Value(updatedAt);
  static Insertable<ModelConfigRow> custom({
    Expression<String>? id,
    Expression<String>? configJson,
    Expression<String>? category,
    Expression<int>? enabled,
    Expression<int>? priority,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (configJson != null) 'config_json': configJson,
      if (category != null) 'category': category,
      if (enabled != null) 'enabled': enabled,
      if (priority != null) 'priority': priority,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ModelConfigRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? configJson,
    Value<String>? category,
    Value<int>? enabled,
    Value<int>? priority,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return ModelConfigRowsCompanion(
      id: id ?? this.id,
      configJson: configJson ?? this.configJson,
      category: category ?? this.category,
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (configJson.present) {
      map['config_json'] = Variable<String>(configJson.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<int>(enabled.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ModelConfigRowsCompanion(')
          ..write('id: $id, ')
          ..write('configJson: $configJson, ')
          ..write('category: $category, ')
          ..write('enabled: $enabled, ')
          ..write('priority: $priority, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ResourceRowsTable extends ResourceRows
    with TableInfo<$ResourceRowsTable, ResourceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ResourceRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originalPathMeta = const VerificationMeta(
    'originalPath',
  );
  @override
  late final GeneratedColumn<String> originalPath = GeneratedColumn<String>(
    'original_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originalNameMeta = const VerificationMeta(
    'originalName',
  );
  @override
  late final GeneratedColumn<String> originalName = GeneratedColumn<String>(
    'original_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _missingMeta = const VerificationMeta(
    'missing',
  );
  @override
  late final GeneratedColumn<int> missing = GeneratedColumn<int>(
    'missing',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    role,
    originalPath,
    originalName,
    relativePath,
    mimeType,
    size,
    sha256,
    missing,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'resources';
  @override
  VerificationContext validateIntegrity(
    Insertable<ResourceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('original_path')) {
      context.handle(
        _originalPathMeta,
        originalPath.isAcceptableOrUnknown(
          data['original_path']!,
          _originalPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalPathMeta);
    }
    if (data.containsKey('original_name')) {
      context.handle(
        _originalNameMeta,
        originalName.isAcceptableOrUnknown(
          data['original_name']!,
          _originalNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalNameMeta);
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    }
    if (data.containsKey('missing')) {
      context.handle(
        _missingMeta,
        missing.isAcceptableOrUnknown(data['missing']!, _missingMeta),
      );
    } else if (isInserting) {
      context.missing(_missingMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ResourceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ResourceRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      originalPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_path'],
      )!,
      originalName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_name'],
      )!,
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      ),
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      ),
      missing: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}missing'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ResourceRowsTable createAlias(String alias) {
    return $ResourceRowsTable(attachedDatabase, alias);
  }
}

class ResourceRow extends DataClass implements Insertable<ResourceRow> {
  final String id;
  final String kind;
  final String role;
  final String originalPath;
  final String originalName;
  final String? relativePath;
  final String mimeType;
  final int size;
  final String? sha256;
  final int missing;
  final String createdAt;
  const ResourceRow({
    required this.id,
    required this.kind,
    required this.role,
    required this.originalPath,
    required this.originalName,
    this.relativePath,
    required this.mimeType,
    required this.size,
    this.sha256,
    required this.missing,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    map['role'] = Variable<String>(role);
    map['original_path'] = Variable<String>(originalPath);
    map['original_name'] = Variable<String>(originalName);
    if (!nullToAbsent || relativePath != null) {
      map['relative_path'] = Variable<String>(relativePath);
    }
    map['mime_type'] = Variable<String>(mimeType);
    map['size'] = Variable<int>(size);
    if (!nullToAbsent || sha256 != null) {
      map['sha256'] = Variable<String>(sha256);
    }
    map['missing'] = Variable<int>(missing);
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  ResourceRowsCompanion toCompanion(bool nullToAbsent) {
    return ResourceRowsCompanion(
      id: Value(id),
      kind: Value(kind),
      role: Value(role),
      originalPath: Value(originalPath),
      originalName: Value(originalName),
      relativePath: relativePath == null && nullToAbsent
          ? const Value.absent()
          : Value(relativePath),
      mimeType: Value(mimeType),
      size: Value(size),
      sha256: sha256 == null && nullToAbsent
          ? const Value.absent()
          : Value(sha256),
      missing: Value(missing),
      createdAt: Value(createdAt),
    );
  }

  factory ResourceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ResourceRow(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      role: serializer.fromJson<String>(json['role']),
      originalPath: serializer.fromJson<String>(json['originalPath']),
      originalName: serializer.fromJson<String>(json['originalName']),
      relativePath: serializer.fromJson<String?>(json['relativePath']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      size: serializer.fromJson<int>(json['size']),
      sha256: serializer.fromJson<String?>(json['sha256']),
      missing: serializer.fromJson<int>(json['missing']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'role': serializer.toJson<String>(role),
      'originalPath': serializer.toJson<String>(originalPath),
      'originalName': serializer.toJson<String>(originalName),
      'relativePath': serializer.toJson<String?>(relativePath),
      'mimeType': serializer.toJson<String>(mimeType),
      'size': serializer.toJson<int>(size),
      'sha256': serializer.toJson<String?>(sha256),
      'missing': serializer.toJson<int>(missing),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  ResourceRow copyWith({
    String? id,
    String? kind,
    String? role,
    String? originalPath,
    String? originalName,
    Value<String?> relativePath = const Value.absent(),
    String? mimeType,
    int? size,
    Value<String?> sha256 = const Value.absent(),
    int? missing,
    String? createdAt,
  }) => ResourceRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    role: role ?? this.role,
    originalPath: originalPath ?? this.originalPath,
    originalName: originalName ?? this.originalName,
    relativePath: relativePath.present ? relativePath.value : this.relativePath,
    mimeType: mimeType ?? this.mimeType,
    size: size ?? this.size,
    sha256: sha256.present ? sha256.value : this.sha256,
    missing: missing ?? this.missing,
    createdAt: createdAt ?? this.createdAt,
  );
  ResourceRow copyWithCompanion(ResourceRowsCompanion data) {
    return ResourceRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      role: data.role.present ? data.role.value : this.role,
      originalPath: data.originalPath.present
          ? data.originalPath.value
          : this.originalPath,
      originalName: data.originalName.present
          ? data.originalName.value
          : this.originalName,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      size: data.size.present ? data.size.value : this.size,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      missing: data.missing.present ? data.missing.value : this.missing,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ResourceRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('role: $role, ')
          ..write('originalPath: $originalPath, ')
          ..write('originalName: $originalName, ')
          ..write('relativePath: $relativePath, ')
          ..write('mimeType: $mimeType, ')
          ..write('size: $size, ')
          ..write('sha256: $sha256, ')
          ..write('missing: $missing, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    role,
    originalPath,
    originalName,
    relativePath,
    mimeType,
    size,
    sha256,
    missing,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ResourceRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.role == this.role &&
          other.originalPath == this.originalPath &&
          other.originalName == this.originalName &&
          other.relativePath == this.relativePath &&
          other.mimeType == this.mimeType &&
          other.size == this.size &&
          other.sha256 == this.sha256 &&
          other.missing == this.missing &&
          other.createdAt == this.createdAt);
}

class ResourceRowsCompanion extends UpdateCompanion<ResourceRow> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String> role;
  final Value<String> originalPath;
  final Value<String> originalName;
  final Value<String?> relativePath;
  final Value<String> mimeType;
  final Value<int> size;
  final Value<String?> sha256;
  final Value<int> missing;
  final Value<String> createdAt;
  final Value<int> rowid;
  const ResourceRowsCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.role = const Value.absent(),
    this.originalPath = const Value.absent(),
    this.originalName = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.size = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.missing = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ResourceRowsCompanion.insert({
    required String id,
    required String kind,
    required String role,
    required String originalPath,
    required String originalName,
    this.relativePath = const Value.absent(),
    required String mimeType,
    required int size,
    this.sha256 = const Value.absent(),
    required int missing,
    required String createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       role = Value(role),
       originalPath = Value(originalPath),
       originalName = Value(originalName),
       mimeType = Value(mimeType),
       size = Value(size),
       missing = Value(missing),
       createdAt = Value(createdAt);
  static Insertable<ResourceRow> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? role,
    Expression<String>? originalPath,
    Expression<String>? originalName,
    Expression<String>? relativePath,
    Expression<String>? mimeType,
    Expression<int>? size,
    Expression<String>? sha256,
    Expression<int>? missing,
    Expression<String>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (role != null) 'role': role,
      if (originalPath != null) 'original_path': originalPath,
      if (originalName != null) 'original_name': originalName,
      if (relativePath != null) 'relative_path': relativePath,
      if (mimeType != null) 'mime_type': mimeType,
      if (size != null) 'size': size,
      if (sha256 != null) 'sha256': sha256,
      if (missing != null) 'missing': missing,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ResourceRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<String>? role,
    Value<String>? originalPath,
    Value<String>? originalName,
    Value<String?>? relativePath,
    Value<String>? mimeType,
    Value<int>? size,
    Value<String?>? sha256,
    Value<int>? missing,
    Value<String>? createdAt,
    Value<int>? rowid,
  }) {
    return ResourceRowsCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      role: role ?? this.role,
      originalPath: originalPath ?? this.originalPath,
      originalName: originalName ?? this.originalName,
      relativePath: relativePath ?? this.relativePath,
      mimeType: mimeType ?? this.mimeType,
      size: size ?? this.size,
      sha256: sha256 ?? this.sha256,
      missing: missing ?? this.missing,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (originalPath.present) {
      map['original_path'] = Variable<String>(originalPath.value);
    }
    if (originalName.present) {
      map['original_name'] = Variable<String>(originalName.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (missing.present) {
      map['missing'] = Variable<int>(missing.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ResourceRowsCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('role: $role, ')
          ..write('originalPath: $originalPath, ')
          ..write('originalName: $originalName, ')
          ..write('relativePath: $relativePath, ')
          ..write('mimeType: $mimeType, ')
          ..write('size: $size, ')
          ..write('sha256: $sha256, ')
          ..write('missing: $missing, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConversationRowsTable extends ConversationRows
    with TableInfo<$ConversationRowsTable, ConversationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _settingsJsonMeta = const VerificationMeta(
    'settingsJson',
  );
  @override
  late final GeneratedColumn<String> settingsJson = GeneratedColumn<String>(
    'settings_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _agentPlanJsonMeta = const VerificationMeta(
    'agentPlanJson',
  );
  @override
  late final GeneratedColumn<String> agentPlanJson = GeneratedColumn<String>(
    'agent_plan_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _agentWorkingMemoryJsonMeta =
      const VerificationMeta('agentWorkingMemoryJson');
  @override
  late final GeneratedColumn<String> agentWorkingMemoryJson =
      GeneratedColumn<String>(
        'agent_working_memory_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _roleIdMeta = const VerificationMeta('roleId');
  @override
  late final GeneratedColumn<String> roleId = GeneratedColumn<String>(
    'role_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    modelId,
    settingsJson,
    agentPlanJson,
    agentWorkingMemoryJson,
    roleId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConversationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_modelIdMeta);
    }
    if (data.containsKey('settings_json')) {
      context.handle(
        _settingsJsonMeta,
        settingsJson.isAcceptableOrUnknown(
          data['settings_json']!,
          _settingsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_settingsJsonMeta);
    }
    if (data.containsKey('agent_plan_json')) {
      context.handle(
        _agentPlanJsonMeta,
        agentPlanJson.isAcceptableOrUnknown(
          data['agent_plan_json']!,
          _agentPlanJsonMeta,
        ),
      );
    }
    if (data.containsKey('agent_working_memory_json')) {
      context.handle(
        _agentWorkingMemoryJsonMeta,
        agentWorkingMemoryJson.isAcceptableOrUnknown(
          data['agent_working_memory_json']!,
          _agentWorkingMemoryJsonMeta,
        ),
      );
    }
    if (data.containsKey('role_id')) {
      context.handle(
        _roleIdMeta,
        roleId.isAcceptableOrUnknown(data['role_id']!, _roleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_roleIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConversationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConversationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      )!,
      settingsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}settings_json'],
      )!,
      agentPlanJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_plan_json'],
      ),
      agentWorkingMemoryJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_working_memory_json'],
      ),
      roleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ConversationRowsTable createAlias(String alias) {
    return $ConversationRowsTable(attachedDatabase, alias);
  }
}

class ConversationRow extends DataClass implements Insertable<ConversationRow> {
  final String id;
  final String title;
  final String modelId;
  final String settingsJson;
  final String? agentPlanJson;
  final String? agentWorkingMemoryJson;
  final String roleId;
  final String createdAt;
  final String updatedAt;
  const ConversationRow({
    required this.id,
    required this.title,
    required this.modelId,
    required this.settingsJson,
    this.agentPlanJson,
    this.agentWorkingMemoryJson,
    required this.roleId,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['model_id'] = Variable<String>(modelId);
    map['settings_json'] = Variable<String>(settingsJson);
    if (!nullToAbsent || agentPlanJson != null) {
      map['agent_plan_json'] = Variable<String>(agentPlanJson);
    }
    if (!nullToAbsent || agentWorkingMemoryJson != null) {
      map['agent_working_memory_json'] = Variable<String>(
        agentWorkingMemoryJson,
      );
    }
    map['role_id'] = Variable<String>(roleId);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  ConversationRowsCompanion toCompanion(bool nullToAbsent) {
    return ConversationRowsCompanion(
      id: Value(id),
      title: Value(title),
      modelId: Value(modelId),
      settingsJson: Value(settingsJson),
      agentPlanJson: agentPlanJson == null && nullToAbsent
          ? const Value.absent()
          : Value(agentPlanJson),
      agentWorkingMemoryJson: agentWorkingMemoryJson == null && nullToAbsent
          ? const Value.absent()
          : Value(agentWorkingMemoryJson),
      roleId: Value(roleId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ConversationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConversationRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      modelId: serializer.fromJson<String>(json['modelId']),
      settingsJson: serializer.fromJson<String>(json['settingsJson']),
      agentPlanJson: serializer.fromJson<String?>(json['agentPlanJson']),
      agentWorkingMemoryJson: serializer.fromJson<String?>(
        json['agentWorkingMemoryJson'],
      ),
      roleId: serializer.fromJson<String>(json['roleId']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'modelId': serializer.toJson<String>(modelId),
      'settingsJson': serializer.toJson<String>(settingsJson),
      'agentPlanJson': serializer.toJson<String?>(agentPlanJson),
      'agentWorkingMemoryJson': serializer.toJson<String?>(
        agentWorkingMemoryJson,
      ),
      'roleId': serializer.toJson<String>(roleId),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  ConversationRow copyWith({
    String? id,
    String? title,
    String? modelId,
    String? settingsJson,
    Value<String?> agentPlanJson = const Value.absent(),
    Value<String?> agentWorkingMemoryJson = const Value.absent(),
    String? roleId,
    String? createdAt,
    String? updatedAt,
  }) => ConversationRow(
    id: id ?? this.id,
    title: title ?? this.title,
    modelId: modelId ?? this.modelId,
    settingsJson: settingsJson ?? this.settingsJson,
    agentPlanJson: agentPlanJson.present
        ? agentPlanJson.value
        : this.agentPlanJson,
    agentWorkingMemoryJson: agentWorkingMemoryJson.present
        ? agentWorkingMemoryJson.value
        : this.agentWorkingMemoryJson,
    roleId: roleId ?? this.roleId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ConversationRow copyWithCompanion(ConversationRowsCompanion data) {
    return ConversationRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      settingsJson: data.settingsJson.present
          ? data.settingsJson.value
          : this.settingsJson,
      agentPlanJson: data.agentPlanJson.present
          ? data.agentPlanJson.value
          : this.agentPlanJson,
      agentWorkingMemoryJson: data.agentWorkingMemoryJson.present
          ? data.agentWorkingMemoryJson.value
          : this.agentWorkingMemoryJson,
      roleId: data.roleId.present ? data.roleId.value : this.roleId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConversationRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('modelId: $modelId, ')
          ..write('settingsJson: $settingsJson, ')
          ..write('agentPlanJson: $agentPlanJson, ')
          ..write('agentWorkingMemoryJson: $agentWorkingMemoryJson, ')
          ..write('roleId: $roleId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    modelId,
    settingsJson,
    agentPlanJson,
    agentWorkingMemoryJson,
    roleId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConversationRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.modelId == this.modelId &&
          other.settingsJson == this.settingsJson &&
          other.agentPlanJson == this.agentPlanJson &&
          other.agentWorkingMemoryJson == this.agentWorkingMemoryJson &&
          other.roleId == this.roleId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ConversationRowsCompanion extends UpdateCompanion<ConversationRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> modelId;
  final Value<String> settingsJson;
  final Value<String?> agentPlanJson;
  final Value<String?> agentWorkingMemoryJson;
  final Value<String> roleId;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const ConversationRowsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.modelId = const Value.absent(),
    this.settingsJson = const Value.absent(),
    this.agentPlanJson = const Value.absent(),
    this.agentWorkingMemoryJson = const Value.absent(),
    this.roleId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationRowsCompanion.insert({
    required String id,
    required String title,
    required String modelId,
    required String settingsJson,
    this.agentPlanJson = const Value.absent(),
    this.agentWorkingMemoryJson = const Value.absent(),
    required String roleId,
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       modelId = Value(modelId),
       settingsJson = Value(settingsJson),
       roleId = Value(roleId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ConversationRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? modelId,
    Expression<String>? settingsJson,
    Expression<String>? agentPlanJson,
    Expression<String>? agentWorkingMemoryJson,
    Expression<String>? roleId,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (modelId != null) 'model_id': modelId,
      if (settingsJson != null) 'settings_json': settingsJson,
      if (agentPlanJson != null) 'agent_plan_json': agentPlanJson,
      if (agentWorkingMemoryJson != null)
        'agent_working_memory_json': agentWorkingMemoryJson,
      if (roleId != null) 'role_id': roleId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? modelId,
    Value<String>? settingsJson,
    Value<String?>? agentPlanJson,
    Value<String?>? agentWorkingMemoryJson,
    Value<String>? roleId,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return ConversationRowsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      modelId: modelId ?? this.modelId,
      settingsJson: settingsJson ?? this.settingsJson,
      agentPlanJson: agentPlanJson ?? this.agentPlanJson,
      agentWorkingMemoryJson:
          agentWorkingMemoryJson ?? this.agentWorkingMemoryJson,
      roleId: roleId ?? this.roleId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (settingsJson.present) {
      map['settings_json'] = Variable<String>(settingsJson.value);
    }
    if (agentPlanJson.present) {
      map['agent_plan_json'] = Variable<String>(agentPlanJson.value);
    }
    if (agentWorkingMemoryJson.present) {
      map['agent_working_memory_json'] = Variable<String>(
        agentWorkingMemoryJson.value,
      );
    }
    if (roleId.present) {
      map['role_id'] = Variable<String>(roleId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationRowsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('modelId: $modelId, ')
          ..write('settingsJson: $settingsJson, ')
          ..write('agentPlanJson: $agentPlanJson, ')
          ..write('agentWorkingMemoryJson: $agentWorkingMemoryJson, ')
          ..write('roleId: $roleId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessageRowsTable extends MessageRows
    with TableInfo<$MessageRowsTable, MessageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessageRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thinkingContentMeta = const VerificationMeta(
    'thinkingContent',
  );
  @override
  late final GeneratedColumn<String> thinkingContent = GeneratedColumn<String>(
    'thinking_content',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _agentTraceJsonMeta = const VerificationMeta(
    'agentTraceJson',
  );
  @override
  late final GeneratedColumn<String> agentTraceJson = GeneratedColumn<String>(
    'agent_trace_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<String> timestamp = GeneratedColumn<String>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    role,
    content,
    thinkingContent,
    agentTraceJson,
    timestamp,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('thinking_content')) {
      context.handle(
        _thinkingContentMeta,
        thinkingContent.isAcceptableOrUnknown(
          data['thinking_content']!,
          _thinkingContentMeta,
        ),
      );
    }
    if (data.containsKey('agent_trace_json')) {
      context.handle(
        _agentTraceJsonMeta,
        agentTraceJson.isAcceptableOrUnknown(
          data['agent_trace_json']!,
          _agentTraceJsonMeta,
        ),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MessageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      thinkingContent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thinking_content'],
      ),
      agentTraceJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_trace_json'],
      ),
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timestamp'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $MessageRowsTable createAlias(String alias) {
    return $MessageRowsTable(attachedDatabase, alias);
  }
}

class MessageRow extends DataClass implements Insertable<MessageRow> {
  final String id;
  final String conversationId;
  final String role;
  final String content;
  final String? thinkingContent;
  final String? agentTraceJson;
  final String timestamp;
  final int sortOrder;
  const MessageRow({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.thinkingContent,
    this.agentTraceJson,
    required this.timestamp,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['role'] = Variable<String>(role);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || thinkingContent != null) {
      map['thinking_content'] = Variable<String>(thinkingContent);
    }
    if (!nullToAbsent || agentTraceJson != null) {
      map['agent_trace_json'] = Variable<String>(agentTraceJson);
    }
    map['timestamp'] = Variable<String>(timestamp);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  MessageRowsCompanion toCompanion(bool nullToAbsent) {
    return MessageRowsCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      role: Value(role),
      content: Value(content),
      thinkingContent: thinkingContent == null && nullToAbsent
          ? const Value.absent()
          : Value(thinkingContent),
      agentTraceJson: agentTraceJson == null && nullToAbsent
          ? const Value.absent()
          : Value(agentTraceJson),
      timestamp: Value(timestamp),
      sortOrder: Value(sortOrder),
    );
  }

  factory MessageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageRow(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      role: serializer.fromJson<String>(json['role']),
      content: serializer.fromJson<String>(json['content']),
      thinkingContent: serializer.fromJson<String?>(json['thinkingContent']),
      agentTraceJson: serializer.fromJson<String?>(json['agentTraceJson']),
      timestamp: serializer.fromJson<String>(json['timestamp']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'role': serializer.toJson<String>(role),
      'content': serializer.toJson<String>(content),
      'thinkingContent': serializer.toJson<String?>(thinkingContent),
      'agentTraceJson': serializer.toJson<String?>(agentTraceJson),
      'timestamp': serializer.toJson<String>(timestamp),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  MessageRow copyWith({
    String? id,
    String? conversationId,
    String? role,
    String? content,
    Value<String?> thinkingContent = const Value.absent(),
    Value<String?> agentTraceJson = const Value.absent(),
    String? timestamp,
    int? sortOrder,
  }) => MessageRow(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    role: role ?? this.role,
    content: content ?? this.content,
    thinkingContent: thinkingContent.present
        ? thinkingContent.value
        : this.thinkingContent,
    agentTraceJson: agentTraceJson.present
        ? agentTraceJson.value
        : this.agentTraceJson,
    timestamp: timestamp ?? this.timestamp,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  MessageRow copyWithCompanion(MessageRowsCompanion data) {
    return MessageRow(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      thinkingContent: data.thinkingContent.present
          ? data.thinkingContent.value
          : this.thinkingContent,
      agentTraceJson: data.agentTraceJson.present
          ? data.agentTraceJson.value
          : this.agentTraceJson,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageRow(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('thinkingContent: $thinkingContent, ')
          ..write('agentTraceJson: $agentTraceJson, ')
          ..write('timestamp: $timestamp, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    role,
    content,
    thinkingContent,
    agentTraceJson,
    timestamp,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageRow &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.role == this.role &&
          other.content == this.content &&
          other.thinkingContent == this.thinkingContent &&
          other.agentTraceJson == this.agentTraceJson &&
          other.timestamp == this.timestamp &&
          other.sortOrder == this.sortOrder);
}

class MessageRowsCompanion extends UpdateCompanion<MessageRow> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<String> role;
  final Value<String> content;
  final Value<String?> thinkingContent;
  final Value<String?> agentTraceJson;
  final Value<String> timestamp;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const MessageRowsCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.thinkingContent = const Value.absent(),
    this.agentTraceJson = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessageRowsCompanion.insert({
    required String id,
    required String conversationId,
    required String role,
    required String content,
    this.thinkingContent = const Value.absent(),
    this.agentTraceJson = const Value.absent(),
    required String timestamp,
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       conversationId = Value(conversationId),
       role = Value(role),
       content = Value(content),
       timestamp = Value(timestamp);
  static Insertable<MessageRow> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? role,
    Expression<String>? content,
    Expression<String>? thinkingContent,
    Expression<String>? agentTraceJson,
    Expression<String>? timestamp,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (thinkingContent != null) 'thinking_content': thinkingContent,
      if (agentTraceJson != null) 'agent_trace_json': agentTraceJson,
      if (timestamp != null) 'timestamp': timestamp,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessageRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? conversationId,
    Value<String>? role,
    Value<String>? content,
    Value<String?>? thinkingContent,
    Value<String?>? agentTraceJson,
    Value<String>? timestamp,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return MessageRowsCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      thinkingContent: thinkingContent ?? this.thinkingContent,
      agentTraceJson: agentTraceJson ?? this.agentTraceJson,
      timestamp: timestamp ?? this.timestamp,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (thinkingContent.present) {
      map['thinking_content'] = Variable<String>(thinkingContent.value);
    }
    if (agentTraceJson.present) {
      map['agent_trace_json'] = Variable<String>(agentTraceJson.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<String>(timestamp.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessageRowsCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('thinkingContent: $thinkingContent, ')
          ..write('agentTraceJson: $agentTraceJson, ')
          ..write('timestamp: $timestamp, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessageAttachmentRowsTable extends MessageAttachmentRows
    with TableInfo<$MessageAttachmentRowsTable, MessageAttachmentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessageAttachmentRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resourceIdMeta = const VerificationMeta(
    'resourceId',
  );
  @override
  late final GeneratedColumn<String> resourceId = GeneratedColumn<String>(
    'resource_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _legacyPathMeta = const VerificationMeta(
    'legacyPath',
  );
  @override
  late final GeneratedColumn<String> legacyPath = GeneratedColumn<String>(
    'legacy_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    messageId,
    resourceId,
    displayName,
    mimeType,
    size,
    sortOrder,
    legacyPath,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'message_attachments';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageAttachmentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('resource_id')) {
      context.handle(
        _resourceIdMeta,
        resourceId.isAcceptableOrUnknown(data['resource_id']!, _resourceIdMeta),
      );
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('legacy_path')) {
      context.handle(
        _legacyPathMeta,
        legacyPath.isAcceptableOrUnknown(data['legacy_path']!, _legacyPathMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MessageAttachmentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageAttachmentRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      resourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resource_id'],
      ),
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      legacyPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}legacy_path'],
      ),
    );
  }

  @override
  $MessageAttachmentRowsTable createAlias(String alias) {
    return $MessageAttachmentRowsTable(attachedDatabase, alias);
  }
}

class MessageAttachmentRow extends DataClass
    implements Insertable<MessageAttachmentRow> {
  final String id;
  final String messageId;
  final String? resourceId;
  final String displayName;
  final String mimeType;
  final int size;
  final int sortOrder;
  final String? legacyPath;
  const MessageAttachmentRow({
    required this.id,
    required this.messageId,
    this.resourceId,
    required this.displayName,
    required this.mimeType,
    required this.size,
    required this.sortOrder,
    this.legacyPath,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['message_id'] = Variable<String>(messageId);
    if (!nullToAbsent || resourceId != null) {
      map['resource_id'] = Variable<String>(resourceId);
    }
    map['display_name'] = Variable<String>(displayName);
    map['mime_type'] = Variable<String>(mimeType);
    map['size'] = Variable<int>(size);
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || legacyPath != null) {
      map['legacy_path'] = Variable<String>(legacyPath);
    }
    return map;
  }

  MessageAttachmentRowsCompanion toCompanion(bool nullToAbsent) {
    return MessageAttachmentRowsCompanion(
      id: Value(id),
      messageId: Value(messageId),
      resourceId: resourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(resourceId),
      displayName: Value(displayName),
      mimeType: Value(mimeType),
      size: Value(size),
      sortOrder: Value(sortOrder),
      legacyPath: legacyPath == null && nullToAbsent
          ? const Value.absent()
          : Value(legacyPath),
    );
  }

  factory MessageAttachmentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageAttachmentRow(
      id: serializer.fromJson<String>(json['id']),
      messageId: serializer.fromJson<String>(json['messageId']),
      resourceId: serializer.fromJson<String?>(json['resourceId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      size: serializer.fromJson<int>(json['size']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      legacyPath: serializer.fromJson<String?>(json['legacyPath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'messageId': serializer.toJson<String>(messageId),
      'resourceId': serializer.toJson<String?>(resourceId),
      'displayName': serializer.toJson<String>(displayName),
      'mimeType': serializer.toJson<String>(mimeType),
      'size': serializer.toJson<int>(size),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'legacyPath': serializer.toJson<String?>(legacyPath),
    };
  }

  MessageAttachmentRow copyWith({
    String? id,
    String? messageId,
    Value<String?> resourceId = const Value.absent(),
    String? displayName,
    String? mimeType,
    int? size,
    int? sortOrder,
    Value<String?> legacyPath = const Value.absent(),
  }) => MessageAttachmentRow(
    id: id ?? this.id,
    messageId: messageId ?? this.messageId,
    resourceId: resourceId.present ? resourceId.value : this.resourceId,
    displayName: displayName ?? this.displayName,
    mimeType: mimeType ?? this.mimeType,
    size: size ?? this.size,
    sortOrder: sortOrder ?? this.sortOrder,
    legacyPath: legacyPath.present ? legacyPath.value : this.legacyPath,
  );
  MessageAttachmentRow copyWithCompanion(MessageAttachmentRowsCompanion data) {
    return MessageAttachmentRow(
      id: data.id.present ? data.id.value : this.id,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      resourceId: data.resourceId.present
          ? data.resourceId.value
          : this.resourceId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      size: data.size.present ? data.size.value : this.size,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      legacyPath: data.legacyPath.present
          ? data.legacyPath.value
          : this.legacyPath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageAttachmentRow(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('resourceId: $resourceId, ')
          ..write('displayName: $displayName, ')
          ..write('mimeType: $mimeType, ')
          ..write('size: $size, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('legacyPath: $legacyPath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    messageId,
    resourceId,
    displayName,
    mimeType,
    size,
    sortOrder,
    legacyPath,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageAttachmentRow &&
          other.id == this.id &&
          other.messageId == this.messageId &&
          other.resourceId == this.resourceId &&
          other.displayName == this.displayName &&
          other.mimeType == this.mimeType &&
          other.size == this.size &&
          other.sortOrder == this.sortOrder &&
          other.legacyPath == this.legacyPath);
}

class MessageAttachmentRowsCompanion
    extends UpdateCompanion<MessageAttachmentRow> {
  final Value<String> id;
  final Value<String> messageId;
  final Value<String?> resourceId;
  final Value<String> displayName;
  final Value<String> mimeType;
  final Value<int> size;
  final Value<int> sortOrder;
  final Value<String?> legacyPath;
  final Value<int> rowid;
  const MessageAttachmentRowsCompanion({
    this.id = const Value.absent(),
    this.messageId = const Value.absent(),
    this.resourceId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.size = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.legacyPath = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessageAttachmentRowsCompanion.insert({
    required String id,
    required String messageId,
    this.resourceId = const Value.absent(),
    required String displayName,
    required String mimeType,
    required int size,
    this.sortOrder = const Value.absent(),
    this.legacyPath = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       messageId = Value(messageId),
       displayName = Value(displayName),
       mimeType = Value(mimeType),
       size = Value(size);
  static Insertable<MessageAttachmentRow> custom({
    Expression<String>? id,
    Expression<String>? messageId,
    Expression<String>? resourceId,
    Expression<String>? displayName,
    Expression<String>? mimeType,
    Expression<int>? size,
    Expression<int>? sortOrder,
    Expression<String>? legacyPath,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (messageId != null) 'message_id': messageId,
      if (resourceId != null) 'resource_id': resourceId,
      if (displayName != null) 'display_name': displayName,
      if (mimeType != null) 'mime_type': mimeType,
      if (size != null) 'size': size,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (legacyPath != null) 'legacy_path': legacyPath,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessageAttachmentRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? messageId,
    Value<String?>? resourceId,
    Value<String>? displayName,
    Value<String>? mimeType,
    Value<int>? size,
    Value<int>? sortOrder,
    Value<String?>? legacyPath,
    Value<int>? rowid,
  }) {
    return MessageAttachmentRowsCompanion(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      resourceId: resourceId ?? this.resourceId,
      displayName: displayName ?? this.displayName,
      mimeType: mimeType ?? this.mimeType,
      size: size ?? this.size,
      sortOrder: sortOrder ?? this.sortOrder,
      legacyPath: legacyPath ?? this.legacyPath,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (resourceId.present) {
      map['resource_id'] = Variable<String>(resourceId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (legacyPath.present) {
      map['legacy_path'] = Variable<String>(legacyPath.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessageAttachmentRowsCompanion(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('resourceId: $resourceId, ')
          ..write('displayName: $displayName, ')
          ..write('mimeType: $mimeType, ')
          ..write('size: $size, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('legacyPath: $legacyPath, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteFolderRowsTable extends NoteFolderRows
    with TableInfo<$NoteFolderRowsTable, NoteFolderRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteFolderRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    createdAt,
    updatedAt,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_folders';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteFolderRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteFolderRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteFolderRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $NoteFolderRowsTable createAlias(String alias) {
    return $NoteFolderRowsTable(attachedDatabase, alias);
  }
}

class NoteFolderRow extends DataClass implements Insertable<NoteFolderRow> {
  final String id;
  final String title;
  final String createdAt;
  final String updatedAt;
  final int sortOrder;
  const NoteFolderRow({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  NoteFolderRowsCompanion toCompanion(bool nullToAbsent) {
    return NoteFolderRowsCompanion(
      id: Value(id),
      title: Value(title),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      sortOrder: Value(sortOrder),
    );
  }

  factory NoteFolderRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteFolderRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  NoteFolderRow copyWith({
    String? id,
    String? title,
    String? createdAt,
    String? updatedAt,
    int? sortOrder,
  }) => NoteFolderRow(
    id: id ?? this.id,
    title: title ?? this.title,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  NoteFolderRow copyWithCompanion(NoteFolderRowsCompanion data) {
    return NoteFolderRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteFolderRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, createdAt, updatedAt, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteFolderRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.sortOrder == this.sortOrder);
}

class NoteFolderRowsCompanion extends UpdateCompanion<NoteFolderRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const NoteFolderRowsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteFolderRowsCompanion.insert({
    required String id,
    required String title,
    required String createdAt,
    required String updatedAt,
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       sortOrder = Value(sortOrder);
  static Insertable<NoteFolderRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteFolderRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return NoteFolderRowsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteFolderRowsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteRowsTable extends NoteRows with TableInfo<$NoteRowsTable, NoteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<String> folderId = GeneratedColumn<String>(
    'folder_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _currentRevisionIdMeta = const VerificationMeta(
    'currentRevisionId',
  );
  @override
  late final GeneratedColumn<String> currentRevisionId =
      GeneratedColumn<String>(
        'current_revision_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _currentPageIdMeta = const VerificationMeta(
    'currentPageId',
  );
  @override
  late final GeneratedColumn<String> currentPageId = GeneratedColumn<String>(
    'current_page_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wrapMeta = const VerificationMeta('wrap');
  @override
  late final GeneratedColumn<int> wrap = GeneratedColumn<int>(
    'wrap',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    folderId,
    currentRevisionId,
    currentPageId,
    createdAt,
    updatedAt,
    wrap,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    }
    if (data.containsKey('current_revision_id')) {
      context.handle(
        _currentRevisionIdMeta,
        currentRevisionId.isAcceptableOrUnknown(
          data['current_revision_id']!,
          _currentRevisionIdMeta,
        ),
      );
    }
    if (data.containsKey('current_page_id')) {
      context.handle(
        _currentPageIdMeta,
        currentPageId.isAcceptableOrUnknown(
          data['current_page_id']!,
          _currentPageIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('wrap')) {
      context.handle(
        _wrapMeta,
        wrap.isAcceptableOrUnknown(data['wrap']!, _wrapMeta),
      );
    } else if (isInserting) {
      context.missing(_wrapMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_id'],
      ),
      currentRevisionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_revision_id'],
      ),
      currentPageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_page_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      wrap: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wrap'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $NoteRowsTable createAlias(String alias) {
    return $NoteRowsTable(attachedDatabase, alias);
  }
}

class NoteRow extends DataClass implements Insertable<NoteRow> {
  final String id;
  final String title;
  final String? folderId;
  final String? currentRevisionId;
  final String? currentPageId;
  final String createdAt;
  final String updatedAt;
  final int wrap;
  final int sortOrder;
  const NoteRow({
    required this.id,
    required this.title,
    this.folderId,
    this.currentRevisionId,
    this.currentPageId,
    required this.createdAt,
    required this.updatedAt,
    required this.wrap,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || folderId != null) {
      map['folder_id'] = Variable<String>(folderId);
    }
    if (!nullToAbsent || currentRevisionId != null) {
      map['current_revision_id'] = Variable<String>(currentRevisionId);
    }
    if (!nullToAbsent || currentPageId != null) {
      map['current_page_id'] = Variable<String>(currentPageId);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    map['wrap'] = Variable<int>(wrap);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  NoteRowsCompanion toCompanion(bool nullToAbsent) {
    return NoteRowsCompanion(
      id: Value(id),
      title: Value(title),
      folderId: folderId == null && nullToAbsent
          ? const Value.absent()
          : Value(folderId),
      currentRevisionId: currentRevisionId == null && nullToAbsent
          ? const Value.absent()
          : Value(currentRevisionId),
      currentPageId: currentPageId == null && nullToAbsent
          ? const Value.absent()
          : Value(currentPageId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      wrap: Value(wrap),
      sortOrder: Value(sortOrder),
    );
  }

  factory NoteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      folderId: serializer.fromJson<String?>(json['folderId']),
      currentRevisionId: serializer.fromJson<String?>(
        json['currentRevisionId'],
      ),
      currentPageId: serializer.fromJson<String?>(json['currentPageId']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      wrap: serializer.fromJson<int>(json['wrap']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'folderId': serializer.toJson<String?>(folderId),
      'currentRevisionId': serializer.toJson<String?>(currentRevisionId),
      'currentPageId': serializer.toJson<String?>(currentPageId),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'wrap': serializer.toJson<int>(wrap),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  NoteRow copyWith({
    String? id,
    String? title,
    Value<String?> folderId = const Value.absent(),
    Value<String?> currentRevisionId = const Value.absent(),
    Value<String?> currentPageId = const Value.absent(),
    String? createdAt,
    String? updatedAt,
    int? wrap,
    int? sortOrder,
  }) => NoteRow(
    id: id ?? this.id,
    title: title ?? this.title,
    folderId: folderId.present ? folderId.value : this.folderId,
    currentRevisionId: currentRevisionId.present
        ? currentRevisionId.value
        : this.currentRevisionId,
    currentPageId: currentPageId.present
        ? currentPageId.value
        : this.currentPageId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    wrap: wrap ?? this.wrap,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  NoteRow copyWithCompanion(NoteRowsCompanion data) {
    return NoteRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      currentRevisionId: data.currentRevisionId.present
          ? data.currentRevisionId.value
          : this.currentRevisionId,
      currentPageId: data.currentPageId.present
          ? data.currentPageId.value
          : this.currentPageId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      wrap: data.wrap.present ? data.wrap.value : this.wrap,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('folderId: $folderId, ')
          ..write('currentRevisionId: $currentRevisionId, ')
          ..write('currentPageId: $currentPageId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('wrap: $wrap, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    folderId,
    currentRevisionId,
    currentPageId,
    createdAt,
    updatedAt,
    wrap,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.folderId == this.folderId &&
          other.currentRevisionId == this.currentRevisionId &&
          other.currentPageId == this.currentPageId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.wrap == this.wrap &&
          other.sortOrder == this.sortOrder);
}

class NoteRowsCompanion extends UpdateCompanion<NoteRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> folderId;
  final Value<String?> currentRevisionId;
  final Value<String?> currentPageId;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> wrap;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const NoteRowsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.folderId = const Value.absent(),
    this.currentRevisionId = const Value.absent(),
    this.currentPageId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.wrap = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteRowsCompanion.insert({
    required String id,
    required String title,
    this.folderId = const Value.absent(),
    this.currentRevisionId = const Value.absent(),
    this.currentPageId = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    required int wrap,
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       wrap = Value(wrap),
       sortOrder = Value(sortOrder);
  static Insertable<NoteRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? folderId,
    Expression<String>? currentRevisionId,
    Expression<String>? currentPageId,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? wrap,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (folderId != null) 'folder_id': folderId,
      if (currentRevisionId != null) 'current_revision_id': currentRevisionId,
      if (currentPageId != null) 'current_page_id': currentPageId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (wrap != null) 'wrap': wrap,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? folderId,
    Value<String?>? currentRevisionId,
    Value<String?>? currentPageId,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? wrap,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return NoteRowsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      folderId: folderId ?? this.folderId,
      currentRevisionId: currentRevisionId ?? this.currentRevisionId,
      currentPageId: currentPageId ?? this.currentPageId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      wrap: wrap ?? this.wrap,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<String>(folderId.value);
    }
    if (currentRevisionId.present) {
      map['current_revision_id'] = Variable<String>(currentRevisionId.value);
    }
    if (currentPageId.present) {
      map['current_page_id'] = Variable<String>(currentPageId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (wrap.present) {
      map['wrap'] = Variable<int>(wrap.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteRowsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('folderId: $folderId, ')
          ..write('currentRevisionId: $currentRevisionId, ')
          ..write('currentPageId: $currentPageId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('wrap: $wrap, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NotePageRowsTable extends NotePageRows
    with TableInfo<$NotePageRowsTable, NotePageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotePageRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentRevisionIdMeta = const VerificationMeta(
    'currentRevisionId',
  );
  @override
  late final GeneratedColumn<String> currentRevisionId =
      GeneratedColumn<String>(
        'current_revision_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    noteId,
    title,
    fileName,
    relativePath,
    currentRevisionId,
    sortOrder,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_pages';
  @override
  VerificationContext validateIntegrity(
    Insertable<NotePageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('current_revision_id')) {
      context.handle(
        _currentRevisionIdMeta,
        currentRevisionId.isAcceptableOrUnknown(
          data['current_revision_id']!,
          _currentRevisionIdMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NotePageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NotePageRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      currentRevisionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_revision_id'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $NotePageRowsTable createAlias(String alias) {
    return $NotePageRowsTable(attachedDatabase, alias);
  }
}

class NotePageRow extends DataClass implements Insertable<NotePageRow> {
  final String id;
  final String noteId;
  final String title;
  final String fileName;
  final String relativePath;
  final String? currentRevisionId;
  final int sortOrder;
  final String createdAt;
  final String updatedAt;
  const NotePageRow({
    required this.id,
    required this.noteId,
    required this.title,
    required this.fileName,
    required this.relativePath,
    this.currentRevisionId,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['note_id'] = Variable<String>(noteId);
    map['title'] = Variable<String>(title);
    map['file_name'] = Variable<String>(fileName);
    map['relative_path'] = Variable<String>(relativePath);
    if (!nullToAbsent || currentRevisionId != null) {
      map['current_revision_id'] = Variable<String>(currentRevisionId);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  NotePageRowsCompanion toCompanion(bool nullToAbsent) {
    return NotePageRowsCompanion(
      id: Value(id),
      noteId: Value(noteId),
      title: Value(title),
      fileName: Value(fileName),
      relativePath: Value(relativePath),
      currentRevisionId: currentRevisionId == null && nullToAbsent
          ? const Value.absent()
          : Value(currentRevisionId),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory NotePageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NotePageRow(
      id: serializer.fromJson<String>(json['id']),
      noteId: serializer.fromJson<String>(json['noteId']),
      title: serializer.fromJson<String>(json['title']),
      fileName: serializer.fromJson<String>(json['fileName']),
      relativePath: serializer.fromJson<String>(json['relativePath']),
      currentRevisionId: serializer.fromJson<String?>(
        json['currentRevisionId'],
      ),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'noteId': serializer.toJson<String>(noteId),
      'title': serializer.toJson<String>(title),
      'fileName': serializer.toJson<String>(fileName),
      'relativePath': serializer.toJson<String>(relativePath),
      'currentRevisionId': serializer.toJson<String?>(currentRevisionId),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  NotePageRow copyWith({
    String? id,
    String? noteId,
    String? title,
    String? fileName,
    String? relativePath,
    Value<String?> currentRevisionId = const Value.absent(),
    int? sortOrder,
    String? createdAt,
    String? updatedAt,
  }) => NotePageRow(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    title: title ?? this.title,
    fileName: fileName ?? this.fileName,
    relativePath: relativePath ?? this.relativePath,
    currentRevisionId: currentRevisionId.present
        ? currentRevisionId.value
        : this.currentRevisionId,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  NotePageRow copyWithCompanion(NotePageRowsCompanion data) {
    return NotePageRow(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      title: data.title.present ? data.title.value : this.title,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      currentRevisionId: data.currentRevisionId.present
          ? data.currentRevisionId.value
          : this.currentRevisionId,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NotePageRow(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('title: $title, ')
          ..write('fileName: $fileName, ')
          ..write('relativePath: $relativePath, ')
          ..write('currentRevisionId: $currentRevisionId, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    noteId,
    title,
    fileName,
    relativePath,
    currentRevisionId,
    sortOrder,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NotePageRow &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.title == this.title &&
          other.fileName == this.fileName &&
          other.relativePath == this.relativePath &&
          other.currentRevisionId == this.currentRevisionId &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class NotePageRowsCompanion extends UpdateCompanion<NotePageRow> {
  final Value<String> id;
  final Value<String> noteId;
  final Value<String> title;
  final Value<String> fileName;
  final Value<String> relativePath;
  final Value<String?> currentRevisionId;
  final Value<int> sortOrder;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const NotePageRowsCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.title = const Value.absent(),
    this.fileName = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.currentRevisionId = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotePageRowsCompanion.insert({
    required String id,
    required String noteId,
    required String title,
    required String fileName,
    required String relativePath,
    this.currentRevisionId = const Value.absent(),
    required int sortOrder,
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       noteId = Value(noteId),
       title = Value(title),
       fileName = Value(fileName),
       relativePath = Value(relativePath),
       sortOrder = Value(sortOrder),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<NotePageRow> custom({
    Expression<String>? id,
    Expression<String>? noteId,
    Expression<String>? title,
    Expression<String>? fileName,
    Expression<String>? relativePath,
    Expression<String>? currentRevisionId,
    Expression<int>? sortOrder,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (title != null) 'title': title,
      if (fileName != null) 'file_name': fileName,
      if (relativePath != null) 'relative_path': relativePath,
      if (currentRevisionId != null) 'current_revision_id': currentRevisionId,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotePageRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? noteId,
    Value<String>? title,
    Value<String>? fileName,
    Value<String>? relativePath,
    Value<String?>? currentRevisionId,
    Value<int>? sortOrder,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return NotePageRowsCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      title: title ?? this.title,
      fileName: fileName ?? this.fileName,
      relativePath: relativePath ?? this.relativePath,
      currentRevisionId: currentRevisionId ?? this.currentRevisionId,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (currentRevisionId.present) {
      map['current_revision_id'] = Variable<String>(currentRevisionId.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotePageRowsCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('title: $title, ')
          ..write('fileName: $fileName, ')
          ..write('relativePath: $relativePath, ')
          ..write('currentRevisionId: $currentRevisionId, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteRevisionRowsTable extends NoteRevisionRows
    with TableInfo<$NoteRevisionRowsTable, NoteRevisionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteRevisionRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageIdMeta = const VerificationMeta('pageId');
  @override
  late final GeneratedColumn<String> pageId = GeneratedColumn<String>(
    'page_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentRevisionIdMeta = const VerificationMeta(
    'parentRevisionId',
  );
  @override
  late final GeneratedColumn<String> parentRevisionId = GeneratedColumn<String>(
    'parent_revision_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _savedAtMeta = const VerificationMeta(
    'savedAt',
  );
  @override
  late final GeneratedColumn<String> savedAt = GeneratedColumn<String>(
    'saved_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deltaStartMeta = const VerificationMeta(
    'deltaStart',
  );
  @override
  late final GeneratedColumn<int> deltaStart = GeneratedColumn<int>(
    'delta_start',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedTextMeta = const VerificationMeta(
    'deletedText',
  );
  @override
  late final GeneratedColumn<String> deletedText = GeneratedColumn<String>(
    'deleted_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _insertedTextMeta = const VerificationMeta(
    'insertedText',
  );
  @override
  late final GeneratedColumn<String> insertedText = GeneratedColumn<String>(
    'inserted_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    noteId,
    pageId,
    parentRevisionId,
    savedAt,
    deltaStart,
    deletedText,
    insertedText,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteRevisionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('page_id')) {
      context.handle(
        _pageIdMeta,
        pageId.isAcceptableOrUnknown(data['page_id']!, _pageIdMeta),
      );
    }
    if (data.containsKey('parent_revision_id')) {
      context.handle(
        _parentRevisionIdMeta,
        parentRevisionId.isAcceptableOrUnknown(
          data['parent_revision_id']!,
          _parentRevisionIdMeta,
        ),
      );
    }
    if (data.containsKey('saved_at')) {
      context.handle(
        _savedAtMeta,
        savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    if (data.containsKey('delta_start')) {
      context.handle(
        _deltaStartMeta,
        deltaStart.isAcceptableOrUnknown(data['delta_start']!, _deltaStartMeta),
      );
    } else if (isInserting) {
      context.missing(_deltaStartMeta);
    }
    if (data.containsKey('deleted_text')) {
      context.handle(
        _deletedTextMeta,
        deletedText.isAcceptableOrUnknown(
          data['deleted_text']!,
          _deletedTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deletedTextMeta);
    }
    if (data.containsKey('inserted_text')) {
      context.handle(
        _insertedTextMeta,
        insertedText.isAcceptableOrUnknown(
          data['inserted_text']!,
          _insertedTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_insertedTextMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteRevisionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteRevisionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      pageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}page_id'],
      ),
      parentRevisionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_revision_id'],
      ),
      savedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}saved_at'],
      )!,
      deltaStart: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}delta_start'],
      )!,
      deletedText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_text'],
      )!,
      insertedText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}inserted_text'],
      )!,
    );
  }

  @override
  $NoteRevisionRowsTable createAlias(String alias) {
    return $NoteRevisionRowsTable(attachedDatabase, alias);
  }
}

class NoteRevisionRow extends DataClass implements Insertable<NoteRevisionRow> {
  final String id;
  final String noteId;
  final String? pageId;
  final String? parentRevisionId;
  final String savedAt;
  final int deltaStart;
  final String deletedText;
  final String insertedText;
  const NoteRevisionRow({
    required this.id,
    required this.noteId,
    this.pageId,
    this.parentRevisionId,
    required this.savedAt,
    required this.deltaStart,
    required this.deletedText,
    required this.insertedText,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['note_id'] = Variable<String>(noteId);
    if (!nullToAbsent || pageId != null) {
      map['page_id'] = Variable<String>(pageId);
    }
    if (!nullToAbsent || parentRevisionId != null) {
      map['parent_revision_id'] = Variable<String>(parentRevisionId);
    }
    map['saved_at'] = Variable<String>(savedAt);
    map['delta_start'] = Variable<int>(deltaStart);
    map['deleted_text'] = Variable<String>(deletedText);
    map['inserted_text'] = Variable<String>(insertedText);
    return map;
  }

  NoteRevisionRowsCompanion toCompanion(bool nullToAbsent) {
    return NoteRevisionRowsCompanion(
      id: Value(id),
      noteId: Value(noteId),
      pageId: pageId == null && nullToAbsent
          ? const Value.absent()
          : Value(pageId),
      parentRevisionId: parentRevisionId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentRevisionId),
      savedAt: Value(savedAt),
      deltaStart: Value(deltaStart),
      deletedText: Value(deletedText),
      insertedText: Value(insertedText),
    );
  }

  factory NoteRevisionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteRevisionRow(
      id: serializer.fromJson<String>(json['id']),
      noteId: serializer.fromJson<String>(json['noteId']),
      pageId: serializer.fromJson<String?>(json['pageId']),
      parentRevisionId: serializer.fromJson<String?>(json['parentRevisionId']),
      savedAt: serializer.fromJson<String>(json['savedAt']),
      deltaStart: serializer.fromJson<int>(json['deltaStart']),
      deletedText: serializer.fromJson<String>(json['deletedText']),
      insertedText: serializer.fromJson<String>(json['insertedText']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'noteId': serializer.toJson<String>(noteId),
      'pageId': serializer.toJson<String?>(pageId),
      'parentRevisionId': serializer.toJson<String?>(parentRevisionId),
      'savedAt': serializer.toJson<String>(savedAt),
      'deltaStart': serializer.toJson<int>(deltaStart),
      'deletedText': serializer.toJson<String>(deletedText),
      'insertedText': serializer.toJson<String>(insertedText),
    };
  }

  NoteRevisionRow copyWith({
    String? id,
    String? noteId,
    Value<String?> pageId = const Value.absent(),
    Value<String?> parentRevisionId = const Value.absent(),
    String? savedAt,
    int? deltaStart,
    String? deletedText,
    String? insertedText,
  }) => NoteRevisionRow(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    pageId: pageId.present ? pageId.value : this.pageId,
    parentRevisionId: parentRevisionId.present
        ? parentRevisionId.value
        : this.parentRevisionId,
    savedAt: savedAt ?? this.savedAt,
    deltaStart: deltaStart ?? this.deltaStart,
    deletedText: deletedText ?? this.deletedText,
    insertedText: insertedText ?? this.insertedText,
  );
  NoteRevisionRow copyWithCompanion(NoteRevisionRowsCompanion data) {
    return NoteRevisionRow(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      pageId: data.pageId.present ? data.pageId.value : this.pageId,
      parentRevisionId: data.parentRevisionId.present
          ? data.parentRevisionId.value
          : this.parentRevisionId,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
      deltaStart: data.deltaStart.present
          ? data.deltaStart.value
          : this.deltaStart,
      deletedText: data.deletedText.present
          ? data.deletedText.value
          : this.deletedText,
      insertedText: data.insertedText.present
          ? data.insertedText.value
          : this.insertedText,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteRevisionRow(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('pageId: $pageId, ')
          ..write('parentRevisionId: $parentRevisionId, ')
          ..write('savedAt: $savedAt, ')
          ..write('deltaStart: $deltaStart, ')
          ..write('deletedText: $deletedText, ')
          ..write('insertedText: $insertedText')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    noteId,
    pageId,
    parentRevisionId,
    savedAt,
    deltaStart,
    deletedText,
    insertedText,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteRevisionRow &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.pageId == this.pageId &&
          other.parentRevisionId == this.parentRevisionId &&
          other.savedAt == this.savedAt &&
          other.deltaStart == this.deltaStart &&
          other.deletedText == this.deletedText &&
          other.insertedText == this.insertedText);
}

class NoteRevisionRowsCompanion extends UpdateCompanion<NoteRevisionRow> {
  final Value<String> id;
  final Value<String> noteId;
  final Value<String?> pageId;
  final Value<String?> parentRevisionId;
  final Value<String> savedAt;
  final Value<int> deltaStart;
  final Value<String> deletedText;
  final Value<String> insertedText;
  final Value<int> rowid;
  const NoteRevisionRowsCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.pageId = const Value.absent(),
    this.parentRevisionId = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.deltaStart = const Value.absent(),
    this.deletedText = const Value.absent(),
    this.insertedText = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteRevisionRowsCompanion.insert({
    required String id,
    required String noteId,
    this.pageId = const Value.absent(),
    this.parentRevisionId = const Value.absent(),
    required String savedAt,
    required int deltaStart,
    required String deletedText,
    required String insertedText,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       noteId = Value(noteId),
       savedAt = Value(savedAt),
       deltaStart = Value(deltaStart),
       deletedText = Value(deletedText),
       insertedText = Value(insertedText);
  static Insertable<NoteRevisionRow> custom({
    Expression<String>? id,
    Expression<String>? noteId,
    Expression<String>? pageId,
    Expression<String>? parentRevisionId,
    Expression<String>? savedAt,
    Expression<int>? deltaStart,
    Expression<String>? deletedText,
    Expression<String>? insertedText,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (pageId != null) 'page_id': pageId,
      if (parentRevisionId != null) 'parent_revision_id': parentRevisionId,
      if (savedAt != null) 'saved_at': savedAt,
      if (deltaStart != null) 'delta_start': deltaStart,
      if (deletedText != null) 'deleted_text': deletedText,
      if (insertedText != null) 'inserted_text': insertedText,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteRevisionRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? noteId,
    Value<String?>? pageId,
    Value<String?>? parentRevisionId,
    Value<String>? savedAt,
    Value<int>? deltaStart,
    Value<String>? deletedText,
    Value<String>? insertedText,
    Value<int>? rowid,
  }) {
    return NoteRevisionRowsCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      pageId: pageId ?? this.pageId,
      parentRevisionId: parentRevisionId ?? this.parentRevisionId,
      savedAt: savedAt ?? this.savedAt,
      deltaStart: deltaStart ?? this.deltaStart,
      deletedText: deletedText ?? this.deletedText,
      insertedText: insertedText ?? this.insertedText,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (pageId.present) {
      map['page_id'] = Variable<String>(pageId.value);
    }
    if (parentRevisionId.present) {
      map['parent_revision_id'] = Variable<String>(parentRevisionId.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<String>(savedAt.value);
    }
    if (deltaStart.present) {
      map['delta_start'] = Variable<int>(deltaStart.value);
    }
    if (deletedText.present) {
      map['deleted_text'] = Variable<String>(deletedText.value);
    }
    if (insertedText.present) {
      map['inserted_text'] = Variable<String>(insertedText.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteRevisionRowsCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('pageId: $pageId, ')
          ..write('parentRevisionId: $parentRevisionId, ')
          ..write('savedAt: $savedAt, ')
          ..write('deltaStart: $deltaStart, ')
          ..write('deletedText: $deletedText, ')
          ..write('insertedText: $insertedText, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteEditProposalRowsTable extends NoteEditProposalRows
    with TableInfo<$NoteEditProposalRowsTable, NoteEditProposalRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteEditProposalRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageIdMeta = const VerificationMeta('pageId');
  @override
  late final GeneratedColumn<String> pageId = GeneratedColumn<String>(
    'page_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _baseRevisionIdMeta = const VerificationMeta(
    'baseRevisionId',
  );
  @override
  late final GeneratedColumn<String> baseRevisionId = GeneratedColumn<String>(
    'base_revision_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _baseContentHashMeta = const VerificationMeta(
    'baseContentHash',
  );
  @override
  late final GeneratedColumn<String> baseContentHash = GeneratedColumn<String>(
    'base_content_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    noteId,
    pageId,
    baseRevisionId,
    baseContentHash,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_edit_proposals';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteEditProposalRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('page_id')) {
      context.handle(
        _pageIdMeta,
        pageId.isAcceptableOrUnknown(data['page_id']!, _pageIdMeta),
      );
    }
    if (data.containsKey('base_revision_id')) {
      context.handle(
        _baseRevisionIdMeta,
        baseRevisionId.isAcceptableOrUnknown(
          data['base_revision_id']!,
          _baseRevisionIdMeta,
        ),
      );
    }
    if (data.containsKey('base_content_hash')) {
      context.handle(
        _baseContentHashMeta,
        baseContentHash.isAcceptableOrUnknown(
          data['base_content_hash']!,
          _baseContentHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_baseContentHashMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteEditProposalRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteEditProposalRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      pageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}page_id'],
      ),
      baseRevisionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_revision_id'],
      ),
      baseContentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_content_hash'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $NoteEditProposalRowsTable createAlias(String alias) {
    return $NoteEditProposalRowsTable(attachedDatabase, alias);
  }
}

class NoteEditProposalRow extends DataClass
    implements Insertable<NoteEditProposalRow> {
  final String id;
  final String noteId;
  final String? pageId;
  final String? baseRevisionId;
  final String baseContentHash;
  final String createdAt;
  const NoteEditProposalRow({
    required this.id,
    required this.noteId,
    this.pageId,
    this.baseRevisionId,
    required this.baseContentHash,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['note_id'] = Variable<String>(noteId);
    if (!nullToAbsent || pageId != null) {
      map['page_id'] = Variable<String>(pageId);
    }
    if (!nullToAbsent || baseRevisionId != null) {
      map['base_revision_id'] = Variable<String>(baseRevisionId);
    }
    map['base_content_hash'] = Variable<String>(baseContentHash);
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  NoteEditProposalRowsCompanion toCompanion(bool nullToAbsent) {
    return NoteEditProposalRowsCompanion(
      id: Value(id),
      noteId: Value(noteId),
      pageId: pageId == null && nullToAbsent
          ? const Value.absent()
          : Value(pageId),
      baseRevisionId: baseRevisionId == null && nullToAbsent
          ? const Value.absent()
          : Value(baseRevisionId),
      baseContentHash: Value(baseContentHash),
      createdAt: Value(createdAt),
    );
  }

  factory NoteEditProposalRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteEditProposalRow(
      id: serializer.fromJson<String>(json['id']),
      noteId: serializer.fromJson<String>(json['noteId']),
      pageId: serializer.fromJson<String?>(json['pageId']),
      baseRevisionId: serializer.fromJson<String?>(json['baseRevisionId']),
      baseContentHash: serializer.fromJson<String>(json['baseContentHash']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'noteId': serializer.toJson<String>(noteId),
      'pageId': serializer.toJson<String?>(pageId),
      'baseRevisionId': serializer.toJson<String?>(baseRevisionId),
      'baseContentHash': serializer.toJson<String>(baseContentHash),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  NoteEditProposalRow copyWith({
    String? id,
    String? noteId,
    Value<String?> pageId = const Value.absent(),
    Value<String?> baseRevisionId = const Value.absent(),
    String? baseContentHash,
    String? createdAt,
  }) => NoteEditProposalRow(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    pageId: pageId.present ? pageId.value : this.pageId,
    baseRevisionId: baseRevisionId.present
        ? baseRevisionId.value
        : this.baseRevisionId,
    baseContentHash: baseContentHash ?? this.baseContentHash,
    createdAt: createdAt ?? this.createdAt,
  );
  NoteEditProposalRow copyWithCompanion(NoteEditProposalRowsCompanion data) {
    return NoteEditProposalRow(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      pageId: data.pageId.present ? data.pageId.value : this.pageId,
      baseRevisionId: data.baseRevisionId.present
          ? data.baseRevisionId.value
          : this.baseRevisionId,
      baseContentHash: data.baseContentHash.present
          ? data.baseContentHash.value
          : this.baseContentHash,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteEditProposalRow(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('pageId: $pageId, ')
          ..write('baseRevisionId: $baseRevisionId, ')
          ..write('baseContentHash: $baseContentHash, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    noteId,
    pageId,
    baseRevisionId,
    baseContentHash,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteEditProposalRow &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.pageId == this.pageId &&
          other.baseRevisionId == this.baseRevisionId &&
          other.baseContentHash == this.baseContentHash &&
          other.createdAt == this.createdAt);
}

class NoteEditProposalRowsCompanion
    extends UpdateCompanion<NoteEditProposalRow> {
  final Value<String> id;
  final Value<String> noteId;
  final Value<String?> pageId;
  final Value<String?> baseRevisionId;
  final Value<String> baseContentHash;
  final Value<String> createdAt;
  final Value<int> rowid;
  const NoteEditProposalRowsCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.pageId = const Value.absent(),
    this.baseRevisionId = const Value.absent(),
    this.baseContentHash = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteEditProposalRowsCompanion.insert({
    required String id,
    required String noteId,
    this.pageId = const Value.absent(),
    this.baseRevisionId = const Value.absent(),
    required String baseContentHash,
    required String createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       noteId = Value(noteId),
       baseContentHash = Value(baseContentHash),
       createdAt = Value(createdAt);
  static Insertable<NoteEditProposalRow> custom({
    Expression<String>? id,
    Expression<String>? noteId,
    Expression<String>? pageId,
    Expression<String>? baseRevisionId,
    Expression<String>? baseContentHash,
    Expression<String>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (pageId != null) 'page_id': pageId,
      if (baseRevisionId != null) 'base_revision_id': baseRevisionId,
      if (baseContentHash != null) 'base_content_hash': baseContentHash,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteEditProposalRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? noteId,
    Value<String?>? pageId,
    Value<String?>? baseRevisionId,
    Value<String>? baseContentHash,
    Value<String>? createdAt,
    Value<int>? rowid,
  }) {
    return NoteEditProposalRowsCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      pageId: pageId ?? this.pageId,
      baseRevisionId: baseRevisionId ?? this.baseRevisionId,
      baseContentHash: baseContentHash ?? this.baseContentHash,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (pageId.present) {
      map['page_id'] = Variable<String>(pageId.value);
    }
    if (baseRevisionId.present) {
      map['base_revision_id'] = Variable<String>(baseRevisionId.value);
    }
    if (baseContentHash.present) {
      map['base_content_hash'] = Variable<String>(baseContentHash.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteEditProposalRowsCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('pageId: $pageId, ')
          ..write('baseRevisionId: $baseRevisionId, ')
          ..write('baseContentHash: $baseContentHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteEditBlockRowsTable extends NoteEditBlockRows
    with TableInfo<$NoteEditBlockRowsTable, NoteEditBlockRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteEditBlockRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _proposalIdMeta = const VerificationMeta(
    'proposalId',
  );
  @override
  late final GeneratedColumn<String> proposalId = GeneratedColumn<String>(
    'proposal_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startLineMeta = const VerificationMeta(
    'startLine',
  );
  @override
  late final GeneratedColumn<int> startLine = GeneratedColumn<int>(
    'start_line',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deleteCountMeta = const VerificationMeta(
    'deleteCount',
  );
  @override
  late final GeneratedColumn<int> deleteCount = GeneratedColumn<int>(
    'delete_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedLinesJsonMeta = const VerificationMeta(
    'deletedLinesJson',
  );
  @override
  late final GeneratedColumn<String> deletedLinesJson = GeneratedColumn<String>(
    'deleted_lines_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _insertLinesJsonMeta = const VerificationMeta(
    'insertLinesJson',
  );
  @override
  late final GeneratedColumn<String> insertLinesJson = GeneratedColumn<String>(
    'insert_lines_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    proposalId,
    startLine,
    deleteCount,
    deletedLinesJson,
    insertLinesJson,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_edit_blocks';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteEditBlockRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('proposal_id')) {
      context.handle(
        _proposalIdMeta,
        proposalId.isAcceptableOrUnknown(data['proposal_id']!, _proposalIdMeta),
      );
    } else if (isInserting) {
      context.missing(_proposalIdMeta);
    }
    if (data.containsKey('start_line')) {
      context.handle(
        _startLineMeta,
        startLine.isAcceptableOrUnknown(data['start_line']!, _startLineMeta),
      );
    } else if (isInserting) {
      context.missing(_startLineMeta);
    }
    if (data.containsKey('delete_count')) {
      context.handle(
        _deleteCountMeta,
        deleteCount.isAcceptableOrUnknown(
          data['delete_count']!,
          _deleteCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deleteCountMeta);
    }
    if (data.containsKey('deleted_lines_json')) {
      context.handle(
        _deletedLinesJsonMeta,
        deletedLinesJson.isAcceptableOrUnknown(
          data['deleted_lines_json']!,
          _deletedLinesJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deletedLinesJsonMeta);
    }
    if (data.containsKey('insert_lines_json')) {
      context.handle(
        _insertLinesJsonMeta,
        insertLinesJson.isAcceptableOrUnknown(
          data['insert_lines_json']!,
          _insertLinesJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_insertLinesJsonMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteEditBlockRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteEditBlockRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      proposalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}proposal_id'],
      )!,
      startLine: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_line'],
      )!,
      deleteCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}delete_count'],
      )!,
      deletedLinesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_lines_json'],
      )!,
      insertLinesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}insert_lines_json'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $NoteEditBlockRowsTable createAlias(String alias) {
    return $NoteEditBlockRowsTable(attachedDatabase, alias);
  }
}

class NoteEditBlockRow extends DataClass
    implements Insertable<NoteEditBlockRow> {
  final String id;
  final String proposalId;
  final int startLine;
  final int deleteCount;
  final String deletedLinesJson;
  final String insertLinesJson;
  final int sortOrder;
  const NoteEditBlockRow({
    required this.id,
    required this.proposalId,
    required this.startLine,
    required this.deleteCount,
    required this.deletedLinesJson,
    required this.insertLinesJson,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['proposal_id'] = Variable<String>(proposalId);
    map['start_line'] = Variable<int>(startLine);
    map['delete_count'] = Variable<int>(deleteCount);
    map['deleted_lines_json'] = Variable<String>(deletedLinesJson);
    map['insert_lines_json'] = Variable<String>(insertLinesJson);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  NoteEditBlockRowsCompanion toCompanion(bool nullToAbsent) {
    return NoteEditBlockRowsCompanion(
      id: Value(id),
      proposalId: Value(proposalId),
      startLine: Value(startLine),
      deleteCount: Value(deleteCount),
      deletedLinesJson: Value(deletedLinesJson),
      insertLinesJson: Value(insertLinesJson),
      sortOrder: Value(sortOrder),
    );
  }

  factory NoteEditBlockRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteEditBlockRow(
      id: serializer.fromJson<String>(json['id']),
      proposalId: serializer.fromJson<String>(json['proposalId']),
      startLine: serializer.fromJson<int>(json['startLine']),
      deleteCount: serializer.fromJson<int>(json['deleteCount']),
      deletedLinesJson: serializer.fromJson<String>(json['deletedLinesJson']),
      insertLinesJson: serializer.fromJson<String>(json['insertLinesJson']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'proposalId': serializer.toJson<String>(proposalId),
      'startLine': serializer.toJson<int>(startLine),
      'deleteCount': serializer.toJson<int>(deleteCount),
      'deletedLinesJson': serializer.toJson<String>(deletedLinesJson),
      'insertLinesJson': serializer.toJson<String>(insertLinesJson),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  NoteEditBlockRow copyWith({
    String? id,
    String? proposalId,
    int? startLine,
    int? deleteCount,
    String? deletedLinesJson,
    String? insertLinesJson,
    int? sortOrder,
  }) => NoteEditBlockRow(
    id: id ?? this.id,
    proposalId: proposalId ?? this.proposalId,
    startLine: startLine ?? this.startLine,
    deleteCount: deleteCount ?? this.deleteCount,
    deletedLinesJson: deletedLinesJson ?? this.deletedLinesJson,
    insertLinesJson: insertLinesJson ?? this.insertLinesJson,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  NoteEditBlockRow copyWithCompanion(NoteEditBlockRowsCompanion data) {
    return NoteEditBlockRow(
      id: data.id.present ? data.id.value : this.id,
      proposalId: data.proposalId.present
          ? data.proposalId.value
          : this.proposalId,
      startLine: data.startLine.present ? data.startLine.value : this.startLine,
      deleteCount: data.deleteCount.present
          ? data.deleteCount.value
          : this.deleteCount,
      deletedLinesJson: data.deletedLinesJson.present
          ? data.deletedLinesJson.value
          : this.deletedLinesJson,
      insertLinesJson: data.insertLinesJson.present
          ? data.insertLinesJson.value
          : this.insertLinesJson,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteEditBlockRow(')
          ..write('id: $id, ')
          ..write('proposalId: $proposalId, ')
          ..write('startLine: $startLine, ')
          ..write('deleteCount: $deleteCount, ')
          ..write('deletedLinesJson: $deletedLinesJson, ')
          ..write('insertLinesJson: $insertLinesJson, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    proposalId,
    startLine,
    deleteCount,
    deletedLinesJson,
    insertLinesJson,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteEditBlockRow &&
          other.id == this.id &&
          other.proposalId == this.proposalId &&
          other.startLine == this.startLine &&
          other.deleteCount == this.deleteCount &&
          other.deletedLinesJson == this.deletedLinesJson &&
          other.insertLinesJson == this.insertLinesJson &&
          other.sortOrder == this.sortOrder);
}

class NoteEditBlockRowsCompanion extends UpdateCompanion<NoteEditBlockRow> {
  final Value<String> id;
  final Value<String> proposalId;
  final Value<int> startLine;
  final Value<int> deleteCount;
  final Value<String> deletedLinesJson;
  final Value<String> insertLinesJson;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const NoteEditBlockRowsCompanion({
    this.id = const Value.absent(),
    this.proposalId = const Value.absent(),
    this.startLine = const Value.absent(),
    this.deleteCount = const Value.absent(),
    this.deletedLinesJson = const Value.absent(),
    this.insertLinesJson = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteEditBlockRowsCompanion.insert({
    required String id,
    required String proposalId,
    required int startLine,
    required int deleteCount,
    required String deletedLinesJson,
    required String insertLinesJson,
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       proposalId = Value(proposalId),
       startLine = Value(startLine),
       deleteCount = Value(deleteCount),
       deletedLinesJson = Value(deletedLinesJson),
       insertLinesJson = Value(insertLinesJson),
       sortOrder = Value(sortOrder);
  static Insertable<NoteEditBlockRow> custom({
    Expression<String>? id,
    Expression<String>? proposalId,
    Expression<int>? startLine,
    Expression<int>? deleteCount,
    Expression<String>? deletedLinesJson,
    Expression<String>? insertLinesJson,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (proposalId != null) 'proposal_id': proposalId,
      if (startLine != null) 'start_line': startLine,
      if (deleteCount != null) 'delete_count': deleteCount,
      if (deletedLinesJson != null) 'deleted_lines_json': deletedLinesJson,
      if (insertLinesJson != null) 'insert_lines_json': insertLinesJson,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteEditBlockRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? proposalId,
    Value<int>? startLine,
    Value<int>? deleteCount,
    Value<String>? deletedLinesJson,
    Value<String>? insertLinesJson,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return NoteEditBlockRowsCompanion(
      id: id ?? this.id,
      proposalId: proposalId ?? this.proposalId,
      startLine: startLine ?? this.startLine,
      deleteCount: deleteCount ?? this.deleteCount,
      deletedLinesJson: deletedLinesJson ?? this.deletedLinesJson,
      insertLinesJson: insertLinesJson ?? this.insertLinesJson,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (proposalId.present) {
      map['proposal_id'] = Variable<String>(proposalId.value);
    }
    if (startLine.present) {
      map['start_line'] = Variable<int>(startLine.value);
    }
    if (deleteCount.present) {
      map['delete_count'] = Variable<int>(deleteCount.value);
    }
    if (deletedLinesJson.present) {
      map['deleted_lines_json'] = Variable<String>(deletedLinesJson.value);
    }
    if (insertLinesJson.present) {
      map['insert_lines_json'] = Variable<String>(insertLinesJson.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteEditBlockRowsCompanion(')
          ..write('id: $id, ')
          ..write('proposalId: $proposalId, ')
          ..write('startLine: $startLine, ')
          ..write('deleteCount: $deleteCount, ')
          ..write('deletedLinesJson: $deletedLinesJson, ')
          ..write('insertLinesJson: $insertLinesJson, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ScheduleRowsTable extends ScheduleRows
    with TableInfo<$ScheduleRowsTable, ScheduleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScheduleRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startTimeMeta = const VerificationMeta(
    'startTime',
  );
  @override
  late final GeneratedColumn<String> startTime = GeneratedColumn<String>(
    'start_time',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endTimeMeta = const VerificationMeta(
    'endTime',
  );
  @override
  late final GeneratedColumn<String> endTime = GeneratedColumn<String>(
    'end_time',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    startTime,
    endTime,
    note,
    kind,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'schedules';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScheduleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('start_time')) {
      context.handle(
        _startTimeMeta,
        startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_startTimeMeta);
    }
    if (data.containsKey('end_time')) {
      context.handle(
        _endTimeMeta,
        endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_endTimeMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ScheduleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScheduleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      startTime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_time'],
      )!,
      endTime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_time'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
    );
  }

  @override
  $ScheduleRowsTable createAlias(String alias) {
    return $ScheduleRowsTable(attachedDatabase, alias);
  }
}

class ScheduleRow extends DataClass implements Insertable<ScheduleRow> {
  final String id;
  final String title;
  final String startTime;
  final String endTime;
  final String? note;
  final String kind;
  const ScheduleRow({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.note,
    required this.kind,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['start_time'] = Variable<String>(startTime);
    map['end_time'] = Variable<String>(endTime);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['kind'] = Variable<String>(kind);
    return map;
  }

  ScheduleRowsCompanion toCompanion(bool nullToAbsent) {
    return ScheduleRowsCompanion(
      id: Value(id),
      title: Value(title),
      startTime: Value(startTime),
      endTime: Value(endTime),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      kind: Value(kind),
    );
  }

  factory ScheduleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScheduleRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      startTime: serializer.fromJson<String>(json['startTime']),
      endTime: serializer.fromJson<String>(json['endTime']),
      note: serializer.fromJson<String?>(json['note']),
      kind: serializer.fromJson<String>(json['kind']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'startTime': serializer.toJson<String>(startTime),
      'endTime': serializer.toJson<String>(endTime),
      'note': serializer.toJson<String?>(note),
      'kind': serializer.toJson<String>(kind),
    };
  }

  ScheduleRow copyWith({
    String? id,
    String? title,
    String? startTime,
    String? endTime,
    Value<String?> note = const Value.absent(),
    String? kind,
  }) => ScheduleRow(
    id: id ?? this.id,
    title: title ?? this.title,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    note: note.present ? note.value : this.note,
    kind: kind ?? this.kind,
  );
  ScheduleRow copyWithCompanion(ScheduleRowsCompanion data) {
    return ScheduleRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      note: data.note.present ? data.note.value : this.note,
      kind: data.kind.present ? data.kind.value : this.kind,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScheduleRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('note: $note, ')
          ..write('kind: $kind')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, startTime, endTime, note, kind);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.note == this.note &&
          other.kind == this.kind);
}

class ScheduleRowsCompanion extends UpdateCompanion<ScheduleRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> startTime;
  final Value<String> endTime;
  final Value<String?> note;
  final Value<String> kind;
  final Value<int> rowid;
  const ScheduleRowsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.note = const Value.absent(),
    this.kind = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ScheduleRowsCompanion.insert({
    required String id,
    required String title,
    required String startTime,
    required String endTime,
    this.note = const Value.absent(),
    required String kind,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       startTime = Value(startTime),
       endTime = Value(endTime),
       kind = Value(kind);
  static Insertable<ScheduleRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? startTime,
    Expression<String>? endTime,
    Expression<String>? note,
    Expression<String>? kind,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (note != null) 'note': note,
      if (kind != null) 'kind': kind,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ScheduleRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? startTime,
    Value<String>? endTime,
    Value<String?>? note,
    Value<String>? kind,
    Value<int>? rowid,
  }) {
    return ScheduleRowsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      note: note ?? this.note,
      kind: kind ?? this.kind,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<String>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<String>(endTime.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScheduleRowsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('note: $note, ')
          ..write('kind: $kind, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TodoListRowsTable extends TodoListRows
    with TableInfo<$TodoListRowsTable, TodoListRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TodoListRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, title, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'todo_lists';
  @override
  VerificationContext validateIntegrity(
    Insertable<TodoListRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TodoListRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TodoListRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TodoListRowsTable createAlias(String alias) {
    return $TodoListRowsTable(attachedDatabase, alias);
  }
}

class TodoListRow extends DataClass implements Insertable<TodoListRow> {
  final String id;
  final String title;
  final String createdAt;
  final String updatedAt;
  const TodoListRow({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  TodoListRowsCompanion toCompanion(bool nullToAbsent) {
    return TodoListRowsCompanion(
      id: Value(id),
      title: Value(title),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory TodoListRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TodoListRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  TodoListRow copyWith({
    String? id,
    String? title,
    String? createdAt,
    String? updatedAt,
  }) => TodoListRow(
    id: id ?? this.id,
    title: title ?? this.title,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  TodoListRow copyWithCompanion(TodoListRowsCompanion data) {
    return TodoListRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TodoListRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TodoListRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TodoListRowsCompanion extends UpdateCompanion<TodoListRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const TodoListRowsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TodoListRowsCompanion.insert({
    required String id,
    required String title,
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<TodoListRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TodoListRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return TodoListRowsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TodoListRowsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TodoItemRowsTable extends TodoItemRows
    with TableInfo<$TodoItemRowsTable, TodoItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TodoItemRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _listIdMeta = const VerificationMeta('listId');
  @override
  late final GeneratedColumn<String> listId = GeneratedColumn<String>(
    'list_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemTextMeta = const VerificationMeta(
    'itemText',
  );
  @override
  late final GeneratedColumn<String> itemText = GeneratedColumn<String>(
    'text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _doneMeta = const VerificationMeta('done');
  @override
  late final GeneratedColumn<int> done = GeneratedColumn<int>(
    'done',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, listId, itemText, done, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'todo_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<TodoItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('list_id')) {
      context.handle(
        _listIdMeta,
        listId.isAcceptableOrUnknown(data['list_id']!, _listIdMeta),
      );
    } else if (isInserting) {
      context.missing(_listIdMeta);
    }
    if (data.containsKey('text')) {
      context.handle(
        _itemTextMeta,
        itemText.isAcceptableOrUnknown(data['text']!, _itemTextMeta),
      );
    } else if (isInserting) {
      context.missing(_itemTextMeta);
    }
    if (data.containsKey('done')) {
      context.handle(
        _doneMeta,
        done.isAcceptableOrUnknown(data['done']!, _doneMeta),
      );
    } else if (isInserting) {
      context.missing(_doneMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TodoItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TodoItemRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      listId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}list_id'],
      )!,
      itemText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text'],
      )!,
      done: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}done'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $TodoItemRowsTable createAlias(String alias) {
    return $TodoItemRowsTable(attachedDatabase, alias);
  }
}

class TodoItemRow extends DataClass implements Insertable<TodoItemRow> {
  final String id;
  final String listId;
  final String itemText;
  final int done;
  final int sortOrder;
  const TodoItemRow({
    required this.id,
    required this.listId,
    required this.itemText,
    required this.done,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['list_id'] = Variable<String>(listId);
    map['text'] = Variable<String>(itemText);
    map['done'] = Variable<int>(done);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  TodoItemRowsCompanion toCompanion(bool nullToAbsent) {
    return TodoItemRowsCompanion(
      id: Value(id),
      listId: Value(listId),
      itemText: Value(itemText),
      done: Value(done),
      sortOrder: Value(sortOrder),
    );
  }

  factory TodoItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TodoItemRow(
      id: serializer.fromJson<String>(json['id']),
      listId: serializer.fromJson<String>(json['listId']),
      itemText: serializer.fromJson<String>(json['itemText']),
      done: serializer.fromJson<int>(json['done']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'listId': serializer.toJson<String>(listId),
      'itemText': serializer.toJson<String>(itemText),
      'done': serializer.toJson<int>(done),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  TodoItemRow copyWith({
    String? id,
    String? listId,
    String? itemText,
    int? done,
    int? sortOrder,
  }) => TodoItemRow(
    id: id ?? this.id,
    listId: listId ?? this.listId,
    itemText: itemText ?? this.itemText,
    done: done ?? this.done,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  TodoItemRow copyWithCompanion(TodoItemRowsCompanion data) {
    return TodoItemRow(
      id: data.id.present ? data.id.value : this.id,
      listId: data.listId.present ? data.listId.value : this.listId,
      itemText: data.itemText.present ? data.itemText.value : this.itemText,
      done: data.done.present ? data.done.value : this.done,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TodoItemRow(')
          ..write('id: $id, ')
          ..write('listId: $listId, ')
          ..write('itemText: $itemText, ')
          ..write('done: $done, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, listId, itemText, done, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TodoItemRow &&
          other.id == this.id &&
          other.listId == this.listId &&
          other.itemText == this.itemText &&
          other.done == this.done &&
          other.sortOrder == this.sortOrder);
}

class TodoItemRowsCompanion extends UpdateCompanion<TodoItemRow> {
  final Value<String> id;
  final Value<String> listId;
  final Value<String> itemText;
  final Value<int> done;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const TodoItemRowsCompanion({
    this.id = const Value.absent(),
    this.listId = const Value.absent(),
    this.itemText = const Value.absent(),
    this.done = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TodoItemRowsCompanion.insert({
    required String id,
    required String listId,
    required String itemText,
    required int done,
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       listId = Value(listId),
       itemText = Value(itemText),
       done = Value(done),
       sortOrder = Value(sortOrder);
  static Insertable<TodoItemRow> custom({
    Expression<String>? id,
    Expression<String>? listId,
    Expression<String>? itemText,
    Expression<int>? done,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (listId != null) 'list_id': listId,
      if (itemText != null) 'text': itemText,
      if (done != null) 'done': done,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TodoItemRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? listId,
    Value<String>? itemText,
    Value<int>? done,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return TodoItemRowsCompanion(
      id: id ?? this.id,
      listId: listId ?? this.listId,
      itemText: itemText ?? this.itemText,
      done: done ?? this.done,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (listId.present) {
      map['list_id'] = Variable<String>(listId.value);
    }
    if (itemText.present) {
      map['text'] = Variable<String>(itemText.value);
    }
    if (done.present) {
      map['done'] = Variable<int>(done.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TodoItemRowsCompanion(')
          ..write('id: $id, ')
          ..write('listId: $listId, ')
          ..write('itemText: $itemText, ')
          ..write('done: $done, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RoleplayScenarioRowsTable extends RoleplayScenarioRows
    with TableInfo<$RoleplayScenarioRowsTable, RoleplayScenarioRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoleplayScenarioRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataJsonMeta = const VerificationMeta(
    'dataJson',
  );
  @override
  late final GeneratedColumn<String> dataJson = GeneratedColumn<String>(
    'data_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, dataJson, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'roleplay_scenarios';
  @override
  VerificationContext validateIntegrity(
    Insertable<RoleplayScenarioRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('data_json')) {
      context.handle(
        _dataJsonMeta,
        dataJson.isAcceptableOrUnknown(data['data_json']!, _dataJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_dataJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RoleplayScenarioRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoleplayScenarioRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      dataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RoleplayScenarioRowsTable createAlias(String alias) {
    return $RoleplayScenarioRowsTable(attachedDatabase, alias);
  }
}

class RoleplayScenarioRow extends DataClass
    implements Insertable<RoleplayScenarioRow> {
  final String id;
  final String dataJson;
  final String updatedAt;
  const RoleplayScenarioRow({
    required this.id,
    required this.dataJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['data_json'] = Variable<String>(dataJson);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  RoleplayScenarioRowsCompanion toCompanion(bool nullToAbsent) {
    return RoleplayScenarioRowsCompanion(
      id: Value(id),
      dataJson: Value(dataJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory RoleplayScenarioRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoleplayScenarioRow(
      id: serializer.fromJson<String>(json['id']),
      dataJson: serializer.fromJson<String>(json['dataJson']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'dataJson': serializer.toJson<String>(dataJson),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  RoleplayScenarioRow copyWith({
    String? id,
    String? dataJson,
    String? updatedAt,
  }) => RoleplayScenarioRow(
    id: id ?? this.id,
    dataJson: dataJson ?? this.dataJson,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RoleplayScenarioRow copyWithCompanion(RoleplayScenarioRowsCompanion data) {
    return RoleplayScenarioRow(
      id: data.id.present ? data.id.value : this.id,
      dataJson: data.dataJson.present ? data.dataJson.value : this.dataJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoleplayScenarioRow(')
          ..write('id: $id, ')
          ..write('dataJson: $dataJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, dataJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoleplayScenarioRow &&
          other.id == this.id &&
          other.dataJson == this.dataJson &&
          other.updatedAt == this.updatedAt);
}

class RoleplayScenarioRowsCompanion
    extends UpdateCompanion<RoleplayScenarioRow> {
  final Value<String> id;
  final Value<String> dataJson;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const RoleplayScenarioRowsCompanion({
    this.id = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RoleplayScenarioRowsCompanion.insert({
    required String id,
    required String dataJson,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       dataJson = Value(dataJson),
       updatedAt = Value(updatedAt);
  static Insertable<RoleplayScenarioRow> custom({
    Expression<String>? id,
    Expression<String>? dataJson,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (dataJson != null) 'data_json': dataJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RoleplayScenarioRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? dataJson,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return RoleplayScenarioRowsCompanion(
      id: id ?? this.id,
      dataJson: dataJson ?? this.dataJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (dataJson.present) {
      map['data_json'] = Variable<String>(dataJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoleplayScenarioRowsCompanion(')
          ..write('id: $id, ')
          ..write('dataJson: $dataJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RoleplayThreadRowsTable extends RoleplayThreadRows
    with TableInfo<$RoleplayThreadRowsTable, RoleplayThreadRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoleplayThreadRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataJsonMeta = const VerificationMeta(
    'dataJson',
  );
  @override
  late final GeneratedColumn<String> dataJson = GeneratedColumn<String>(
    'data_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, dataJson, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'roleplay_threads';
  @override
  VerificationContext validateIntegrity(
    Insertable<RoleplayThreadRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('data_json')) {
      context.handle(
        _dataJsonMeta,
        dataJson.isAcceptableOrUnknown(data['data_json']!, _dataJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_dataJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RoleplayThreadRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoleplayThreadRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      dataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RoleplayThreadRowsTable createAlias(String alias) {
    return $RoleplayThreadRowsTable(attachedDatabase, alias);
  }
}

class RoleplayThreadRow extends DataClass
    implements Insertable<RoleplayThreadRow> {
  final String id;
  final String dataJson;
  final String updatedAt;
  const RoleplayThreadRow({
    required this.id,
    required this.dataJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['data_json'] = Variable<String>(dataJson);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  RoleplayThreadRowsCompanion toCompanion(bool nullToAbsent) {
    return RoleplayThreadRowsCompanion(
      id: Value(id),
      dataJson: Value(dataJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory RoleplayThreadRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoleplayThreadRow(
      id: serializer.fromJson<String>(json['id']),
      dataJson: serializer.fromJson<String>(json['dataJson']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'dataJson': serializer.toJson<String>(dataJson),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  RoleplayThreadRow copyWith({
    String? id,
    String? dataJson,
    String? updatedAt,
  }) => RoleplayThreadRow(
    id: id ?? this.id,
    dataJson: dataJson ?? this.dataJson,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RoleplayThreadRow copyWithCompanion(RoleplayThreadRowsCompanion data) {
    return RoleplayThreadRow(
      id: data.id.present ? data.id.value : this.id,
      dataJson: data.dataJson.present ? data.dataJson.value : this.dataJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoleplayThreadRow(')
          ..write('id: $id, ')
          ..write('dataJson: $dataJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, dataJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoleplayThreadRow &&
          other.id == this.id &&
          other.dataJson == this.dataJson &&
          other.updatedAt == this.updatedAt);
}

class RoleplayThreadRowsCompanion extends UpdateCompanion<RoleplayThreadRow> {
  final Value<String> id;
  final Value<String> dataJson;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const RoleplayThreadRowsCompanion({
    this.id = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RoleplayThreadRowsCompanion.insert({
    required String id,
    required String dataJson,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       dataJson = Value(dataJson),
       updatedAt = Value(updatedAt);
  static Insertable<RoleplayThreadRow> custom({
    Expression<String>? id,
    Expression<String>? dataJson,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (dataJson != null) 'data_json': dataJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RoleplayThreadRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? dataJson,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return RoleplayThreadRowsCompanion(
      id: id ?? this.id,
      dataJson: dataJson ?? this.dataJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (dataJson.present) {
      map['data_json'] = Variable<String>(dataJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoleplayThreadRowsCompanion(')
          ..write('id: $id, ')
          ..write('dataJson: $dataJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecycleBinRowsTable extends RecycleBinRows
    with TableInfo<$RecycleBinRowsTable, RecycleBinRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecycleBinRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerMeta = const VerificationMeta('owner');
  @override
  late final GeneratedColumn<String> owner = GeneratedColumn<String>(
    'owner',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _previewMeta = const VerificationMeta(
    'preview',
  );
  @override
  late final GeneratedColumn<String> preview = GeneratedColumn<String>(
    'preview',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
    'deleted_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    owner,
    category,
    type,
    title,
    preview,
    payloadJson,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recycle_bin';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecycleBinRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner')) {
      context.handle(
        _ownerMeta,
        owner.isAcceptableOrUnknown(data['owner']!, _ownerMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('preview')) {
      context.handle(
        _previewMeta,
        preview.isAcceptableOrUnknown(data['preview']!, _previewMeta),
      );
    } else if (isInserting) {
      context.missing(_previewMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_deletedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecycleBinRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecycleBinRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      owner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      preview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preview'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_at'],
      )!,
    );
  }

  @override
  $RecycleBinRowsTable createAlias(String alias) {
    return $RecycleBinRowsTable(attachedDatabase, alias);
  }
}

class RecycleBinRow extends DataClass implements Insertable<RecycleBinRow> {
  final String id;
  final String owner;
  final String category;
  final String type;
  final String title;
  final String preview;
  final String payloadJson;
  final String deletedAt;
  const RecycleBinRow({
    required this.id,
    required this.owner,
    required this.category,
    required this.type,
    required this.title,
    required this.preview,
    required this.payloadJson,
    required this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner'] = Variable<String>(owner);
    map['category'] = Variable<String>(category);
    map['type'] = Variable<String>(type);
    map['title'] = Variable<String>(title);
    map['preview'] = Variable<String>(preview);
    map['payload_json'] = Variable<String>(payloadJson);
    map['deleted_at'] = Variable<String>(deletedAt);
    return map;
  }

  RecycleBinRowsCompanion toCompanion(bool nullToAbsent) {
    return RecycleBinRowsCompanion(
      id: Value(id),
      owner: Value(owner),
      category: Value(category),
      type: Value(type),
      title: Value(title),
      preview: Value(preview),
      payloadJson: Value(payloadJson),
      deletedAt: Value(deletedAt),
    );
  }

  factory RecycleBinRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecycleBinRow(
      id: serializer.fromJson<String>(json['id']),
      owner: serializer.fromJson<String>(json['owner']),
      category: serializer.fromJson<String>(json['category']),
      type: serializer.fromJson<String>(json['type']),
      title: serializer.fromJson<String>(json['title']),
      preview: serializer.fromJson<String>(json['preview']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      deletedAt: serializer.fromJson<String>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'owner': serializer.toJson<String>(owner),
      'category': serializer.toJson<String>(category),
      'type': serializer.toJson<String>(type),
      'title': serializer.toJson<String>(title),
      'preview': serializer.toJson<String>(preview),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'deletedAt': serializer.toJson<String>(deletedAt),
    };
  }

  RecycleBinRow copyWith({
    String? id,
    String? owner,
    String? category,
    String? type,
    String? title,
    String? preview,
    String? payloadJson,
    String? deletedAt,
  }) => RecycleBinRow(
    id: id ?? this.id,
    owner: owner ?? this.owner,
    category: category ?? this.category,
    type: type ?? this.type,
    title: title ?? this.title,
    preview: preview ?? this.preview,
    payloadJson: payloadJson ?? this.payloadJson,
    deletedAt: deletedAt ?? this.deletedAt,
  );
  RecycleBinRow copyWithCompanion(RecycleBinRowsCompanion data) {
    return RecycleBinRow(
      id: data.id.present ? data.id.value : this.id,
      owner: data.owner.present ? data.owner.value : this.owner,
      category: data.category.present ? data.category.value : this.category,
      type: data.type.present ? data.type.value : this.type,
      title: data.title.present ? data.title.value : this.title,
      preview: data.preview.present ? data.preview.value : this.preview,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecycleBinRow(')
          ..write('id: $id, ')
          ..write('owner: $owner, ')
          ..write('category: $category, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('preview: $preview, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    owner,
    category,
    type,
    title,
    preview,
    payloadJson,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecycleBinRow &&
          other.id == this.id &&
          other.owner == this.owner &&
          other.category == this.category &&
          other.type == this.type &&
          other.title == this.title &&
          other.preview == this.preview &&
          other.payloadJson == this.payloadJson &&
          other.deletedAt == this.deletedAt);
}

class RecycleBinRowsCompanion extends UpdateCompanion<RecycleBinRow> {
  final Value<String> id;
  final Value<String> owner;
  final Value<String> category;
  final Value<String> type;
  final Value<String> title;
  final Value<String> preview;
  final Value<String> payloadJson;
  final Value<String> deletedAt;
  final Value<int> rowid;
  const RecycleBinRowsCompanion({
    this.id = const Value.absent(),
    this.owner = const Value.absent(),
    this.category = const Value.absent(),
    this.type = const Value.absent(),
    this.title = const Value.absent(),
    this.preview = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecycleBinRowsCompanion.insert({
    required String id,
    required String owner,
    required String category,
    required String type,
    required String title,
    required String preview,
    required String payloadJson,
    required String deletedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       owner = Value(owner),
       category = Value(category),
       type = Value(type),
       title = Value(title),
       preview = Value(preview),
       payloadJson = Value(payloadJson),
       deletedAt = Value(deletedAt);
  static Insertable<RecycleBinRow> custom({
    Expression<String>? id,
    Expression<String>? owner,
    Expression<String>? category,
    Expression<String>? type,
    Expression<String>? title,
    Expression<String>? preview,
    Expression<String>? payloadJson,
    Expression<String>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (owner != null) 'owner': owner,
      if (category != null) 'category': category,
      if (type != null) 'type': type,
      if (title != null) 'title': title,
      if (preview != null) 'preview': preview,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecycleBinRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? owner,
    Value<String>? category,
    Value<String>? type,
    Value<String>? title,
    Value<String>? preview,
    Value<String>? payloadJson,
    Value<String>? deletedAt,
    Value<int>? rowid,
  }) {
    return RecycleBinRowsCompanion(
      id: id ?? this.id,
      owner: owner ?? this.owner,
      category: category ?? this.category,
      type: type ?? this.type,
      title: title ?? this.title,
      preview: preview ?? this.preview,
      payloadJson: payloadJson ?? this.payloadJson,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (owner.present) {
      map['owner'] = Variable<String>(owner.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (preview.present) {
      map['preview'] = Variable<String>(preview.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecycleBinRowsCompanion(')
          ..write('id: $id, ')
          ..write('owner: $owner, ')
          ..write('category: $category, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('preview: $preview, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$StorageV2DriftDatabase extends GeneratedDatabase {
  _$StorageV2DriftDatabase(QueryExecutor e) : super(e);
  $StorageV2DriftDatabaseManager get managers =>
      $StorageV2DriftDatabaseManager(this);
  late final $StorageMetaTable storageMeta = $StorageMetaTable(this);
  late final $AppSettingsRowsTable appSettingsRows = $AppSettingsRowsTable(
    this,
  );
  late final $ModelConfigRowsTable modelConfigRows = $ModelConfigRowsTable(
    this,
  );
  late final $ResourceRowsTable resourceRows = $ResourceRowsTable(this);
  late final $ConversationRowsTable conversationRows = $ConversationRowsTable(
    this,
  );
  late final $MessageRowsTable messageRows = $MessageRowsTable(this);
  late final $MessageAttachmentRowsTable messageAttachmentRows =
      $MessageAttachmentRowsTable(this);
  late final $NoteFolderRowsTable noteFolderRows = $NoteFolderRowsTable(this);
  late final $NoteRowsTable noteRows = $NoteRowsTable(this);
  late final $NotePageRowsTable notePageRows = $NotePageRowsTable(this);
  late final $NoteRevisionRowsTable noteRevisionRows = $NoteRevisionRowsTable(
    this,
  );
  late final $NoteEditProposalRowsTable noteEditProposalRows =
      $NoteEditProposalRowsTable(this);
  late final $NoteEditBlockRowsTable noteEditBlockRows =
      $NoteEditBlockRowsTable(this);
  late final $ScheduleRowsTable scheduleRows = $ScheduleRowsTable(this);
  late final $TodoListRowsTable todoListRows = $TodoListRowsTable(this);
  late final $TodoItemRowsTable todoItemRows = $TodoItemRowsTable(this);
  late final $RoleplayScenarioRowsTable roleplayScenarioRows =
      $RoleplayScenarioRowsTable(this);
  late final $RoleplayThreadRowsTable roleplayThreadRows =
      $RoleplayThreadRowsTable(this);
  late final $RecycleBinRowsTable recycleBinRows = $RecycleBinRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    storageMeta,
    appSettingsRows,
    modelConfigRows,
    resourceRows,
    conversationRows,
    messageRows,
    messageAttachmentRows,
    noteFolderRows,
    noteRows,
    notePageRows,
    noteRevisionRows,
    noteEditProposalRows,
    noteEditBlockRows,
    scheduleRows,
    todoListRows,
    todoItemRows,
    roleplayScenarioRows,
    roleplayThreadRows,
    recycleBinRows,
  ];
}

typedef $$StorageMetaTableCreateCompanionBuilder =
    StorageMetaCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$StorageMetaTableUpdateCompanionBuilder =
    StorageMetaCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$StorageMetaTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $StorageMetaTable> {
  $$StorageMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StorageMetaTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $StorageMetaTable> {
  $$StorageMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StorageMetaTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $StorageMetaTable> {
  $$StorageMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$StorageMetaTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $StorageMetaTable,
          StorageMetaData,
          $$StorageMetaTableFilterComposer,
          $$StorageMetaTableOrderingComposer,
          $$StorageMetaTableAnnotationComposer,
          $$StorageMetaTableCreateCompanionBuilder,
          $$StorageMetaTableUpdateCompanionBuilder,
          (
            StorageMetaData,
            BaseReferences<
              _$StorageV2DriftDatabase,
              $StorageMetaTable,
              StorageMetaData
            >,
          ),
          StorageMetaData,
          PrefetchHooks Function()
        > {
  $$StorageMetaTableTableManager(
    _$StorageV2DriftDatabase db,
    $StorageMetaTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StorageMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StorageMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StorageMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StorageMetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => StorageMetaCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StorageMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $StorageMetaTable,
      StorageMetaData,
      $$StorageMetaTableFilterComposer,
      $$StorageMetaTableOrderingComposer,
      $$StorageMetaTableAnnotationComposer,
      $$StorageMetaTableCreateCompanionBuilder,
      $$StorageMetaTableUpdateCompanionBuilder,
      (
        StorageMetaData,
        BaseReferences<
          _$StorageV2DriftDatabase,
          $StorageMetaTable,
          StorageMetaData
        >,
      ),
      StorageMetaData,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsRowsTableCreateCompanionBuilder =
    AppSettingsRowsCompanion Function({
      Value<int> id,
      required String settingsJson,
      required String updatedAt,
    });
typedef $$AppSettingsRowsTableUpdateCompanionBuilder =
    AppSettingsRowsCompanion Function({
      Value<int> id,
      Value<String> settingsJson,
      Value<String> updatedAt,
    });

class $$AppSettingsRowsTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $AppSettingsRowsTable> {
  $$AppSettingsRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get settingsJson => $composableBuilder(
    column: $table.settingsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsRowsTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $AppSettingsRowsTable> {
  $$AppSettingsRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get settingsJson => $composableBuilder(
    column: $table.settingsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsRowsTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $AppSettingsRowsTable> {
  $$AppSettingsRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get settingsJson => $composableBuilder(
    column: $table.settingsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppSettingsRowsTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $AppSettingsRowsTable,
          AppSettingsRow,
          $$AppSettingsRowsTableFilterComposer,
          $$AppSettingsRowsTableOrderingComposer,
          $$AppSettingsRowsTableAnnotationComposer,
          $$AppSettingsRowsTableCreateCompanionBuilder,
          $$AppSettingsRowsTableUpdateCompanionBuilder,
          (
            AppSettingsRow,
            BaseReferences<
              _$StorageV2DriftDatabase,
              $AppSettingsRowsTable,
              AppSettingsRow
            >,
          ),
          AppSettingsRow,
          PrefetchHooks Function()
        > {
  $$AppSettingsRowsTableTableManager(
    _$StorageV2DriftDatabase db,
    $AppSettingsRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> settingsJson = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
              }) => AppSettingsRowsCompanion(
                id: id,
                settingsJson: settingsJson,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String settingsJson,
                required String updatedAt,
              }) => AppSettingsRowsCompanion.insert(
                id: id,
                settingsJson: settingsJson,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $AppSettingsRowsTable,
      AppSettingsRow,
      $$AppSettingsRowsTableFilterComposer,
      $$AppSettingsRowsTableOrderingComposer,
      $$AppSettingsRowsTableAnnotationComposer,
      $$AppSettingsRowsTableCreateCompanionBuilder,
      $$AppSettingsRowsTableUpdateCompanionBuilder,
      (
        AppSettingsRow,
        BaseReferences<
          _$StorageV2DriftDatabase,
          $AppSettingsRowsTable,
          AppSettingsRow
        >,
      ),
      AppSettingsRow,
      PrefetchHooks Function()
    >;
typedef $$ModelConfigRowsTableCreateCompanionBuilder =
    ModelConfigRowsCompanion Function({
      required String id,
      required String configJson,
      required String category,
      required int enabled,
      required int priority,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$ModelConfigRowsTableUpdateCompanionBuilder =
    ModelConfigRowsCompanion Function({
      Value<String> id,
      Value<String> configJson,
      Value<String> category,
      Value<int> enabled,
      Value<int> priority,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$ModelConfigRowsTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $ModelConfigRowsTable> {
  $$ModelConfigRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ModelConfigRowsTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $ModelConfigRowsTable> {
  $$ModelConfigRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ModelConfigRowsTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $ModelConfigRowsTable> {
  $$ModelConfigRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<int> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ModelConfigRowsTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $ModelConfigRowsTable,
          ModelConfigRow,
          $$ModelConfigRowsTableFilterComposer,
          $$ModelConfigRowsTableOrderingComposer,
          $$ModelConfigRowsTableAnnotationComposer,
          $$ModelConfigRowsTableCreateCompanionBuilder,
          $$ModelConfigRowsTableUpdateCompanionBuilder,
          (
            ModelConfigRow,
            BaseReferences<
              _$StorageV2DriftDatabase,
              $ModelConfigRowsTable,
              ModelConfigRow
            >,
          ),
          ModelConfigRow,
          PrefetchHooks Function()
        > {
  $$ModelConfigRowsTableTableManager(
    _$StorageV2DriftDatabase db,
    $ModelConfigRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ModelConfigRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ModelConfigRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ModelConfigRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> configJson = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<int> enabled = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ModelConfigRowsCompanion(
                id: id,
                configJson: configJson,
                category: category,
                enabled: enabled,
                priority: priority,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String configJson,
                required String category,
                required int enabled,
                required int priority,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ModelConfigRowsCompanion.insert(
                id: id,
                configJson: configJson,
                category: category,
                enabled: enabled,
                priority: priority,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ModelConfigRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $ModelConfigRowsTable,
      ModelConfigRow,
      $$ModelConfigRowsTableFilterComposer,
      $$ModelConfigRowsTableOrderingComposer,
      $$ModelConfigRowsTableAnnotationComposer,
      $$ModelConfigRowsTableCreateCompanionBuilder,
      $$ModelConfigRowsTableUpdateCompanionBuilder,
      (
        ModelConfigRow,
        BaseReferences<
          _$StorageV2DriftDatabase,
          $ModelConfigRowsTable,
          ModelConfigRow
        >,
      ),
      ModelConfigRow,
      PrefetchHooks Function()
    >;
typedef $$ResourceRowsTableCreateCompanionBuilder =
    ResourceRowsCompanion Function({
      required String id,
      required String kind,
      required String role,
      required String originalPath,
      required String originalName,
      Value<String?> relativePath,
      required String mimeType,
      required int size,
      Value<String?> sha256,
      required int missing,
      required String createdAt,
      Value<int> rowid,
    });
typedef $$ResourceRowsTableUpdateCompanionBuilder =
    ResourceRowsCompanion Function({
      Value<String> id,
      Value<String> kind,
      Value<String> role,
      Value<String> originalPath,
      Value<String> originalName,
      Value<String?> relativePath,
      Value<String> mimeType,
      Value<int> size,
      Value<String?> sha256,
      Value<int> missing,
      Value<String> createdAt,
      Value<int> rowid,
    });

class $$ResourceRowsTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $ResourceRowsTable> {
  $$ResourceRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalPath => $composableBuilder(
    column: $table.originalPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalName => $composableBuilder(
    column: $table.originalName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get missing => $composableBuilder(
    column: $table.missing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ResourceRowsTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $ResourceRowsTable> {
  $$ResourceRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalPath => $composableBuilder(
    column: $table.originalPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalName => $composableBuilder(
    column: $table.originalName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get missing => $composableBuilder(
    column: $table.missing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ResourceRowsTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $ResourceRowsTable> {
  $$ResourceRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get originalPath => $composableBuilder(
    column: $table.originalPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originalName => $composableBuilder(
    column: $table.originalName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<int> get missing =>
      $composableBuilder(column: $table.missing, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ResourceRowsTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $ResourceRowsTable,
          ResourceRow,
          $$ResourceRowsTableFilterComposer,
          $$ResourceRowsTableOrderingComposer,
          $$ResourceRowsTableAnnotationComposer,
          $$ResourceRowsTableCreateCompanionBuilder,
          $$ResourceRowsTableUpdateCompanionBuilder,
          (
            ResourceRow,
            BaseReferences<
              _$StorageV2DriftDatabase,
              $ResourceRowsTable,
              ResourceRow
            >,
          ),
          ResourceRow,
          PrefetchHooks Function()
        > {
  $$ResourceRowsTableTableManager(
    _$StorageV2DriftDatabase db,
    $ResourceRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ResourceRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ResourceRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ResourceRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> originalPath = const Value.absent(),
                Value<String> originalName = const Value.absent(),
                Value<String?> relativePath = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<int> missing = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ResourceRowsCompanion(
                id: id,
                kind: kind,
                role: role,
                originalPath: originalPath,
                originalName: originalName,
                relativePath: relativePath,
                mimeType: mimeType,
                size: size,
                sha256: sha256,
                missing: missing,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String kind,
                required String role,
                required String originalPath,
                required String originalName,
                Value<String?> relativePath = const Value.absent(),
                required String mimeType,
                required int size,
                Value<String?> sha256 = const Value.absent(),
                required int missing,
                required String createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ResourceRowsCompanion.insert(
                id: id,
                kind: kind,
                role: role,
                originalPath: originalPath,
                originalName: originalName,
                relativePath: relativePath,
                mimeType: mimeType,
                size: size,
                sha256: sha256,
                missing: missing,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ResourceRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $ResourceRowsTable,
      ResourceRow,
      $$ResourceRowsTableFilterComposer,
      $$ResourceRowsTableOrderingComposer,
      $$ResourceRowsTableAnnotationComposer,
      $$ResourceRowsTableCreateCompanionBuilder,
      $$ResourceRowsTableUpdateCompanionBuilder,
      (
        ResourceRow,
        BaseReferences<
          _$StorageV2DriftDatabase,
          $ResourceRowsTable,
          ResourceRow
        >,
      ),
      ResourceRow,
      PrefetchHooks Function()
    >;
typedef $$ConversationRowsTableCreateCompanionBuilder =
    ConversationRowsCompanion Function({
      required String id,
      required String title,
      required String modelId,
      required String settingsJson,
      Value<String?> agentPlanJson,
      Value<String?> agentWorkingMemoryJson,
      required String roleId,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$ConversationRowsTableUpdateCompanionBuilder =
    ConversationRowsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> modelId,
      Value<String> settingsJson,
      Value<String?> agentPlanJson,
      Value<String?> agentWorkingMemoryJson,
      Value<String> roleId,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$ConversationRowsTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $ConversationRowsTable> {
  $$ConversationRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get settingsJson => $composableBuilder(
    column: $table.settingsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentPlanJson => $composableBuilder(
    column: $table.agentPlanJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentWorkingMemoryJson => $composableBuilder(
    column: $table.agentWorkingMemoryJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roleId => $composableBuilder(
    column: $table.roleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConversationRowsTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $ConversationRowsTable> {
  $$ConversationRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get settingsJson => $composableBuilder(
    column: $table.settingsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentPlanJson => $composableBuilder(
    column: $table.agentPlanJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentWorkingMemoryJson => $composableBuilder(
    column: $table.agentWorkingMemoryJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roleId => $composableBuilder(
    column: $table.roleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConversationRowsTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $ConversationRowsTable> {
  $$ConversationRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get modelId =>
      $composableBuilder(column: $table.modelId, builder: (column) => column);

  GeneratedColumn<String> get settingsJson => $composableBuilder(
    column: $table.settingsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get agentPlanJson => $composableBuilder(
    column: $table.agentPlanJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get agentWorkingMemoryJson => $composableBuilder(
    column: $table.agentWorkingMemoryJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get roleId =>
      $composableBuilder(column: $table.roleId, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ConversationRowsTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $ConversationRowsTable,
          ConversationRow,
          $$ConversationRowsTableFilterComposer,
          $$ConversationRowsTableOrderingComposer,
          $$ConversationRowsTableAnnotationComposer,
          $$ConversationRowsTableCreateCompanionBuilder,
          $$ConversationRowsTableUpdateCompanionBuilder,
          (
            ConversationRow,
            BaseReferences<
              _$StorageV2DriftDatabase,
              $ConversationRowsTable,
              ConversationRow
            >,
          ),
          ConversationRow,
          PrefetchHooks Function()
        > {
  $$ConversationRowsTableTableManager(
    _$StorageV2DriftDatabase db,
    $ConversationRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> modelId = const Value.absent(),
                Value<String> settingsJson = const Value.absent(),
                Value<String?> agentPlanJson = const Value.absent(),
                Value<String?> agentWorkingMemoryJson = const Value.absent(),
                Value<String> roleId = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationRowsCompanion(
                id: id,
                title: title,
                modelId: modelId,
                settingsJson: settingsJson,
                agentPlanJson: agentPlanJson,
                agentWorkingMemoryJson: agentWorkingMemoryJson,
                roleId: roleId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String modelId,
                required String settingsJson,
                Value<String?> agentPlanJson = const Value.absent(),
                Value<String?> agentWorkingMemoryJson = const Value.absent(),
                required String roleId,
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ConversationRowsCompanion.insert(
                id: id,
                title: title,
                modelId: modelId,
                settingsJson: settingsJson,
                agentPlanJson: agentPlanJson,
                agentWorkingMemoryJson: agentWorkingMemoryJson,
                roleId: roleId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConversationRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $ConversationRowsTable,
      ConversationRow,
      $$ConversationRowsTableFilterComposer,
      $$ConversationRowsTableOrderingComposer,
      $$ConversationRowsTableAnnotationComposer,
      $$ConversationRowsTableCreateCompanionBuilder,
      $$ConversationRowsTableUpdateCompanionBuilder,
      (
        ConversationRow,
        BaseReferences<
          _$StorageV2DriftDatabase,
          $ConversationRowsTable,
          ConversationRow
        >,
      ),
      ConversationRow,
      PrefetchHooks Function()
    >;
typedef $$MessageRowsTableCreateCompanionBuilder =
    MessageRowsCompanion Function({
      required String id,
      required String conversationId,
      required String role,
      required String content,
      Value<String?> thinkingContent,
      Value<String?> agentTraceJson,
      required String timestamp,
      Value<int> sortOrder,
      Value<int> rowid,
    });
typedef $$MessageRowsTableUpdateCompanionBuilder =
    MessageRowsCompanion Function({
      Value<String> id,
      Value<String> conversationId,
      Value<String> role,
      Value<String> content,
      Value<String?> thinkingContent,
      Value<String?> agentTraceJson,
      Value<String> timestamp,
      Value<int> sortOrder,
      Value<int> rowid,
    });

class $$MessageRowsTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $MessageRowsTable> {
  $$MessageRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thinkingContent => $composableBuilder(
    column: $table.thinkingContent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentTraceJson => $composableBuilder(
    column: $table.agentTraceJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessageRowsTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $MessageRowsTable> {
  $$MessageRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thinkingContent => $composableBuilder(
    column: $table.thinkingContent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentTraceJson => $composableBuilder(
    column: $table.agentTraceJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessageRowsTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $MessageRowsTable> {
  $$MessageRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get thinkingContent => $composableBuilder(
    column: $table.thinkingContent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get agentTraceJson => $composableBuilder(
    column: $table.agentTraceJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$MessageRowsTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $MessageRowsTable,
          MessageRow,
          $$MessageRowsTableFilterComposer,
          $$MessageRowsTableOrderingComposer,
          $$MessageRowsTableAnnotationComposer,
          $$MessageRowsTableCreateCompanionBuilder,
          $$MessageRowsTableUpdateCompanionBuilder,
          (
            MessageRow,
            BaseReferences<
              _$StorageV2DriftDatabase,
              $MessageRowsTable,
              MessageRow
            >,
          ),
          MessageRow,
          PrefetchHooks Function()
        > {
  $$MessageRowsTableTableManager(
    _$StorageV2DriftDatabase db,
    $MessageRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessageRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessageRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessageRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String?> thinkingContent = const Value.absent(),
                Value<String?> agentTraceJson = const Value.absent(),
                Value<String> timestamp = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageRowsCompanion(
                id: id,
                conversationId: conversationId,
                role: role,
                content: content,
                thinkingContent: thinkingContent,
                agentTraceJson: agentTraceJson,
                timestamp: timestamp,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String conversationId,
                required String role,
                required String content,
                Value<String?> thinkingContent = const Value.absent(),
                Value<String?> agentTraceJson = const Value.absent(),
                required String timestamp,
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageRowsCompanion.insert(
                id: id,
                conversationId: conversationId,
                role: role,
                content: content,
                thinkingContent: thinkingContent,
                agentTraceJson: agentTraceJson,
                timestamp: timestamp,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MessageRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $MessageRowsTable,
      MessageRow,
      $$MessageRowsTableFilterComposer,
      $$MessageRowsTableOrderingComposer,
      $$MessageRowsTableAnnotationComposer,
      $$MessageRowsTableCreateCompanionBuilder,
      $$MessageRowsTableUpdateCompanionBuilder,
      (
        MessageRow,
        BaseReferences<_$StorageV2DriftDatabase, $MessageRowsTable, MessageRow>,
      ),
      MessageRow,
      PrefetchHooks Function()
    >;
typedef $$MessageAttachmentRowsTableCreateCompanionBuilder =
    MessageAttachmentRowsCompanion Function({
      required String id,
      required String messageId,
      Value<String?> resourceId,
      required String displayName,
      required String mimeType,
      required int size,
      Value<int> sortOrder,
      Value<String?> legacyPath,
      Value<int> rowid,
    });
typedef $$MessageAttachmentRowsTableUpdateCompanionBuilder =
    MessageAttachmentRowsCompanion Function({
      Value<String> id,
      Value<String> messageId,
      Value<String?> resourceId,
      Value<String> displayName,
      Value<String> mimeType,
      Value<int> size,
      Value<int> sortOrder,
      Value<String?> legacyPath,
      Value<int> rowid,
    });

class $$MessageAttachmentRowsTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $MessageAttachmentRowsTable> {
  $$MessageAttachmentRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resourceId => $composableBuilder(
    column: $table.resourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get legacyPath => $composableBuilder(
    column: $table.legacyPath,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessageAttachmentRowsTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $MessageAttachmentRowsTable> {
  $$MessageAttachmentRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resourceId => $composableBuilder(
    column: $table.resourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get legacyPath => $composableBuilder(
    column: $table.legacyPath,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessageAttachmentRowsTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $MessageAttachmentRowsTable> {
  $$MessageAttachmentRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get resourceId => $composableBuilder(
    column: $table.resourceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get legacyPath => $composableBuilder(
    column: $table.legacyPath,
    builder: (column) => column,
  );
}

class $$MessageAttachmentRowsTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $MessageAttachmentRowsTable,
          MessageAttachmentRow,
          $$MessageAttachmentRowsTableFilterComposer,
          $$MessageAttachmentRowsTableOrderingComposer,
          $$MessageAttachmentRowsTableAnnotationComposer,
          $$MessageAttachmentRowsTableCreateCompanionBuilder,
          $$MessageAttachmentRowsTableUpdateCompanionBuilder,
          (
            MessageAttachmentRow,
            BaseReferences<
              _$StorageV2DriftDatabase,
              $MessageAttachmentRowsTable,
              MessageAttachmentRow
            >,
          ),
          MessageAttachmentRow,
          PrefetchHooks Function()
        > {
  $$MessageAttachmentRowsTableTableManager(
    _$StorageV2DriftDatabase db,
    $MessageAttachmentRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessageAttachmentRowsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$MessageAttachmentRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$MessageAttachmentRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String?> resourceId = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String?> legacyPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageAttachmentRowsCompanion(
                id: id,
                messageId: messageId,
                resourceId: resourceId,
                displayName: displayName,
                mimeType: mimeType,
                size: size,
                sortOrder: sortOrder,
                legacyPath: legacyPath,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String messageId,
                Value<String?> resourceId = const Value.absent(),
                required String displayName,
                required String mimeType,
                required int size,
                Value<int> sortOrder = const Value.absent(),
                Value<String?> legacyPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageAttachmentRowsCompanion.insert(
                id: id,
                messageId: messageId,
                resourceId: resourceId,
                displayName: displayName,
                mimeType: mimeType,
                size: size,
                sortOrder: sortOrder,
                legacyPath: legacyPath,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MessageAttachmentRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $MessageAttachmentRowsTable,
      MessageAttachmentRow,
      $$MessageAttachmentRowsTableFilterComposer,
      $$MessageAttachmentRowsTableOrderingComposer,
      $$MessageAttachmentRowsTableAnnotationComposer,
      $$MessageAttachmentRowsTableCreateCompanionBuilder,
      $$MessageAttachmentRowsTableUpdateCompanionBuilder,
      (
        MessageAttachmentRow,
        BaseReferences<
          _$StorageV2DriftDatabase,
          $MessageAttachmentRowsTable,
          MessageAttachmentRow
        >,
      ),
      MessageAttachmentRow,
      PrefetchHooks Function()
    >;
typedef $$NoteFolderRowsTableCreateCompanionBuilder =
    NoteFolderRowsCompanion Function({
      required String id,
      required String title,
      required String createdAt,
      required String updatedAt,
      required int sortOrder,
      Value<int> rowid,
    });
typedef $$NoteFolderRowsTableUpdateCompanionBuilder =
    NoteFolderRowsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> sortOrder,
      Value<int> rowid,
    });

class $$NoteFolderRowsTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $NoteFolderRowsTable> {
  $$NoteFolderRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NoteFolderRowsTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $NoteFolderRowsTable> {
  $$NoteFolderRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteFolderRowsTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $NoteFolderRowsTable> {
  $$NoteFolderRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$NoteFolderRowsTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $NoteFolderRowsTable,
          NoteFolderRow,
          $$NoteFolderRowsTableFilterComposer,
          $$NoteFolderRowsTableOrderingComposer,
          $$NoteFolderRowsTableAnnotationComposer,
          $$NoteFolderRowsTableCreateCompanionBuilder,
          $$NoteFolderRowsTableUpdateCompanionBuilder,
          (
            NoteFolderRow,
            BaseReferences<
              _$StorageV2DriftDatabase,
              $NoteFolderRowsTable,
              NoteFolderRow
            >,
          ),
          NoteFolderRow,
          PrefetchHooks Function()
        > {
  $$NoteFolderRowsTableTableManager(
    _$StorageV2DriftDatabase db,
    $NoteFolderRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteFolderRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteFolderRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteFolderRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteFolderRowsCompanion(
                id: id,
                title: title,
                createdAt: createdAt,
                updatedAt: updatedAt,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String createdAt,
                required String updatedAt,
                required int sortOrder,
                Value<int> rowid = const Value.absent(),
              }) => NoteFolderRowsCompanion.insert(
                id: id,
                title: title,
                createdAt: createdAt,
                updatedAt: updatedAt,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NoteFolderRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $NoteFolderRowsTable,
      NoteFolderRow,
      $$NoteFolderRowsTableFilterComposer,
      $$NoteFolderRowsTableOrderingComposer,
      $$NoteFolderRowsTableAnnotationComposer,
      $$NoteFolderRowsTableCreateCompanionBuilder,
      $$NoteFolderRowsTableUpdateCompanionBuilder,
      (
        NoteFolderRow,
        BaseReferences<
          _$StorageV2DriftDatabase,
          $NoteFolderRowsTable,
          NoteFolderRow
        >,
      ),
      NoteFolderRow,
      PrefetchHooks Function()
    >;
typedef $$NoteRowsTableCreateCompanionBuilder =
    NoteRowsCompanion Function({
      required String id,
      required String title,
      Value<String?> folderId,
      Value<String?> currentRevisionId,
      Value<String?> currentPageId,
      required String createdAt,
      required String updatedAt,
      required int wrap,
      required int sortOrder,
      Value<int> rowid,
    });
typedef $$NoteRowsTableUpdateCompanionBuilder =
    NoteRowsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> folderId,
      Value<String?> currentRevisionId,
      Value<String?> currentPageId,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> wrap,
      Value<int> sortOrder,
      Value<int> rowid,
    });

class $$NoteRowsTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $NoteRowsTable> {
  $$NoteRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentRevisionId => $composableBuilder(
    column: $table.currentRevisionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentPageId => $composableBuilder(
    column: $table.currentPageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wrap => $composableBuilder(
    column: $table.wrap,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NoteRowsTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $NoteRowsTable> {
  $$NoteRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentRevisionId => $composableBuilder(
    column: $table.currentRevisionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentPageId => $composableBuilder(
    column: $table.currentPageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wrap => $composableBuilder(
    column: $table.wrap,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteRowsTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $NoteRowsTable> {
  $$NoteRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get folderId =>
      $composableBuilder(column: $table.folderId, builder: (column) => column);

  GeneratedColumn<String> get currentRevisionId => $composableBuilder(
    column: $table.currentRevisionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currentPageId => $composableBuilder(
    column: $table.currentPageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get wrap =>
      $composableBuilder(column: $table.wrap, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$NoteRowsTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $NoteRowsTable,
          NoteRow,
          $$NoteRowsTableFilterComposer,
          $$NoteRowsTableOrderingComposer,
          $$NoteRowsTableAnnotationComposer,
          $$NoteRowsTableCreateCompanionBuilder,
          $$NoteRowsTableUpdateCompanionBuilder,
          (
            NoteRow,
            BaseReferences<_$StorageV2DriftDatabase, $NoteRowsTable, NoteRow>,
          ),
          NoteRow,
          PrefetchHooks Function()
        > {
  $$NoteRowsTableTableManager(_$StorageV2DriftDatabase db, $NoteRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> folderId = const Value.absent(),
                Value<String?> currentRevisionId = const Value.absent(),
                Value<String?> currentPageId = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> wrap = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteRowsCompanion(
                id: id,
                title: title,
                folderId: folderId,
                currentRevisionId: currentRevisionId,
                currentPageId: currentPageId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                wrap: wrap,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String?> folderId = const Value.absent(),
                Value<String?> currentRevisionId = const Value.absent(),
                Value<String?> currentPageId = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                required int wrap,
                required int sortOrder,
                Value<int> rowid = const Value.absent(),
              }) => NoteRowsCompanion.insert(
                id: id,
                title: title,
                folderId: folderId,
                currentRevisionId: currentRevisionId,
                currentPageId: currentPageId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                wrap: wrap,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NoteRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $NoteRowsTable,
      NoteRow,
      $$NoteRowsTableFilterComposer,
      $$NoteRowsTableOrderingComposer,
      $$NoteRowsTableAnnotationComposer,
      $$NoteRowsTableCreateCompanionBuilder,
      $$NoteRowsTableUpdateCompanionBuilder,
      (
        NoteRow,
        BaseReferences<_$StorageV2DriftDatabase, $NoteRowsTable, NoteRow>,
      ),
      NoteRow,
      PrefetchHooks Function()
    >;
typedef $$NotePageRowsTableCreateCompanionBuilder =
    NotePageRowsCompanion Function({
      required String id,
      required String noteId,
      required String title,
      required String fileName,
      required String relativePath,
      Value<String?> currentRevisionId,
      required int sortOrder,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$NotePageRowsTableUpdateCompanionBuilder =
    NotePageRowsCompanion Function({
      Value<String> id,
      Value<String> noteId,
      Value<String> title,
      Value<String> fileName,
      Value<String> relativePath,
      Value<String?> currentRevisionId,
      Value<int> sortOrder,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$NotePageRowsTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $NotePageRowsTable> {
  $$NotePageRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentRevisionId => $composableBuilder(
    column: $table.currentRevisionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NotePageRowsTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $NotePageRowsTable> {
  $$NotePageRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentRevisionId => $composableBuilder(
    column: $table.currentRevisionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotePageRowsTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $NotePageRowsTable> {
  $$NotePageRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currentRevisionId => $composableBuilder(
    column: $table.currentRevisionId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$NotePageRowsTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $NotePageRowsTable,
          NotePageRow,
          $$NotePageRowsTableFilterComposer,
          $$NotePageRowsTableOrderingComposer,
          $$NotePageRowsTableAnnotationComposer,
          $$NotePageRowsTableCreateCompanionBuilder,
          $$NotePageRowsTableUpdateCompanionBuilder,
          (
            NotePageRow,
            BaseReferences<
              _$StorageV2DriftDatabase,
              $NotePageRowsTable,
              NotePageRow
            >,
          ),
          NotePageRow,
          PrefetchHooks Function()
        > {
  $$NotePageRowsTableTableManager(
    _$StorageV2DriftDatabase db,
    $NotePageRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotePageRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotePageRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotePageRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String> relativePath = const Value.absent(),
                Value<String?> currentRevisionId = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotePageRowsCompanion(
                id: id,
                noteId: noteId,
                title: title,
                fileName: fileName,
                relativePath: relativePath,
                currentRevisionId: currentRevisionId,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String noteId,
                required String title,
                required String fileName,
                required String relativePath,
                Value<String?> currentRevisionId = const Value.absent(),
                required int sortOrder,
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => NotePageRowsCompanion.insert(
                id: id,
                noteId: noteId,
                title: title,
                fileName: fileName,
                relativePath: relativePath,
                currentRevisionId: currentRevisionId,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotePageRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $NotePageRowsTable,
      NotePageRow,
      $$NotePageRowsTableFilterComposer,
      $$NotePageRowsTableOrderingComposer,
      $$NotePageRowsTableAnnotationComposer,
      $$NotePageRowsTableCreateCompanionBuilder,
      $$NotePageRowsTableUpdateCompanionBuilder,
      (
        NotePageRow,
        BaseReferences<
          _$StorageV2DriftDatabase,
          $NotePageRowsTable,
          NotePageRow
        >,
      ),
      NotePageRow,
      PrefetchHooks Function()
    >;
typedef $$NoteRevisionRowsTableCreateCompanionBuilder =
    NoteRevisionRowsCompanion Function({
      required String id,
      required String noteId,
      Value<String?> pageId,
      Value<String?> parentRevisionId,
      required String savedAt,
      required int deltaStart,
      required String deletedText,
      required String insertedText,
      Value<int> rowid,
    });
typedef $$NoteRevisionRowsTableUpdateCompanionBuilder =
    NoteRevisionRowsCompanion Function({
      Value<String> id,
      Value<String> noteId,
      Value<String?> pageId,
      Value<String?> parentRevisionId,
      Value<String> savedAt,
      Value<int> deltaStart,
      Value<String> deletedText,
      Value<String> insertedText,
      Value<int> rowid,
    });

class $$NoteRevisionRowsTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $NoteRevisionRowsTable> {
  $$NoteRevisionRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pageId => $composableBuilder(
    column: $table.pageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentRevisionId => $composableBuilder(
    column: $table.parentRevisionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deltaStart => $composableBuilder(
    column: $table.deltaStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedText => $composableBuilder(
    column: $table.deletedText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get insertedText => $composableBuilder(
    column: $table.insertedText,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NoteRevisionRowsTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $NoteRevisionRowsTable> {
  $$NoteRevisionRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pageId => $composableBuilder(
    column: $table.pageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentRevisionId => $composableBuilder(
    column: $table.parentRevisionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deltaStart => $composableBuilder(
    column: $table.deltaStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedText => $composableBuilder(
    column: $table.deletedText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get insertedText => $composableBuilder(
    column: $table.insertedText,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteRevisionRowsTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $NoteRevisionRowsTable> {
  $$NoteRevisionRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get pageId =>
      $composableBuilder(column: $table.pageId, builder: (column) => column);

  GeneratedColumn<String> get parentRevisionId => $composableBuilder(
    column: $table.parentRevisionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);

  GeneratedColumn<int> get deltaStart => $composableBuilder(
    column: $table.deltaStart,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deletedText => $composableBuilder(
    column: $table.deletedText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get insertedText => $composableBuilder(
    column: $table.insertedText,
    builder: (column) => column,
  );
}

class $$NoteRevisionRowsTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $NoteRevisionRowsTable,
          NoteRevisionRow,
          $$NoteRevisionRowsTableFilterComposer,
          $$NoteRevisionRowsTableOrderingComposer,
          $$NoteRevisionRowsTableAnnotationComposer,
          $$NoteRevisionRowsTableCreateCompanionBuilder,
          $$NoteRevisionRowsTableUpdateCompanionBuilder,
          (
            NoteRevisionRow,
            BaseReferences<
              _$StorageV2DriftDatabase,
              $NoteRevisionRowsTable,
              NoteRevisionRow
            >,
          ),
          NoteRevisionRow,
          PrefetchHooks Function()
        > {
  $$NoteRevisionRowsTableTableManager(
    _$StorageV2DriftDatabase db,
    $NoteRevisionRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteRevisionRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteRevisionRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteRevisionRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<String?> pageId = const Value.absent(),
                Value<String?> parentRevisionId = const Value.absent(),
                Value<String> savedAt = const Value.absent(),
                Value<int> deltaStart = const Value.absent(),
                Value<String> deletedText = const Value.absent(),
                Value<String> insertedText = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteRevisionRowsCompanion(
                id: id,
                noteId: noteId,
                pageId: pageId,
                parentRevisionId: parentRevisionId,
                savedAt: savedAt,
                deltaStart: deltaStart,
                deletedText: deletedText,
                insertedText: insertedText,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String noteId,
                Value<String?> pageId = const Value.absent(),
                Value<String?> parentRevisionId = const Value.absent(),
                required String savedAt,
                required int deltaStart,
                required String deletedText,
                required String insertedText,
                Value<int> rowid = const Value.absent(),
              }) => NoteRevisionRowsCompanion.insert(
                id: id,
                noteId: noteId,
                pageId: pageId,
                parentRevisionId: parentRevisionId,
                savedAt: savedAt,
                deltaStart: deltaStart,
                deletedText: deletedText,
                insertedText: insertedText,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NoteRevisionRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $NoteRevisionRowsTable,
      NoteRevisionRow,
      $$NoteRevisionRowsTableFilterComposer,
      $$NoteRevisionRowsTableOrderingComposer,
      $$NoteRevisionRowsTableAnnotationComposer,
      $$NoteRevisionRowsTableCreateCompanionBuilder,
      $$NoteRevisionRowsTableUpdateCompanionBuilder,
      (
        NoteRevisionRow,
        BaseReferences<
          _$StorageV2DriftDatabase,
          $NoteRevisionRowsTable,
          NoteRevisionRow
        >,
      ),
      NoteRevisionRow,
      PrefetchHooks Function()
    >;
typedef $$NoteEditProposalRowsTableCreateCompanionBuilder =
    NoteEditProposalRowsCompanion Function({
      required String id,
      required String noteId,
      Value<String?> pageId,
      Value<String?> baseRevisionId,
      required String baseContentHash,
      required String createdAt,
      Value<int> rowid,
    });
typedef $$NoteEditProposalRowsTableUpdateCompanionBuilder =
    NoteEditProposalRowsCompanion Function({
      Value<String> id,
      Value<String> noteId,
      Value<String?> pageId,
      Value<String?> baseRevisionId,
      Value<String> baseContentHash,
      Value<String> createdAt,
      Value<int> rowid,
    });

class $$NoteEditProposalRowsTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $NoteEditProposalRowsTable> {
  $$NoteEditProposalRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pageId => $composableBuilder(
    column: $table.pageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseRevisionId => $composableBuilder(
    column: $table.baseRevisionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseContentHash => $composableBuilder(
    column: $table.baseContentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NoteEditProposalRowsTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $NoteEditProposalRowsTable> {
  $$NoteEditProposalRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pageId => $composableBuilder(
    column: $table.pageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseRevisionId => $composableBuilder(
    column: $table.baseRevisionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseContentHash => $composableBuilder(
    column: $table.baseContentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteEditProposalRowsTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $NoteEditProposalRowsTable> {
  $$NoteEditProposalRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get pageId =>
      $composableBuilder(column: $table.pageId, builder: (column) => column);

  GeneratedColumn<String> get baseRevisionId => $composableBuilder(
    column: $table.baseRevisionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get baseContentHash => $composableBuilder(
    column: $table.baseContentHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$NoteEditProposalRowsTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $NoteEditProposalRowsTable,
          NoteEditProposalRow,
          $$NoteEditProposalRowsTableFilterComposer,
          $$NoteEditProposalRowsTableOrderingComposer,
          $$NoteEditProposalRowsTableAnnotationComposer,
          $$NoteEditProposalRowsTableCreateCompanionBuilder,
          $$NoteEditProposalRowsTableUpdateCompanionBuilder,
          (
            NoteEditProposalRow,
            BaseReferences<
              _$StorageV2DriftDatabase,
              $NoteEditProposalRowsTable,
              NoteEditProposalRow
            >,
          ),
          NoteEditProposalRow,
          PrefetchHooks Function()
        > {
  $$NoteEditProposalRowsTableTableManager(
    _$StorageV2DriftDatabase db,
    $NoteEditProposalRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteEditProposalRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteEditProposalRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$NoteEditProposalRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<String?> pageId = const Value.absent(),
                Value<String?> baseRevisionId = const Value.absent(),
                Value<String> baseContentHash = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteEditProposalRowsCompanion(
                id: id,
                noteId: noteId,
                pageId: pageId,
                baseRevisionId: baseRevisionId,
                baseContentHash: baseContentHash,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String noteId,
                Value<String?> pageId = const Value.absent(),
                Value<String?> baseRevisionId = const Value.absent(),
                required String baseContentHash,
                required String createdAt,
                Value<int> rowid = const Value.absent(),
              }) => NoteEditProposalRowsCompanion.insert(
                id: id,
                noteId: noteId,
                pageId: pageId,
                baseRevisionId: baseRevisionId,
                baseContentHash: baseContentHash,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NoteEditProposalRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $NoteEditProposalRowsTable,
      NoteEditProposalRow,
      $$NoteEditProposalRowsTableFilterComposer,
      $$NoteEditProposalRowsTableOrderingComposer,
      $$NoteEditProposalRowsTableAnnotationComposer,
      $$NoteEditProposalRowsTableCreateCompanionBuilder,
      $$NoteEditProposalRowsTableUpdateCompanionBuilder,
      (
        NoteEditProposalRow,
        BaseReferences<
          _$StorageV2DriftDatabase,
          $NoteEditProposalRowsTable,
          NoteEditProposalRow
        >,
      ),
      NoteEditProposalRow,
      PrefetchHooks Function()
    >;
typedef $$NoteEditBlockRowsTableCreateCompanionBuilder =
    NoteEditBlockRowsCompanion Function({
      required String id,
      required String proposalId,
      required int startLine,
      required int deleteCount,
      required String deletedLinesJson,
      required String insertLinesJson,
      required int sortOrder,
      Value<int> rowid,
    });
typedef $$NoteEditBlockRowsTableUpdateCompanionBuilder =
    NoteEditBlockRowsCompanion Function({
      Value<String> id,
      Value<String> proposalId,
      Value<int> startLine,
      Value<int> deleteCount,
      Value<String> deletedLinesJson,
      Value<String> insertLinesJson,
      Value<int> sortOrder,
      Value<int> rowid,
    });

class $$NoteEditBlockRowsTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $NoteEditBlockRowsTable> {
  $$NoteEditBlockRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get proposalId => $composableBuilder(
    column: $table.proposalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startLine => $composableBuilder(
    column: $table.startLine,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deleteCount => $composableBuilder(
    column: $table.deleteCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedLinesJson => $composableBuilder(
    column: $table.deletedLinesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get insertLinesJson => $composableBuilder(
    column: $table.insertLinesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NoteEditBlockRowsTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $NoteEditBlockRowsTable> {
  $$NoteEditBlockRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get proposalId => $composableBuilder(
    column: $table.proposalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startLine => $composableBuilder(
    column: $table.startLine,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deleteCount => $composableBuilder(
    column: $table.deleteCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedLinesJson => $composableBuilder(
    column: $table.deletedLinesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get insertLinesJson => $composableBuilder(
    column: $table.insertLinesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteEditBlockRowsTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $NoteEditBlockRowsTable> {
  $$NoteEditBlockRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get proposalId => $composableBuilder(
    column: $table.proposalId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startLine =>
      $composableBuilder(column: $table.startLine, builder: (column) => column);

  GeneratedColumn<int> get deleteCount => $composableBuilder(
    column: $table.deleteCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deletedLinesJson => $composableBuilder(
    column: $table.deletedLinesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get insertLinesJson => $composableBuilder(
    column: $table.insertLinesJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$NoteEditBlockRowsTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $NoteEditBlockRowsTable,
          NoteEditBlockRow,
          $$NoteEditBlockRowsTableFilterComposer,
          $$NoteEditBlockRowsTableOrderingComposer,
          $$NoteEditBlockRowsTableAnnotationComposer,
          $$NoteEditBlockRowsTableCreateCompanionBuilder,
          $$NoteEditBlockRowsTableUpdateCompanionBuilder,
          (
            NoteEditBlockRow,
            BaseReferences<
              _$StorageV2DriftDatabase,
              $NoteEditBlockRowsTable,
              NoteEditBlockRow
            >,
          ),
          NoteEditBlockRow,
          PrefetchHooks Function()
        > {
  $$NoteEditBlockRowsTableTableManager(
    _$StorageV2DriftDatabase db,
    $NoteEditBlockRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteEditBlockRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteEditBlockRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteEditBlockRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> proposalId = const Value.absent(),
                Value<int> startLine = const Value.absent(),
                Value<int> deleteCount = const Value.absent(),
                Value<String> deletedLinesJson = const Value.absent(),
                Value<String> insertLinesJson = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteEditBlockRowsCompanion(
                id: id,
                proposalId: proposalId,
                startLine: startLine,
                deleteCount: deleteCount,
                deletedLinesJson: deletedLinesJson,
                insertLinesJson: insertLinesJson,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String proposalId,
                required int startLine,
                required int deleteCount,
                required String deletedLinesJson,
                required String insertLinesJson,
                required int sortOrder,
                Value<int> rowid = const Value.absent(),
              }) => NoteEditBlockRowsCompanion.insert(
                id: id,
                proposalId: proposalId,
                startLine: startLine,
                deleteCount: deleteCount,
                deletedLinesJson: deletedLinesJson,
                insertLinesJson: insertLinesJson,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NoteEditBlockRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $NoteEditBlockRowsTable,
      NoteEditBlockRow,
      $$NoteEditBlockRowsTableFilterComposer,
      $$NoteEditBlockRowsTableOrderingComposer,
      $$NoteEditBlockRowsTableAnnotationComposer,
      $$NoteEditBlockRowsTableCreateCompanionBuilder,
      $$NoteEditBlockRowsTableUpdateCompanionBuilder,
      (
        NoteEditBlockRow,
        BaseReferences<
          _$StorageV2DriftDatabase,
          $NoteEditBlockRowsTable,
          NoteEditBlockRow
        >,
      ),
      NoteEditBlockRow,
      PrefetchHooks Function()
    >;
typedef $$ScheduleRowsTableCreateCompanionBuilder =
    ScheduleRowsCompanion Function({
      required String id,
      required String title,
      required String startTime,
      required String endTime,
      Value<String?> note,
      required String kind,
      Value<int> rowid,
    });
typedef $$ScheduleRowsTableUpdateCompanionBuilder =
    ScheduleRowsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> startTime,
      Value<String> endTime,
      Value<String?> note,
      Value<String> kind,
      Value<int> rowid,
    });

class $$ScheduleRowsTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $ScheduleRowsTable> {
  $$ScheduleRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ScheduleRowsTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $ScheduleRowsTable> {
  $$ScheduleRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ScheduleRowsTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $ScheduleRowsTable> {
  $$ScheduleRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<String> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);
}

class $$ScheduleRowsTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $ScheduleRowsTable,
          ScheduleRow,
          $$ScheduleRowsTableFilterComposer,
          $$ScheduleRowsTableOrderingComposer,
          $$ScheduleRowsTableAnnotationComposer,
          $$ScheduleRowsTableCreateCompanionBuilder,
          $$ScheduleRowsTableUpdateCompanionBuilder,
          (
            ScheduleRow,
            BaseReferences<
              _$StorageV2DriftDatabase,
              $ScheduleRowsTable,
              ScheduleRow
            >,
          ),
          ScheduleRow,
          PrefetchHooks Function()
        > {
  $$ScheduleRowsTableTableManager(
    _$StorageV2DriftDatabase db,
    $ScheduleRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScheduleRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScheduleRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScheduleRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> startTime = const Value.absent(),
                Value<String> endTime = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScheduleRowsCompanion(
                id: id,
                title: title,
                startTime: startTime,
                endTime: endTime,
                note: note,
                kind: kind,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String startTime,
                required String endTime,
                Value<String?> note = const Value.absent(),
                required String kind,
                Value<int> rowid = const Value.absent(),
              }) => ScheduleRowsCompanion.insert(
                id: id,
                title: title,
                startTime: startTime,
                endTime: endTime,
                note: note,
                kind: kind,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ScheduleRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $ScheduleRowsTable,
      ScheduleRow,
      $$ScheduleRowsTableFilterComposer,
      $$ScheduleRowsTableOrderingComposer,
      $$ScheduleRowsTableAnnotationComposer,
      $$ScheduleRowsTableCreateCompanionBuilder,
      $$ScheduleRowsTableUpdateCompanionBuilder,
      (
        ScheduleRow,
        BaseReferences<
          _$StorageV2DriftDatabase,
          $ScheduleRowsTable,
          ScheduleRow
        >,
      ),
      ScheduleRow,
      PrefetchHooks Function()
    >;
typedef $$TodoListRowsTableCreateCompanionBuilder =
    TodoListRowsCompanion Function({
      required String id,
      required String title,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$TodoListRowsTableUpdateCompanionBuilder =
    TodoListRowsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$TodoListRowsTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $TodoListRowsTable> {
  $$TodoListRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TodoListRowsTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $TodoListRowsTable> {
  $$TodoListRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TodoListRowsTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $TodoListRowsTable> {
  $$TodoListRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$TodoListRowsTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $TodoListRowsTable,
          TodoListRow,
          $$TodoListRowsTableFilterComposer,
          $$TodoListRowsTableOrderingComposer,
          $$TodoListRowsTableAnnotationComposer,
          $$TodoListRowsTableCreateCompanionBuilder,
          $$TodoListRowsTableUpdateCompanionBuilder,
          (
            TodoListRow,
            BaseReferences<
              _$StorageV2DriftDatabase,
              $TodoListRowsTable,
              TodoListRow
            >,
          ),
          TodoListRow,
          PrefetchHooks Function()
        > {
  $$TodoListRowsTableTableManager(
    _$StorageV2DriftDatabase db,
    $TodoListRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TodoListRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TodoListRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TodoListRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TodoListRowsCompanion(
                id: id,
                title: title,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => TodoListRowsCompanion.insert(
                id: id,
                title: title,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TodoListRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $TodoListRowsTable,
      TodoListRow,
      $$TodoListRowsTableFilterComposer,
      $$TodoListRowsTableOrderingComposer,
      $$TodoListRowsTableAnnotationComposer,
      $$TodoListRowsTableCreateCompanionBuilder,
      $$TodoListRowsTableUpdateCompanionBuilder,
      (
        TodoListRow,
        BaseReferences<
          _$StorageV2DriftDatabase,
          $TodoListRowsTable,
          TodoListRow
        >,
      ),
      TodoListRow,
      PrefetchHooks Function()
    >;
typedef $$TodoItemRowsTableCreateCompanionBuilder =
    TodoItemRowsCompanion Function({
      required String id,
      required String listId,
      required String itemText,
      required int done,
      required int sortOrder,
      Value<int> rowid,
    });
typedef $$TodoItemRowsTableUpdateCompanionBuilder =
    TodoItemRowsCompanion Function({
      Value<String> id,
      Value<String> listId,
      Value<String> itemText,
      Value<int> done,
      Value<int> sortOrder,
      Value<int> rowid,
    });

class $$TodoItemRowsTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $TodoItemRowsTable> {
  $$TodoItemRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get listId => $composableBuilder(
    column: $table.listId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemText => $composableBuilder(
    column: $table.itemText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get done => $composableBuilder(
    column: $table.done,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TodoItemRowsTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $TodoItemRowsTable> {
  $$TodoItemRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get listId => $composableBuilder(
    column: $table.listId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemText => $composableBuilder(
    column: $table.itemText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get done => $composableBuilder(
    column: $table.done,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TodoItemRowsTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $TodoItemRowsTable> {
  $$TodoItemRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get listId =>
      $composableBuilder(column: $table.listId, builder: (column) => column);

  GeneratedColumn<String> get itemText =>
      $composableBuilder(column: $table.itemText, builder: (column) => column);

  GeneratedColumn<int> get done =>
      $composableBuilder(column: $table.done, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$TodoItemRowsTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $TodoItemRowsTable,
          TodoItemRow,
          $$TodoItemRowsTableFilterComposer,
          $$TodoItemRowsTableOrderingComposer,
          $$TodoItemRowsTableAnnotationComposer,
          $$TodoItemRowsTableCreateCompanionBuilder,
          $$TodoItemRowsTableUpdateCompanionBuilder,
          (
            TodoItemRow,
            BaseReferences<
              _$StorageV2DriftDatabase,
              $TodoItemRowsTable,
              TodoItemRow
            >,
          ),
          TodoItemRow,
          PrefetchHooks Function()
        > {
  $$TodoItemRowsTableTableManager(
    _$StorageV2DriftDatabase db,
    $TodoItemRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TodoItemRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TodoItemRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TodoItemRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> listId = const Value.absent(),
                Value<String> itemText = const Value.absent(),
                Value<int> done = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TodoItemRowsCompanion(
                id: id,
                listId: listId,
                itemText: itemText,
                done: done,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String listId,
                required String itemText,
                required int done,
                required int sortOrder,
                Value<int> rowid = const Value.absent(),
              }) => TodoItemRowsCompanion.insert(
                id: id,
                listId: listId,
                itemText: itemText,
                done: done,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TodoItemRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $TodoItemRowsTable,
      TodoItemRow,
      $$TodoItemRowsTableFilterComposer,
      $$TodoItemRowsTableOrderingComposer,
      $$TodoItemRowsTableAnnotationComposer,
      $$TodoItemRowsTableCreateCompanionBuilder,
      $$TodoItemRowsTableUpdateCompanionBuilder,
      (
        TodoItemRow,
        BaseReferences<
          _$StorageV2DriftDatabase,
          $TodoItemRowsTable,
          TodoItemRow
        >,
      ),
      TodoItemRow,
      PrefetchHooks Function()
    >;
typedef $$RoleplayScenarioRowsTableCreateCompanionBuilder =
    RoleplayScenarioRowsCompanion Function({
      required String id,
      required String dataJson,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$RoleplayScenarioRowsTableUpdateCompanionBuilder =
    RoleplayScenarioRowsCompanion Function({
      Value<String> id,
      Value<String> dataJson,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$RoleplayScenarioRowsTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $RoleplayScenarioRowsTable> {
  $$RoleplayScenarioRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RoleplayScenarioRowsTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $RoleplayScenarioRowsTable> {
  $$RoleplayScenarioRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RoleplayScenarioRowsTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $RoleplayScenarioRowsTable> {
  $$RoleplayScenarioRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get dataJson =>
      $composableBuilder(column: $table.dataJson, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$RoleplayScenarioRowsTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $RoleplayScenarioRowsTable,
          RoleplayScenarioRow,
          $$RoleplayScenarioRowsTableFilterComposer,
          $$RoleplayScenarioRowsTableOrderingComposer,
          $$RoleplayScenarioRowsTableAnnotationComposer,
          $$RoleplayScenarioRowsTableCreateCompanionBuilder,
          $$RoleplayScenarioRowsTableUpdateCompanionBuilder,
          (
            RoleplayScenarioRow,
            BaseReferences<
              _$StorageV2DriftDatabase,
              $RoleplayScenarioRowsTable,
              RoleplayScenarioRow
            >,
          ),
          RoleplayScenarioRow,
          PrefetchHooks Function()
        > {
  $$RoleplayScenarioRowsTableTableManager(
    _$StorageV2DriftDatabase db,
    $RoleplayScenarioRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoleplayScenarioRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoleplayScenarioRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RoleplayScenarioRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoleplayScenarioRowsCompanion(
                id: id,
                dataJson: dataJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String dataJson,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => RoleplayScenarioRowsCompanion.insert(
                id: id,
                dataJson: dataJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RoleplayScenarioRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $RoleplayScenarioRowsTable,
      RoleplayScenarioRow,
      $$RoleplayScenarioRowsTableFilterComposer,
      $$RoleplayScenarioRowsTableOrderingComposer,
      $$RoleplayScenarioRowsTableAnnotationComposer,
      $$RoleplayScenarioRowsTableCreateCompanionBuilder,
      $$RoleplayScenarioRowsTableUpdateCompanionBuilder,
      (
        RoleplayScenarioRow,
        BaseReferences<
          _$StorageV2DriftDatabase,
          $RoleplayScenarioRowsTable,
          RoleplayScenarioRow
        >,
      ),
      RoleplayScenarioRow,
      PrefetchHooks Function()
    >;
typedef $$RoleplayThreadRowsTableCreateCompanionBuilder =
    RoleplayThreadRowsCompanion Function({
      required String id,
      required String dataJson,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$RoleplayThreadRowsTableUpdateCompanionBuilder =
    RoleplayThreadRowsCompanion Function({
      Value<String> id,
      Value<String> dataJson,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$RoleplayThreadRowsTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $RoleplayThreadRowsTable> {
  $$RoleplayThreadRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RoleplayThreadRowsTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $RoleplayThreadRowsTable> {
  $$RoleplayThreadRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RoleplayThreadRowsTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $RoleplayThreadRowsTable> {
  $$RoleplayThreadRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get dataJson =>
      $composableBuilder(column: $table.dataJson, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$RoleplayThreadRowsTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $RoleplayThreadRowsTable,
          RoleplayThreadRow,
          $$RoleplayThreadRowsTableFilterComposer,
          $$RoleplayThreadRowsTableOrderingComposer,
          $$RoleplayThreadRowsTableAnnotationComposer,
          $$RoleplayThreadRowsTableCreateCompanionBuilder,
          $$RoleplayThreadRowsTableUpdateCompanionBuilder,
          (
            RoleplayThreadRow,
            BaseReferences<
              _$StorageV2DriftDatabase,
              $RoleplayThreadRowsTable,
              RoleplayThreadRow
            >,
          ),
          RoleplayThreadRow,
          PrefetchHooks Function()
        > {
  $$RoleplayThreadRowsTableTableManager(
    _$StorageV2DriftDatabase db,
    $RoleplayThreadRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoleplayThreadRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoleplayThreadRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoleplayThreadRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoleplayThreadRowsCompanion(
                id: id,
                dataJson: dataJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String dataJson,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => RoleplayThreadRowsCompanion.insert(
                id: id,
                dataJson: dataJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RoleplayThreadRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $RoleplayThreadRowsTable,
      RoleplayThreadRow,
      $$RoleplayThreadRowsTableFilterComposer,
      $$RoleplayThreadRowsTableOrderingComposer,
      $$RoleplayThreadRowsTableAnnotationComposer,
      $$RoleplayThreadRowsTableCreateCompanionBuilder,
      $$RoleplayThreadRowsTableUpdateCompanionBuilder,
      (
        RoleplayThreadRow,
        BaseReferences<
          _$StorageV2DriftDatabase,
          $RoleplayThreadRowsTable,
          RoleplayThreadRow
        >,
      ),
      RoleplayThreadRow,
      PrefetchHooks Function()
    >;
typedef $$RecycleBinRowsTableCreateCompanionBuilder =
    RecycleBinRowsCompanion Function({
      required String id,
      required String owner,
      required String category,
      required String type,
      required String title,
      required String preview,
      required String payloadJson,
      required String deletedAt,
      Value<int> rowid,
    });
typedef $$RecycleBinRowsTableUpdateCompanionBuilder =
    RecycleBinRowsCompanion Function({
      Value<String> id,
      Value<String> owner,
      Value<String> category,
      Value<String> type,
      Value<String> title,
      Value<String> preview,
      Value<String> payloadJson,
      Value<String> deletedAt,
      Value<int> rowid,
    });

class $$RecycleBinRowsTableFilterComposer
    extends Composer<_$StorageV2DriftDatabase, $RecycleBinRowsTable> {
  $$RecycleBinRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get preview => $composableBuilder(
    column: $table.preview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecycleBinRowsTableOrderingComposer
    extends Composer<_$StorageV2DriftDatabase, $RecycleBinRowsTable> {
  $$RecycleBinRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get preview => $composableBuilder(
    column: $table.preview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecycleBinRowsTableAnnotationComposer
    extends Composer<_$StorageV2DriftDatabase, $RecycleBinRowsTable> {
  $$RecycleBinRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get owner =>
      $composableBuilder(column: $table.owner, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get preview =>
      $composableBuilder(column: $table.preview, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$RecycleBinRowsTableTableManager
    extends
        RootTableManager<
          _$StorageV2DriftDatabase,
          $RecycleBinRowsTable,
          RecycleBinRow,
          $$RecycleBinRowsTableFilterComposer,
          $$RecycleBinRowsTableOrderingComposer,
          $$RecycleBinRowsTableAnnotationComposer,
          $$RecycleBinRowsTableCreateCompanionBuilder,
          $$RecycleBinRowsTableUpdateCompanionBuilder,
          (
            RecycleBinRow,
            BaseReferences<
              _$StorageV2DriftDatabase,
              $RecycleBinRowsTable,
              RecycleBinRow
            >,
          ),
          RecycleBinRow,
          PrefetchHooks Function()
        > {
  $$RecycleBinRowsTableTableManager(
    _$StorageV2DriftDatabase db,
    $RecycleBinRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecycleBinRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecycleBinRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecycleBinRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> owner = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> preview = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecycleBinRowsCompanion(
                id: id,
                owner: owner,
                category: category,
                type: type,
                title: title,
                preview: preview,
                payloadJson: payloadJson,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String owner,
                required String category,
                required String type,
                required String title,
                required String preview,
                required String payloadJson,
                required String deletedAt,
                Value<int> rowid = const Value.absent(),
              }) => RecycleBinRowsCompanion.insert(
                id: id,
                owner: owner,
                category: category,
                type: type,
                title: title,
                preview: preview,
                payloadJson: payloadJson,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecycleBinRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageV2DriftDatabase,
      $RecycleBinRowsTable,
      RecycleBinRow,
      $$RecycleBinRowsTableFilterComposer,
      $$RecycleBinRowsTableOrderingComposer,
      $$RecycleBinRowsTableAnnotationComposer,
      $$RecycleBinRowsTableCreateCompanionBuilder,
      $$RecycleBinRowsTableUpdateCompanionBuilder,
      (
        RecycleBinRow,
        BaseReferences<
          _$StorageV2DriftDatabase,
          $RecycleBinRowsTable,
          RecycleBinRow
        >,
      ),
      RecycleBinRow,
      PrefetchHooks Function()
    >;

class $StorageV2DriftDatabaseManager {
  final _$StorageV2DriftDatabase _db;
  $StorageV2DriftDatabaseManager(this._db);
  $$StorageMetaTableTableManager get storageMeta =>
      $$StorageMetaTableTableManager(_db, _db.storageMeta);
  $$AppSettingsRowsTableTableManager get appSettingsRows =>
      $$AppSettingsRowsTableTableManager(_db, _db.appSettingsRows);
  $$ModelConfigRowsTableTableManager get modelConfigRows =>
      $$ModelConfigRowsTableTableManager(_db, _db.modelConfigRows);
  $$ResourceRowsTableTableManager get resourceRows =>
      $$ResourceRowsTableTableManager(_db, _db.resourceRows);
  $$ConversationRowsTableTableManager get conversationRows =>
      $$ConversationRowsTableTableManager(_db, _db.conversationRows);
  $$MessageRowsTableTableManager get messageRows =>
      $$MessageRowsTableTableManager(_db, _db.messageRows);
  $$MessageAttachmentRowsTableTableManager get messageAttachmentRows =>
      $$MessageAttachmentRowsTableTableManager(_db, _db.messageAttachmentRows);
  $$NoteFolderRowsTableTableManager get noteFolderRows =>
      $$NoteFolderRowsTableTableManager(_db, _db.noteFolderRows);
  $$NoteRowsTableTableManager get noteRows =>
      $$NoteRowsTableTableManager(_db, _db.noteRows);
  $$NotePageRowsTableTableManager get notePageRows =>
      $$NotePageRowsTableTableManager(_db, _db.notePageRows);
  $$NoteRevisionRowsTableTableManager get noteRevisionRows =>
      $$NoteRevisionRowsTableTableManager(_db, _db.noteRevisionRows);
  $$NoteEditProposalRowsTableTableManager get noteEditProposalRows =>
      $$NoteEditProposalRowsTableTableManager(_db, _db.noteEditProposalRows);
  $$NoteEditBlockRowsTableTableManager get noteEditBlockRows =>
      $$NoteEditBlockRowsTableTableManager(_db, _db.noteEditBlockRows);
  $$ScheduleRowsTableTableManager get scheduleRows =>
      $$ScheduleRowsTableTableManager(_db, _db.scheduleRows);
  $$TodoListRowsTableTableManager get todoListRows =>
      $$TodoListRowsTableTableManager(_db, _db.todoListRows);
  $$TodoItemRowsTableTableManager get todoItemRows =>
      $$TodoItemRowsTableTableManager(_db, _db.todoItemRows);
  $$RoleplayScenarioRowsTableTableManager get roleplayScenarioRows =>
      $$RoleplayScenarioRowsTableTableManager(_db, _db.roleplayScenarioRows);
  $$RoleplayThreadRowsTableTableManager get roleplayThreadRows =>
      $$RoleplayThreadRowsTableTableManager(_db, _db.roleplayThreadRows);
  $$RecycleBinRowsTableTableManager get recycleBinRows =>
      $$RecycleBinRowsTableTableManager(_db, _db.recycleBinRows);
}
