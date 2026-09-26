import 'dart:convert';
import 'model_catalog.dart';
import 'reasoning_effort.dart';

/// 从模型目录（models.dev）得到的建议值。
///
/// 目录值只用于**补全空缺**：它是派生数据，由目录服务在刷新/获取模型列表时
/// 写入，永远不会改写用户手填的 `maxTokens`、`contextWindow` 或能力开关。
/// 生效优先级见 [ModelConfig.effectiveContextWindow] 与
/// [ModelConfig.supportsVision] 等 getter。
class ModelCatalogHint {
  /// 创建一个目录建议。
  ModelCatalogHint({
    required this.providerId,
    required this.modelId,
    this.exact = true,
    this.contextWindow,
    this.maxOutputTokens,
    this.supportsVision = false,
    this.supportsTools = false,
    this.supportsThinking = false,
    this.reasoningOptions = const [],
    this.fetchedAt,
  });

  /// 命中的 models.dev provider id。
  final String providerId;

  /// 命中的模型 id。
  final String modelId;

  /// 是否精确命中模型 id（false 表示经过归一化/去 vendor 前缀匹配）。
  final bool exact;

  /// 目录给出的上下文窗口。
  final int? contextWindow;

  /// 目录给出的最大输出 token 数。
  final int? maxOutputTokens;

  /// 目录给出的视觉能力。
  final bool supportsVision;

  /// 目录给出的工具调用能力。
  final bool supportsTools;

  /// 目录给出的思考输出能力。
  final bool supportsThinking;

  /// 目录给出的思考强度选项。
  final List<ModelCatalogReasoningOption> reasoningOptions;

  /// 目录数据的抓取时间。
  final DateTime? fetchedAt;

  /// 支持的思考强度取值（effort 型，保持上游顺序）。
  List<String> get reasoningEffortValues => reasoningOptions
      .where((option) => option.kind == ModelCatalogReasoningKind.effort)
      .expand((option) => option.values)
      .toList(growable: false);

  /// 是否支持思考预算（budget_tokens 型）。
  bool get supportsThinkingBudget => reasoningOptions.any(
    (option) => option.kind == ModelCatalogReasoningKind.budgetTokens,
  );

  /// 从目录记录构造建议值。
  factory ModelCatalogHint.fromModel(
    ModelCatalogModel model, {
    required String providerId,
    bool exact = true,
    DateTime? fetchedAt,
  }) {
    return ModelCatalogHint(
      providerId: providerId,
      modelId: model.id,
      exact: exact,
      contextWindow: model.contextWindow,
      maxOutputTokens: model.maxOutputTokens,
      supportsVision: model.supportsVision,
      supportsTools: model.toolCall,
      supportsThinking: model.reasoning,
      reasoningOptions: model.effortOptions,
      fetchedAt: fetchedAt,
    );
  }

  /// 从 JSON 数据创建目录建议。
  factory ModelCatalogHint.fromJson(Map<String, dynamic> json) {
    final options = <ModelCatalogReasoningOption>[];
    final rawOptions = json['reasoningOptions'];
    if (rawOptions is List) {
      for (final item in rawOptions) {
        final parsed = ModelCatalogReasoningOption.tryParse(item);
        if (parsed != null) options.add(parsed);
      }
    }
    return ModelCatalogHint(
      providerId: json['providerId'] as String? ?? '',
      modelId: json['modelId'] as String? ?? '',
      exact: json['exact'] as bool? ?? true,
      contextWindow: (json['contextWindow'] as num?)?.toInt(),
      maxOutputTokens: (json['maxOutputTokens'] as num?)?.toInt(),
      supportsVision: json['supportsVision'] == true,
      supportsTools: json['supportsTools'] == true,
      supportsThinking: json['supportsThinking'] == true,
      reasoningOptions: List.unmodifiable(options),
      fetchedAt: DateTime.tryParse(json['fetchedAt']?.toString() ?? ''),
    );
  }

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() {
    return {
      'providerId': providerId,
      'modelId': modelId,
      'exact': exact,
      if (contextWindow != null) 'contextWindow': contextWindow,
      if (maxOutputTokens != null) 'maxOutputTokens': maxOutputTokens,
      'supportsVision': supportsVision,
      'supportsTools': supportsTools,
      'supportsThinking': supportsThinking,
      if (reasoningOptions.isNotEmpty)
        'reasoningOptions': reasoningOptions
            .map((option) => option.toJson())
            .toList(growable: false),
      if (fetchedAt != null) 'fetchedAt': fetchedAt!.toUtc().toIso8601String(),
    };
  }

