import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/tree_sitter_native.dart';

/// Runs [body] only when tree-sitter native bundle is available and the
/// requested language is compiled in.
void _guard(String language, void Function(TreeSitterNative native) body) {
  final native = TreeSitterNative.instance;
  if (!native.isAvailable) return;
  if (!native.isLanguageSupported(language)) return;
  body(native);
}

/// Returns true when at least one token in [tokens] matches [kind].
bool _hasKind(List<TreeSitterHighlightToken> tokens, int kind) =>
    tokens.any((t) => t.kind == kind);

void main() {
  test('TreeSitterNative probing is safe without bundled library in tests', () {
    final native = TreeSitterNative.instance;

    expect(() => native.isAvailable, returnsNormally);
    expect(() => native.compiledLanguageCount, returnsNormally);
    expect(() => native.isLanguageSupported('javascript'), returnsNormally);
    expect(
      () => native.parseSummary('javascript', 'const value = 1;'),
      returnsNormally,
    );
  });

  test('TreeSitterNative stub parse summary is unavailable', () {
    final summary = TreeSitterNative.instance.parseSummary(
      'not-a-real-language',
      'source',
    );

    if (!TreeSitterNative.instance.isAvailable) {
      expect(summary.supported, false);
      expect(summary.parsed, false);
    }
  });

  test('TreeSitterNative query highlight classifies function names', () {
    _guard('javascript', (native) {
      final tokens = native.highlightTokens(
        'javascript',
        'function greet(name) { return name; }',
      );
      expect(_hasKind(tokens, TreeSitterTokenKind.function), true);
    });
  });

  test('TreeSitterNative query highlight classifies TypeScript types', () {
    _guard('typescript', (native) {
      final tokens = native.highlightTokens(
        'typescript',
        'function greet(name: string): void {}',
      );
      expect(_hasKind(tokens, TreeSitterTokenKind.type), true);
    });
  });

  test('TreeSitterNative query highlight classifies TSX tags and attributes', () {
    _guard('tsx', (native) {
      final tokens = native.highlightTokens(
        'tsx',
        '<div className="x"><span/></div>',
      );
      expect(_hasKind(tokens, TreeSitterTokenKind.tag), true);
      expect(_hasKind(tokens, TreeSitterTokenKind.attribute), true);
    });
  });

  test('TreeSitterNative query highlight classifies Python functions', () {
    _guard('python', (native) {
      final tokens = native.highlightTokens(
        'python',
        'def greet(name):\n    return name',
      );
      expect(_hasKind(tokens, TreeSitterTokenKind.function), true);
    });
  });

  test('TreeSitterNative query highlight classifies Python constants', () {
    _guard('python', (native) {
      final tokens = native.highlightTokens(
        'python',
        'x = True',
      );
      expect(_hasKind(tokens, TreeSitterTokenKind.constant), true);
    });
  });

  test('TreeSitterNative query highlight classifies JSON property keys', () {
    _guard('json', (native) {
      final tokens = native.highlightTokens(
        'json',
        '{"name": "value", "count": 42, "active": true}',
      );
      expect(_hasKind(tokens, TreeSitterTokenKind.property), true);
      expect(_hasKind(tokens, TreeSitterTokenKind.string), true);
      expect(_hasKind(tokens, TreeSitterTokenKind.number), true);
      expect(_hasKind(tokens, TreeSitterTokenKind.constant), true);
    });
  });

  test('TreeSitterNative query highlight classifies YAML properties', () {
    _guard('yaml', (native) {
      final tokens = native.highlightTokens(
        'yaml',
        'name: value\nage: 30\nactive: true\n',
      );
      expect(_hasKind(tokens, TreeSitterTokenKind.property), true);
    });
  });

  test('TreeSitterNative query highlight classifies HTML tags', () {
    _guard('html', (native) {
      final tokens = native.highlightTokens(
        'html',
        '<div class="box"><span>text</span></div>',
      );
      expect(_hasKind(tokens, TreeSitterTokenKind.tag), true);
    });
  });

  test('TreeSitterNative query highlight classifies CSS properties', () {
    _guard('css', (native) {
      final tokens = native.highlightTokens(
        'css',
        '.box { color: red; font-size: 16px; }',
      );
      expect(_hasKind(tokens, TreeSitterTokenKind.property), true);
    });
  });

  test('TreeSitterNative query highlight classifies Rust functions', () {
    _guard('rust', (native) {
      final tokens = native.highlightTokens(
        'rust',
        'fn greet(name: &str) -> String { name.to_string() }',
      );
      expect(_hasKind(tokens, TreeSitterTokenKind.function), true);
    });
  });

  test('TreeSitterNative query highlight classifies Go functions', () {
    _guard('go', (native) {
      final tokens = native.highlightTokens(
        'go',
        'func greet(name string) string { return name }',
      );
      expect(_hasKind(tokens, TreeSitterTokenKind.function), true);
    });
  });

  test('TreeSitterNative query highlight classifies Java methods', () {
    _guard('java', (native) {
      final tokens = native.highlightTokens(
        'java',
        'class A { void greet(String name) { } }',
      );
      expect(_hasKind(tokens, TreeSitterTokenKind.function), true);
    });
  });

  test('TreeSitterNative query highlight classifies C functions', () {
    _guard('c', (native) {
      final tokens = native.highlightTokens(
        'c',
        'int greet(const char* name) { return 0; }',
      );
      expect(_hasKind(tokens, TreeSitterTokenKind.function), true);
    });
  });

  test('TreeSitterNative query highlight classifies C++ types', () {
    _guard('cpp', (native) {
      final tokens = native.highlightTokens(
        'cpp',
        'std::string greet() { return ""; }',
      );
      expect(_hasKind(tokens, TreeSitterTokenKind.type), true);
    });
  });

  test('TreeSitterNative query highlight classifies Bash functions', () {
    _guard('bash', (native) {
      final tokens = native.highlightTokens(
        'bash',
        'greet() { echo "hello"; }',
      );
      expect(_hasKind(tokens, TreeSitterTokenKind.function), true);
    });
  });

  test('TreeSitterNative query highlight classifies TOML keys', () {
    _guard('toml', (native) {
      final tokens = native.highlightTokens(
        'toml',
        'title = "config"\nversion = 1\nenabled = true\n',
      );
      expect(_hasKind(tokens, TreeSitterTokenKind.property), true);
    });
  });

  test('TreeSitterNative query highlight classifies Markdown headings', () {
    _guard('markdown', (native) {
      final tokens = native.highlightTokens(
        'markdown',
        '# Hello\n\nParagraph text.\n',
      );
      expect(_hasKind(tokens, TreeSitterTokenKind.keyword), true);
    });
  });
}
