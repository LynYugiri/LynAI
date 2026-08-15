import 'package:flutter/material.dart';

import '../../models/agent_plan.dart';

/// 对话页底部常驻的 Agent Plan 面板。
///
/// 三级信息密度：
/// - 收起态：标题、完成进度、细进度条、当前激活步骤；
/// - 内联展开态：每步状态 chip 和一行摘要，点击步骤展开完整摘要；
/// - 底部详情视图：完整标题、统计和所有步骤详情。
class AgentPlanPanel extends StatefulWidget {
  const AgentPlanPanel({super.key, required this.plan});

  final AgentPlan plan;

  @override
  State<AgentPlanPanel> createState() => _AgentPlanPanelState();
}

class _AgentPlanPanelState extends State<AgentPlanPanel> {
  bool? _expanded;
  String? _expandedStepId;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final scheme = Theme.of(context).colorScheme;
    final expanded = _expanded ?? MediaQuery.sizeOf(context).width >= 600;
    final completed = _completedCount(plan);
    final active = _activeItem(plan);
    final progress = plan.items.isEmpty
        ? 0.0
        : (completed / plan.items.length).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _expanded = !expanded),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(
                          expanded ? Icons.expand_more : Icons.chevron_right,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.account_tree_outlined,
                          size: 16,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '计划 $completed/${plan.items.length}：'
                            '${active?.title ?? plan.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          '$completed/${plan.items.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _showPlanDetails(context),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                child: const Text('详情', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 0, 0, 2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                color: scheme.primary,
                backgroundColor: scheme.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
          ),
          if (active != null)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 2),
              child: Text(
                '当前：${active.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (expanded) ...[
            const SizedBox(height: 4),
            for (var index = 0; index < plan.items.length; index++)
              _planStep(plan.items[index], index),
          ],
          Divider(
            height: 8,
            color: scheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ],
      ),
    );
  }

  Widget _planStep(AgentPlanItem item, int index) {
    final scheme = Theme.of(context).colorScheme;
    final active = _isActive(item);
    final failed = item.status == AgentPlanItem.failed;
    final completed = _isCompleted(item);
    final detail = failed
        ? (item.error ?? item.summary)
        : completed
        ? (item.resultSummary ?? item.summary)
        : item.summary;
    final color = failed
        ? scheme.error
        : active
        ? scheme.primary
        : scheme.onSurfaceVariant.withValues(alpha: completed ? 0.58 : 0.82);
    final marker = completed
        ? '✓'
        : failed
        ? '!'
        : active
        ? '•'
        : '·';
    final expanded = _expandedStepId == item.id;
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 3),
      child: InkWell(
        onTap: detail == null || detail.isEmpty
            ? null
            : () => setState(() {
                _expandedStepId = expanded ? null : item.id;
              }),
        borderRadius: BorderRadius.circular(6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: 16,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: active || failed ? color : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 16,
              child: Text(
                marker,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${index + 1}. ${item.title}',
                          maxLines: expanded ? null : 1,
                          overflow: expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: color,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _statusChip(item.status, color),
                    ],
                  ),
                  if (detail != null && detail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        detail,
                        maxLines: expanded ? null : 1,
                        overflow: expanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: failed
                              ? scheme.error
                              : scheme.onSurfaceVariant.withValues(
                                  alpha: 0.68,
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status, Color color) {
    final label = switch (status) {
      AgentPlanItem.inProgress => '进行中',
      AgentPlanItem.completed => '已完成',
      AgentPlanItem.failed => '失败',
      AgentPlanItem.skipped => '跳过',
      AgentPlanItem.needsConfirmation => '需确认',
      _ => '待开始',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }

  void _showPlanDetails(BuildContext context) {
    final plan = widget.plan;
    final scheme = Theme.of(context).colorScheme;
    final completed = _completedCount(plan);
    final failed = plan.items
        .where((item) => item.status == AgentPlanItem.failed)
        .length;
    final needsConfirmation = plan.items
        .where((item) => item.status == AgentPlanItem.needsConfirmation)
        .length;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          minChildSize: 0.35,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Text(
                  plan.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '完成 $completed/${plan.items.length} · 进行中 ${_inProgressCount(plan)} · '
                  '失败 $failed · 需确认 $needsConfirmation',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                const Divider(height: 20),
                for (var index = 0; index < plan.items.length; index++)
                  _detailStep(plan.items[index], index),
              ],
            );
          },
        );
      },
    );
  }

  Widget _detailStep(AgentPlanItem item, int index) {
    final scheme = Theme.of(context).colorScheme;
    final failed = item.status == AgentPlanItem.failed;
    final active = _isActive(item);
    final completed = _isCompleted(item);
    final color = failed
        ? scheme.error
        : active
        ? scheme.primary
        : scheme.onSurfaceVariant.withValues(alpha: completed ? 0.58 : 0.82);
    final marker = completed
        ? '✓'
        : failed
        ? '!'
        : active
        ? '•'
        : '·';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Text(
              marker,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${index + 1}. ${item.title}',
                        style: TextStyle(
                          fontSize: 14,
                          color: color,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    _statusChip(item.status, color),
                  ],
                ),
                if (item.summary != null && item.summary!.isNotEmpty)
                  _detailLine('摘要', item.summary!, scheme),
                if (item.resultSummary != null &&
                    item.resultSummary!.isNotEmpty)
                  _detailLine('结果', item.resultSummary!, scheme),
                if (item.error != null && item.error!.isNotEmpty)
                  _detailLine('错误', item.error!, scheme, error: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(
    String label,
    String value,
    ColorScheme scheme, {
    bool error = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$label：$value',
        style: TextStyle(
          fontSize: 12,
          color: error ? scheme.error : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  static int _completedCount(AgentPlan plan) => plan.items
      .where(
        (item) =>
            item.status == AgentPlanItem.completed ||
            item.status == AgentPlanItem.skipped,
      )
      .length;

  static int _inProgressCount(AgentPlan plan) => plan.items
      .where(
        (item) =>
            item.status == AgentPlanItem.inProgress ||
            item.status == AgentPlanItem.needsConfirmation,
      )
      .length;

  static AgentPlanItem? _activeItem(AgentPlan plan) {
    for (final item in plan.items) {
      if (_isActive(item)) return item;
    }
    return null;
  }

  static bool _isActive(AgentPlanItem item) =>
      item.status == AgentPlanItem.inProgress ||
      item.status == AgentPlanItem.needsConfirmation ||
      item.status == AgentPlanItem.failed;

  static bool _isCompleted(AgentPlanItem item) =>
      item.status == AgentPlanItem.completed ||
      item.status == AgentPlanItem.skipped;
}
