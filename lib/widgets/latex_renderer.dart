import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight.dart' as hl;
import 'package:markdown/markdown.dart' as md;
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_clipboard/super_clipboard.dart';

const _codeFontFamily = 'Hurmit Nerd Font';

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
  final bool selectable;

  const _MathBlock({
    required this.formula,
    this.textStyle,
    this.selectable = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = 'LaTeX';
    try {
      return _ExportableBlock(
        label: label,
        source: formula,
        includeActions: selectable,
        margin: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.tertiary.withValues(alpha: 0.25),
          ),
        ),
        exportChildBuilder: (context) => _latexExportBody(context, theme),
        compactExport: true,
        child: _latexBody(context, theme),
      );
    } catch (_) {
      return _fallback(formula, theme);
    }
  }

  Widget _latexBody(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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
                  onErrorFallback: (_) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(formula, style: _fallbackStyle(theme)),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _latexExportBody(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Math.tex(
            formula,
            mathStyle: MathStyle.display,
            textStyle: TextStyle(
              fontSize: 30,
              color: theme.colorScheme.onSurface,
            ).merge(textStyle),
            onErrorFallback: (_) => ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Text(
                formula,
                softWrap: true,
                style: _fallbackStyle(theme),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallback(String formula, ThemeData theme) {
    return _ExportableBlock(
      label: 'LaTeX',
      source: formula,
      includeActions: selectable,
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.2),
        ),
      ),
      exportChildBuilder: (context) => _fallbackExportBody(theme),
      compactExport: true,
      child: _fallbackBody(theme),
    );
  }

  Widget _fallbackExportBody(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Text(formula, softWrap: true, style: _fallbackStyle(theme)),
    );
  }

  Widget _fallbackBody(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(formula, style: _fallbackStyle(theme)),
      ),
    );
  }

  TextStyle _fallbackStyle(ThemeData theme) {
    return TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      color: theme.colorScheme.onSurfaceVariant,
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
  final bool wrapCodeBlocks;

  const MarkdownWithLatex({
    super.key,
    required this.content,
    this.textStyle,
    this.selectable = true,
    this.wrapCodeBlocks = false,
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
    final child =
        LatexRenderer.hasLatexContent(_contentOutsideFencedCodeBlocks(content))
        ? _buildLatexContent(context)
        : _buildMarkdown(context, content);
    return selectable ? SelectionArea(child: child) : child;
  }

  Widget _buildMarkdown(
    BuildContext context,
    String text, {
    bool withInlineLatex = false,
  }) {
    final styleSheet = _markdownStyle(context);
    final highlighter = _OneDarkSyntaxHighlighter(
      styleSheet.code ?? const TextStyle(fontFamily: _codeFontFamily),
    );
    final builders = <String, MarkdownElementBuilder>{
      'pre': _CodeBlockBuilder(
        selectable: selectable,
        wrap: wrapCodeBlocks,
        highlighter: highlighter,
      ),
      if (withInlineLatex) 'inlineLatex': _LatexBuilder(textStyle: textStyle),
    };

    return MarkdownBody(
      data: text,
      selectable: false,
      styleSheet: styleSheet,
      builders: builders,
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
        fontFamily: _codeFontFamily,
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
    final segments = _splitFencedCodeBlocks(content);
    final blockRegExp = RegExp(r'\$\$(.+?)\$\$', dotAll: true);
    final widgets = <Widget>[];

    for (final segment in segments) {
      if (segment.isFencedCodeBlock) {
        widgets.add(_buildMarkdown(context, segment.text));
        continue;
      }

      final normalized = LatexRenderer._normalize(segment.text);
      final parts = normalized.split(blockRegExp);
      final blockMatches = blockRegExp.allMatches(normalized).toList();
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
              _MathBlock(
                formula: formula.trim(),
                textStyle: textStyle,
                selectable: selectable,
              ),
            );
          }
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  static String _contentOutsideFencedCodeBlocks(String text) {
    return _splitFencedCodeBlocks(text)
        .where((segment) => !segment.isFencedCodeBlock)
        .map((segment) => segment.text)
        .join('\n');
  }

  static List<_MarkdownSegment> _splitFencedCodeBlocks(String text) {
    final segments = <_MarkdownSegment>[];
    final lines = text.split('\n');
    final buffer = StringBuffer();
    var inFence = false;
    var fenceMarker = '';
    var fenceLength = 0;

    void flush({required bool isFence}) {
      if (buffer.isEmpty) return;
      segments.add(_MarkdownSegment(buffer.toString(), isFence));
      buffer.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final openMatch = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(line);
      final closeMatch = RegExp(
        r'^ {0,3}(`{3,}|~{3,})[ \t]*$',
      ).firstMatch(line);
      final wasInFence = inFence;
      if (!wasInFence && openMatch != null) {
        flush(isFence: false);
        inFence = true;
        fenceMarker = openMatch.group(1)![0];
        fenceLength = openMatch.group(1)!.length;
      }

      buffer.write(line);
      if (i != lines.length - 1) buffer.write('\n');

      if (wasInFence && closeMatch != null) {
        final marker = closeMatch.group(1)!;
        if (marker[0] == fenceMarker && marker.length >= fenceLength) {
          inFence = false;
          flush(isFence: true);
        }
      }
    }

    flush(isFence: inFence);
    return segments;
  }
}

class _MarkdownSegment {
  final String text;
  final bool isFencedCodeBlock;

  const _MarkdownSegment(this.text, this.isFencedCodeBlock);
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  final bool selectable;
  final bool wrap;
  final _OneDarkSyntaxHighlighter highlighter;

  _CodeBlockBuilder({
    required this.selectable,
    required this.wrap,
    required this.highlighter,
  });

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.textContent.replaceAll(RegExp(r'\n$'), '');
    final language = _languageFrom(element);
    final span = highlighter.formatCode(code, language: language);
    return _CodeBlock(
      code: code,
      language: language,
      span: span,
      selectable: selectable,
      wrap: wrap,
    );
  }

  String? _languageFrom(md.Element element) {
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is! md.Element || child.tag != 'code') continue;
      final className = child.attributes['class'] ?? '';
      final match = RegExp(r'(?:^|\s)language-([^\s]+)').firstMatch(className);
      if (match != null) return match.group(1);
    }
    return null;
  }
}

