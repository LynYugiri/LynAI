import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/account_provider.dart';
import '../providers/model_config_provider.dart';
import '../services/backend_client.dart';
import 'login_dialog.dart';

/// 设置页顶部的账号卡片。
///
/// 已登录时显示头像、用户名和登出按钮；未登录时显示「点击登录」按钮，
/// 点击后弹出 [LoginDialog]。后端未连接时登录不可用。
class AccountHeaderCard extends StatelessWidget {
  const AccountHeaderCard({super.key});

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountProvider>();
    final theme = Theme.of(context);

    if (account.isLoggedIn) {
      return _LoggedInCard(account: account, theme: theme);
    }

    return _LoggedOutCard(account: account, theme: theme);
  }
}

class _LoggedInCard extends StatelessWidget {
  const _LoggedInCard({required this.account, required this.theme});

  final AccountProvider account;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final user = account.user!;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primary.withValues(
                alpha: 0.12,
              ),
              child: Text(
                user.displayName.isNotEmpty
                    ? user.displayName[0].toUpperCase()
                    : '?',
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (user.isAdmin) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '管理员',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (user.phone.isNotEmpty)
                    Text(user.phone, style: theme.textTheme.bodySmall),
                  if (!account.isBackendConnected)
                    Text(
                      '本地账号 · 未连接后端',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (account.loading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              TextButton(
                onPressed: () async {
                  await account.logout();
                  if (context.mounted) {
                    await context
                        .read<ModelConfigProvider>()
                        .removeLynaiManagedProviders();
                  }
                },
                child: const Text('退出登录'),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoggedOutCard extends StatelessWidget {
  const _LoggedOutCard({required this.account, required this.theme});

  final AccountProvider account;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final backend = context.watch<BackendClient>();
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.12,
                  ),
                  child: Icon(
                    Icons.person_outline,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '未登录',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        !account.isBackendConnected
                            ? '可在下方连接可信 HTTPS 服务端；内置 HTTP 地址仅供隔离测试。'
                            : backend.usesInsecureHttp
                            ? '当前远程 HTTP 后端仅供隔离测试，请勿使用真实账号、常用密码或生产数据。'
                            : '已连接 HTTPS 服务端，登录后可使用服务端模型与同步能力。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (account.error != null) ...[
              const SizedBox(height: 8),
              Text(
                account.error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: account.loading
                  ? null
                  : () => _showLoginDialog(context),
              child: account.loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('登录/注册'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLoginDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const LoginDialog(),
    );
  }
}
