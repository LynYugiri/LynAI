import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// 简单的 LaTeX 渲染器
///
/// 支持块级公式 `$$...$$` 和内联公式 `$...$`。
/// 将常见的 LaTeX 命令映射到 Unicode 字符。
class LatexRenderer {
  static const _blockPattern = r'\$\$(.+?)\$\$';
  static const _inlinePattern = r'\$(.+?)\$';

  /// 将包含 LaTeX 的文本解析为 Widget 列表
  static List<InlineSpan> parseToSpans(String text, BuildContext context) {
    final spans = <InlineSpan>[];
    final theme = Theme.of(context);

    // 先处理块级公式 $$...$$
    final blockRegExp = RegExp(_blockPattern, dotAll: true);
    final parts = text.split(blockRegExp);
    final blockMatches = blockRegExp.allMatches(text).toList();

    for (var i = 0; i < parts.length; i++) {
      if (i % 2 == 0) {
        // 普通文本部分 - 进一步处理内联公式
        spans.addAll(_parseInlineMath(parts[i], context));
      } else {
        // 块级公式
        final idx = i ~/ 2;
        if (idx < blockMatches.length) {
          final formula = blockMatches[idx].group(1) ?? '';
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _buildMathBlock(formula, theme),
          ));
        }
      }
    }

    return spans;
  }

  /// 解析内联公式 $...$
  static List<InlineSpan> _parseInlineMath(String text, BuildContext context) {
    final spans = <InlineSpan>[];
    final inlineRegExp = RegExp(_inlinePattern);
    final theme = Theme.of(context);

    int lastEnd = 0;
    for (final match in inlineRegExp.allMatches(text)) {
      // 添加公式前的普通文本
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      // 添加内联公式
      final formula = match.group(1) ?? '';
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            _convertLatex(formula),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.tertiary,
            ),
          ),
        ),
      ));
      lastEnd = match.end;
    }

    // 添加剩余文本
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return spans.isEmpty ? [TextSpan(text: text)] : spans;
  }

  /// 构建块级公式容器
  static Widget _buildMathBlock(String formula, ThemeData theme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.tertiary.withValues(alpha: 0.3),
        ),
      ),
      child: SelectableText(
        _convertLatex(formula),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 15,
          fontStyle: FontStyle.italic,
          color: theme.colorScheme.tertiary,
        ),
      ),
    );
  }

  /// 将 LaTeX 命令转换为 Unicode 等价字符
  static String _convertLatex(String formula) {
    String result = formula;

    // 希腊字母（小写）
    const greekLower = {
      r'\alpha': 'α', r'\beta': 'β', r'\gamma': 'γ', r'\delta': 'δ',
      r'\epsilon': 'ε', r'\varepsilon': 'ε', r'\zeta': 'ζ', r'\eta': 'η',
      r'\theta': 'θ', r'\vartheta': 'ϑ', r'\iota': 'ι', r'\kappa': 'κ',
      r'\lambda': 'λ', r'\mu': 'μ', r'\nu': 'ν', r'\xi': 'ξ',
      r'\pi': 'π', r'\varpi': 'ϖ', r'\rho': 'ρ', r'\varrho': 'ϱ',
      r'\sigma': 'σ', r'\varsigma': 'ς', r'\tau': 'τ', r'\upsilon': 'υ',
      r'\phi': 'φ', r'\varphi': 'ϕ', r'\chi': 'χ', r'\psi': 'ψ',
      r'\omega': 'ω',
    };

    // 希腊字母（大写）
    const greekUpper = {
      r'\Gamma': 'Γ', r'\Delta': 'Δ', r'\Theta': 'Θ', r'\Lambda': 'Λ',
      r'\Xi': 'Ξ', r'\Pi': 'Π', r'\Sigma': 'Σ', r'\Upsilon': 'Υ',
      r'\Phi': 'Φ', r'\Psi': 'Ψ', r'\Omega': 'Ω',
    };

    // 数学符号
    const mathSymbols = {
      r'\times': '×', r'\cdot': '·', r'\div': '÷', r'\pm': '±',
      r'\mp': '∓', r'\leq': '≤', r'\geq': '≥', r'\neq': '≠',
      r'\approx': '≈', r'\equiv': '≡', r'\propto': '∝', r'\sim': '∼',
      r'\infty': '∞', r'\partial': '∂', r'\nabla': '∇', r'\forall': '∀',
      r'\exists': '∃', r'\in': '∈', r'\notin': '∉', r'\subset': '⊂',
      r'\supset': '⊃', r'\subseteq': '⊆', r'\supseteq': '⊇',
      r'\cup': '∪', r'\cap': '∩', r'\emptyset': '∅', r'\varnothing': '∅',
      r'\to': '→', r'\rightarrow': '→', r'\leftarrow': '←',
      r'\Rightarrow': '⇒', r'\Leftarrow': '⇐', r'\leftrightarrow': '↔',
      r'\mapsto': '↦', r'\implies': '⇒', r'\iff': '⇔',
      r'\int': '∫', r'\iint': '∬', r'\iiint': '∭', r'\oint': '∮',
      r'\sum': '∑', r'\prod': '∏', r'\coprod': '∐',
      r'\sqrt': '√', r'\angle': '∠', r'\parallel': '∥',
      r'\perp': '⊥', r'\triangle': '△',
      r'\cdots': '⋯', r'\vdots': '⋮', r'\ddots': '⋱', r'\ldots': '…',
      r'\therefore': '∴', r'\because': '∵',
      r'\langle': '⟨', r'\rangle': '⟩', r'\lceil': '⌈', r'\rceil': '⌉',
      r'\lfloor': '⌊', r'\rfloor': '⌋',
      r'\oplus': '⊕', r'\ominus': '⊖', r'\otimes': '⊗',
      r'\odot': '⊙', r'\circ': '∘', r'\star': '★',
      r'\aleph': 'ℵ', r'\hbar': 'ℏ',
    };

    // 分数处理 \frac{a}{b} → (a/b)
    final fracRegExp = RegExp(r'\\frac\s*\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}\s*\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}');
    result = result.replaceAllMapped(fracRegExp, (m) => '(${m.group(1)} / ${m.group(2)})');

    // 上标处理 ^{...}
    result = result.replaceAllMapped(
      RegExp(r'\^\{(.+?)\}'),
      (m) => _toSuperscript(m.group(1)!),
    );
    result = result.replaceAllMapped(
      RegExp(r'\^(\w)'),
      (m) => _toSuperscript(m.group(1)!),
    );

    // 下标处理 _{...}
    result = result.replaceAllMapped(
      RegExp(r'_\{(.+?)\}'),
      (m) => _toSubscript(m.group(1)!),
    );
    result = result.replaceAllMapped(
      RegExp(r'_(\w)'),
      (m) => _toSubscript(m.group(1)!),
    );

    // 替换所有符号（长的在前，避免部分匹配）
    final allSymbols = <String, String>{
      ...greekUpper,
      ...greekLower,
      ...mathSymbols,
    };

    final sortedKeys = allSymbols.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final key in sortedKeys) {
      result = result.replaceAll(key, allSymbols[key]!);
    }

    // 清理多余的反斜杠和花括号
    result = result.replaceAll('\\left', '');
    result = result.replaceAll('\\right', '');
    result = result.replaceAll('\\,', ' ');
    result = result.replaceAll('\\;', '  ');
    result = result.replaceAll('\\!', '');
    result = result.replaceAll('\\\\', '\n');
    result = result.replaceAll('{', '');
    result = result.replaceAll('}', '');
    result = result.replaceAll(r'\ ', ' ');

    // 清理剩余的未知命令
    result = result.replaceAll(RegExp(r'\\[a-zA-Z]+'), '');

    return result.trim();
  }

  static String _toSuperscript(String text) {
    const superscriptMap = {
      '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
      '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
      'a': 'ᵃ', 'b': 'ᵇ', 'c': 'ᶜ', 'd': 'ᵈ', 'e': 'ᵉ',
      'f': 'ᶠ', 'g': 'ᵍ', 'h': 'ʰ', 'i': 'ⁱ', 'j': 'ʲ',
      'k': 'ᵏ', 'l': 'ˡ', 'm': 'ᵐ', 'n': 'ⁿ', 'o': 'ᵒ',
      'p': 'ᵖ', 'r': 'ʳ', 's': 'ˢ', 't': 'ᵗ', 'u': 'ᵘ',
      'v': 'ᵛ', 'w': 'ʷ', 'x': 'ˣ', 'y': 'ʸ', 'z': 'ᶻ',
      'A': 'ᴬ', 'B': 'ᴮ', 'C': 'ꟲ', 'D': 'ᴰ', 'E': 'ᴱ',
      'F': 'ꟳ', 'G': 'ᴳ', 'H': 'ᴴ', 'I': 'ᴵ', 'J': 'ᴶ',
      'K': 'ᴷ', 'L': 'ᴸ', 'M': 'ᴹ', 'N': 'ᴺ', 'O': 'ᴼ',
      'P': 'ᴾ', 'R': 'ᴿ', 'T': 'ᵀ', 'U': 'ᵁ', 'V': 'ⱽ',
      'W': 'ᵂ', '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾',
      '/': ' ',
    };
    return text.split('').map((c) => superscriptMap[c] ?? c).join();
  }

  static String _toSubscript(String text) {
    const subscriptMap = {
      '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
      '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
      'a': 'ₐ', 'e': 'ₑ', 'h': 'ₕ', 'i': 'ᵢ', 'j': 'ⱼ',
      'k': 'ₖ', 'l': 'ₗ', 'm': 'ₘ', 'n': 'ₙ', 'o': 'ₒ',
      'p': 'ₚ', 'r': 'ᵣ', 's': 'ₛ', 't': 'ₜ', 'u': 'ᵤ',
      'v': 'ᵥ', 'x': 'ₓ', '+': '₊', '-': '₋', '=': '₌',
      '(': '₍', ')': '₎', '/': ' ',
    };
    return text.split('').map((c) => subscriptMap[c] ?? c).join();
  }

  /// 检查文本是否包含 LaTeX 公式
  static bool hasLatexContent(String text) {
    return text.contains(RegExp(_blockPattern)) ||
        text.contains(RegExp(_inlinePattern));
  }
}

