cmake_minimum_required(VERSION 3.14)

project(lynai_tree_sitter LANGUAGES C CXX)

if(POLICY CMP0169)
  cmake_policy(SET CMP0169 OLD)
endif()

include(FetchContent)

set(FETCHCONTENT_QUIET FALSE)

# FetchContent sources are shared across ABIs and build types so a clean
# multi-ABI release build clones each grammar exactly once instead of once per
# ABI. The cache lives next to CMakeLists.txt (ignored by git) and is keyed by
# the content name, so different tags still land in separate subdirectories.
set(LYNAI_TS_FETCH_CACHE "${CMAKE_CURRENT_SOURCE_DIR}/.fetch-cache")
set(FETCHCONTENT_BASE_DIR "${LYNAI_TS_FETCH_CACHE}")
file(MAKE_DIRECTORY "${LYNAI_TS_FETCH_CACHE}")

# Grammars are fetched at configure time instead of vendored into the Flutter
# tree. The facade exports one stable library for Dart FFI, while unsupported
# languages safely fall back to the existing Dart highlighter.
#
# FetchContent_Populate is guarded by a per-name content lock so concurrent
# Ninja jobs (one per ABI) never race on the same git clone. The lock is
# released automatically when the function returns.
function(lynai_fetch_tree_sitter NAME REPOSITORY TAG)
  FetchContent_Declare(
    ${NAME}
    GIT_REPOSITORY ${REPOSITORY}
    GIT_TAG ${TAG}
    GIT_SHALLOW TRUE
  )
  file(LOCK "${LYNAI_TS_FETCH_CACHE}/${NAME}.lock" GUARD PROCESS RESULT_VARIABLE _lock_result)
  FetchContent_Populate(${NAME})
  if(_lock_result EQUAL 0)
    file(LOCK "${LYNAI_TS_FETCH_CACHE}/${NAME}.lock" RELEASE)
  endif()
  set(${NAME}_SOURCE_DIR "${${NAME}_SOURCE_DIR}" PARENT_SCOPE)
endfunction()

set(LYNAI_TS_SOURCES lynai_tree_sitter.c)
set(LYNAI_TS_INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR})
set(LYNAI_TS_DEFINITIONS)

