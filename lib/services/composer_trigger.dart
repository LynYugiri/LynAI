/// 输入框内 `@` / `/` 触发的检测规则。
///
/// 触发态**不保存状态**：每次都由「光标前的那段文本」重新推导。因此只要用户
/// 输入空格、换行或其它无关内容，触发就不再成立，那段文本按普通正文处理，
/// 不会留下任何痕迹。
///
/// 规则：
/// - `@` 与 `/` 必须位于文首、行首或空白之后；
/// - `/` 额外要求它前面只有空白（即行首形式），因为 `/` 在正文里太常见
///   （`A/B`、`和/或`、URL、路径），只认行首能避免误触发；
/// - token 内部出现空白或换行立即失效，所以 `@笔记 你好` 里的 `@笔记`
///   也只是普通文本；
/// - 邮箱、URL、文件路径里的 `@` 与 `/` 前方不是空白，天然不触发。
library;

/// 触发种类。
enum ComposerTriggerKind {
  /// `@`：引用面板。
  reference,

  /// `/`：指令面板。
  command,
}

/// 一次成功的触发：触发符所在位置、种类与过滤词。
class ComposerTriggerMatch {
  const ComposerTriggerMatch({
    required this.kind,
    required this.start,
    required this.end,
    required this.query,
  });

  final ComposerTriggerKind kind;

  /// 触发符（`@` 或 `/`）在文本中的下标。
  final int start;

  /// 光标位置；替换触发段时用 `[start, end)`。
  final int end;

  /// 触发符之后、光标之前的过滤词，可能为空。
  final String query;

  /// 触发符自身，用于回填提示。
  String get symbol =>
      kind == ComposerTriggerKind.reference ? referenceSymbol : commandSymbol;

  bool get isReference => kind == ComposerTriggerKind.reference;

  static const referenceSymbol = '@';
  static const commandSymbol = '/';
}

/// 从 [text] 与 [cursor] 推导当前触发；没有触发返回 null。
///
/// [cursor] 必须是有效的光标位置（折叠选区）。选区非折叠时调用方应传 null，
/// 表示「正在选择文本」——此时不应弹面板。
ComposerTriggerMatch? detectComposerTrigger({
  required String text,
  required int? cursor,
}) {
  if (cursor == null || cursor < 0 || cursor > text.length) return null;
  var index = cursor - 1;
  while (index >= 0) {
    final char = text[index];
    if (_isWhitespace(char)) return null;
    if (char == ComposerTriggerMatch.referenceSymbol) {
      return _match(
        text: text,
        index: index,
        cursor: cursor,
        kind: ComposerTriggerKind.reference,
      );
    }
    if (char == ComposerTriggerMatch.commandSymbol) {
      final match = _match(
        text: text,
        index: index,
        cursor: cursor,
        kind: ComposerTriggerKind.command,
      );
      if (match == null) return null;
      // `/` 只认行首（允许缩进空白），避免 URL、路径与 `A/B` 误触发。
      return _lineIsBlankBefore(text, index) ? match : null;
    }
    index--;
  }
  return null;
}

ComposerTriggerMatch? _match({
  required String text,
  required int index,
  required int cursor,
  required ComposerTriggerKind kind,
}) {
  if (!_precededByBoundary(text, index)) return null;
  final query = text.substring(index + 1, cursor);
  // token 内部一旦出现空白，触发立即失效，整段退回普通文本。
  if (query.contains(RegExp(r'\s'))) return null;
  return ComposerTriggerMatch(
    kind: kind,
    start: index,
    end: cursor,
    query: query,
  );
}

/// 触发符前必须是文首或空白，否则视为普通字符（邮箱、路径等）。
bool _precededByBoundary(String text, int index) {
  if (index == 0) return true;
  return _isWhitespace(text[index - 1]);
}

/// [index] 之前到行首之间是否只有空白。
bool _lineIsBlankBefore(String text, int index) {
  var cursor = index - 1;
  while (cursor >= 0) {
    final char = text[cursor];
    if (char == '\n') return true;
    if (!_isWhitespace(char)) return false;
    cursor--;
  }
  return true;
}

bool _isWhitespace(String char) => char.trim().isEmpty;