  @override
  String toString() =>
      'ModelCatalogHint($providerId/$modelId, context: $contextWindow, '
      'output: $maxOutputTokens)';
}

/// 提供商配置中的一个可选子模型。
///
/// 一个 Provider 可能暴露多个模型名。子模型级参数优先于 Provider 级参数，
/// 并决定当前请求是否启用视觉、思考和工具能力。
class ModelEntry {
  /// 子模型名称。
  final String name;

  /// 该子模型是否启用。
  final bool enabled;

  /// 该子模型是否支持视觉输入。
  final bool supportsVision;

  /// 该子模型是否支持思考过程输出。
  final bool supportsThinking;

  /// 该子模型是否支持工具调用。
  final bool supportsTools;

  /// 该子模型的最大 Token 数，为 null 时继承 Provider 级设置。
  final int? maxTokens;

  /// 该子模型的温度参数，为 null 时继承 Provider 级设置。
  final double? temperature;

  /// 该子模型的 Top-P 采样参数，为 null 时继承 Provider 级设置。
  final double? topP;

  /// 该子模型使用的 managed relay workflow。
  final String? workflow;

  /// 上下文窗口大小（token 数）。
  ///
  /// 来源优先级：用户在模型编辑器里手填 > 托管 `/relay/config` 下发 >
  /// 从模型 endpoint 拉取（见 [fetchedContextWindow]）> 默认值。
  final int? contextWindow;

  /// 从 OpenAI 兼容 `GET /models` 或 Ollama `/api/show` 拉取的上下文窗口。
  ///
  /// 与 [contextWindow] 分开存储，避免自动拉取值覆盖用户手填值。
  final int? fetchedContextWindow;

  /// 从模型目录（models.dev）补全的建议值，为空表示还没有匹配到目录记录。
  ///
  /// 目录值是派生数据：刷新会整体替换它，但不会改动用户手填字段。
  final ModelCatalogHint? catalog;

  /// 该模型默认使用的思考强度（effort 取值，如 `low`/`medium`/`high`）。
  ///
  /// null 表示不指定：对话没有单独设置时不下发强度参数，交给服务端默认行为。
  /// 可选值来自模型目录的 `reasoning_options`（见 [ModelCatalogHint]）。
  final String? reasoningEffort;

  /// 用户在模型编辑器里显式设定的能力开关（`supportsVision` 等）。
  ///
  /// 只在用户的选择与目录建议不同时才记录：目录建议 `false`、用户打开开关就
  /// 会写入 `true`，避免下一次目录刷新把用户显式开启的能力又关回去。
  final Map<String, bool> capabilityOverrides;

  /// 创建一个子模型配置实例。
  ModelEntry({
    required this.name,
    this.enabled = false,
    this.supportsVision = true,
    this.supportsThinking = true,
    this.supportsTools = true,
    this.maxTokens,
    this.temperature,
    this.topP,
    this.workflow,
    this.contextWindow,
    this.fetchedContextWindow,
    this.catalog,
    this.reasoningEffort,
    Map<String, bool>? capabilityOverrides,
  }) : capabilityOverrides = Map.unmodifiable(
         capabilityOverrides ?? const <String, bool>{},
       );