lynai_fetch_tree_sitter(ts_core https://github.com/tree-sitter/tree-sitter.git v0.25.10)
list(APPEND LYNAI_TS_SOURCES ${ts_core_SOURCE_DIR}/lib/src/lib.c)
list(APPEND LYNAI_TS_INCLUDE_DIRS ${ts_core_SOURCE_DIR}/lib/include ${ts_core_SOURCE_DIR}/lib/src)

function(lynai_add_grammar NAME REPOSITORY TAG)
  set(options)
  set(oneValueArgs ROOT SYMBOL)
  set(multiValueArgs SOURCES)
  cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
  lynai_fetch_tree_sitter(${NAME} ${REPOSITORY} ${TAG})
  if(ARG_ROOT)
    set(grammar_root "${${NAME}_SOURCE_DIR}/${ARG_ROOT}")
  else()
    set(grammar_root "${${NAME}_SOURCE_DIR}")
  endif()
  foreach(source ${ARG_SOURCES})
    list(APPEND LYNAI_TS_SOURCES "${grammar_root}/${source}")
  endforeach()
  list(APPEND LYNAI_TS_INCLUDE_DIRS "${grammar_root}/src")
  if(ARG_SYMBOL)
    list(APPEND LYNAI_TS_DEFINITIONS "${ARG_SYMBOL}=1")
  endif()
  set(LYNAI_TS_SOURCES "${LYNAI_TS_SOURCES}" PARENT_SCOPE)
  set(LYNAI_TS_INCLUDE_DIRS "${LYNAI_TS_INCLUDE_DIRS}" PARENT_SCOPE)
  set(LYNAI_TS_DEFINITIONS "${LYNAI_TS_DEFINITIONS}" PARENT_SCOPE)
endfunction()

lynai_add_grammar(ts_javascript https://github.com/tree-sitter/tree-sitter-javascript.git v0.25.0 SYMBOL LYNAI_TS_JAVASCRIPT SOURCES src/parser.c src/scanner.c)
lynai_add_grammar(ts_typescript https://github.com/tree-sitter/tree-sitter-typescript.git v0.23.2 ROOT typescript SYMBOL LYNAI_TS_TYPESCRIPT SOURCES src/parser.c src/scanner.c)
lynai_add_grammar(ts_tsx https://github.com/tree-sitter/tree-sitter-typescript.git v0.23.2 ROOT tsx SYMBOL LYNAI_TS_TSX SOURCES src/parser.c src/scanner.c)
lynai_add_grammar(ts_html https://github.com/tree-sitter/tree-sitter-html.git v0.23.2 SYMBOL LYNAI_TS_HTML SOURCES src/parser.c src/scanner.c)
lynai_add_grammar(ts_css https://github.com/tree-sitter/tree-sitter-css.git v0.23.2 SYMBOL LYNAI_TS_CSS SOURCES src/parser.c src/scanner.c)
lynai_add_grammar(ts_python https://github.com/tree-sitter/tree-sitter-python.git v0.23.6 SYMBOL LYNAI_TS_PYTHON SOURCES src/parser.c src/scanner.c)
lynai_add_grammar(ts_go https://github.com/tree-sitter/tree-sitter-go.git v0.23.4 SYMBOL LYNAI_TS_GO SOURCES src/parser.c)
lynai_add_grammar(ts_rust https://github.com/tree-sitter/tree-sitter-rust.git v0.24.0 SYMBOL LYNAI_TS_RUST SOURCES src/parser.c src/scanner.c)
lynai_add_grammar(ts_c https://github.com/tree-sitter/tree-sitter-c.git v0.23.6 SYMBOL LYNAI_TS_C SOURCES src/parser.c)
lynai_add_grammar(ts_cpp https://github.com/tree-sitter/tree-sitter-cpp.git v0.23.4 SYMBOL LYNAI_TS_CPP SOURCES src/parser.c src/scanner.c)
lynai_add_grammar(ts_java https://github.com/tree-sitter/tree-sitter-java.git v0.23.5 SYMBOL LYNAI_TS_JAVA SOURCES src/parser.c)
lynai_add_grammar(ts_json https://github.com/tree-sitter/tree-sitter-json.git v0.24.8 SYMBOL LYNAI_TS_JSON SOURCES src/parser.c)
lynai_add_grammar(ts_bash https://github.com/tree-sitter/tree-sitter-bash.git v0.25.0 SYMBOL LYNAI_TS_BASH SOURCES src/parser.c src/scanner.c)
lynai_add_grammar(ts_yaml https://github.com/tree-sitter-grammars/tree-sitter-yaml.git v0.7.1 SYMBOL LYNAI_TS_YAML SOURCES src/parser.c src/scanner.c)
lynai_add_grammar(ts_toml https://github.com/tree-sitter-grammars/tree-sitter-toml.git v0.7.0 SYMBOL LYNAI_TS_TOML SOURCES src/parser.c src/scanner.c)
lynai_add_grammar(ts_markdown https://github.com/tree-sitter-grammars/tree-sitter-markdown.git v0.5.1 ROOT tree-sitter-markdown SYMBOL LYNAI_TS_MARKDOWN SOURCES src/parser.c src/scanner.c)

add_library(lynai_tree_sitter SHARED ${LYNAI_TS_SOURCES})

target_include_directories(lynai_tree_sitter PUBLIC ${LYNAI_TS_INCLUDE_DIRS})

target_compile_definitions(lynai_tree_sitter PRIVATE TREE_SITTER_HIDE_SYMBOLS ${LYNAI_TS_DEFINITIONS})

if(MSVC)
  target_compile_options(lynai_tree_sitter PRIVATE /W3)
else()
  target_compile_options(lynai_tree_sitter PRIVATE -Wall -Wextra -Wno-unused-parameter)
endif()
