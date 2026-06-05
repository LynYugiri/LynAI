import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/model_config.dart';
import '../providers/model_config_provider.dart';

/// A stable plugin-local model selection.
///
/// Unlike the chat page picker, selecting a sub-model here must not mutate the
/// provider's global `modelName`; plugin config stores the chosen provider and
/// sub-model explicitly so plugin behavior stays reproducible.
class ModelSelectionValue {
  final String modelId;
  final String? modelName;
  final String category;

  const ModelSelectionValue({
    required this.modelId,
    required this.modelName,
    required this.category,
  });

  Map<String, dynamic> toJson() => {
    'modelId': modelId,
    if (modelName != null && modelName!.isNotEmpty) 'modelName': modelName,
    'category': category,
  };
}

class ModelConfigPicker extends StatefulWidget {
  final String title;
  final String category;
  final ModelSelectionValue? value;
  final List<String> capabilities;
  final bool allowClear;
  final ValueChanged<ModelSelectionValue?> onChanged;

  const ModelConfigPicker({
    super.key,
    required this.title,
    required this.category,
    required this.value,
    this.capabilities = const [],
    this.allowClear = true,
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
                    currentName ?? '未选择模型',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
            final entries = model.models
                .where(
                  (entry) => entry.enabled && _entryMatchesCapabilities(entry),
                )
                .toList(growable: false);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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

  ModelConfig? _currentModel(List<ModelConfig> models) {
    final id = widget.value?.modelId;
    if (id == null || id.isEmpty) return null;
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }

  String? _currentLabel(ModelConfig? model) {
    if (model == null) return null;
    final name = widget.value?.modelName;
    if (name == null || name.isEmpty) return model.name;
    return '${model.name} / $name';
  }

  bool _matchesCapabilities(ModelConfig model) {
    if (widget.capabilities.isEmpty) return true;
    return model.models.any(
      (entry) => entry.enabled && _entryMatchesCapabilities(entry),
    );
  }

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
