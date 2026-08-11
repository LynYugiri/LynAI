import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/web_search.dart';
import 'agent_cancellation.dart';
import 'backend_client.dart';
import 'bounded_outbound_http_client.dart';
import 'outbound_network_policy.dart';
import 'secret_store.dart';
import 'server_capabilities_service.dart';
import '../providers/settings_provider.dart';

class WebSearchException implements Exception {
  const WebSearchException(this.message, {this.canFallback = true});

  final String message;
  final bool canFallback;

  @override
  String toString() => 'WebSearchException: $message';
}

abstract interface class WebSearchAdapter {
  String get id;

  WebSearchClientProvider? get clientProvider;

  Future<bool> isConfigured();

  Future<List<WebSearchResult>> search(
    WebSearchRequest request, {
    AgentCancellationToken? cancellationToken,
  });
}

class TavilyWebSearchAdapter implements WebSearchAdapter {
  TavilyWebSearchAdapter({
    required SecretStore secretStore,
    required BoundedOutboundHttpClient httpClient,
  }) : _secretStore = secretStore,
       _httpClient = httpClient;

  static const apiKeySecretKey = 'web_search.tavily.api_key';
  static final Uri _endpoint = Uri.parse('https://api.tavily.com/search');

  final SecretStore _secretStore;
  final BoundedOutboundHttpClient _httpClient;

  @override
  String get id => 'tavily';

  @override
  WebSearchClientProvider get clientProvider => WebSearchClientProvider.tavily;

  @override
  Future<bool> isConfigured() async =>
      (await _secretStore.read(apiKeySecretKey))?.trim().isNotEmpty == true;

  @override
  Future<List<WebSearchResult>> search(
    WebSearchRequest request, {
    AgentCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final apiKey = (await _secretStore.read(apiKeySecretKey))?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw const WebSearchException('Tavily is not configured');
    }
    final response = await _httpClient.send(
      method: 'POST',
      uri: _endpoint,
      headers: const {'Content-Type': 'application/json'},
      bodyBytes: utf8.encode(
        jsonEncode({
          'api_key': apiKey,
          'query': request.query,
          'max_results': request.maxResults,
          if (request.timeRange != null) 'time_range': request.timeRange,
          'include_answer': false,
          'include_raw_content': false,
        }),
      ),
      maxRedirects: 0,
      cancellation: cancellationToken?.whenCancelled.then((_) {}),
    );
    return _decodeProviderResponse(response, request.maxResults, id);
  }
}

