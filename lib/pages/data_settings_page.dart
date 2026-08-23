import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/recycle_bin_provider.dart';
import '../widgets/settings_entry.dart';
import 'data_management_page.dart';
import 'lan_sync_page.dart';
import 'recycle_bin_page.dart';

/// 数据设置页。
///
/// 收纳数据管理、回收站与局域网配对同步三个入口。
class DataSettingsPage extends StatelessWidget {
  const DataSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final recycleBin = context.watch<RecycleBinProvider>();
    return SettingsSubpage(
      title: '数据',
      entries: [
        SettingsEntry(
          icon: Icons.import_export,
          title: '数据管理',
          subtitle: '导入、导出与备份恢复',
          iconColor: Colors.teal,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DataManagementPage()),
          ),
        ),
        SettingsEntry(
          icon: Icons.delete_sweep_outlined,
          title: '回收站',
          subtitle: '${recycleBin.items.length} 个项目',
          iconColor: Colors.red,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RecycleBinPage()),
          ),
        ),
        SettingsEntry(
          icon: Icons.phonelink_lock_outlined,
          title: '局域网配对与同步',
          subtitle: '发现设备、扫码配对、同步、冲突与撤销',
          iconColor: Colors.blue,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LanSyncPage()),
          ),
        ),
      ],
    );
  }
}
