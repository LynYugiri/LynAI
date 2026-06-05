import 'tree_sitter_native_stub.dart'
    if (dart.library.ffi) 'tree_sitter_native_ffi.dart';

/// Runtime probe for LynAI's optional bundled tree-sitter native library.
///
/// Rendering must not depend on this being present: tests, Web, and platforms
/// without the native bundle use the stub and fall back to Dart highlighting.
abstract class TreeSitterNative {
  static TreeSitterNative get instance => createTreeSitterNative();

  bool get isAvailable;
  int get compiledLanguageCount;
  bool isLanguageSupported(String language);
  TreeSitterParseSummary parseSummary(String language, String source);
  List<TreeSitterHighlightToken> highlightTokens(
    String language,
    String source,
  );
}

class TreeSitterTokenKind {
  static const unknown = 0;
  static const keyword = 1;
  static const string = 2;
  static const comment = 3;
  static const number = 4;
  static const operator = 5;
  static const type = 6;
  static const function = 7;
  static const property = 8;
  static const variable = 9;
  static const constant = 10;
  static const punctuation = 11;
  static const tag = 12;
  static const attribute = 13;
}

class TreeSitterHighlightToken {
  final int startByte;
  final int endByte;
  final int kind;

  const TreeSitterHighlightToken({
    required this.startByte,
    required this.endByte,
    required this.kind,
  });
}

class TreeSitterParseSummary {
  final bool supported;
  final bool parsed;
  final bool hasError;
  final int rootChildCount;
  final int rootStartByte;
  final int rootEndByte;

  const TreeSitterParseSummary({
    required this.supported,
    required this.parsed,
    required this.hasError,
    required this.rootChildCount,
    required this.rootStartByte,
    required this.rootEndByte,
  });

  static const unavailable = TreeSitterParseSummary(
    supported: false,
    parsed: false,
    hasError: false,
    rootChildCount: 0,
    rootStartByte: 0,
    rootEndByte: 0,
  );
}
