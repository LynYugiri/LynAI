import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/agent_persistence.dart';
import '../providers/mcp_provider.dart';
import '../repositories/mcp_repository.dart';

class McpSettingsPage extends StatelessWidget {
  const McpSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<McpProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP 服务'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: provider.loading ? null : provider.load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('添加服务'),
      ),
      body: _body(context, provider),
    );
  }

  Widget _body(BuildContext context, McpProvider provider) {
    if (provider.loading && provider.servers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.loadError != null && provider.servers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(provider.loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: provider.load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (provider.servers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.hub_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              const Text('尚未配置 MCP 服务', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              const Text(
                '可连接远程 Streamable HTTP 服务；桌面端还可启动本地 stdio 服务。',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: provider.servers.length,
      itemBuilder: (context, index) => _ServerCard(
        state: provider.servers[index],
        onEdit: () => _showEditor(context, provider.servers[index]),
      ),
    );
  }

  Future<void> _showEditor(
    BuildContext context, [
    McpServerState? state,
  ]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _McpServerDialog(existing: state),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.state, required this.onEdit});

  final McpServerState state;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<McpProvider>();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(_statusIcon(state.status), color: _statusColor(context)),
        title: Text(
          state.server.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(_subtitle),
        trailing: Switch(
          value: state.server.enabled,
          onChanged: (value) =>
              provider.setServerEnabled(state.server.id, value),
        ),
        children: [
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑'),
                ),
                OutlinedButton.icon(
                  onPressed: state.status == McpServerStatus.connecting
                      ? null
                      : () => provider.testConnection(state.server.id),
                  icon: const Icon(Icons.network_check),
                  label: const Text('测试'),
                ),
                if (state.status == McpServerStatus.connected)
                  OutlinedButton.icon(
                    onPressed: () => provider.disconnect(state.server.id),
                    icon: const Icon(Icons.link_off),
                    label: const Text('断开'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: state.status == McpServerStatus.connecting
                        ? null
                        : () => provider.connect(state.server.id),
                    icon: const Icon(Icons.link),
                    label: const Text('连接'),
                  ),
              ],
            ),
          ),
          if (state.tools.isEmpty)
            const ListTile(
              dense: true,
              leading: Icon(Icons.build_outlined),
              title: Text('连接后显示服务发现的工具'),
            )
          else
            ...state.tools.map(
              (tool) => SwitchListTile(
                dense: true,
                value: provider.isToolEnabled(state.server.id, tool.name),
                title: Text(tool.name),
                subtitle: tool.description.isEmpty
                    ? null
                    : Text(tool.description),
                onChanged: (value) =>
                    provider.setToolEnabled(state.server.id, tool.name, value),
              ),
            ),
        ],
      ),
    );
  }

  String get _subtitle {
    final target = state.server.transport == 'stdio'
        ? state.server.command ?? ''
        : state.server.url ?? '';
    return '${_statusLabel(state.status)} · $target';
  }

  Color _statusColor(BuildContext context) => switch (state.status) {
    McpServerStatus.connected => Colors.green,
    McpServerStatus.connecting => Colors.orange,
    McpServerStatus.failed => Theme.of(context).colorScheme.error,
    McpServerStatus.disconnected => Colors.grey,
  };

  IconData _statusIcon(McpServerStatus status) => switch (status) {
    McpServerStatus.connected => Icons.check_circle_outline,
    McpServerStatus.connecting => Icons.sync,
    McpServerStatus.failed => Icons.error_outline,
    McpServerStatus.disconnected => Icons.radio_button_unchecked,
  };

  String _statusLabel(McpServerStatus status) => switch (status) {
    McpServerStatus.connected => '已连接',
    McpServerStatus.connecting => '连接中',
    McpServerStatus.failed => '连接失败',
    McpServerStatus.disconnected => '未连接',
  };
}

class _McpServerDialog extends StatefulWidget {
  const _McpServerDialog({this.existing});

  final McpServerState? existing;

  @override
  State<_McpServerDialog> createState() => _McpServerDialogState();
}