class _CodeBlock extends StatelessWidget {
  final String code;
  final String? language;
  final TextSpan span;
  final bool selectable;
  final bool wrap;

  const _CodeBlock({
    required this.code,
    required this.language,
    required this.span,
    required this.selectable,
    required this.wrap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoration = BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(8),
    );
    return _ExportableBlock(
      label: _displayLanguage(language),
      source: code,
      includeActions: selectable,
      decoration: decoration,
      exportChildBuilder: (_) => _codeExportBody(),
      child: _codeBody(wrap: wrap),
    );
  }

  Widget _codeExportBody() {
    final lines = code.split('\n');
    final lineCountWidth = (lines.length.toString().length * 8 + 18).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: lineCountWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < lines.length; i++)
                  Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontFamily: _codeFontFamily,
                      fontSize: 13,
                      height: 1.5,
                      color: Color(0xFF5C6370),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text.rich(span, softWrap: true)),
        ],
      ),
    );
  }

  Widget _codeBody({required bool wrap}) {
    final text = Text.rich(span, softWrap: wrap);
    final padded = Padding(padding: const EdgeInsets.all(8), child: text);
    if (wrap) return padded;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: padded,
    );
  }

  String _displayLanguage(String? language) {
    final raw = language?.trim();
    if (raw == null || raw.isEmpty) return 'Code';
    const names = {
      'bash': 'Bash',
      'cpp': 'C++',
      'cs': 'C#',
      'css': 'CSS',
      'dart': 'Dart',
      'go': 'Go',
      'html': 'HTML',
      'java': 'Java',
      'javascript': 'JavaScript',
      'json': 'JSON',
      'kotlin': 'Kotlin',
      'markdown': 'Markdown',
      'python': 'Python',
      'rust': 'Rust',
      'swift': 'Swift',
      'typescript': 'TypeScript',
      'xml': 'XML',
      'yaml': 'YAML',
    };
    return names[raw.toLowerCase()] ?? raw;
  }
}

class _OneDarkSyntaxHighlighter extends SyntaxHighlighter {
  static const _foreground = Color(0xFFABB2BF);
  static const _red = Color(0xFFE06C75);
  static const _orange = Color(0xFFD19A66);
  static const _yellow = Color(0xFFE5C07B);
  static const _green = Color(0xFF98C379);
  static const _cyan = Color(0xFF56B6C2);
  static const _blue = Color(0xFF61AFEF);
  static const _purple = Color(0xFFC678DD);
  static const _comment = Color(0xFF5C6370);

  static final _operatorRegExp = RegExp(
    r'(===|!==|==|!=|<=|>=|=>|->|::|\.\.\.|\.\.|\+\+|--|&&|\|\||<<|>>|[-+*/%=&|^~!?:<>.,;()[\]{}])',
  );

  static final _plainTokenRegExp = RegExp(
    r'(===|!==|==|!=|<=|>=|=>|->|::|\.\.\.|\.\.|\+\+|--|&&|\|\||<<|>>|[-+*/%=&|^~!?:<>.,;()[\]{}]|\b[A-Za-z_][A-Za-z0-9_]*\b)',
  );

