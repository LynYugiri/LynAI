import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

class LatexRenderer {
  static List<InlineSpan> parseToSpans(String text, BuildContext context) {
    final spans = <InlineSpan>[];
    final normalized = _normalize(text);
    final blockRegExp = RegExp(r'\$\$(.+?)\$\$', dotAll: true);
    final parts = normalized.split(blockRegExp);
    final blockMatches = blockRegExp.allMatches(normalized).toList();

    for (var i = 0; i < parts.length; i++) {
      if (i % 2 == 0) {
        spans.addAll(_parseInlineMath(parts[i]));
      } else {
        final idx = i ~/ 2;
        if (idx < blockMatches.length) {
          final formula = blockMatches[idx].group(1) ?? '';
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _MathBlock(formula: formula.trim()),
            ),
          );
        }
      }
    }
    return spans;
  }

  static List<InlineSpan> _parseInlineMath(String text) {
    final spans = <InlineSpan>[];
    final inlineRegExp = RegExp(r'\$(.+?)\$');
    int lastEnd = 0;

    for (final match in inlineRegExp.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final formula = match.group(1) ?? '';
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _InlineMath(formula: formula.trim()),
        ),
      );
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return spans.isEmpty ? [TextSpan(text: text)] : spans;
  }

  static String _normalize(String text) {
    String result = text.replaceAllMapped(
      RegExp(r'\\\[(.+?)\\\]', dotAll: true),
      (m) => '\$\$${m.group(1)}\$\$',
    );
    result = result.replaceAllMapped(
      RegExp(r'\\\((.+?)\\\)'),
      (m) => '\$${m.group(1)}\$',
    );
    return result;
  }

  static bool hasLatexContent(String text) {
    if (text.contains(RegExp(r'\$\$.+?\$\$', dotAll: true))) return true;
    if (text.contains(RegExp(r'\\\[.+?\\\]', dotAll: true))) return true;
    if (text.contains(RegExp(r'\\\(.+?\\\)'))) return true;
    final inlineMatch = RegExp(r'\$(.+?)\$');
    final matches = inlineMatch.allMatches(text);
    for (final m in matches) {
      final inner = m.group(1) ?? '';
      if (inner.trim().isNotEmpty && _looksLikeMath(inner)) return true;
    }
    return false;
  }

  static bool _looksLikeMath(String text) {
    final trimmed = text.trim();
    // Pure numbers/currency like $100 or $5.99 are not math
    if (RegExp(r'^-?\s*\d+\.?\d*\s*$').hasMatch(trimmed)) return false;
    if (RegExp(r'^\d+\.?\d*\s*\$?$').hasMatch(trimmed)) return false;
    return true;
  }
}

class _MathBlock extends StatelessWidget {
  final String formula;
  final TextStyle? textStyle;

  const _MathBlock({required this.formula, this.textStyle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    try {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.tertiary.withValues(alpha: 0.25),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Center(
                  child: Math.tex(
                    formula,
                    mathStyle: MathStyle.display,
                    textStyle: TextStyle(
                      fontSize: 18,
                      color: theme.colorScheme.onSurface,
                    ).merge(textStyle),
                    onErrorFallback: (_) => _fallback(formula, theme),
                  ),
                ),
              ),
            );
          },
        ),
      );
    } catch (_) {
      return _fallback(formula, theme);
    }
  }

  Widget _fallback(String formula, ThemeData theme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.2),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          formula,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _InlineMath extends StatelessWidget {
  final String formula;
  final TextStyle? textStyle;

  const _InlineMath({required this.formula, this.textStyle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    try {
      return Math.tex(
        formula,
        mathStyle: MathStyle.text,
        textStyle: TextStyle(
          fontSize: 16,
          color: theme.colorScheme.onSurface,
        ).merge(textStyle),
        onErrorFallback: (_) => Text(
          formula,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.tertiary,
          ),
        ),
      );
    } catch (_) {
      return Text(
        formula,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          fontStyle: FontStyle.italic,
          color: theme.colorScheme.tertiary,
        ),
      );
    }
  }
}