class _McpServerDialogState extends State<_McpServerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _target;
  late final TextEditingController _arguments;
  late final TextEditingController _credentials;
  late String _transport;
  late bool _allowHttp;
  late bool _allowPrivate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _transport = existing?.server.transport == 'stdio' ? 'stdio' : 'http';
    _name = TextEditingController(text: existing?.server.name ?? '');
    _target = TextEditingController(
      text: _transport == 'stdio'
          ? existing?.server.command ?? ''
          : existing?.server.url ?? '',
    );
    _arguments = TextEditingController(
      text: existing?.server.arguments.join('\n') ?? '',
    );
    _credentials = TextEditingController(
      text:
          existing?.server.environmentNames
              .map(
                (name) => existing.preferences.credentialTargets[name] ?? name,
              )
              .join('\n') ??
          '',
    );
    _allowHttp = existing?.preferences.allowHttp ?? false;
    _allowPrivate = existing?.preferences.allowPrivateNetwork ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _arguments.dispose();
    _credentials.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supportsStdio = context.read<McpProvider>().supportsStdio;
    return AlertDialog(
      title: Text(widget.existing == null ? '添加 MCP 服务' : '编辑 MCP 服务'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: [
                    const ButtonSegment(
                      value: 'http',
                      icon: Icon(Icons.cloud_outlined),
                      label: Text('远程 HTTP'),
                    ),
                    ButtonSegment(
                      value: 'stdio',
                      enabled: supportsStdio,
                      icon: const Icon(Icons.terminal),
                      label: const Text('桌面 stdio'),
                    ),
                  ],
                  selected: {_transport},
                  onSelectionChanged: (value) {
                    setState(() {
                      _transport = value.single;
                      _target.clear();
                    });
                  },
                ),
                if (!supportsStdio)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('stdio 仅支持 Linux、macOS 和 Windows'),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    border: OutlineInputBorder(),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _target,
                  decoration: InputDecoration(
                    labelText: _transport == 'stdio' ? '可执行命令' : '服务 URL',
                    hintText: _transport == 'stdio'
                        ? 'npx'
                        : 'https://example.com/mcp',
                    border: const OutlineInputBorder(),
                  ),
                  validator: _validateTarget,
                ),
                if (_transport == 'stdio') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _arguments,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: '参数（每行一个）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ] else ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _allowHttp,
                    title: const Text('允许未加密 HTTP'),
                    subtitle: const Text('仅用于受控测试环境'),
                    onChanged: (value) => setState(() => _allowHttp = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _allowPrivate,
                    title: const Text('允许私网地址'),
                    subtitle: const Text('包括 localhost、局域网 IP 和 .local'),
                    onChanged: (value) => setState(() => _allowPrivate = value),
                  ),
                ],
                TextFormField(
                  controller: _credentials,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: _transport == 'stdio'
                        ? '环境变量（每行 NAME 或 NAME=值）'
                        : '请求头（每行 Name 或 Name=值）',
                    helperText: '值只写入系统安全存储；留空值可保留已有凭据',
                    border: const OutlineInputBorder(),
                  ),
                  validator: _validateCredentials,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '必填' : null;

  String? _validateTarget(String? value) {
    final required = _required(value);
    if (required != null || _transport == 'stdio') return required;
    final uri = Uri.tryParse(value!.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '请输入有效 URL';
    if (uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return 'URL 不得包含凭据、查询参数或片段';
    }
    if (uri.scheme != 'https' && !(_allowHttp && uri.scheme == 'http')) {
      return '默认必须使用 HTTPS';
    }
    return null;
  }

  String? _validateCredentials(String? value) {
    for (final line in _lines(value ?? '')) {
      final name = line.split('=').first.trim();
      if (_transport == 'stdio' &&
          !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) {
        return '无效环境变量名: $name';
      }
      if (_transport == 'http' && (name.isEmpty || name.contains(':'))) {
        return '无效请求头名称: $name';
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      final now = DateTime.now();
      final parsedCredentials = <String, String>{};
      final names = <String>[];
      final credentialTargets = <String, String>{};
      final existingAliases = {
        for (final entry
            in existing?.preferences.credentialTargets.entries ??
                const <MapEntry<String, String>>[])
          entry.value: entry.key,
      };
      for (final line in _lines(_credentials.text)) {
        final separator = line.indexOf('=');
        final target = (separator < 0 ? line : line.substring(0, separator))
            .trim();
        final name = _transport == 'http'
            ? existingAliases[target] ?? _nextHeaderAlias(names)
            : target;
        names.add(name);
        if (_transport == 'http') credentialTargets[name] = target;
        if (separator >= 0) {
          parsedCredentials[name] = line.substring(separator + 1).trim();
        }
      }
      final id =
          existing?.server.id ??
          'mcp_${now.microsecondsSinceEpoch.toRadixString(36)}';
      final server = AgentMcpServerRecord(
        id: id,
        name: _name.text.trim(),
        transport: _transport,
        enabled: existing?.server.enabled ?? true,
        command: _transport == 'stdio' ? _target.text.trim() : null,
        url: _transport == 'http' ? _target.text.trim() : null,
        arguments: _transport == 'stdio' ? _lines(_arguments.text) : const [],
        environmentNames: names,
        createdAt: existing?.server.createdAt ?? now,
        updatedAt: now,
      );
      await context.read<McpProvider>().saveServer(
        server: server,
        preferences: McpServerPreferences(
          allowHttp: _transport == 'http' && _allowHttp,
          allowPrivateNetwork: _transport == 'http' && _allowPrivate,
          enabledTools: existing?.preferences.enabledTools ?? const {},
          credentialTargets: credentialTargets,
        ),
        credentials: parsedCredentials,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $error')));
      setState(() => _saving = false);
    }
  }

  List<String> _lines(String value) => value
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);

  String _nextHeaderAlias(List<String> names) {
    var index = 1;
    while (names.contains('MCP_HEADER_$index')) {
      index++;
    }
    return 'MCP_HEADER_$index';
  }
}
