/// 模型目录（models.dev 数据）在客户端的规范化视图。
///
/// 这一层只描述数据与解析/匹配规则，不做网络请求与本地持久化：
/// - [ModelCatalogDocument] 是裁剪后的目录文档，与后端 `/models/catalog`、
///   内置快照和本地缓存文件共用同一种 JSON 形状；
/// - [ModelCatalogModel] 是一条模型记录，字段名沿用 models.dev 的 wire 名称；
/// - [ModelCatalogIndex] 提供 provider/模型名匹配；
/// - [ModelCatalogProviderResolver] 把 endpoint 映射到 models.dev 的 provider id。
///
/// 目录只是建议值：调用方（模型配置层）必须保证用户手填值优先，目录值只用于
/// 补全空缺，绝不覆盖用户输入。
library;

import 'dart:convert';

/// 目录文档当前的 JSON schema 版本。
const int modelCatalogSchemaVersion = 1;

/// 目录数据的来源标识。
const String modelCatalogSource = 'models.dev';

/// 目录里内置的默认 provider 集合（与后端 `/models/catalog` 的默认集合一致）。
const List<String> defaultModelCatalogProviderIds = [
  'openai',
  'anthropic',
  'google',
  'deepseek',
  'openrouter',
  'groq',
  'togetherai',
  'xai',
  'moonshotai',
  'moonshotai-cn',
  'zai',
  'zhipuai',
  'alibaba',
  'alibaba-cn',
  'siliconflow',
  'minimax',
  'mistral',
  'nvidia',
  'stepfun',
  'ollama-cloud',
  'perplexity',
  'cerebras',
  'fireworks-ai',
  'deepinfra',
  'novita-ai',
];

/// 一条模型目录记录支持的思考强度形态。
enum ModelCatalogReasoningKind {
  /// 只有开/关，没有强度概念。
  toggle,

  /// 通过离散强度值（如 `low`/`medium`/`high`）控制。
  effort,

  /// 通过思考预算 token 数控制。
  budgetTokens,
}

/// 模型目录给出的一个思考强度选项。
class ModelCatalogReasoningOption {
  /// 创建一个思考强度选项。
  const ModelCatalogReasoningOption({
    required this.kind,
    this.values = const [],
    this.minBudgetTokens,
  });

  /// 强度形态。
  final ModelCatalogReasoningKind kind;

  /// [ModelCatalogReasoningKind.effort] 支持的取值（保持上游顺序）。
  final List<String> values;

  /// [ModelCatalogReasoningKind.budgetTokens] 的最小预算。
  final int? minBudgetTokens;

  /// 从 models.dev 的 `reasoning_options` 条目解析。
  ///
  /// 未知 `type`、类型不符的字段都返回 null，由调用方跳过而不是让整份目录失败。
  static ModelCatalogReasoningOption? tryParse(Object? value) {
    if (value is! Map) return null;
    final type = value['type']?.toString().trim();
    switch (type) {
      case 'toggle':
        return const ModelCatalogReasoningOption(
          kind: ModelCatalogReasoningKind.toggle,
        );
      case 'effort':
        final rawValues = value['values'];
        final values = rawValues is List
            ? rawValues
                  .map((item) => item?.toString().trim() ?? '')
                  .where((item) => item.isNotEmpty)
                  .toList(growable: false)
            : const <String>[];
        if (values.isEmpty) return null;
        return ModelCatalogReasoningOption(
          kind: ModelCatalogReasoningKind.effort,
          values: values,
        );
      case 'budget_tokens':
        return ModelCatalogReasoningOption(
          kind: ModelCatalogReasoningKind.budgetTokens,
          minBudgetTokens: _asInt(value['min']),
        );
      default:
        return null;
    }
  }

