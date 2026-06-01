import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../models/model_config.dart';
import '../providers/conversation_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/settings_provider.dart';

const _endpointPresets = [
  {'name': 'OpenAI', 'url': 'https://api.openai.com/v1', 'type': 'openai'},
  {'name': 'DeepSeek', 'url': 'https://api.deepseek.com', 'type': 'openai'},
  {
    'name': 'Anthropic',
    'url': 'https://api.anthropic.com',
    'type': 'anthropic',
  },
  {
    'name': 'Google AI',
    'url': 'https://generativelanguage.googleapis.com/v1beta/openai',
    'type': 'openai',
  },
  {'name': 'Ollama (本地)', 'url': 'http://localhost:11434', 'type': 'ollama'},
  {
    'name': 'OpenRouter',
    'url': 'https://openrouter.ai/api/v1',
    'type': 'openai',
  },
  {'name': 'Groq', 'url': 'https://api.groq.com/openai/v1', 'type': 'openai'},
  {
    'name': 'Together AI',
    'url': 'https://api.together.xyz/v1',
    'type': 'openai',
  },
  {'name': 'xAI (Grok)', 'url': 'https://api.x.ai/v1', 'type': 'openai'},
  {'name': 'Moonshot', 'url': 'https://api.moonshot.cn/v1', 'type': 'openai'},
  {'name': 'vivo', 'url': 'https://api-ai.vivo.com.cn/v1', 'type': 'openai'},
  {
    'name': 'Zhipu (智谱)',
    'url': 'https://open.bigmodel.cn/api/paas/v4',
    'type': 'openai',
  },
  {
    'name': 'Qwen (通义千问)',
    'url': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    'type': 'openai',
  },
  {
    'name': 'SiliconFlow',
    'url': 'https://api.siliconflow.cn/v1',
    'type': 'openai',
  },
  {'name': '自定义', 'url': '', 'type': 'custom'},
];

const _ocrEndpointPresets = [
  {
    'name': 'vivo OCR',
    'url': 'https://api-ai.vivo.com.cn/ocr/general_recognition',
    'type': ModelConfig.categoryOcr,
  },
  {'name': '自定义', 'url': '', 'type': ModelConfig.categoryOcr},
];

const _speechEndpointPresets = [
  {
    'name': 'vivo 长语音转写',
    'url': 'https://api-ai.vivo.com.cn',
    'type': ModelConfig.categorySpeech,
  },
  {'name': '自定义', 'url': '', 'type': ModelConfig.categorySpeech},
];

const _imageEndpointPresets = [
  {
    'name': 'vivo 图片生成',
    'url': 'https://api-ai.vivo.com.cn/api/v1/image_generation',
    'type': 'vivo_image',
  },
  {
    'name': 'OpenAI Images',
    'url': 'https://api.openai.com/v1',
    'type': 'openai_image',
  },
  {'name': '自定义', 'url': '', 'type': 'openai_image'},
];

const _categories = [
  ApiCategory(
    ModelConfig.categoryChat,
    'Chat',
    '对话模型',
    Icons.chat_bubble_outline,
    Colors.blue,
  ),
  ApiCategory(
    ModelConfig.categoryOcr,
    'OCR',
    '图片文字识别',
    Icons.document_scanner_outlined,
    Colors.deepPurple,
  ),
  ApiCategory(
    ModelConfig.categorySpeech,
    '语音转文字',
    'vivo 长语音转写',
    Icons.mic_none,
    Colors.green,
  ),
  ApiCategory(
    ModelConfig.categoryImageGeneration,
    '图片生成',
    '文本或图片生成图片',
    Icons.auto_awesome,
    Colors.orange,
  ),
];

class ApiCategory {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  const ApiCategory(this.id, this.title, this.subtitle, this.icon, this.color);
}

