import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/model_config.dart';
import '../providers/model_config_provider.dart';

/// 插件本地的稳定模型选择值。
///
/// 与聊天页的模型选择不同，这里选择的子模型不会修改 Provider 的全局 `modelName`。
/// 插件配置文件独立存储模型 ID、子模型名称和分类，保证插件行为的可重现性。
class ModelSelectionValue {
  /// 模型提供者 ID。
  final String modelId;

  /// 子模型名称（如 gpt-4o）。
  final String? modelName;

  /// 模型分类（chat、embedding 等）。
  final String category;

  const ModelSelectionValue({
    required this.modelId,
    required this.modelName,
    required this.category,
  });

  /// 序列化为 JSON Map，用于写入插件配置文件。
  Map<String, dynamic> toJson() => {
    'modelId': modelId,
    if (modelName != null && modelName!.isNotEmpty) 'modelName': modelName,
    'category': category,
  };
}

/// 插件配置用的模型选择器组件。
///
/// 提供按分类筛选、能力匹配和子模型展开的模型选择 UI。与全局聊天模型选择器
/// 隔离，确保插件配置不会意外改变主界面的当前模型。
class ModelConfigPicker extends StatefulWidget {
  /// 选择器标题。
  final String title;

  /// 模型分类，用于过滤可选项。
  final String category;

  /// 当前选中的模型值。
  final ModelSelectionValue? value;

  /// 所需能力列表（vision、thinking、tools），为空则不过滤。
  final List<String> capabilities;

  /// 是否允许清空选择。
  final bool allowClear;

  /// 未选择时显示的标签。
  final String emptyLabel;

  /// 选择变更回调。
  final ValueChanged<ModelSelectionValue?> onChanged;

  const ModelConfigPicker({
    super.key,
    required this.title,
    required this.category,
    required this.value,
    this.capabilities = const [],
    this.allowClear = true,
    this.emptyLabel = '未选择模型',
    required this.onChanged,
  });

  @override
  State<ModelConfigPicker> createState() => _ModelConfigPickerState();
}

class _ModelConfigPickerState extends State<ModelConfigPicker> {
  bool _expanded = false;
  String? _expandedProviderId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ModelConfigProvider>();
    final current = _currentModel(provider.models);
    final currentName = _currentLabel(current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 主选择器按钮，显示当前选中模型或"未选择模型"
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _expanded
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.35)
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
              color: _expanded
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.05)
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.hub_outlined,
                  size: 18,
                  color: current == null
                      ? Theme.of(context).colorScheme.outline
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    currentName ?? widget.emptyLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 允许清空且已有选中值时显示清除按钮
                if (widget.allowClear && widget.value != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => widget.onChanged(null),
                  ),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        ),
        if (_expanded) ...[const SizedBox(height: 4), _modelList(provider)],
      ],
    );
  }

  /// 构建模型列表，按分类和能力过滤后展示。
  Widget _modelList(ModelConfigProvider provider) {
    final models = provider
        .modelsByCategory(widget.category)
        .where(_matchesCapabilities)
        .toList(growable: false);
    if (models.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '没有可用模型',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: models.length,
          itemBuilder: (_, index) {
            final model = models[index];
            final selected = widget.value?.modelId == model.id;
            final expanded = _expandedProviderId == model.id;
            // 过滤启用的子模型并按能力匹配
            final entries = model.models
                .where(
                  (entry) => entry.enabled && _entryMatchesCapabilities(entry),
                )
                .toList(growable: false);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 模型提供者行
                ListTile(
                  dense: true,
                  leading: Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    size: 18,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                  title: Text(
                    model.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    model.hasMultipleModels
                        ? '${entries.length} 个模型'
                        : model.modelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: entries.length > 1
                      ? const Icon(Icons.chevron_right, size: 16)
                      : null,
                  onTap: () {
                    // 多个子模型时展开子列表，否则直接选中
                    if (entries.length > 1) {
                      setState(
                        () => _expandedProviderId = expanded ? null : model.id,
                      );
                      return;
                    }
                    final name = entries.isNotEmpty
                        ? entries.first.name
                        : model.modelName;
                    _select(model, name);
                  },
                ),
                // 展开的子模型列表
                if (expanded)
                  for (final entry in entries)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(
                        left: 56,
                        right: 16,
                      ),
                      leading: Icon(
                        widget.value?.modelId == model.id &&
                                widget.value?.modelName == entry.name
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 14,
                      ),
                      title: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _select(model, entry.name),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 选择模型并关闭面板。
  void _select(ModelConfig model, String modelName) {
    widget.onChanged(
      ModelSelectionValue(
        modelId: model.id,
        modelName: modelName,
        category: widget.category,
      ),
    );
    setState(() {
      _expanded = false;
      _expandedProviderId = null;
    });
  }

  /// 从模型列表中查找当前选中的模型配置。
  ModelConfig? _currentModel(List<ModelConfig> models) {
    final id = widget.value?.modelId;
    if (id == null || id.isEmpty) return null;
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }

  /// 生成当前选择的可读标签，格式为"模型名 / 子模型名"。
  String? _currentLabel(ModelConfig? model) {
    if (model == null) return null;
    final name = widget.value?.modelName;
    if (name == null || name.isEmpty) return model.name;
    return '${model.name} / $name';
  }

  /// 检查模型是否满足所需能力要求。
  bool _matchesCapabilities(ModelConfig model) {
    if (widget.capabilities.isEmpty) return true;
    return model.models.any(
      (entry) => entry.enabled && _entryMatchesCapabilities(entry),
    );
  }

  /// 检查子模型条目是否满足指定能力要求。
  bool _entryMatchesCapabilities(ModelEntry entry) {
    bool has(String capability) {
      return switch (capability) {
        'vision' => entry.supportsVision,
        'thinking' => entry.supportsThinking,
        'tools' => entry.supportsTools,
        _ => true,
      };
    }

    return widget.capabilities.every(has);
  }
}
