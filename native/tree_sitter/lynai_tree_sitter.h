#ifndef LYNAI_TREE_SITTER_H_
#define LYNAI_TREE_SITTER_H_

#include <stdint.h>

#ifdef _WIN32
#define LYNAI_TS_EXPORT __declspec(dllexport)
#else
#define LYNAI_TS_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct LynaiTsParseSummary {
  int32_t supported;
  int32_t parsed;
  int32_t has_error;
  uint32_t root_child_count;
  uint32_t root_start_byte;
  uint32_t root_end_byte;
} LynaiTsParseSummary;

typedef enum LynaiTsTokenKind {
  LYNAI_TS_TOKEN_UNKNOWN = 0,
  LYNAI_TS_TOKEN_KEYWORD = 1,
  LYNAI_TS_TOKEN_STRING = 2,
  LYNAI_TS_TOKEN_COMMENT = 3,
  LYNAI_TS_TOKEN_NUMBER = 4,
  LYNAI_TS_TOKEN_OPERATOR = 5,
  LYNAI_TS_TOKEN_TYPE = 6,
  LYNAI_TS_TOKEN_FUNCTION = 7,
  LYNAI_TS_TOKEN_PROPERTY = 8,
  LYNAI_TS_TOKEN_VARIABLE = 9,
  LYNAI_TS_TOKEN_CONSTANT = 10,
  LYNAI_TS_TOKEN_PUNCTUATION = 11,
  LYNAI_TS_TOKEN_TAG = 12,
  LYNAI_TS_TOKEN_ATTRIBUTE = 13,
} LynaiTsTokenKind;

typedef struct LynaiTsToken {
  uint32_t start_byte;
  uint32_t end_byte;
  int32_t kind;
} LynaiTsToken;

typedef struct LynaiTsHighlightResult {
  int32_t supported;
  int32_t parsed;
  int32_t has_error;
  uint32_t token_count;
  LynaiTsToken* tokens;
} LynaiTsHighlightResult;

LYNAI_TS_EXPORT int lynai_ts_available(void);
LYNAI_TS_EXPORT int lynai_ts_language_supported(const char* language);
LYNAI_TS_EXPORT int lynai_ts_compiled_language_count(void);
LYNAI_TS_EXPORT int lynai_ts_parse_summary(
    const char* language,
    const char* source,
    uint32_t source_length,
    LynaiTsParseSummary* out_summary);
LYNAI_TS_EXPORT int lynai_ts_highlight_tokens(
    const char* language,
    const char* source,
    uint32_t source_length,
    LynaiTsHighlightResult* out_result);
LYNAI_TS_EXPORT void lynai_ts_free_highlight_result(
    LynaiTsHighlightResult* result);

#ifdef __cplusplus
}
#endif

#endif
