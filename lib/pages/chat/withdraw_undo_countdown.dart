import 'package:flutter/material.dart';

/// 撤回提示里的环形倒计时展示。
///
/// 环按剩余比例反向收缩，环心显示剩余秒数，右侧是说明文字。组件只负责视觉
/// 呈现与秒数递减，不承担关闭或撤销语义：关闭由承载它的容器（例如 `SnackBar`
/// 的 `duration` + `persist: false`）决定，撤销由容器上的操作按钮决定。
class WithdrawUndoCountdown extends StatefulWidget {
  /// 创建一个环形倒计时组件。
  const WithdrawUndoCountdown({
    super.key,
    required this.duration,
    this.label = '已撤回，内容回到输入框',
  });

  /// 倒计时总时长，必须大于零。
  final Duration duration;

  /// 倒计时环右侧的说明文字。
  final String label;

  @override
  State<WithdrawUndoCountdown> createState() => _WithdrawUndoCountdownState();
}

class _WithdrawUndoCountdownState extends State<WithdrawUndoCountdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // SnackBar 正文颜色由主题决定（M3 是 onInverseSurface），环沿用同一颜色，
    // 避免在浅色/深色主题下各自硬编码。
    final color =
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onInverseSurface;
    final totalSeconds = _totalSeconds;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final remaining = _remainingSeconds(totalSeconds);
        return Row(
          children: [
            Semantics(
              label: '撤销剩余 $remaining 秒',
              child: ExcludeSemantics(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: 1 - _controller.value,
                        strokeWidth: 2.5,
                        color: color,
                        backgroundColor: color.withValues(alpha: 0.28),
                      ),
                      Text(
                        '$remaining',
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(widget.label)),
          ],
        );
      },
    );
  }

  /// 总秒数只用于收敛首尾显示，避免出现 `0` 或超过总时长的数字。
  int get _totalSeconds =>
      (widget.duration.inMilliseconds / 1000).ceil().clamp(1, 3600);

  int _remainingSeconds(int totalSeconds) {
    final remainingMs =
        widget.duration.inMilliseconds * (1 - _controller.value);
    return (remainingMs / 1000).ceil().clamp(1, totalSeconds);
  }
}
