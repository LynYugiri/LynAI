enum WebSearchRoute { client, backend, auto }

enum WebSearchClientProvider { tavily, searxng }

class WebSearchRequest {
  WebSearchRequest({
    required String query,
    this.maxResults = 5,
    String? language,
    String? timeRange,
  }) : query = query.trim(),
       language = _language(language),
       timeRange = _timeRange(timeRange) {
    if (this.query.isEmpty || this.query.length > 1000) {
      throw ArgumentError.value(
        query,
        'query',
        'must contain 1-1000 characters',
      );
    }
    if (maxResults < 1 || maxResults > 10) {
      throw ArgumentError.value(maxResults, 'maxResults', 'must be 1-10');
    }
  }

  final String query;
  final int maxResults;
  final String? language;
  final String? timeRange;
}

class WebSearchResult {
  const WebSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
    this.score,
    this.publishedAt,
  });

  final String title;
  final Uri url;
  final String snippet;
  final double? score;
  final DateTime? publishedAt;
}

class WebSearchResponse {
  const WebSearchResponse({
    required this.query,
    required this.provider,
    required this.route,
    required this.results,
  });

  final String query;
  final String provider;
  final WebSearchRoute route;
  final List<WebSearchResult> results;
}

String? _optionalText(String? value, String name) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  if (normalized.length > 64) {
    throw ArgumentError.value(value, name, 'must not exceed 64 characters');
  }
  return normalized;
}

String? _language(String? value) {
  final normalized = _optionalText(value, 'language');
  if (normalized == null) return null;
  if (!RegExp(r'^[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*$').hasMatch(normalized)) {
    throw ArgumentError.value(value, 'language', 'must be a language tag');
  }
  return normalized;
}

String? _timeRange(String? value) {
  final normalized = _optionalText(value, 'timeRange')?.toLowerCase();
  if (normalized == null) return null;
  if (normalized != 'day' && normalized != 'month' && normalized != 'year') {
    throw ArgumentError.value(
      value,
      'timeRange',
      'must be day, month, or year',
    );
  }
  return normalized;
}