  static const _reservedWords = {
    'abstract',
    'alignas',
    'alignof',
    'and',
    'as',
    'asm',
    'async',
    'await',
    'bool',
    'break',
    'case',
    'catch',
    'char',
    'class',
    'const',
    'constexpr',
    'continue',
    'def',
    'default',
    'delete',
    'do',
    'double',
    'dynamic',
    'else',
    'enum',
    'export',
    'extends',
    'false',
    'final',
    'finally',
    'float',
    'for',
    'from',
    'func',
    'function',
    'if',
    'implements',
    'import',
    'in',
    'inline',
    'int',
    'interface',
    'is',
    'let',
    'long',
    'namespace',
    'new',
    'noexcept',
    'not',
    'nullptr',
    'operator',
    'or',
    'private',
    'protected',
    'public',
    'return',
    'short',
    'signed',
    'sizeof',
    'static',
    'string',
    'struct',
    'super',
    'switch',
    'template',
    'this',
    'throw',
    'true',
    'try',
    'typedef',
    'typename',
    'union',
    'unsigned',
    'using',
    'var',
    'virtual',
    'void',
    'volatile',
    'while',
    'with',
  };

  static const _syntaxColors = {
    'subst': _foreground,
    'comment': _comment,
    'quote': _comment,
    'doctag': _purple,
    'keyword': _purple,
    'formula': _purple,
    'operator': _purple,
    'punctuation': _foreground,
    'section': _red,
    'name': _red,
    'tag': _red,
    'selector-tag': _red,
    'deletion': _red,
    'literal': _cyan,
    'string': _green,
    'regexp': _green,
    'addition': _green,
    'attribute': _orange,
    'meta-string': _orange,
    'built_in': _yellow,
    'builtin-name': _yellow,
    'class': _yellow,
    'class-name': _yellow,
    'attr': _orange,
    'property': _red,
    'variable': _red,
    'template-variable': _red,
    'type': _yellow,
    'selector-class': _orange,
    'selector-attr': _orange,
    'selector-pseudo': _orange,
    'number': _orange,
    'symbol': _blue,
    'bullet': _blue,
    'link': _blue,
    'meta': _blue,
    'selector-id': _blue,
    'title': _blue,
    'function': _blue,
    'function-name': _blue,
    'params': _foreground,
    'emphasis': _foreground,
    'strong': _foreground,
  };

  static const _languageAliases = {
    'c++': 'cpp',
    'c#': 'cs',
    'csharp': 'cs',
    'golang': 'go',
    'js': 'javascript',
    'jsx': 'javascript',
    'kt': 'kotlin',
    'html': 'xml',
    'md': 'markdown',
    'objc': 'objectivec',
    'py': 'python',
    'rb': 'ruby',
    'rs': 'rust',
    'sh': 'bash',
    'shell': 'bash',
    'ts': 'typescript',
    'tsx': 'typescript',
    'yml': 'yaml',
  };

  final TextStyle baseStyle;

  _OneDarkSyntaxHighlighter(TextStyle baseStyle)
    : baseStyle = baseStyle.copyWith(
        color: _foreground,
        backgroundColor: Colors.transparent,
      );

  @override
  TextSpan format(String source) => formatCode(source);

  TextSpan formatCode(String source, {String? language}) {
    final normalized = _normalizeLanguage(language);
    try {
      final result = normalized == null
          ? hl.highlight.parse(source, autoDetection: true)
          : hl.highlight.parse(source, language: normalized);
      return TextSpan(
        style: baseStyle,
        children: _spansFromNodes(result.nodes),
      );
    } catch (_) {
      return TextSpan(style: baseStyle, text: source);
    }
  }

  String? _normalizeLanguage(String? language) {
    final value = language?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    return _languageAliases[value] ?? value;
  }

  List<TextSpan> _spansFromNodes(List<hl.Node>? nodes, [TextStyle? inherited]) {
    final spans = <TextSpan>[];
    for (final node in nodes ?? const <hl.Node>[]) {
      final style = inherited == null
          ? _styleFor(node.className)
          : inherited.merge(_styleFor(node.className));
      if (node.value != null) {
        spans.addAll(_splitOperators(node.value!, style));
      } else if (node.children != null) {
        spans.addAll(_spansFromNodes(node.children, style));
      }
    }
    return spans;
  }

