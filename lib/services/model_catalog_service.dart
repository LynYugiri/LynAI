import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:path_provider/path_provider.dart';
import '../models/model_catalog.dart';
import '../models/model_config.dart';
import 'backend_client.dart';
import 'bounded_outbound_http_client.dart';
import 'outbound_network_policy.dart';
import 'storage_v2_service.dart';

/// 目录数据当前的来源。
enum ModelCatalogLoadSource {
  /// 还没有任何数据。
  none,

  /// 应用内置的精简快照。
  bundled,

  /// 本地缓存文件。
  cache,

  /// 后端 `/models/catalog` 代理。
  backend,

  /// 直连 models.dev。
  remote,
}

/// 目录服务对外暴露的状态快照。
class ModelCatalogStatus {
  /// 创建状态快照。
  const ModelCatalogStatus({
    this.source = ModelCatalogLoadSource.none,
    this.loading = false,
    this.fetchedAt,
    this.checkedAt,
    this.providerCount = 0,
    this.modelCount = 0,
    this.error,
  });

  /// 当前数据来源。
  final ModelCatalogLoadSource source;

  /// 是否正在刷新。
  final bool loading;

  /// 上游数据时间。
  final DateTime? fetchedAt;

  /// 本机最近一次尝试刷新的时间。
  final DateTime? checkedAt;

  /// provider 数量。
  final int providerCount;

  /// 模型数量。
  final int modelCount;

  /// 最近一次刷新失败的原因；成功后清空。
  final String? error;

  /// 是否已经有可用数据。
  bool get hasData => providerCount > 0;
}

/// models.dev 模型目录的加载、缓存与查询入口。
///
/// 数据来源优先级：后端 `/models/catalog` 代理 → 直连 models.dev →
/// 本地缓存文件 → 内置精简快照。任何一环失败都回退到上一份可用数据，不向
/// 调用方抛异常（失败原因放在 [status] 里）。
///
/// 缓存文件只保存裁剪后的目录（默认 provider 集合），是派生数据：不进入
/// storage_v2、备份、云同步或 LAN 同步；幂等覆写，删掉也不影响项目数据。
class ModelCatalogService extends ChangeNotifier {
  /// 创建目录服务。
  ModelCatalogService({
    BackendClient? backend,
    StorageV2Service? storageV2,
    Directory? cacheDirectory,
    AssetBundle? assetBundle,
    OutboundHttpClientFactory? clientFactory,
    OutboundNetworkPolicy? policy,
    DateTime Function()? now,
    bool enableRemote = true,
  }) : _backend = backend,
       _storageV2 = storageV2,
       _cacheDirectory = cacheDirectory,
       _assetBundle = assetBundle ?? rootBundle,
       _clientFactory = clientFactory,
       _policy = policy ?? const OutboundNetworkPolicy(),
       _now = now ?? DateTime.now,
       _enableRemote = enableRemote;

  /// 内置快照的 asset 路径。
  static const bundledAssetPath = 'assets/model_catalog/catalog.json';

  /// 缓存文件名。
  static const cacheFileName = 'model_catalog_cache.json';

  /// 缓存多久之后在后台尝试刷新。
  static const refreshTtl = Duration(days: 7);

  /// 直连 models.dev 时的响应大小上限（gzip 解压后约 4.9 MiB）。
  static const maxRemoteBytes = 8 * 1024 * 1024;

  /// 后端代理响应的大小上限。
  static const maxBackendBytes = 6 * 1024 * 1024;

  /// models.dev 的目录文档地址。
  static const remoteUrl = 'https://models.dev/api.json';

  /// 后端代理路径。
  static const backendPath = '/models/catalog';

  final BackendClient? _backend;
  final StorageV2Service? _storageV2;
  final Directory? _cacheDirectory;
  final AssetBundle _assetBundle;

  /// 直连请求的客户端工厂，测试可注入假客户端。
  final OutboundHttpClientFactory? _clientFactory;

  /// 直连请求的出站网络策略（默认 HTTPS + 公网 DNS）。
  final OutboundNetworkPolicy _policy;
  final DateTime Function() _now;
  final bool _enableRemote;

  ModelCatalogDocument? _document;
  ModelCatalogIndex? _index;
  ModelCatalogStatus _status = const ModelCatalogStatus();
  String? _etag;
  Future<void>? _loadFuture;
  Future<bool>? _refreshFuture;
  final Set<String> _extraProviderIds = {};

