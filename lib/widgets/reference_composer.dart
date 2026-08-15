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

  /// 气泡展示的正文：引用替换为 `@标题`。
  String get displayText => _render((ref) => '@${ref.title}');

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
      final code =
          _refCodeStart + ((_nextCode - _refCodeStart + i) % span);
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
          Icon(_typeIcon(reference.type), size: 12, color: scheme.primary),
          const SizedBox(width: 3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              reference.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: scheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  IconData _typeIcon(ComposerReferenceType type) => switch (type) {
    ComposerReferenceType.note => Icons.note,
    ComposerReferenceType.notePage => Icons.description,
    ComposerReferenceType.task => Icons.check_circle_outline,
    ComposerReferenceType.taskList => Icons.checklist,
    ComposerReferenceType.pluginResource => Icons.extension,
    ComposerReferenceType.pluginSkill => Icons.auto_awesome,
  };
}
