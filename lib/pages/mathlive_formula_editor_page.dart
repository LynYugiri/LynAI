import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:webview_all/webview_all.dart';

import '../utils/webview_dispose_utils.dart';

/// 基于 MathLive WebView 的 LaTeX 公式编辑器。
///
/// 支持可视编辑（内嵌 MathLive）和源码模式（纯文本），预览通过 flutter_math_fork 渲染。
/// 在不支持内嵌 MathLive 的平台上自动回退到源码模式。
class MathLiveFormulaEditorPage extends StatefulWidget {
  final String initialFormula;
  final bool preferBlock;
  final String title;
  final bool? supportsEmbeddedMathLiveOverride;

  const MathLiveFormulaEditorPage({
    super.key,
    required this.initialFormula,
    required this.preferBlock,
    required this.title,
    this.supportsEmbeddedMathLiveOverride,
  });

  @override
  State<MathLiveFormulaEditorPage> createState() =>
      _MathLiveFormulaEditorPageState();
}

class _MathLiveFormulaEditorPageState extends State<MathLiveFormulaEditorPage> {
  late final TextEditingController _rawCtrl;
  WebViewController? _webCtrl;
  Timer? _readyTimeout;
  var _formula = '';
  var _mathLiveReady = false;
  var _keyboardVisible = false;
  var _syncingFromWeb = false;
  var _useSourceMode = false;
  var _webViewActive = true;
  var _closing = false;
  String? _lastThemePayload;
  String? _notice;

