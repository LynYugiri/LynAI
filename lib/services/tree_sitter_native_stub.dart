import 'tree_sitter_native.dart';

TreeSitterNative createTreeSitterNative() => const _TreeSitterNativeStub();

class _TreeSitterNativeStub implements TreeSitterNative {
  const _TreeSitterNativeStub();

  @override
  bool get isAvailable => false;

  @override
  int get compiledLanguageCount => 0;

  @override
  bool isLanguageSupported(String language) => false;

  @override
  TreeSitterParseSummary parseSummary(String language, String source) {
    return TreeSitterParseSummary.unavailable;
  }

  @override
  List<TreeSitterHighlightToken> highlightTokens(
    String language,
    String source,
  ) {
    return const [];
  }
}
