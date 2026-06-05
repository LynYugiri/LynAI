import 'package:flutter/foundation.dart';

@immutable
class TreeSitterLanguageDefinition {
  final String id;
  final String symbol;
  final Set<String> aliases;
  final bool hasExternalScanner;

  const TreeSitterLanguageDefinition({
    required this.id,
    required this.symbol,
    this.aliases = const {},
    this.hasExternalScanner = false,
  });

  bool matches(String language) {
    final normalized = language.trim().toLowerCase();
    return normalized == id || aliases.contains(normalized);
  }
}

/// Mainstream language registry for LynAI's native tree-sitter bundle.
///
/// Web intentionally falls back to the existing Dart highlighter; these entries
/// describe native grammars that can be compiled into the app bundle.
class TreeSitterLanguageRegistry {
  static const definitions = <TreeSitterLanguageDefinition>[
    TreeSitterLanguageDefinition(
      id: 'javascript',
      symbol: 'tree_sitter_javascript',
      aliases: {'js', 'mjs', 'cjs', 'jsx'},
    ),
    TreeSitterLanguageDefinition(
      id: 'typescript',
      symbol: 'tree_sitter_typescript',
      aliases: {'ts'},
    ),
    TreeSitterLanguageDefinition(id: 'tsx', symbol: 'tree_sitter_tsx'),
    TreeSitterLanguageDefinition(id: 'html', symbol: 'tree_sitter_html'),
    TreeSitterLanguageDefinition(id: 'css', symbol: 'tree_sitter_css'),
    TreeSitterLanguageDefinition(id: 'scss', symbol: 'tree_sitter_scss'),
    TreeSitterLanguageDefinition(id: 'vue', symbol: 'tree_sitter_vue'),
    TreeSitterLanguageDefinition(id: 'svelte', symbol: 'tree_sitter_svelte'),
    TreeSitterLanguageDefinition(id: 'dart', symbol: 'tree_sitter_dart'),
    TreeSitterLanguageDefinition(id: 'kotlin', symbol: 'tree_sitter_kotlin'),
    TreeSitterLanguageDefinition(
      id: 'swift',
      symbol: 'tree_sitter_swift',
      hasExternalScanner: true,
    ),
    TreeSitterLanguageDefinition(id: 'java', symbol: 'tree_sitter_java'),
    TreeSitterLanguageDefinition(
      id: 'objective-c',
      symbol: 'tree_sitter_objc',
      aliases: {'objc', 'objectivec'},
    ),
    TreeSitterLanguageDefinition(
      id: 'python',
      symbol: 'tree_sitter_python',
      aliases: {'py'},
    ),
    TreeSitterLanguageDefinition(
      id: 'go',
      symbol: 'tree_sitter_go',
      aliases: {'golang'},
    ),
    TreeSitterLanguageDefinition(
      id: 'rust',
      symbol: 'tree_sitter_rust',
      aliases: {'rs'},
    ),
    TreeSitterLanguageDefinition(id: 'c', symbol: 'tree_sitter_c'),
    TreeSitterLanguageDefinition(
      id: 'cpp',
      symbol: 'tree_sitter_cpp',
      aliases: {'c++', 'cc', 'cxx', 'hpp'},
    ),
    TreeSitterLanguageDefinition(
      id: 'c-sharp',
      symbol: 'tree_sitter_c_sharp',
      aliases: {'cs', 'csharp'},
    ),
    TreeSitterLanguageDefinition(id: 'php', symbol: 'tree_sitter_php'),
    TreeSitterLanguageDefinition(
      id: 'ruby',
      symbol: 'tree_sitter_ruby',
      aliases: {'rb'},
    ),
    TreeSitterLanguageDefinition(
      id: 'bash',
      symbol: 'tree_sitter_bash',
      aliases: {'sh', 'shell'},
    ),
    TreeSitterLanguageDefinition(
      id: 'powershell',
      symbol: 'tree_sitter_powershell',
      aliases: {'ps1', 'pwsh'},
    ),
    TreeSitterLanguageDefinition(id: 'lua', symbol: 'tree_sitter_lua'),
    TreeSitterLanguageDefinition(
      id: 'perl',
      symbol: 'tree_sitter_perl',
      aliases: {'pl'},
    ),
    TreeSitterLanguageDefinition(id: 'json', symbol: 'tree_sitter_json'),
    TreeSitterLanguageDefinition(
      id: 'yaml',
      symbol: 'tree_sitter_yaml',
      aliases: {'yml'},
    ),
    TreeSitterLanguageDefinition(id: 'toml', symbol: 'tree_sitter_toml'),
    TreeSitterLanguageDefinition(id: 'xml', symbol: 'tree_sitter_xml'),
    TreeSitterLanguageDefinition(id: 'sql', symbol: 'tree_sitter_sql'),
    TreeSitterLanguageDefinition(
      id: 'markdown',
      symbol: 'tree_sitter_markdown',
      aliases: {'md'},
    ),
    TreeSitterLanguageDefinition(
      id: 'elixir',
      symbol: 'tree_sitter_elixir',
      aliases: {'ex', 'exs'},
    ),
    TreeSitterLanguageDefinition(
      id: 'erlang',
      symbol: 'tree_sitter_erlang',
      aliases: {'erl'},
    ),
    TreeSitterLanguageDefinition(id: 'scala', symbol: 'tree_sitter_scala'),
    TreeSitterLanguageDefinition(
      id: 'haskell',
      symbol: 'tree_sitter_haskell',
      aliases: {'hs'},
    ),
    TreeSitterLanguageDefinition(id: 'r', symbol: 'tree_sitter_r'),
  ];

  static TreeSitterLanguageDefinition? find(String? language) {
    if (language == null || language.trim().isEmpty) return null;
    for (final definition in definitions) {
      if (definition.matches(language)) return definition;
    }
    return null;
  }
}
