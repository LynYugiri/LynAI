import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class LatexRenderer {

  static List<InlineSpan> parseToSpans(String text, BuildContext context) {
    final spans = <InlineSpan>[];
    final theme = Theme.of(context);
    final normalized = _normalize(text);
    final blockRegExp = RegExp(r'\$\$(.+?)\$\$', dotAll: true);
    final parts = normalized.split(blockRegExp);
    final blockMatches = blockRegExp.allMatches(normalized).toList();

    for (var i = 0; i < parts.length; i++) {
      if (i % 2 == 0) {
        spans.addAll(_parseInlineMath(parts[i], theme));
      } else {
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

  static List<InlineSpan> _parseInlineMath(String text, ThemeData theme) {
    final spans = <InlineSpan>[];
    final inlineRegExp = RegExp(r'\$(.+?)\$');
    int lastEnd = 0;

    for (final match in inlineRegExp.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
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

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return spans.isEmpty ? [TextSpan(text: text)] : spans;
  }

  static String _normalize(String text) {
    // Convert \[ ... \] → $$ ... $$
    String result = text.replaceAllMapped(
      RegExp(r'\\\[(.+?)\\\]', dotAll: true),
      (m) => '\$\$${m.group(1)}\$\$',
    );
    // Convert \( ... \) → $ ... $
    result = result.replaceAllMapped(
      RegExp(r'\\\((.+?)\\\)'),
      (m) => '\$${m.group(1)}\$',
    );
    return result;
  }

  static Widget _buildMathBlock(String formula, ThemeData theme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.tertiary.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.functions, size: 12, color: theme.colorScheme.tertiary.withValues(alpha: 0.5)),
          const SizedBox(width: 4),
          Text('公式', style: TextStyle(fontSize: 10, color: theme.colorScheme.tertiary.withValues(alpha: 0.5))),
        ]),
        const SizedBox(height: 8),
        SelectableText(
          _convertLatex(formula),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 15,
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.tertiary,
          ),
        ),
      ]),
    );
  }

  static String _convertLatex(String formula) {
    String result = formula.trim();
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
    const greekUpper = {
      r'\Gamma': 'Γ', r'\Delta': 'Δ', r'\Theta': 'Θ', r'\Lambda': 'Λ',
      r'\Xi': 'Ξ', r'\Pi': 'Π', r'\Sigma': 'Σ', r'\Upsilon': 'Υ',
      r'\Phi': 'Φ', r'\Psi': 'Ψ', r'\Omega': 'Ω',
    };
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
      r'\spadesuit': '♠', r'\heartsuit': '♥', r'\diamondsuit': '♦', r'\clubsuit': '♣',
      r'\neg': '¬', r'\land': '∧', r'\lor': '∨',
    };

    // Handle \frac{num}{den} → num / den (with spaces for readability)
    result = result.replaceAllMapped(
      RegExp(
        r'\\frac\s*\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}\s*\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}',
      ),
      (m) => '(${m.group(1)}) / (${m.group(2)})',
    );

    // Handle superscripts: ^{...} and ^single_char
    result = result.replaceAllMapped(
      RegExp(r'\^\{([^{}]+(?:\{[^{}]*\}[^{}]*)*)\}'),
      (m) => _toSuperscript(m.group(1)!.replaceAll('{', '').replaceAll('}', '')),
    );
    result = result.replaceAllMapped(
      RegExp(r'\^(\S)'),
      (m) => _toSuperscript(m.group(1)!),
    );

    // Handle subscripts: _{...} and _single_char
    result = result.replaceAllMapped(
      RegExp(r'_\{([^{}]+(?:\{[^{}]*\}[^{}]*)*)\}'),
      (m) => _toSubscript(m.group(1)!.replaceAll('{', '').replaceAll('}', '')),
    );
    result = result.replaceAllMapped(
      RegExp(r'_(\S)'),
      (m) => _toSubscript(m.group(1)!),
    );

    // Replace symbols (longer ones first to avoid partial matches)
    final allSymbols = <String, String>{...greekUpper, ...greekLower, ...mathSymbols};
    final sortedKeys = allSymbols.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in sortedKeys) {
      result = result.replaceAll(key, allSymbols[key]!);
    }

    // Clean up remaining LaTeX syntax
    result = result
        .replaceAll('\\left', '')
        .replaceAll('\\right', '')
        .replaceAll('\\,', ' ')
        .replaceAll('\\;', '  ')
        .replaceAll('\\!', '')
        .replaceAll('\\\\', '\n')
        .replaceAll(r'\ ', ' ');
    result = result.replaceAll(RegExp(r'\\[a-zA-Z]+'), '');

    // Clean extra braces
    result = result.replaceAll('{', '').replaceAll('}', '');

    return result.trim();
  }

  static String _toSuperscript(String text) {
    const map = {
      '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵',
      '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹', 'a': 'ᵃ', 'b': 'ᵇ',
      'c': 'ᶜ', 'd': 'ᵈ', 'e': 'ᵉ', 'f': 'ᶠ', 'g': 'ᵍ', 'h': 'ʰ',
      'i': 'ⁱ', 'j': 'ʲ', 'k': 'ᵏ', 'l': 'ˡ', 'm': 'ᵐ', 'n': 'ⁿ',
      'o': 'ᵒ', 'p': 'ᵖ', 'r': 'ʳ', 's': 'ˢ', 't': 'ᵗ', 'u': 'ᵘ',
      'v': 'ᵛ', 'w': 'ʷ', 'x': 'ˣ', 'y': 'ʸ', 'z': 'ᶻ', '+': '⁺',
      '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾', '/': 'ᐟ',
    };
    return text.split('').map((c) => map[c] ?? c).join();
  }

  static String _toSubscript(String text) {
    const map = {
      '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅',
      '6': '₆', '7': '₇', '8': '₈', '9': '₉', 'a': 'ₐ', 'e': 'ₑ',
      'i': 'ᵢ', 'j': 'ⱼ', 'k': 'ₖ', 'l': 'ₗ', 'm': 'ₘ', 'n': 'ₙ',
      'o': 'ₒ', 'p': 'ₚ', 'r': 'ᵣ', 's': 'ₛ', 't': 'ₜ', 'u': 'ᵤ',
      'v': 'ᵥ', 'x': 'ₓ', '+': '₊', '-': '₋', '=': '₌',
      '(': '₍', ')': '₎',
    };
    return text.split('').map((c) => map[c] ?? c).join();
  }

  static bool hasLatexContent(String text) {
    return text.contains(RegExp(r'\$\$.+?\$\$', dotAll: true)) ||
        text.contains(RegExp(r'\$.+?\$')) ||
        text.contains(RegExp(r'\\\[.+?\\\]', dotAll: true)) ||
        text.contains(RegExp(r'\\\(.+?\\\)'));
  }
}

