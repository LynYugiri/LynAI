part of '../feature_page.dart';

/// 插件功能页引用。
///
/// 由插件 ID 与功能页 ID 组成，可序列化为 `plugin:<pluginId>:<pageId>` 键。
class _PluginFeatureRef {
  final String pluginId;
  final String pageId;

  const _PluginFeatureRef(this.pluginId, this.pageId);

  String get key =>
      '${_FeaturePageState._pluginFeaturePrefix}$pluginId:$pageId';

  static _PluginFeatureRef? tryParse(String value) {
    if (!value.startsWith(_FeaturePageState._pluginFeaturePrefix)) return null;
    final rest = value.substring(_FeaturePageState._pluginFeaturePrefix.length);
    final separator = rest.indexOf(':');
    if (separator <= 0 || separator == rest.length - 1) return null;
    final pluginId = rest.substring(0, separator);
    final pageId = rest.substring(separator + 1);
    if (pluginId.isEmpty || pageId.isEmpty) return null;
    return _PluginFeatureRef(pluginId, pageId);
  }
}

/// 解析后的插件功能页。
///
/// 关联已安装插件实例与其功能页定义，用于路由到对应页面。
class _ResolvedPluginFeature {
  final InstalledPlugin plugin;
  final PluginFeaturePageDefinition page;

  const _ResolvedPluginFeature({required this.plugin, required this.page});
}
