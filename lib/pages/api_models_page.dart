import 'dart:convert';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../models/model_config.dart';
import '../providers/conversation_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/settings_provider.dart';
import '../services/backend_client.dart';
import '../widgets/text_editing_controller_host.dart';

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
    'type': 'vivo_ocr',
  },
  {'name': '自定义', 'url': '', 'type': 'custom'},
];

const _speechEndpointPresets = [
  {
    'name': 'vivo 长语音转写',
    'url': 'https://api-ai.vivo.com.cn',
    'type': 'vivo_lasr',
  },
  {'name': '自定义', 'url': '', 'type': 'custom'},
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
              onReorderItem: (oldIndex, newIndex) => provider
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
        subtitle: model.managed
            ? null
            : Column(
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
  final _scrollController = ScrollController();
  final _advancedOptionsKey = GlobalKey();
  late TextEditingController _nameController,
      _endpointController,
      _apiKeyController,
      _appIdController,
      _maxTokensController,
      _temperatureController,
      _topPController,
      _presencePenaltyController,
      _frequencyPenaltyController,
      _seedController,
      _stopController,
      _userController;
  late TextEditingController _newModelController;
  late List<ModelEntry> _modelEntries;
  String _apiType = 'openai';
  bool _obscureApiKey = true;
  bool _showEndpointSuggestions = false;
  bool _isFetchingModels = false;
  bool _showAdvancedOptions = false;
  bool _debugSse = false;
  bool _saved = false;
  bool _closing = false;
  bool _refreshingManaged = false;
  bool _cloudSyncEnabled = false;
  ModelConfig? _managedDisplayModel;
  List<Map<String, dynamic>> _filteredPresets = [];

  bool get isEditing => widget.model != null;
  bool get _isManaged => widget.model?.managed == true;
  ModelConfig get _managedModel => _managedDisplayModel ?? widget.model!;
  bool get isChat => widget.category.id == ModelConfig.categoryChat;
  bool get isImageGeneration =>
      widget.category.id == ModelConfig.categoryImageGeneration;
  bool get isSpeech => widget.category.id == ModelConfig.categorySpeech;
  bool get isOcr => widget.category.id == ModelConfig.categoryOcr;
  bool get needsAppId =>
      widget.category.id == ModelConfig.categoryOcr ||
      widget.category.id == ModelConfig.categorySpeech;
  bool get isInterfaceOnly =>
      widget.category.id == ModelConfig.categoryOcr ||
      widget.category.id == ModelConfig.categorySpeech;
  bool get hasChatStyleOptions => true;
  bool get _isOpenAICompatible => _apiType == 'openai' || _apiType == 'custom';

  @override
  void initState() {
    super.initState();
    final model = widget.model;
    if (model?.managed == true) {
      _managedDisplayModel = model;
    }
    _nameController = TextEditingController(
      text: model?.name ?? _defaultName(),
    );
    _endpointController = TextEditingController(text: model?.endpoint ?? '');
    _apiKeyController = TextEditingController(text: model?.apiKey ?? '');
    _appIdController = TextEditingController(
      text: model?.extraParams['appId'] as String? ?? '',
    );
    _maxTokensController = TextEditingController(
      text: model?.maxTokens?.toString() ?? '',
    );
    _temperatureController = TextEditingController(
      text: model?.temperature?.toString() ?? '',
    );
    _topPController = TextEditingController(
      text: model?.topP?.toString() ?? '',
    );
    _presencePenaltyController = TextEditingController(
      text: model?.extraParams['presence_penalty']?.toString() ?? '',
    );
    _frequencyPenaltyController = TextEditingController(
      text: model?.extraParams['frequency_penalty']?.toString() ?? '',
    );
    _seedController = TextEditingController(
      text: model?.extraParams['seed']?.toString() ?? '',
    );
    _stopController = TextEditingController(
      text: (model?.extraParams['stop'] as List<dynamic>?)?.join('\n') ?? '',
    );
    _userController = TextEditingController(
      text: model?.extraParams['user'] as String? ?? '',
    );
    _debugSse = model?.extraParams['debugSse'] == true;
    _showAdvancedOptions = _debugSse;
    _newModelController = TextEditingController();
    _apiType = model?.apiType ?? _defaultApiType;
    _cloudSyncEnabled = model?.cloudSyncEnabled ?? false;
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
    _scrollController.dispose();
    _nameController.dispose();
    _endpointController.dispose();
    _apiKeyController.dispose();
    _appIdController.dispose();
    _maxTokensController.dispose();
    _temperatureController.dispose();
    _topPController.dispose();
    _presencePenaltyController.dispose();
    _frequencyPenaltyController.dispose();
    _seedController.dispose();
    _stopController.dispose();
    _userController.dispose();
    _newModelController.dispose();
    super.dispose();
  }

  bool _saveModel() {
    if (_isManaged) return false;
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
    final extraParams = _buildExtraParams();
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
      maxTokens: int.tryParse(_maxTokensController.text.trim()),
      temperature: double.tryParse(_temperatureController.text.trim()),
      topP: double.tryParse(_topPController.text.trim()),
      extraParams: extraParams,
      models: entries,
      cloudSyncEnabled: _cloudSyncEnabled,
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
    if (_isManaged) return false;
    final original = widget.model;
    final currentEntries = isInterfaceOnly
        ? [ModelEntry(name: _fixedInterfaceModelName, enabled: true)]
        : _modelEntries.where((m) => m.name.trim().isNotEmpty).toList();
    if (original == null) {
      return _nameController.text.trim().isNotEmpty ||
          _endpointController.text.trim().isNotEmpty ||
          _apiKeyController.text.trim().isNotEmpty ||
          _appIdController.text.trim().isNotEmpty ||
          _maxTokensController.text.trim().isNotEmpty ||
          _temperatureController.text.trim().isNotEmpty ||
          _topPController.text.trim().isNotEmpty ||
          _presencePenaltyController.text.trim().isNotEmpty ||
          _frequencyPenaltyController.text.trim().isNotEmpty ||
          _seedController.text.trim().isNotEmpty ||
          _stopController.text.trim().isNotEmpty ||
          _userController.text.trim().isNotEmpty ||
          _debugSse ||
          _cloudSyncEnabled ||
          _apiType != _defaultApiType ||
          (!isInterfaceOnly && currentEntries.isNotEmpty);
    }
    final originalAppId = original.extraParams['appId'] as String? ?? '';
    final originalDebugSse = original.extraParams['debugSse'] == true;
    return _nameController.text.trim() != original.name ||
        _endpointController.text.trim() != original.endpoint ||
        _apiKeyController.text.trim() != original.apiKey ||
        _appIdController.text.trim() != originalAppId ||
        _debugSse != originalDebugSse ||
        _cloudSyncEnabled != original.cloudSyncEnabled ||
        _apiType != original.apiType ||
        !_sameModelEntries(currentEntries, original.models) ||
        (_maxTokensController.text.trim() !=
            (original.maxTokens?.toString() ?? '')) ||
        (_temperatureController.text.trim() !=
            (original.temperature?.toString() ?? '')) ||
        (_topPController.text.trim() != (original.topP?.toString() ?? '')) ||
        _extraFieldChanged(
          original,
          'presence_penalty',
          _presencePenaltyController,
        ) ||
        _extraFieldChanged(
          original,
          'frequency_penalty',
          _frequencyPenaltyController,
        ) ||
        _extraIntFieldChanged(original, 'seed', _seedController) ||
        _stopFieldChanged(original) ||
        (_userController.text.trim() !=
            (original.extraParams['user'] as String? ?? ''));
  }

  bool _extraFieldChanged(
    ModelConfig original,
    String key,
    TextEditingController controller,
  ) {
    final origValue = original.extraParams[key];
    final text = controller.text.trim();
    if (text.isEmpty) return origValue != null;
    final parsed = double.tryParse(text);
    if (parsed == null) return origValue != null;
    return parsed != (origValue as num?)?.toDouble();
  }

  bool _extraIntFieldChanged(
    ModelConfig original,
    String key,
    TextEditingController controller,
  ) {
    final origValue = original.extraParams[key];
    final text = controller.text.trim();
    if (text.isEmpty) return origValue != null;
    final parsed = int.tryParse(text);
    if (parsed == null) return origValue != null;
    return parsed != (origValue as num?)?.toInt();
  }

  bool _stopFieldChanged(ModelConfig original) {
    final origList =
        (original.extraParams['stop'] as List<dynamic>?) ?? const [];
    final current = const LineSplitter()
        .convert(_stopController.text.trim())
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return !listEquals(current, origList);
  }

  Map<String, dynamic> _buildExtraParams() {
    final extra = Map<String, dynamic>.from(
      widget.model?.extraParams ?? const {},
    );
    final appId = _appIdController.text.trim();
    if (needsAppId) {
      if (appId.isNotEmpty) {
        extra['appId'] = appId;
      } else {
        extra.remove('appId');
      }
    } else {
      extra.remove('appId');
    }
    if (isChat && _debugSse) {
      extra['debugSse'] = true;
    } else {
      extra.remove('debugSse');
    }
    if (_isOpenAICompatible) {
      _writeExtraNumber(extra, 'presence_penalty', _presencePenaltyController);
      _writeExtraNumber(
        extra,
        'frequency_penalty',
        _frequencyPenaltyController,
      );
      _writeExtraNumber(extra, 'seed', _seedController, isInt: true);
      final stopText = _stopController.text.trim();
      if (stopText.isNotEmpty) {
        extra['stop'] = const LineSplitter()
            .convert(stopText)
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      } else {
        extra.remove('stop');
      }
      final userText = _userController.text.trim();
      if (userText.isNotEmpty) {
        extra['user'] = userText;
      } else {
        extra.remove('user');
      }
    } else {
      extra.remove('presence_penalty');
      extra.remove('frequency_penalty');
      extra.remove('seed');
      extra.remove('stop');
      extra.remove('user');
    }
    return extra;
  }

  void _writeExtraNumber(
    Map<String, dynamic> extra,
    String key,
    TextEditingController controller, {
    bool isInt = false,
  }) {
    final text = controller.text.trim();
    if (text.isEmpty) {
      extra.remove(key);
      return;
    }
    final value = isInt ? int.tryParse(text) : double.tryParse(text);
    if (value != null) {
      extra[key] = value;
    } else {
      extra.remove(key);
    }
  }

  String get _defaultApiType => isChat
      ? 'openai'
      : isImageGeneration
      ? 'openai_image'
      : isSpeech
      ? 'openai_speech'
      : isOcr
      ? 'vivo_ocr'
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
      final normalizedEndpoint = _normalizeEndpoint(endpoint);
      if (_apiType == 'ollama') {
        final resp = await http
            .get(Uri.parse('$normalizedEndpoint/api/tags'))
            .timeout(const Duration(seconds: 20));
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
        final resp = await http
            .get(Uri.parse('$normalizedEndpoint/models'), headers: headers)
            .timeout(const Duration(seconds: 20));
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

  String _normalizeEndpoint(String endpoint) {
    return endpoint.endsWith('/')
        ? endpoint.substring(0, endpoint.length - 1)
        : endpoint;
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
            if (isEditing && !_isManaged)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                tooltip: '删除模型',
                onPressed: () => _confirmDelete(),
              ),
          ],
        ),
        body: SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isManaged)
                  _managedProviderDetails()
                else ...[
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
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('同步此 Provider 的非秘密配置'),
                    subtitle: const Text(
                      '默认关闭。本地/LAN/Ollama 地址也只有明确开启后才会跨设备同步；API Key 永不上传。',
                    ),
                    value: _cloudSyncEnabled,
                    onChanged: (value) =>
                        setState(() => _cloudSyncEnabled = value),
                  ),
                  const SizedBox(height: 8),
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
                  if (isChat) ...[
                    _advancedOptionsSection(),
                    const SizedBox(height: 12),
                  ],
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _managedProviderDetails() {
    final model = _managedModel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_done_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  model.disabledByUser
                      ? '此服务端模型已在本机关闭。服务端仍会同步基线配置，但本机不会优先使用它。'
                      : 'LynAI 由已登录的后端自动同步，接口地址和鉴权信息不需要手动配置；本机覆盖项优先级高于服务端。',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _managedInfoRow('名称', model.name),
        const SizedBox(height: 12),
        _managedInfoRow('API 类型', model.apiType.toUpperCase()),
        const SizedBox(height: 12),
        _managedInfoRow('分类', _categoryTitle(model.category)),
        const SizedBox(height: 16),
        _managedOverridesEditor(model),
        const SizedBox(height: 16),
        _managedModelList(model),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () {
            widget.provider.setManagedDisabled(model.id, !model.disabledByUser);
            setState(() {
              _managedDisplayModel = model.copyWith(
                disabledByUser: !model.disabledByUser,
              );
            });
          },
          icon: Icon(model.disabledByUser ? Icons.toggle_on : Icons.toggle_off),
          label: Text(model.disabledByUser ? '在本机启用' : '在本机关闭'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _refreshingManaged ? null : _refreshManagedModels,
          icon: _refreshingManaged
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: Text(_refreshingManaged ? '刷新中...' : '刷新模型列表'),
        ),
      ],
    );
  }

  Widget _managedOverridesEditor(ModelConfig model) {
    final disabled = model.disabledByUser;
    return Opacity(
      opacity: disabled ? 0.62 : 1,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withValues(alpha: 0.28)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  const Icon(Icons.tune, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '本机覆盖参数',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (model.userOverrides.isNotEmpty)
                    TextButton(
                      onPressed: disabled
                          ? null
                          : () => _clearManagedOverrides(model),
                      child: const Text('全部清除'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                disabled ? '本机已关闭时不会应用覆盖项。' : '留空表示使用服务端下发值。',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            _managedNumericOverrideTile(
              model,
              keyName: 'maxTokens',
              title: 'Max Tokens',
              fallback: model.activeEntry?.maxTokens ?? model.maxTokens,
              integer: true,
              disabled: disabled,
            ),
            _managedNumericOverrideTile(
              model,
              keyName: 'temperature',
              title: 'Temperature',
              fallback: model.activeEntry?.temperature ?? model.temperature,
              disabled: disabled,
            ),
            _managedNumericOverrideTile(
              model,
              keyName: 'topP',
              title: 'Top P',
              fallback: model.activeEntry?.topP ?? model.topP,
              disabled: disabled,
            ),
            const Divider(height: 1),
            _managedBoolOverrideTile(
              model,
              keyName: 'supportsVision',
              title: '视觉能力',
              fallback: model.activeEntry?.supportsVision ?? true,
              disabled: disabled,
            ),
            _managedBoolOverrideTile(
              model,
              keyName: 'supportsThinking',
              title: '思考输出',
              fallback: model.activeEntry?.supportsThinking ?? true,
              disabled: disabled,
            ),
            _managedBoolOverrideTile(
              model,
              keyName: 'supportsTools',
              title: '工具调用',
              fallback: model.activeEntry?.supportsTools ?? true,
              disabled: disabled,
            ),
          ],
        ),
      ),
    );
  }

  Widget _managedNumericOverrideTile(
    ModelConfig model, {
    required String keyName,
    required String title,
    required num? fallback,
    bool integer = false,
    required bool disabled,
  }) {
    final override = model.userOverrides[keyName] as num?;
    return ListTile(
      dense: true,
      title: Text(title),
      subtitle: Text(
        override == null
            ? '服务端: ${fallback?.toString() ?? "未设置"}'
            : '本机覆盖: $override',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (override != null)
            IconButton(
              tooltip: '清除覆盖',
              onPressed: disabled
                  ? null
                  : () => _clearManagedUserOverride(model, keyName),
              icon: const Icon(Icons.close),
            ),
          IconButton(
            tooltip: '编辑覆盖',
            onPressed: disabled
                ? null
                : () => _editManagedNumericOverride(
                    model,
                    keyName: keyName,
                    title: title,
                    integer: integer,
                  ),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }

  Widget _managedBoolOverrideTile(
    ModelConfig model, {
    required String keyName,
    required String title,
    required bool fallback,
    required bool disabled,
  }) {
    final hasOverride = model.userOverrides.containsKey(keyName);
    final value = model.userOverrides[keyName] as bool? ?? fallback;
    return SwitchListTile(
      dense: true,
      title: Text(title),
      subtitle: Text(hasOverride ? '本机覆盖' : '服务端: ${fallback ? "开启" : "关闭"}'),
      value: value,
      onChanged: disabled
          ? null
          : (next) => _setManagedUserOverride(model, keyName, next),
      secondary: hasOverride
          ? IconButton(
              tooltip: '清除覆盖',
              onPressed: disabled
                  ? null
                  : () => _clearManagedUserOverride(model, keyName),
              icon: const Icon(Icons.close),
            )
          : null,
    );
  }

  Future<void> _editManagedNumericOverride(
    ModelConfig model, {
    required String keyName,
    required String title,
    required bool integer,
  }) async {
    final current = model.userOverrides[keyName]?.toString() ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => TextEditingControllerHost(
        initialTexts: [current],
        builder: (ctx, controllers) {
          final controller = controllers.single;
          return AlertDialog(
            title: Text('覆盖 $title'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '本机覆盖值',
                hintText: '留空使用服务端值',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, ''),
                child: const Text('清除'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null) return;
    if (result.isEmpty) {
      _clearManagedUserOverride(model, keyName);
      return;
    }
    final parsed = integer ? int.tryParse(result) : double.tryParse(result);
    if (parsed == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$title 必须是有效数字')));
      return;
    }
    _setManagedUserOverride(model, keyName, parsed);
  }

  void _setManagedUserOverride(ModelConfig model, String key, dynamic value) {
    widget.provider.setManagedUserOverride(model.id, key, value);
    final overrides = Map<String, dynamic>.from(model.userOverrides)
      ..[key] = value;
    setState(() {
      _managedDisplayModel = model.copyWith(userOverrides: overrides);
    });
  }

  void _clearManagedUserOverride(ModelConfig model, String key) {
    widget.provider.clearManagedUserOverride(model.id, key);
    final overrides = Map<String, dynamic>.from(model.userOverrides)
      ..remove(key);
    setState(() {
      _managedDisplayModel = model.copyWith(userOverrides: overrides);
    });
  }

  void _clearManagedOverrides(ModelConfig model) {
    for (final key in model.userOverrides.keys.toList()) {
      widget.provider.clearManagedUserOverride(model.id, key);
    }
    setState(() {
      _managedDisplayModel = model.copyWith(userOverrides: const {});
    });
  }

  String _categoryTitle(String category) {
    switch (category) {
      case ModelConfig.categoryOcr:
        return 'OCR';
      case ModelConfig.categorySpeech:
        return '语音转文字';
      case ModelConfig.categoryImageGeneration:
        return '图片生成';
      default:
        return 'Chat';
    }
  }

  Widget _managedInfoRow(String label, String value) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: Text(value),
    );
  }

  Widget _managedModelList(ModelConfig model) {
    final entries = model.models
        .where((entry) => entry.name.trim().isNotEmpty)
        .toList();
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
                  '${entries.length} 个模型',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (entries.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('暂无模型'))
          else
            ...entries.map(
              (entry) => ListTile(
                dense: true,
                title: Text(
                  entry.name,
                  style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _refreshManagedModels() async {
    setState(() => _refreshingManaged = true);
    try {
      final backend = context.read<BackendClient>();
      final ok = await widget.provider.syncLynaiManagedProvider(backend);
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('刷新失败，请检查登录状态和后端配置')));
        return;
      }
      ModelConfig? latest;
      for (final model in widget.provider.models) {
        if (model.id == widget.model!.id) {
          latest = model;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _managedDisplayModel = latest ?? _managedDisplayModel;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已刷新 LynAI 模型列表')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('刷新失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _refreshingManaged = false);
    }
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
      items: (_apiTypeOptions())
          .map(
            (t) =>
                DropdownMenuItem(value: t['value'], child: Text(t['label']!)),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) setState(() => _apiType = v);
      },
    );
  }

  List<Map<String, String>> _apiTypeOptions() {
    if (isImageGeneration) {
      return const [
        {'value': 'openai_image', 'label': 'OpenAI 格式'},
        {'value': 'vivo_image', 'label': 'vivo 原生'},
        {'value': 'custom', 'label': 'Custom'},
      ];
    }
    if (isSpeech) {
      return const [
        {'value': 'openai_speech', 'label': 'OpenAI 语音'},
        {'value': 'vivo_lasr', 'label': 'vivo 长语音'},
        {'value': 'custom', 'label': 'Custom'},
      ];
    }
    if (isOcr) {
      return const [
        {'value': 'vivo_ocr', 'label': 'vivo OCR'},
        {'value': 'openai', 'label': 'OpenAI 视觉'},
        {'value': 'ollama', 'label': 'Ollama 视觉'},
        {'value': 'anthropic', 'label': 'Anthropic 视觉'},
        {'value': 'custom', 'label': 'Custom'},
      ];
    }
    return const [
      {'value': 'openai', 'label': 'OpenAI 兼容'},
      {'value': 'ollama', 'label': 'Ollama'},
      {'value': 'anthropic', 'label': 'Anthropic'},
      {'value': 'custom', 'label': 'Custom'},
    ];
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

  Widget _advancedOptionsSection() {
    return Card(
      key: _advancedOptionsKey,
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: _showAdvancedOptions,
        onExpansionChanged: (expanded) {
          setState(() => _showAdvancedOptions = expanded);
          if (expanded) _ensureAdvancedOptionsVisible();
        },
        leading: const Icon(Icons.tune),
        title: const Text('高级选项'),
        subtitle: const Text('采样参数与兼容性开关'),
        childrenPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        children: [
          if (hasChatStyleOptions) ...[
            _advancedNumberField(
              controller: _maxTokensController,
              label: 'Max Tokens',
              hint: 'Provider 级最大 Token 数，留空使用服务默认值',
              min: 1,
            ),
            const SizedBox(height: 12),
            _advancedNumberField(
              controller: _temperatureController,
              label: 'Temperature',
              hint: 'Provider 级温度，留空使用服务默认值',
              isDecimal: true,
              min: 0,
            ),
            const SizedBox(height: 12),
            _advancedNumberField(
              controller: _topPController,
              label: 'Top P',
              hint: 'Provider 级核采样，留空使用服务默认值',
              isDecimal: true,
              min: 0,
              max: 1,
            ),
            const SizedBox(height: 16),
          ],
          if (_isOpenAICompatible) ...[
            _advancedNumberField(
              controller: _presencePenaltyController,
              label: 'Presence Penalty',
              hint: '-2.0 到 2.0，正值增加新话题倾向',
              isDecimal: true,
              min: -2,
              max: 2,
            ),
            const SizedBox(height: 12),
            _advancedNumberField(
              controller: _frequencyPenaltyController,
              label: 'Frequency Penalty',
              hint: '-2.0 到 2.0，正值减少重复',
              isDecimal: true,
              min: -2,
              max: 2,
            ),
            const SizedBox(height: 12),
            _advancedNumberField(
              controller: _seedController,
              label: 'Seed',
              hint: '整数种子值，使输出可复现',
              isInt: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stopController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Stop',
                hintText: '停止词列表，每行一个',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _userController,
              decoration: const InputDecoration(
                labelText: 'User',
                hintText: '终端用户标识符',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('SSE 调试日志'),
            subtitle: const Text('打印流式请求摘要、原始 SSE chunk 和 tool call 解析结果'),
            value: _debugSse,
            onChanged: (value) {
              setState(() => _debugSse = value);
            },
          ),
        ],
      ),
    );
  }

  Widget _advancedNumberField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool isDecimal = false,
    bool isInt = false,
    num? min,
    num? max,
  }) {
    TextInputType keyboardType = TextInputType.number;
    if (isDecimal) {
      keyboardType = const TextInputType.numberWithOptions(decimal: true);
    }
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: (value) => _validateNumberField(
        value,
        label: label,
        isInt: isInt,
        min: min,
        max: max,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  void _ensureAdvancedOptionsVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _advancedOptionsKey.currentContext;
      if (context == null || !mounted) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 0.08,
      );
    });
  }

  String? _validateNumberField(
    String? value, {
    required String label,
    required bool isInt,
    num? min,
    num? max,
  }) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = isInt ? int.tryParse(text) : double.tryParse(text);
    if (parsed == null) return '$label 必须是${isInt ? '整数' : '数字'}';
    if (min != null && parsed < min) return '$label 不能小于 $min';
    if (max != null && parsed > max) return '$label 不能大于 $max';
    return null;
  }

  Future<void> _editModelEntry(int index) async {
    final entry = _modelEntries[index];
    final formKey = GlobalKey<FormState>();
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
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
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
                  TextFormField(
                    controller: maxTokens,
                    keyboardType: TextInputType.number,
                    validator: (value) => _validateNumberField(
                      value,
                      label: 'Max Tokens',
                      isInt: true,
                      min: 1,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Max Tokens',
                      hintText: '留空继承 Provider 级设置',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: temperature,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) => _validateNumberField(
                      value,
                      label: 'Temperature',
                      isInt: false,
                      min: 0,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Temperature',
                      hintText: '留空继承 Provider 级设置',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: topP,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) => _validateNumberField(
                      value,
                      label: 'Top P',
                      isInt: false,
                      min: 0,
                      max: 1,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Top P',
                      hintText: '留空继承 Provider 级设置',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(
                  ctx,
                  entry.copyWith(
                    supportsVision: supportsVision,
                    supportsThinking: supportsThinking,
                    supportsTools: supportsTools,
                    maxTokens: int.tryParse(maxTokens.text.trim()),
                    temperature: double.tryParse(temperature.text.trim()),
                    topP: double.tryParse(topP.text.trim()),
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      maxTokens.dispose();
      temperature.dispose();
      topP.dispose();
    });
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
