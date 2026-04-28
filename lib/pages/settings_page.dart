import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/model_config_provider.dart';
import 'about_page.dart';
import 'background_page.dart';
import 'api_models_page.dart';
import 'theme_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final modelProvider = context.watch<ModelConfigProvider>();
    final speechModel = settings.speechModelId != null
        ? modelProvider.models
            .firstWhere((m) => m.id == settings.speechModelId, orElse: () => modelProvider.models.first)
        : null;
    final imageModel = settings.imageModelId != null
        ? modelProvider.models
            .firstWhere((m) => m.id == settings.imageModelId, orElse: () => modelProvider.models.first)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildSettingsItem(
            context,
            icon: Icons.info_outline,
            title: 'About',
            subtitle: '关于 LynAI',
            iconColor: Colors.blue,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutPage()),
              );
            },
          ),
          _buildSettingsItem(
            context,
            icon: Icons.wallpaper,
            title: 'Background',
            subtitle: settings.backgroundImagePath != null
                ? '已设置背景图片'
                : '自定义背景图片',
            iconColor: Colors.purple,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BackgroundPage()),
              );
            },
          ),
          _buildSettingsItem(
            context,
            icon: Icons.api,
            title: 'API',
            subtitle: '管理 AI 模型',
            iconColor: Colors.orange,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ApiModelsPage()),
              );
            },
          ),
          _buildSettingsItem(
            context,
            icon: Icons.palette,
            title: 'Theme',
            subtitle: '自定义主题颜色',
            iconColor: Colors.green,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ThemePage()),
              );
            },
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              '功能模型配置',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ),
          // 语音转文字模型
          _buildModelPickerItem(
            context,
            icon: Icons.mic,
            title: '语音转文字模型',
            currentModel: speechModel,
            modelProvider: modelProvider,
            color: Colors.teal,
            onSelected: (modelId) {
              context.read<SettingsProvider>().setSpeechModelId(modelId);
            },
            onClear: () {
              context.read<SettingsProvider>().setSpeechModelId(null);
            },
          ),
          // 图片文件转述模型
          _buildModelPickerItem(
            context,
            icon: Icons.image_search,
            title: '图片文件转述模型',
            currentModel: imageModel,
            modelProvider: modelProvider,
            color: Colors.indigo,
            onSelected: (modelId) {
              context.read<SettingsProvider>().setImageModelId(modelId);
            },
            onClear: () {
              context.read<SettingsProvider>().setImageModelId(null);
            },
          ),
          // 图片转述提示词
          _buildImagePromptItem(context, settings.imagePrompt),
        ],
      ),
    );
  }

  Widget _buildModelPickerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    dynamic currentModel,
    required ModelConfigProvider modelProvider,
    required Color color,
    required void Function(String?) onSelected,
    required VoidCallback onClear,
  }) {
    final subtitle = currentModel != null
        ? '当前: ${currentModel.name} (${currentModel.modelName})'
        : '未设置（使用默认发送按钮）';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            if (action == 'clear') {
              onClear();
            } else if (action == 'select') {
              _showModelPickerDialog(
                  context, modelProvider, currentModel, onSelected);
            }
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(value: 'select', child: Text('选择模型')),
            if (currentModel != null)
              const PopupMenuItem(value: 'clear', child: Text('清除设置')),
          ],
        ),
      ),
    );
  }

  void _showModelPickerDialog(
    BuildContext context,
    ModelConfigProvider modelProvider,
    dynamic currentModel,
    void Function(String?) onSelected,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择模型'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: modelProvider.models.length,
            itemBuilder: (ctx, index) {
              final model = modelProvider.models[index];
              final isSelected = currentModel != null &&
                  model.id == currentModel.id;
              return ListTile(
                leading: Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
                title: Text(model.name),
                subtitle: Text(model.modelName,
                    style: const TextStyle(fontSize: 12)),
                onTap: () {
                  onSelected(model.id);
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePromptItem(BuildContext context, String currentPrompt) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.indigo.withValues(alpha: 0.1),
          child: const Icon(Icons.edit_note, color: Colors.indigo),
        ),
        title: const Text('图片转述提示词',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          currentPrompt,
          style: const TextStyle(fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          _showPromptEditDialog(context, currentPrompt);
        },
      ),
    );
  }

  void _showPromptEditDialog(BuildContext context, String currentPrompt) {
    final controller = TextEditingController(text: currentPrompt);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义提示词'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Describe this file in Chinese',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              context.read<SettingsProvider>().setImagePrompt(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: iconColor.withValues(alpha: 0.1),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
