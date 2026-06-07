import 'package:flutter/material.dart';
import '../models/changelog_entry.dart';
import 'latex_renderer.dart';

enum ChangelogDialogAction { dismiss, viewAll }

Future<ChangelogDialogAction> showChangelogDialog(
  BuildContext context,
  ChangelogEntry entry,
) async {
  return await showDialog<ChangelogDialogAction>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ChangelogDialog(entry: entry),
      ) ??
      ChangelogDialogAction.dismiss;
}

class _ChangelogDialog extends StatelessWidget {
  const _ChangelogDialog({required this.entry});

  final ChangelogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.auto_awesome, color: colorScheme.primary),
          ),
          const SizedBox(height: 12),
          Text(
            '更新日志',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'v${entry.version}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              if (entry.date.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  entry.date,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(height: 24),
                for (final section in entry.sections) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        section.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  for (final item in section.items)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 4,
                        top: 2,
                        bottom: 2,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.circle,
                              size: 6,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: MarkdownWithLatex(
                              content: item,
                              selectable: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () =>
              Navigator.of(context).pop(ChangelogDialogAction.viewAll),
          child: const Text('查看全部'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(ChangelogDialogAction.dismiss),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}