  bool get _supportsEmbeddedMathLive {
    final override = widget.supportsEmbeddedMathLiveOverride;
    if (override != null) return override;
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      _ => false,
    };
  }

  @override
  void initState() {
    super.initState();
    _formula = widget.initialFormula.trim();
    _rawCtrl = TextEditingController(text: _formula);
    _useSourceMode = !_supportsEmbeddedMathLive;
    if (!_supportsEmbeddedMathLive) {
      _notice = '当前平台暂不支持内嵌 MathLive，可继续使用源码模式编辑公式。';
      return;
    }
    _webCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xff101216))
      ..addJavaScriptChannel(
        'MathLiveBridge',
        onMessageReceived: (message) {
          _handleBridgeMessage(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _scheduleReadyTimeout();
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false) return;
            _fallbackToSourceMode(
              'MathLive 加载失败：${error.description}，已切到源码模式。',
            );
          },
        ),
      )
      ..loadFlutterAsset(_mathLiveEditorAssetKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pushThemeToMathLive();
  }

  @override
  void dispose() {
    unawaited(_cleanupMathLiveEditor());
    final controller = _webCtrl;
    _webCtrl = null;
    if (controller != null) {
      unawaited(WebViewDisposeUtils.disposeDesktop(controller));
    }
    _readyTimeout?.cancel();
    _rawCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _closeEditor),
        title: Text(widget.title),
        actions: [
          TextButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.check),
            label: const Text('完成'),
          ),
        ],
      ),
      body: PopScope(
        canPop: !_supportsEmbeddedMathLive || _closing,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || _closing) return;
          _closeEditor();
        },
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(compact ? 10 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_notice != null) _noticeBanner(),
                _modeBar(compact),
                if (_useSourceMode) ...[
                  const SizedBox(height: 10),
                  _previewCard(context),
                ],
                const SizedBox(height: 10),
                Expanded(
                  child: _useSourceMode
                      ? _sourceEditor()
                      : _visualEditor(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeBar(bool compact) {
    final modeSwitcher = SegmentedButton<bool>(
      segments: const [
        ButtonSegment<bool>(
          value: false,
          icon: Icon(Icons.functions),
          label: Text('可视编辑'),
        ),
        ButtonSegment<bool>(
          value: true,
          icon: Icon(Icons.code),
          label: Text('源码模式'),
        ),
      ],
      selected: {_useSourceMode},
      onSelectionChanged: (selection) {
        final next = selection.first;
        if (!next && !_supportsEmbeddedMathLive) {
          _showNotice('当前平台暂不支持内嵌 MathLive，可继续使用源码模式。');
          return;
        }
        setState(() {
          _useSourceMode = next;
          if (next) _formula = _rawCtrl.text;
        });
        if (!next) {
          _formula = _rawCtrl.text;
          _pushFormulaToMathLive(_rawCtrl.text);
        } else {
          _setKeyboardVisible(false, activateNativeInput: false);
        }
      },
    );
    final keyboardButton = !_useSourceMode && _supportsEmbeddedMathLive
        ? OutlinedButton.icon(
            onPressed: _toggleKeyboard,
            icon: Icon(_keyboardVisible ? Icons.keyboard_hide : Icons.keyboard),
            label: Text(_keyboardVisible ? '收起键盘' : '键盘'),
          )
        : null;
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          modeSwitcher,
          if (keyboardButton != null) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: keyboardButton),
          ],
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: modeSwitcher),
        if (keyboardButton != null) ...[
          const SizedBox(width: 10),
          keyboardButton,
        ],
      ],
    );
  }

  Widget _noticeBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MaterialBanner(
        content: Text(_notice!),
        actions: [
          TextButton(
            onPressed: () => setState(() => _notice = null),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _previewCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.preferBlock ? '块级预览' : '行内预览',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 10),
          if (_formula.trim().isEmpty)
            Text(
              '输入公式后会在这里实时预览',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Math.tex(
                _formula,
                mathStyle: widget.preferBlock
                    ? MathStyle.display
                    : MathStyle.text,
                textStyle: TextStyle(
                  fontSize: widget.preferBlock ? 24 : 20,
                  color: scheme.onSurface,
                ),
                onErrorFallback: (_) => Text(
                  '公式暂时无法渲染，请检查语法',
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sourceEditor() {
    return TextField(
      controller: _rawCtrl,
      autofocus: true,
      expands: true,
      minLines: null,
      maxLines: null,
      style: const TextStyle(fontFamily: 'Hurmit Nerd Font', height: 1.45),
      decoration: const InputDecoration(
        labelText: 'LaTeX 源码',
        hintText: r'例如 E = mc^2、\frac{x}{y}、\begin{matrix}a&b\\c&d\end{matrix}',
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
      onChanged: (value) async {
        if (_syncingFromWeb) return;
        setState(() => _formula = value);
        await _pushFormulaToMathLive(value);
      },
      onSubmitted: (_) => _submit(),
    );
  }

  Widget _visualEditor(BuildContext context) {
    final controller = _webCtrl;
    if (!_webViewActive) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller == null) return _sourceEditor();
    final editor = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: controller)),
          if (!_mathLiveReady)
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.88),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('MathLive 加载中...'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (_usesOverlayWebView) return editor;
    return ClipRRect(borderRadius: BorderRadius.circular(16), child: editor);
  }

  bool get _usesOverlayWebView {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.linux;
  }

  Future<void> _pushFormulaToMathLive(String formula) async {
    final controller = _webCtrl;
    if (!_supportsEmbeddedMathLive || controller == null || !_mathLiveReady) {
      return;
    }
    final encoded = jsonEncode(formula);
    await controller.runJavaScript('window.setFormula($encoded);');
  }

  Future<void> _configureMathLive() async {
    final controller = _webCtrl;
    if (!_supportsEmbeddedMathLive || controller == null || !_mathLiveReady) {
      return;
    }
    final encoded = jsonEncode({
      'displayMode': widget.preferBlock ? 'block' : 'inline',
    });
    await controller.runJavaScript('window.configureMathLive($encoded);');
  }

  Future<void> _setKeyboardVisible(
    bool visible, {
    bool activateNativeInput = true,
  }) async {
    final controller = _webCtrl;
    if (!_supportsEmbeddedMathLive || controller == null || !_mathLiveReady) {
      return;
    }
    final encoded = jsonEncode({
      'visible': visible,
      'activateNativeInput': activateNativeInput,
    });
    await controller.runJavaScript('window.setKeyboardVisible($encoded);');
  }

  Future<void> _cleanupMathLiveEditor() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final controller = _webCtrl;
    if (controller == null || !_mathLiveReady) return;
    try {
      await controller.runJavaScript(
        'if (window.disposeMathLiveEditor) window.disposeMathLiveEditor();',
      );
    } catch (_) {
      // The platform webview may already be tearing down.
    }
  }

  Future<void> _detachWebView() async {
    await _cleanupMathLiveEditor();
    if (!mounted || !_webViewActive) return;
    setState(() {
      _webViewActive = false;
      _keyboardVisible = false;
    });
    await WebViewDisposeUtils.waitForNativeDetach();
    final controller = _webCtrl;
    _webCtrl = null;
    if (controller != null) {
      await WebViewDisposeUtils.disposeDesktop(controller);
    }
  }

  Future<void> _closeEditor() async {
    if (_closing) return;
    _closing = true;
    await _detachWebView();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _toggleKeyboard() {
    return _setKeyboardVisible(
      !_keyboardVisible,
      activateNativeInput: !_keyboardVisible,
    );
  }

  // 分派 WebView 发来的 JSON 消息：就绪、键盘可见性、错误、公式输入。
  void _handleBridgeMessage(String rawMessage) {
    if (!mounted) return;
    final dynamic decoded;
    try {
      decoded = jsonDecode(rawMessage);
    } catch (_) {
      _applyFormulaFromWeb(rawMessage);
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    final type = decoded['type'] as String? ?? 'input';
    switch (type) {
      case 'ready':
        _readyTimeout?.cancel();
        setState(() {
          _mathLiveReady = true;
          _keyboardVisible = false;
          _notice = null;
        });
        _configureMathLive();
        _pushThemeToMathLive();
        _pushFormulaToMathLive(_rawCtrl.text);
        break;
      case 'keyboard-visibility':
        final visible = decoded['visible'] == true;
        if (mounted) setState(() => _keyboardVisible = visible);
        break;
      case 'error':
        _fallbackToSourceMode(
          'MathLive 初始化失败：${decoded['message'] ?? '未知错误'}，已切到源码模式。',
        );
        break;
      case 'input':
        _applyFormulaFromWeb(decoded['latex'] as String? ?? '');
        break;
      default:
        break;
    }
  }

  void _applyFormulaFromWeb(String latex) {
    _syncingFromWeb = true;
    try {
      if (_rawCtrl.text != latex) {
        _rawCtrl.value = TextEditingValue(
          text: latex,
          selection: TextSelection.collapsed(offset: latex.length),
        );
      }
      if (_useSourceMode) {
        if (mounted) setState(() => _formula = latex);
      } else {
        _formula = latex;
      }
    } finally {
      _syncingFromWeb = false;
    }
  }

  // 将当前主题的亮色/暗色和色彩角色推送给 MathLive WebView。
  Future<void> _pushThemeToMathLive() async {
    final controller = _webCtrl;
    if (!_supportsEmbeddedMathLive || controller == null || !_mathLiveReady) {
      return;
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final payload = jsonEncode({
      'brightness': theme.brightness.name,
      'surface': _hexColor(scheme.surface),
      'surfaceContainer': _hexColor(scheme.surfaceContainer),
      'surfaceContainerHighest': _hexColor(scheme.surfaceContainerHighest),
      'onSurface': _hexColor(scheme.onSurface),
      'onSurfaceVariant': _hexColor(scheme.onSurfaceVariant),
      'outlineVariant': _hexColor(scheme.outlineVariant),
      'primary': _hexColor(scheme.primary),
      'onPrimary': _hexColor(scheme.onPrimary),
      'primaryContainer': _hexColor(scheme.primaryContainer),
      'secondaryContainer': _hexColor(scheme.secondaryContainer),
      'tertiary': _hexColor(scheme.tertiary),
    });
    if (payload == _lastThemePayload) return;
    _lastThemePayload = payload;
    if (!mounted) return;
    await controller.runJavaScript('window.configureTheme($payload);');
  }

  String _hexColor(Color color) {
    final value = color.toARGB32() & 0x00ffffff;
    return '#${value.toRadixString(16).padLeft(6, '0')}';
  }

  // 4 秒后若 MathLive 仍未就绪，回退到源码模式。
  void _scheduleReadyTimeout() {
    _readyTimeout?.cancel();
    _readyTimeout = Timer(const Duration(seconds: 4), () {
      if (!mounted || _mathLiveReady) return;
      _fallbackToSourceMode('MathLive 还没有完成加载，已切到源码模式继续编辑。');
    });
  }

  // MathLive 加载超时或出错时切换到源码模式。
  void _fallbackToSourceMode(String message) {
    if (!mounted) return;
    setState(() {
      _notice = message;
      _useSourceMode = true;
      _keyboardVisible = false;
      _formula = _rawCtrl.text;
    });
  }

  void _showNotice(String message) {
    if (!mounted) return;
    setState(() => _notice = message);
  }

  // 提交时先卸载 WebView 再返回公式内容。
  Future<void> _submit() async {
    final formula = _rawCtrl.text.trim();
    if (formula.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('公式不能为空')));
      return;
    }
    if (_closing) return;
    _closing = true;
    await _detachWebView();
    if (!mounted) return;
    Navigator.of(context).pop(formula);
  }
}

const _mathLiveEditorAssetKey = 'assets/mathlive/editor.html';
