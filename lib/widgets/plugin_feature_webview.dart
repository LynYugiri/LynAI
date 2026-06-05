import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_all/webview_all.dart';

import '../models/plugin.dart';
import '../providers/conversation_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import '../services/lynai_function_service.dart';
import '../utils/plugin_path_utils.dart';

/// 在 WebView 中渲染插件功能页，并提供 JS Bridge 与原生能力交互。
class PluginFeatureWebView extends StatefulWidget {
  final InstalledPlugin plugin;
  final PluginFeaturePageDefinition page;

  const PluginFeatureWebView({
    super.key,
    required this.plugin,
    required this.page,
  });

  @override
  State<PluginFeatureWebView> createState() => _PluginFeatureWebViewState();
}

class _PluginFeatureWebViewState extends State<PluginFeatureWebView> {
  WebViewController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEntry();
  }

  @override
  void didUpdateWidget(covariant PluginFeatureWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plugin.path != widget.plugin.path ||
        oldWidget.page.entry != widget.page.entry) {
      _loadEntry();
    }
  }

  /// 加载插件功能页的入口 HTML 文件。
  void _loadEntry() {
    final path = safePluginFilePath(widget.plugin.path, widget.page.entry);
    if (path == null) {
      setState(() {
        _controller = null;
        _error = '插件入口路径不安全: ${widget.page.entry}';
      });
      return;
    }
    final customFile = File(path);
    File? loadFile;
    if (customFile.existsSync()) {
      loadFile = customFile;
    } else {
      final defaultRel = context.read<PluginProvider>().defaultPathFor(
        widget.plugin.id,
        widget.page.entry,
      );
      if (defaultRel != null) {
        final defaultPath = safePluginFilePath(
          widget.plugin.path,
          defaultRel,
        );
        if (defaultPath != null) {
          final defaultFile = File(defaultPath);
          if (defaultFile.existsSync()) loadFile = defaultFile;
        }
      }
    }
    if (loadFile == null) {
      setState(() {
        _controller = null;
        _error = '插件入口文件不存在: ${widget.page.entry}';
      });
      return;
    }
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'LynAIBridge',
        onMessageReceived: (message) => _handleBridgeMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _injectBridge(),
          onNavigationRequest: (request) {
            final targetPath = _filePathFromUrl(request.url);
            if (targetPath == null) return NavigationDecision.prevent;
            final root = Directory(
              widget.plugin.path,
            ).absolute.path.replaceAll('\\', '/');
            final normalized = targetPath.replaceAll('\\', '/');
            return normalized.startsWith('$root/')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.file(loadFile.absolute.path));
    setState(() {
      _controller = controller;
      _error = null;
    });
  }

  /// 从 file:// URL 中提取本地文件路径。
  String? _filePathFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'file') return null;
    try {
      return uri.toFilePath();
    } catch (_) {
      return null;
    }
  }

  /// 向 WebView 注入 LynAI JS Bridge 脚本。
  Future<void> _injectBridge() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.runJavaScript(r'''
(function () {
  if (window.lynai && window.lynai.call) return;
  var seq = 0;
  var pending = {};
  window.__lynaiBridgeResolve = function (payload) {
    var item = pending[payload.id];
    if (!item) return;
    delete pending[payload.id];
    if (payload.ok) {
      item.resolve(payload.result);
    } else {
      item.reject(new Error(payload.error || 'LynAI bridge call failed'));
    }
  };
  window.lynai = {
    call: function (method, params) {
      return new Promise(function (resolve, reject) {
        if (!window.LynAIBridge || !window.LynAIBridge.postMessage) {
          reject(new Error('LynAI bridge is unavailable'));
          return;
        }
        var id = 'req_' + (++seq) + '_' + Date.now();
        pending[id] = { resolve: resolve, reject: reject };
        window.LynAIBridge.postMessage(JSON.stringify({
          id: id,
          method: method,
          params: params || {}
        }));
      });
    }
  };
  window.dispatchEvent(new Event('lynai-ready'));
})();
''');
  }

  /// 处理来自 WebView 的 Bridge 调用请求。
  Future<void> _handleBridgeMessage(String message) async {
    String id = '';
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) throw Exception('Bridge 请求必须是对象');
      id = decoded['id']?.toString() ?? '';
      final method = decoded['method']?.toString() ?? '';
      if (id.isEmpty || method.isEmpty) {
        throw Exception('Bridge 请求缺少 id 或 method');
      }
      final result = _jsonMap(
        await _executeBridgeCall(method, decoded['params']),
      );
      await _sendBridgeResponse({'id': id, 'ok': true, 'result': result});
    } catch (e) {
      await _sendBridgeResponse({
        'id': id,
        'ok': false,
        'error': e.toString().replaceFirst('Exception: ', ''),
      });
    }
  }

  /// 执行具体的 Bridge 方法调用，转发到 LynAIFunctionService。
  Future<Map<String, dynamic>> _executeBridgeCall(
    String method,
    Object? params,
  ) async {
    if (!widget.plugin.grantedPermissions.contains('webview:bridge')) {
      throw Exception('插件未授权 webview:bridge');
    }
    final args = params is Map
        ? Map<String, dynamic>.from(params)
        : <String, dynamic>{};
    final result = await LynAIFunctionService().execute(
      LynAIFunctionCall(name: method, arguments: args),
      LynAIFunctionContext(
        features: context.read<FeatureProvider>(),
        modelConfigs: context.read<ModelConfigProvider>(),
        settings: context.read<SettingsProvider>(),
        plugins: context.read<PluginProvider>(),
        conversations: context.read<ConversationProvider>(),
        plugin: widget.plugin,
        showToast: (message) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
          }
        },
      ),
    );
    if (result['ok'] != true) {
      throw Exception(
        result['error']?.toString() ?? 'Bridge 调用失败: $method',
      );
    }
    return result;
  }

  /// 向 WebView 发送 Bridge 调用的响应结果。
  Future<void> _sendBridgeResponse(Map<String, dynamic> payload) async {
    final controller = _controller;
    if (controller == null) return;
    final json = jsonEncode(payload);
    await controller.runJavaScript(
      'window.__lynaiBridgeResolve?.($json);',
    );
  }

  /// 将动态值转换为 JSON 安全的 Map 结构。
  static Map<String, dynamic> _jsonMap(dynamic source) {
    if (source is List) {
      return {'data': source.map(_jsonValue).toList()};
    }
    if (source is Map) {
      return source.map((k, v) => MapEntry(k.toString(), _jsonValue(v)));
    }
    return {'value': _jsonValue(source)};
  }

  /// 将动态值转换为 JSON 安全的基本类型值。
  static Object? _jsonValue(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is List) return value.map(_jsonValue).toList(growable: false);
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _jsonValue(item)),
      );
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    if (_controller != null) {
      return WebViewWidget(controller: _controller!);
    }
    return const Center(child: CircularProgressIndicator());
  }
}
