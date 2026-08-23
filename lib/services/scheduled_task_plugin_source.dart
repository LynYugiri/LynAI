import 'package:flutter/foundation.dart';

import '../models/plugin.dart';

/// 定时任务调度器所需的插件查询/变更通知接口。
///
/// [PluginProvider] 天然满足该接口；测试可注入轻量实现。
abstract interface class ScheduledTaskPluginSource {
  List<InstalledPlugin> get plugins;

  InstalledPlugin? pluginById(String id);

  void addListener(VoidCallback listener);

  void removeListener(VoidCallback listener);
}
