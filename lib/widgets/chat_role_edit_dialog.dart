import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_role.dart';
import '../models/model_config.dart';
import '../providers/model_config_provider.dart';
import '../providers/settings_provider.dart';

class ChatRoleEditDialog extends StatefulWidget {
  final ChatRole? initialRole;
  final void Function(
    String name,
    String description,
    String systemPrompt,
    String? modelId,
    String? modelName,
    Color? themeColor,
    List<String> groupIds,
  )
  onSave;
  final VoidCallback? onDelete;

  const ChatRoleEditDialog({
    super.key,
    this.initialRole,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<ChatRoleEditDialog> createState() => _ChatRoleEditDialogState();
}

class _ChatRoleEditDialogState extends State<ChatRoleEditDialog> {
  late final _nameCtrl = TextEditingController(
    text: widget.initialRole?.name ?? '',
  );
  late final _descCtrl = TextEditingController(
    text: widget.initialRole?.description ?? '',
  );
  late final _promptCtrl = TextEditingController(
    text: widget.initialRole?.systemPrompt ?? '',
  );
  late String? _modelId = widget.initialRole?.modelId;
  late String? _modelName = widget.initialRole?.modelName;
  late Color? _themeColor = widget.initialRole?.themeColor;
  final Set<String> _groupIds = {};
  bool _groupIdsInitialized = false;

  static const _colors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.indigo,
    Colors.pink,
    Color(0xFF6C5CE7),
    Color(0xFF00B894),
    Color(0xFFE17055),
    Color(0xFF355C7D),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_groupIdsInitialized) return;
    final role = widget.initialRole;
    if (role != null) {
      _groupIds.addAll(
        context
            .read<SettingsProvider>()
            .groupsForRole(role.id)
            .map((e) => e.id),
      );
    }
    _groupIdsInitialized = true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialRole == null ? '添加角色' : '编辑角色'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '角色名称',
                  border: OutlineInputBorder(),
                  hintText: '默认',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '描述',
                  border: OutlineInputBorder(),
                  hintText: '这个角色的用途或风格',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _promptCtrl,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '系统提示词',
                  border: OutlineInputBorder(),
                  hintText: 'You are a helpful assistant.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              _ChatRoleModelSelector(
                modelId: _modelId,
                modelName: _modelName,
                onChanged: (modelId, modelName) => setState(() {
                  _modelId = modelId;
                  _modelName = modelName;
                }),
              ),
              const SizedBox(height: 12),
              _roleGroupSection(context),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '主题配色（可选）',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('无'),
                      selected: _themeColor == null,
                      onSelected: (_) => setState(() => _themeColor = null),
                    ),
                    for (final color in _colors)
                      Tooltip(
                        message:
                            '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => setState(() => _themeColor = color),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    _themeColor?.toARGB32() == color.toARGB32()
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Colors.transparent,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _save, child: const Text('保存')),
        if (widget.onDelete != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onDelete!();
            },
            child: Text('删除', style: TextStyle(color: Colors.red[400])),
          ),
      ],
    );
  }

  Widget _roleGroupSection(BuildContext context) {
    final groups = context.watch<SettingsProvider>().settings.roleGroups;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '分组',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              TextButton.icon(
                onPressed: _createGroup,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (groups.isEmpty)
            Text(
              '暂无分组，可新建后勾选。',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final group in groups)
                  FilterChip(
                    label: Text(group.name),
                    selected: _groupIds.contains(group.id),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _groupIds.add(group.id);
                        } else {
                          _groupIds.remove(group.id);
                        }
                      });
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _createGroup() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建角色分组'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: '分组名称'),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (!mounted || name == null || name.trim().isEmpty) return;
    final id = context.read<SettingsProvider>().addRoleGroup(name);
    if (id.isEmpty) return;
    setState(() => _groupIds.add(id));
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final description = _descCtrl.text.trim();
    final prompt = _promptCtrl.text.trim();
    if (name.isEmpty || prompt.isEmpty) return;
    Navigator.pop(context);
    widget.onSave(
      name,
      description,
      prompt,
      _modelId,
      _modelName,
      _themeColor,
      _groupIds.toList(),
    );
  }
}

class _ChatRoleModelSelector extends StatefulWidget {
  final String? modelId;
  final String? modelName;
  final void Function(String? modelId, String? modelName) onChanged;

  const _ChatRoleModelSelector({
    required this.modelId,
    required this.modelName,
    required this.onChanged,
  });

  @override
  State<_ChatRoleModelSelector> createState() => _ChatRoleModelSelectorState();
}

class _ChatRoleModelSelectorState extends State<_ChatRoleModelSelector> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final models = context.watch<ModelConfigProvider>().modelsByCategory(
      ModelConfig.categoryChat,
    );
    final scheme = Theme.of(context).colorScheme;
    final selected = _selectedModel(models);
    final displayName = widget.modelId == null
        ? '不指定'
        : selected == null
        ? '模型不存在'
        : widget.modelName != null && widget.modelName!.isNotEmpty
        ? '${selected.name} / ${widget.modelName}'
        : '${selected.name} / ${selected.modelName}';
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _expanded
                    ? scheme.primary.withValues(alpha: 0.3)
                    : scheme.outlineVariant.withValues(alpha: 0.35),
              ),
              color: _expanded ? scheme.primary.withValues(alpha: 0.06) : null,
            ),
            child: Row(
              children: [
                Icon(Icons.smart_toy, size: 18, color: scheme.outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '角色模型',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: scheme.outline,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 4),
          Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView(
                shrinkWrap: true,
                children: [
                  _modelRadioTile(
                    title: '不指定',
                    subtitle: '使用对话当前模型',
                    selected: widget.modelId == null,
                    onTap: () => _select(null),
                  ),
                  const Divider(height: 1),
                  for (final model in models) ...[
                    _modelTile(model),
                    if (model.hasMultipleModels &&
                        widget.modelId == model.id &&
                        model.models.any((entry) => entry.enabled))
                      for (final entry in model.models)
                        if (entry.enabled) _subModelTile(model, entry),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  ModelConfig? _selectedModel(List<ModelConfig> models) {
    final id = widget.modelId;
    if (id == null || id.isEmpty) return null;
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }

  Widget _modelRadioTile({
    required String title,
    String? subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        size: 18,
        color: selected ? scheme.primary : scheme.outline,
      ),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(fontSize: 11))
          : null,
      onTap: onTap,
    );
  }

  Widget _modelTile(ModelConfig model) {
    return _modelRadioTile(
      title: model.name,
      subtitle: model.hasMultipleModels
          ? '${model.enabledModelNames.length} 个模型 · 当前 ${model.modelName}'
          : model.modelName,
      selected: widget.modelId == model.id,
      onTap: () {
        final hasSubs =
            model.hasMultipleModels &&
            model.models.any((entry) => entry.enabled);
        if (hasSubs && widget.modelId == model.id) return;
        _select(model.id, model.hasMultipleModels ? model.modelName : null);
      },
    );
  }

  Widget _subModelTile(ModelConfig model, ModelEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    final selected =
        widget.modelId == model.id &&
        (widget.modelName == entry.name ||
            (widget.modelName == null && entry.name == model.modelName));
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 48),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        size: 14,
        color: selected ? scheme.primary : scheme.outline,
      ),
      title: Text(
        entry.name,
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
      ),
      onTap: () => _select(model.id, entry.name),
    );
  }

  void _select(String? modelId, [String? modelName]) {
    widget.onChanged(modelId, modelName);
    setState(() => _expanded = false);
  }
}
