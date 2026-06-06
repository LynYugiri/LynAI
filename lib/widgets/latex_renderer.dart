import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:webview_all/webview_all.dart';

import '../services/code_syntax_service.dart';
import '../utils/snackbar_utils.dart';

typedef MarkdownBlockEditCallback =
    void Function(String source, int start, int end);

/// 低层 LaTeX 渲染工具。
///
/// 页面通常直接使用 [MarkdownWithLatex]；这个类保留给需要单独渲染公式的
/// 场景，例如块级公式导出或独立预览。
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
  final String rawSource;
  final TextStyle? textStyle;
  final bool selectable;
  final VoidCallback? onEdit;

  const _MathBlock({
    required this.formula,
    String? rawSource,
    this.textStyle,
    this.selectable = true,
    this.onEdit,
  }) : rawSource = rawSource ?? formula;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = 'LaTeX';
    try {
      return _ExportableBlock(
        label: label,
        source: rawSource,
        includeActions: selectable,
        onEdit: onEdit,
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
      source: rawSource,
      includeActions: selectable,
      onEdit: onEdit,
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

class _LatexParenthesizedInlineSyntax extends md.InlineSyntax {
  _LatexParenthesizedInlineSyntax() : super(r'\\\((.+?)\\\)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final formula = match[1]!;
    if (LatexRenderer._looksLikeMath(formula)) {
      final element = md.Element.text('inlineLatex', formula.trim());
      parser.addNode(element);
    } else {
      parser.addNode(md.Text('\\($formula\\)'));
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

/// 支持 Markdown、代码高亮和 LaTeX 的统一渲染组件。
///
/// 组件会避开 fenced code block 中的 `$`，避免把代码误判为公式。代码块和
/// 公式块可以复制源码，也可以按平台导出为图片。
class MarkdownWithLatex extends StatelessWidget {
  final String content;
  final TextStyle? textStyle;
  final bool selectable;
  final bool wrapCodeBlocks;
  final bool renderMermaid;
  final MarkdownBlockEditCallback? onEditLatexBlock;
  final MarkdownBlockEditCallback? onEditMermaidBlock;
  final MarkdownBlockEditCallback? onEditCodeBlock;

  const MarkdownWithLatex({
    super.key,
    required this.content,
    this.textStyle,
    this.selectable = true,
    this.wrapCodeBlocks = false,
    this.renderMermaid = true,
    this.onEditLatexBlock,
    this.onEditMermaidBlock,
    this.onEditCodeBlock,
  });

  static final _inlineRegExp = RegExp(r'\$(.+?)\$');
  static bool _hasInlineMath(String text) {
    final dollarMath = _inlineRegExp
        .allMatches(text)
        .any((m) => LatexRenderer._looksLikeMath(m.group(1) ?? ''));
    if (dollarMath) return true;
    return RegExp(r'\\\((.+?)\\\)')
        .allMatches(text)
        .any((m) => LatexRenderer._looksLikeMath(m.group(1) ?? ''));
  }

  @override
  Widget build(BuildContext context) {
    if (content.isEmpty) return const SizedBox.shrink();
    final segments = _splitFencedCodeBlocks(content);
    final nonFenced = segments
        .where((s) => !s.isFencedCodeBlock)
        .map((s) => s.text)
        .join('\n');
    final hasLatex = LatexRenderer.hasLatexContent(nonFenced);
    final hasMermaid =
        renderMermaid &&
        segments.any(
          (s) => s.isFencedCodeBlock && _mermaidFence(s.text) != null,
        );
    final child = hasLatex || hasMermaid || onEditCodeBlock != null
        ? _buildRichContent(context, segments)
        : _buildMarkdown(context, content);
    return selectable ? SelectionArea(child: child) : child;
  }

  Widget _buildMarkdown(
    BuildContext context,
    String text, {
    bool withInlineLatex = false,
  }) {
    final styleSheet = _markdownStyle(context);
    final highlighter = createCodeHighlighter(
      styleSheet.code ?? const TextStyle(fontFamily: codeFontFamily),
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
      data: _sanitizeFencedCodeInfo(_normalizeIndentedCodeBlocks(text)),
      selectable: false,
      styleSheet: styleSheet,
      builders: builders,
      extensionSet: _extensionSet(withInlineLatex: withInlineLatex),
      softLineBreak: true,
    );
  }

  String _sanitizeFencedCodeInfo(String text) {
    final lines = text.split('\n');
    var inFence = false;
    var fenceMarker = '';
    var fenceLength = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final openMatch = RegExp(
        r'^([ \t]{0,3})(`{3,}|~{3,})([^`~]*)$',
      ).firstMatch(line);
      final closeMatch = RegExp(
        r'^[ \t]{0,3}(`{3,}|~{3,})[ \t]*$',
      ).firstMatch(line);
      final wasInFence = inFence;
      if (!wasInFence && openMatch != null) {
        inFence = true;
        final indent = openMatch.group(1)!;
        final marker = openMatch.group(2)!;
        final info = openMatch.group(3)!.trim();
        fenceMarker = marker[0];
        fenceLength = marker.length;
        final language = _safeFenceLanguage(info);
        lines[i] = language == null
            ? '$indent$marker'
            : '$indent$marker$language';
      }
      if (wasInFence && closeMatch != null) {
        final marker = closeMatch.group(1)!;
        if (marker[0] == fenceMarker && marker.length >= fenceLength) {
          inFence = false;
        }
      }
    }
    return lines.join('\n');
  }

  String? _safeFenceLanguage(String info) {
    if (info.isEmpty) return null;
    final language = info.split(RegExp(r'\s+')).first.trim();
    if (RegExp(r'^[A-Za-z][A-Za-z0-9_+#.-]*$').hasMatch(language)) {
      return language;
    }
    return null;
  }

  String _normalizeIndentedCodeBlocks(String text) {
    final nbsp = String.fromCharCode(0x00A0);
    final lines = text.split('\n');
    var inFence = false;
    var fenceMarker = '';
    var fenceLength = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final openMatch = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(line);
      final closeMatch = RegExp(
        r'^ {0,3}(`{3,}|~{3,})[ \t]*$',
      ).firstMatch(line);
      final wasInFence = inFence;
      if (!wasInFence && openMatch != null) {
        inFence = true;
        fenceMarker = openMatch.group(1)![0];
        fenceLength = openMatch.group(1)!.length;
      } else if (!wasInFence && line.startsWith('    ')) {
        lines[i] = '$nbsp$nbsp$nbsp$nbsp${line.substring(4)}';
      }
      if (wasInFence && closeMatch != null) {
        final marker = closeMatch.group(1)!;
        if (marker[0] == fenceMarker && marker.length >= fenceLength) {
          inFence = false;
        }
      }
    }
    return lines.join('\n');
  }

  md.ExtensionSet _extensionSet({required bool withInlineLatex}) {
    final inlineSyntaxes = withInlineLatex
        ? [
            ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
            _LatexInlineSyntax(),
            _LatexParenthesizedInlineSyntax(),
          ]
        : md.ExtensionSet.gitHubFlavored.inlineSyntaxes;
    return md.ExtensionSet(
      md.ExtensionSet.gitHubFlavored.blockSyntaxes,
      inlineSyntaxes,
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
        fontFamily: codeFontFamily,
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

  Widget _buildRichContent(
    BuildContext context,
    List<_MarkdownSegment> segments,
  ) {
    final blockRegExp = RegExp(r'\$\$(.+?)\$\$|\\\[(.+?)\\\]', dotAll: true);
    final widgets = <Widget>[];

    for (final segment in segments) {
      if (segment.isFencedCodeBlock) {
        final mermaid = renderMermaid ? _mermaidFence(segment.text) : null;
        if (mermaid == null) {
          widgets.add(_buildCodeFence(context, segment));
        } else {
          widgets.add(
            _MermaidBlock(
              code: mermaid.code,
              source: segment.text,
              selectable: selectable,
              onEdit: onEditMermaidBlock == null
                  ? null
                  : () => onEditMermaidBlock!(
                      segment.text,
                      segment.startOffset,
                      segment.startOffset + segment.text.length,
                    ),
            ),
          );
        }
        continue;
      }

      var lastEnd = 0;
      for (final match in blockRegExp.allMatches(segment.text)) {
        final leading = segment.text.substring(lastEnd, match.start);
        if (leading.isNotEmpty) {
          if (_hasInlineMath(leading)) {
            widgets.add(
              _buildMarkdown(context, leading, withInlineLatex: true),
            );
          } else {
            widgets.add(_buildMarkdown(context, leading));
          }
        }
        final source = match.group(0) ?? '';
        final formula = (match.group(1) ?? match.group(2) ?? '').trim();
        widgets.add(
          _MathBlock(
            formula: formula,
            rawSource: source,
            textStyle: textStyle,
            selectable: selectable,
            onEdit: onEditLatexBlock == null
                ? null
                : () => onEditLatexBlock!(
                    source,
                    segment.startOffset + match.start,
                    segment.startOffset + match.end,
                  ),
          ),
        );
        lastEnd = match.end;
      }
      final trailing = segment.text.substring(lastEnd);
      if (trailing.isNotEmpty) {
        if (_hasInlineMath(trailing)) {
          widgets.add(_buildMarkdown(context, trailing, withInlineLatex: true));
        } else {
          widgets.add(_buildMarkdown(context, trailing));
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  Widget _buildCodeFence(BuildContext context, _MarkdownSegment segment) {
    final fence = MarkdownCodeFence.tryParse(
      segment.text,
      startOffset: segment.startOffset,
    );
    if (fence == null) return _buildMarkdown(context, segment.text);
    final styleSheet = _markdownStyle(context);
    final highlighter = createCodeHighlighter(
      styleSheet.code ?? const TextStyle(fontFamily: codeFontFamily),
    );
    return _CodeBlock(
      code: fence.bodyForDisplay,
      language: fence.language,
      span: highlighter.formatCode(
        fence.bodyForDisplay,
        language: fence.language,
      ),
      selectable: selectable,
      wrap: wrapCodeBlocks,
      onEdit: onEditCodeBlock == null
          ? null
          : () => onEditCodeBlock!(fence.source, fence.start, fence.end),
    );
  }

  @visibleForTesting
  static String? debugMermaidBody(String text) {
    return _mermaidFence(text)?.code;
  }

  @visibleForTesting
  static List<Map<String, Object?>> debugSegments(String text) {
    return _splitFencedCodeBlocks(text)
        .map(
          (s) => <String, Object?>{
            'text': s.text,
            'isFencedCodeBlock': s.isFencedCodeBlock,
            'startOffset': s.startOffset,
          },
        )
        .toList();
  }

  static _MermaidFence? _mermaidFence(String text) {
    final lines = text.split('\n');
    if (lines.length < 2) return null;
    final openMatch = RegExp(
      r'^[ \t]{0,3}(`{3,}|~{3,})([^`~]*)$',
    ).firstMatch(lines.first);
    if (openMatch == null) return null;
    final info = openMatch.group(2)!.trim();
    final language = info.isEmpty
        ? ''
        : info.split(RegExp(r'\s+')).first.trim().toLowerCase();
    if (language != 'mermaid' && language != 'mmd') return null;

    var end = lines.length;
    final closeMatch = RegExp(r'^[ \t]{0,3}(`{3,}|~{3,})[ \t]*$');
    while (end > 1 && lines[end - 1].trim().isEmpty) {
      end--;
    }
    if (end > 1 && closeMatch.hasMatch(lines[end - 1])) end--;
    final code = lines.sublist(1, end).join('\n').trimRight();
    if (code.trim().isEmpty) return null;
    return _MermaidFence(code);
  }

  static List<_MarkdownSegment> _splitFencedCodeBlocks(String text) {
    final segments = <_MarkdownSegment>[];
    final lines = text.split('\n');
    final buffer = StringBuffer();
    var inFence = false;
    var fenceMarker = '';
    var fenceLength = 0;
    var bufferStart = 0;
    var currentOffset = 0;

    void flush({required bool isFence}) {
      if (buffer.isEmpty) return;
      segments.add(_MarkdownSegment(buffer.toString(), isFence, bufferStart));
      buffer.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (buffer.isEmpty) bufferStart = currentOffset;
      final openMatch = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(line);
      final closeMatch = RegExp(
        r'^ {0,3}(`{3,}|~{3,})[ \t]*$',
      ).firstMatch(line);
      final wasInFence = inFence;
      if (!wasInFence && openMatch != null) {
        flush(isFence: false);
        bufferStart = currentOffset;
        inFence = true;
        fenceMarker = openMatch.group(1)![0];
        fenceLength = openMatch.group(1)!.length;
      }

      buffer.write(line);
      if (i != lines.length - 1) {
        buffer.write('\n');
        currentOffset += line.length + 1;
      } else {
        currentOffset += line.length;
      }

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

const _mermaidRendererAssetKey = 'assets/mermaid/renderer.html';

class _MermaidFence {
  final String code;

  const _MermaidFence(this.code);
}

class _MermaidBlock extends StatefulWidget {
  final String code;
  final String source;
  final bool selectable;
  final VoidCallback? onEdit;

  const _MermaidBlock({
    required this.code,
    required this.source,
    required this.selectable,
    this.onEdit,
  });

  @override
  State<_MermaidBlock> createState() => _MermaidBlockState();
}

class _MermaidBlockState extends State<_MermaidBlock> {
  WebViewController? _controller;
  var _ready = false;
  var _rendered = false;
  var _renderId = 0;
  var _height = 220.0;
  var _width = 420.0;
  String? _svg;
  String? _error;
  Brightness? _lastBrightness;
  Timer? _renderTimeout;

  bool get _supportsEmbeddedWebView {
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
    if (!_supportsEmbeddedWebView) return;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'MermaidBridge',
        onMessageReceived: (message) => _handleBridgeMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _ready = true;
            unawaited(_renderMermaid());
          },
          onNavigationRequest: (request) {
            if (!_ready) return NavigationDecision.navigate;
            final uri = Uri.tryParse(request.url);
            return uri != null &&
                    (uri.scheme == 'http' || uri.scheme == 'https')
                ? NavigationDecision.prevent
                : NavigationDecision.navigate;
          },
        ),
      )
      ..loadFlutterAsset(_mermaidRendererAssetKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_lastBrightness == brightness) return;
    _lastBrightness = brightness;
    if (_ready) {
      setState(() {
        _rendered = false;
        _error = null;
      });
      unawaited(_renderMermaid());
    }
  }

  @override
  void didUpdateWidget(covariant _MermaidBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code && _ready) {
      setState(() {
        _rendered = false;
        _svg = null;
        _error = null;
      });
      unawaited(_renderMermaid());
    }
  }

  @override
  void dispose() {
    _renderTimeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoration = BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: theme.colorScheme.primary.withValues(alpha: 0.16),
      ),
    );
    return _ExportableBlock(
      label: _label,
      source: widget.source,
      includeActions: widget.selectable,
      onEdit: widget.onEdit,
      decoration: decoration,
      exportChildBuilder: (_) => _exportBody(),
      child: _body(theme),
    );
  }

  String get _label {
    final first = widget.code
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    return first == 'mindmap' ? 'Mermaid Mindmap' : 'Mermaid';
  }

  Widget _body(ThemeData theme) {
    if (!_supportsEmbeddedWebView || _controller == null) {
      return _sourceFallback(theme, '当前平台暂不支持 Mermaid 预览');
    }
    if (_error != null) return _errorBody(theme);
    if (_rendered) return _webViewBody();
    return SizedBox(
      height: _height,
      child: Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: _controller!)),
          Positioned.fill(
            child: ColoredBox(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.68,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Mermaid 渲染中...',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _webViewBody() {
    final svg = _svg;
    if (svg != null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(_width, constraints.maxWidth);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: _height,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SvgPicture.string(svg, fit: BoxFit.contain),
              ),
            ),
          );
        },
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(_width, constraints.maxWidth);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: _height,
            child: WebViewWidget(controller: _controller!),
          ),
        );
      },
    );
  }

  Widget _exportBody() {
    final svg = _svg;
    if (svg == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          widget.source,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      );
    }
    return SizedBox(
      width: math.max(_width, 640),
      height: math.max(_height, 220),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: SvgPicture.string(svg, fit: BoxFit.contain),
      ),
    );
  }

  Widget _errorBody(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Mermaid 渲染失败\n$_error',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.code,
            style: TextStyle(
              fontFamily: codeFontFamily,
              fontSize: 13,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sourceFallback(ThemeData theme, String notice) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            notice,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.code,
            style: TextStyle(
              fontFamily: codeFontFamily,
              fontSize: 13,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _renderMermaid() async {
    final controller = _controller;
    if (!_ready || controller == null || !mounted) return;
    final renderId = ++_renderId;
    _renderTimeout?.cancel();
    _renderTimeout = Timer(const Duration(seconds: 8), () {
      if (!mounted || renderId != _renderId || _rendered || _error != null) {
        return;
      }
      setState(() => _error = '渲染超时，显示源码');
    });
    final payload = jsonEncode({
      'renderId': renderId,
      'code': widget.code,
      'theme': Theme.of(context).brightness == Brightness.dark
          ? 'dark'
          : 'light',
    });
    try {
      await controller.runJavaScript('window.renderMermaid($payload);');
    } catch (e) {
      _renderTimeout?.cancel();
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _handleBridgeMessage(String message) {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['renderId'] != _renderId) return;
      _renderTimeout?.cancel();
      setState(() {
        _width = ((data['width'] as num?)?.toDouble() ?? _width).clamp(
          220.0,
          2400.0,
        );
        _height = ((data['height'] as num?)?.toDouble() ?? _height).clamp(
          160.0,
          720.0,
        );
        if (data['ok'] == true) {
          final svg = (data['svg'] as String?)?.trim();
          if (svg == null || svg.isEmpty) {
            _rendered = false;
            _svg = null;
            _error = 'Mermaid 返回空 SVG';
          } else {
            _rendered = true;
            _svg = svg;
            _error = null;
          }
        } else {
          _rendered = false;
          _error = (data['error'] as String?) ?? '未知错误';
        }
      });
    } catch (e) {
      _renderTimeout?.cancel();
      if (mounted) setState(() => _error = e.toString());
    }
  }
}

class _MarkdownSegment {
  final String text;
  final bool isFencedCodeBlock;
  final int startOffset;

  const _MarkdownSegment(this.text, this.isFencedCodeBlock, this.startOffset);
}

/// Parsed Markdown fenced code block with source offsets in the parent note.
///
/// The parser keeps the exact opening/closing fence text so preview edits can
/// replace only the original block range without normalizing the user's
/// Markdown. Unclosed fences remain unclosed after editing.
class MarkdownCodeFence {
  final String source;
  final int start;
  final int end;
  final String openingFence;
  final String closingFence;
  final String info;
  final String? language;
  final String body;
  final int bodyStart;
  final int bodyEnd;
  final bool hasClosingFence;

  const MarkdownCodeFence({
    required this.source,
    required this.start,
    required this.end,
    required this.openingFence,
    required this.closingFence,
    required this.info,
    required this.language,
    required this.body,
    required this.bodyStart,
    required this.bodyEnd,
    required this.hasClosingFence,
  });

  String get bodyForDisplay => body.replaceAll(RegExp(r'\n$'), '');

  String wrapBody(String nextBody) {
    if (!hasClosingFence) return '$openingFence\n$nextBody';
    final suffix = nextBody.endsWith('\n') ? '' : '\n';
    return '$openingFence\n$nextBody$suffix$closingFence';
  }

  static MarkdownCodeFence? tryParse(String source, {int startOffset = 0}) {
    final firstLineEnd = source.indexOf('\n');
    if (firstLineEnd < 0) return null;
    final opening = source.substring(0, firstLineEnd);
    final openMatch = RegExp(
      r'^[ \t]{0,3}(`{3,}|~{3,})([^`~]*)$',
    ).firstMatch(opening);
    if (openMatch == null) return null;

    final marker = openMatch.group(1)!;
    final markerChar = marker[0];
    final markerLength = marker.length;
    final info = openMatch.group(2)!.trim();
    final language = _safeLanguage(info);
    final closingMarkerPattern = '${RegExp.escape(markerChar)}{$markerLength,}';
    final closePattern = RegExp('^[ \\t]{0,3}$closingMarkerPattern[ \\t]*\$');

    var lineStart = firstLineEnd + 1;
    var closingStart = source.length;
    var closingEnd = source.length;
    var closing = '';
    var hasClosingFence = false;
    while (lineStart <= source.length) {
      final lineEnd = source.indexOf('\n', lineStart);
      final safeLineEnd = lineEnd < 0 ? source.length : lineEnd;
      final line = source.substring(lineStart, safeLineEnd);
      if (closePattern.hasMatch(line)) {
        closingStart = lineStart;
        closingEnd = safeLineEnd;
        closing = line;
        hasClosingFence = true;
        break;
      }
      if (lineEnd < 0) break;
      lineStart = lineEnd + 1;
    }

    final bodyStart = firstLineEnd + 1;
    final bodyEnd = closingStart > bodyStart && source[closingStart - 1] == '\n'
        ? closingStart - 1
        : closingStart;
    final fencedSource = source.substring(0, closingEnd);
    return MarkdownCodeFence(
      source: fencedSource,
      start: startOffset,
      end: startOffset + fencedSource.length,
      openingFence: opening,
      closingFence: closing,
      info: info,
      language: language,
      body: source.substring(bodyStart, bodyEnd),
      bodyStart: startOffset + bodyStart,
      bodyEnd: startOffset + bodyEnd,
      hasClosingFence: hasClosingFence,
    );
  }

  static String? _safeLanguage(String info) {
    if (info.isEmpty) return null;
    final language = info.split(RegExp(r'\s+')).first.trim();
    if (RegExp(r'^[A-Za-z][A-Za-z0-9_+#.-]*$').hasMatch(language)) {
      return language;
    }
    return null;
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  final bool selectable;
  final bool wrap;
  final CodeSyntaxHighlighter highlighter;

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
  final VoidCallback? onEdit;

  const _CodeBlock({
    required this.code,
    required this.language,
    required this.span,
    required this.selectable,
    required this.wrap,
    this.onEdit,
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
      onEdit: onEdit,
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
                      fontFamily: codeFontFamily,
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
  final VoidCallback? onEdit;

  const _ExportableBlock({
    required this.label,
    required this.source,
    required this.includeActions,
    required this.decoration,
    required this.child,
    required this.exportChildBuilder,
    this.compactExport = false,
    this.margin,
    this.onEdit,
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
            if (onEdit != null)
              _BlockIconButton(
                tooltip: '编辑',
                icon: Icons.edit_outlined,
                onTap: onEdit!,
              ),
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
        pixelRatio: compactExport ? 4.0 : 2.5,
        context: context,
        constraints: const BoxConstraints(maxWidth: 840),
      );
      if (!context.mounted) return;
      await _writeImage(context, bytes);
    } catch (e) {
      if (!context.mounted) return;
      _showImageSnack(context, '导出图片失败: $e');
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
      _showImageSnack(context, '图片已复制到剪贴板');
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
      _showImageSnack(context, '图片已保存到图库');
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

  void _showImageSnack(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(shortSnackBar(message));
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