  /// 当前目录文档；尚未加载时为 null。
  ModelCatalogDocument? get document => _document;

  /// 目录索引；尚未加载时为 null。
  ModelCatalogIndex? get index => _index;

  /// 当前状态。
  ModelCatalogStatus get status => _status;

  /// 是否有可用数据。
  bool get hasData => _index != null;

  /// 目录里的 provider（按名称排序，供手动指定目录来源的下拉使用）。
  List<ModelCatalogProvider> get providers {
    final document = _document;
    if (document == null) return const [];
    final values = document.providers.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(values);
  }

  /// 首次使用时加载：先本地（缓存文件/内置快照），必要时后台刷新。
  ///
  /// 重复调用共享同一个 Future；不会抛异常。已有数据（含测试注入）时立即返回。
  Future<void> ensureLoaded() {
    if (_document != null) return Future<void>.value();
    return _loadFuture ??= _loadLocal();
  }

  /// 仅供测试：直接注入一份目录数据，跳过 asset/缓存/网络 IO。
  ///
  /// 组件测试的 fake-async 环境里真实文件 IO 不会完成，页面又会在 post-frame
  /// 触发加载，因此需要这个入口来搭出「目录已就绪」的状态。
  @visibleForTesting
  void debugSeedDocument(
    ModelCatalogDocument document, {
    ModelCatalogLoadSource source = ModelCatalogLoadSource.bundled,
    DateTime? checkedAt,
  }) {
    _applyDocument(
      document,
      source: source,
      checkedAt: checkedAt ?? _now(),
    );
  }

  Future<void> _loadLocal() async {
    var applied = false;
    try {
      final cached = await _readCacheFile();
      if (cached != null) {
        _applyDocument(
          cached.document,
          source: ModelCatalogLoadSource.cache,
          etag: cached.etag,
          checkedAt: cached.checkedAt,
        );
        applied = true;
      }
    } catch (error) {
      debugPrint('读取模型目录缓存失败: $error');
    }
    if (!applied) {
      try {
        final bundled = await _readBundled();
        if (bundled != null) {
          _applyDocument(
            bundled,
            source: ModelCatalogLoadSource.bundled,
            checkedAt: _now(),
          );
          applied = true;
        }
      } catch (error) {
        debugPrint('读取内置模型目录快照失败: $error');
      }
    }
    if (!applied) {
      _status = ModelCatalogStatus(error: _status.error);
      notifyListeners();
    }
    if (_enableRemote && _isStale) {
      unawaited(refresh());
    }
  }

  /// 缓存是否过期（或没有数据）。
  bool get _isStale {
    final checkedAt = _status.checkedAt;
    if (checkedAt == null) return true;
    return _now().difference(checkedAt) >= refreshTtl;
  }

  /// 显式刷新目录；返回是否拿到了可用数据。
  ///
  /// 后端代理不可用（未连接或返回 404）时自动回退到直连 models.dev。
  Future<bool> refresh() {
    return _refreshFuture ??= _refresh().whenComplete(() {
      _refreshFuture = null;
    });
  }

  Future<bool> _refresh() async {
    _setStatus(loading: true, error: null);
    String? error;
    if (_backend != null && _backend.isConnected) {
      try {
        final applied = await _refreshFromBackend();
        if (applied) {
          _setStatus(loading: false, error: null);
          return true;
        }
      } catch (e) {
        error = '$e';
      }
    }
    try {
      await _refreshFromRemote();
      _setStatus(loading: false, error: null);
      return true;
    } catch (e) {
      error ??= '$e';
      _setStatus(loading: false, error: error);
      return hasData;
    }
  }

  /// 返回 true 表示后端代理已处理（含 304）；false 表示后端不支持该接口。
  Future<bool> _refreshFromBackend() async {
    final backend = _backend;
    if (backend == null) return false;
    final response = await backend.getBounded(
      backendPath,
      maxBytes: maxBackendBytes,
      headers: {
        'Accept': 'application/json',
        'If-None-Match': ?_etag,
      },
    );
    if (response.statusCode == 304) {
      _setStatus(checkedAt: _now());
      await _writeCacheFile();
      return true;
    }
    if (response.statusCode == 404 || response.statusCode == 405) return false;
    if (response.statusCode != 200) {
      throw Exception('后端模型目录返回 ${response.statusCode}');
    }
    final document = ModelCatalogDocument.tryParseDocument(
      jsonDecode(utf8.decode(response.bodyBytes)),
    );
    if (document == null) throw Exception('后端模型目录结构无法识别');
    _applyDocument(
      document,
      source: ModelCatalogLoadSource.backend,
      etag: response.headers['etag'],
      checkedAt: _now(),
    );
    await _writeCacheFile();
    return true;
  }

