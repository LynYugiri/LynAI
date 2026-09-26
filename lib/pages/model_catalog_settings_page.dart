import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/model_config.dart';
import '../providers/model_config_provider.dart';
import '../services/model_catalog_service.dart';
import '../utils/snackbar_utils.dart';

/// 可选地取出模型目录服务。
///
/// 目录服务是可选依赖：单元/组件测试可以只搭最小 Provider 图，此时返回 null，
/// 调用方跳过所有目录补全逻辑而不是抛 ProviderNotFoundException。
ModelCatalogService? modelCatalogOrNull(BuildContext context) {
  try {
    return context.read<ModelCatalogService>();
  } on ProviderNotFoundException {
    return null;
  }
}

/// 把 token 数格式化成紧凑文本（`4096`、`200k`、`1M`）。
String formatModelTokenCount(int? value) {
  if (value == null || value <= 0) return '未设置';
  if (value >= 1000000) {
    final millions = value / 1000000;
    return '${millions.toStringAsFixed(millions >= 10 ? 0 : 1)}M';
  }
  if (value >= 1000) {
    final thousands = value / 1000;
    return '${thousands.toStringAsFixed(thousands >= 100 ? 0 : 1)}k';
  }
  return '$value';
}

/// 目录数据来源的展示名。
String modelCatalogSourceLabel(ModelCatalogLoadSource source) {
  return switch (source) {
    ModelCatalogLoadSource.none => '无数据',
    ModelCatalogLoadSource.bundled => '内置快照',
    ModelCatalogLoadSource.cache => '本地缓存',
    ModelCatalogLoadSource.backend => '后端代理',
    ModelCatalogLoadSource.remote => 'models.dev',
  };
}

/// 登记已保存配置里手动指定的目录来源。
///
/// 目录服务只按默认 provider 集合裁剪数据；手动指定到集合之外的来源必须在这里
/// 重新登记，后续刷新（含后端代理）才会继续带上它，否则该配置会突然匹配不到目录。
void registerConfiguredCatalogProviders(
  ModelCatalogService? catalog,
  Iterable<ModelConfig> models,
) {
  if (catalog == null) return;
  for (final model in models) {
    final id = model.catalogProviderId?.trim() ?? '';
    if (id.isNotEmpty) catalog.requestProvider(id);
  }
}

/// 为 [model] 的每个子模型补全或刷新目录建议。
///
/// 只写 `ModelEntry.catalog`（派生数据），不改动用户手填的 `maxTokens`、
/// `contextWindow` 和能力开关。没有任何变化时返回 null。
ModelConfig? applyModelCatalogHints(
  ModelConfig model,
  ModelCatalogService catalog,
) {
  if (model.managed || model.isBuiltInLocalModel) return null;
  if (model.category != ModelConfig.categoryChat) return null;
  var changed = false;
  final entries = model.models.map((entry) {
    if (entry.name.trim().isEmpty) return entry;
    final hint = catalog.hintFor(model, entry.name);
    if (hint == null) return entry;
    if (entry.catalog != null &&
        jsonEncode(entry.catalog!.toJson()) == jsonEncode(hint.toJson())) {
      return entry;
    }
    changed = true;
    return entry.copyWith(catalog: hint);
  }).toList(growable: false);
  return changed ? model.copyWith(models: entries) : null;
}

/// 模型目录建议的只读展示：上下文/输出上限/能力/思考强度 + 命中的目录条目。
class ModelCatalogHintPanel extends StatelessWidget {
  /// 创建目录建议面板。
  const ModelCatalogHintPanel({super.key, required this.hint, this.dense = false});

  /// 目录建议；为 null 时展示"未匹配到目录记录"。
  final ModelCatalogHint? hint;

  /// 紧凑模式（用于列表副标题区域）。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = hint;
    if (value == null) {
      return Text(
        '模型目录：未匹配到记录（参数按手填值或默认值生效）',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      );
    }
    final chips = <String>[
      '上下文 ${formatModelTokenCount(value.contextWindow)}',
      if (value.maxOutputTokens != null)
        '输出 ${formatModelTokenCount(value.maxOutputTokens)}',
      if (value.supportsVision) '视觉',
      if (value.supportsTools) '工具',
      if (value.supportsThinking) '思考',
      if (value.reasoningEffortValues.isNotEmpty)
        '强度 ${value.reasoningEffortValues.join('/')}',
    ];
    final source =
        'models.dev · ${value.providerId}/${value.modelId}'
        '${value.exact ? '' : '（模糊匹配）'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final chip in chips)
              Chip(
                label: Text(chip),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
                labelStyle: theme.textTheme.labelSmall,
              ),
          ],
        ),
        if (!dense) ...[
          const SizedBox(height: 4),
          Text(
            source,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          Text(
            '留空即采用目录值；任何手填值优先于目录。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ],
    );
  }
}

