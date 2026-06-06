import 'tree_sitter_native.dart';

/// 工厂函数，当 FFI 不可用时（Web 平台、测试环境）返回 stub 实现。
TreeSitterNative createTreeSitterNative() => const _TreeSitterNativeStub();

/// 原生 tree-sitter 库的占位桩实现。
///
/// 当 `dart:ffi` 不可用时（Web 平台或某些测试环境），由条件导入机制选取此类。
/// 所有方法返回空值或 false，调用方应通过 [isAvailable] 检查并降级到 Dart
/// 高亮方案。
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
