import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plugin.dart';
import '../providers/plugin_provider.dart';
import '../widgets/code_file_editor.dart';
import '../widgets/plugin_feature_webview.dart';

/// 插件文件编辑器页面。
///
/// 复用通用 [CodeFileEditorPage]，把保存回调接到 PluginProvider；若打开
/// 的是功能页入口文件，额外提供“预览页面”动作。
class PluginFileEditorPage extends StatelessWidget {
  const PluginFileEditorPage({
    super.key,
    required this.pluginId,
    required this.path,
    required this.initialContent,
    this.readOnly = false,
  });

  final String pluginId;
  final String path;
  final String initialContent;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final plugin = context.watch<PluginProvider>().pluginById(pluginId);
    if (plugin == null) {
      return const Scaffold(body: Center(child: Text('插件不存在')));
    }
    final page = _featurePageForPath(plugin, path);
    return CodeFileEditorPage(
      path: path,
      initialContent: initialContent,
      readOnly: readOnly,
      onSave: (content) => context.read<PluginProvider>().writeEditableFile(
        pluginId,
        path,
        content,
      ),
      previewPageBuilder: page == null
          ? null
          : (context) =>
                PluginPagePreviewPage(pluginId: pluginId, pageId: page.id),
    );
  }

  PluginFeaturePageDefinition? _featurePageForPath(
    InstalledPlugin plugin,
    String path,
  ) {
    final normalized = path.replaceAll('\\', '/');
    for (final page in plugin.manifest.featurePages) {
      if (page.entry.replaceAll('\\', '/') == normalized) return page;
    }
    return null;
  }
}

/// 插件功能页预览页面。
///
/// 通过 [PluginFeatureWebView] 加载插件声明的功能页入口。
class PluginPagePreviewPage extends StatelessWidget {
  const PluginPagePreviewPage({
    super.key,
    required this.pluginId,
    required this.pageId,
  });

  final String pluginId;
  final String pageId;

  @override
  Widget build(BuildContext context) {
    final plugin = context.watch<PluginProvider>().pluginById(pluginId);
    PluginFeaturePageDefinition? page;
    for (final item in plugin?.manifest.featurePages ?? const []) {
      if (item.id == pageId) {
        page = item;
        break;
      }
    }
    if (plugin == null || page == null) {
      return const Scaffold(body: Center(child: Text('插件页面不存在')));
    }
    return Scaffold(
      appBar: AppBar(title: Text('${plugin.displayName} 预览')),
      body: PluginFeatureWebView(plugin: plugin, page: page),
    );
  }
}