/// 模型目录（models.dev）设置页：查看状态、刷新缓存、批量补全已配置模型。
class ModelCatalogSettingsPage extends StatefulWidget {
  /// 创建模型目录设置页。
  const ModelCatalogSettingsPage({super.key});

  @override
  State<ModelCatalogSettingsPage> createState() =>
      _ModelCatalogSettingsPageState();
}

class _ModelCatalogSettingsPageState extends State<ModelCatalogSettingsPage> {
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    final catalog = modelCatalogOrNull(context);
    if (catalog != null) {
      registerConfiguredCatalogProviders(
        catalog,
        context.read<ModelConfigProvider>().models,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) catalog.ensureLoaded();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = modelCatalogOrNull(context);
    return Scaffold(
      appBar: AppBar(title: const Text('模型目录')),
      body: catalog == null
          ? const Center(child: Text('模型目录服务不可用'))
          : ListenableBuilder(
              listenable: catalog,
              builder: (context, _) => _body(context, catalog),
            ),
    );
  }

  Widget _body(BuildContext context, ModelCatalogService catalog) {
    final theme = Theme.of(context);
    final status = catalog.status;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Card(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'models.dev 模型信息',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (status.loading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '来源：${modelCatalogSourceLabel(status.source)}\n'
                  '数据时间：${_formatTime(status.fetchedAt)}\n'
                  '最近检查：${_formatTime(status.checkedAt)}\n'
                  '${status.providerCount} 个 provider · ${status.modelCount} 个模型',
                  style: theme.textTheme.bodySmall,
                ),
                if (status.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '最近一次刷新失败：${status.error}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: status.loading ? null : () => _refresh(catalog),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('立即刷新'),
                ),
              ],
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.auto_fix_high_outlined),
                title: const Text('为已配置模型补全参数'),
                subtitle: const Text('按目录补全上下文窗口、输出上限、能力与思考强度；不覆盖手填值'),
                enabled: !_applying && catalog.hasData,
                onTap: !_applying && catalog.hasData
                    ? () => _applyToAll(catalog)
                    : null,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('清除本地目录缓存'),
                subtitle: const Text('下次刷新重新下载；内置快照仍可离线使用'),
                onTap: status.loading ? null : () => _clearCache(catalog),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            '目录数据来自公开的 models.dev（仅下载模型规格，不上传 API Key、'
            '对话内容或任何本机数据）。没有匹配到目录记录的模型保持现状：'
            '参数只按手填值、端点返回值或默认值生效。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _refresh(ModelCatalogService catalog) async {
    final ok = await catalog.refresh();
    if (!mounted) return;
    final status = catalog.status;
    showShortSnackBar(
      context,
      ok
          ? '目录已更新（${modelCatalogSourceLabel(status.source)}）'
          : '目录刷新失败：${status.error ?? '未知错误'}',
    );
  }

  Future<void> _clearCache(ModelCatalogService catalog) async {
    await catalog.clearCache();
    if (!mounted) return;
    showShortSnackBar(context, '已清除本地目录缓存');
  }

  Future<void> _applyToAll(ModelCatalogService catalog) async {
    setState(() => _applying = true);
    try {
      await catalog.ensureLoaded();
      if (!mounted) return;
      final provider = context.read<ModelConfigProvider>();
      var updated = 0;
      var considered = 0;
      for (final model in provider.models.toList(growable: false)) {
        if (model.managed || model.isBuiltInLocalModel) continue;
        if (model.category != ModelConfig.categoryChat) continue;
        considered++;
        final next = applyModelCatalogHints(model, catalog);
        if (next == null) continue;
        provider.updateModel(next);
        updated++;
      }
      if (!mounted) return;
      showShortSnackBar(
        context,
        updated > 0
            ? '已补全 $updated 个模型配置（共检查 $considered 个）'
            : '没有可补全的模型（共检查 $considered 个）',
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '未知';
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
