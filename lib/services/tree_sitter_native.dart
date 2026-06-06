import 'tree_sitter_native_stub.dart'
    if (dart.library.ffi) 'tree_sitter_native_ffi.dart';

/// 原生 tree-sitter 库的 Dart 端抽象接口。
///
/// 通过条件导入实现平台自适应：
/// - 支持 `dart:ffi` 的平台加载 [tree_sitter_native_ffi.dart] 的 FFI 实现
/// - Web 等不支持 FFI 的平台加载 [tree_sitter_native_stub.dart] 的桩实现
///
/// 调用方应先检查 [isAvailable]，不可用时降级到 Dart 高亮方案。
/// [instance] 是全局单例，懒加载创建对应平台的实现。
abstract class TreeSitterNative {
  /// 根据平台获取对应的单例实现。
  static TreeSitterNative get instance => createTreeSitterNative();

  /// 原生库是否已成功加载且可用。
  bool get isAvailable;

  /// 已编译进原生库的语言语法数量。
  int get compiledLanguageCount;

  /// 检查指定语言 ID 的语法是否被原生库支持。
  bool isLanguageSupported(String language);

  /// 对源代码执行语法解析并返回解析摘要。
  TreeSitterParseSummary parseSummary(String language, String source);

  /// 对源代码执行语法高亮并返回 token 列表。
  List<TreeSitterHighlightToken> highlightTokens(
    String language,
    String source,
  );
}

/// Tree-sitter 语法 token 的类型常量。
///
/// 这些值与原生 C 侧 `TreeSitterTokenKind` 枚举一一对应，用于在高亮渲染时
/// 将单调的整数值映射到可视样式。
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

/// 单个语法高亮 token。
///
/// [startByte] 和 [endByte] 是 UTF-8 字节偏移（tree-sitter 原生输出格式），
/// 渲染时需通过字节到 code unit 映射表转换为 Dart 字符串索引。
/// [kind] 取值为 [TreeSitterTokenKind] 中的常量。
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

/// 语法解析结果摘要。
///
/// 相比完整的高亮 token 列表，这个轻量结构体适合在解析失败或语言不支持时
/// 快速返回状态信息，无需分配大数组。
class TreeSitterParseSummary {
  /// 该语言是否被原生库支持。
  final bool supported;

  /// 解析是否完成执行（不等于无错误，需结合 [hasError] 判断）。
  final bool parsed;

  /// 解析过程中是否出现语法错误。
  final bool hasError;

  /// 根语法节点的直接子节点数量。
  final int rootChildCount;

  /// 根节点起始字节偏移。
  final int rootStartByte;

  /// 根节点结束字节偏移。
  final int rootEndByte;

  const TreeSitterParseSummary({
    required this.supported,
    required this.parsed,
    required this.hasError,
    required this.rootChildCount,
    required this.rootStartByte,
    required this.rootEndByte,
  });

  /// 预定义的不可用状态常量，用于 FFI 未加载时的默认返回。
  static const unavailable = TreeSitterParseSummary(
    supported: false,
    parsed: false,
    hasError: false,
    rootChildCount: 0,
    rootStartByte: 0,
    rootEndByte: 0,
  );
}
