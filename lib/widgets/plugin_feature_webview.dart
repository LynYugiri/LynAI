import 'dart:async';
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
import '../services/lynai_call_identity.dart';
import '../services/lynai_function_service.dart';
import '../utils/plugin_path_utils.dart';
import '../utils/webview_dispose_utils.dart';

/// 在 WebView 中渲染插件功能页，并提供 JS Bridge 与原生能力交互。
class PluginFeatureWebView extends StatefulWidget {
  final InstalledPlugin plugin;
  final PluginFeaturePageDefinition page;
  final double linuxOverlayBottomInset;

  const PluginFeatureWebView({
    super.key,
    required this.plugin,
    required this.page,
    this.linuxOverlayBottomInset = 0,
  });

  @override
  State<PluginFeatureWebView> createState() => _PluginFeatureWebViewState();
}

class _PluginFeatureWebViewState extends State<PluginFeatureWebView> {
  WebViewController? _controller;
  String? _error;
  final int _renderSession = DateTime.now().microsecondsSinceEpoch;
  int _loadGeneration = 0;
  int? _renderVersion;
  Directory? _activeRenderRoot;

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
      _renderVersion = context.read<PluginProvider>().renderVersion(
        widget.plugin.id,
      );
      _loadEntry();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final version = context.watch<PluginProvider>().renderVersion(
      widget.plugin.id,
    );
    if (_renderVersion == null) {
      _renderVersion = version;
      return;
    }
    if (_renderVersion != version) {
      _renderVersion = version;
      _loadEntry();
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(WebViewDisposeUtils.disposeDesktop(controller));
    }
    final renderRoot = _activeRenderRoot;
    if (renderRoot != null) unawaited(_deleteDirectory(renderRoot));
    super.dispose();
  }

  /// 加载插件功能页的入口 HTML 文件。
  Future<void> _loadEntry() async {
    final generation = ++_loadGeneration;
    final previousRenderRoot = _activeRenderRoot;
    _activeRenderRoot = null;
    await _detachCurrentWebView();
    if (previousRenderRoot != null) {
      unawaited(_deleteDirectory(previousRenderRoot));
    }
    if (!mounted || generation != _loadGeneration) return;

    final path = safePluginFilePath(widget.plugin.path, widget.page.entry);
    if (path == null) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _controller = null;
        _error = '插件入口路径不安全: ${widget.page.entry}';
      });
      return;
    }
    final renderEntry = await _buildRenderEntry(generation);
    if (!mounted || generation != _loadGeneration) {
      if (renderEntry != null) unawaited(_deleteDirectory(renderEntry.root));
      return;
    }
    if (renderEntry == null) {
      setState(() {
        _controller = null;
        _error = '插件入口文件不存在: ${widget.page.entry}';
      });
      return;
    }
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Theme.of(context).colorScheme.surface);
    final renderRoot = renderEntry.root.absolute.path.replaceAll('\\', '/');
    controller
      ..addJavaScriptChannel(
        'LynAIBridge',
        onMessageReceived: (message) => _handleBridgeMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            unawaited(_injectBridge(controller, generation));
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false) return;
            if (!mounted || generation != _loadGeneration) return;
            final failedController = _controller == controller
                ? controller
                : null;
            setState(() {
              _controller = null;
              _error = '插件页面加载失败: ${error.description}';
            });
            if (failedController != null) {
              unawaited(WebViewDisposeUtils.disposeDesktop(failedController));
            }
          },
          onNavigationRequest: (request) {
            return _isAllowedNavigation(request.url, renderRoot)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );
    try {
      await controller.loadFile(renderEntry.file.absolute.path);
    } catch (e) {
      await WebViewDisposeUtils.disposeDesktop(controller);
      if (!mounted || generation != _loadGeneration) {
        unawaited(_deleteDirectory(renderEntry.root));
        return;
      }
      setState(() {
        _controller = null;
        _error = '插件页面加载失败: $e';
      });
      unawaited(_deleteDirectory(renderEntry.root));
      return;
    }
    if (!mounted || generation != _loadGeneration) {
      await WebViewDisposeUtils.disposeDesktop(controller);
      unawaited(_deleteDirectory(renderEntry.root));
      return;
    }
    _activeRenderRoot = renderEntry.root;
    setState(() {
      _controller = controller;
      _error = null;
    });
  }

  /// 从 Flutter 树中移除当前 WebView，让 webview_all 自行恢复原生输入区域。
  Future<void> _detachCurrentWebView() async {
    final controller = _controller;
    if (controller == null) return;
    if (mounted) {
      setState(() => _controller = null);
    }
    await WebViewDisposeUtils.waitForNativeDetach();
    await WebViewDisposeUtils.disposeDesktop(controller);
  }

  /// 构建 WebView 渲染目录，使相对资源也按“根目录覆盖 defaults/”解析。
  Future<_RenderEntry?> _buildRenderEntry(int generation) async {
    final renderRoot = _renderRoot(generation);
    await renderRoot.create(recursive: true);
    await _copyRootResources(renderRoot);
    await _copyDefaultMappedFiles(renderRoot);
    final entryPath = safePluginFilePath(renderRoot.path, widget.page.entry);
    if (entryPath == null) return null;
    final entry = File(entryPath);
    if (await entry.exists()) {
      return _RenderEntry(root: renderRoot, file: entry);
    }
    await _deleteDirectory(renderRoot);
    return null;
  }

  /// 构建渲染目录路径，确保每次加载使用独立目录避免缓存问题。
  Directory _renderRoot(int generation) {
    return Directory(
      '${Directory.systemTemp.path}/lynai_plugin_webview/${_safeSegment(widget.plugin.id)}_${_safeSegment(widget.page.id)}_${_renderSession}_$generation',
    );
  }

  /// 安全删除临时渲染目录，失败时静默忽略。
  Future<void> _deleteDirectory(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {}
  }

  /// 复制插件根目录下的资源文件到渲染目录，隐藏受保护路径。
  Future<void> _copyRootResources(Directory renderRoot) async {
    final root = Directory(widget.plugin.path);
    if (!await root.exists()) return;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relativePath = _relativePluginPath(root.path, entity.path);
      if (relativePath == null || _isHiddenRenderPath(relativePath)) continue;
      final targetPath = safePluginFilePath(renderRoot.path, relativePath);
      if (targetPath == null) continue;
      final target = File(targetPath);
      if (!await target.parent.exists()) {
        await target.parent.create(recursive: true);
      }
      await entity.copy(target.path);
    }
  }

  /// 将可编辑文件的 defaults 模板复制到渲染目录对应位置。
  Future<void> _copyDefaultMappedFiles(Directory renderRoot) async {
    for (final file in widget.plugin.manifest.editableFiles) {
      final defaultPath = file.defaultPath;
      if (defaultPath == null || defaultPath.isEmpty) continue;
      final targetPath = safePluginFilePath(renderRoot.path, file.path);
      if (targetPath == null) continue;
      final customPath = safePluginFilePath(widget.plugin.path, file.path);
      final defaultSafePath = safePluginFilePath(
        widget.plugin.path,
        defaultPath,
      );
      final source = customPath != null && await File(customPath).exists()
          ? File(customPath)
          : defaultSafePath == null
          ? null
          : File(defaultSafePath);
      if (source == null || !await source.exists()) continue;
      final target = File(targetPath);
      if (!await target.parent.exists()) {
        await target.parent.create(recursive: true);
      }
      await source.copy(target.path);
    }
  }

  /// 计算路径相对于插件根目录的相对路径。
  String? _relativePluginPath(String root, String path) {
    final normalizedRoot = root
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    final normalizedPath = path.replaceAll('\\', '/');
    if (!normalizedPath.startsWith('$normalizedRoot/')) return null;
    return normalizedPath.substring(normalizedRoot.length + 1);
  }

  /// 判断路径是否应在渲染时跳过（plugin.json、defaults/、配置文件、入口文件）。
  bool _isHiddenRenderPath(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    if (normalized == 'plugin.json') return true;
    if (normalized.startsWith('defaults/')) return true;
    if (normalized ==
        widget.plugin.manifest.config.path.replaceAll('\\', '/')) {
      return true;
    }
    if (normalized ==
        widget.plugin.manifest.config.schema.replaceAll('\\', '/')) {
      return true;
    }
    return normalized == widget.plugin.manifest.entry.replaceAll('\\', '/');
  }

  /// 将字符串中非合法文件名字符替换为下划线，防止文件名注入。
  String _safeSegment(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');
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

  /// 只允许插件临时渲染目录内资源；Windows loadFile 使用 webview_all 的本地虚拟域名。
  bool _isAllowedNavigation(String url, String renderRoot) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (Platform.isWindows &&
        uri.scheme == 'https' &&
        uri.host == 'app-file.webview.flutter.dev') {
      return true;
    }
    final targetPath = _filePathFromUrl(url);
    if (targetPath == null) return false;
    final normalized = targetPath.replaceAll('\\', '/');
    return normalized.startsWith('$renderRoot/');
  }

  /// 向 WebView 注入 LynAI JS Bridge 脚本。
  Future<void> _injectBridge(
    WebViewController controller,
    int generation,
  ) async {
    if (!mounted ||
        generation != _loadGeneration ||
        _controller != controller) {
      return;
    }
    try {
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
    } catch (e) {
      if (mounted &&
          generation == _loadGeneration &&
          _controller == controller) {
        debugPrint('注入插件 WebView Bridge 失败: $e');
      }
    }
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
        identity: LynAICallIdentity(
          type: LynAICallerType.pluginWebview,
          pluginId: widget.plugin.id,
          toolName: method,
        ),
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
      throw Exception(result['error']?.toString() ?? 'Bridge 调用失败: $method');
    }
    return result;
  }

  /// 向 WebView 发送 Bridge 调用的响应结果。
  Future<void> _sendBridgeResponse(Map<String, dynamic> payload) async {
    final controller = _controller;
    if (controller == null) return;
    final json = jsonEncode(payload);
    try {
      await controller.runJavaScript(
        'if (window.__lynaiBridgeResolve) window.__lynaiBridgeResolve($json);',
      );
    } catch (e) {
      if (mounted && _controller == controller) {
        debugPrint('发送插件 WebView Bridge 响应失败: $e');
      }
    }
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
      Widget webView = ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: WebViewWidget(controller: _controller!),
      );
      if (Platform.isLinux && widget.linuxOverlayBottomInset > 0) {
        webView = Padding(
          padding: EdgeInsets.only(bottom: widget.linuxOverlayBottomInset),
          child: webView,
        );
      }
      return webView;
    }
    return const Center(child: CircularProgressIndicator());
  }
}

/// 渲染目录包装，持有临时目录和入口文件的引用。
class _RenderEntry {
  final Directory root;
  final File file;

  const _RenderEntry({required this.root, required this.file});
}
