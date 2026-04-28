import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/model_config.dart';
import '../providers/model_config_provider.dart';

class ApiModelsPage extends StatelessWidget {
  const ApiModelsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ModelConfigProvider>();
    final models = provider.models;

    return Scaffold(
      appBar: AppBar(
        title: const Text('API 模型管理'),
        centerTitle: true,
      ),
      body: models.isEmpty
          ? _buildEmptyState()
          : ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: models.length,
              onReorder: provider.reorderModel,
              buildDefaultDragHandles: false,
              itemBuilder: (context, index) {
                final model = models[index];
                return _buildModelItem(
                  context,
                  model,
                  index,
                  models.length,
                  provider,
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _navigateToEditModel(context, provider);
        },
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
          Text(
            '暂无模型配置',
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
              '${model.apiType.toUpperCase()} - ${model.modelName}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            Text(
              model.endpoint,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _getPriorityColor(index, total)
                    .withValues(alpha: 0.1),
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
        onTap: () {
          _navigateToEditModel(context, provider, model: model);
        },
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
        builder: (_) => EditModelPage(
          model: model,
          provider: provider,
        ),
      ),
    );
  }
}

class EditModelPage extends StatefulWidget {
  final ModelConfig? model;
  final ModelConfigProvider provider;

  const EditModelPage({
    super.key,
    this.model,
    required this.provider,
  });

  @override
  State<EditModelPage> createState() => _EditModelPageState();
}

class _EditModelPageState extends State<EditModelPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _endpointController;
  late TextEditingController _apiKeyController;
  late TextEditingController _modelNameController;
  late TextEditingController _maxTokensController;
  late TextEditingController _temperatureController;
  late TextEditingController _topPController;
  String _apiType = 'openai';
  bool _showAdvanced = false;
  bool _obscureApiKey = true;

  final List<Map<String, String>> _apiTypes = [
    {'value': 'openai', 'label': 'OpenAI'},
    {'value': 'ollama', 'label': 'Ollama'},
    {'value': 'anthropic', 'label': 'Anthropic'},
    {'value': 'custom', 'label': 'Custom'},
  ];

  bool get isEditing => widget.model != null;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.model?.name ?? '');
    _endpointController =
        TextEditingController(text: widget.model?.endpoint ?? '');
    _apiKeyController =
        TextEditingController(text: widget.model?.apiKey ?? '');
    _modelNameController =
        TextEditingController(text: widget.model?.modelName ?? '');
    _maxTokensController = TextEditingController(
        text: widget.model?.maxTokens?.toString() ?? '');
    _temperatureController = TextEditingController(
        text: widget.model?.temperature?.toString() ?? '');
    _topPController = TextEditingController(
        text: widget.model?.topP?.toString() ?? '');
    _apiType = widget.model?.apiType ?? 'openai';
    _showAdvanced = widget.model?.maxTokens != null ||
        widget.model?.temperature != null ||
        widget.model?.topP != null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _endpointController.dispose();
    _apiKeyController.dispose();
    _modelNameController.dispose();
    _maxTokensController.dispose();
    _temperatureController.dispose();
    _topPController.dispose();
    super.dispose();
  }

  void _saveModel() {
    if (!_formKey.currentState!.validate()) return;

    final config = ModelConfig(
      id: widget.model?.id ?? widget.provider.generateId(),
      name: _nameController.text.trim(),
      endpoint: _endpointController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      modelName: _modelNameController.text.trim(),
      apiType: _apiType,
      priority: widget.model?.priority ?? 999,
      maxTokens: int.tryParse(_maxTokensController.text.trim()),
      temperature: double.tryParse(_temperatureController.text.trim()),
      topP: double.tryParse(_topPController.text.trim()),
    );

    if (isEditing) {
      widget.provider.updateModel(config);
    } else {
      widget.provider.addModel(config);
    }

    Navigator.pop(context);
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
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () {
                          widget.provider.deleteModel(widget.model!.id);
                          Navigator.pop(ctx);
                          Navigator.pop(context);
                        },
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.red),
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
              // 模型名称
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '模型名称',
                  hintText: '例如：GPT-4 Turbo',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入模型名称';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // API 类型选择
              DropdownButtonFormField<String>(
                initialValue: _apiType,
                decoration: const InputDecoration(
                  labelText: 'API 类型',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: _apiTypes.map((type) {
                  return DropdownMenuItem(
                    value: type['value'],
                    child: Text(type['label']!),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _apiType = value);
                  }
                },
              ),
              const SizedBox(height: 16),

              // Endpoint
              TextFormField(
                controller: _endpointController,
                decoration: InputDecoration(
                  labelText: 'Endpoint',
                  hintText: _apiType == 'openai'
                      ? 'https://api.openai.com/v1'
                      : _apiType == 'ollama'
                          ? 'http://localhost:11434'
                          : 'https://your-api-endpoint',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.link),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入 Endpoint';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // API Key
              TextFormField(
                controller: _apiKeyController,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  hintText: apiKeyOptional ? '可选（Ollama 无需 Key）' : 'sk-...',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.key),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureApiKey
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() => _obscureApiKey = !_obscureApiKey);
                    },
                  ),
                ),
                obscureText: _obscureApiKey,
                validator: apiKeyOptional ? null : (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入 API Key';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Model Name
              TextFormField(
                controller: _modelNameController,
                decoration: InputDecoration(
                  labelText: 'Model',
                  hintText: _apiType == 'openai'
                      ? 'gpt-4-turbo'
                      : _apiType == 'ollama'
                          ? 'llama3'
                          : '模型标识符',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.smart_toy),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入 Model 名称';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 高级选项
              InkWell(
                onTap: () {
                  setState(() => _showAdvanced = !_showAdvanced);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _showAdvanced
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '高级选项',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'max_tokens, temperature 等',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              ),

              if (_showAdvanced) ...[
                const SizedBox(height: 12),
                // max_tokens
                TextFormField(
                  controller: _maxTokensController,
                  decoration: const InputDecoration(
                    labelText: 'Max Tokens',
                    hintText: '例如：4096',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.numbers),
                    helperText: '最大输出 token 数量，留空使用默认值',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                // Temperature
                TextFormField(
                  controller: _temperatureController,
                  decoration: const InputDecoration(
                    labelText: 'Temperature',
                    hintText: '例如：0.7',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.thermostat),
                    helperText: '采样温度，0-2，越高越随机，留空使用默认值',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                // Top P
                TextFormField(
                  controller: _topPController,
                  decoration: const InputDecoration(
                    labelText: 'Top P',
                    hintText: '例如：0.9',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.tune),
                    helperText: '核采样参数，0-1，留空使用默认值',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ],

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
    );
  }
}
