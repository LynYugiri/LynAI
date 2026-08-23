import 'package:flutter/material.dart';

/// 设置入口的数据描述。
///
/// [searchTerms] 用于补充该入口包含的子项目关键词，使顶层搜索框可以
/// 命中嵌套在子页面里的设置项。
class SettingsEntry {
  const SettingsEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.onTap,
    this.searchTerms = const [],
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final VoidCallback onTap;
  final List<String> searchTerms;

  bool matches(String normalizedQuery) {
    if (title.toLowerCase().contains(normalizedQuery) ||
        subtitle.toLowerCase().contains(normalizedQuery)) {
      return true;
    }
    return searchTerms.any(
      (term) => term.toLowerCase().contains(normalizedQuery),
    );
  }
}

/// 统一的设置入口卡片：圆形图标、标题、副标题和右侧箭头。
class SettingsItemCard extends StatelessWidget {
  const SettingsItemCard({super.key, required this.entry});

  final SettingsEntry entry;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: entry.iconColor.withValues(alpha: 0.1),
          child: Icon(entry.icon, color: entry.iconColor),
        ),
        title: Text(
          entry.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(entry.subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: entry.onTap,
      ),
    );
  }
}

/// 通用设置子项目页。
///
/// 顶部为页面标题，下方依次展示 [entries] 对应的设置入口卡片。
class SettingsSubpage extends StatelessWidget {
  const SettingsSubpage({
    super.key,
    required this.title,
    required this.entries,
  });

  final String title;
  final List<SettingsEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [for (final entry in entries) SettingsItemCard(entry: entry)],
      ),
    );
  }
}
