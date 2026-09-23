import 'package:flutter/material.dart';

import '../services/composer_command_registry.dart';
import '../services/composer_selector_registry.dart';
import 'reference_composer.dart';

/// 触发面板的一行。
///
/// 引用行与指令行共用同一个列表与同一套键盘导航，因此选中态、上下移动和
/// 「回车确认」只有一份实现。
sealed class ComposerPaletteRow {
  const ComposerPaletteRow({required this.key, required this.title});

  final String key;
  final String title;

  String? get subtitle;

  IconData get icon;
}

/// 一条引用候选。
class ComposerReferenceRow extends ComposerPaletteRow {
  const ComposerReferenceRow({
    required super.key,
    required super.title,
    required this.value,
    this.modelId,
    this.isScope = false,
  });

  final ComposerSelectorValue value;

  /// 插件数据源声明的模型覆盖。
  final String? modelId;

  /// 是否是「引用整个 X」的范围行。
  final bool isScope;

  @override
  String? get subtitle => value.subtitle;

  @override
  IconData get icon => isScope
      ? Icons.select_all
      : composerReferenceIcon(value.type, scope: value.scope);
}

/// 一条 `/` 指令候选。
class ComposerCommandRow extends ComposerPaletteRow {
  ComposerCommandRow({required this.command})
    : super(key: 'command:${command.name}', title: '/${command.name}');

  final ComposerCommand command;

  @override
  String get title => '/${command.name}';

  @override
  String? get subtitle =>
      command.description.isEmpty ? command.displayTitle : command.description;

  @override
  IconData get icon => command.kind == ComposerCommandKind.run
      ? Icons.play_arrow_outlined
      : Icons.text_fields;
}

/// 输入框下方的 `@` / `/` 触发面板。
///
/// 面板只负责渲染与交互反馈：数据由页面从引用源注册表与指令注册表解析后
/// 传入，[selectedIndex] 也由页面持有，这样键盘（↑/↓/Enter/Esc）与鼠标
/// 共用同一套选中语义。
///
/// 首层列出引用源（或匹配到的指令）；[pendingItems] 非空表示已进入某个
/// 引用源，此时渲染该源在当前 [path] 与 [query] 下的条目。
class ComposerTriggerPalette extends StatefulWidget {
  const ComposerTriggerPalette({
    super.key,
    required this.sourceRows,
    required this.onSourceRowsChanged,
    required this.itemRows,
    required this.pendingItems,
    required this.query,
    required this.selectedIndex,
    required this.onSelect,
    required this.onEnterSource,
    required this.onBack,
    this.emptyHint = '没有匹配项',
  });

  /// 首层候选项（跨源搜索结果或指令列表）。
  final List<ComposerPaletteRow> sourceRows;

  /// 次层候选项（已进入某个引用源）。
  final List<ComposerPaletteRow> itemRows;

  /// [pendingItems] 解析完成后回调，供页面更新键盘可选项。
  final ValueChanged<List<ComposerPaletteRow>> onSourceRowsChanged;

  /// 是否处于「已进入某个引用源」的次层。
  final bool pendingItems;

  /// 当前过滤词，用于显示提示。
  final String query;

  final int selectedIndex;

  /// 确认选中一行；页面据此插入引用或执行指令。
  final ValueChanged<ComposerPaletteRow> onSelect;

  /// 进入引用源（点击源行）。
  final ValueChanged<ComposerSelector> onEnterSource;

  /// 次层返回首层。
  final VoidCallback onBack;

  final String emptyHint;

  @override
  State<ComposerTriggerPalette> createState() => _ComposerTriggerPaletteState();
}

class _ComposerTriggerPaletteState extends State<ComposerTriggerPalette> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ComposerTriggerPalette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) _revealSelection();
  }

  /// 让键盘选中的行保持可见。
  void _revealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      const extent = 48.0;
      final target = widget.selectedIndex * extent;
      final viewport = _scroll.position.viewportDimension;
      final current = _scroll.offset;
      if (target < current) {
        _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
      } else if (target + extent > current + viewport) {
        _scroll.jumpTo(
          (target + extent - viewport).clamp(0, _scroll.position.maxScrollExtent),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = widget.pendingItems ? widget.itemRows : widget.sourceRows;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(scheme),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: rows.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      widget.emptyHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: scheme.outline),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    itemCount: rows.length,
                    itemExtent: 48,
                    itemBuilder: (context, index) => _row(
                      context,
                      rows[index],
                      index == widget.selectedIndex,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    final label = widget.pendingItems
        ? (widget.query.isEmpty ? '选择要引用的内容' : '搜索「${widget.query}」')
        : (widget.query.isEmpty ? '搜索或选择类型' : '搜索「${widget.query}」');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 4),
      child: Row(
        children: [
          if (widget.pendingItems)
            IconButton(
              tooltip: '返回',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_back, size: 18),
              onPressed: widget.onBack,
            )
          else
            Icon(Icons.alternate_email, size: 18, color: scheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: scheme.outline),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '↑↓ 选择 · Enter 确认 · Esc 关闭',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, ComposerPaletteRow row, bool selected) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = row.subtitle;
    return InkWell(
      onTap: () {
        if (row is ComposerSourceRow) {
          widget.onEnterSource(row.selector);
        } else {
          widget.onSelect(row);
        }
      },
      child: Container(
        color: selected ? scheme.primary.withValues(alpha: 0.10) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(row.icon, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.title,
                    style: const TextStyle(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (row is ComposerSourceRow)
              const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

/// 首层的一个引用源条目。
///
/// 与 [ComposerReferenceRow] 分列，是因为两者的确认语义不同：源条目是
/// 「进入下一层」，引用条目才是「插入引用」。
class ComposerSourceRow extends ComposerPaletteRow {
  ComposerSourceRow({required this.selector})
    : super(
        key: 'source:${selector.name}',
        title: selector.title.isEmpty ? selector.name : selector.title,
      );

  final ComposerSelector selector;

  @override
  String get title =>
      selector.title.isEmpty ? selector.name : selector.title;

  @override
  String? get subtitle =>
      selector.description.isEmpty ? null : selector.description;

  @override
  IconData get icon => selector.icon ?? Icons.folder_open_outlined;
}
