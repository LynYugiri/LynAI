import 'package:flutter/material.dart';

import '../../models/jotting.dart';
import '../../widgets/latex_renderer.dart';

/// Read-only detail view for a local jotting.
///
/// Editing is opened as a dedicated full-screen route by the parent timeline,
/// keeping the timeline mounted and preserving its scroll position.
class JottingDetail extends StatelessWidget {
  const JottingDetail({super.key, required this.jotting, required this.onEdit});

  final Jotting jotting;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('随记'),
        actions: [
          IconButton(
            tooltip: '编辑随记',
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '创建于 ${_formatTime(jotting.createdAt)} · '
                '更新于 ${_formatTime(jotting.updatedAt)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (jotting.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in jotting.tags)
                      Chip(
                        label: Text('#$tag'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
              const Divider(height: 28),
              MarkdownWithLatex(content: jotting.content),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }
}
