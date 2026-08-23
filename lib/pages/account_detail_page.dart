import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../providers/account_provider.dart';
import '../utils/snackbar_utils.dart';

/// 账号详情页。
///
/// 展示当前登录用户的头像、用户名、手机号和连接状态，支持修改用户名；
/// 退出登录按钮固定在页面底部。账号在页面打开期间失效时显示未登录提示。
class AccountDetailPage extends StatefulWidget {
  const AccountDetailPage({super.key});

  @override
  State<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends State<AccountDetailPage> {
  late final TextEditingController _displayNameController;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: context.read<AccountProvider>().user?.displayName ?? '',
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _saveDisplayName() async {
    final name = _displayNameController.text.trim();
    if (name.isEmpty) {
      showShortSnackBar(context, '用户名不能为空');
      return;
    }
    final account = context.read<AccountProvider>();
    final updated = await account.updateDisplayName(name);
    if (!mounted) return;
    if (updated != null) {
      _displayNameController.text = updated.displayName;
      showShortSnackBar(context, '用户名已更新');
    } else {
      showErrorSnackBar(context, '修改用户名失败', details: account.error);
    }
  }

  Future<void> _logout() async {
    final navigator = Navigator.of(context);
    final account = context.read<AccountProvider>();
    await account.logout();
    // LynAI 托管模型由公开的 /relay/config 下发，登出后仍需保留，
    // 保证未登录用户可以继续在模型列表中选择和调用上游模型。
    if (!mounted) return;
    if (account.user == null) {
      showShortSnackBar(context, '已退出登录');
      if (navigator.canPop()) {
        navigator.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountProvider>();
    final user = account.user;
    return Scaffold(
      appBar: AppBar(title: const Text('账号详情'), centerTitle: true),
      body: user == null
          ? const Center(child: Text('未登录'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildUserHeader(context, user, account),
                const SizedBox(height: 12),
                _buildDisplayNameEditor(account),
                if (account.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    account.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 40),
                _buildLogoutButton(account),
              ],
            ),
    );
  }

  Widget _buildUserHeader(
    BuildContext context,
    AccountUser user,
    AccountProvider account,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.primary.withValues(
                alpha: 0.12,
              ),
              child: Text(
                user.displayName.isNotEmpty
                    ? user.displayName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontSize: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 16),
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
                            fontSize: 18,
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
                  if (user.phone.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(user.phone, style: theme.textTheme.bodyMedium),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    account.isBackendConnected ? '已连接服务端' : '本地账号 · 未连接后端',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisplayNameEditor(AccountProvider account) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _displayNameController,
              enabled: !account.loading,
              maxLength: 32,
              decoration: const InputDecoration(
                labelText: '用户名',
                hintText: '登录后显示的用户名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: account.loading ? null : _saveDisplayName,
              icon: account.loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(account.loading ? '保存中…' : '保存用户名'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton(AccountProvider account) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: account.loading ? null : _logout,
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.colorScheme.error,
        side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      icon: const Icon(Icons.logout),
      label: const Text('退出登录'),
    );
  }
}
