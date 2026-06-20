import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:highlight/highlight.dart' as hl;

import 'tree_sitter_language_registry.dart';
import 'tree_sitter_native.dart';

/// 代码块渲染专用等宽字体。
const codeFontFamily = 'Hurmit Nerd Font';

/// 创建代码语法高亮器工厂函数。
///
/// 返回双路径高亮器：优先使用原生 tree-sitter 解析，降级时使用 OneDark Dart
/// 高亮作为兜底。两者通过 [TreeSitterSyntaxHighlighter] 串联。
CodeSyntaxHighlighter createCodeHighlighter(TextStyle baseStyle) {
  final fallback = OneDarkSyntaxHighlighter(baseStyle);
  return TreeSitterSyntaxHighlighter(fallback);
}

/// 代码语法高亮器抽象基类。
///
/// 继承自 flutter_markdown_plus 的 [SyntaxHighlighter]，添加带语言参数的
/// [formatCode] 方法，供具体实现按语言选择不同的高亮策略。
abstract class CodeSyntaxHighlighter extends SyntaxHighlighter {
  /// 对指定语言的源代码进行语法高亮并返回富文本片段。
  TextSpan formatCode(String source, {String? language});
}

/// 基于原生 tree-sitter 的语法高亮器，带降级兜底。
///
/// 高亮流程分三步：
/// 1. 通过 [TreeSitterLanguageRegistry] 查找语言定义，确认是否支持
/// 2. 跳过 Web 平台、超大文件（>200KB）和不支持的语言，直接走 Dart 降级
/// 3. 将 tree-sitter 返回的字节级 token 转换为 UTF-16 code unit 级 [TextSpan]
///
/// 该架构确保任何情况下都能返回可读的高亮结果，而不是白屏或崩溃。
class TreeSitterSyntaxHighlighter extends CodeSyntaxHighlighter {
  final OneDarkSyntaxHighlighter fallback;

  TreeSitterSyntaxHighlighter(this.fallback);

  @override
  TextSpan format(String source) => formatCode(source);

  @override
  TextSpan formatCode(String source, {String? language}) {
    final definition = TreeSitterLanguageRegistry.find(language);
    final native = TreeSitterNative.instance;
    // Web 平台无原生库、未知语言、超大文件、或 native 不可用时直接降级
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

  /// 将 tree-sitter 字节级 token 列表转换为 [TextSpan] 树。
  ///
  /// tree-sitter 返回的是 UTF-8 字节偏移，而 Dart 字符串使用 UTF-16 code unit
  /// 索引。这里通过预先构建的字节到 code unit 映射表完成转换。
  TextSpan _spanFromTokens(
    String source,
    List<TreeSitterHighlightToken> tokens,
  ) {
    final byteToCodeUnit = _byteToCodeUnitOffsets(source);
    final children = <TextSpan>[];
    var cursor = 0;
    // 按起始字节排序 token，确保渲染顺序正确
    final sortedTokens = [...tokens]
      ..sort((a, b) => a.startByte.compareTo(b.startByte));

    for (final token in sortedTokens) {
      // 跳过越界的 token（防御性处理）
      if (token.startByte >= byteToCodeUnit.length ||
          token.endByte >= byteToCodeUnit.length) {
        continue;
      }
      final start = byteToCodeUnit[token.startByte].clamp(0, source.length);
      final end = byteToCodeUnit[token.endByte].clamp(0, source.length);
      if (start < cursor || end <= start) continue;
      // 填充 token 之间的无高亮文本
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

    // 末尾剩余文本
    if (cursor < source.length) {
      children.add(TextSpan(text: source.substring(cursor)));
    }
    return TextSpan(style: fallback.baseStyle, children: children);
  }

  /// 构建字节偏移到 code unit 偏移的映射表。
  ///
  /// 返回的列表中，索引 i 对应第 i 个 UTF-8 字节在字符串中的 code unit 位置。
  /// 末尾填充 [source.length] 作为哨兵值。
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
      // BMP 内的字符占 1 个 code unit，补充平面的字符占 2 个
      codeUnitOffset += rune > 0xFFFF ? 2 : 1;
      offsets[byteOffset] = codeUnitOffset;
    }
    return offsets;
  }

  /// 根据 tree-sitter 的 token 类型编号返回对应的 TextStyle。
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

/// 基于 Dart highlight 库的 OneDark 配色语法高亮器。
///
/// 当原生 tree-sitter 不可用时（Web 平台、不支持的语言等），此高亮器作为降级
/// 方案使用。配色方案参考 Atom OneDark 主题。
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

  // 用于识别操作符和标点符号的正则表达式
  static final _operatorRegExp = RegExp(
    r'(===|!==|==|!=|<=|>=|=>|->|::|\.\.\.|\.\.|\+\+|--|&&|\|\||<<|>>|[-+*/%=&|^~!?:<>.,;()[\]{}])',
  );

  // 用于在无明确分类时拆分文本的通用 token 正则
  static final _plainTokenRegExp = RegExp(
    r'(===|!==|==|!=|<=|>=|=>|->|::|\.\.\.|\.\.|\+\+|--|&&|\|\||<<|>>|[-+*/%=&|^~!?:<>.,;()[\]{}]|\b[A-Za-z_][A-Za-z0-9_]*\b)',
  );

  // 跨语言保留字集合，用于将未识别的单词标记为关键字色
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

  // highlight.js 分类到 OneDark 颜色的映射表
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

  // 语言别名映射，将常见简称转换为 highlight.js 使用的标准名称
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

  /// 高亮器的基础文本样式，所有 span 由此派生。
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
      // 无语言信息时仅拆分操作符
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

  /// 将语言名称规范化为 highlight.js 可识别的名称。
  String? _normalizeLanguage(String? language) {
    final value = language?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    return _languageAliases[value] ?? value;
  }

  /// 递归将 highlight.js 的 AST 节点树转换为 [TextSpan] 列表。
  List<TextSpan> _spansFromNodes(List<hl.Node>? nodes, [TextStyle? inherited]) {
    final spans = <TextSpan>[];
    for (final node in nodes ?? const <hl.Node>[]) {
      // 合并父级样式和当前节点的分类样式
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

  /// 将文本按操作符和保留字拆分为独立的 [TextSpan]。
  ///
  /// 当 highlight.js 未能精确分类某个 token 时（如 Python 或未知语言），
  /// 此方法提供额外的操作符着色和保留字高亮。
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

  /// 对单个纯文本 token 进行分类：操作符 -> 紫色，保留字 -> 紫色，其他 -> 红色。
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

  /// 根据 highlight.js 的 className 返回对应的 TextStyle。
  ///
  /// className 可以是空格分隔的多个分类，取第一个有映射的颜色。
  /// 注释类型附加 italic，strong 类型附加 bold。
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