  /// 序列化回目录文档使用的键名。
  Map<String, dynamic> toJson() {
    return switch (kind) {
      ModelCatalogReasoningKind.toggle => {'type': 'toggle'},
      ModelCatalogReasoningKind.effort => {
        'type': 'effort',
        'values': values,
      },
      ModelCatalogReasoningKind.budgetTokens => {
        'type': 'budget_tokens',
        if (minBudgetTokens != null) 'min': minBudgetTokens,
      },
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ModelCatalogReasoningOption &&
        other.kind == kind &&
        other.minBudgetTokens == minBudgetTokens &&
        _sameStrings(other.values, values);
  }

  @override
  int get hashCode => Object.hash(kind, minBudgetTokens, Object.hashAll(values));

  @override
  String toString() =>
      'ModelCatalogReasoningOption(${kind.name}, $values, min: $minBudgetTokens)';
}

/// 目录里的一条模型记录。
class ModelCatalogModel {
  /// 创建一个模型目录记录。
  ModelCatalogModel({
    required this.providerId,
    required this.id,
    required this.name,
    this.contextWindow,
    this.maxOutputTokens,
    this.inputModalities = const [],
    this.attachment = false,
    this.toolCall = false,
    this.reasoning = false,
    this.reasoningOptions = const [],
    this.temperature = false,
    this.releasedAt,
    this.updatedAt,
  });

  /// 所属 models.dev provider id。
  final String providerId;

  /// 模型 id（models.dev 的键）。
  final String id;

  /// 展示名。
  final String name;

  /// `limit.context`。
  final int? contextWindow;

  /// `limit.output`。
  final int? maxOutputTokens;

  /// `modalities.input`。
  final List<String> inputModalities;

  /// `attachment`：支持文件/图片附件。
  final bool attachment;

  /// `tool_call`。
  final bool toolCall;

  /// `reasoning`。
  final bool reasoning;

  /// `reasoning_options`。
  final List<ModelCatalogReasoningOption> reasoningOptions;

  /// `temperature`：是否接受 temperature 参数。
  final bool temperature;

  /// `release_date`。
  final DateTime? releasedAt;

  /// `last_updated`。
  final DateTime? updatedAt;

  /// 是否支持图片输入（`attachment` 或 `modalities.input` 含 image）。
  bool get supportsVision =>
      attachment || inputModalities.any((item) => item == 'image');

  /// 支持的思考强度形态；没有强度概念时为空（例如仅 `toggle`）。
  List<ModelCatalogReasoningOption> get effortOptions => reasoningOptions
      .where((item) => item.kind != ModelCatalogReasoningKind.toggle)
      .toList(growable: false);

  /// 支持的思考强度取值（effort 型，保持上游顺序）。
  List<String> get reasoningEffortValues => reasoningOptions
      .where((item) => item.kind == ModelCatalogReasoningKind.effort)
      .expand((item) => item.values)
      .toList(growable: false);

  /// 从 models.dev 的模型对象解析；[fallbackId] 是所属键名。
  static ModelCatalogModel? tryParse(
    String providerId,
    String fallbackId,
    Object? value,
  ) {
    if (value is! Map) return null;
    final rawId = value['id']?.toString().trim() ?? '';
    final id = rawId.isNotEmpty ? rawId : fallbackId.trim();
    if (id.isEmpty) return null;
    final rawName = value['name']?.toString().trim() ?? '';
    final limit = value['limit'];
    final modalities = value['modalities'];
    final options = <ModelCatalogReasoningOption>[];
    final rawOptions = value['reasoning_options'];
    if (rawOptions is List) {
      for (final item in rawOptions) {
        final parsed = ModelCatalogReasoningOption.tryParse(item);
        if (parsed != null) options.add(parsed);
      }
    }
    return ModelCatalogModel(
      providerId: providerId,
      id: id,
      name: rawName.isEmpty ? id : rawName,
      contextWindow: limit is Map ? _asInt(limit['context']) : null,
      maxOutputTokens: limit is Map ? _asInt(limit['output']) : null,
      inputModalities: modalities is Map
          ? _asStringList(modalities['input'])
          : const [],
      attachment: value['attachment'] == true,
      toolCall: value['tool_call'] == true,
      reasoning: value['reasoning'] == true,
      reasoningOptions: List.unmodifiable(options),
      temperature: value['temperature'] == true,
      releasedAt: _asDate(value['release_date']),
      updatedAt: _asDate(value['last_updated']),
    );
  }

