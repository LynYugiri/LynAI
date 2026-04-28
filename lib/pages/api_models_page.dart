import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/model_config.dart';
import '../providers/model_config_provider.dart';

/// API 模型管理页面
///
/// 功能：
/// - 显示模型列表，按优先级从上到下排列
/// - 点击模型进入编辑页面
/// - 右下角加号按钮添加新模型
/// - 长按拖拽调整优先级排序
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
              // 每个列表项显示拖拽手柄，支持重新排序
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
      // 右下角添加模型按钮
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _navigateToEditModel(context, provider);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 构建空状态
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

  /// 构建模型列表项
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
        // 拖拽手柄
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle, color: Colors.grey),
        ),
        // 模型信息
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
        // 优先级标签
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

  /// 根据优先级获取颜色
  Color _getPriorityColor(int index, int total) {
    if (total <= 1) return Colors.grey;
    final ratio = index / (total - 1);
    if (ratio < 0.33) return Colors.green;
    if (ratio < 0.66) return Colors.orange;
    return Colors.red;
  }

  /// 导航到编辑/添加模型页面
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

/// 编辑/添加模型页面
///
/// 表单包含：
/// - 模型名称（自定义显示名称）
/// - Endpoint（API 端点）
/// - API Key
/// - Model（实际模型名称）
/// - API 类型（OpenAI / Ollama 等）
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
  String _apiType = 'openai';

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
    _apiType = widget.model?.apiType ?? 'openai';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _endpointController.dispose();
    _apiKeyController.dispose();
    _modelNameController.dispose();
    super.dispose();
  }

  /// 保存模型配置
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
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: 'sk-...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
                ),
                obscureText: true,
                validator: (value) {
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
              const SizedBox(height: 32),

              // 保存按钮
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

