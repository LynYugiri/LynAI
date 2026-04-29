import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../models/model_config.dart';
import '../providers/model_config_provider.dart';

const _endpointPresets = [
  {'name': 'OpenAI', 'url': 'https://api.openai.com/v1', 'type': 'openai'},
  {'name': 'DeepSeek', 'url': 'https://api.deepseek.com', 'type': 'openai'},
  {'name': 'Anthropic', 'url': 'https://api.anthropic.com', 'type': 'anthropic'},
  {'name': 'Google AI', 'url': 'https://generativelanguage.googleapis.com/v1beta', 'type': 'openai'},
  {'name': 'Ollama (本地)', 'url': 'http://localhost:11434', 'type': 'ollama'},
  {'name': 'OpenRouter', 'url': 'https://openrouter.ai/api/v1', 'type': 'openai'},
  {'name': 'Groq', 'url': 'https://api.groq.com/openai/v1', 'type': 'openai'},
  {'name': 'Together AI', 'url': 'https://api.together.xyz/v1', 'type': 'openai'},
  {'name': 'xAI (Grok)', 'url': 'https://api.x.ai/v1', 'type': 'openai'},
  {'name': 'Moonshot', 'url': 'https://api.moonshot.cn/v1', 'type': 'openai'},
  {'name': 'Zhipu (智谱)', 'url': 'https://open.bigmodel.cn/api/paas/v4', 'type': 'openai'},
  {'name': 'Qwen (通义千问)', 'url': 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'type': 'openai'},
  {'name': 'SiliconFlow', 'url': 'https://api.siliconflow.cn/v1', 'type': 'openai'},
  {'name': '自定义', 'url': '', 'type': 'custom'},
];

class ApiModelsPage extends StatelessWidget {
  const ApiModelsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ModelConfigProvider>();
    final models = provider.models;

    return Scaffold(
      appBar: AppBar(title: const Text('API 模型管理'), centerTitle: true),
      body: models.isEmpty
          ? _buildEmptyState()
          : ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: models.length,
              onReorder: provider.reorderModel,
              buildDefaultDragHandles: false,
              itemBuilder: (context, index) {
                final model = models[index];
                return _buildModelItem(context, model, index, models.length, provider);
              },
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
          Icon(Icons.api, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('暂无模型配置', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text('点击右下角 + 添加模型', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildModelItem(BuildContext context, ModelConfig model, int index, int total, ModelConfigProvider provider) {
    final enabledCount = model.enabledModelNames.length;
    return Card(
      key: ValueKey(model.id),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle, color: Colors.grey),
        ),
        title: Text(model.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${model.apiType.toUpperCase()} - ${model.endpoint}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (model.hasMultipleModels)
              Text('已启用 $enabledCount / ${model.models.length} 个模型',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
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
              child: Text('优先级 ${index + 1}',
                  style: TextStyle(fontSize: 11, color: _getPriorityColor(index, total), fontWeight: FontWeight.w600)),
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

  void _navigateToEditModel(BuildContext context, ModelConfigProvider provider, {ModelConfig? model}) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => EditModelPage(model: model, provider: provider)));
  }
}

class EditModelPage extends StatefulWidget {
  final ModelConfig? model;
  final ModelConfigProvider provider;
  const EditModelPage({super.key, this.model, required this.provider});

  @override
  State<EditModelPage> createState() => _EditModelPageState();
}

class _EditModelPageState extends State<EditModelPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController, _endpointController, _apiKeyController;
  late TextEditingController _maxTokensController, _temperatureController, _topPController;
  late TextEditingController _newModelController;
  late List<ModelEntry> _modelEntries;
  String _apiType = 'openai';
  bool _showAdvanced = false;
  bool _obscureApiKey = true;
  bool _showEndpointSuggestions = false;
  bool _isFetchingModels = false;
  List<Map<String, dynamic>> _filteredPresets = [];

  bool get isEditing => widget.model != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.model?.name ?? '');
    _endpointController = TextEditingController(text: widget.model?.endpoint ?? '');
    _apiKeyController = TextEditingController(text: widget.model?.apiKey ?? '');
    _maxTokensController = TextEditingController(text: widget.model?.maxTokens?.toString() ?? '');
    _temperatureController = TextEditingController(text: widget.model?.temperature?.toString() ?? '');
    _topPController = TextEditingController(text: widget.model?.topP?.toString() ?? '');
    _newModelController = TextEditingController();
    _apiType = widget.model?.apiType ?? 'openai';
    _showAdvanced = widget.model?.maxTokens != null || widget.model?.temperature != null || widget.model?.topP != null;
    _modelEntries = widget.model?.models.map((m) => ModelEntry(name: m.name, enabled: m.enabled)).toList()
        ?? [ModelEntry(name: '', enabled: false)];
    _filteredPresets = List.from(_endpointPresets);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _endpointController.dispose();
    _apiKeyController.dispose();
    _maxTokensController.dispose();
    _temperatureController.dispose();
    _topPController.dispose();
    _newModelController.dispose();
    super.dispose();
  }

