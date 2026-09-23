import 'package:flutter/material.dart';

import '../models/composer_reference.dart';

const int _refCodeStart = 0xE000;
const int _refCodeEnd = 0xF8FF;

/// 在普通文本流中渲染不可拆分引用 Chip 的输入控制器。
///
/// 权威状态是 [segments]（文本段与引用段交错）。底层 [text] 中每个引用 Chip
/// 用一个私用区码点占位，使 Chip 天然成为单个字符：退格/删除会整体移除，
/// 用户无法把光标切进 Chip 内部；渲染时再把占位码点换成 [WidgetSpan]。
///
/// 它继承 [TextEditingController]，因此可无缝替换现有输入框控制器，
/// 已有的键盘包装（`ChatComposerKeyboard`）与 `TextField` 无需改动。
class ReferenceComposerController extends TextEditingController {
  ReferenceComposerController({String text = ''}) {
    if (text.isNotEmpty) {
      value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  final Map<int, ComposerReference> _refsByCode = {};
  int _nextCode = _refCodeStart;

  /// 当前引用，按文本顺序。
  List<ComposerReference> get references {
    final result = <ComposerReference>[];
    for (final rune in text.runes) {
      final ref = _refsByCode[rune];
      if (ref != null) result.add(ref);
    }
    return result;
  }

  bool get hasReferences => _refsByCode.isNotEmpty;

  /// 发送给模型的正文：引用替换为 `<lynai_ref .../>`。
  String get modelText => _render(ComposerReferenceCodec.encode);

  /// 气泡展示的正文：引用替换为 `@标题`；文件夹引用带层级后缀以便区分。
  String get displayText => _render((ref) => '@${ref.displayTitle}');

  /// 片段列表，供消息持久化。
  List<ComposerSegment> get segments {
    final result = <ComposerSegment>[];
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final ref = _refsByCode[rune];
      if (ref == null) {
        buffer.writeCharCode(rune);
        continue;
      }
      if (buffer.isNotEmpty) {
        result.add(ComposerTextSegment(buffer.toString()));
        buffer.clear();
      }
      result.add(ComposerReferenceSegment(ref));
    }
    if (buffer.isNotEmpty) result.add(ComposerTextSegment(buffer.toString()));
    return result;
  }

  String _render(String Function(ComposerReference) encode) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final ref = _refsByCode[rune];
      if (ref == null) {
        buffer.writeCharCode(rune);
      } else {
        buffer.write(encode(ref));
      }
    }
    return buffer.toString();
  }

  /// 在光标处插入一个引用 Chip。
  void insertReference(ComposerReference reference) {
    final code = _allocateCode();
    _refsByCode[code] = reference;
    final sel = selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : start;
    final token = String.fromCharCode(code);
    value = TextEditingValue(
      text: text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
  }

  /// 把 `[start, end)`（通常是 `@查询词` 触发段）整体替换成一个引用 Chip。
  ///
  /// 光标停在 Chip 之后，触发文本不残留。
  void replaceRangeWithReference(
    int start,
    int end,
    ComposerReference reference,
  ) {
    final safeStart = start.clamp(0, text.length);
    final safeEnd = end.clamp(safeStart, text.length);
    final code = _allocateCode();
    _refsByCode[code] = reference;
    final token = String.fromCharCode(code);
    final next = text.replaceRange(safeStart, safeEnd, token);
    value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: safeStart + token.length),
    );
  }

  /// 把 `[start, end)`（通常是 `/查询词` 触发段）替换成普通文本。
  ///
  /// [replacement] 为空即删除该段；光标停在替换文本之后。用于指令面板：
  /// 立即执行的指令吃光触发文本，插入文本型指令留下可编辑正文。
  void replaceRangeWithText(int start, int end, String replacement) {
    final safeStart = start.clamp(0, text.length);
    final safeEnd = end.clamp(safeStart, text.length);
    final next = text.replaceRange(safeStart, safeEnd, replacement);
    value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: safeStart + replacement.length,
      ),
    );
  }

  /// 用普通文本替换当前选区（无选区时在光标处插入）。
  ///
  /// 引用按钮用它插入 `@` 触发符：触发态由文本推导，按钮不必另存状态。
  void replaceSelectionWithText(String replacement) {
    final sel = selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : start;
    final next = text.replaceRange(start, end, replacement);
    value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
  }

  /// 按绑定 ID 移除一个引用。
  void removeReference(String localId) {
    int? code;
    for (final entry in _refsByCode.entries) {
      if (entry.value.localId == localId) {
        code = entry.key;
        break;
      }
    }
    if (code == null) return;
    _refsByCode.remove(code);
    _writeText(text.replaceAll(String.fromCharCode(code), ''));
  }

  /// 整体替换片段（用于恢复持久化内容）。
  void replaceSegments(List<ComposerSegment> segments) {
    final codes = <int, ComposerReference>{};
    final buffer = StringBuffer();
    for (final segment in segments) {
      if (segment is ComposerTextSegment) {
        buffer.write(segment.text);
      } else if (segment is ComposerReferenceSegment) {
        final code = _allocateCode();
        codes[code] = segment.reference;
        buffer.writeCharCode(code);
      }
    }
    _refsByCode
      ..clear()
      ..addAll(codes);
    _writeText(buffer.toString());
  }

  void _writeText(String newText) {
    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }

  int _allocateCode() {
    final span = _refCodeEnd - _refCodeStart + 1;
    for (var i = 0; i < span; i++) {
      final code = _refCodeStart + ((_nextCode - _refCodeStart + i) % span);
      if (!_refsByCode.containsKey(code)) {
        _nextCode = code + 1;
        return code;
      }
    }
    throw StateError('引用数量超过上限');
  }

  @override
  set value(TextEditingValue newValue) {
    _reconcile(newValue.text);
    super.value = newValue;
  }

  void _reconcile(String newText) {
    final remaining = <int, ComposerReference>{};
    for (final rune in newText.runes) {
      final ref = _refsByCode[rune];
      if (ref != null) remaining[rune] = ref;
    }
    _refsByCode
      ..clear()
      ..addAll(remaining);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final children = <InlineSpan>[];
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final ref = _refsByCode[rune];
      if (ref == null) {
        buffer.writeCharCode(rune);
        continue;
      }
      if (buffer.isNotEmpty) {
        children.add(TextSpan(text: buffer.toString()));
        buffer.clear();
      }
      children.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _ReferenceChip(reference: ref),
        ),
      );
    }
    if (buffer.isNotEmpty) children.add(TextSpan(text: buffer.toString()));
    return TextSpan(style: style, children: children);
  }
}

class _ReferenceChip extends StatelessWidget {
  const _ReferenceChip({required this.reference});

  final ComposerReference reference;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            composerReferenceIcon(
              reference.type,
              scope: reference.scope,
            ),
            size: 12,
            color: scheme.primary,
          ),
          const SizedBox(width: 3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              reference.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: scheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// 引用类型的显示图标；文件夹层级用文件夹图标区分「整个文件夹」。
IconData composerReferenceIcon(
  ComposerReferenceType type, {
  ComposerReferenceScope scope = ComposerReferenceScope.entity,
}) {
  if (scope == ComposerReferenceScope.folder) return Icons.folder_outlined;
  return switch (type) {
    ComposerReferenceType.note => Icons.note,
    ComposerReferenceType.notePage => Icons.description,
    ComposerReferenceType.task => Icons.check_circle_outline,
    ComposerReferenceType.taskList => Icons.checklist,
    ComposerReferenceType.knowledgeBase => Icons.local_library_outlined,
    ComposerReferenceType.knowledgeEntry => Icons.description_outlined,
    ComposerReferenceType.pluginResource => Icons.extension,
    ComposerReferenceType.pluginSkill => Icons.auto_awesome,
    ComposerReferenceType.conversation => Icons.forum_outlined,
  };
}
