part of '../chat_page.dart';

class _SystemPromptEditDialog extends StatefulWidget {
  final String initialTitle;
  final String initialContent;
  final void Function(String title, String content) onSave;
  final VoidCallback? onDelete;

  const _SystemPromptEditDialog({
    this.initialTitle = '',
    this.initialContent = '',
    required this.onSave,
    this.onDelete,
  });

  @override
  State<_SystemPromptEditDialog> createState() =>
      _SystemPromptEditDialogState();
}

class _RoleEditDialog extends StatefulWidget {
  final ChatRole? initialRole;
  final void Function(
    String name,
    String description,
    String systemPrompt,
    String? modelId,
    Color? themeColor,
    List<String> groupIds,
  )
  onSave;
  final VoidCallback? onDelete;

  const _RoleEditDialog({
    this.initialRole,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<_RoleEditDialog> createState() => _RoleEditDialogState();
}

class _RoleEditDialogState extends State<_RoleEditDialog> {
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
    final models = context.watch<ModelConfigProvider>().modelsByCategory(
      ModelConfig.categoryChat,
    );
    return AlertDialog(
      title: Text(widget.initialRole == null ? '添加角色' : '编辑角色'),
      content: SingleChildScrollView(
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
            DropdownButtonFormField<String?>(
              initialValue: _modelId,
              decoration: const InputDecoration(
                labelText: '模型（可选）',
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('不指定'),
                ),
                ...models.map(
                  (m) => DropdownMenuItem<String?>(
                    value: m.id,
                    child: Text('${m.name} / ${m.modelName}'),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _modelId = v),
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
                              color: _themeColor?.toARGB32() == color.toARGB32()
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
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
              _themeColor,
              _groupIds.toList(),
            );
          },
          child: const Text('保存'),
        ),
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
}

class _SystemPromptEditDialogState extends State<_SystemPromptEditDialog> {
  late final _titleCtrl = TextEditingController(text: widget.initialTitle);
  late final _contentCtrl = TextEditingController(text: widget.initialContent);

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.onDelete != null ? '编辑系统提示词' : '添加系统提示词'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: '标题',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contentCtrl,
            maxLines: 8,
            minLines: 3,
            decoration: const InputDecoration(
              labelText: '系统提示词',
              border: OutlineInputBorder(),
              hintText: 'You are a helpful assistant.',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            final title = _titleCtrl.text.trim();
            final content = _contentCtrl.text.trim();
            if (title.isEmpty || content.isEmpty) return;
            Navigator.pop(context);
            widget.onSave(title, content);
          },
          child: const Text('保存'),
        ),
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
}
