import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/plugin_market_entry.dart';
import 'backend_client.dart';
import 'market_service.dart';

/// 连接真实后端的 [MarketService] 实现。
///
/// 通过 [BackendClient] 发送 HTTP 请求到 Go 后端 `/market/*` 端点。
/// 需要鉴权的端点（submit、updates）会自动附加 Bearer token。
class RemoteMarketService implements MarketService {
  final BackendClient _client;

  /// 创建远端市场服务实例。
  RemoteMarketService(this._client);

  @override
  bool get isBackendConnected => true;

  @override
  Future<MarketQueryResult> listPlugins(MarketQuery query) async {
    final params = <String, String>{};
    if (query.category.isNotEmpty) params['category'] = query.category;
    if (query.query.isNotEmpty) params['q'] = query.query;
    params['page'] = query.page.toString();
    params['page_size'] = query.pageSize.toString();

    final resp = await _client.get(
      '/market/plugins?${Uri(queryParameters: params).query}',
    );
    if (resp.statusCode != 200) {
      throw MarketUnavailableException(
        BackendClient.extractErrorMessage(resp.body) ?? '获取插件列表失败',
      );
    }
    final json = jsonDecode(resp.body) as Map;
    final entries = (json['entries'] as List? ?? const [])
        .map(
          (item) => MarketPluginEntry.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
    final hasMore = json['hasMore'] as bool? ?? false;
    return MarketQueryResult(entries: entries, hasMore: hasMore);
  }

  @override
  Future<MarketPluginEntry> getPluginDetail(String id) async {
    final resp = await _client.get('/market/plugins/$id');
    if (resp.statusCode != 200) {
      throw MarketUnavailableException(
        BackendClient.extractErrorMessage(resp.body) ?? '获取插件详情失败',
      );
    }
    return MarketPluginEntry.fromJson(
      Map<String, dynamic>.from(jsonDecode(resp.body) as Map),
    );
  }

  @override
  Future<List<int>> downloadPlugin(String id) async {
    final resp = await _client.get('/market/plugins/$id/download');
    if (resp.statusCode != 200) {
      throw MarketUnavailableException(
        BackendClient.extractErrorMessage(resp.body) ?? '下载插件失败',
      );
    }
    return resp.bodyBytes;
  }

  @override
  Future<List<MarketPluginEntry>> getInstalledUpdates() async {
    // 更新检查需要传入本地已安装插件的 ID+版本列表。
    // 这个方法在页面层编排时使用——页面从 PluginProvider 读取已安装列表，
    // 构造请求体后直接调用 [checkUpdates]。
    return const [];
  }

  /// 向后端批量查询已安装插件的可用更新。
  ///
  /// 页面层从 PluginProvider 读取本地已安装插件 ID 和版本，
  /// 传入此方法后端返回有差异的条目。
  Future<List<MarketPluginEntry>> checkUpdates(
    List<({String id, String version})> installed,
  ) async {
    final body = {
      'installed': installed
          .map((item) => {'id': item.id, 'version': item.version})
          .toList(),
    };
    final resp = await _client.post('/market/updates', body: body);
    if (resp.statusCode != 200) {
      throw MarketUnavailableException(
        BackendClient.extractErrorMessage(resp.body) ?? '检查更新失败',
      );
    }
    final json = jsonDecode(resp.body) as Map;
    final updates = (json['updates'] as List? ?? const [])
        .map(
          (item) => MarketPluginEntry.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
    return updates;
  }

  /// 提交插件到市场。
  ///
  /// 接收插件 ZIP 的字节内容和元数据，通过 multipart 上传到后端。
  /// 需要登录态——[BackendClient] 会自动附加 Bearer token。
  Future<MarketPluginEntry> submitPlugin(List<int> zipBytes) async {
    final req = _client.multipartRequest('POST', '/market/plugins/submit');
    req.files.add(
      http.MultipartFile.fromBytes('zip', zipBytes, filename: 'plugin.zip'),
    );
    final streamedResp = await req.send();
    final resp = await http.Response.fromStream(streamedResp);
    if (resp.statusCode != 200) {
      throw MarketUnavailableException(
        BackendClient.extractErrorMessage(resp.body) ?? '提交插件失败',
      );
    }
    return MarketPluginEntry.fromJson(
      Map<String, dynamic>.from(jsonDecode(resp.body) as Map),
    );
  }

  /// 获取当前用户提交的插件列表。
  Future<List<MarketPluginEntry>> mySubmissions() async {
    final resp = await _client.get('/market/submissions/mine');
    if (resp.statusCode != 200) {
      throw MarketUnavailableException(
        BackendClient.extractErrorMessage(resp.body) ?? '获取提交列表失败',
      );
    }
    final json = jsonDecode(resp.body) as Map;
    final subs = (json['submissions'] as List? ?? const [])
        .map(
          (item) => MarketPluginEntry.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
    return subs;
  }

  /// 获取待审核插件列表（管理员）。
  Future<List<MarketPluginEntry>> pendingPlugins() async {
    final resp = await _client.get('/market/plugins/pending');
    if (resp.statusCode != 200) {
      throw MarketUnavailableException(
        BackendClient.extractErrorMessage(resp.body) ?? '获取待审核列表失败',
      );
    }
    final json = jsonDecode(resp.body) as Map;
    final entries = (json['entries'] as List? ?? const [])
        .map(
          (item) => MarketPluginEntry.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
    return entries;
  }

  /// 批准插件上架（管理员）。
  Future<void> approvePlugin(String id) async {
    final resp = await _client.post('/market/plugins/$id/approve');
    if (resp.statusCode != 200) {
      throw MarketUnavailableException(
        BackendClient.extractErrorMessage(resp.body) ?? '批准失败',
      );
    }
  }

  /// 驳回插件（管理员）。
  Future<void> rejectPlugin(String id, {String? reason}) async {
    final resp = await _client.post(
      '/market/plugins/$id/reject',
      body: reason != null ? {'reason': reason} : const {},
    );
    if (resp.statusCode != 200) {
      throw MarketUnavailableException(
        BackendClient.extractErrorMessage(resp.body) ?? '驳回失败',
      );
    }
  }
}
