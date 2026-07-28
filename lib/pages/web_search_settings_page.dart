import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/web_search.dart';
import '../providers/settings_provider.dart';
import '../services/secret_store.dart';
import '../services/web_search_service.dart';

class WebSearchSettingsPage extends StatefulWidget {
  const WebSearchSettingsPage({super.key});

  @override
  State<WebSearchSettingsPage> createState() => _WebSearchSettingsPageState();
}

class _WebSearchSettingsPageState extends State<WebSearchSettingsPage> {
  final _endpoint = TextEditingController();
  final _tavilyKey = TextEditingController();
  final _searxngToken = TextEditingController();
  bool _loading = true;
  bool _allowSearxngHttp = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = context.read<SettingsProvider>().settings;
    final secrets = context.read<SecretStore>();
    _endpoint.text = settings.searxngEndpoint ?? '';
    _allowSearxngHttp = settings.searxngAllowHttp;
    _tavilyKey.text =
        await secrets.read(TavilyWebSearchAdapter.apiKeySecretKey) ?? '';
    _searxngToken.text =
        await secrets.read(SearxngWebSearchAdapter.bearerTokenSecretKey) ?? '';
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _tavilyKey.dispose();
    _searxngToken.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final settingsProvider = context.read<SettingsProvider>();
    final secrets = context.read<SecretStore>();
    final rawEndpoint = _endpoint.text.trim();
    final endpoint = rawEndpoint.isEmpty ? null : Uri.tryParse(rawEndpoint);
    if (endpoint != null &&
        (endpoint.host.isEmpty ||
            endpoint.userInfo.isNotEmpty ||
            (endpoint.scheme != 'http' && endpoint.scheme != 'https'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SearXNG 地址必须是无凭据的 HTTP(S) URL')),
      );
      return;
    }
    if (endpoint?.scheme == 'http' && !_allowSearxngHttp) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('HTTP SearXNG 需要显式启用明文传输')));
      return;
    }
    if (endpoint?.scheme == 'http' &&
        _searxngToken.text.trim().isNotEmpty &&
        !await _confirmPlaintextBearer(endpoint!)) {
      return;
    }
    final settings = settingsProvider.settings;
    await settingsProvider.updateWebSearchSettings(
      route: settings.webSearchRoute,
      provider: settings.webSearchClientProvider,
      searxngEndpoint: endpoint?.toString(),
      searxngAllowHttp: endpoint?.scheme == 'http' && _allowSearxngHttp,
    );
    await _writeSecret(
      secrets,
      TavilyWebSearchAdapter.apiKeySecretKey,
      _tavilyKey.text,
    );
    await _writeSecret(
      secrets,
      SearxngWebSearchAdapter.bearerTokenSecretKey,
      _searxngToken.text,
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('网页搜索设置已保存')));
    }
  }

  Future<bool> _confirmPlaintextBearer(Uri endpoint) async {
    final origin = _origin(endpoint);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认明文发送 Bearer token'),
            content: Text(
              'Bearer token 将仅发送到 $origin，但 HTTP 无法加密传输内容或凭据。'
              '重定向不会继续携带 token。是否保存此显式授权？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('仍然允许'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _writeSecret(SecretStore store, String key, String value) async {
    final normalized = value.trim();
    normalized.isEmpty
        ? await store.delete(key)
        : await store.write(key, normalized);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    return Scaffold(
      appBar: AppBar(title: const Text('网页搜索')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<WebSearchRoute>(
                  initialValue: settings.webSearchRoute,
                  decoration: const InputDecoration(labelText: '路由策略'),
                  items: const [
                    DropdownMenuItem(
                      value: WebSearchRoute.auto,
                      child: Text('自动：客户端优先，失败后服务端'),
                    ),
                    DropdownMenuItem(
                      value: WebSearchRoute.client,
                      child: Text('仅客户端'),
                    ),
                    DropdownMenuItem(
                      value: WebSearchRoute.backend,
                      child: Text('仅 LynAI 服务端'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    context.read<SettingsProvider>().updateWebSearchSettings(
                      route: value,
                      provider: settings.webSearchClientProvider,
                      searxngEndpoint: settings.searxngEndpoint,
                      searxngAllowHttp: settings.searxngAllowHttp,
                    );
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<WebSearchClientProvider>(
                  initialValue: settings.webSearchClientProvider,
                  decoration: const InputDecoration(
                    labelText: '客户端首选 Provider',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: WebSearchClientProvider.tavily,
                      child: Text('Tavily'),
                    ),
                    DropdownMenuItem(
                      value: WebSearchClientProvider.searxng,
                      child: Text('SearXNG'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    context.read<SettingsProvider>().updateWebSearchSettings(
                      route: settings.webSearchRoute,
                      provider: value,
                      searxngEndpoint: settings.searxngEndpoint,
                      searxngAllowHttp: settings.searxngAllowHttp,
                    );
                  },
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _allowSearxngHttp,
                  onChanged: (value) =>
                      setState(() => _allowSearxngHttp = value ?? false),
                  title: const Text('允许此 SearXNG 地址使用 HTTP'),
                  subtitle: const Text(
                    '仅授权当前配置地址的精确 origin；查询和 Bearer token 将以明文传输。',
                  ),
                ),
                if (_allowSearxngHttp &&
                    Uri.tryParse(_endpoint.text.trim())?.scheme == 'http')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      '明文授权 origin：${_origin(Uri.parse(_endpoint.text.trim()))}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _endpoint,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'SearXNG 搜索地址',
                    hintText: 'https://search.example/search',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _tavilyKey,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Tavily API key',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searxngToken,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'SearXNG Bearer token（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: _save, child: const Text('保存')),
                const SizedBox(height: 12),
                const Text('密钥和 token 只写入系统安全存储；路由、Provider 和地址写入应用设置。'),
              ],
            ),
    );
  }
}

String _origin(Uri uri) {
  final port = uri.hasPort && uri.port != 80 ? ':${uri.port}' : '';
  return 'http://${uri.host.toLowerCase()}$port';
}
