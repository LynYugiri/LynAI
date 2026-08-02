import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lynai/models/web_search.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/bounded_outbound_http_client.dart';
import 'package:lynai/services/outbound_network_policy.dart';
import 'package:lynai/services/secret_store.dart';
import 'package:lynai/services/web_search_service.dart';

void main() {
  test('request validates the shared search contract', () {
    expect(
      () => WebSearchRequest(query: 'query', maxResults: 11),
      throwsArgumentError,
    );
    expect(
      () => WebSearchRequest(query: 'query', language: 'not a tag!'),
      throwsArgumentError,
    );
    expect(
      () => WebSearchRequest(query: 'query', timeRange: 'week'),
      throwsArgumentError,
    );
    final request = WebSearchRequest(
      query: 'query',
      maxResults: 10,
      language: 'zh-CN',
      timeRange: 'MONTH',
    );
    expect(request.language, 'zh-CN');
    expect(request.timeRange, 'month');
  });

  test(
    'Tavily uses its fixed endpoint and keeps API key out of output',
    () async {
      const secret = 'tavily-super-secret';
      late http.BaseRequest recorded;
      final adapter = TavilyWebSearchAdapter(
        secretStore: InMemorySecretStore({
          TavilyWebSearchAdapter.apiKeySecretKey: secret,
        }),
        httpClient: BoundedOutboundHttpClient(
          policy: OutboundNetworkPolicy(
            hostResolver: (host) async => const ['93.184.216.34'],
          ),
          clientFactory: () => _HandlerClient((request) async {
            recorded = request;
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  jsonEncode({
                    'results': [
                      {
                        'title': ' Result ',
                        'url': 'https://example.com/page#section',
                        'content': ' Snippet ',
                        'score': 0.8,
                      },
                    ],
                  }),
                ),
              ),
              200,
            );
          }),
        ),
      );
      final service = WebSearchService(clientAdapters: [adapter]);

      final response = await service.search(
        WebSearchRequest(
          query: ' flutter search ',
          maxResults: 7,
          language: 'en',
          timeRange: 'month',
        ),
        route: WebSearchRoute.client,
      );

      expect(recorded.url, Uri.parse('https://api.tavily.com/search'));
      expect(response.query, 'flutter search');
      expect(response.provider, 'tavily');
      expect(response.results.single.title, 'Result');
      expect(response.results.single.snippet, 'Snippet');
      expect(response.results.single.url.fragment, isEmpty);
      expect(response.toString(), isNot(contains(secret)));
      expect(response.results.toString(), isNot(contains(secret)));
      final body = jsonDecode((recorded as http.Request).body) as Map;
      expect(body, {
        'api_key': secret,
        'query': 'flutter search',
        'max_results': 7,
        'time_range': 'month',
        'include_answer': false,
        'include_raw_content': false,
      });
    },
  );

  test(
    'Tavily refuses redirects that could replay its body credential',
    () async {
      final requests = <http.BaseRequest>[];
      final adapter = TavilyWebSearchAdapter(
        secretStore: InMemorySecretStore({
          TavilyWebSearchAdapter.apiKeySecretKey: 'secret',
        }),
        httpClient: BoundedOutboundHttpClient(
          policy: OutboundNetworkPolicy(
            hostResolver: (host) async => const ['93.184.216.34'],
          ),
          clientFactory: () => _HandlerClient((request) async {
            requests.add(request);
            return http.StreamedResponse(
              const Stream.empty(),
              307,
              headers: {'location': 'https://other.example/search'},
            );
          }),
        ),
      );

      await expectLater(
        adapter.search(WebSearchRequest(query: 'query')),
        throwsA(isA<OutboundHttpException>()),
      );
      expect(requests, hasLength(1));
    },
  );

  test('auto route falls back across client providers then backend', () async {
    final calls = <String>[];
    final service = WebSearchService(
      clientAdapters: [
        _FakeAdapter(
          id: 'tavily',
          provider: WebSearchClientProvider.tavily,
          onSearch: () {
            calls.add('tavily');
            throw const WebSearchException('temporary failure');
          },
        ),
        _FakeAdapter(
          id: 'searxng',
          provider: WebSearchClientProvider.searxng,
          configured: false,
          onSearch: () => const [],
        ),
      ],
      backendAdapter: _FakeAdapter(
        id: 'lynai_backend',
        provider: null,
        onSearch: () {
          calls.add('backend');
          return [
            WebSearchResult(
              title: 'Backend result',
              url: Uri.parse('https://example.com/result'),
              snippet: 'ok',
            ),
          ];
        },
      ),
    );

    final response = await service.search(
      WebSearchRequest(query: 'query'),
      route: WebSearchRoute.auto,
      preferredClientProvider: WebSearchClientProvider.tavily,
    );

    expect(calls, ['tavily', 'backend']);
    expect(response.route, WebSearchRoute.backend);
    expect(response.provider, 'lynai_backend');
  });

  test('backend adapter posts the exact shared request contract', () async {
    late http.BaseRequest recorded;
    final backend = BackendClient(
      client: _HandlerClient((request) async {
        recorded = request;
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"provider":"searxng","results":[]}')),
          200,
        );
      }),
    );
    backend.configure('https://backend.example');
    backend.setTokens('access-token', 'refresh-token');

    await LynaiBackendWebSearchAdapter(backend: backend).search(
      WebSearchRequest(
        query: 'contract',
        maxResults: 10,
        language: 'zh-CN',
        timeRange: 'day',
      ),
    );

    expect(recorded.method, 'POST');
    expect(recorded.url, Uri.parse('https://backend.example/search/web'));
    expect(jsonDecode((recorded as http.Request).body), {
      'query': 'contract',
      'maxResults': 10,
      'language': 'zh-CN',
      'timeRange': 'day',
    });
    backend.close();
  });

  test('normalizes, deduplicates, and caps provider results', () async {
    final service = WebSearchService(
      clientAdapters: [
        _FakeAdapter(
          id: 'searxng',
          provider: WebSearchClientProvider.searxng,
          onSearch: () => [
            WebSearchResult(
              title: ' First ',
              url: Uri.parse('https://example.com/a#one'),
              snippet: ' A ',
            ),
            WebSearchResult(
              title: 'Duplicate',
              url: Uri.parse('https://example.com/a#two'),
              snippet: 'duplicate',
            ),
            WebSearchResult(
              title: 'Second',
              url: Uri.parse('https://example.com/b'),
              snippet: 'B',
            ),
          ],
        ),
      ],
    );

    final response = await service.search(
      WebSearchRequest(query: 'query', maxResults: 2),
      route: WebSearchRoute.client,
    );

    expect(response.results, hasLength(2));
    expect(response.results.first.title, 'First');
    expect(response.results.first.url, Uri.parse('https://example.com/a'));
    expect(response.results.last.url, Uri.parse('https://example.com/b'));
  });

  test(
    'SearXNG endpoint is trusted construction input, never request input',
    () async {
      final requests = <http.BaseRequest>[];
      final adapter = SearxngWebSearchAdapter(
        endpoint: Uri.parse('https://search.example/api'),
        secretStore: InMemorySecretStore(),
        httpClient: BoundedOutboundHttpClient(
          policy: OutboundNetworkPolicy(
            hostResolver: (host) async => const ['93.184.216.34'],
          ),
          clientFactory: () => _HandlerClient((request) async {
            requests.add(request);
            return http.StreamedResponse(
              Stream.value(utf8.encode('{"results":[]}')),
              200,
            );
          }),
        ),
      );

      await adapter.search(
        WebSearchRequest(
          query: 'https://127.0.0.1/admin',
          language: 'zh-CN',
          timeRange: 'year',
        ),
      );

      expect(requests.single.url.host, 'search.example');
      expect(
        requests.single.url.queryParameters['q'],
        'https://127.0.0.1/admin',
      );
      expect(
        requests.single.url.queryParameters,
        containsPair('format', 'json'),
      );
      expect(requests.single.url.queryParameters, containsPair('pageno', '1'));
      expect(
        requests.single.url.queryParameters,
        containsPair('language', 'zh-CN'),
      );
      expect(
        requests.single.url.queryParameters,
        containsPair('time_range', 'year'),
      );
    },
  );

  test('provider errors do not include secret values', () async {
    const secret = 'do-not-leak-this';
    final adapter = TavilyWebSearchAdapter(
      secretStore: InMemorySecretStore({
        TavilyWebSearchAdapter.apiKeySecretKey: secret,
      }),
      httpClient: BoundedOutboundHttpClient(
        policy: OutboundNetworkPolicy(
          hostResolver: (host) async => const ['93.184.216.34'],
        ),
        clientFactory: () => _HandlerClient(
          (request) async => http.StreamedResponse(
            Stream.value(utf8.encode('{"error":"$secret"}')),
            401,
          ),
        ),
      ),
    );

    await expectLater(
      adapter.search(WebSearchRequest(query: 'query')),
      throwsA(
        isA<WebSearchException>().having(
          (error) => error.toString(),
          'message',
          isNot(contains(secret)),
        ),
      ),
    );
  });

  test(
    'SearXNG bearer token cannot use HTTP without exact-origin policy',
    () async {
      var requests = 0;
      final adapter = SearxngWebSearchAdapter(
        endpoint: Uri.parse('http://search.example:8080/search'),
        secretStore: InMemorySecretStore({
          SearxngWebSearchAdapter.bearerTokenSecretKey: 'secret',
        }),
        allowPlaintextHttp: true,
        httpClient: BoundedOutboundHttpClient(
          policy: OutboundNetworkPolicy(
            hostResolver: (host) async => const ['93.184.216.34'],
          ),
          clientFactory: () => _HandlerClient((request) async {
            requests++;
            return http.StreamedResponse(const Stream.empty(), 200);
          }),
        ),
      );

      await expectLater(
        adapter.search(WebSearchRequest(query: 'query')),
        throwsA(isA<OutboundNetworkPolicyException>()),
      );
      expect(requests, 0);
    },
  );

  test(
    'SearXNG HTTP opt-in is scoped to the configured exact origin',
    () async {
      late http.BaseRequest recorded;
      final endpoint = Uri.parse('http://search.example:8080/search');
      final adapter = SearxngWebSearchAdapter(
        endpoint: endpoint,
        secretStore: InMemorySecretStore({
          SearxngWebSearchAdapter.bearerTokenSecretKey: 'secret',
        }),
        allowPlaintextHttp: true,
        httpClient: BoundedOutboundHttpClient(
          policy: OutboundNetworkPolicy(
            allowedHttpOrigins: {outboundOrigin(endpoint)},
            hostResolver: (host) async => const ['93.184.216.34'],
          ),
          clientFactory: () => _HandlerClient((request) async {
            recorded = request;
            return http.StreamedResponse(
              Stream.value(utf8.encode('{"results":[]}')),
              200,
            );
          }),
        ),
      );

      await adapter.search(WebSearchRequest(query: 'query'));

      expect(recorded.url.host, endpoint.host);
      expect(recorded.url.port, endpoint.port);
      expect(recorded.headers['Authorization'], 'Bearer secret');
    },
  );

  test('SearXNG rejects plaintext construction without explicit opt-in', () {
    expect(
      () => SearxngWebSearchAdapter(
        endpoint: Uri.parse('http://search.example/search'),
        secretStore: InMemorySecretStore(),
        httpClient: BoundedOutboundHttpClient(),
      ),
      throwsArgumentError,
    );
  });

  test(
    'SearXNG HTTP redirect cannot expand plaintext origin authority',
    () async {
      final endpoint = Uri.parse('http://search.example:8080/search');
      final requests = <http.BaseRequest>[];
      final adapter = SearxngWebSearchAdapter(
        endpoint: endpoint,
        secretStore: InMemorySecretStore({
          SearxngWebSearchAdapter.bearerTokenSecretKey: 'secret',
        }),
        allowPlaintextHttp: true,
        httpClient: BoundedOutboundHttpClient(
          policy: OutboundNetworkPolicy(
            allowedHttpOrigins: {outboundOrigin(endpoint)},
            hostResolver: (host) async => const ['93.184.216.34'],
          ),
          clientFactory: () => _HandlerClient((request) async {
            requests.add(request);
            return http.StreamedResponse(
              const Stream.empty(),
              302,
              headers: {'location': 'http://other.example:8080/search'},
            );
          }),
        ),
      );

      await expectLater(
        adapter.search(WebSearchRequest(query: 'query')),
        throwsA(isA<OutboundNetworkPolicyException>()),
      );
      expect(requests, hasLength(1));
      expect(requests.single.headers['Authorization'], 'Bearer secret');
    },
  );

  test('Tavily isConfigured requires a stored API key', () async {
    final adapter = TavilyWebSearchAdapter(
      secretStore: InMemorySecretStore(),
      httpClient: BoundedOutboundHttpClient(),
    );
    expect(await adapter.isConfigured(), isFalse);
    final configured = TavilyWebSearchAdapter(
      secretStore: InMemorySecretStore({
        TavilyWebSearchAdapter.apiKeySecretKey: 'secret',
      }),
      httpClient: BoundedOutboundHttpClient(),
    );
    expect(await configured.isConfigured(), isTrue);
  });

  test('isConfigured reports whether any candidate adapter is available', (
    ) async {
    final none = WebSearchService(
      clientAdapters: [
        _FakeAdapter(
          id: 'tavily',
          provider: WebSearchClientProvider.tavily,
          configured: false,
          onSearch: () => const [],
        ),
      ],
    );
    expect(await none.isConfigured(), isFalse);
    expect(await none.isConfigured(route: WebSearchRoute.backend), isFalse);

    final some = WebSearchService(
      clientAdapters: [
        _FakeAdapter(
          id: 'tavily',
          provider: WebSearchClientProvider.tavily,
          configured: false,
          onSearch: () => const [],
        ),
        _FakeAdapter(
          id: 'searxng',
          provider: WebSearchClientProvider.searxng,
          configured: true,
          onSearch: () => const [],
        ),
      ],
      backendAdapter: _FakeAdapter(
        id: 'lynai_backend',
        provider: null,
        configured: false,
        onSearch: () => const [],
      ),
    );
    expect(await some.isConfigured(), isTrue);
    expect(
      await some.isConfigured(
        route: WebSearchRoute.client,
        preferredClientProvider: WebSearchClientProvider.tavily,
      ),
      isTrue,
    );
    expect(await some.isConfigured(route: WebSearchRoute.backend), isFalse);
  });
}

class _HandlerClient extends http.BaseClient {
  _HandlerClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

class _FakeAdapter implements WebSearchAdapter {
  _FakeAdapter({
    required this.id,
    required WebSearchClientProvider? provider,
    required this.onSearch,
    this.configured = true,
  }) : clientProvider = provider;

  @override
  final String id;

  @override
  final WebSearchClientProvider? clientProvider;

  final bool configured;
  final List<WebSearchResult> Function() onSearch;

  @override
  Future<bool> isConfigured() async => configured;

  @override
  Future<List<WebSearchResult>> search(
    WebSearchRequest request, {
    cancellationToken,
  }) async => onSearch();
}
