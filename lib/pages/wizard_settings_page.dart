import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_entry.dart';
import 'onboarding/onboarding_page.dart';

/// 向导设置页。
///
/// 收纳新手向导与功能引导两个入口。
class WizardSettingsPage extends StatelessWidget {
  const WizardSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    return SettingsSubpage(
      title: '向导',
      entries: [
        SettingsEntry(
          icon: Icons.auto_awesome,
          title: '新手向导',
          subtitle: settings.hasCompletedOnboarding
              ? '重新生成个性化初始配置'
              : '选择用途与身份，生成专属配置',
          iconColor: Colors.orange,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OnboardingPage()),
          ),
        ),
        SettingsEntry(
          icon: Icons.explore_outlined,
          title: '功能引导',
          subtitle: '重新看一遍底部导航、快捷盘和角色/Agent 入口',
          iconColor: Colors.teal,
          onTap: () {
            final provider = context.read<SettingsProvider>();
            provider.replaceSettings(
              provider.settings.copyWith(hasCompletedGuidedTour: false),
            );
          },
        ),
      ],
    );
  }
}