  /// 从 JSON 数据创建 [ModelEntry] 实例。
  factory ModelEntry.fromJson(Map<String, dynamic> json) {
    final rawCatalog = json['catalog'];
    final rawOverrides = json['capabilityOverrides'];
    return ModelEntry(
      name: json['name'] as String,
      enabled: json['enabled'] as bool? ?? false,
      supportsVision: json['supportsVision'] as bool? ?? true,
      supportsThinking: json['supportsThinking'] as bool? ?? true,
      supportsTools: json['supportsTools'] as bool? ?? true,
      maxTokens: (json['maxTokens'] as num?)?.toInt(),
      temperature: (json['temperature'] as num?)?.toDouble(),
      topP: (json['topP'] as num?)?.toDouble(),
      workflow: json['workflow'] as String?,
      contextWindow: (json['contextWindow'] as num?)?.toInt(),
      fetchedContextWindow: (json['fetchedContextWindow'] as num?)?.toInt(),
      catalog: rawCatalog is Map
          ? ModelCatalogHint.fromJson(Map<String, dynamic>.from(rawCatalog))
          : null,
      reasoningEffort: (json['reasoningEffort'] as String?)?.trim().isEmpty == true
          ? null
          : json['reasoningEffort'] as String?,
      capabilityOverrides: rawOverrides is Map
          ? {
              for (final entry in rawOverrides.entries)
                if (entry.key is String && entry.value is bool)
                  entry.key as String: entry.value as bool,
            }
          : null,
    );
  }

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() => {
    'name': name,
    'enabled': enabled,
    'supportsVision': supportsVision,
    'supportsThinking': supportsThinking,
    'supportsTools': supportsTools,
    if (maxTokens != null) 'maxTokens': maxTokens,
    if (temperature != null) 'temperature': temperature,
    if (topP != null) 'topP': topP,
    if (workflow != null && workflow!.isNotEmpty) 'workflow': workflow,
    if (contextWindow != null) 'contextWindow': contextWindow,
    if (fetchedContextWindow != null)
      'fetchedContextWindow': fetchedContextWindow,
    if (catalog != null) 'catalog': catalog!.toJson(),
    if (reasoningEffort != null && reasoningEffort!.isNotEmpty)
      'reasoningEffort': reasoningEffort,
    if (capabilityOverrides.isNotEmpty)
      'capabilityOverrides': capabilityOverrides,
  };

  /// 创建当前实例的副本，可选择性更新部分字段。
  ModelEntry copyWith({
    String? name,
    bool? enabled,
    bool? supportsVision,
    bool? supportsThinking,
    bool? supportsTools,
    Object? maxTokens = _sentinel,
    Object? temperature = _sentinel,
    Object? topP = _sentinel,
    Object? workflow = _sentinel,
    Object? contextWindow = _sentinel,
    Object? fetchedContextWindow = _sentinel,
    Object? catalog = _sentinel,
    Object? reasoningEffort = _sentinel,
    Map<String, bool>? capabilityOverrides,
  }) {
    return ModelEntry(
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      supportsVision: supportsVision ?? this.supportsVision,
      supportsThinking: supportsThinking ?? this.supportsThinking,
      supportsTools: supportsTools ?? this.supportsTools,
      maxTokens: identical(maxTokens, _sentinel)
          ? this.maxTokens
          : maxTokens as int?,
      temperature: identical(temperature, _sentinel)
          ? this.temperature
          : temperature as double?,
      topP: identical(topP, _sentinel) ? this.topP : topP as double?,
      workflow: identical(workflow, _sentinel)
          ? this.workflow
          : workflow as String?,
      contextWindow: identical(contextWindow, _sentinel)
          ? this.contextWindow
          : contextWindow as int?,
      fetchedContextWindow: identical(fetchedContextWindow, _sentinel)
          ? this.fetchedContextWindow
          : fetchedContextWindow as int?,
      catalog: identical(catalog, _sentinel)
          ? this.catalog
          : catalog as ModelCatalogHint?,
      reasoningEffort: identical(reasoningEffort, _sentinel)
          ? this.reasoningEffort
          : reasoningEffort as String?,
      capabilityOverrides: capabilityOverrides ?? this.capabilityOverrides,
    );
  }

  static const _sentinel = Object();
}

/// 一个模型提供商或接口配置。
///
/// `category` 决定配置用途：聊天、OCR、语音转写或图片生成。聊天配置可以
/// 通过 [models] 维护多个子模型，`modelName` 表示当前激活子模型。
class ModelConfig {
  /// 聊天类配置的类别常量。
  static const categoryChat = 'chat';

  /// OCR 类配置的类别常量。
  static const categoryOcr = 'ocr';

  /// 语音转写类配置的类别常量。
  static const categorySpeech = 'speech';