  Future<void> _refreshFromRemote() async {
    final client = BoundedOutboundHttpClient(
      policy: _policy,
      clientFactory: _clientFactory,
    );
    final response = await client.send(
      method: 'GET',
      uri: Uri.parse(remoteUrl),
      headers: {
        'Accept': 'application/json',
        'If-None-Match': ?_etag,
      },
      maxResponseBytes: maxRemoteBytes,
      timeout: const Duration(seconds: 30),
    );
    if (response.statusCode == 304) {
      _setStatus(checkedAt: _now());
      await _writeCacheFile();
      return;
    }
    if (response.statusCode != 200) {
      throw Exception('models.dev 返回 ${response.statusCode}');
    }
    final document = ModelCatalogDocument.tryParseModelsDevApi(
      jsonDecode(utf8.decode(response.bodyBytes)),
      providerFilter: _wantedProviderIds,
      fetchedAt: _now(),
    );
    if (document == null) throw Exception('models.dev 目录结构无法识别');
    _applyDocument(
      document,
      source: ModelCatalogLoadSource.remote,
      etag: response.headers['etag'],
      checkedAt: _now(),
    );
    await _writeCacheFile();
  }

  Set<String> get _wantedProviderIds => {
    ...defaultModelCatalogProviderIds,
    ..._extraProviderIds,
  };

  /// 让后续刷新把 [providerId] 也纳入缓存（手动指定目录来源时使用）。
  void requestProvider(String providerId) {
    final id = providerId.trim();
    if (id.isEmpty || defaultModelCatalogProviderIds.contains(id)) return;
    if (!_extraProviderIds.add(id)) return;
    _etag = null;
  }