/// 支持 LaTeX 的 Markdown 内容渲染组件
class MarkdownWithLatex extends StatelessWidget {
  final String content;

  const MarkdownWithLatex({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    if (content.isEmpty) return const SizedBox.shrink();

    // 如果包含 LaTeX，使用自定义渲染
    if (LatexRenderer.hasLatexContent(content)) {
      return _buildLatexContent(context);
    }

    // 否则使用 Markdown 渲染
    return MarkdownBody(
      data: content,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(fontSize: 15, height: 1.5),
        code: TextStyle(
          fontSize: 13,
          backgroundColor: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.5),
        ),
        codeblockDecoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLatexContent(BuildContext context) {
    // 按块分割：$$...$$ 之间的是块级公式
    final blockRegExp = RegExp(r'\$\$(.+?)\$\$', dotAll: true);
    final parts = content.split(blockRegExp);
    final blockMatches = blockRegExp.allMatches(content).toList();

    final widgets = <Widget>[];

    for (var i = 0; i < parts.length; i++) {
      if (i % 2 == 0) {
        // 普通文本/Markdown 部分
        if (parts[i].trim().isNotEmpty) {
          widgets.add(MarkdownBody(
            data: parts[i],
            selectable: true,
            styleSheet: MarkdownStyleSheet(
              p: const TextStyle(fontSize: 15, height: 1.5),
              code: TextStyle(
                fontSize: 13,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
              ),
              codeblockDecoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              blockquoteDecoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                ),
              ),
            ),
          ));
        }
      } else {
        // 块级公式
        final idx = i ~/ 2;
        if (idx < blockMatches.length) {
          final formula = blockMatches[idx].group(1) ?? '';
          widgets.add(Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .tertiary
                    .withValues(alpha: 0.3),
              ),
            ),
            child: SelectableText(
              LatexRenderer._convertLatex(formula.trim()),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ),
          ));
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }
}
