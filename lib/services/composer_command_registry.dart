/// `/` 指令的种类，决定选中后如何收尾。
enum ComposerCommandKind {
  /// 立即执行：吃掉触发文本，不往输入框留任何字符。
  run,

  /// 插入文本：把 [ComposerCommand.insertText] 填进输入框，用户可以继续编辑。
  insert,
}

/// 一条 `/` 指令。
///
/// 指令**没有参数语法**：要么立即执行（需要不同行为就加一条新指令），要么把
/// 一段可编辑文本插进输入框。参数解析需要分隔符与转义，会和「`/` 后输入空格
/// 即退回普通文本」的规则直接冲突，因此不引入。
class ComposerCommand {
  /// 规范名（不含 `/`），用于匹配与展示。
  final String name;

  /// 兼容别名，例如 `compact` 之于 `压缩`。
  final List<String> aliases;

  /// 面板标题。
  final String title;

  /// 面板说明。
  final String description;

  final ComposerCommandKind kind;

  /// [ComposerCommandKind.insert] 时插入输入框的文本。
  final String insertText;

  /// 执行动作的稳定标识；[ComposerCommandKind.run] 由页面按 id 分发。
  ///
  /// 注册表本身不持有执行逻辑，避免服务层依赖 BuildContext / Provider。
  final String actionId;

  const ComposerCommand({
    required this.name,
    this.aliases = const [],
    this.title = '',
    this.description = '',
    this.kind = ComposerCommandKind.run,
    this.insertText = '',
    this.actionId = '',
  });

  /// 面板主标题：优先中文标题，回退到规范名。
  String get displayTitle => title.isNotEmpty ? title : '/$name';

  bool _matchesText(String? value, String query) {
    if (value == null || value.isEmpty) return false;
    return value.toLowerCase().contains(query);
  }

  /// 与过滤词 [rawQuery] 的匹配程度；0 表示不匹配，数值越小越靠前。
  ///
  /// 规范名与别名前缀命中优先于标题、说明的子串命中；全不中即返回 0，调用方
  /// 据此把该指令从列表移除（于是「没匹配到就当普通字符」成为自然结果）。
  /// 每条指令只给出一个分数：标题通常包含名称，若前缀命中后继续比标题，同一条
  /// 指令会被计入两次。
  int matchScore(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return 1;
    if (name.toLowerCase().startsWith(query)) return 1;
    for (final alias in aliases) {
      if (alias.toLowerCase().startsWith(query)) return 1;
    }
    if (_matchesText(title, query)) return 2;
    if (_matchesText(description, query)) return 3;
    for (final alias in aliases) {
      if (_matchesText(alias, query)) return 3;
    }
    return 0;
  }
}

/// `/` 指令注册表：内置指令与插件指令共用一套匹配规则。
class ComposerCommandRegistry {
  final List<ComposerCommand> _commands = [];

  void register(ComposerCommand command) => _commands.add(command);

  Iterable<ComposerCommand> get commands => List.unmodifiable(_commands);

  bool get isEmpty => _commands.isEmpty;

  /// 按 [query] 过滤并按匹配度排序；未命中的指令不返回。
  List<ComposerCommand> search(String query) {
    final scored = <(int, ComposerCommand)>[];
    for (final command in _commands) {
      final score = command.matchScore(query);
      if (score == 0) continue;
      scored.add((score, command));
    }
    scored.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final entry in scored) entry.$2];
  }
}

/// 内置指令的稳定 action id；页面按它分发执行。
abstract final class ComposerCommandActions {
  /// 压缩当前对话较早历史并持久化 checkpoint。
  static const compact = 'chat.compact';

  /// 用当前模型总结压缩后的上下文，结果不进上下文。
  static const summarize = 'chat.summarize';
}

/// 内置指令：默认中文命名，英文名作为别名兼容。
List<ComposerCommand> builtInComposerCommands() => const [
  ComposerCommand(
    name: '压缩',
    aliases: ['compact'],
    title: '压缩上下文',
    description: '把较早的对话历史压缩成检查点，界面保留原文但发送时用摘要顶替',
    kind: ComposerCommandKind.run,
    actionId: ComposerCommandActions.compact,
  ),
  ComposerCommand(
    name: '总结',
    aliases: ['summarize'],
    title: '总结这段对话',
    description: '用当前模型总结压缩后的上下文，结果只展示、不进入上下文',
    kind: ComposerCommandKind.run,
    actionId: ComposerCommandActions.summarize,
  ),
];

/// 构建内置指令注册表。
ComposerCommandRegistry buildBuiltInCommandRegistry({
  List<ComposerCommand>? extra,
}) {
  final registry = ComposerCommandRegistry();
  for (final command in builtInComposerCommands()) {
    registry.register(command);
  }
  for (final command in extra ?? const <ComposerCommand>[]) {
    registry.register(command);
  }
  return registry;
}