  void _saveModel() {
    if (!_formKey.currentState!.validate()) return;
    final entries = _modelEntries.where((m) => m.name.trim().isNotEmpty).toList();
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少添加一个模型')),
      );
      return;
    }
    final enabled = entries.where((m) => m.enabled).toList();
    final activeModelName = enabled.isNotEmpty ? enabled.first.name : entries.first.name;

    final config = ModelConfig(
      id: widget.model?.id ?? widget.provider.generateId(),
      name: _nameController.text.trim(),
      endpoint: _endpointController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      modelName: activeModelName,
      apiType: _apiType,
      priority: widget.model?.priority ?? 999,
      maxTokens: int.tryParse(_maxTokensController.text.trim()),
      temperature: double.tryParse(_temperatureController.text.trim()),
      topP: double.tryParse(_topPController.text.trim()),
      models: entries,
    );

    if (isEditing) {
      widget.provider.updateModel(config);
    } else {
      widget.provider.addModel(config);
    }
    Navigator.pop(context);
  }

  void _addModelEntry() {
    final name = _newModelController.text.trim();
    if (name.isEmpty) return;
    if (_modelEntries.any((m) => m.name == name)) return;
    setState(() {
      _modelEntries.add(ModelEntry(name: name, enabled: false));
      _newModelController.clear();
    });
  }

  void _removeModelEntry(int index) {
    setState(() => _modelEntries.removeAt(index));
  }

  void _toggleModelEntry(int index) {
    setState(() {
      _modelEntries[index] = _modelEntries[index].copyWith(
        enabled: !_modelEntries[index].enabled,
      );
    });
  }

  void _selectEndpointPreset(Map<String, dynamic> preset) {
    _endpointController.text = preset['url'] as String;
    if (preset['type'] != 'custom') {
      setState(() => _apiType = preset['type'] as String);
    }
    setState(() => _showEndpointSuggestions = false);
  }

  void _filterEndpointPresets(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredPresets = List.from(_endpointPresets);
      } else {
        _filteredPresets = _endpointPresets
            .where((p) => (p['name'] as String).toLowerCase().contains(query.toLowerCase())
                || (p['url'] as String).toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  Future<void> _fetchModels() async {
    final endpoint = _endpointController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    if (endpoint.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写 Endpoint')),
      );
      return;
    }
    setState(() => _isFetchingModels = true);
    try {
      List<ModelEntry> fetched = [];
      if (_apiType == 'ollama') {
        final resp = await http.get(Uri.parse('$endpoint/api/tags'));
        if (resp.statusCode == 200) {
          final models = jsonDecode(resp.body)['models'] as List;
          fetched = models.map((m) {
            final name = (m['name'] as String).replaceAll(':latest', '');
            return ModelEntry(name: name, enabled: false);
          }).toList();
        } else {
          throw Exception('${resp.statusCode}');
        }
      } else {
        final headers = <String, String>{};
        if (apiKey.isNotEmpty) headers['Authorization'] = 'Bearer $apiKey';
        final resp = await http.get(Uri.parse('$endpoint/models'), headers: headers);
        if (resp.statusCode == 200) {
          final models = jsonDecode(resp.body)['data'] as List? ?? [];
          fetched = models.map((m) => ModelEntry(name: m['id'] as String, enabled: false)).toList();
        } else {
          throw Exception('${resp.statusCode}');
        }
      }
      // Merge: keep existing entries, add new ones that don't exist yet
      final existingNames = _modelEntries.map((e) => e.name).toSet();
      final newEntries = fetched.where((e) => !existingNames.contains(e.name)).toList();
      final addedCount = newEntries.length;
      setState(() => _modelEntries.addAll(newEntries));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(addedCount > 0 ? '新增 $addedCount 个模型' : '没有新模型，已全部存在')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取模型列表失败: $e')),
        );
      }
    } finally {
      setState(() => _isFetchingModels = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final apiKeyOptional = _apiType == 'ollama';
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '编辑模型' : '添加模型'),
        centerTitle: true,
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: '删除模型',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('删除模型'),
                    content: Text('确定要删除"${widget.model!.name}"吗？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                      TextButton(
                        onPressed: () {
                          widget.provider.deleteModel(widget.model!.id);
                          Navigator.pop(ctx);
                          Navigator.pop(context);
                        },
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
              },
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
                  labelText: '模型提供商名称', hintText: '例如：DeepSeek',
                  border: OutlineInputBorder(), prefixIcon: Icon(Icons.label),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? '请输入名称' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _apiType,
                decoration: const InputDecoration(
                  labelText: 'API 类型', border: OutlineInputBorder(), prefixIcon: Icon(Icons.category),
                ),
                items: [
                  {'value': 'openai', 'label': 'OpenAI 兼容'},
                  {'value': 'ollama', 'label': 'Ollama'},
                  {'value': 'anthropic', 'label': 'Anthropic'},
                  {'value': 'custom', 'label': 'Custom'},
                ].map((t) => DropdownMenuItem(value: t['value'], child: Text(t['label']!))).toList(),
                onChanged: (v) { if (v != null) setState(() => _apiType = v); },
              ),
              const SizedBox(height: 16),
              // Endpoint with suggestions
              TextFormField(
                controller: _endpointController,
                decoration: InputDecoration(
                  labelText: 'Endpoint',
                  hintText: 'https://api.openai.com/v1',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.link),
                  suffixIcon: IconButton(
                    icon: Icon(_showEndpointSuggestions ? Icons.expand_less : Icons.expand_more),
                    onPressed: () {
                      setState(() {
                        _showEndpointSuggestions = !_showEndpointSuggestions;
                        if (_showEndpointSuggestions) {
                          _filterEndpointPresets(_endpointController.text);
                        }
                      });
                    },
                  ),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? '请输入 Endpoint' : null,
                onChanged: (v) {
                  if (_showEndpointSuggestions) _filterEndpointPresets(v);
                },
                onTap: () {
                  setState(() {
                    _showEndpointSuggestions = true;
                    _filterEndpointPresets(_endpointController.text);
                  });
                },
              ),
              if (_showEndpointSuggestions)
                Container(
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
                          size: 18, color: Colors.grey[600],
                        ),
                        title: Text(p['name'] as String, style: const TextStyle(fontSize: 14)),
                        subtitle: Text(p['url'] as String, style: const TextStyle(fontSize: 11)),
                        onTap: () => _selectEndpointPreset(p),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _apiKeyController,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  hintText: apiKeyOptional ? '可选（Ollama 无需 Key）' : 'sk-...',
                  border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.key),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureApiKey ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                  ),
                ),
                obscureText: _obscureApiKey,
                validator: apiKeyOptional ? null : (v) => (v == null || v.trim().isEmpty) ? '请输入 API Key' : null,
              ),
              const SizedBox(height: 16),
              // 获取模型按钮
              OutlinedButton.icon(
                onPressed: _isFetchingModels ? null : _fetchModels,
                icon: _isFetchingModels
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download),
                label: Text(_isFetchingModels ? '获取中...' : '从 Endpoint 获取模型列表'),
              ),
              const SizedBox(height: 12),
              // 模型列表
              Container(
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
                          const Text('模型列表', style: TextStyle(fontWeight: FontWeight.w500)),
                          const Spacer(),
                          Text('已启用 ${_modelEntries.where((m) => m.enabled).length} / ${_modelEntries.where((m) => m.name.isNotEmpty).length}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (_modelEntries.where((m) => m.name.isNotEmpty).isNotEmpty)
                      ..._modelEntries.asMap().entries.where((e) => e.value.name.isNotEmpty).map((e) {
                        final idx = e.key;
                        final entry = e.value;
                        return ListTile(
                          dense: true,
                          title: Text(entry.name, style: const TextStyle(fontSize: 14, fontFamily: 'monospace')),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: entry.enabled,
                                onChanged: (_) => _toggleModelEntry(idx),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () => _removeModelEntry(idx),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                              ),
                            ],
                          ),
                        );
                      }),
                    // 添加模型输入
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
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
              ),
              const SizedBox(height: 16),
              // 高级选项
              InkWell(
                onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more, size: 20, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Text('高级选项', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey[700])),
                      const Spacer(),
                      Text('max_tokens, temperature 等', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
              ),
              if (_showAdvanced) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _maxTokensController,
                  decoration: const InputDecoration(
                    labelText: 'Max Tokens', hintText: '例如：4096',
                    border: OutlineInputBorder(), prefixIcon: Icon(Icons.numbers),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _temperatureController,
                  decoration: const InputDecoration(
                    labelText: 'Temperature', hintText: '例如：0.7',
                    border: OutlineInputBorder(), prefixIcon: Icon(Icons.thermostat),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _topPController,
                  decoration: const InputDecoration(
                    labelText: 'Top P', hintText: '例如：0.9',
                    border: OutlineInputBorder(), prefixIcon: Icon(Icons.tune),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _saveModel,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: Text(isEditing ? '保存修改' : '添加模型', style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