  /// 清除本地缓存文件，并回退到内置快照。
  ///
  /// 内置快照随包分发，因此清除缓存后仍可离线补全；下次刷新会重新下载。
  Future<void> clearCache() async {
    try {
      final file = await _cacheFile();
      if (file != null && await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('清除模型目录缓存失败: $error');
    }
    _etag = null;
    _extraProviderIds.clear();
    try {
      final bundled = await _readBundled();
      if (bundled != null) {
        _applyDocument(
          bundled,
          source: ModelCatalogLoadSource.bundled,
          checkedAt: null,
        );
      }
    } catch (error) {
      debugPrint('回退内置模型目录快照失败: $error');
    }
    _status = ModelCatalogStatus(
      source: _status.source,
      fetchedAt: _status.fetchedAt,
      providerCount: _status.providerCount,
      modelCount: _status.modelCount,
      error: null,
    );
    notifyListeners();
  }

  /// 按配置与模型名查询目录记录。
  ///
  /// provider 无法判断或模型名无法唯一匹配时返回 null：宁可不填，也不猜。
  ModelCatalogModel? lookup({
    required String endpoint,
    String? explicitProviderId,
    required String modelName,
  }) {
    final index = _index;
    if (index == null) return null;
    final providerId = const ModelCatalogProviderResolver().resolve(
      explicitProviderId: explicitProviderId,
      endpoint: endpoint,
      document: _document,
    );
    if (providerId == null) return null;
    return index.lookup(providerId: providerId, modelName: modelName);
  }

  /// 查询某个配置下 [modelName] 的目录提示（可写入 `ModelEntry.catalog`）。
  ModelCatalogHint? hintFor(ModelConfig config, String modelName) {
    return hintForEndpoint(
      endpoint: config.endpoint,
      explicitProviderId: config.catalogProviderId,
      modelName: modelName,
    );
  }

  /// 按 endpoint（可选手动 provider）查询 [modelName] 的目录提示。
  ///
  /// 用于模型配置尚未保存时（编辑器里的临时条目）也能拿到建议。
  ModelCatalogHint? hintForEndpoint({
    required String endpoint,
    String? explicitProviderId,
    required String modelName,
  }) {
    final index = _index;
    if (index == null) return null;
    final providerId = const ModelCatalogProviderResolver().resolve(
      explicitProviderId: explicitProviderId,
      endpoint: endpoint,
      document: _document,
    );
    if (providerId == null) return null;
    final match = index.match(providerId: providerId, modelName: modelName);
    if (match == null) return null;
    return ModelCatalogHint.fromModel(
      match.model,
      providerId: providerId,
      exact: match.exact,
      fetchedAt: _status.fetchedAt,
    );
  }

  /// [modelName] 的候选目录记录，用于在 UI 里让用户手动选择。
  List<ModelCatalogModel> candidates({
    required String endpoint,
    String? explicitProviderId,
    required String modelName,
    int limit = 5,
  }) {
    final index = _index;
    if (index == null) return const [];
    final providerId = const ModelCatalogProviderResolver().resolve(
      explicitProviderId: explicitProviderId,
      endpoint: endpoint,
      document: _document,
    );
    if (providerId == null) return const [];
    return index.candidates(
      providerId: providerId,
      modelName: modelName,
      limit: limit,
    );
  }

  void _applyDocument(
    ModelCatalogDocument document, {
    required ModelCatalogLoadSource source,
    String? etag,
    DateTime? checkedAt,
  }) {
    _document = document;
    _index = ModelCatalogIndex(document);
    _etag = etag ?? _etag;
    _status = ModelCatalogStatus(
      source: source,
      loading: _status.loading,
      fetchedAt: document.fetchedAt ?? _status.fetchedAt,
      checkedAt: checkedAt ?? _status.checkedAt,
      providerCount: document.providers.length,
      modelCount: document.providers.values.fold(
        0,
        (total, provider) => total + provider.models.length,
      ),
      error: null,
    );
    notifyListeners();
  }

  void _setStatus({
    bool? loading,
    DateTime? checkedAt,
    String? error,
  }) {
    _status = ModelCatalogStatus(
      source: _status.source,
      loading: loading ?? _status.loading,
      fetchedAt: _status.fetchedAt,
      checkedAt: checkedAt ?? _status.checkedAt,
      providerCount: _status.providerCount,
      modelCount: _status.modelCount,
      error: error ?? _status.error,
    );
    notifyListeners();
  }

  Future<ModelCatalogDocument?> _readBundled() async {
    final raw = await _assetBundle.loadString(bundledAssetPath);
    if (raw.trim().isEmpty) return null;
    return ModelCatalogDocument.tryParseDocument(jsonDecode(raw));
  }

  Future<_CachedCatalog?> _readCacheFile() async {
    final file = await _cacheFile();
    if (file == null || !await file.exists()) return null;
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    final document = ModelCatalogDocument.tryParseDocument(decoded);
    if (document == null) return null;
    String? etag;
    DateTime? checkedAt;
    if (decoded is Map) {
      final rawEtag = decoded['etag']?.toString().trim() ?? '';
      etag = rawEtag.isEmpty ? null : rawEtag;
      checkedAt = DateTime.tryParse(decoded['checkedAt']?.toString() ?? '');
    }
    return _CachedCatalog(
      document: document,
      etag: etag,
      checkedAt: checkedAt,
    );
  }

  Future<void> _writeCacheFile() async {
    final document = _document;
    if (document == null) return;
    try {
      final file = await _cacheFile();
      if (file == null) return;
      final parent = file.parent;
      if (!await parent.exists()) await parent.create(recursive: true);
      final payload = <String, dynamic>{
        ...document.toJson(),
        if (_etag != null) 'etag': _etag,
        'checkedAt': (_status.checkedAt ?? _now()).toUtc().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (error) {
      debugPrint('写入模型目录缓存失败: $error');
    }
  }

  Future<File?> _cacheFile() async {
    final directory = await _resolveCacheDirectory();
    if (directory == null) return null;
    return File('${directory.path}${Platform.pathSeparator}$cacheFileName');
  }

  Future<Directory?> _resolveCacheDirectory() async {
    final override = _cacheDirectory;
    if (override != null) return override;
    final storage = _storageV2;
    if (storage != null) {
      final root = await storage.storageRoot();
      return Directory('${root.parent.path}${Platform.pathSeparator}model_catalog');
    }
    try {
      final support = await getApplicationSupportDirectory();
      return Directory(
        '${support.path}${Platform.pathSeparator}model_catalog',
      );
    } catch (error) {
      debugPrint('无法解析模型目录缓存位置: $error');
      return null;
    }
  }
}

class _CachedCatalog {
  const _CachedCatalog({
    required this.document,
    this.etag,
    this.checkedAt,
  });

  final ModelCatalogDocument document;
  final String? etag;
  final DateTime? checkedAt;
}
