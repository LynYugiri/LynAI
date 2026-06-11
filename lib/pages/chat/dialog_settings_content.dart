part of '../chat_page.dart';

/// 对话设置弹窗内容。
///
/// 整合模型选择器、思维链开关、系统提示词编辑、语音和图片模型配置。
class _DialogSettingsContent extends StatefulWidget {
  final ConversationSettings settings;
  final ValueChanged<ConversationSettings> onChanged;

  const _DialogSettingsContent({
    required this.settings,
    required this.onChanged,
  });

  @override
  State<_DialogSettingsContent> createState() => _DialogSettingsContentState();
}

class _DialogSettingsContentState extends State<_DialogSettingsContent> {
  bool _showSpeechList = false;
  bool _showImageList = false;
  bool _showImageRecognitionList = false;
  bool _showRoleList = false;
  bool _showSystemPromptList = false;
  String? _expandedSpeechId;
  String? _expandedImageId;
  String? _expandedImageRecognitionId;
  late ConversationSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  void _updateSettings(ConversationSettings settings) {
    setState(() => _settings = settings);
    widget.onChanged(settings);
  }

  @override
  Widget build(BuildContext context) {
    final set = context.watch<SettingsProvider>().settings;
    final mp = context.watch<ModelConfigProvider>();
    final speechModel = _settings.speechModelId != null
        ? _findModelConfigById(mp.models, _settings.speechModelId!)
        : null;
    final ocrModel = _settings.imageModelId != null
        ? _findModelConfigById(mp.models, _settings.imageModelId!)
        : null;
    final imageRecognitionModel = _settings.imageRecognitionModelId != null
        ? _findModelConfigById(mp.models, _settings.imageRecognitionModelId!)
        : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollCtrl) => SingleChildScrollView(
        controller: scrollCtrl,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune, size: 22),
                  const SizedBox(width: 8),
                  Text('对话设置', style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                '角色管理',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(() => _showRoleList = !_showRoleList),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _showRoleList
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.3)
                          : Theme.of(
                              context,
                            ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: _showRoleList
                        ? Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.05)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.watch<SettingsProvider>().currentRole.name,
                        ),
                      ),
                      Icon(
                        _showRoleList ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              if (_showRoleList) ...[const SizedBox(height: 4), _roleList(set)],
              const SizedBox(height: 20),
              // 系统提示词
              Text(
                '系统提示词',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(
                  () => _showSystemPromptList = !_showSystemPromptList,
                ),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _showSystemPromptList
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.3)
                          : Theme.of(
                              context,
                            ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: _showSystemPromptList
                        ? Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.05)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _currentSystemPromptLabel(set),
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        _showSystemPromptList
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 18,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ],
                  ),
                ),
              ),
              if (_showSystemPromptList) ...[
                const SizedBox(height: 4),
                _systemPromptList(set),
              ],
              const SizedBox(height: 20),
              Text(
                'Agent 设置',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              _agentSettings(),
              const SizedBox(height: 20),
              // 语音转文字模型
              Text(
                '语音转文字模型',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              _inlineModelPicker(
                mp: mp,
                category: ModelConfig.categorySpeech,
                currentModel: speechModel,
                showList: _showSpeechList,
                expandedId: _expandedSpeechId,
                hint: '未设置（设置后将支持发送语音）',
                icon: Icons.mic,
                onToggle: () => setState(() {
                  _showSpeechList = !_showSpeechList;
                  _showImageList = false;
                  _expandedSpeechId = null;
                }),
                onSelect: (id) {
                  _updateSettings(_settings.copyWith(speechModelId: id));
                  setState(() {
                    _showSpeechList = false;
                    _expandedSpeechId = null;
                  });
                },
                onExpandProvider: (id) {
                  _updateSettings(_settings.copyWith(speechModelId: id));
                  setState(() {
                    _expandedSpeechId = id;
                  });
                },
                onSelectSub: (config, modelName) {
                  final c = config.copyWith(modelName: modelName);
                  context.read<ModelConfigProvider>().updateModel(c);
                  setState(() {
                    _showSpeechList = false;
                    _expandedSpeechId = null;
                  });
                },
                onClear: () {
                  _updateSettings(_settings.copyWith(speechModelId: null));
                  setState(() {
                    _expandedSpeechId = null;
                  });
                },
              ),
              const SizedBox(height: 20),
              // OCR 模型
              Text(
                'OCR 模型',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              _inlineModelPicker(
                mp: mp,
                category: ModelConfig.categoryOcr,
                currentModel: ocrModel,
                showList: _showImageList,
                expandedId: _expandedImageId,
                hint: '未设置（非图片文件将跳过 OCR，仅保留附件信息）',
                icon: Icons.image,
                onToggle: () => setState(() {
                  _showImageList = !_showImageList;
                  _showSpeechList = false;
                  _expandedImageId = null;
                }),
                onSelect: (id) {
                  _updateSettings(_settings.copyWith(imageModelId: id));
                  setState(() {
                    _showImageList = false;
                    _expandedImageId = null;
                  });
                },
                onExpandProvider: (id) {
                  _updateSettings(_settings.copyWith(imageModelId: id));
                  setState(() {
                    _expandedImageId = id;
                  });
                },
                onSelectSub: (config, modelName) {
                  final c = config.copyWith(modelName: modelName);
                  context.read<ModelConfigProvider>().updateModel(c);
                  setState(() {
                    _showImageList = false;
                    _expandedImageId = null;
                  });
                },
                onClear: () {
                  _updateSettings(_settings.copyWith(imageModelId: null));
                  setState(() {
                    _expandedImageId = null;
                  });
                },
              ),
              const SizedBox(height: 16),
              // 文件识别模型
              Text(
                '文件识别模型',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              _inlineModelPicker(
                mp: mp,
                category: ModelConfig.categoryChat,
                currentModel: imageRecognitionModel,
                showList: _showImageRecognitionList,
                expandedId: _expandedImageRecognitionId,
                hint: '未设置（启用文件识别后将用该模型读取附件）',
                icon: Icons.file_present_outlined,
                onToggle: () => setState(() {
                  _showSpeechList = false;
                  _showImageList = false;
                  _showSystemPromptList = false;
                  _showImageRecognitionList = !_showImageRecognitionList;
                  _expandedImageRecognitionId = null;
                }),
                onSelect: (id) {
                  _updateSettings(
                    _settings.copyWith(imageRecognitionModelId: id),
                  );
                  setState(() {
                    _showImageRecognitionList = false;
                    _expandedImageRecognitionId = null;
                  });
                },
                onExpandProvider: (id) {
                  _updateSettings(
                    _settings.copyWith(imageRecognitionModelId: id),
                  );
                  setState(() => _expandedImageRecognitionId = id);
                },
                onSelectSub: (config, modelName) {
                  final c = config.copyWith(modelName: modelName);
                  context.read<ModelConfigProvider>().updateModel(c);
                },
                onClear: () {
                  _updateSettings(
                    _settings.copyWith(imageRecognitionModelId: null),
                  );
                },
                filter: (config) => config.models.any(
                  (entry) => entry.enabled && entry.supportsVision,
                ),
                entryFilter: (entry) => entry.supportsVision,
              ),
              const SizedBox(height: 16),
              // 文件识别提示词
              Text(
                '文件识别提示词',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final result = await _showPromptDialog(
                    context,
                    _settings.imageRecognitionPrompt,
                  );
                  if (result != null && mounted) {
                    _updateSettings(
                      _settings.copyWith(imageRecognitionPrompt: result),
                    );
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _settings.imageRecognitionPrompt,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inlineModelPicker({
    required ModelConfigProvider mp,
    required String category,
    required ModelConfig? currentModel,
    required bool showList,
    required String? expandedId,
    required String hint,
    required IconData icon,
    required VoidCallback onToggle,
    required void Function(String) onSelect,
    required void Function(String) onExpandProvider,
    required void Function(ModelConfig, String) onSelectSub,
    required VoidCallback onClear,
    bool Function(ModelConfig)? filter,
    bool Function(ModelEntry)? entryFilter,
  }) {
    final compact = MediaQuery.sizeOf(context).width < 380;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (currentModel != null)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    compact
                        ? currentModel.name
                        : '${currentModel.name} / ${currentModel.modelName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onClear,
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: showList
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.3)
                    : Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              color: showList
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.05)
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: showList
                      ? Theme.of(context).colorScheme.primary
                      : (currentModel != null
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    currentModel != null ? '已选择：${currentModel.name}' : hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: currentModel != null
                          ? null
                          : Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                Icon(
                  showList ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ],
            ),
          ),
        ),
        if (showList) ...[
          const SizedBox(height: 4),
          _modelSelectList(
            mp,
            category,
            onSelect,
            onSelectSub,
            currentModel?.id,
            expandedId,
            (id) {
              if (id == expandedId) {
                onToggle();
              } else {
                onExpandProvider(id);
              }
            },
            filter,
            entryFilter,
          ),
        ],
      ],
    );
  }

  Widget _modelSelectList(
    ModelConfigProvider mp,
    String category,
    void Function(String) onSelect,
    void Function(ModelConfig, String) onSelectSub,
    String? selectedId,
    String? expandedId,
    void Function(String) onExpandToggle,
    bool Function(ModelConfig)? filter,
    bool Function(ModelEntry)? entryFilter,
  ) {
    final models = mp
        .modelsByCategory(category)
        .where((model) {
          return filter == null || filter(model);
        })
        .toList(growable: false);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: models.length,
          itemBuilder: (_, i) {
            final m = models[i];
            final isSelected = selectedId != null && m.id == selectedId;
            final isExpanded = expandedId != null && m.id == expandedId;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  dense: true,
                  title: Text(
                    m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    m.hasMultipleModels
                        ? '${m.enabledModelNames.length} 个模型'
                        : m.modelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  leading: Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    size: 18,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                  trailing: m.hasMultipleModels
                      ? const Icon(Icons.chevron_right, size: 16)
                      : null,
                  onTap: () {
                    if (m.hasMultipleModels) {
                      onExpandToggle(m.id);
                    } else {
                      onSelect(m.id);
                    }
                  },
                ),
                if (isExpanded && m.hasMultipleModels)
                  ...m.models
                      .where((e) => e.enabled)
                      .where((e) => entryFilter == null || entryFilter(e))
                      .map(
                        (e) => ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.only(left: 56),
                          leading: Icon(
                            e.name == m.modelName
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 14,
                            color: e.name == m.modelName
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                          ),
                          title: Text(
                            e.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                          ),
                          onTap: () => onSelectSub(m, e.name),
                        ),
                      ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<String?> _showPromptDialog(
    BuildContext context,
    String current,
  ) async {
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义提示词'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '请根据下面的文件内容或识别结果回答。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final text = ctrl.text.trim();
              Navigator.pop(ctx, text);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  String _currentSystemPromptLabel(AppSettings set) {
    if (_settings.selectedSystemPromptId != null) {
      try {
        final p = set.systemPrompts.firstWhere(
          (p) => p.id == _settings.selectedSystemPromptId,
        );
        return p.title;
      } catch (_) {}
    }
    return '默认';
  }

  void _closeSystemPromptList() {
    setState(() => _showSystemPromptList = false);
  }

  Widget _systemPromptList(AppSettings set) {
    final prompts = set.systemPrompts;
    final selectedId = _settings.selectedSystemPromptId;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: ListView.builder(
          key: ValueKey('sysprompt_${selectedId ?? 'none'}_${prompts.length}'),
          shrinkWrap: true,
          itemCount: 1 + prompts.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              final sel = selectedId == null;
              return ListTile(
                dense: true,
                leading: Icon(
                  sel ? Icons.check_circle : Icons.circle_outlined,
                  size: 18,
                  color: sel
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
                title: const Text('默认', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  'You are a helpful assistant.',
                  style: TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  _updateSettings(
                    _settings.copyWith(selectedSystemPromptId: null),
                  );
                  _closeSystemPromptList();
                },
              );
            }
            if (i == 1 + prompts.length) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.add,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      '添加系统提示词',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    onTap: () => _addSystemPrompt(),
                  ),
                ],
              );
            }
            final p = prompts[i - 1];
            final sel = p.id == selectedId;
            return ListTile(
              dense: true,
              leading: Icon(
                sel ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: sel
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
              title: Text(p.title, style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                p.content.length > 40
                    ? '${p.content.substring(0, 40)}...'
                    : p.content,
                style: const TextStyle(fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit, size: 18),
                onPressed: () => _editSystemPrompt(p),
              ),
              onTap: () {
                _updateSettings(
                  _settings.copyWith(selectedSystemPromptId: p.id),
                );
                _closeSystemPromptList();
              },
            );
          },
        ),
      ),
    );
  }

  Widget _agentSettings() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          SwitchListTile(
            dense: true,
            value: _settings.agentEnabled,
            title: const Text('启用 Agent 模式'),
            subtitle: const Text('允许模型创建 Plan，并按步骤调用工具完成复杂任务。'),
            onChanged: (value) =>
                _updateSettings(_settings.copyWith(agentEnabled: value)),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Agent 权限（全局）',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          _agentPermissionTile(
            const LynAIPermissionDefinition(
              id: '__info__',
              title: '这些权限对所有对话生效',
              description: '当前开关只决定本对话是否启用 Agent。',
            ),
            informational: true,
          ),
          for (final definition in lynaiPermissionDefinitions)
            _agentPermissionTile(definition),
        ],
      ),
    );
  }

  Widget _agentPermissionTile(
    LynAIPermissionDefinition definition, {
    bool informational = false,
  }) {
    if (informational) {
      return ListTile(
        dense: true,
        title: Text(definition.title),
        subtitle: Text(definition.description),
      );
    }
    final provider = context.watch<SettingsProvider>();
    final permissions = provider.settings.agentGrantedPermissions.toSet();
    return CheckboxListTile(
      dense: true,
      value: permissions.contains(definition.id),
      title: Text(definition.title),
      subtitle: Text(definition.description),
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: (value) {
        if (value == true) {
          permissions.add(definition.id);
        } else {
          permissions.remove(definition.id);
        }
        context.read<SettingsProvider>().replaceSettings(
          provider.settings.copyWith(
            agentGrantedPermissions: LynAIPermissions.agentAssignable
                .where(permissions.contains)
                .toList(growable: false),
          ),
        );
      },
    );
  }

  Widget _roleList(AppSettings set) {
    final roles = set.roles;
    final roleById = {for (final role in roles) role.id: role};
    final groupedIds = set.roleGroups.expand((group) => group.roleIds).toSet();
    final ungrouped = roles
        .where((role) => !groupedIds.contains(role.id))
        .toList(growable: false);
    final selectedGroups = set.roleGroups
        .where((group) => group.roleIds.contains(set.currentRoleId))
        .toList(growable: false);
    final expandedGroupId = selectedGroups.isEmpty
        ? '__ungrouped__'
        : selectedGroups.first.id;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: ListView(
          shrinkWrap: true,
          children: [
            _roleGroupTile(
              id: '__ungrouped__',
              title: '未分组',
              roles: ungrouped,
              currentRoleId: set.currentRoleId,
              initiallyExpanded: expandedGroupId == '__ungrouped__',
            ),
            for (final group in set.roleGroups)
              _roleGroupTile(
                id: group.id,
                title: group.name,
                roles: group.roleIds
                    .map((id) => roleById[id])
                    .whereType<ChatRole>()
                    .toList(growable: false),
                currentRoleId: set.currentRoleId,
                initiallyExpanded: expandedGroupId == group.id,
              ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(
                Icons.add,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                '添加角色',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              onTap: _addRole,
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.manage_accounts_outlined, size: 18),
              title: const Text('完整角色管理'),
              onTap: _openRoleManagement,
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleGroupTile({
    required String id,
    required String title,
    required List<ChatRole> roles,
    required String currentRoleId,
    required bool initiallyExpanded,
  }) {
    return ExpansionTile(
      key: ValueKey('role-group-$id'),
      initiallyExpanded: initiallyExpanded,
      dense: true,
      title: Text(
        '$title · ${roles.length}',
        style: const TextStyle(fontSize: 14),
      ),
      children: roles.isEmpty
          ? [
              ListTile(
                dense: true,
                title: Text(
                  '暂无角色',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ),
            ]
          : roles.map((role) => _roleItem(role, currentRoleId)).toList(),
    );
  }

  Widget _roleItem(ChatRole role, String currentRoleId) {
    final selected = role.id == currentRoleId;
    return ListTile(
      dense: true,
      leading: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        size: 18,
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
      title: Text(role.name),
      subtitle: Text(
        role.description.isNotEmpty ? role.description : role.systemPrompt,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: role.id == ChatRole.defaultId
          ? null
          : IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: () => _editRole(role),
            ),
      onTap: () {
        context.read<SettingsProvider>().selectRole(role.id);
        _updateSettings(_roleConversationSettings(role));
        setState(() => _showRoleList = false);
      },
    );
  }

  ConversationSettings _roleConversationSettings(ChatRole role) {
    return _settings.copyWith(
      modelId: role.modelId ?? _settings.modelId,
      modelName: role.modelName ?? _settings.modelName,
      selectedSystemPromptId: role.id == ChatRole.defaultId ? null : role.id,
      systemPrompt: role.systemPrompt,
    );
  }

  void _addRole() {
    showDialog(
      context: context,
      builder: (ctx) => ChatRoleEditDialog(
        onSave:
            (
              name,
              description,
              prompt,
              modelId,
              modelName,
              themeColor,
              groupIds,
            ) {
              context.read<SettingsProvider>().addRole(
                name: name,
                description: description,
                systemPrompt: prompt,
                modelId: modelId,
                modelName: modelName,
                themeColor: themeColor,
                groupIds: groupIds,
              );
            },
      ),
    );
  }

  void _editRole(ChatRole role) {
    final sp = context.read<SettingsProvider>();
    showDialog(
      context: context,
      builder: (ctx) => ChatRoleEditDialog(
        initialRole: role,
        onSave:
            (
              name,
              description,
              prompt,
              modelId,
              modelName,
              themeColor,
              groupIds,
            ) {
              sp.updateRole(
                id: role.id,
                name: name,
                description: description,
                systemPrompt: prompt,
                modelId: modelId,
                modelName: modelName,
                themeColor: themeColor,
                groupIds: groupIds,
              );
              if (role.id == sp.settings.currentRoleId) {
                _updateSettings(_roleConversationSettings(sp.currentRole));
              }
            },
        onDelete: () => sp.deleteRole(role.id),
      ),
    );
  }

  void _openRoleManagement() {
    setState(() => _showRoleList = false);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RoleManagementPage()),
    );
  }

  void _addSystemPrompt() {
    showDialog(
      context: context,
      builder: (ctx) => _SystemPromptEditDialog(
        onSave: (title, content) {
          final id = context.read<SettingsProvider>().addSystemPrompt(
            title,
            content,
          );
          _updateSettings(_settings.copyWith(selectedSystemPromptId: id));
        },
      ),
    );
  }

  void _editSystemPrompt(SystemPrompt p) {
    final sp = context.read<SettingsProvider>();
    showDialog(
      context: context,
      builder: (ctx) => _SystemPromptEditDialog(
        initialTitle: p.title,
        initialContent: p.content,
        onSave: (title, content) {
          sp.updateSystemPrompt(p.id, title, content);
        },
        onDelete: () {
          sp.deleteSystemPrompt(p.id);
        },
      ),
    );
  }
}