class ApiModelsPage extends StatelessWidget {
  const ApiModelsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ModelConfigProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('模型类别'), centerTitle: true),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final count = provider.modelsByCategory(category.id).length;
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: category.color.withValues(alpha: 0.1),
                child: Icon(category.icon, color: category.color),
              ),
              title: Text(
                category.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('${category.subtitle} · $count 个配置'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ApiCategoryPage(category: category),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ApiCategoryPage extends StatelessWidget {
  final ApiCategory category;
  const ApiCategoryPage({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ModelConfigProvider>();
    final models = provider.modelsByCategory(category.id);
    return Scaffold(
      appBar: AppBar(title: Text(category.title), centerTitle: true),
      body: models.isEmpty
          ? _buildEmptyState()
          : ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: models.length,
              onReorder: (oldIndex, newIndex) => provider
                  .reorderModelsInCategory(category.id, oldIndex, newIndex),
              buildDefaultDragHandles: false,
              itemBuilder: (context, index) => _buildModelItem(
                context,
                models[index],
                index,
                models.length,
                provider,
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToEditModel(context, provider),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(category.icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '暂无${category.title}配置',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角 + 添加模型',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildModelItem(
    BuildContext context,
    ModelConfig model,
    int index,
    int total,
    ModelConfigProvider provider,
  ) {
    final enabledCount = model.enabledModelNames.length;
    final isInterfaceOnly =
        model.category == ModelConfig.categoryOcr ||
        model.category == ModelConfig.categorySpeech;
    return Card(
      key: ValueKey(model.id),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle, color: Colors.grey),
        ),
        title: Text(
          model.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${model.apiType.toUpperCase()} - ${model.endpoint}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (!isInterfaceOnly && model.hasMultipleModels)
              Text(
                '已启用 $enabledCount / ${model.models.length} 个模型',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _getPriorityColor(index, total).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '优先级 ${index + 1}',
                style: TextStyle(
                  fontSize: 11,
                  color: _getPriorityColor(index, total),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
        onTap: () => _navigateToEditModel(context, provider, model: model),
      ),
    );
  }

  Color _getPriorityColor(int index, int total) {
    if (total <= 1) return Colors.grey;
    final ratio = index / (total - 1);
    if (ratio < 0.33) return Colors.green;
    if (ratio < 0.66) return Colors.orange;
    return Colors.red;
  }

  void _navigateToEditModel(
    BuildContext context,
    ModelConfigProvider provider, {
    ModelConfig? model,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EditModelPage(category: category, model: model, provider: provider),
      ),
    );
  }
}

class EditModelPage extends StatefulWidget {
  final ApiCategory category;
  final ModelConfig? model;
  final ModelConfigProvider provider;
  const EditModelPage({
    super.key,
    required this.category,
    this.model,
    required this.provider,
  });

  @override
  State<EditModelPage> createState() => _EditModelPageState();
}

class _EditModelPageState extends State<EditModelPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController,
      _endpointController,
      _apiKeyController,
      _appIdController;
  late TextEditingController _newModelController;
  late List<ModelEntry> _modelEntries;
  String _apiType = 'openai';
  bool _obscureApiKey = true;
  bool _showEndpointSuggestions = false;
  bool _isFetchingModels = false;
  bool _saved = false;
  bool _closing = false;
  List<Map<String, dynamic>> _filteredPresets = [];

  bool get isEditing => widget.model != null;
  bool get isChat => widget.category.id == ModelConfig.categoryChat;
  bool get isImageGeneration =>
      widget.category.id == ModelConfig.categoryImageGeneration;
  bool get needsAppId =>
      widget.category.id == ModelConfig.categoryOcr ||
      widget.category.id == ModelConfig.categorySpeech;
  bool get isInterfaceOnly =>
      widget.category.id == ModelConfig.categoryOcr ||
      widget.category.id == ModelConfig.categorySpeech;
  bool get hasChatStyleOptions => isChat || isImageGeneration;

  @override
  void initState() {
    super.initState();
    final model = widget.model;
    _nameController = TextEditingController(
      text: model?.name ?? _defaultName(),
    );
    _endpointController = TextEditingController(text: model?.endpoint ?? '');
    _apiKeyController = TextEditingController(text: model?.apiKey ?? '');
    _appIdController = TextEditingController(
      text: model?.extraParams['appId'] as String? ?? '',
    );
    _newModelController = TextEditingController();
    _apiType =
        model?.apiType ??
        (isChat
            ? 'openai'
            : isImageGeneration
            ? 'openai_image'
            : widget.category.id);
    _modelEntries =
        model?.models.toList() ?? [ModelEntry(name: '', enabled: false)];
    _filteredPresets = List.from(_currentEndpointPresets);
  }

  String _defaultName() => '';

  String _endpointHint() {
    return switch (widget.category.id) {
      ModelConfig.categoryOcr =>
        'https://api-ai.vivo.com.cn/ocr/general_recognition',
      ModelConfig.categorySpeech => 'https://api-ai.vivo.com.cn',
      ModelConfig.categoryImageGeneration =>
        'https://api-ai.vivo.com.cn/api/v1/image_generation 或 https://api.openai.com/v1',
      _ => 'https://api.openai.com/v1',
    };
  }

  List<Map<String, dynamic>> get _currentEndpointPresets {
    return switch (widget.category.id) {
      ModelConfig.categoryOcr => _ocrEndpointPresets,
      ModelConfig.categorySpeech => _speechEndpointPresets,
      ModelConfig.categoryImageGeneration => _imageEndpointPresets,
      _ => _endpointPresets,
    };
  }

  String get _fixedInterfaceModelName {
    return switch (widget.category.id) {
      ModelConfig.categoryOcr => 'general_recognition',
      ModelConfig.categorySpeech => 'fileasrrecorder',
      _ => '',
    };
  }

  @override
  void dispose() {
    _nameController.dispose();
    _endpointController.dispose();
    _apiKeyController.dispose();
    _appIdController.dispose();
    _newModelController.dispose();
    super.dispose();
  }

  bool _saveModel() {
    if (!_formKey.currentState!.validate()) return false;
    final entries = isInterfaceOnly
        ? [ModelEntry(name: _fixedInterfaceModelName, enabled: true)]
        : _modelEntries.where((m) => m.name.trim().isNotEmpty).toList();
    if (!isInterfaceOnly && entries.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少添加一个模型')));
      return false;
    }
    final enabled = entries.where((m) => m.enabled).toList();
    if (hasChatStyleOptions && enabled.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少启用一个模型')));
      return false;
    }
    final previousModelName = widget.model?.modelName;
    String? preservedActive;
    if (previousModelName != null) {
      for (final entry in enabled) {
        if (entry.name == previousModelName) {
          preservedActive = entry.name;
          break;
        }
      }
    }
    final activeModelName =
        preservedActive ??
        (enabled.isNotEmpty ? enabled.first.name : entries.first.name);
    final config = ModelConfig(
      id: widget.model?.id ?? widget.provider.generateId(),
      name: _nameController.text.trim(),
      category: widget.category.id,
      endpoint: _endpointController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      modelName: activeModelName,
      apiType: _apiType,
      priority:
          widget.model?.priority ??
          widget.provider.nextPriorityForCategory(widget.category.id),
      maxTokens: null,
      temperature: null,
      topP: null,
      extraParams: needsAppId
          ? {'appId': _appIdController.text.trim()}
          : widget.model?.extraParams,
      models: entries,
    );
    if (isEditing) {
      widget.provider.updateModel(config);
    } else {
      widget.provider.addModel(config);
    }
    context.read<SettingsProvider>().repairMediaModelSelections(
      widget.provider.models,
    );
    context.read<ConversationProvider>().repairModelReferences(
      widget.provider.models,
    );
    _saved = true;
    _closeNow();
    return true;
  }

  void _closeNow() {
    if (!mounted) return;
    setState(() => _closing = true);
    Navigator.pop(context);
  }

  Future<void> _attemptClose() async {
    if (_saved || !_hasUnsavedChanges) {
      _closeNow();
      return;
    }
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('保存更改？'),
        content: const Text('当前模型配置还没有保存，退出前是否保存？'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('不保存'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'discard') {
      _saved = true;
      _closeNow();
      return;
    }
    _saveModel();
  }

  bool get _hasUnsavedChanges {
    final original = widget.model;
    final currentEntries = isInterfaceOnly
        ? [ModelEntry(name: _fixedInterfaceModelName, enabled: true)]
        : _modelEntries.where((m) => m.name.trim().isNotEmpty).toList();
    if (original == null) {
      return _nameController.text.trim().isNotEmpty ||
          _endpointController.text.trim().isNotEmpty ||
          _apiKeyController.text.trim().isNotEmpty ||
          _appIdController.text.trim().isNotEmpty ||
          _apiType != _defaultApiType ||
          (!isInterfaceOnly && currentEntries.isNotEmpty);
    }
    final originalAppId = original.extraParams['appId'] as String? ?? '';
    return _nameController.text.trim() != original.name ||
        _endpointController.text.trim() != original.endpoint ||
        _apiKeyController.text.trim() != original.apiKey ||
        _appIdController.text.trim() != originalAppId ||
        _apiType != original.apiType ||
        !_sameModelEntries(currentEntries, original.models);
  }

  String get _defaultApiType => isChat
      ? 'openai'
      : isImageGeneration
      ? 'openai_image'
      : widget.category.id;

  bool _sameModelEntries(List<ModelEntry> a, List<ModelEntry> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (jsonEncode(a[i].toJson()) != jsonEncode(b[i].toJson())) return false;
    }
    return true;
  }

  void _addModelEntry() {
    final name = _newModelController.text.trim();
    if (name.isEmpty || _modelEntries.any((m) => m.name == name)) return;
    setState(() {
      _modelEntries.add(ModelEntry(name: name, enabled: true));
      _newModelController.clear();
    });
  }

  void _removeModelEntry(int index) =>
      setState(() => _modelEntries.removeAt(index));

  void _toggleModelEntry(int index) {
    setState(
      () => _modelEntries[index] = _modelEntries[index].copyWith(
        enabled: !_modelEntries[index].enabled,
      ),
    );
  }

  void _selectEndpointPreset(Map<String, dynamic> preset) {
    _endpointController.text = preset['url'] as String;
    if (preset['type'] != 'custom' && hasChatStyleOptions) {
      setState(() => _apiType = preset['type'] as String);
    }
    setState(() => _showEndpointSuggestions = false);
  }

  void _filterEndpointPresets(String query) {
    setState(() {
      _filteredPresets = query.isEmpty
          ? List.from(_currentEndpointPresets)
          : _currentEndpointPresets
                .where(
                  (p) =>
                      (p['name'] as String).toLowerCase().contains(
                        query.toLowerCase(),
                      ) ||
                      (p['url'] as String).toLowerCase().contains(
                        query.toLowerCase(),
                      ),
                )
                .toList();
    });
  }

  Future<void> _fetchModels() async {
    final endpoint = _endpointController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    if (endpoint.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先填写 Endpoint')));
      return;
    }
    setState(() => _isFetchingModels = true);
    try {
      List<ModelEntry> fetched = [];
      if (_apiType == 'ollama') {
        final resp = await http.get(Uri.parse('$endpoint/api/tags'));
        if (resp.statusCode != 200) throw Exception('${resp.statusCode}');
        final models = jsonDecode(resp.body)['models'] as List;
        fetched = models.map((m) {
          final rawName = m['name'] as String;
          final name = rawName.endsWith(':latest')
              ? rawName.substring(0, rawName.length - ':latest'.length)
              : rawName;
          return ModelEntry(name: name, enabled: false);
        }).toList();
      } else {
        final headers = <String, String>{};
        if (apiKey.isNotEmpty) headers['Authorization'] = 'Bearer $apiKey';
        final resp = await http.get(
          Uri.parse('$endpoint/models'),
          headers: headers,
        );
        if (resp.statusCode != 200) throw Exception('${resp.statusCode}');
        final models = jsonDecode(resp.body)['data'] as List? ?? [];
        fetched = models
            .map((m) => ModelEntry(name: m['id'] as String, enabled: false))
            .toList();
      }
      final existingNames = _modelEntries.map((e) => e.name).toSet();
      final newEntries = fetched
          .where((e) => !existingNames.contains(e.name))
          .toList();
      if (!mounted) return;
      setState(() => _modelEntries.addAll(newEntries));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newEntries.isNotEmpty
                ? '新增 ${newEntries.length} 个模型'
                : '没有新模型，已全部存在',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('获取模型列表失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isFetchingModels = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final apiKeyOptional = isChat && _apiType == 'ollama';
    final apiKeyLabel = needsAppId ? 'AppKey' : 'API Key';
    return PopScope(
      canPop: _closing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _attemptClose();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _attemptClose,
          ),
          title: Text(
            isEditing
                ? '编辑${widget.category.title}'
                : '添加${widget.category.title}',
          ),
          centerTitle: true,
          actions: [
            if (isEditing)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                tooltip: '删除模型',
                onPressed: () => _confirmDelete(),
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '模型提供商名称',
                    hintText: '例如：DeepSeek',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.label),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入名称' : null,
                ),
                const SizedBox(height: 16),
                if (hasChatStyleOptions) ...[
                  _apiTypeField(),
                  const SizedBox(height: 16),
                ],
                _endpointField(),
                const SizedBox(height: 16),
                if (needsAppId) ...[
                  TextFormField(
                    controller: _appIdController,
                    decoration: const InputDecoration(
                      labelText: 'AppID',
                      hintText: '例如：123456',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入 AppID' : null,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _apiKeyController,
                  decoration: InputDecoration(
                    labelText: apiKeyLabel,
                    hintText: apiKeyOptional ? '可选（Ollama 无需 Key）' : 'sk-...',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.key),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureApiKey
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _obscureApiKey = !_obscureApiKey),
                    ),
                  ),
                  obscureText: _obscureApiKey,
                  validator: apiKeyOptional
                      ? null
                      : (v) => (v == null || v.trim().isEmpty)
                            ? '请输入 $apiKeyLabel'
                            : null,
                ),
                const SizedBox(height: 16),
                if (isChat)
                  OutlinedButton.icon(
                    onPressed: _isFetchingModels ? null : _fetchModels,
                    icon: _isFetchingModels
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: Text(
                      _isFetchingModels ? '获取中...' : '从 Endpoint 获取模型列表',
                    ),
                  ),
                if (isChat) const SizedBox(height: 12),
                if (!isInterfaceOnly) _modelList(),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _saveModel,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    isEditing ? '保存修改' : '添加模型',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _apiTypeField() {
    return DropdownButtonFormField<String>(
      key: ValueKey('apiType_$_apiType'),
      initialValue: _apiType,
      decoration: const InputDecoration(
        labelText: 'API 类型',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.category),
      ),
      items:
          (isImageGeneration
                  ? [
                      {'value': 'openai_image', 'label': 'OpenAI 格式'},
                      {'value': 'vivo_image', 'label': 'vivo 原生'},
                      {'value': 'custom', 'label': 'Custom'},
                    ]
                  : [
                      {'value': 'openai', 'label': 'OpenAI 兼容'},
                      {'value': 'ollama', 'label': 'Ollama'},
                      {'value': 'anthropic', 'label': 'Anthropic'},
                      {'value': 'custom', 'label': 'Custom'},
                    ])
              .map(
                (t) => DropdownMenuItem(
                  value: t['value'],
                  child: Text(t['label']!),
                ),
              )
              .toList(),
      onChanged: (v) {
        if (v != null) setState(() => _apiType = v);
      },
    );
  }

  Widget _endpointField() {
    return Column(
      children: [
        TextFormField(
          controller: _endpointController,
          decoration: InputDecoration(
            labelText: 'Endpoint',
            hintText: _endpointHint(),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.link),
            suffixIcon: IconButton(
              icon: Icon(
                _showEndpointSuggestions
                    ? Icons.expand_less
                    : Icons.expand_more,
              ),
              onPressed: _toggleEndpointSuggestions,
            ),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? '请输入 Endpoint' : null,
          onChanged: (v) {
            if (_showEndpointSuggestions) _filterEndpointPresets(v);
          },
          onTap: _toggleEndpointSuggestionsOnTap,
        ),
        if (_showEndpointSuggestions) _endpointSuggestions(),
      ],
    );
  }

  void _toggleEndpointSuggestions() {
    setState(() {
      _showEndpointSuggestions = !_showEndpointSuggestions;
      if (_showEndpointSuggestions) {
        _filterEndpointPresets(_endpointController.text);
      }
    });
  }

  void _toggleEndpointSuggestionsOnTap() {
    setState(() {
      _showEndpointSuggestions = true;
      _filterEndpointPresets(_endpointController.text);
    });
  }

  Widget _endpointSuggestions() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _filteredPresets.length,
        itemBuilder: (ctx, i) {
          final p = _filteredPresets[i];
          return ListTile(
            dense: true,
            leading: Icon(
              p['type'] == 'ollama' ? Icons.computer : Icons.cloud,
              size: 18,
              color: Colors.grey[600],
            ),
            title: Text(
              p['name'] as String,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              p['url'] as String,
              style: const TextStyle(fontSize: 11),
            ),
            onTap: () => _selectEndpointPreset(p),
          );
        },
      ),
    );
  }

  Widget _modelList() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.list_alt, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                const Text(
                  '模型列表',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Text(
                  '已启用 ${_modelEntries.where((m) => m.enabled).length} / ${_modelEntries.where((m) => m.name.isNotEmpty).length}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_modelEntries.where((m) => m.name.isNotEmpty).isNotEmpty)
            ..._modelEntries
                .asMap()
                .entries
                .where((e) => e.value.name.isNotEmpty)
                .map((e) {
                  final idx = e.key;
                  final entry = e.value;
                  return ListTile(
                    dense: true,
                    title: Text(
                      entry.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontFamily: 'monospace',
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isChat)
                          IconButton(
                            tooltip: '模型设置',
                            icon: const Icon(Icons.settings_outlined, size: 17),
                            onPressed: () => _editModelEntry(idx),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                          ),
                        Switch(
                          value: entry.enabled,
                          onChanged: (_) => _toggleModelEntry(idx),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => _removeModelEntry(idx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newModelController,
                    decoration: const InputDecoration(
                      hintText: '输入模型名称，回车添加',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) => _addModelEntry(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _addModelEntry,
                  icon: const Icon(Icons.add_circle, color: Colors.blue),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editModelEntry(int index) async {
    final entry = _modelEntries[index];
    final maxTokens = TextEditingController(
      text: entry.maxTokens?.toString() ?? '',
    );
    final temperature = TextEditingController(
      text: entry.temperature?.toString() ?? '',
    );
    final topP = TextEditingController(text: entry.topP?.toString() ?? '');
    var supportsVision = entry.supportsVision;
    var supportsThinking = entry.supportsThinking;
    var supportsTools = entry.supportsTools;
    final result = await showDialog<ModelEntry>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(entry.name),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('视觉'),
                  subtitle: const Text('可用于图片/文件识别和视觉输入'),
                  value: supportsVision,
                  onChanged: (v) => setDialog(() => supportsVision = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('思考'),
                  subtitle: const Text('发送 thinking/reasoning 相关参数'),
                  value: supportsThinking,
                  onChanged: (v) => setDialog(() => supportsThinking = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('工具使用'),
                  subtitle: const Text('OpenAI 格式下发送 tools/tool_choice'),
                  value: supportsTools,
                  onChanged: (v) => setDialog(() => supportsTools = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: maxTokens,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Max Tokens',
                    hintText: '留空使用服务默认值',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: temperature,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Temperature',
                    hintText: '留空使用服务默认值',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: topP,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Top P',
                    hintText: '留空使用服务默认值',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                ctx,
                entry.copyWith(
                  supportsVision: supportsVision,
                  supportsThinking: supportsThinking,
                  supportsTools: supportsTools,
                  maxTokens: int.tryParse(maxTokens.text.trim()),
                  temperature: double.tryParse(temperature.text.trim()),
                  topP: double.tryParse(topP.text.trim()),
                ),
              ),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    maxTokens.dispose();
    temperature.dispose();
    topP.dispose();
    if (result == null || !mounted) return;
    setState(() => _modelEntries[index] = result);
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('确定要删除"${widget.model!.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              widget.provider.deleteModel(widget.model!.id);
              context.read<SettingsProvider>().repairMediaModelSelections(
                widget.provider.models,
              );
              context.read<ConversationProvider>().repairModelReferences(
                widget.provider.models,
              );
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
