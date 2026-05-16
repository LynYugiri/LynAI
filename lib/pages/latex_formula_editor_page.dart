import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:math_keyboard/math_keyboard.dart';

class LatexFormulaEditorPage extends StatefulWidget {
  final String initialFormula;
  final bool preferBlock;
  final String title;

  const LatexFormulaEditorPage({
    super.key,
    required this.initialFormula,
    required this.preferBlock,
    required this.title,
  });

  @override
  State<LatexFormulaEditorPage> createState() => _LatexFormulaEditorPageState();
}

class _LatexFormulaEditorPageState extends State<LatexFormulaEditorPage> {
  late final MathFieldEditingController _mathCtrl;
  late final TextEditingController _rawCtrl;
  var _formula = '';
  var _useSourceMode = false;
  var _showFallbackNotice = false;

  @override
  void initState() {
    super.initState();
    _formula = widget.initialFormula.trim();
    _mathCtrl = MathFieldEditingController();
    _rawCtrl = TextEditingController(text: _formula);
    _hydrateMathField(_formula);
  }

  @override
  void dispose() {
    _mathCtrl.dispose();
    _rawCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MathKeyboardViewInsets(
      child: Scaffold(
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
          child: Column(
            children: [
              if (_showFallbackNotice)
                MaterialBanner(
                  content: const Text(
                    '这条公式包含 math_keyboard 暂不支持的结构，已切换到源码模式。你也可以手动切回可视编辑重新输入。',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        setState(() => _showFallbackNotice = false);
                      },
                      child: const Text('知道了'),
                    ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        final useSourceMode = selection.first;
                        if (!useSourceMode &&
                            !_hydrateMathField(_rawCtrl.text)) {
                          setState(() {});
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('当前源码暂时无法导入可视编辑器')),
                          );
                          return;
                        }
                        setState(() => _useSourceMode = useSourceMode);
                      },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.4,
                        ),
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
                          if (_formula.isEmpty)
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
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _useSourceMode ? _sourceEditor() : _visualEditor(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _visualEditor() {
    return MathField(
      controller: _mathCtrl,
      autofocus: true,
      variables: const ['x', 'y', 'z', 'n', 'i'],
      decoration: const InputDecoration(
        labelText: '公式',
        hintText: '在这里输入公式',
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
      onChanged: (value) {
        final formula = value.trim();
        setState(() => _formula = formula);
        if (_rawCtrl.text != formula) {
          _rawCtrl.value = TextEditingValue(
            text: formula,
            selection: TextSelection.collapsed(offset: formula.length),
          );
        }
      },
      onSubmitted: (_) => _submit(),
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
        hintText: r'例如 \frac{x}{y} 或 \int_0^1 x^2\,dx',
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
      onChanged: (value) => setState(() {
        _formula = value.trim();
        _showFallbackNotice = false;
      }),
      onSubmitted: (_) => _submit(),
    );
  }

  bool _hydrateMathField(String formula) {
    final trimmed = formula.trim();
    if (trimmed.isEmpty) {
      _mathCtrl.clear();
      _formula = '';
      _showFallbackNotice = false;
      return true;
    }
    try {
      final expression = TeXParser(trimmed).parse();
      _mathCtrl.updateValue(expression);
      _formula = _mathCtrl
          .currentEditingValue(placeholderWhenEmpty: false)
          .trim();
      if (_rawCtrl.text != _formula) {
        _rawCtrl.value = TextEditingValue(
          text: _formula,
          selection: TextSelection.collapsed(offset: _formula.length),
        );
      }
      _showFallbackNotice = false;
      return true;
    } catch (_) {
      _showFallbackNotice = true;
      _useSourceMode = true;
      return false;
    }
  }

  void _submit() {
    final formula = (_useSourceMode ? _rawCtrl.text : _formula).trim();
    if (formula.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('公式不能为空')));
      return;
    }
    Navigator.of(context).pop(formula);
  }
}