class MarkdownWithLatex extends StatelessWidget {
  final String content;
  const MarkdownWithLatex({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    if (content.isEmpty) return const SizedBox.shrink();
    if (LatexRenderer.hasLatexContent(content)) {
      return _buildLatexContent(context);
    }
    return _buildMarkdown(context, content);
  }

  Widget _buildMarkdown(BuildContext context, String text) {
    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: _markdownStyle(context),
    );
  }

  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    return MarkdownStyleSheet(
      p: const TextStyle(fontSize: 15, height: 1.5),
      code: TextStyle(
        fontSize: 13,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      codeblockDecoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 3)),
      ),
    );
  }

  Widget _buildLatexContent(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = LatexRenderer._normalize(content);
    final blockRegExp = RegExp(r'\$\$(.+?)\$\$', dotAll: true);
    final parts = normalized.split(blockRegExp);
    final blockMatches = blockRegExp.allMatches(normalized).toList();
    final widgets = <Widget>[];

    for (var i = 0; i < parts.length; i++) {
      if (i % 2 == 0) {
        if (parts[i].trim().isNotEmpty) {
          widgets.add(_buildMixedContent(parts[i], theme, context));
        }
      } else {
        final idx = i ~/ 2;
        if (idx < blockMatches.length) {
          final formula = blockMatches[idx].group(1) ?? '';
          widgets.add(LatexRenderer._buildMathBlock(formula.trim(), theme));
        }
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: widgets);
  }

  Widget _buildMixedContent(String text, ThemeData theme, BuildContext context) {
    final inlineRegExp = RegExp(r'\$(.+?)\$');
    if (!inlineRegExp.hasMatch(text)) {
      return _buildMarkdown(context, text);
    }

    final parts = text.split(inlineRegExp);
    final matches = inlineRegExp.allMatches(text).toList();
    final spans = <InlineSpan>[];

    for (var i = 0; i < parts.length; i++) {
      if (i % 2 == 0) {
        if (parts[i].isNotEmpty) {
          spans.add(TextSpan(text: parts[i], style: const TextStyle(fontSize: 15, height: 1.5)));
        }
      } else {
        final idx = i ~/ 2;
        if (idx < matches.length) {
          final formula = matches[idx].group(1) ?? '';
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                LatexRenderer._convertLatex(formula.trim()),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ),
          ));
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text.rich(TextSpan(children: spans)),
    );
  }
}
