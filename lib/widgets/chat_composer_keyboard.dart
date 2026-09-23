import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum ChatComposerEnterAction { send, newline }

ChatComposerEnterAction resolveChatComposerEnterAction({
  required TargetPlatform platform,
  required bool controlPressed,
  required bool metaPressed,
  required bool shiftPressed,
  required bool altPressed,
  required bool composing,
}) {
  if (composing || altPressed) return ChatComposerEnterAction.newline;
  if (controlPressed || metaPressed) return ChatComposerEnterAction.send;
  if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
    return ChatComposerEnterAction.newline;
  }
  return shiftPressed
      ? ChatComposerEnterAction.newline
      : ChatComposerEnterAction.send;
}

class ChatComposerKeyboard extends StatelessWidget {
  const ChatComposerKeyboard({
    super.key,
    required this.controller,
    required this.onSend,
    required this.child,
    this.onPaste,
    this.onPaletteKey,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onPaste;

  /// `@` / `/` 触发面板打开时的按键拦截；返回 true 表示已消费。
  ///
  /// 面板的候选项选中态由页面持有，所以键盘语义（↑/↓ 移动、Enter 确认、
  /// Esc 关闭）在这里统一转发给页面；面板关闭时该回调为 null，回车与方向键
  /// 的既有行为完全不变。
  final bool Function(KeyEvent event)? onPaletteKey;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(onKeyEvent: _handleKeyEvent, child: child);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final paletteKey = onPaletteKey;
    if (paletteKey != null &&
        (event is KeyDownEvent || event is KeyRepeatEvent)) {
      // 输入法组合期间不抢键：此时 Enter 属于上屏而不是确认候选项。
      final composingRange = controller.value.composing;
      final composing =
          composingRange.isValid && !composingRange.isCollapsed;
      if (!composing && paletteKey(event)) return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      final composingRange = controller.value.composing;
      final action = resolveChatComposerEnterAction(
        platform: defaultTargetPlatform,
        controlPressed: keyboard.isControlPressed,
        metaPressed: keyboard.isMetaPressed,
        shiftPressed: keyboard.isShiftPressed,
        altPressed: keyboard.isAltPressed,
        composing: composingRange.isValid && !composingRange.isCollapsed,
      );
      if (action == ChatComposerEnterAction.send) {
        onSend();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final paste =
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (keyboard.isControlPressed || keyboard.isMetaPressed);
    if (paste && onPaste != null) onPaste!();
    return KeyEventResult.ignored;
  }
}

class DesktopEscapeBackScope extends StatefulWidget {
  const DesktopEscapeBackScope({
    super.key,
    required this.onBack,
    required this.child,
  });

  final VoidCallback onBack;
  final Widget child;

  @override
  State<DesktopEscapeBackScope> createState() => _DesktopEscapeBackScopeState();
}

class _DesktopEscapeBackScopeState extends State<DesktopEscapeBackScope> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  bool _handleKeyEvent(KeyEvent event) {
    if (!_isDesktop ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        ModalRoute.of(context)?.isCurrent != true ||
        _focusIsEditingText()) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed ||
        keyboard.isAltPressed) {
      return false;
    }
    widget.onBack();
    return true;
  }

  bool get _isDesktop {
    if (kIsWeb) return true;
    return defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS;
  }

  bool _focusIsEditingText() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    return focusContext?.findAncestorWidgetOfExactType<EditableText>() !=
            null ||
        focusContext?.widget is EditableText;
  }
}
