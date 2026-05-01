import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import 'about_page.dart';
import 'background_page.dart';
import 'api_models_page.dart';
import 'theme_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;

    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildItem(context, Icons.info_outline, 'About', '关于 LynAI', Colors.blue,
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutPage()))),
          _buildItem(context, Icons.wallpaper, 'Background',
              settings.backgroundImagePath != null ? '已设置背景图片' : '自定义背景图片', Colors.purple,
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackgroundPage()))),
          _buildItem(context, Icons.api, 'API', '管理 AI 模型', Colors.orange,
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApiModelsPage()))),
          _buildItem(context, Icons.palette, 'Theme', settings.themeMode == 'dark' ? '自定义主题颜色' : (settings.themeMode == 'system' ? '自定义主题颜色' : '自定义主题颜色'), Colors.green,
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemePage()))),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, IconData icon, String title, String subtitle, Color iconColor, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: iconColor.withValues(alpha: 0.1), child: Icon(icon, color: iconColor)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
