#include "lynai_tree_sitter.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <tree_sitter/api.h>

#ifdef LYNAI_TS_JAVASCRIPT
extern const TSLanguage* tree_sitter_javascript(void);
#endif
#ifdef LYNAI_TS_TYPESCRIPT
extern const TSLanguage* tree_sitter_typescript(void);
#endif
#ifdef LYNAI_TS_TSX
extern const TSLanguage* tree_sitter_tsx(void);
#endif
#ifdef LYNAI_TS_HTML
extern const TSLanguage* tree_sitter_html(void);
#endif
#ifdef LYNAI_TS_CSS
extern const TSLanguage* tree_sitter_css(void);
#endif
#ifdef LYNAI_TS_PYTHON
extern const TSLanguage* tree_sitter_python(void);
#endif
#ifdef LYNAI_TS_GO
extern const TSLanguage* tree_sitter_go(void);
#endif
#ifdef LYNAI_TS_RUST
extern const TSLanguage* tree_sitter_rust(void);
#endif
#ifdef LYNAI_TS_C
extern const TSLanguage* tree_sitter_c(void);
#endif
#ifdef LYNAI_TS_CPP
extern const TSLanguage* tree_sitter_cpp(void);
#endif
#ifdef LYNAI_TS_JAVA
extern const TSLanguage* tree_sitter_java(void);
#endif
#ifdef LYNAI_TS_JSON
extern const TSLanguage* tree_sitter_json(void);
#endif
#ifdef LYNAI_TS_BASH
extern const TSLanguage* tree_sitter_bash(void);
#endif
#ifdef LYNAI_TS_YAML
extern const TSLanguage* tree_sitter_yaml(void);
#endif
#ifdef LYNAI_TS_TOML
extern const TSLanguage* tree_sitter_toml(void);
#endif
#ifdef LYNAI_TS_MARKDOWN
extern const TSLanguage* tree_sitter_markdown(void);
#endif

typedef const TSLanguage* (*LynaiTsLanguageFn)(void);

typedef struct LynaiTsTokenBuffer {
  LynaiTsToken* items;
  uint32_t count;
  uint32_t capacity;
} LynaiTsTokenBuffer;

typedef struct LynaiTsLanguageEntry {
  const char* id;
  const char* const* aliases;
  int alias_count;
  LynaiTsLanguageFn language_fn;
  const char* highlight_query;
} LynaiTsLanguageEntry;

#define LYNAI_TS_ALIASES(name, ...) \
  static const char* const name[] = {__VA_ARGS__}

LYNAI_TS_ALIASES(kJavascriptAliases, "js", "mjs", "cjs", "jsx");
LYNAI_TS_ALIASES(kTypescriptAliases, "ts");
LYNAI_TS_ALIASES(kPythonAliases, "py");
LYNAI_TS_ALIASES(kGoAliases, "golang");
LYNAI_TS_ALIASES(kRustAliases, "rs");
LYNAI_TS_ALIASES(kCppAliases, "c++", "cc", "cxx", "hpp");
LYNAI_TS_ALIASES(kBashAliases, "sh", "shell");
LYNAI_TS_ALIASES(kYamlAliases, "yml");
LYNAI_TS_ALIASES(kMarkdownAliases, "md");

