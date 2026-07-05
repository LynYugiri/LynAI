import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/account_provider.dart';
import '../providers/model_config_provider.dart';
import '../services/backend_client.dart';

/// 登录/注册对话框。
///
/// 手机号是唯一登录标识，密码用于后端认证。
/// 通过顶部 segmented control 切换登录与注册模式。
/// 注册模式下可选填昵称，不填则后端自动生成默认昵称。
class LoginDialog extends StatefulWidget {
  const LoginDialog({super.key, this.initialRegisterMode = false});

  final bool initialRegisterMode;

  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _isRegisterMode = false;

  @override
  void initState() {
    super.initState();
    _isRegisterMode = widget.initialRegisterMode;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountProvider>();
    return AlertDialog(
      title: Text(_isRegisterMode ? '注册' : '登录'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('登录')),
                  ButtonSegment(value: true, label: Text('注册')),
                ],
                selected: {_isRegisterMode},
                onSelectionChanged: (selection) {
                  setState(() => _isRegisterMode = selection.first);
                },
              ),
              const SizedBox(height: 16),
              _DemoAuthNotice(isRegisterMode: _isRegisterMode),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: '账号/手机号',
                  hintText: '可填写任意测试账号',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                keyboardType: TextInputType.text,
                validator: (value) {
                  final v = value?.trim() ?? '';
                  if (v.isEmpty) return '请输入账号';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: '密码',
                  hintText: '请输入密码',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
                validator: (value) {
                  final v = value ?? '';
                  if (v.isEmpty) return '请输入密码';
                  return null;
                },
              ),
              if (_isRegisterMode) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: const InputDecoration(
                    labelText: '确认密码',
                    hintText: '请再次输入密码',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_reset_outlined),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value != _passwordController.text) return '两次输入的密码不一致';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: '昵称（可选）',
                    hintText: '不填则使用默认昵称',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  maxLength: 32,
                ),
              ],
              if (account.error != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    account.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: account.loading ? null : _submit,
          child: Text(_isRegisterMode ? '注册' : '登录'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final account = context.read<AccountProvider>();
    account.clearError();

    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    final displayName = _displayNameController.text.trim();

    bool success;
    if (_isRegisterMode) {
      success = await account.register(
        phone,
        password,
        displayName: displayName.isEmpty ? null : displayName,
      );
    } else {
      success = await account.login(phone, password);
    }

    if (!mounted) return;
    if (success) {
      await context.read<ModelConfigProvider>().syncLynaiManagedProvider(
        context.read<BackendClient>(),
      );
      if (!mounted) return;
      Navigator.pop(context);
    }
    // 失败时保持对话框打开，错误会显示在表单内。
  }
}

class _DemoAuthNotice extends StatelessWidget {
  const _DemoAuthNotice({required this.isRegisterMode});

  final bool isRegisterMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = isRegisterMode
        ? '演示后端已内置，没有短信、邮箱或实名验证；可随意填写账号和密码。注册成功后会直接登录，有账号才能调用服务端提供的模型。'
        : '演示后端已内置，没有任何身份验证；可使用任意测试账号登录。登录账号后才能调用服务端提供的模型。';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSecondaryContainer,
        ),
      ),
    );
  }
}