  /// 图片生成类配置的类别常量。
  static const categoryImageGeneration = 'image_generation';

  /// 所有支持的配置类别列表。
  static const supportedCategories = [
    categoryChat,
    categoryOcr,
    categorySpeech,
    categoryImageGeneration,
  ];

  /// 内置本地 OCR 的保留模型 ID（sentinel）。
  ///
  /// 该 ID 不对应持久化的 [ModelConfig]，仅用于在对话设置和 OCR 服务层
  /// 标识"使用 on-device ncnn + PPOCRv5 推理"。当 `imageModelId` 等于此
  /// 值时，OCR 路径跳过云端 API，直接调用本地推理。
  static const localOcrId = '__local_ppocrv5__';

  /// 内置本地 BlueLM 3B 的保留模型 ID。
  ///
  /// 该配置由 [ModelConfigProvider] 在本地模型状态可用时注入模型列表，
  /// 不持久化到 `model_configs.json`，也不参与云/LAN 同步和备份。
  static const localBlueLmId = '__local_bluelm_3b__';

  /// 本地 BlueLM 3B 使用的 `apiType`，[ApiService] 据此走端侧推理分支。
  static const localBlueLmApiType = 'local_bluelm';

  /// 配置唯一标识符。
  final String id;

  /// 配置显示名称。
  final String name;

  /// 配置类别，决定该配置的使用场景。
  final String category;

  /// API 端点地址。
  final String endpoint;

  /// API 密钥。
  final String apiKey;

  /// 平台安全存储中 API 密钥的非敏感引用。
  final String apiKeySecretRef;

  /// 当前激活的模型名称。
  final String modelName;

  /// 非托管 API 类型标识符，如 'openai'、'anthropic' 等。
  final String apiType;

  /// 配置优先级，数值越大优先级越高。
  final int priority;

  /// 該提供商下的所有子模型列表。
  final List<ModelEntry> models;

  /// Provider 级的最大 Token 数，可被子模型覆盖。
  final int? maxTokens;

  /// Provider 级的温度参数，可被子模型覆盖。
  final double? temperature;

  /// Provider 级的 Top-P 采样参数，可被子模型覆盖。
  final double? topP;

  /// Provider 级的上下文窗口大小，可被子模型覆盖。
  final int? contextWindow;

  /// 额外的自定义请求参数。
  final Map<String, dynamic> extraParams;

  /// 是否由 LynAI 托管同步。托管配置不可被用户改写 endpoint/API key。
  final bool managed;

  /// 用户是否在本机关闭了该托管配置。
  final bool disabledByUser;

  /// 用户对远端托管配置的逐字段覆盖值，优先级高于服务端下发值。
  final Map<String, dynamic> userOverrides;

  /// 用户是否明确允许将此非托管 Provider 的非秘密配置同步到云端。
  final bool cloudSyncEnabled;

  /// 手动指定的模型目录 provider id（models.dev）。
  ///
  /// 为空时由目录服务按 endpoint host 自动推断；显式指定用于自建转发层或
  /// 目录里没有 `api` 字段的服务。
  final String? catalogProviderId;

  /// 创建一个模型配置实例。
  ModelConfig({
    required this.id,
    required this.name,
    this.category = categoryChat,
    required this.endpoint,
    required this.apiKey,
    String? apiKeySecretRef,
    required this.modelName,
    required this.apiType,
    required this.priority,
    this.maxTokens,
    this.temperature,
    this.topP,
    this.contextWindow,
    this.managed = false,
    this.disabledByUser = false,
    Map<String, dynamic>? extraParams,
    Map<String, dynamic>? userOverrides,
    List<ModelEntry>? models,
    this.cloudSyncEnabled = false,
    this.catalogProviderId,
  }) : apiKeySecretRef = apiKeySecretRef ?? secretReferenceForId(id),
       extraParams = extraParams ?? {},
       userOverrides = userOverrides ?? {},
       models = models ?? [ModelEntry(name: modelName, enabled: true)];

