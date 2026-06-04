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
    _FeatureDashboardItem(
      value: 'roleplay',
      icon: Icons.theater_comedy_outlined,
      title: '情景演绎',
      subtitle: '设定场景，多角色共演',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final pluginItems = _pluginItems(context.watch<PluginProvider>());
    final items = [..._items, ...pluginItems];
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
            childAspectRatio: _childAspectRatio(constraints.maxWidth),
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return _FeatureDashboardCard(
              item: item,
              onTap: () => onFeatureSelected(item.value),
            );
          },
        );
      },
    );
  }

  List<_FeatureDashboardItem> _pluginItems(PluginProvider provider) {
    final items = <_FeatureDashboardItem>[];
    for (final plugin in provider.plugins) {
      if (!plugin.enabled || plugin.hasError) continue;
      for (final page in plugin.manifest.featurePages) {
        if (!plugin.enabledFeaturePages.contains(page.id)) continue;
        if (page.entry.trim().isEmpty) continue;
        items.add(
          _FeatureDashboardItem.plugin(
            value: _PluginFeatureRef(plugin.id, page.id).key,
            title: page.title.isEmpty ? plugin.manifest.name : page.title,
            subtitle: plugin.manifest.name,
            pluginPath: plugin.path,
            iconPath: page.icon,
            fallbackIconPath: plugin.manifest.icon,
          ),
        );
      }
    }
    return items;
  }

  int _crossAxisCount(double width) {
    if (width < 600) return 2;
    if (width < 900) return 4;
    if (width < 1280) return 5;
    return 6;
  }

  double _childAspectRatio(double width) {
    if (width < 600) return 1.18;
    if (width < 900) return 1.05;
    return 1.0;
  }
}

class _FeatureDashboardItem {
  final String value;
  final IconData icon;
  final String? pluginPath;
  final String? iconPath;
  final String? fallbackIconPath;
  final String title;
  final String subtitle;

  const _FeatureDashboardItem({
    required this.value,
    required this.icon,
    required this.title,
    required this.subtitle,
  }) : pluginPath = null,
       iconPath = null,
       fallbackIconPath = null;

  const _FeatureDashboardItem.plugin({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.pluginPath,
    required this.iconPath,
    required this.fallbackIconPath,
  }) : icon = Icons.extension;
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
            final compact = constraints.maxWidth < 120;
            final iconBoxSize = compact ? 42.0 : 50.0;
            final iconSize = compact ? 24.0 : 28.0;
            return Padding(
              padding: EdgeInsets.all(compact ? 10 : 12),
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
                    child: item.pluginPath == null
                        ? Icon(item.icon, color: scheme.primary, size: iconSize)
                        : PluginIcon(
                            pluginPath: item.pluginPath!,
                            iconPath: item.iconPath,
                            fallbackIconPath: item.fallbackIconPath,
                            size: iconSize,
                            color: scheme.primary,
                          ),
                  ),
                  SizedBox(height: compact ? 9 : 12),
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