  /// 序列化为裁剪后的目录文档形状。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (contextWindow != null || maxOutputTokens != null)
        'limit': {
          if (contextWindow != null) 'context': contextWindow,
          if (maxOutputTokens != null) 'output': maxOutputTokens,
        },
      'attachment': attachment,
      'tool_call': toolCall,
      'reasoning': reasoning,
      if (reasoningOptions.isNotEmpty)
        'reasoning_options': reasoningOptions
            .map((item) => item.toJson())
            .toList(growable: false),
      if (inputModalities.isNotEmpty)
        'modalities': {'input': inputModalities, 'output': const ['text']},
      'temperature': temperature,
      if (releasedAt != null) 'release_date': _dateText(releasedAt!),
      if (updatedAt != null) 'last_updated': _dateText(updatedAt!),
    };
  }
}

/// 目录里的一个 provider。
class ModelCatalogProvider {
  /// 创建一个 provider 记录。
  ModelCatalogProvider({
    required this.id,
    required this.name,
    this.api,
    Map<String, ModelCatalogModel> models = const {},
  }) : models = Map.unmodifiable(models);

  /// models.dev provider id。
  final String id;

  /// 展示名。
  final String name;

  /// 上游 base URL；models.dev 里有 26 个 provider 不提供该字段。
  final String? api;

  /// provider 下的模型，键是模型 id。
  final Map<String, ModelCatalogModel> models;

  /// 从 models.dev 的 provider 对象解析。
  static ModelCatalogProvider? tryParse(String providerId, Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString().trim() ?? providerId.trim();
    if (id.isEmpty) return null;
    final rawName = value['name']?.toString().trim() ?? '';
    final rawApi = value['api']?.toString().trim() ?? '';
    final parsedModels = <String, ModelCatalogModel>{};
    final rawModels = value['models'];
    if (rawModels is Map) {
      for (final entry in rawModels.entries) {
        final key = entry.key?.toString() ?? '';
        if (key.isEmpty) continue;
        final model = ModelCatalogModel.tryParse(id, key, entry.value);
        if (model != null) parsedModels[model.id] = model;
      }
    }
    return ModelCatalogProvider(
      id: id,
      name: rawName.isEmpty ? id : rawName,
      api: rawApi.isEmpty ? null : rawApi,
      models: parsedModels,
    );
  }

  /// 序列化为裁剪后的目录文档形状。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (api != null && api!.isNotEmpty) 'api': api,
      'models': {
        for (final entry in models.entries) entry.key: entry.value.toJson(),
      },
    };
  }
}

/// 一份裁剪后的模型目录文档。
class ModelCatalogDocument {
  /// 创建目录文档。
  ModelCatalogDocument({
    required this.providers,
    this.schemaVersion = modelCatalogSchemaVersion,
    this.source = modelCatalogSource,
    this.fetchedAt,
  });

  /// provider id → provider 记录。
  final Map<String, ModelCatalogProvider> providers;

  /// 文档 schema 版本。
  final int schemaVersion;

  /// 数据来源标识。
  final String source;

  /// 上游抓取时间。
  final DateTime? fetchedAt;

  /// 目录是否为空。
  bool get isEmpty => providers.isEmpty;

  /// 从 models.dev 的 `api.json` 解析。
  ///
  /// [providerFilter] 非空时只保留其中的 provider（用于把整份文档裁剪到需要的
  /// 集合）；文档结构不可识别时返回 null，单条损坏记录被跳过。
  static ModelCatalogDocument? tryParseModelsDevApi(
    Object? json, {
    Set<String>? providerFilter,
    DateTime? fetchedAt,
  }) {
    if (json is! Map) return null;
    final providers = <String, ModelCatalogProvider>{};
    for (final entry in json.entries) {
      final key = entry.key?.toString() ?? '';
      if (key.isEmpty) continue;
      if (providerFilter != null && !providerFilter.contains(key)) continue;
      final provider = ModelCatalogProvider.tryParse(key, entry.value);
      if (provider != null && provider.models.isNotEmpty) {
        providers[provider.id] = provider;
      }
    }
    if (providers.isEmpty) return null;
    return ModelCatalogDocument(providers: providers, fetchedAt: fetchedAt);
  }

