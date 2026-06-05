import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'tree_sitter_native.dart';

typedef _NativeAvailable = Int32 Function();
typedef _DartAvailable = int Function();
typedef _NativeLanguageSupported = Int32 Function(Pointer<Utf8> language);
typedef _DartLanguageSupported = int Function(Pointer<Utf8> language);
typedef _NativeParseSummary =
    Int32 Function(
      Pointer<Utf8> language,
      Pointer<Utf8> source,
      Uint32 sourceLength,
      Pointer<_TreeSitterParseSummaryNative> outSummary,
    );
typedef _DartParseSummary =
    int Function(
      Pointer<Utf8> language,
      Pointer<Utf8> source,
      int sourceLength,
      Pointer<_TreeSitterParseSummaryNative> outSummary,
    );
typedef _NativeHighlightTokens =
    Int32 Function(
      Pointer<Utf8> language,
      Pointer<Utf8> source,
      Uint32 sourceLength,
      Pointer<_TreeSitterHighlightResultNative> outResult,
    );
typedef _DartHighlightTokens =
    int Function(
      Pointer<Utf8> language,
      Pointer<Utf8> source,
      int sourceLength,
      Pointer<_TreeSitterHighlightResultNative> outResult,
    );
typedef _NativeFreeHighlightResult =
    Void Function(Pointer<_TreeSitterHighlightResultNative> result);
typedef _DartFreeHighlightResult =
    void Function(Pointer<_TreeSitterHighlightResultNative> result);

final class _TreeSitterParseSummaryNative extends Struct {
  @Int32()
  external int supported;

  @Int32()
  external int parsed;

  @Int32()
  external int hasError;

  @Uint32()
  external int rootChildCount;

  @Uint32()
  external int rootStartByte;

  @Uint32()
  external int rootEndByte;
}

final class _TreeSitterHighlightTokenNative extends Struct {
  @Uint32()
  external int startByte;

  @Uint32()
  external int endByte;

  @Int32()
  external int kind;
}

final class _TreeSitterHighlightResultNative extends Struct {
  @Int32()
  external int supported;

  @Int32()
  external int parsed;

  @Int32()
  external int hasError;

  @Uint32()
  external int tokenCount;

  external Pointer<_TreeSitterHighlightTokenNative> tokens;
}

TreeSitterNative createTreeSitterNative() => _TreeSitterNativeFfi.instance;

class _TreeSitterNativeFfi implements TreeSitterNative {
  static final instance = _TreeSitterNativeFfi._();

  DynamicLibrary? _library;
  _DartAvailable? _available;
  _DartAvailable? _languageCount;
  _DartLanguageSupported? _languageSupported;
  _DartParseSummary? _parseSummary;
  _DartHighlightTokens? _highlightTokens;
  _DartFreeHighlightResult? _freeHighlightResult;
  var _loaded = false;

  _TreeSitterNativeFfi._();

  @override
  bool get isAvailable {
    _ensureLoaded();
    return (_available?.call() ?? 0) != 0;
  }

  @override
  int get compiledLanguageCount {
    _ensureLoaded();
    return _languageCount?.call() ?? 0;
  }

  @override
  bool isLanguageSupported(String language) {
    _ensureLoaded();
    final supported = _languageSupported;
    if (supported == null) return false;
    final nativeLanguage = language.toNativeUtf8();
    try {
      return supported(nativeLanguage) != 0;
    } finally {
      calloc.free(nativeLanguage);
    }
  }

  @override
  TreeSitterParseSummary parseSummary(String language, String source) {
    _ensureLoaded();
    final parse = _parseSummary;
    if (parse == null) return TreeSitterParseSummary.unavailable;

    final nativeLanguage = language.toNativeUtf8();
    final nativeSource = source.toNativeUtf8();
    final out = calloc<_TreeSitterParseSummaryNative>();
    try {
      final ok = parse(nativeLanguage, nativeSource, nativeSource.length, out);
      if (ok == 0) return TreeSitterParseSummary.unavailable;
      final summary = out.ref;
      return TreeSitterParseSummary(
        supported: summary.supported != 0,
        parsed: summary.parsed != 0,
        hasError: summary.hasError != 0,
        rootChildCount: summary.rootChildCount,
        rootStartByte: summary.rootStartByte,
        rootEndByte: summary.rootEndByte,
      );
    } finally {
      calloc.free(out);
      calloc.free(nativeSource);
      calloc.free(nativeLanguage);
    }
  }

  @override
  List<TreeSitterHighlightToken> highlightTokens(
    String language,
    String source,
  ) {
    _ensureLoaded();
    final highlight = _highlightTokens;
    final freeResult = _freeHighlightResult;
    if (highlight == null || freeResult == null) return const [];

    final nativeLanguage = language.toNativeUtf8();
    final nativeSource = source.toNativeUtf8();
    final out = calloc<_TreeSitterHighlightResultNative>();
    try {
      final ok = highlight(
        nativeLanguage,
        nativeSource,
        nativeSource.length,
        out,
      );
      if (ok == 0 || out.ref.parsed == 0 || out.ref.tokenCount == 0) {
        return const [];
      }
      final tokens = <TreeSitterHighlightToken>[];
      for (var i = 0; i < out.ref.tokenCount; i++) {
        final token = (out.ref.tokens + i).ref;
        tokens.add(
          TreeSitterHighlightToken(
            startByte: token.startByte,
            endByte: token.endByte,
            kind: token.kind,
          ),
        );
      }
      return tokens;
    } finally {
      freeResult(out);
      calloc.free(out);
      calloc.free(nativeSource);
      calloc.free(nativeLanguage);
    }
  }

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      _library = _openLibrary();
      _available = _library!.lookupFunction<_NativeAvailable, _DartAvailable>(
        'lynai_ts_available',
      );
      _languageCount = _library!
          .lookupFunction<_NativeAvailable, _DartAvailable>(
            'lynai_ts_compiled_language_count',
          );
      _languageSupported = _library!
          .lookupFunction<_NativeLanguageSupported, _DartLanguageSupported>(
            'lynai_ts_language_supported',
          );
      _parseSummary = _library!
          .lookupFunction<_NativeParseSummary, _DartParseSummary>(
            'lynai_ts_parse_summary',
          );
      _highlightTokens = _library!
          .lookupFunction<_NativeHighlightTokens, _DartHighlightTokens>(
            'lynai_ts_highlight_tokens',
          );
      _freeHighlightResult = _library!
          .lookupFunction<_NativeFreeHighlightResult, _DartFreeHighlightResult>(
            'lynai_ts_free_highlight_result',
          );
    } catch (_) {
      _library = null;
      _available = null;
      _languageCount = null;
      _languageSupported = null;
      _parseSummary = null;
      _highlightTokens = null;
      _freeHighlightResult = null;
    }
  }

  DynamicLibrary _openLibrary() {
    if (Platform.isIOS) return DynamicLibrary.process();
    if (Platform.isMacOS) {
      try {
        return DynamicLibrary.open('liblynai_tree_sitter.dylib');
      } catch (_) {
        return DynamicLibrary.process();
      }
    }
    if (Platform.isWindows) return DynamicLibrary.open('lynai_tree_sitter.dll');
    return DynamicLibrary.open('liblynai_tree_sitter.so');
  }
}
