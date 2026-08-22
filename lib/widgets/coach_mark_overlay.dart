import 'package:flutter/material.dart';

/// 聚光灯引导中的单个步骤。
///
/// [targetRect] 返回目标控件的全局矩形；返回 null 时提示卡居中显示，不挖洞。
/// 矩形在每次构建时重新测量，因此底部导航等静态控件可以直接用 GlobalKey
/// 测量，动态控件也能在步骤切换时拿到最新位置。
class CoachMarkStep {
  final String title;
  final String message;
  final IconData icon;
  final Rect? Function()? targetRect;

  const CoachMarkStep({
    required this.title,
    required this.message,
    this.icon = Icons.touch_app_outlined,
    this.targetRect,
  });
}

/// 全屏聚光灯引导。
///
/// 其余区域变暗，[CoachMarkStep.targetRect] 指定的区域保持高亮，旁边显示
/// 提示卡。步骤之间用「下一步」推进，最后一步为「完成」；任何一步都可以跳过。
/// 完成后调用 [onClose]，由调用方负责移除 overlay 并持久化完成标记。
class CoachMarkOverlay extends StatefulWidget {
  final List<CoachMarkStep> steps;
  final VoidCallback onClose;

  const CoachMarkOverlay({super.key, required this.steps, required this.onClose});

  @override
  State<CoachMarkOverlay> createState() => _CoachMarkOverlayState();
}

class _CoachMarkOverlayState extends State<CoachMarkOverlay> {
  int _index = 0;

  CoachMarkStep get _step => widget.steps[_index];

  void _next() {
    if (_index >= widget.steps.length - 1) {
      widget.onClose();
    } else {
      setState(() => _index += 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _step.targetRect?.call();
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () {},
              child: CustomPaint(painter: _DimPainter(target)),
            ),
          ),
          _buildCard(context, target),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, Rect? target) {
    final size = MediaQuery.of(context).size;
    final cardWidth = (size.width - 48).clamp(280.0, 420.0);
    final card = Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 12,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_step.icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _step.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${_index + 1}/${widget.steps.length}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_step.message, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onClose,
                  child: const Text('跳过'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _next,
                  child: Text(
                    _index >= widget.steps.length - 1 ? '完成' : '下一步',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final topPadding = MediaQuery.of(context).padding.top;
    if (target == null) {
      return Positioned(
        top: topPadding + 24,
        left: (size.width - cardWidth) / 2,
        width: cardWidth,
        child: card,
      );
    }

    const gap = 12.0;
    final cardHeight = 176.0;
    final left = (target.center.dx - cardWidth / 2).clamp(12.0, size.width - cardWidth - 12.0);
    final above = target.top - gap - cardHeight;
    final below = target.bottom + gap;
    final top = above >= topPadding + 12 ? above : below;
    return Positioned(
      top: top,
      left: left,
      width: cardWidth,
      child: card,
    );
  }
}

class _DimPainter extends CustomPainter {
  final Rect? hole;

  _DimPainter(this.hole);

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.62);
    if (hole == null || hole!.isEmpty) {
      canvas.drawRect(Offset.zero & size, dim);
      return;
    }

    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(
        RRect.fromRectAndRadius(
          hole!.inflate(8),
          const Radius.circular(14),
        ),
      );
    canvas.drawPath(path, dim);
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole!.inflate(8), const Radius.circular(14)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _DimPainter oldDelegate) {
    return oldDelegate.hole != hole;
  }
}
