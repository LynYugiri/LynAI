import '../models/plugin_market_entry.dart';
import 'market_service.dart';

/// 未连接后端时的本地桩实现。
///
/// 所有远端调用抛出 [MarketUnavailableException]，让页面渲染空态文案并
/// 提供「从 ZIP 导入」入口，避免误导用户把本地已安装插件当作市场内容。
/// 后端就绪后由 [RemoteMarketService] 替换。
class LocalMarketService implements MarketService {
  /// 创建本地桩服务实例。
  const LocalMarketService();

  @override
  bool get isBackendConnected => false;

  @override
  Future<MarketQueryResult> listPlugins(MarketQuery query) async {
    throw const MarketUnavailableException('尚未连接 LynAI 后端');
  }

  @override
  Future<MarketPluginEntry> getPluginDetail(String id) async {
    throw const MarketUnavailableException('尚未连接 LynAI 后端');
  }

  @override
  Future<List<int>> downloadPlugin(String id) async {
    throw const MarketUnavailableException('尚未连接 LynAI 后端');
  }

  @override
  Future<List<MarketPluginEntry>> getInstalledUpdates() async => const [];
}