  /// 内置本地 BlueLM 3B 模型，采样与上下文默认值和 Demo 保持一致。
  static ModelConfig localBlueLm() {
    const modelName = 'BlueLM-3B-MTK';
    return ModelConfig(
      id: localBlueLmId,
      name: '本地 BlueLM 3B',
      endpoint: '',
      apiKey: '',
      modelName: modelName,
      apiType: localBlueLmApiType,
      priority: -1,
      maxTokens: 200,
      temperature: 0.0,
      topP: 1.0,
      contextWindow: 4096,
      models: [
        ModelEntry(
          name: modelName,
          enabled: true,
          supportsVision: false,
          supportsThinking: false,
          supportsTools: false,
          maxTokens: 200,
          temperature: 0.0,
          topP: 1.0,
          contextWindow: 4096,
        ),
      ],
    );
  }

  /// 是否为内置本地 BlueLM 3B 配置。
  bool get isBuiltInLocalModel => id == localBlueLmId;

  /// 所有已启用的子模型名称列表。
  List<String> get enabledModelNames => disabledByUser
      ? const []
      : models.where((m) => m.enabled).map((m) => m.name).toList();

  /// 该提供商是否配置了多个子模型。
  bool get hasMultipleModels => models.length > 1;

  /// 当前激活的子模型配置项。
  ModelEntry? get activeEntry {
    for (final entry in models) {
      if (entry.name == modelName) return entry;
    }
    if (models.isEmpty) return null;
    final enabled = models.where((m) => m.enabled);
    return enabled.isNotEmpty ? enabled.first : models.first;
  }

  /// 生效的最大 Token 数。
  ///
  /// 优先级：用户本地覆盖 > 子模型手填 > 模型目录建议 > Provider 级。
  int? get effectiveMaxTokens =>
      (userOverrides['maxTokens'] as num?)?.toInt() ??
      activeEntry?.maxTokens ??
      activeEntry?.catalog?.maxOutputTokens ??
      maxTokens;

  /// 生效的温度参数，优先使用子模型设置。
  double? get effectiveTemperature =>
      (userOverrides['temperature'] as num?)?.toDouble() ??
      activeEntry?.temperature ??
      temperature;

  /// 生效的 Top-P 采样参数，优先使用子模型设置。
  double? get effectiveTopP =>
      (userOverrides['topP'] as num?)?.toDouble() ?? activeEntry?.topP ?? topP;

  /// 生效的上下文窗口大小。
  ///
  /// 优先级：用户本地覆盖 > 手填/托管下发 > 端点拉取 > 模型目录建议 >
  /// Provider 级 > null。目录只补空缺，不会覆盖任何用户输入。
  int? get effectiveContextWindow =>
      (userOverrides['contextWindow'] as num?)?.toInt() ??
      activeEntry?.contextWindow ??
      activeEntry?.fetchedContextWindow ??
      activeEntry?.catalog?.contextWindow ??
      contextWindow;

  /// 当前激活模型是否支持视觉输入。
  bool get supportsVision =>
      _effectiveCapability('supportsVision', activeEntry?.supportsVision);

  /// 当前激活模型是否支持思考过程输出。
  bool get supportsThinking =>
      _effectiveCapability('supportsThinking', activeEntry?.supportsThinking);

  /// 当前激活模型是否支持工具调用。
  bool get supportsTools =>
      _effectiveCapability('supportsTools', activeEntry?.supportsTools);

  /// 生效的思考强度可选档位。
  ///
  /// 目录给出 effort 取值时直接用目录值；目录只给 `budget_tokens`（Anthropic 风格的
  /// 预算型模型）时，如果本配置能把档位忠实地换算成预算，就回退到通用档位
  /// [budgetReasoningEffortLadder]；其余 OpenAI 兼容端点不做猜测，宁可不给档位。
  List<String> get effectiveReasoningEffortValues {
    final catalog = activeEntry?.catalog;
    if (catalog == null) return const [];
    final values = catalog.reasoningEffortValues
        .where((value) => value != reasoningEffortNone)
        .toList(growable: false);
    if (values.isNotEmpty) return values;
    if (!catalog.supportsThinking) return const [];
    return _supportsBudgetEffortLadder ? budgetReasoningEffortLadder : const [];
  }