class SearxngWebSearchAdapter implements WebSearchAdapter {
  SearxngWebSearchAdapter({
    required Uri endpoint,
    required SecretStore secretStore,
    required BoundedOutboundHttpClient httpClient,
    this.allowPlaintextHttp = false,
  }) : _endpoint = endpoint,
       _secretStore = secretStore,
       _httpClient = httpClient {
    if (endpoint.userInfo.isNotEmpty ||
        endpoint.host.isEmpty ||
        (endpoint.scheme != 'http' && endpoint.scheme != 'https')) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'must be an HTTP(S) URL without credentials',
      );
    }
    if (endpoint.scheme == 'http' && !allowPlaintextHttp) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'plain HTTP requires explicit opt-in',
      );
    }
  }

  static const bearerTokenSecretKey = 'web_search.searxng.bearer_token';

  final Uri _endpoint;
  final SecretStore _secretStore;
  final BoundedOutboundHttpClient _httpClient;
  final bool allowPlaintextHttp;

  @override
  String get id => 'searxng';

  @override
  WebSearchClientProvider get clientProvider => WebSearchClientProvider.searxng;

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<List<WebSearchResult>> search(
    WebSearchRequest request, {
    AgentCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final token = (await _secretStore.read(bearerTokenSecretKey))?.trim();
    final query = Map<String, String>.from(_endpoint.queryParameters)
      ..['q'] = request.query
      ..['format'] = 'json'
      ..['pageno'] = '1';
    if (request.language != null) query['language'] = request.language!;
    if (request.timeRange != null) query['time_range'] = request.timeRange!;
    final response = await _httpClient.send(
      method: 'GET',
      uri: _endpoint.replace(queryParameters: query),
      headers: {
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      cancellation: cancellationToken?.whenCancelled.then((_) {}),
    );
    return _decodeProviderResponse(response, request.maxResults, id);
  }
}

class LynaiBackendWebSearchAdapter implements WebSearchAdapter {
  LynaiBackendWebSearchAdapter({
    required BackendClient backend,
    Future<bool> Function()? configuredProbe,
  }) : _backend = backend,
       _configuredProbe = configuredProbe;

  static const path = '/search/web';

  final BackendClient _backend;
  final Future<bool> Function()? _configuredProbe;

  @override
  String get id => 'lynai_backend';

  @override
  WebSearchClientProvider? get clientProvider => null;

  @override
  Future<bool> isConfigured() async =>
      _backend.isConnected &&
      (_backend.accessToken ?? '').isNotEmpty &&
      (await _configuredProbe?.call() ?? true);

  @override
  Future<List<WebSearchResult>> search(
    WebSearchRequest request, {
    AgentCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final body = utf8.encode(
      jsonEncode({
        'query': request.query,
        'maxResults': request.maxResults,
        if (request.language != null) 'language': request.language,
        if (request.timeRange != null) 'timeRange': request.timeRange,
      }),
    );
    final operation = _backend.sendAuthenticatedStreamed(
      () => http.Request('POST', Uri.parse('${_backend.backendUrl}$path'))
        ..headers['Content-Type'] = 'application/json'
        ..bodyBytes = body,
      maxResponseBytes: _maxResponseBytes,
    );
    final response = cancellationToken == null
        ? await operation
        : await Future.any([
            operation,
            cancellationToken.whenCancelled.then<Never>(
              (reason) => throw AgentCancellationException(reason),
            ),
          ]);
    final responseBytes = await _readBackendResponse(
      response,
      cancellationToken,
    );
    return _decodeJsonResponse(
      response.statusCode,
      responseBytes,
      request.maxResults,
      id,
    );
  }

  static const _maxResponseBytes = 2 * 1024 * 1024;

  static Future<List<int>> _readBackendResponse(
    http.StreamedResponse response,
    AgentCancellationToken? cancellationToken,
  ) async {
    Future<List<int>> read() async {
      final contentLength = response.contentLength;
      if (contentLength != null && contentLength > _maxResponseBytes) {
        throw const WebSearchException('Backend search response is too large');
      }
      final bytes = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response.stream) {
        total += chunk.length;
        if (total > _maxResponseBytes) {
          throw const WebSearchException(
            'Backend search response is too large',
          );
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    }

    if (cancellationToken == null) return read();
    return Future.any([
      read(),
      cancellationToken.whenCancelled.then<Never>(
        (reason) => throw AgentCancellationException(reason),
      ),
    ]);
  }
}

class WebSearchService {
  WebSearchService({
    List<WebSearchAdapter> clientAdapters = const [],
    WebSearchAdapter? backendAdapter,
  }) : _clientAdapters = List.unmodifiable(clientAdapters),
       _backendAdapter = backendAdapter;

  final List<WebSearchAdapter> _clientAdapters;
  final WebSearchAdapter? _backendAdapter;

  /// 是否存在至少一个可用的搜索适配器（未配置返回 false）。
  Future<bool> isConfigured({
    WebSearchRoute route = WebSearchRoute.auto,
    WebSearchClientProvider? preferredClientProvider,
  }) async {
    final candidates = switch (route) {
      WebSearchRoute.client => _orderedClients(preferredClientProvider),
      WebSearchRoute.backend => [?_backendAdapter],
      WebSearchRoute.auto => [
        ..._orderedClients(preferredClientProvider),
        ?_backendAdapter,
      ],
    };
    for (final adapter in candidates) {
      if (await adapter.isConfigured()) return true;
    }
    return false;
  }

  factory WebSearchService.production({
    required SettingsProvider settings,
    required SecretStore secretStore,
    required BackendClient backend,
    required ServerCapabilitiesService serverCapabilities,
    BoundedOutboundHttpClient? httpClient,
  }) {
    return _PolicyWebSearchService(
      settings: settings,
      secretStore: secretStore,
      backend: backend,
      serverCapabilities: serverCapabilities,
      httpClient: httpClient,
    );
  }

  Future<WebSearchResponse> search(
    WebSearchRequest request, {
    WebSearchRoute route = WebSearchRoute.auto,
    WebSearchClientProvider? preferredClientProvider,
    AgentCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final candidates = switch (route) {
      WebSearchRoute.client => _orderedClients(preferredClientProvider),
      WebSearchRoute.backend => [?_backendAdapter],
      WebSearchRoute.auto => [
        ..._orderedClients(preferredClientProvider),
        ?_backendAdapter,
      ],
    };
    WebSearchException? lastError;
    for (final adapter in candidates) {
      cancellationToken?.throwIfCancellationRequested();
      if (!await adapter.isConfigured()) continue;
      try {
        final results = await adapter.search(
          request,
          cancellationToken: cancellationToken,
        );
        return WebSearchResponse(
          query: request.query,
          provider: adapter.id,
          route: adapter.clientProvider == null
              ? WebSearchRoute.backend
              : WebSearchRoute.client,
          results: _normalizeResults(results, request.maxResults),
        );
      } on WebSearchException catch (error) {
        lastError = error;
        if (!error.canFallback) rethrow;
      } on OutboundRequestCancelledException {
        cancellationToken?.throwIfCancellationRequested();
        rethrow;
      } on AgentCancellationException {
        rethrow;
      } catch (_) {
        lastError = WebSearchException('${adapter.id} search failed');
      }
    }
    throw lastError ??
        const WebSearchException('No web search provider is configured');
  }

  List<WebSearchAdapter> _orderedClients(WebSearchClientProvider? preferred) {
    if (preferred == null) return _clientAdapters;
    return [
      ..._clientAdapters.where(
        (adapter) => adapter.clientProvider == preferred,
      ),
      ..._clientAdapters.where(
        (adapter) => adapter.clientProvider != preferred,
      ),
    ];
  }
}

class _PolicyWebSearchService extends WebSearchService {
  _PolicyWebSearchService({
    required this.settings,
    required this.secretStore,
    required this.backend,
    required this.serverCapabilities,
    this.httpClient,
  });

  final SettingsProvider settings;
  final SecretStore secretStore;
  final BackendClient backend;
  final ServerCapabilitiesService serverCapabilities;
  final BoundedOutboundHttpClient? httpClient;

  @override
  Future<bool> isConfigured({
    WebSearchRoute route = WebSearchRoute.auto,
    WebSearchClientProvider? preferredClientProvider,
  }) {
    final policy = settings.settings;
    final endpoint = Uri.tryParse(policy.searxngEndpoint ?? '');
    final defaultClient = httpClient ?? BoundedOutboundHttpClient();
    final clients = <WebSearchAdapter>[
      TavilyWebSearchAdapter(
        secretStore: secretStore,
        httpClient: defaultClient,
      ),
      if (endpoint != null && endpoint.host.isNotEmpty)
        SearxngWebSearchAdapter(
          endpoint: endpoint,
          secretStore: secretStore,
          httpClient:
              httpClient ??
              BoundedOutboundHttpClient(
                policy: OutboundNetworkPolicy(
                  allowedHttpOrigins:
                      endpoint.scheme == 'http' && policy.searxngAllowHttp
                      ? {outboundOrigin(endpoint)}
                      : const {},
                ),
              ),
          allowPlaintextHttp:
              endpoint.scheme == 'http' && policy.searxngAllowHttp,
        ),
    ];
    return WebSearchService(
      clientAdapters: clients,
      backendAdapter: LynaiBackendWebSearchAdapter(
        backend: backend,
        configuredProbe: () async => serverCapabilities.webSearchConfigured,
      ),
    ).isConfigured(
      route: policy.webSearchRoute,
      preferredClientProvider: policy.webSearchClientProvider,
    );
  }

  @override
  Future<WebSearchResponse> search(
    WebSearchRequest request, {
    WebSearchRoute route = WebSearchRoute.auto,
    WebSearchClientProvider? preferredClientProvider,
    AgentCancellationToken? cancellationToken,
  }) {
    final policy = settings.settings;
    final endpoint = Uri.tryParse(policy.searxngEndpoint ?? '');
    final defaultClient = httpClient ?? BoundedOutboundHttpClient();
    final searxngClient =
        httpClient ??
        BoundedOutboundHttpClient(
          policy: OutboundNetworkPolicy(
            allowedHttpOrigins:
                endpoint?.scheme == 'http' && policy.searxngAllowHttp
                ? {outboundOrigin(endpoint!)}
                : const {},
          ),
        );
    final clients = <WebSearchAdapter>[
      TavilyWebSearchAdapter(
        secretStore: secretStore,
        httpClient: defaultClient,
      ),
      if (endpoint != null && endpoint.host.isNotEmpty)
        SearxngWebSearchAdapter(
          endpoint: endpoint,
          secretStore: secretStore,
          httpClient: searxngClient,
          allowPlaintextHttp:
              endpoint.scheme == 'http' && policy.searxngAllowHttp,
        ),
    ];
    return WebSearchService(
      clientAdapters: clients,
      backendAdapter: LynaiBackendWebSearchAdapter(
        backend: backend,
        configuredProbe: () async => serverCapabilities.webSearchConfigured,
      ),
    ).search(
      request,
      route: policy.webSearchRoute,
      preferredClientProvider: policy.webSearchClientProvider,
      cancellationToken: cancellationToken,
    );
  }
}

List<WebSearchResult> _decodeProviderResponse(
  BoundedOutboundResponse response,
  int maxResults,
  String provider,
) => _decodeJsonResponse(
  response.statusCode,
  response.bodyBytes,
  maxResults,
  provider,
);

List<WebSearchResult> _decodeJsonResponse(
  int statusCode,
  List<int> bodyBytes,
  int maxResults,
  String provider,
) {
  if (statusCode < 200 || statusCode >= 300) {
    throw WebSearchException('$provider returned HTTP $statusCode');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bodyBytes));
  } catch (_) {
    throw WebSearchException('$provider returned invalid JSON');
  }
  if (decoded is! Map) {
    throw WebSearchException('$provider returned an invalid response');
  }
  final rawResults = decoded['results'];
  if (rawResults is! List) {
    throw WebSearchException('$provider response is missing results');
  }
  final results = <WebSearchResult>[];
  for (final raw in rawResults) {
    if (raw is! Map) continue;
    final url = Uri.tryParse(raw['url']?.toString().trim() ?? '');
    if (url == null ||
        url.userInfo.isNotEmpty ||
        url.host.isEmpty ||
        (url.scheme != 'http' && url.scheme != 'https')) {
      continue;
    }
    final title = _boundedText(raw['title'], 500);
    final snippet = _boundedText(raw['content'] ?? raw['snippet'], 4000);
    if (title.isEmpty && snippet.isEmpty) continue;
    final score = raw['score'] is num ? (raw['score'] as num).toDouble() : null;
    results.add(
      WebSearchResult(
        title: title.isEmpty ? url.host : title,
        url: url,
        snippet: snippet,
        score: score?.isFinite == true ? score : null,
        publishedAt: DateTime.tryParse(
          raw['published_date']?.toString() ??
              raw['publishedAt']?.toString() ??
              '',
        ),
      ),
    );
    if (results.length >= maxResults * 2) break;
  }
  return results;
}

List<WebSearchResult> _normalizeResults(
  List<WebSearchResult> results,
  int maxResults,
) {
  final seen = <String>{};
  final normalized = <WebSearchResult>[];
  for (final result in results) {
    final uri = Uri.parse(result.url.toString().split('#').first);
    final key = uri.toString();
    if (!seen.add(key)) continue;
    normalized.add(
      WebSearchResult(
        title: _boundedText(result.title, 500),
        url: uri,
        snippet: _boundedText(result.snippet, 4000),
        score: result.score?.isFinite == true ? result.score : null,
        publishedAt: result.publishedAt,
      ),
    );
    if (normalized.length >= maxResults) break;
  }
  return List.unmodifiable(normalized);
}

String _boundedText(Object? value, int maxLength) {
  final text = value?.toString().trim() ?? '';
  return text.length <= maxLength ? text : text.substring(0, maxLength);
}
