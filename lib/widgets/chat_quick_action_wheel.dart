import 'package:flutter/material.dart';

import '../models/chat_quick_action.dart';

enum ChatQuickActionWheelMode { normal, edit }

class ChatQuickActionWheelVisualState {
  final ChatQuickActionWheelMode mode;
  final String? selectedDirection;
  final ChatQuickActions actions;

  const ChatQuickActionWheelVisualState({
    required this.mode,
    required this.selectedDirection,
    required this.actions,
  });
}

/// 全屏快捷盘 Overlay：只展示，不拦截手势。
class ChatQuickActionWheelOverlay extends StatelessWidget {
  final ChatQuickActionWheelVisualState state;

  const ChatQuickActionWheelOverlay({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 104,
            child: Center(
              child: ChatQuickActionWheel(state: state, primaryColor: primary),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatQuickActionWheel extends StatelessWidget {
  final ChatQuickActionWheelVisualState state;
  final Color primaryColor;

  const ChatQuickActionWheel({
    super.key,
    required this.state,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final editMode = state.mode == ChatQuickActionWheelMode.edit;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: editMode
                  ? Colors.amber.withValues(alpha: 0.9)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              editMode ? '松开选择要修改的方向' : '滑向一个方向',
              style: TextStyle(
                color: editMode
                    ? Colors.black
                    : Theme.of(context).colorScheme.onSurface,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _DirectionCard(
            direction: 'up',
            icon: Icons.keyboard_arrow_up_rounded,
            action: state.actions.up,
            selected: state.selectedDirection == 'up',
            editMode: editMode,
            primaryColor: primaryColor,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DirectionCard(
                direction: 'left',
                icon: Icons.keyboard_arrow_left_rounded,
                action: state.actions.left,
                selected: state.selectedDirection == 'left',
                editMode: editMode,
                primaryColor: primaryColor,
              ),
              const SizedBox(width: 10),
              _DirectionCard(
                direction: 'right',
                icon: Icons.keyboard_arrow_right_rounded,
                action: state.actions.right,
                selected: state.selectedDirection == 'right',
                editMode: editMode,
                primaryColor: primaryColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DirectionCard extends StatelessWidget {
  final String direction;
  final IconData icon;
  final ChatQuickAction action;
  final bool selected;
  final bool editMode;
  final Color primaryColor;

  const _DirectionCard({
    required this.direction,
    required this.icon,
    required this.action,
    required this.selected,
    required this.editMode,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = editMode
        ? (selected ? Colors.amber : Colors.brown)
        : (selected ? primaryColor : Theme.of(context).colorScheme.surface);
    final borderColor = editMode
        ? (selected ? Colors.amber : Colors.amber.withValues(alpha: 0.4))
        : (selected
              ? primaryColor
              : Theme.of(context).colorScheme.outlineVariant);
    return AnimatedScale(
      scale: selected ? 1.18 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: selected ? 0.9 : 0.85),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: editMode
                  ? Colors.black
                  : Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(height: 2),
            Text(
              action.displayTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: editMode
                    ? Colors.black
                    : Theme.of(context).colorScheme.onSurface,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