  /// 是否能把通用档位换算成该配置认得的下发字段。
  ///
  /// 托管 relay 需要后端广告 `capabilities.reasoningEffort`（旧后端对未知字段
  /// fail closed）；非托管只有 Anthropic 格式有 `thinking.budget_tokens` 可用。
  bool get _supportsBudgetEffortLadder =>
      managed
      ? extraParams['relayReasoningEffort'] == true
      : apiType == 'anthropic';

  /// 该模型配置默认的思考强度；null 表示不指定。
  String? get effectiveReasoningEffort {
    final value = activeEntry?.reasoningEffort?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// 解析一次请求实际使用的思考强度。
  ///
  /// 优先级：对话设置 > 模型默认 > 不指定。目录给出了该模型的 effort 取值
  /// （[effectiveReasoningEffortValues] 非空）时只接受列表里的值：切换模型后
  /// 残留的强度会被跳过并退回模型默认，避免把上一个模型的取值发给当前模型。
  /// `none` 表示显式关闭思考，不受该列表限制。
  String? resolveReasoningEffort(String? conversationEffort) {
    final allowed = effectiveReasoningEffortValues
        .map(normalizeReasoningEffort)
        .where((value) => value.isNotEmpty)
        .toSet();
    for (final candidate in [
      conversationEffort?.trim(),
      effectiveReasoningEffort,
    ]) {
      if (candidate == null || candidate.isEmpty) continue;
      final normalized = normalizeReasoningEffort(candidate);
      if (isReasoningEffortDisabled(normalized)) return reasoningEffortNone;
      if (allowed.isEmpty || allowed.contains(normalized)) return normalized;
    }
    return null;
  }

  /// 生效的思考预算下限（来自模型目录，budget_tokens 型）。
  int? get effectiveReasoningBudgetMin {
    for (final option in activeEntry?.catalog?.reasoningOptions ?? const []) {
      if (option.kind == ModelCatalogReasoningKind.budgetTokens) {
        return option.minBudgetTokens;
      }
    }
    return null;
  }

  /// 计算能力开关的生效值。
  ///
  /// 托管配置的值来自服务端下发，能力只可能被本机覆盖关掉；用户自建配置的
  /// 优先级是：条目显式覆盖 > 本机覆盖 > 目录建议 > 子模型手填值（`false`
  /// 视为用户显式关闭，`true` 只是历史默认值，因此让位给目录）> true。
  bool _effectiveCapability(String key, bool? configured) {
    final fallback = configured ?? true;
    final entry = activeEntry;
    final entryOverride = entry?.capabilityOverrides[key];
    final override = entryOverride ?? userOverrides[key] as bool?;
    if (managed) return fallback && override != false;
    if (override != null) return override;
    if (fallback == false) return false;
    return _catalogCapability(key) ?? true;
  }

  bool? _catalogCapability(String key) {
    final catalog = activeEntry?.catalog;
    if (catalog == null) return null;
    return switch (key) {
      'supportsVision' => catalog.supportsVision,
      'supportsThinking' => catalog.supportsThinking,
      'supportsTools' => catalog.supportsTools,
      _ => null,
    };
  }

  /// 当前配置是否可使用应用原生工具协议。
  bool get supportsNativeTools =>
      supportsTools &&
      extraParams['disableTools'] != true &&
      (managed || (apiType != 'ollama' && apiType != 'anthropic'));

  /// 创建当前实例的副本，可选择性更新部分字段。
  ModelConfig copyWith({
    String? id,
    String? name,
    String? category,
    String? endpoint,
    String? apiKey,
    Object? apiKeySecretRef = _sentinel,
    String? modelName,
    String? apiType,
    int? priority,
    Object? maxTokens = _sentinel,
    Object? temperature = _sentinel,
    Object? topP = _sentinel,
    Object? contextWindow = _sentinel,
    bool? managed,
    bool? disabledByUser,
    Map<String, dynamic>? extraParams,
    Map<String, dynamic>? userOverrides,
    List<ModelEntry>? models,
    bool? cloudSyncEnabled,
    Object? catalogProviderId = _sentinel,
  }) {
    return ModelConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      endpoint: endpoint ?? this.endpoint,
      apiKey: apiKey ?? this.apiKey,
      apiKeySecretRef: identical(apiKeySecretRef, _sentinel)
          ? (id != null && id != this.id
                ? secretReferenceForId(id)
                : this.apiKeySecretRef)
          : apiKeySecretRef as String?,
      modelName: modelName ?? this.modelName,
      apiType: apiType ?? this.apiType,
      priority: priority ?? this.priority,
      maxTokens: identical(maxTokens, _sentinel)
          ? this.maxTokens
          : maxTokens as int?,
      temperature: identical(temperature, _sentinel)
          ? this.temperature
          : temperature as double?,
      topP: identical(topP, _sentinel) ? this.topP : topP as double?,
      contextWindow: identical(contextWindow, _sentinel)
          ? this.contextWindow
          : contextWindow as int?,
      managed: managed ?? this.managed,
      disabledByUser: disabledByUser ?? this.disabledByUser,
      extraParams: extraParams ?? this.extraParams,
      userOverrides: userOverrides ?? this.userOverrides,
      models: models ?? this.models,
      cloudSyncEnabled: cloudSyncEnabled ?? this.cloudSyncEnabled,
      catalogProviderId: identical(catalogProviderId, _sentinel)
          ? this.catalogProviderId
          : catalogProviderId as String?,
    );
  }

