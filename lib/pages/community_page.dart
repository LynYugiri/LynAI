import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/account_provider.dart';

/// 社区页面（占位）。
///
/// 计划承载对话、角色、插件包的分享、点赞、评论与订阅能力。
/// 后端社区 API 尚未启动，首版仅展示「敬请期待」占位与未来能力说明，
/// 不发起任何服务调用。根据登录态显示不同文案：已登录时提示上线后
/// 自动同步，未登录时引导跳转设置页登录。
class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = context.watch<AccountProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('社区'), centerTitle: true),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.groups_outlined,
                size: 72,
                color: theme.colorScheme.primary.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16),
              Text(
                '社区功能即将上线',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '未来可在此分享对话、角色和插件包，发现其他用户的创作。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (account.isLoggedIn)
                Text(
                  '你已登录，社区上线后将自动同步你的内容。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                )
              else ...[
                Text(
                  '登录后即可在社区上线时收到通知。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => _navigateToSettings(context),
                  child: const Text('去登录'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 提示用户切到设置 tab 登录。
  ///
  /// HomePage 是 IndexedStack，无法直接用 Navigator 跳转。这里用 SnackBar
  /// 引导用户点击底部「设置」tab。后端就绪后可改为真正的导航回调。
  void _navigateToSettings(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('请点击底部「设置」tab 登录'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
