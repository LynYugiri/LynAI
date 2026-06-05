import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:highlight/highlight.dart' as hl;

import 'tree_sitter_language_registry.dart';
import 'tree_sitter_native.dart';

const codeFontFamily = 'Hurmit Nerd Font';

CodeSyntaxHighlighter createCodeHighlighter(TextStyle baseStyle) {
  final fallback = OneDarkSyntaxHighlighter(baseStyle);
  return TreeSitterSyntaxHighlighter(fallback);
}

abstract class CodeSyntaxHighlighter extends SyntaxHighlighter {
  TextSpan formatCode(String source, {String? language});
}

class TreeSitterSyntaxHighlighter extends CodeSyntaxHighlighter {
  final OneDarkSyntaxHighlighter fallback;

  TreeSitterSyntaxHighlighter(this.fallback);

  @override
  TextSpan format(String source) => formatCode(source);

  @override
  TextSpan formatCode(String source, {String? language}) {
    final definition = TreeSitterLanguageRegistry.find(language);
    final native = TreeSitterNative.instance;
    if (kIsWeb ||
        definition == null ||
        source.length > 200 * 1024 ||
        !native.isAvailable ||
        !native.isLanguageSupported(definition.id)) {
      return fallback.formatCode(source, language: language);
    }

    final tokens = native.highlightTokens(definition.id, source);
    if (tokens.isEmpty) return fallback.formatCode(source, language: language);
    return _spanFromTokens(source, tokens);
  }

  TextSpan _spanFromTokens(
    String source,
    List<TreeSitterHighlightToken> tokens,
  ) {
    final byteToCodeUnit = _byteToCodeUnitOffsets(source);
    final children = <TextSpan>[];
    var cursor = 0;
    final sortedTokens = [...tokens]
      ..sort((a, b) => a.startByte.compareTo(b.startByte));

    for (final token in sortedTokens) {
      if (token.startByte >= byteToCodeUnit.length ||
          token.endByte >= byteToCodeUnit.length) {
        continue;
      }
      final start = byteToCodeUnit[token.startByte].clamp(0, source.length);
      final end = byteToCodeUnit[token.endByte].clamp(0, source.length);
      if (start < cursor || end <= start) continue;
      if (cursor < start) {
        children.add(TextSpan(text: source.substring(cursor, start)));
      }
      children.add(
        TextSpan(
          text: source.substring(start, end),
          style: _styleForTreeSitterKind(token.kind),
        ),
      );
      cursor = end;
    }

    if (cursor < source.length) {
      children.add(TextSpan(text: source.substring(cursor)));
    }
    return TextSpan(style: fallback.baseStyle, children: children);
  }

  List<int> _byteToCodeUnitOffsets(String source) {
    final totalBytes = utf8.encode(source).length;
    final offsets = List<int>.filled(totalBytes + 1, source.length);
    var byteOffset = 0;
    var codeUnitOffset = 0;
    for (final rune in source.runes) {
      final bytes = utf8.encode(String.fromCharCode(rune));
      for (var i = 0; i < bytes.length; i++) {
        offsets[byteOffset + i] = codeUnitOffset;
      }
      byteOffset += bytes.length;
      codeUnitOffset += rune > 0xFFFF ? 2 : 1;
      offsets[byteOffset] = codeUnitOffset;
    }
    return offsets;
  }

  TextStyle? _styleForTreeSitterKind(int kind) {
    return switch (kind) {
      TreeSitterTokenKind.keyword => const TextStyle(
        color: OneDarkSyntaxHighlighter._purple,
      ),
      TreeSitterTokenKind.string => const TextStyle(
        color: OneDarkSyntaxHighlighter._green,
      ),
      TreeSitterTokenKind.comment => const TextStyle(
        color: OneDarkSyntaxHighlighter._comment,
        fontStyle: FontStyle.italic,
      ),
      TreeSitterTokenKind.number => const TextStyle(
        color: OneDarkSyntaxHighlighter._orange,
      ),
      TreeSitterTokenKind.operator => const TextStyle(
        color: OneDarkSyntaxHighlighter._purple,
      ),
      TreeSitterTokenKind.type => const TextStyle(
        color: OneDarkSyntaxHighlighter._yellow,
      ),
      TreeSitterTokenKind.function => const TextStyle(
        color: OneDarkSyntaxHighlighter._blue,
      ),
      TreeSitterTokenKind.property => const TextStyle(
        color: OneDarkSyntaxHighlighter._red,
      ),
      TreeSitterTokenKind.variable => const TextStyle(
        color: OneDarkSyntaxHighlighter._red,
      ),
      TreeSitterTokenKind.constant => const TextStyle(
        color: OneDarkSyntaxHighlighter._cyan,
      ),
      TreeSitterTokenKind.punctuation => const TextStyle(
        color: OneDarkSyntaxHighlighter._foreground,
      ),
      TreeSitterTokenKind.tag => const TextStyle(
        color: OneDarkSyntaxHighlighter._red,
      ),
      TreeSitterTokenKind.attribute => const TextStyle(
        color: OneDarkSyntaxHighlighter._orange,
      ),
      _ => null,
    };
  }
}

class OneDarkSyntaxHighlighter extends CodeSyntaxHighlighter {
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
    'abstract', 'alignas', 'alignof', 'and', 'as', 'asm', 'async',
    'await', 'bool', 'break', 'case', 'catch', 'char', 'class',
    'const', 'constexpr', 'continue', 'def', 'default', 'delete',
    'do', 'double', 'dynamic', 'else', 'enum', 'export', 'extends',
    'false', 'final', 'finally', 'float', 'for', 'from', 'func',
    'function', 'if', 'implements', 'import', 'in', 'inline',
    'int', 'interface', 'is', 'let', 'long', 'namespace', 'new',
    'noexcept', 'not', 'nullptr', 'operator', 'or', 'private',
    'protected', 'public', 'return', 'short', 'signed', 'sizeof',
    'static', 'string', 'struct', 'super', 'switch', 'template',
    'this', 'throw', 'true', 'try', 'typedef', 'typename', 'union',
    'unsigned', 'using', 'var', 'virtual', 'void', 'volatile',
    'while', 'with',
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

  OneDarkSyntaxHighlighter(TextStyle baseStyle)
    : baseStyle = baseStyle.copyWith(
        color: _foreground,
        backgroundColor: const Color(0x00000000),
      );

  @override
  TextSpan format(String source) => formatCode(source);

  @override
  TextSpan formatCode(String source, {String? language}) {
    final normalized = _normalizeLanguage(language);
    if (normalized == null) {
      return TextSpan(
        style: baseStyle,
        children: _splitOperators(source, null),
      );
    }
    try {
      final result = hl.highlight.parse(source, language: normalized);
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
    final classes =
        className.split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    Color? color;
    for (final cls in classes) {
      color ??= _syntaxColors[cls];
    }
    if (color == null) return null;
    final isComment =
        classes.any((cls) => cls == 'comment' || cls == 'quote');
    final isStrong = classes.any((cls) => cls == 'strong');
    return TextStyle(
      color: color,
      fontStyle: isComment ? FontStyle.italic : null,
      fontWeight: isStrong ? FontWeight.w700 : null,
    );
  }
}