  /// 从本地缓存文件、内置快照或后端 `/models/catalog` 响应解析。
  ///
  /// 期望 `{schemaVersion, source, fetchedAt, providers: {...}}`；也兼容直接给出
  /// provider 映射的旧文档。结构不可识别或 schema 版本不支持时返回 null。
  static ModelCatalogDocument? tryParseDocument(Object? json) {
    if (json is! Map) return null;
    final version = _asInt(json['schemaVersion']);
    if (version != null && version > modelCatalogSchemaVersion) return null;
    final rawProviders = json['providers'];
    final source = json['source']?.toString().trim();
    if (rawProviders is Map) {
      final providers = <String, ModelCatalogProvider>{};
      for (final entry in rawProviders.entries) {
        final key = entry.key?.toString() ?? '';
        if (key.isEmpty) continue;
        final provider = ModelCatalogProvider.tryParse(key, entry.value);
        if (provider != null && provider.models.isNotEmpty) {
          providers[provider.id] = provider;
        }
      }
      if (providers.isEmpty) return null;
      return ModelCatalogDocument(
        providers: providers,
        schemaVersion: version ?? modelCatalogSchemaVersion,
        source: source == null || source.isEmpty ? modelCatalogSource : source,
        fetchedAt: _asDate(json['fetchedAt']),
      );
    }
    // 兼容没有包装层的 provider 映射。
    return tryParseModelsDevApi(json, fetchedAt: _asDate(json['fetchedAt']));
  }

  /// 序列化为缓存文件 / 内置快照使用的文档形状。
  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'source': source,
      if (fetchedAt != null) 'fetchedAt': fetchedAt!.toUtc().toIso8601String(),
      'providers': {
        for (final entry in providers.entries) entry.key: entry.value.toJson(),
      },
    };
  }

  /// 编码为 JSON 文本。
  String encode() => jsonEncode(toJson());
}

/// 一次目录匹配的结果。
class ModelCatalogMatch {
  /// 创建匹配结果。
  const ModelCatalogMatch({required this.model, required this.exact});

  /// 命中的目录记录。
  final ModelCatalogModel model;

  /// 是否精确命中模型 id（false 表示经过归一化或去 vendor 前缀后命中）。
  final bool exact;
}

/// 按 provider + 模型名查询目录。
class ModelCatalogIndex {
  /// 从目录文档构建索引。
  ModelCatalogIndex(this.document)
    : _exact = {
        for (final provider in document.providers.values)
          for (final model in provider.models.values)
            '${provider.id}\u0000${model.id}': model,
      },
      _normalized = _buildNormalizedIndex(document);

  /// 被索引的目录文档。
  final ModelCatalogDocument document;

  final Map<String, ModelCatalogModel> _exact;
  final Map<String, List<ModelCatalogModel>> _normalized;

  static Map<String, List<ModelCatalogModel>> _buildNormalizedIndex(
    ModelCatalogDocument document,
  ) {
    final index = <String, List<ModelCatalogModel>>{};
    for (final provider in document.providers.values) {
      for (final model in provider.models.values) {
        for (final key in _candidateKeys(model.id)) {
          index.putIfAbsent('${provider.id}\u0000$key', () => []).add(model);
        }
      }
    }
    return index;
  }

  /// 查询 [providerId] 下名为 [modelName] 的模型。
  ///
  /// 先精确匹配，再做小写、去 `vendor/` 前缀、去 `:latest`/`-latest`/日期/
  /// `-preview` 后缀的归一化匹配；归一化命中多个不同模型时返回 null（宁可不填，
  /// 也不猜）。[candidates] 用于把这些歧义暴露给 UI。
  ModelCatalogModel? lookup({
    required String providerId,
    required String modelName,
  }) {
    final result = match(providerId: providerId, modelName: modelName);
    return result?.model;
  }