  static const _sentinel = Object();

  /// 从 JSON 数据创建 [ModelConfig] 实例。
  factory ModelConfig.fromJson(Map<String, dynamic> json) {
    List<ModelEntry> entries = [];
    if (json['models'] != null) {
      entries = (json['models'] as List<dynamic>? ?? const [])
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
    final category = json['category'] as String? ?? categoryChat;
    final maxTokens = (json['maxTokens'] as num?)?.toInt();
    final temperature = (json['temperature'] as num?)?.toDouble();
    final topP = (json['topP'] as num?)?.toDouble();
    final contextWindow = (json['contextWindow'] as num?)?.toInt();
    if (category == categoryChat) {
      entries = entries
          .map(
            (entry) => entry.copyWith(
              maxTokens: entry.maxTokens ?? maxTokens,
              temperature: entry.temperature ?? temperature,
              topP: entry.topP ?? topP,
            ),
          )
          .toList();
    }

    return ModelConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      category: category,
      endpoint: json['endpoint'] as String,
      apiKey: json['apiKey'] as String? ?? '',
      apiKeySecretRef: json['apiKeySecretRef'] as String?,
      modelName: modelName,
      apiType: json['managed'] == true ? '' : json['apiType'] as String,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      maxTokens: maxTokens,
      temperature: temperature,
      topP: topP,
      contextWindow: contextWindow,
      managed: json['managed'] == true,
      disabledByUser: json['disabledByUser'] == true,
      extraParams: json['extraParams'] is Map
          ? Map<String, dynamic>.from(json['extraParams'])
          : {},
      userOverrides: json['userOverrides'] is Map
          ? Map<String, dynamic>.from(json['userOverrides'])
          : {},
      models: entries,
      cloudSyncEnabled: json['cloudSyncEnabled'] == true,
      catalogProviderId: json['catalogProviderId'] as String?,
    );
  }

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'endpoint': endpoint,
      'apiKeySecretRef': apiKeySecretRef,
      'modelName': modelName,
      if (!managed) 'apiType': apiType,
      'priority': priority,
      'models': models.map((m) => m.toJson()).toList(),
      if (maxTokens != null) 'maxTokens': maxTokens,
      if (temperature != null) 'temperature': temperature,
      if (topP != null) 'topP': topP,
      if (contextWindow != null) 'contextWindow': contextWindow,
      if (managed) 'managed': managed,
      if (disabledByUser) 'disabledByUser': disabledByUser,
      if (extraParams.isNotEmpty) 'extraParams': extraParams,
      if (userOverrides.isNotEmpty) 'userOverrides': userOverrides,
      if (cloudSyncEnabled) 'cloudSyncEnabled': true,
      if (catalogProviderId != null && catalogProviderId!.isNotEmpty)
        'catalogProviderId': catalogProviderId,
    };
  }

  /// Returns the only valid secure-storage reference for a model ID.
  static String secretReferenceForId(String id) {
    final encoded = base64UrlEncode(utf8.encode(id)).replaceAll('=', '');
    return 'lynai.model-api-key.v1.$encoded';
  }
}