#define LYNAI_TS_ENTRY(ID, FN, QUERY) {ID, 0, 0, FN, QUERY}
#define LYNAI_TS_ENTRY_ALIASES(ID, ALIASES, QUERY) \
  { ID, ALIASES, (int)(sizeof(ALIASES) / sizeof(ALIASES[0])), tree_sitter_##ID, QUERY }
#define LYNAI_TS_ENTRY_ALIASES_FN(ID, ALIASES, FN, QUERY) \
  { ID, ALIASES, (int)(sizeof(ALIASES) / sizeof(ALIASES[0])), FN, QUERY }

static const char kQueryjavascript[] =
    "(comment) @comment\n"
    "(string) @string\n"
    "(template_string) @string\n"
    "(regex) @string\n"
    "(number) @number\n"
    "(function_declaration name: (identifier) @function)\n"
    "(method_definition name: (property_identifier) @function)\n"
    "(call_expression function: (identifier) @function.call)\n"
    "(call_expression function: (member_expression property: (property_identifier) @function.call))\n"
    "(property_identifier) @property\n"
    "(shorthand_property_identifier) @property\n"
    "(identifier) @variable\n";

static const char kQuerytypescript[] =
    "(comment) @comment\n"
    "(string) @string\n"
    "(template_string) @string\n"
    "(number) @number\n"
    "(function_declaration name: (identifier) @function)\n"
    "(method_definition name: (property_identifier) @function)\n"
    "(type_identifier) @type\n"
    "(predefined_type) @type\n"
    "(true) @constant\n"
    "(false) @constant\n"
    "(null) @constant\n"
    "(undefined) @constant\n"
    "(property_identifier) @property\n"
    "(shorthand_property_identifier) @property\n"
    "(identifier) @variable\n";

static const char kQuerytsx[] =
    "(comment) @comment\n"
    "(string) @string\n"
    "(template_string) @string\n"
    "(number) @number\n"
    "(function_declaration name: (identifier) @function)\n"
    "(type_identifier) @type\n"
    "(predefined_type) @type\n"
    "(true) @constant\n"
    "(false) @constant\n"
    "(null) @constant\n"
    "(undefined) @constant\n"
    "(property_identifier) @property\n"
    "(jsx_opening_element name: (identifier) @tag)\n"
    "(jsx_closing_element name: (identifier) @tag)\n"
    "(jsx_self_closing_element name: (identifier) @tag)\n"
    "(jsx_attribute) @attribute\n"
    "(identifier) @variable\n";

static const char kQueryhtml[] =
    "(tag_name) @tag\n"
    "(attribute_name) @attribute\n"
    "(attribute_value) @string\n"
    "(comment) @comment\n";

static const char kQuerycss[] =
    "[\"@import\" \"@media\" \"@keyframes\" \"!important\"] @keyword\n"
    "(comment) @comment\n"
    "(string_value) @string\n"
    "(color_value) @constant\n"
    "(integer_value) @number\n"
    "(float_value) @number\n"
    "(property_name) @property\n"
    "(tag_name) @tag\n"
    "(class_name) @attribute\n"
    "(id_name) @attribute\n";

static const char kQuerypython[] =
    "(comment) @comment\n"
    "(string) @string\n"
    "(integer) @number\n"
    "(float) @number\n"
    "(function_definition name: (identifier) @function)\n"
    "(true) @constant\n"
    "(false) @constant\n"
    "(none) @constant\n"
    "(attribute) @property\n"
    "(identifier) @variable\n";

static const char kQuerygo[] =
    "(comment) @comment\n"
    "(interpreted_string_literal) @string\n"
    "(raw_string_literal) @string\n"
    "(int_literal) @number\n"
    "(float_literal) @number\n"
    "(function_declaration name: (identifier) @function)\n"
    "(type_identifier) @type\n"
    "(true) @constant\n"
    "(false) @constant\n"
    "(nil) @constant\n"
    "(field_identifier) @property\n"
    "(identifier) @variable\n";

static const char kQueryrust[] =
    "[\"as\" \"async\" \"await\" \"break\" \"const\" \"continue\" \"crate\" \"dyn\" \"else\" \"enum\" \"extern\" \"false\" \"fn\" \"for\" \"if\" \"impl\" \"in\" \"let\" \"loop\" \"match\" \"mod\" \"move\" \"mut\" \"pub\" \"ref\" \"return\" \"self\" \"Self\" \"static\" \"struct\" \"super\" \"trait\" \"true\" \"type\" \"unsafe\" \"use\" \"where\" \"while\"] @keyword\n"
    "(line_comment) @comment\n"
    "(block_comment) @comment\n"
    "(string_literal) @string\n"
    "(raw_string_literal) @string\n"
    "(integer_literal) @number\n"
    "(float_literal) @number\n"
    "(function_item name: (identifier) @function)\n"
    "(call_expression function: (identifier) @function.call)\n"
    "(type_identifier) @type\n"
    "(field_identifier) @property\n"
    "(identifier) @variable\n";

static const char kQueryc[] =
    "[\"auto\" \"break\" \"case\" \"const\" \"continue\" \"default\" \"do\" \"else\" \"enum\" \"extern\" \"for\" \"goto\" \"if\" \"inline\" \"register\" \"return\" \"sizeof\" \"static\" \"struct\" \"switch\" \"typedef\" \"union\" \"volatile\" \"while\"] @keyword\n"
    "(comment) @comment\n"
    "(string_literal) @string\n"
    "(char_literal) @string\n"
    "(number_literal) @number\n"
    "(function_declarator declarator: (identifier) @function)\n"
    "(call_expression function: (identifier) @function.call)\n"
    "(type_identifier) @type\n"
    "(primitive_type) @type\n"
    "(field_identifier) @property\n"
    "(identifier) @variable\n";

static const char kQuerycpp[] =
    "[\"alignas\" \"alignof\" \"auto\" \"break\" \"case\" \"catch\" \"class\" \"const\" \"constexpr\" \"continue\" \"decltype\" \"default\" \"delete\" \"do\" \"else\" \"enum\" \"explicit\" \"export\" \"extern\" \"for\" \"friend\" \"if\" \"inline\" \"mutable\" \"namespace\" \"new\" \"noexcept\" \"operator\" \"private\" \"protected\" \"public\" \"return\" \"sizeof\" \"static\" \"struct\" \"switch\" \"template\" \"this\" \"throw\" \"try\" \"typedef\" \"typename\" \"union\" \"using\" \"virtual\" \"volatile\" \"while\"] @keyword\n"
    "[\"true\" \"false\" \"nullptr\"] @constant\n"
    "(comment) @comment\n"
    "(string_literal) @string\n"
    "(char_literal) @string\n"
    "(number_literal) @number\n"
    "(function_declarator declarator: (identifier) @function)\n"
    "(call_expression function: (identifier) @function.call)\n"
    "(type_identifier) @type\n"
    "(primitive_type) @type\n"
    "(field_identifier) @property\n"
    "(identifier) @variable\n";

static const char kQueryjava[] =
    "(line_comment) @comment\n"
    "(block_comment) @comment\n"
    "(string_literal) @string\n"
    "(character_literal) @string\n"
    "(decimal_integer_literal) @number\n"
    "(decimal_floating_point_literal) @number\n"
    "(method_declaration name: (identifier) @function)\n"
    "(type_identifier) @type\n"
    "(true) @constant\n"
    "(false) @constant\n"
    "(null_literal) @constant\n"
    "(field_access field: (identifier) @property)\n"
    "(identifier) @variable\n";

static const char kQueryjson[] =
    "(pair key: (string) @property)\n"
    "(string) @string\n"
    "(number) @number\n"
    "(true) @constant\n"
    "(false) @constant\n"
    "(null) @constant\n";

static const char kQuerybash[] =
    "(comment) @comment\n"
    "(string) @string\n"
    "(raw_string) @string\n"
    "(ansi_c_string) @string\n"
    "(number) @number\n"
    "(function_definition name: (word) @function)\n"
    "(variable_name) @variable\n";

static const char kQueryyaml[] =
    "(block_mapping_pair key: (_) @property)\n"
    "(comment) @comment\n"
    "(string_scalar) @string\n"
    "(double_quote_scalar) @string\n"
    "(single_quote_scalar) @string\n"
    "(integer_scalar) @number\n"
    "(float_scalar) @number\n"
    "(boolean_scalar) @constant\n"
    "(null_scalar) @constant\n";

static const char kQuerytoml[] =
    "(comment) @comment\n"
    "(string) @string\n"
    "(integer) @number\n"
    "(float) @number\n"
    "(boolean) @constant\n"
    "(bare_key) @property\n";

static const char kQuerymarkdown[] =
    "(atx_heading) @keyword\n"
    "(fenced_code_block) @string\n"
    "(link_destination) @string\n"
    "(link_label) @property\n";

static const LynaiTsLanguageEntry kLanguages[] = {
#ifdef LYNAI_TS_JAVASCRIPT
    LYNAI_TS_ENTRY_ALIASES_FN("javascript", kJavascriptAliases, tree_sitter_javascript, kQueryjavascript),
#endif
#ifdef LYNAI_TS_TYPESCRIPT
    LYNAI_TS_ENTRY_ALIASES_FN("typescript", kTypescriptAliases, tree_sitter_typescript, kQuerytypescript),
#endif
#ifdef LYNAI_TS_TSX
    LYNAI_TS_ENTRY("tsx", tree_sitter_tsx, kQuerytsx),
#endif
#ifdef LYNAI_TS_HTML
    LYNAI_TS_ENTRY("html", tree_sitter_html, kQueryhtml),
#endif
#ifdef LYNAI_TS_CSS
    LYNAI_TS_ENTRY("css", tree_sitter_css, kQuerycss),
#endif
#ifdef LYNAI_TS_PYTHON
    LYNAI_TS_ENTRY_ALIASES_FN("python", kPythonAliases, tree_sitter_python, kQuerypython),
#endif
#ifdef LYNAI_TS_GO
    LYNAI_TS_ENTRY_ALIASES_FN("go", kGoAliases, tree_sitter_go, kQuerygo),
#endif
#ifdef LYNAI_TS_RUST
    LYNAI_TS_ENTRY_ALIASES_FN("rust", kRustAliases, tree_sitter_rust, kQueryrust),
#endif
#ifdef LYNAI_TS_C
    LYNAI_TS_ENTRY("c", tree_sitter_c, kQueryc),
#endif
#ifdef LYNAI_TS_CPP
    LYNAI_TS_ENTRY_ALIASES_FN("cpp", kCppAliases, tree_sitter_cpp, kQuerycpp),
#endif
#ifdef LYNAI_TS_JAVA
    LYNAI_TS_ENTRY("java", tree_sitter_java, kQueryjava),
#endif
#ifdef LYNAI_TS_JSON
    LYNAI_TS_ENTRY("json", tree_sitter_json, kQueryjson),
#endif
#ifdef LYNAI_TS_BASH
    LYNAI_TS_ENTRY_ALIASES_FN("bash", kBashAliases, tree_sitter_bash, kQuerybash),
#endif
#ifdef LYNAI_TS_YAML
    LYNAI_TS_ENTRY_ALIASES_FN("yaml", kYamlAliases, tree_sitter_yaml, kQueryyaml),
#endif
#ifdef LYNAI_TS_TOML
    LYNAI_TS_ENTRY("toml", tree_sitter_toml, kQuerytoml),
#endif
#ifdef LYNAI_TS_MARKDOWN
    LYNAI_TS_ENTRY_ALIASES_FN("markdown", kMarkdownAliases, tree_sitter_markdown, kQuerymarkdown),
#endif
};

static const LynaiTsLanguageEntry* lynai_ts_find_language(const char* language) {
  if (language == 0) return 0;
  const unsigned long count = sizeof(kLanguages) / sizeof(kLanguages[0]);
  for (unsigned long i = 0; i < count; i++) {
    if (strcmp(language, kLanguages[i].id) == 0) return &kLanguages[i];
    for (int alias = 0; alias < kLanguages[i].alias_count; alias++) {
      if (strcmp(language, kLanguages[i].aliases[alias]) == 0) return &kLanguages[i];
    }
  }
  return 0;
}

int lynai_ts_available(void) {
  return lynai_ts_compiled_language_count() > 0 ? 1 : 0;
}

int lynai_ts_language_supported(const char* language) {
  return lynai_ts_find_language(language) != 0 ? 1 : 0;
}

int lynai_ts_compiled_language_count(void) {
  return (int)(sizeof(kLanguages) / sizeof(kLanguages[0]));
}

int lynai_ts_parse_summary(
    const char* language,
    const char* source,
    uint32_t source_length,
    LynaiTsParseSummary* out_summary) {
  if (out_summary == 0) return 0;
  memset(out_summary, 0, sizeof(LynaiTsParseSummary));
  const LynaiTsLanguageEntry* entry = lynai_ts_find_language(language);
  if (entry == 0 || source == 0 || entry->language_fn == 0) return 0;
  out_summary->supported = 1;

  TSParser* parser = ts_parser_new();
  if (parser == 0) return 0;
  if (!ts_parser_set_language(parser, entry->language_fn())) {
    ts_parser_delete(parser);
    return 0;
  }

  TSTree* tree = ts_parser_parse_string(
      parser,
      0,
      source,
      source_length);
  if (tree == 0) {
    ts_parser_delete(parser);
    return 0;
  }

  TSNode root = ts_tree_root_node(tree);
  out_summary->parsed = 1;
  out_summary->has_error = ts_node_has_error(root) ? 1 : 0;
  out_summary->root_child_count = ts_node_child_count(root);
  out_summary->root_start_byte = ts_node_start_byte(root);
  out_summary->root_end_byte = ts_node_end_byte(root);

  ts_tree_delete(tree);
  ts_parser_delete(parser);
  return 1;
}

static bool lynai_ts_is_one_of(const char* value, const char* const* items, int count) {
  for (int i = 0; i < count; i++) {
    if (strcmp(value, items[i]) == 0) return true;
  }
  return false;
}

static int32_t lynai_ts_token_kind_for_node(const char* type) {
  static const char* const keywords[] = {
      "abstract", "as", "async", "await", "break", "case", "catch",
      "class", "const", "continue", "default", "defer", "do", "else",
      "enum", "export", "extends", "false", "final", "finally", "fn",
      "for", "from", "func", "function", "go", "if", "implements",
      "import", "in", "interface", "is", "let", "match", "mod", "new",
      "nil", "null", "package", "private", "protected", "public", "return",
      "static", "struct", "super", "switch", "this", "throw", "trait",
      "true", "try", "type", "use", "var", "void", "while", "yield"};
  static const char* const strings[] = {
      "string", "string_content", "string_fragment", "raw_string_literal",
      "interpreted_string_literal", "escape_sequence", "character_literal",
      "template_string", "template_chars"};
  static const char* const comments[] = {"comment", "line_comment", "block_comment"};
  static const char* const numbers[] = {
      "number", "integer", "float", "decimal_integer_literal",
      "hex_integer_literal", "octal_integer_literal", "binary_integer_literal",
      "float_literal", "integer_literal"};
  static const char* const operators[] = {
      "+", "-", "*", "/", "%", "=", "==", "===", "!=", "!==", "<",
      "<=", ">", ">=", "=>", "->", "&&", "||", "!", "&", "|", "^",
      "~", "<<", ">>", "+=", "-=", "*=", "/=", "%=", "?", ":"};
  static const char* const punctuation[] = {
      ".", ",", ";", "(", ")", "[", "]", "{", "}", "`"};
  static const char* const types[] = {
      "type_identifier", "primitive_type", "predefined_type", "class_name",
      "struct_name", "enum_member", "enum_variant"};
  static const char* const functions[] = {
      "function", "function_name", "method", "method_name", "field_identifier"};
  static const char* const properties[] = {
      "property_identifier", "property_name", "attribute_name", "shorthand_property_identifier"};
  static const char* const tags[] = {"tag_name", "start_tag", "end_tag"};
  static const char* const attributes[] = {"attribute", "attribute_name"};

  if (lynai_ts_is_one_of(type, keywords, (int)(sizeof(keywords) / sizeof(keywords[0])))) {
    return LYNAI_TS_TOKEN_KEYWORD;
  }
  if (lynai_ts_is_one_of(type, strings, (int)(sizeof(strings) / sizeof(strings[0])))) {
    return LYNAI_TS_TOKEN_STRING;
  }
  if (lynai_ts_is_one_of(type, comments, (int)(sizeof(comments) / sizeof(comments[0])))) {
    return LYNAI_TS_TOKEN_COMMENT;
  }
  if (lynai_ts_is_one_of(type, numbers, (int)(sizeof(numbers) / sizeof(numbers[0])))) {
    return LYNAI_TS_TOKEN_NUMBER;
  }
  if (lynai_ts_is_one_of(type, operators, (int)(sizeof(operators) / sizeof(operators[0])))) {
    return LYNAI_TS_TOKEN_OPERATOR;
  }
  if (lynai_ts_is_one_of(type, punctuation, (int)(sizeof(punctuation) / sizeof(punctuation[0])))) {
    return LYNAI_TS_TOKEN_PUNCTUATION;
  }
  if (lynai_ts_is_one_of(type, types, (int)(sizeof(types) / sizeof(types[0])))) {
    return LYNAI_TS_TOKEN_TYPE;
  }
  if (lynai_ts_is_one_of(type, functions, (int)(sizeof(functions) / sizeof(functions[0])))) {
    return LYNAI_TS_TOKEN_FUNCTION;
  }
  if (lynai_ts_is_one_of(type, properties, (int)(sizeof(properties) / sizeof(properties[0])))) {
    return LYNAI_TS_TOKEN_PROPERTY;
  }
  if (lynai_ts_is_one_of(type, tags, (int)(sizeof(tags) / sizeof(tags[0])))) {
    return LYNAI_TS_TOKEN_TAG;
  }
  if (lynai_ts_is_one_of(type, attributes, (int)(sizeof(attributes) / sizeof(attributes[0])))) {
    return LYNAI_TS_TOKEN_ATTRIBUTE;
  }
  if (strcmp(type, "identifier") == 0 || strcmp(type, "variable_name") == 0) {
    return LYNAI_TS_TOKEN_VARIABLE;
  }
  if (strcmp(type, "constant") == 0 || strcmp(type, "constant_identifier") == 0) {
    return LYNAI_TS_TOKEN_CONSTANT;
  }
  return LYNAI_TS_TOKEN_UNKNOWN;
}

static bool lynai_ts_push_token(
    LynaiTsTokenBuffer* buffer,
    uint32_t start_byte,
    uint32_t end_byte,
    int32_t kind) {
  if (kind == LYNAI_TS_TOKEN_UNKNOWN || start_byte >= end_byte) return true;
  if (buffer->count == buffer->capacity) {
    uint32_t next_capacity = buffer->capacity == 0 ? 128 : buffer->capacity * 2;
    LynaiTsToken* next_items = (LynaiTsToken*)realloc(
        buffer->items,
        sizeof(LynaiTsToken) * next_capacity);
    if (next_items == 0) return false;
    buffer->items = next_items;
    buffer->capacity = next_capacity;
  }
  buffer->items[buffer->count].start_byte = start_byte;
  buffer->items[buffer->count].end_byte = end_byte;
  buffer->items[buffer->count].kind = kind;
  buffer->count++;
  return true;
}

static bool lynai_ts_collect_tokens(TSNode node, LynaiTsTokenBuffer* buffer) {
  uint32_t child_count = ts_node_child_count(node);
  if (child_count == 0) {
    const char* type = ts_node_type(node);
    return lynai_ts_push_token(
        buffer,
        ts_node_start_byte(node),
        ts_node_end_byte(node),
        lynai_ts_token_kind_for_node(type));
  }
  for (uint32_t i = 0; i < child_count; i++) {
    if (!lynai_ts_collect_tokens(ts_node_child(node, i), buffer)) return false;
  }
  return true;
}

static bool lynai_ts_collect_supplemental_leaf_tokens(
    TSNode node,
    LynaiTsTokenBuffer* buffer) {
  uint32_t child_count = ts_node_child_count(node);
  if (child_count == 0) {
    const int32_t kind = lynai_ts_token_kind_for_node(ts_node_type(node));
    if (kind != LYNAI_TS_TOKEN_KEYWORD &&
        kind != LYNAI_TS_TOKEN_OPERATOR &&
        kind != LYNAI_TS_TOKEN_PUNCTUATION &&
        kind != LYNAI_TS_TOKEN_CONSTANT) {
      return true;
    }
    return lynai_ts_push_token(
        buffer,
        ts_node_start_byte(node),
        ts_node_end_byte(node),
        kind);
  }
  for (uint32_t i = 0; i < child_count; i++) {
    if (!lynai_ts_collect_supplemental_leaf_tokens(ts_node_child(node, i), buffer)) {
      return false;
    }
  }
  return true;
}

static bool lynai_ts_capture_name_starts_with(
    const char* name,
    uint32_t length,
    const char* prefix) {
  const uint32_t prefix_length = (uint32_t)strlen(prefix);
  return length >= prefix_length && strncmp(name, prefix, prefix_length) == 0;
}

static int32_t lynai_ts_token_kind_for_capture(
    const char* name,
    uint32_t length) {
  if (lynai_ts_capture_name_starts_with(name, length, "keyword")) {
    return LYNAI_TS_TOKEN_KEYWORD;
  }
  if (lynai_ts_capture_name_starts_with(name, length, "string")) {
    return LYNAI_TS_TOKEN_STRING;
  }
  if (lynai_ts_capture_name_starts_with(name, length, "comment")) {
    return LYNAI_TS_TOKEN_COMMENT;
  }
  if (lynai_ts_capture_name_starts_with(name, length, "number")) {
    return LYNAI_TS_TOKEN_NUMBER;
  }
  if (lynai_ts_capture_name_starts_with(name, length, "operator")) {
    return LYNAI_TS_TOKEN_OPERATOR;
  }
  if (lynai_ts_capture_name_starts_with(name, length, "type")) {
    return LYNAI_TS_TOKEN_TYPE;
  }
  if (lynai_ts_capture_name_starts_with(name, length, "function")) {
    return LYNAI_TS_TOKEN_FUNCTION;
  }
  if (lynai_ts_capture_name_starts_with(name, length, "property")) {
    return LYNAI_TS_TOKEN_PROPERTY;
  }
  if (lynai_ts_capture_name_starts_with(name, length, "variable")) {
    return LYNAI_TS_TOKEN_VARIABLE;
  }
  if (lynai_ts_capture_name_starts_with(name, length, "constant")) {
    return LYNAI_TS_TOKEN_CONSTANT;
  }
  if (lynai_ts_capture_name_starts_with(name, length, "punctuation")) {
    return LYNAI_TS_TOKEN_PUNCTUATION;
  }
  if (lynai_ts_capture_name_starts_with(name, length, "tag")) {
    return LYNAI_TS_TOKEN_TAG;
  }
  if (lynai_ts_capture_name_starts_with(name, length, "attribute")) {
    return LYNAI_TS_TOKEN_ATTRIBUTE;
  }
  return LYNAI_TS_TOKEN_UNKNOWN;
}

static bool lynai_ts_collect_query_tokens(
    const LynaiTsLanguageEntry* entry,
    TSNode root,
    LynaiTsTokenBuffer* buffer) {
  if (entry->highlight_query == 0 || entry->highlight_query[0] == '\0') {
    return false;
  }

  uint32_t error_offset = 0;
  TSQueryError error_type = TSQueryErrorNone;
  TSQuery* query = ts_query_new(
      entry->language_fn(),
      entry->highlight_query,
      (uint32_t)strlen(entry->highlight_query),
      &error_offset,
      &error_type);
  if (query == 0 || error_type != TSQueryErrorNone) {
    if (query != 0) ts_query_delete(query);
    return false;
  }

  TSQueryCursor* cursor = ts_query_cursor_new();
  if (cursor == 0) {
    ts_query_delete(query);
    return false;
  }

  bool ok = true;
  TSQueryMatch match;
  uint32_t capture_index = 0;
  ts_query_cursor_exec(cursor, query, root);
  while (ts_query_cursor_next_capture(cursor, &match, &capture_index)) {
    TSQueryCapture capture = match.captures[capture_index];
    uint32_t capture_name_length = 0;
    const char* capture_name = ts_query_capture_name_for_id(
        query,
        capture.index,
        &capture_name_length);
    const int32_t kind = lynai_ts_token_kind_for_capture(
        capture_name,
        capture_name_length);
    if (!lynai_ts_push_token(
            buffer,
            ts_node_start_byte(capture.node),
            ts_node_end_byte(capture.node),
            kind)) {
      ok = false;
      break;
    }
  }

  ts_query_cursor_delete(cursor);
  ts_query_delete(query);
  return ok && buffer->count > 0;
}

int lynai_ts_highlight_tokens(
    const char* language,
    const char* source,
    uint32_t source_length,
    LynaiTsHighlightResult* out_result) {
  if (out_result == 0) return 0;
  memset(out_result, 0, sizeof(LynaiTsHighlightResult));
  const LynaiTsLanguageEntry* entry = lynai_ts_find_language(language);
  if (entry == 0 || source == 0 || entry->language_fn == 0) return 0;
  out_result->supported = 1;

  TSParser* parser = ts_parser_new();
  if (parser == 0) return 0;
  if (!ts_parser_set_language(parser, entry->language_fn())) {
    ts_parser_delete(parser);
    return 0;
  }
  TSTree* tree = ts_parser_parse_string(parser, 0, source, source_length);
  if (tree == 0) {
    ts_parser_delete(parser);
    return 0;
  }

  TSNode root = ts_tree_root_node(tree);
  LynaiTsTokenBuffer buffer = {0, 0, 0};
  bool collected = lynai_ts_collect_query_tokens(entry, root, &buffer);
  if (collected) {
    collected = lynai_ts_collect_supplemental_leaf_tokens(root, &buffer);
  } else {
    free(buffer.items);
    buffer.items = 0;
    buffer.count = 0;
    buffer.capacity = 0;
    collected = lynai_ts_collect_tokens(root, &buffer);
  }
  out_result->parsed = collected ? 1 : 0;
  out_result->has_error = ts_node_has_error(root) ? 1 : 0;
  if (collected) {
    out_result->token_count = buffer.count;
    out_result->tokens = buffer.items;
  } else {
    free(buffer.items);
  }

  ts_tree_delete(tree);
  ts_parser_delete(parser);
  return collected ? 1 : 0;
}

void lynai_ts_free_highlight_result(LynaiTsHighlightResult* result) {
  if (result == 0) return;
  free(result->tokens);
  result->tokens = 0;
  result->token_count = 0;
}
