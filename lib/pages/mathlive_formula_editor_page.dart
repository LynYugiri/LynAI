import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:webview_all/webview_all.dart';

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
  var _syncingFromWeb = false;
  var _useSourceMode = false;
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
      ..setBackgroundColor(const Color(0x00000000))
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
          onWebResourceError: (error) => _showNotice(
            'MathLive 加载失败：${error.description}，可切到源码模式继续编辑。',
          ),
        ),
      )
      ..loadFlutterAsset(_mathLiveEditorAssetKey);
  }

  @override
  void dispose() {
    _readyTimeout?.cancel();
    _rawCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.check),
            label: const Text('完成'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_notice != null) _noticeBanner(),
              _introCard(context),
              const SizedBox(height: 12),
              _exampleChips(),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
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
                  setState(() => _useSourceMode = next);
                  if (!next) {
                    _pushFormulaToMathLive(_rawCtrl.text);
                  }
                },
              ),
              const SizedBox(height: 12),
              _previewCard(context),
              const SizedBox(height: 12),
              Expanded(
                child: _useSourceMode ? _sourceEditor() : _visualEditor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _introCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        widget.preferBlock
            ? 'MathLive 可视编辑现已接入正式公式编辑页，支持等式、分式、上下标和矩阵等更完整的 LaTeX 输入。'
            : 'MathLive 可视编辑现已接入正式公式编辑页，单变量、等式和常见表达式会直接按 LaTeX 同步。',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
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

  Widget _exampleChips() {
    final examples = [
      'm',
      'x',
      'x^2',
      'mc^2',
      'E = mc^2',
      r'\frac{x}{y}',
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final example in examples)
          ActionChip(
            label: Text(example),
            onPressed: () => _setFormula(example),
          ),
      ],
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
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.65)),
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
                mathStyle: widget.preferBlock ? MathStyle.display : MathStyle.text,
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
      minLines: 8,
      maxLines: 18,
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
    if (controller == null) return _sourceEditor();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: WebViewWidget(controller: controller)),
            if (!_mathLiveReady)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
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
      ),
    );
  }

  Future<void> _setFormula(String formula) async {
    _rawCtrl.value = TextEditingValue(
      text: formula,
      selection: TextSelection.collapsed(offset: formula.length),
    );
    setState(() => _formula = formula);
    await _pushFormulaToMathLive(formula);
  }

  Future<void> _pushFormulaToMathLive(String formula) async {
    final controller = _webCtrl;
    if (!_supportsEmbeddedMathLive || controller == null || !_mathLiveReady) return;
    final encoded = jsonEncode(formula);
    await controller.runJavaScript('window.setFormula($encoded);');
  }

  Future<void> _configureMathLive() async {
    final controller = _webCtrl;
    if (!_supportsEmbeddedMathLive || controller == null || !_mathLiveReady) return;
    final encoded = jsonEncode({
      'displayMode': widget.preferBlock ? 'block' : 'inline',
    });
    await controller.runJavaScript('window.configureMathLive($encoded);');
  }

  void _handleBridgeMessage(String rawMessage) {
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
          _notice = null;
        });
        _configureMathLive();
        _pushFormulaToMathLive(_rawCtrl.text);
      case 'error':
        _showNotice(
          'MathLive 初始化失败：${decoded['message'] ?? '未知错误'}，可切到源码模式继续编辑。',
        );
      case 'input':
        _applyFormulaFromWeb(decoded['latex'] as String? ?? '');
      default:
        break;
    }
  }

  void _applyFormulaFromWeb(String latex) {
    _syncingFromWeb = true;
    if (_rawCtrl.text != latex) {
      _rawCtrl.value = TextEditingValue(
        text: latex,
        selection: TextSelection.collapsed(offset: latex.length),
      );
    }
    if (mounted) setState(() => _formula = latex);
    _syncingFromWeb = false;
  }

  void _scheduleReadyTimeout() {
    _readyTimeout?.cancel();
    _readyTimeout = Timer(const Duration(seconds: 4), () {
      if (!mounted || _mathLiveReady) return;
      _showNotice('MathLive 还没有完成加载，若长时间无响应可切到源码模式继续编辑。');
    });
  }

  void _showNotice(String message) {
    if (!mounted) return;
    setState(() => _notice = message);
  }

  void _submit() {
    final formula = _rawCtrl.text.trim();
    if (formula.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('公式不能为空')));
      return;
    }
    Navigator.of(context).pop(formula);
  }
}

const _mathLiveEditorAssetKey = 'assets/mathlive/editor.html';