  /// 与 [lookup] 相同，但返回是否精确命中。
  ModelCatalogMatch? match({
    required String providerId,
    required String modelName,
  }) {
    final provider = document.providers[providerId];
    if (provider == null) return null;
    final name = modelName.trim();
    if (name.isEmpty) return null;
    final exact = _exact['$providerId\u0000$name'];
    if (exact != null) return ModelCatalogMatch(model: exact, exact: true);
    for (final key in _candidateKeys(name)) {
      final hits = _normalized['$providerId\u0000$key'];
      if (hits == null || hits.isEmpty) continue;
      final distinct = {for (final hit in hits) hit.id: hit};
      if (distinct.length == 1) {
        return ModelCatalogMatch(model: distinct.values.first, exact: false);
      }
    }
    return null;
  }
  /// [providerId] 下与 [modelName] 相关的候选（最多 [limit] 条，供 UI 展示）。
  List<ModelCatalogModel> candidates({
    required String providerId,
    required String modelName,
    int limit = 5,
  }) {
    final provider = document.providers[providerId];
    if (provider == null) return const [];
    final keys = _candidateKeys(modelName).toList(growable: false);
    if (keys.isEmpty) return const [];
    final hits = <String, ModelCatalogModel>{};
    for (final key in keys) {
      for (final hit in _normalized['$providerId\u0000$key'] ?? const []) {
        hits[hit.id] = hit;
      }
    }
    final models = hits.values.toList()
      ..sort((a, b) {
        final left = b.updatedAt ?? b.releasedAt;
        final right = a.updatedAt ?? a.releasedAt;
        if (left == null && right == null) return a.id.compareTo(b.id);
        if (left == null) return 1;
        if (right == null) return -1;
        return left.compareTo(right);
      });
    return models.take(limit).toList(growable: false);
  }
}

/// 把 endpoint 映射到 models.dev 的 provider id。
///
/// 顺序：用户显式指定 > 已知 endpoint host 表 > 目录里 provider 自己的 `api`
/// host > 无法判断（返回 null）。无法判断时模型参数保持现状，不做猜测。
class ModelCatalogProviderResolver {
  /// 创建解析器。
  const ModelCatalogProviderResolver();

  /// 已知的 endpoint host → provider id 映射。
  ///
  /// 只覆盖 models.dev 没有给出 `api` 字段或存在地区变体的主流服务；
  /// 其余 provider 由目录里的 `api` host 自动匹配。
  static const Map<String, String> hostProviderIds = {
    'api.openai.com': 'openai',
    'api.anthropic.com': 'anthropic',
    'generativelanguage.googleapis.com': 'google',
    'api.deepseek.com': 'deepseek',
    'openrouter.ai': 'openrouter',
    'api.groq.com': 'groq',
    'api.together.xyz': 'togetherai',
    'api.together.ai': 'togetherai',
    'api.x.ai': 'xai',
    'api.moonshot.cn': 'moonshotai-cn',
    'api.moonshot.ai': 'moonshotai',
    'open.bigmodel.cn': 'zhipuai',
    'api.z.ai': 'zai',
    'dashscope.aliyuncs.com': 'alibaba',
    'dashscope-intl.aliyuncs.com': 'alibaba',
    'api.siliconflow.cn': 'siliconflow',
    'api.siliconflow.com': 'siliconflow',
    'api.minimax.chat': 'minimax',
    'api.minimaxi.com': 'minimax',
    'api.mistral.ai': 'mistral',
    'integrate.api.nvidia.com': 'nvidia',
    'api.stepfun.com': 'stepfun',
    'api.perplexity.ai': 'perplexity',
    'api.cerebras.ai': 'cerebras',
    'api.fireworks.ai': 'fireworks-ai',
    'api.deepinfra.com': 'deepinfra',
    'api.novita.ai': 'novita-ai',
    'ollama.com': 'ollama-cloud',
  };

