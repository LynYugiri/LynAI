import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/community.dart';
import '../models/plugin_market_entry.dart';
import '../services/backend_client.dart';
import '../services/remote_market_service.dart';
import '../utils/snackbar_utils.dart';
import 'plugin_market_detail_page.dart';

/// 把社区帖子携带的插件快照转换为市场详情页需要的条目。
///
/// 社区快照只负责展示和跳转；安装仍由 [PluginMarketDetailPage] 通过
/// [RemoteMarketService] 按插件 id 重新下载最新 ZIP。
MarketPluginEntry communityPluginToMarketEntry(CommunityPluginShare plugin) {
  return MarketPluginEntry(
    id: plugin.id,
    name: plugin.name,
    author: plugin.author,
    uploaderName: plugin.uploaderName,
    description: plugin.description,
    version: plugin.version,
    iconUrl: plugin.iconUrl,
    screenshots: plugin.screenshots,
    permissions: plugin.permissions,
    downloadUrl: plugin.downloadUrl,
    sha256: plugin.sha256,
    category: plugin.category,
    status: plugin.status,
  );
}

/// 把市场目录条目转换为编辑器可预览、提交时仅使用 id 的社区插件快照。
CommunityPluginShare marketEntryToCommunityPluginShare(
  MarketPluginEntry entry,
) {
  return CommunityPluginShare(
    id: entry.id,
    name: entry.name,
    author: entry.author,
    uploaderName: entry.uploaderName,
    description: entry.description,
    version: entry.version,
    iconUrl: entry.iconUrl,
    screenshots: entry.screenshots,
    permissions: entry.permissions,
    downloadUrl: entry.downloadUrl,
    sha256: entry.sha256,
    category: entry.category,
    status: entry.status,
  );
}

/// 打开社区帖子中分享插件对应的插件市场详情页。
void openCommunitySharedPlugin(
  BuildContext context,
  CommunityPluginShare plugin,
) {
  final backend = context.read<BackendClient>();
  if (!backend.isConnected) {
    showErrorSnackBar(context, '尚未连接后端，无法打开插件页面');
    return;
  }
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PluginMarketDetailPage(
        entry: communityPluginToMarketEntry(plugin),
        marketService: RemoteMarketService(backend),
      ),
    ),
  );
}
