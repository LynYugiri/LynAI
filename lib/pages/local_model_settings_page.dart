import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/model_config.dart';
import '../services/on_device_llm_service.dart';

/// BlueLM 本地模型设置页。
///
/// 模型不打包进 APK，像 Demo 一样从设备路径读取。页面始终可访问；
/// 只有在模型校验通过或初始化成功后，本地模型才会出现在聊天模型列表中。
class LocalModelSettingsPage extends StatefulWidget {
  const LocalModelSettingsPage({super.key});

  @override
  State<LocalModelSettingsPage> createState() => _LocalModelSettingsPageState();
}

class _LocalModelSettingsPageState extends State<LocalModelSettingsPage>
    with WidgetsBindingObserver {
  late final TextEditingController _pathController;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final service = context.read<OnDeviceLlmService>();
    final path = service.status.modelPath;
    _pathController = TextEditingController(
      text: path.isEmpty ? OnDeviceLlmService.defaultModelPath : path,
    );
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pathController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final service = context.read<OnDeviceLlmService>();
    await _run(() async {
      await service.refreshStatus();
    });
  }

  Future<void> _run(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      if (successMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(localLlmErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.read<OnDeviceLlmService>();
    return Scaffold(
      appBar: AppBar(title: const Text('本地模型'), centerTitle: true),
      body: ListenableBuilder(
        listenable: service,
        builder: (context, _) {
          final current = service.status;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _statusCard(current),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '模型路径',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '填写模型目录或 bluelm_mtk_llm_config.json 完整路径。'
                        '与 Demo 相同，默认读取 /sdcard/1225。',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pathController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: OnDeviceLlmService.defaultModelPath,
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                await service.setModelPath(
                                  _pathController.text.trim(),
                                );
                              }, successMessage: '模型路径已保存并重新校验'),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('保存路径'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                () async {
                                  await service.requestStoragePermission();
                                },
                                successMessage: current.storagePermission
                                    ? '已获得存储权限'
                                    : null,
                              ),
                        icon: const Icon(Icons.folder_open),
                        label: Text(
                          current.storagePermission ? '存储权限已授权' : '授权所有文件访问',
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _refresh,
                        icon: const Icon(Icons.search),
                        label: const Text('检测模型文件'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                await service.ensureReady(
                                  ModelConfig.localBlueLm(),
                                );
                              }, successMessage: '本地模型初始化成功'),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(current.isReady ? '重新初始化' : '初始化模型'),
                      ),
                      if (current.isReady) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  await service.release();
                                  await service.refreshStatus();
                                }, successMessage: '本地模型已释放'),
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('释放模型'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (current.missingFiles.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '缺失文件（${current.missingFiles.length}）',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final file in current.missingFiles.take(12))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• $file',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        if (current.missingFiles.length > 12)
                          Text(
                            '… 还有 ${current.missingFiles.length - 12} 个文件',
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '说明\n'
                    '• 目标设备：MediaTek DX5（MT6993 等）\n'
                    '• 建议通过 adb push 1.7.0.4_1225_mtk9500 /sdcard/1225/ '
                    '部署模型\n'
                    '• 模型校验或初始化失败时，本地模型不会出现在聊天模型列表中',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statusCard(LocalLlmStatus status) {
    final (label, color, detail) = _describe(status);
    return Card(
      color: color.withValues(alpha: 0.08),
      child: ListTile(
        leading: Icon(_stateIcon(status), color: color),
        title: Text(
          label,
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
        subtitle: Text(
          detail,
          style: const TextStyle(fontSize: 12, height: 1.5),
        ),
      ),
    );
  }

  IconData _stateIcon(LocalLlmStatus status) {
    return switch (status.state) {
      LocalLlmState.ready => Icons.check_circle_outline,
      LocalLlmState.validated => Icons.verified_outlined,
      LocalLlmState.initializing => Icons.hourglass_top,
      LocalLlmState.error ||
      LocalLlmState.invalidModel ||
      LocalLlmState.modelNotFound => Icons.error_outline,
      LocalLlmState.permissionRequired => Icons.lock_outline,
      LocalLlmState.unsupported => Icons.block,
      LocalLlmState.notConfigured => Icons.edit_location_alt_outlined,
      LocalLlmState.unknown => Icons.help_outline,
    };
  }

  (String, Color, String) _describe(LocalLlmStatus status) {
    final path = status.resolvedConfigPath ?? status.modelPath;
    switch (status.state) {
      case LocalLlmState.ready:
        return (
          '已就绪',
          Colors.green,
          status.modelVersion == null
              ? path
              : '$path\n模型版本: ${status.modelVersion}',
        );
      case LocalLlmState.validated:
        return ('文件校验通过', Colors.teal, '$path\n尚未加载权重，首次发送时会自动初始化');
      case LocalLlmState.initializing:
        return ('正在初始化', Colors.blue, path);
      case LocalLlmState.permissionRequired:
        return ('需要存储权限', Colors.orange, '请授权“所有文件访问”后重新检测\n$path');
      case LocalLlmState.modelNotFound:
        return ('未找到模型配置', Colors.red, path);
      case LocalLlmState.invalidModel:
        return ('模型文件不完整', Colors.red, status.lastError ?? path);
      case LocalLlmState.error:
        return (
          '初始化失败',
          Colors.red,
          '${status.lastError ?? ''}'
              '${status.lastErrorCode == null ? '' : ' (${status.lastErrorCode})'}',
        );
      case LocalLlmState.unsupported:
        return (
          '当前设备不支持',
          Colors.red,
          '需要 arm64-v8a 的 MediaTek 设备（DX5/MT6993 等）',
        );
      case LocalLlmState.notConfigured:
        return ('尚未设置路径', Colors.blueGrey, '默认路径: ${status.modelPath}');
      case LocalLlmState.unknown:
        return ('正在检测', Colors.blueGrey, '请稍候…');
    }
  }
}