  /// 解析 provider id。
  ///
  /// [explicitProviderId] 是用户在模型配置里手选的值，优先级最高；
  /// [endpoint] 为本地/私网地址（例如 Ollama）时不匹配任何 provider。
  String? resolve({
    String? explicitProviderId,
    required String endpoint,
    ModelCatalogDocument? document,
  }) {
    final explicit = explicitProviderId?.trim() ?? '';
    if (explicit.isNotEmpty) {
      if (document == null || document.providers.containsKey(explicit)) {
        return explicit;
      }
      return null;
    }
    final host = _hostOf(endpoint);
    if (host.isEmpty) return null;
    final known = hostProviderIds[host];
    if (known != null && (document == null || document.providers.containsKey(known))) {
      return known;
    }
    for (final key in _hostCandidates(host)) {
      final candidate = hostProviderIds[key];
      if (candidate != null &&
          (document == null || document.providers.containsKey(candidate))) {
        return candidate;
      }
    }
    if (document != null) {
      for (final provider in document.providers.values) {
        final api = provider.api;
        if (api == null || api.isEmpty) continue;
        if (_hostOf(api) == host) return provider.id;
      }
    }
    return null;
  }

  static String _hostOf(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return '';
    return uri.host.toLowerCase();
  }

  /// 依次剥离子域，让 `api.deepseek.com` 也能命中 `deepseek.com` 这类表项。
  static Iterable<String> _hostCandidates(String host) sync* {
    final parts = host.split('.');
    for (var index = 1; index < parts.length - 1; index++) {
      yield parts.sublist(index).join('.');
    }
    if (!host.startsWith('api.')) yield 'api.$host';
  }
}

/// 生成模型名匹配用的候选键（精确 id 之外的所有归一化形式）。
Iterable<String> _candidateKeys(String rawName) sync* {
  final base = rawName.trim();
  if (base.isEmpty) return;
  final seen = <String>{};
  for (final value in [
    base,
    base.toLowerCase(),
    _stripVendor(base).toLowerCase(),
  ]) {
    final normalized = _normalizeModelKey(value);
    if (normalized.isNotEmpty && seen.add(normalized)) yield normalized;
  }
}

String _stripVendor(String value) {
  final slash = value.lastIndexOf('/');
  return slash >= 0 && slash + 1 < value.length
      ? value.substring(slash + 1)
      : value;
}

final RegExp _dateSuffix = RegExp(r'[-_]?\d{8}$');
final RegExp _isoDateSuffix = RegExp(r'[-_]?\d{4}-\d{2}-\d{2}$');

String _normalizeModelKey(String value) {
  var result = value.trim().toLowerCase();
  if (result.isEmpty) return result;
  const suffixes = [':latest', '-latest', '-preview', '-exp', '-experimental'];
  var changed = true;
  while (changed) {
    changed = false;
    for (final suffix in suffixes) {
      if (result.length > suffix.length && result.endsWith(suffix)) {
        result = result.substring(0, result.length - suffix.length);
        changed = true;
      }
    }
    for (final pattern in [_isoDateSuffix, _dateSuffix]) {
      final match = pattern.firstMatch(result);
      if (match != null && match.start > 0) {
        result = result.substring(0, match.start);
        changed = true;
      }
    }
  }
  return result;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

List<String> _asStringList(Object? value) {
  if (value is! List) return const [];
  return List.unmodifiable(
    value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty),
  );
}

final RegExp _explicitZone = RegExp(r'(?:[Zz]|[+-]\d{2}:?\d{2})$');

DateTime? _asDate(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  // 目录里的日期没有时区（`2025-08-07`）。按 UTC 补 Z 再解析，否则同一份快照
  // 会在不同时区的设备上解析成不同时刻，甚至前后差一天。
  final normalized = _explicitZone.hasMatch(text)
      ? text
      : text.contains(':')
      ? '${text.replaceFirst(' ', 'T')}Z'
      : '${text}T00:00:00Z';
  return DateTime.tryParse(normalized)?.toUtc();
}

String _dateText(DateTime value) {
  final utc = value.toUtc();
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  return '${utc.year}-$month-$day';
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
