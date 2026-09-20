/// 集合查找工具。
///
/// `Iterable.firstWhere` 在没有命中时会抛异常，调用方通常只能包一层 try/catch
/// 或写成 `where(...).firstOrNull`。这里提供一个直白的空值版本，供 Provider 和
/// Repository 复用。
library;

/// 返回第一个满足 [test] 的元素；没有命中时返回 null。
T? firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}
