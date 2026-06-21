class ChatSearchRange {
  final int start;
  final int end;

  const ChatSearchRange({required this.start, required this.end});
}

class ChatSearchMatcher {
  final String query;
  final String? regexError;
  final RegExp? _regex;

  const ChatSearchMatcher._({
    required this.query,
    required this.regexError,
    required RegExp? regex,
  }) : _regex = regex;

  factory ChatSearchMatcher.fromQuery(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const ChatSearchMatcher._(
        query: '',
        regexError: null,
        regex: null,
      );
    }
    final parsed = _parseRegexSearch(trimmed);
    if (parsed == null) {
      return ChatSearchMatcher._(
        query: trimmed,
        regexError: null,
        regex: RegExp(RegExp.escape(trimmed), caseSensitive: false),
      );
    }
    try {
      return ChatSearchMatcher._(
        query: trimmed,
        regexError: null,
        regex: RegExp(
          parsed.pattern,
          caseSensitive: parsed.caseSensitive,
          multiLine: true,
        ),
      );
    } catch (error) {
      return ChatSearchMatcher._(
        query: trimmed,
        regexError: '$error',
        regex: null,
      );
    }
  }

  bool get isEmpty => query.isEmpty;

  bool get hasError => regexError != null;

  bool matches(String text) => rangesIn(text).isNotEmpty;

  List<ChatSearchRange> rangesIn(String text) {
    final regex = _regex;
    if (query.isEmpty || regex == null) return const [];
    return regex
        .allMatches(text)
        .where((match) => match.start < match.end)
        .map((match) => ChatSearchRange(start: match.start, end: match.end))
        .toList(growable: false);
  }
}

class _ParsedRegexSearch {
  final String pattern;
  final bool caseSensitive;

  const _ParsedRegexSearch(this.pattern, {required this.caseSensitive});
}

_ParsedRegexSearch? _parseRegexSearch(String query) {
  if (query.startsWith('re:')) {
    final pattern = query.substring(3).trim();
    return pattern.isEmpty
        ? null
        : _ParsedRegexSearch(pattern, caseSensitive: false);
  }
  if (!query.startsWith('/') || query.length < 2) return null;
  final lastSlash = query.lastIndexOf('/');
  if (lastSlash <= 0) return null;
  final pattern = query.substring(1, lastSlash);
  if (pattern.isEmpty) return null;
  final flags = query.substring(lastSlash + 1);
  return _ParsedRegexSearch(pattern, caseSensitive: !flags.contains('i'));
}
