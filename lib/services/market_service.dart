import '../models/plugin_market_entry.dart';

/// 插件市场服务抽象。
///
/// 定义插件市场的浏览、详情、下载和更新查询能力，不绑定具体后端实现。
/// 前端页面只依赖这个抽象，后端就绪后用 [RemoteMarketService] 替换
/// [LocalMarketService]，无需改动页面代码。
abstract class MarketService {
  /// 按条件列出市场插件。
  Future<MarketQueryResult> listPlugins(MarketQuery query);

  /// 获取指定插件的详情。
  Future<MarketPluginEntry> getPluginDetail(String id);

  /// 下载指定插件的 ZIP 字节内容。
  ///
  /// 调用方负责把字节交给 [PluginProvider.importZipBytes] 完成安装。
  Future<List<int>> downloadPlugin(String id);

  /// 查询当前已安装插件中可更新的条目。
  ///
  /// 默认实现返回空结果；后端实现需要读取本地已安装版本与市场最新版本对比。
  Future<List<MarketPluginEntry>> getInstalledUpdates();

  /// 当前服务是否已连接到真实后端。
  ///
  /// [LocalMarketService] 返回 false，[RemoteMarketService] 返回 true。
  /// 页面据此决定显示空态文案还是真实数据。
  bool get isBackendConnected;
}