class _LatexInlineSyntax extends md.InlineSyntax {
  _LatexInlineSyntax() : super(r'\$(.+?)\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final formula = match[1]!;
    if (LatexRenderer._looksLikeMath(formula)) {
      final element = md.Element.text('inlineLatex', formula.trim());
      parser.addNode(element);
    } else {
      parser.addNode(md.Text('\$$formula\$'));
    }
    return true;
  }
}

class _LatexBuilder extends MarkdownElementBuilder {
  final TextStyle? textStyle;

  _LatexBuilder({this.textStyle});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return _InlineMath(
      formula: element.textContent,
      textStyle: preferredStyle?.merge(textStyle) ?? textStyle,
    );
  }
}

class MarkdownWithLatex extends StatelessWidget {
  final String content;
  final TextStyle? textStyle;
  final bool selectable;

  const MarkdownWithLatex({
    super.key,
    required this.content,
    this.textStyle,
    this.selectable = true,
  });

  static final _inlineRegExp = RegExp(r'\$(.+?)\$');
  static bool _hasInlineMath(String text) {
    return _inlineRegExp
        .allMatches(text)
        .any((m) => LatexRenderer._looksLikeMath(m.group(1) ?? ''));
  }

  @override
  Widget build(BuildContext context) {
    if (content.isEmpty) return const SizedBox.shrink();
    if (LatexRenderer.hasLatexContent(content)) {
      return _buildLatexContent(context);
    }
    return _buildMarkdown(context, content);
  }

  Widget _buildMarkdown(
    BuildContext context,
    String text, {
    bool withInlineLatex = false,
  }) {
    return MarkdownBody(
      data: text,
      selectable: selectable,
      styleSheet: _markdownStyle(context),
      builders: withInlineLatex
          ? {'inlineLatex': _LatexBuilder(textStyle: textStyle)}
          : const {},
      extensionSet: withInlineLatex
          ? md.ExtensionSet(md.ExtensionSet.gitHubFlavored.blockSyntaxes, [
              ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
              _LatexInlineSyntax(),
            ])
          : null,
    );
  }

  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    final baseStyle = textStyle ?? const TextStyle(fontSize: 15, height: 1.5);
    return MarkdownStyleSheet(
      p: baseStyle,
      h1: baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 15) + 9),
      h2: baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 15) + 7),
      h3: baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 15) + 5),
      h4: baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 15) + 3),
      h5: baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 15) + 1),
      h6: baseStyle,
      listBullet: baseStyle,
      blockquote: baseStyle,
      code: TextStyle(
        fontSize: (baseStyle.fontSize ?? 15) - 2,
        color: baseStyle.color,
        backgroundColor: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      codeblockDecoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
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
    );
  }

  Widget _buildLatexContent(BuildContext context) {
    final normalized = LatexRenderer._normalize(content);
    final blockRegExp = RegExp(r'\$\$(.+?)\$\$', dotAll: true);
    final parts = normalized.split(blockRegExp);
    final blockMatches = blockRegExp.allMatches(normalized).toList();
    final widgets = <Widget>[];

    for (var i = 0; i < parts.length; i++) {
      if (i % 2 == 0) {
        if (parts[i].isNotEmpty) {
          if (_hasInlineMath(parts[i])) {
            widgets.add(
              _buildMarkdown(context, parts[i], withInlineLatex: true),
            );
          } else {
            widgets.add(_buildMarkdown(context, parts[i]));
          }
        }
      } else {
        final idx = i ~/ 2;
        if (idx < blockMatches.length) {
          final formula = blockMatches[idx].group(1) ?? '';
          widgets.add(
            _MathBlock(formula: formula.trim(), textStyle: textStyle),
          );
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
