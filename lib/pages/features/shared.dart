part of '../feature_page.dart';

class _FeatureEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: scheme.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteDiffStats {
  final int addedChars;
  final int removedChars;
  final int addedLines;
  final int removedLines;

  const _NoteDiffStats({
    required this.addedChars,
    required this.removedChars,
    required this.addedLines,
    required this.removedLines,
  });

  bool get hasChanges => addedChars > 0 || removedChars > 0;
}

enum _DiffLineType { context, added, removed }

class _DiffLine {
  final _DiffLineType type;
  final int? beforeLine;
  final int? afterLine;
  final String text;

  const _DiffLine({
    required this.type,
    required this.beforeLine,
    required this.afterLine,
    required this.text,
  });
}
