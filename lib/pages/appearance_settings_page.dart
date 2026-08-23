import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_entry.dart';
import 'background_page.dart';
import 'theme_page.dart';

/// 外观设置页。
///
/// 收纳主题与背景两个设置入口。
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    return SettingsSubpage(
      title: '外观',
      entries: [
        SettingsEntry(
          icon: Icons.palette,
          title: '主题',
          subtitle: '自定义主题颜色',
          iconColor: Colors.green,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ThemePage()),
          ),
        ),
        SettingsEntry(
          icon: Icons.wallpaper,
          title: '背景',
          subtitle: settings.backgroundImagePath != null
              ? '已设置背景图片'
              : '自定义背景图片',
          iconColor: Colors.purple,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BackgroundPage()),
          ),
        ),
      ],
    );
  }
}
