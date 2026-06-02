part of '../feature_page.dart';

class _FeatureDashboard extends StatelessWidget {
  final ValueChanged<String> onFeatureSelected;

  const _FeatureDashboard({required this.onFeatureSelected});

  static const _items = [
    _FeatureDashboardItem(
      value: 'history',
      icon: Icons.history,
      title: '对话历史',
      subtitle: '按角色查看与搜索',
    ),
    _FeatureDashboardItem(
      value: 'schedule',
      icon: Icons.calendar_month,
      title: '日程表',
      subtitle: '月历、日视图与年览',
    ),
    _FeatureDashboardItem(
      value: 'notes',
      icon: Icons.sticky_note_2_outlined,
      title: '笔记',
      subtitle: 'Markdown/LaTeX 记录',
    ),
    _FeatureDashboardItem(
      value: 'todos',
      icon: Icons.checklist,
      title: '待办清单',
      subtitle: '任务勾选与导入导出',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _crossAxisCount(constraints.maxWidth);
        final horizontalPadding = constraints.maxWidth >= 900 ? 24.0 : 12.0;
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            12,
            horizontalPadding,
            24,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final item = _items[index];
            return _FeatureDashboardCard(
              item: item,
              onTap: () => onFeatureSelected(item.value),
            );
          },
        );
      },
    );
  }

  int _crossAxisCount(double width) {
    if (width < 600) return 3;
    if (width < 900) return 4;
    if (width < 1280) return 5;
    return 6;
  }
}

class _FeatureDashboardItem {
  final String value;
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureDashboardItem({
    required this.value,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

class _FeatureDashboardCard extends StatelessWidget {
  final _FeatureDashboardItem item;
  final VoidCallback onTap;

  const _FeatureDashboardCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 128;
            final iconBoxSize = compact ? 40.0 : 46.0;
            final iconSize = compact ? 24.0 : 26.0;
            return Padding(
              padding: EdgeInsets.all(compact ? 8 : 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: iconBoxSize,
                    height: iconBoxSize,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Icon(
                      item.icon,
                      color: scheme.primary,
                      size: iconSize,
                    ),
                  ),
                  SizedBox(height: compact ? 8 : 10),
                  Text(
                    item.title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