  List<TextSpan> _splitOperators(String value, TextStyle? style) {
    if (style?.color != null && style!.color != _foreground) {
      return [TextSpan(text: value, style: style)];
    }
    final spans = <TextSpan>[];
    var lastEnd = 0;
    for (final match in _plainTokenRegExp.allMatches(value)) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(text: value.substring(lastEnd, match.start), style: style),
        );
      }
      final token = match.group(0)!;
      spans.add(TextSpan(text: token, style: _stylePlainToken(token, style)));
      lastEnd = match.end;
    }
    if (lastEnd < value.length) {
      spans.add(TextSpan(text: value.substring(lastEnd), style: style));
    }
    return spans;
  }

  TextStyle? _stylePlainToken(String token, TextStyle? style) {
    final base = style ?? const TextStyle();
    if (_operatorRegExp.hasMatch(token)) {
      return base.merge(const TextStyle(color: _purple));
    }
    if (_reservedWords.contains(token)) {
      return base.merge(const TextStyle(color: _purple));
    }
    return base.merge(const TextStyle(color: _red));
  }

  TextStyle? _styleFor(String? className) {
    if (className == null) return null;
    final classes = className.split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    Color? color;
    for (final cls in classes) {
      color ??= _syntaxColors[cls];
    }
    if (color == null) return null;
    final isComment = classes.any((cls) => cls == 'comment' || cls == 'quote');
    final isStrong = classes.any((cls) => cls == 'strong');
    return TextStyle(
      color: color,
      fontStyle: isComment ? FontStyle.italic : null,
      fontWeight: isStrong ? FontWeight.w700 : null,
    );
  }
}

class _ExportableBlock extends StatelessWidget {
  static const _channel = MethodChannel('lynai/native_tools');

  final String label;
  final String source;
  final bool includeActions;
  final EdgeInsetsGeometry? margin;
  final Decoration decoration;
  final Widget child;
  final WidgetBuilder exportChildBuilder;
  final bool compactExport;

  const _ExportableBlock({
    required this.label,
    required this.source,
    required this.includeActions,
    required this.decoration,
    required this.child,
    required this.exportChildBuilder,
    this.compactExport = false,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin,
      clipBehavior: Clip.hardEdge,
      decoration: decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectionContainer.disabled(child: _header(context)),
          child,
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.36),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (includeActions) ...[
            _BlockIconButton(
              tooltip: '复制',
              icon: Icons.copy_all_outlined,
              onTap: () => _copySource(context),
            ),
            _BlockIconButton(
              tooltip: '导出图片',
              icon: Icons.image_outlined,
              onTap: () => _exportImage(context),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _copySource(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: source));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _exportImage(BuildContext context) async {
    try {
      final theme = Theme.of(context);
      final bytes = await ScreenshotController().captureFromLongWidget(
        _StandaloneBlockImage(
          label: label,
          brightness: theme.brightness,
          seedColor: theme.colorScheme.primary,
          decoration: decoration,
          compact: compactExport,
          child: exportChildBuilder(context),
        ),
        pixelRatio: compactExport ? 3.0 : (source.length > 4000 ? 1.35 : 2.0),
        context: context,
        constraints: const BoxConstraints(maxWidth: 840),
      );
      if (!context.mounted) return;
      await _writeImage(context, bytes);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出图片失败: $e')));
    }
  }

  Future<void> _writeImage(BuildContext context, Uint8List bytes) async {
    final fileName = 'lynai_block_${DateTime.now().millisecondsSinceEpoch}.png';
    if (_isDesktopPlatform) {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) throw Exception('当前平台不支持写入剪贴板');
      final item = DataWriterItem(suggestedName: fileName);
      item.add(Formats.png(bytes));
      await clipboard.write([item]);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('图片已复制到剪贴板')));
      return;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'saveImageToGallery',
        {'bytes': bytes, 'fileName': fileName},
      );
      if (result?['ok'] != true) {
        throw Exception(result?['error'] ?? '保存到图库失败');
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('图片已保存到图库')));
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  bool get _isDesktopPlatform {
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }
}

class _BlockIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  const _BlockIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(
            icon,
            size: 17,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _StandaloneBlockImage extends StatelessWidget {
  final String label;
  final Brightness brightness;
  final Color seedColor;
  final Decoration decoration;
  final bool compact;
  final Widget child;

  const _StandaloneBlockImage({
    required this.label,
    required this.brightness,
    required this.seedColor,
    required this.decoration,
    this.compact = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    final bgColor = Color.lerp(
      scheme.surface,
      scheme.primary,
      isDark ? 0.08 : 0.035,
    )!;
    if (compact) {
      return Material(
        color: Colors.transparent,
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: _compactDecoration(decoration, scheme, isDark),
          child: child,
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 840,
        padding: const EdgeInsets.all(34),
        color: bgColor,
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: decoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.36),
                  border: Border(
                    bottom: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Decoration _compactDecoration(
    Decoration decoration,
    ColorScheme scheme,
    bool isDark,
  ) {
    final color = Color.lerp(
      scheme.surface,
      scheme.surfaceContainerHighest,
      isDark ? 0.55 : 0.28,
    )!;
    if (decoration is BoxDecoration) {
      return decoration.copyWith(color: color);
    }
    return BoxDecoration(color: color);
  }
}
