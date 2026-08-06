/*
 * Offline Tree-sitter highlighter for pumd.
 *
 * This file is intentionally a narrow C ABI. C owns language-tag routing;
 * MoonBit owns UTF-8-to-text-run conversion, styling, and all fallback
 * presentation. A negative result is therefore an ordinary "use the existing
 * plain-code run" result, never an error path.
 */
#if defined(PUMD_STANDALONE)
#include <stdint.h>
typedef uint8_t *moonbit_bytes_t;
#define MOONBIT_FFI_EXPORT
#else
#include <moonbit.h>
#endif

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "vendor/tree-sitter/runtime/include/tree_sitter/api.h"
#include "vendor/tree-sitter/generated/highlight_queries.h"

enum {
  PUMD_HIGHLIGHT_RECORD_BYTES = 12,
  PUMD_HIGHLIGHT_MAX_CAPTURES = 1000000,
  PUMD_HIGHLIGHT_UNKNOWN_LANGUAGE = -1,
  PUMD_HIGHLIGHT_PARSE_FAILURE = -2,
  PUMD_HIGHLIGHT_QUERY_FAILURE = -3,
  PUMD_HIGHLIGHT_OUTPUT_FAILURE = -4,
  PUMD_HIGHLIGHT_INTERNAL_FAILURE = -5,
};

/* Stable project-owned semantic token IDs. Do not expose capture names. */
enum PumdSemanticToken {
  PUMD_TOKEN_KEYWORD = 1,
  PUMD_TOKEN_STRING = 2,
  PUMD_TOKEN_TYPE = 3,
  PUMD_TOKEN_FUNCTION = 4,
  PUMD_TOKEN_PROPERTY = 5,
  PUMD_TOKEN_NUMBER = 6,
  PUMD_TOKEN_COMMENT = 7,
  PUMD_TOKEN_TAG = 8,
  PUMD_TOKEN_ATTRIBUTE = 9,
  PUMD_TOKEN_OPERATOR = 10,
  PUMD_TOKEN_PUNCTUATION = 11,
};

typedef struct {
  uint32_t start_byte;
  uint32_t end_byte;
  uint32_t token;
} PumdHighlightSpan;

typedef struct {
  PumdHighlightSpan *items;
  size_t length;
  size_t capacity;
} PumdSpanList;

typedef struct {
  const TSLanguage *language;
  const unsigned char *query;
  uint32_t query_length;
  const unsigned char *supplement;
  uint32_t supplement_length;
  int html_injections;
} PumdLanguageSpec;

typedef struct {
  const char *canonical_tag;
  const char *revision;
  const char *spdx_license;
  const TSLanguage *(*language_factory)(void);
  const unsigned char *query;
  uint32_t query_length;
  const unsigned char *supplement;
  uint32_t supplement_length;
  int html_injections;
} PumdVendorSpec;

extern const TSLanguage *tree_sitter_javascript(void);
extern const TSLanguage *tree_sitter_typescript(void);
extern const TSLanguage *tree_sitter_tsx(void);
extern const TSLanguage *tree_sitter_bash(void);
extern const TSLanguage *tree_sitter_powershell(void);
extern const TSLanguage *tree_sitter_json(void);
extern const TSLanguage *tree_sitter_yaml(void);
extern const TSLanguage *tree_sitter_toml(void);
extern const TSLanguage *tree_sitter_html(void);
extern const TSLanguage *tree_sitter_css(void);
extern const TSLanguage *tree_sitter_xml(void);
extern const TSLanguage *tree_sitter_sql(void);
extern const TSLanguage *tree_sitter_markdown(void);
extern const TSLanguage *tree_sitter_http(void);
extern const TSLanguage *tree_sitter_proto(void);

enum PumdVendorSpecIndex {
  PUMD_VENDOR_JAVASCRIPT,
  PUMD_VENDOR_JSX,
  PUMD_VENDOR_TYPESCRIPT,
  PUMD_VENDOR_TSX,
  PUMD_VENDOR_SHELL,
  PUMD_VENDOR_POWERSHELL,
  PUMD_VENDOR_JSON,
  PUMD_VENDOR_YAML,
  PUMD_VENDOR_TOML,
  PUMD_VENDOR_HTML,
  PUMD_VENDOR_CSS,
  PUMD_VENDOR_XML,
  PUMD_VENDOR_SQL,
  PUMD_VENDOR_MARKDOWN,
  PUMD_VENDOR_HTTP,
  PUMD_VENDOR_PROTOBUF,
  PUMD_VENDOR_SPEC_COUNT,
};

/*
 * This is the executable source of truth for bundled parser assets. Keep its
 * revision and SPDX fields aligned with vendor/tree-sitter/INVENTORY.md.
 */
static const PumdVendorSpec pumd_vendor_specs[PUMD_VENDOR_SPEC_COUNT] = {
    {"javascript", "58404d8cf191d69f2674a8fd507bd5776f46cb11", "MIT",
     tree_sitter_javascript, pumd_query_javascript,
     (uint32_t)sizeof(pumd_query_javascript), NULL, 0, 0},
    {"jsx", "58404d8cf191d69f2674a8fd507bd5776f46cb11", "MIT",
     tree_sitter_javascript, pumd_query_javascript,
     (uint32_t)sizeof(pumd_query_javascript), pumd_query_javascript_jsx,
     (uint32_t)sizeof(pumd_query_javascript_jsx), 0},
    {"typescript", "75b3874edb2dc714fb1fd77a32013d0f8699989f", "MIT",
     tree_sitter_typescript, pumd_query_javascript,
     (uint32_t)sizeof(pumd_query_javascript), pumd_query_typescript,
     (uint32_t)sizeof(pumd_query_typescript), 0},
    {"tsx", "75b3874edb2dc714fb1fd77a32013d0f8699989f", "MIT",
     tree_sitter_tsx, pumd_query_javascript,
     (uint32_t)sizeof(pumd_query_javascript), pumd_query_tsx,
     (uint32_t)sizeof(pumd_query_tsx), 0},
    {"shell", "a06c2e4415e9bc0346c6b86d401879ffb44058f7", "MIT",
     tree_sitter_bash, pumd_query_bash, (uint32_t)sizeof(pumd_query_bash), NULL,
     0, 0},
    {"powershell", "e7bd348c49fdfd5c853a146a670965ba516a6239", "MIT",
     tree_sitter_powershell, pumd_query_powershell,
     (uint32_t)sizeof(pumd_query_powershell), NULL, 0, 0},
    {"json", "001c28d7a29832b06b0e831ec77845553c89b56d", "MIT",
     tree_sitter_json, pumd_query_json, (uint32_t)sizeof(pumd_query_json), NULL,
     0, 0},
    {"yaml", "a1c4812a73ec5e089de8e441fdea3a921e8d5079", "MIT",
     tree_sitter_yaml, pumd_query_yaml, (uint32_t)sizeof(pumd_query_yaml), NULL,
     0, 0},
    {"toml", "64b56832c2cffe41758f28e05c756a3a98d16f41", "MIT",
     tree_sitter_toml, pumd_query_toml, (uint32_t)sizeof(pumd_query_toml), NULL,
     0, 0},
    {"html", "73a3947324f6efddf9e17c0ea58d454843590cc0", "MIT",
     tree_sitter_html, pumd_query_html, (uint32_t)sizeof(pumd_query_html), NULL,
     0, 1},
    {"css", "dda5cfc5722c429eaba1c910ca32c2c0c5bb1a3f", "MIT",
     tree_sitter_css, pumd_query_css, (uint32_t)sizeof(pumd_query_css), NULL, 0,
     0},
    {"xml", "5000ae8f22d11fbe93939b05c1e37cf21117162d", "MIT",
     tree_sitter_xml, pumd_query_xml, (uint32_t)sizeof(pumd_query_xml), NULL, 0,
     0},
    {"sql", "c2e1e08db1ea20dc23bdb8d228a81a8756e9c450", "MIT",
     tree_sitter_sql, pumd_query_sql, (uint32_t)sizeof(pumd_query_sql), NULL, 0,
     0},
    {"markdown", "a0a00f817d02412bd92c54d316f164d827b57b5c", "MIT",
     tree_sitter_markdown, pumd_query_markdown,
     (uint32_t)sizeof(pumd_query_markdown), NULL, 0, 0},
    {"http", "db8b4398de90b6d0b6c780aba96aaa2cd8e9202c", "MIT",
     tree_sitter_http, pumd_query_http, (uint32_t)sizeof(pumd_query_http), NULL,
     0, 0},
    {"protobuf", "42d82fa18f8afe59b5fc0b16c207ee4f84cb185f", "MIT",
     tree_sitter_proto, pumd_query_protobuf,
     (uint32_t)sizeof(pumd_query_protobuf), NULL, 0, 0},
};

static PumdLanguageSpec pumd_spec_from_vendor(const PumdVendorSpec *vendor) {
  return (PumdLanguageSpec){vendor->language_factory(), vendor->query,
                            vendor->query_length, vendor->supplement,
                            vendor->supplement_length,
                            vendor->html_injections};
}

static PumdLanguageSpec pumd_spec_for(const uint8_t *language, int32_t length,
                                      int *is_console);

static int pumd_bytes_equal(const uint8_t *value, int32_t length,
                            const char *literal) {
  size_t literal_length = strlen(literal);
  size_t index;
  if (length < 0 || (size_t)length != literal_length) return 0;
  for (index = 0; index < literal_length; index++) {
    uint8_t byte = value[index];
    if (byte >= 'A' && byte <= 'Z') byte = (uint8_t)(byte + ('a' - 'A'));
    if (byte != (uint8_t)literal[index]) return 0;
  }
  return 1;
}

static int pumd_span_list_push(PumdSpanList *list, uint32_t start_byte,
                               uint32_t end_byte, uint32_t token) {
  PumdHighlightSpan *items;
  size_t capacity;
  if (start_byte >= end_byte || list->length >= PUMD_HIGHLIGHT_MAX_CAPTURES) {
    return 0;
  }
  if (list->length == list->capacity) {
    capacity = list->capacity == 0 ? 64 : list->capacity * 2;
    if (capacity < list->capacity ||
        capacity > SIZE_MAX / sizeof(PumdHighlightSpan)) {
      return 0;
    }
    items = (PumdHighlightSpan *)realloc(
        list->items, capacity * sizeof(PumdHighlightSpan));
    if (items == NULL) return 0;
    list->items = items;
    list->capacity = capacity;
  }
  list->items[list->length].start_byte = start_byte;
  list->items[list->length].end_byte = end_byte;
  list->items[list->length].token = token;
  list->length++;
  return 1;
}

static int pumd_capture_token(const char *name, uint32_t length,
                              uint32_t *token) {
  /* Prefix mapping deliberately absorbs grammar-specific suffixes. */
#define PUMD_CAPTURE(prefix, value)                                           \
  if (length >= sizeof(prefix) - 1 &&                                         \
      memcmp(name, prefix, sizeof(prefix) - 1) == 0 &&                        \
      (length == sizeof(prefix) - 1 || name[sizeof(prefix) - 1] == '.')) {   \
    *token = value;                                                            \
    return 1;                                                                  \
  }
  PUMD_CAPTURE("comment", PUMD_TOKEN_COMMENT)
  PUMD_CAPTURE("string", PUMD_TOKEN_STRING)
  PUMD_CAPTURE("character", PUMD_TOKEN_STRING)
  PUMD_CAPTURE("escape", PUMD_TOKEN_STRING)
  PUMD_CAPTURE("keyword", PUMD_TOKEN_KEYWORD)
  PUMD_CAPTURE("conditional", PUMD_TOKEN_KEYWORD)
  PUMD_CAPTURE("repeat", PUMD_TOKEN_KEYWORD)
  PUMD_CAPTURE("exception", PUMD_TOKEN_KEYWORD)
  PUMD_CAPTURE("include", PUMD_TOKEN_KEYWORD)
  PUMD_CAPTURE("storageclass", PUMD_TOKEN_KEYWORD)
  PUMD_CAPTURE("type", PUMD_TOKEN_TYPE)
  PUMD_CAPTURE("constructor", PUMD_TOKEN_TYPE)
  PUMD_CAPTURE("function", PUMD_TOKEN_FUNCTION)
  PUMD_CAPTURE("method", PUMD_TOKEN_FUNCTION)
  PUMD_CAPTURE("property", PUMD_TOKEN_PROPERTY)
  PUMD_CAPTURE("field", PUMD_TOKEN_PROPERTY)
  PUMD_CAPTURE("variable.parameter", PUMD_TOKEN_PROPERTY)
  PUMD_CAPTURE("number", PUMD_TOKEN_NUMBER)
  PUMD_CAPTURE("float", PUMD_TOKEN_NUMBER)
  PUMD_CAPTURE("boolean", PUMD_TOKEN_NUMBER)
  PUMD_CAPTURE("constant", PUMD_TOKEN_NUMBER)
  PUMD_CAPTURE("text.title", PUMD_TOKEN_TYPE)
  PUMD_CAPTURE("tag", PUMD_TOKEN_TAG)
  PUMD_CAPTURE("attribute", PUMD_TOKEN_ATTRIBUTE)
  PUMD_CAPTURE("operator", PUMD_TOKEN_OPERATOR)
  PUMD_CAPTURE("punctuation", PUMD_TOKEN_PUNCTUATION)
#undef PUMD_CAPTURE
  return 0;
}

static int pumd_span_compare(const void *left, const void *right) {
  const PumdHighlightSpan *a = (const PumdHighlightSpan *)left;
  const PumdHighlightSpan *b = (const PumdHighlightSpan *)right;
  if (a->start_byte != b->start_byte)
    return a->start_byte < b->start_byte ? -1 : 1;
  /* Prefer the containing capture; then use the stable project token ID. */
  if (a->end_byte != b->end_byte) return a->end_byte > b->end_byte ? -1 : 1;
  if (a->token != b->token) return a->token < b->token ? -1 : 1;
  return 0;
}

static int pumd_is_utf8_boundary(const uint8_t *source, uint32_t length,
                                 uint32_t offset) {
  return offset <= length &&
         (offset == length || (source[offset] & 0xC0u) != 0x80u);
}

static int pumd_normalize_spans(PumdSpanList *list, const uint8_t *source,
                                uint32_t source_length) {
  size_t read_index;
  size_t write_index = 0;
  uint32_t last_end = 0;
  qsort(list->items, list->length, sizeof(PumdHighlightSpan), pumd_span_compare);
  for (read_index = 0; read_index < list->length; read_index++) {
    PumdHighlightSpan span = list->items[read_index];
    if (span.end_byte > source_length || span.start_byte < last_end ||
        !pumd_is_utf8_boundary(source, source_length, span.start_byte) ||
        !pumd_is_utf8_boundary(source, source_length, span.end_byte)) {
      if (span.end_byte > source_length ||
          !pumd_is_utf8_boundary(source, source_length, span.start_byte) ||
          !pumd_is_utf8_boundary(source, source_length, span.end_byte))
        return 0;
      continue;
    }
    if (write_index > 0 &&
        list->items[write_index - 1].end_byte == span.start_byte &&
        list->items[write_index - 1].token == span.token) {
      list->items[write_index - 1].end_byte = span.end_byte;
    } else {
      list->items[write_index++] = span;
    }
    last_end = span.end_byte;
  }
  list->length = write_index;
  return 1;
}

static int pumd_add_query_spans_to_tree(const PumdLanguageSpec *spec,
                                        TSTree *tree, uint32_t offset,
                                        PumdSpanList *spans) {
  TSQuery *query = NULL;
  TSQueryCursor *cursor = NULL;
  TSQueryError query_error;
  uint32_t query_error_offset;
  TSQueryMatch match;
  unsigned char *combined_query = NULL;
  const unsigned char *query_source = spec->query;
  uint32_t query_length = spec->query_length;
  int result = PUMD_HIGHLIGHT_INTERNAL_FAILURE;

  if (tree == NULL || spec->language == NULL || query_source == NULL)
    return PUMD_HIGHLIGHT_INTERNAL_FAILURE;
  if (spec->supplement != NULL) {
    uint64_t combined_length = (uint64_t)query_length + spec->supplement_length + 1;
    if (combined_length > UINT32_MAX) return PUMD_HIGHLIGHT_QUERY_FAILURE;
    combined_query = (unsigned char *)malloc((size_t)combined_length);
    if (combined_query == NULL) return PUMD_HIGHLIGHT_INTERNAL_FAILURE;
    memcpy(combined_query, query_source, query_length);
    combined_query[query_length] = '\n';
    memcpy(combined_query + query_length + 1, spec->supplement,
           spec->supplement_length);
    query_source = combined_query;
    query_length = (uint32_t)combined_length;
  }

  query = ts_query_new(spec->language, (const char *)query_source, query_length,
                       &query_error_offset, &query_error);
  if (query == NULL) {
    result = PUMD_HIGHLIGHT_QUERY_FAILURE;
    goto done;
  }
  cursor = ts_query_cursor_new();
  if (cursor == NULL) goto done;
  ts_query_cursor_set_match_limit(cursor, PUMD_HIGHLIGHT_MAX_CAPTURES);
  ts_query_cursor_exec(cursor, query, ts_tree_root_node(tree));
  while (ts_query_cursor_next_match(cursor, &match)) {
    uint16_t capture_index;
    uint32_t predicate_count = 0;
    /* Tree-sitter exposes predicates but does not evaluate them for us. */
    (void)ts_query_predicates_for_pattern(query, match.pattern_index,
                                          &predicate_count);
    if (predicate_count != 0) continue;
    for (capture_index = 0; capture_index < match.capture_count; capture_index++) {
      const TSQueryCapture *capture = &match.captures[capture_index];
      uint32_t name_length = 0;
      uint32_t token;
      const char *name = ts_query_capture_name_for_id(query, capture->index,
                                                       &name_length);
      uint32_t start_byte;
      uint32_t end_byte;
      if (name == NULL || !pumd_capture_token(name, name_length, &token))
        continue;
      start_byte = ts_node_start_byte(capture->node);
      end_byte = ts_node_end_byte(capture->node);
      /* Queries may capture an absent optional token; it has no native run. */
      if (start_byte == end_byte) continue;
      if (start_byte > UINT32_MAX - offset || end_byte > UINT32_MAX - offset ||
          !pumd_span_list_push(spans, start_byte + offset, end_byte + offset,
                               token)) {
        result = PUMD_HIGHLIGHT_INTERNAL_FAILURE;
        goto done;
      }
    }
  }
  if (ts_query_cursor_did_exceed_match_limit(cursor)) {
    result = PUMD_HIGHLIGHT_QUERY_FAILURE;
    goto done;
  }
  result = 0;

done:
  if (cursor != NULL) ts_query_cursor_delete(cursor);
  if (query != NULL) ts_query_delete(query);
  free(combined_query);
  return result;
}

static int pumd_add_query_spans(const PumdLanguageSpec *spec,
                                const uint8_t *source, uint32_t source_length,
                                uint32_t offset, PumdSpanList *spans) {
  TSParser *parser = NULL;
  TSTree *tree = NULL;
  int result = PUMD_HIGHLIGHT_INTERNAL_FAILURE;
  if (source_length > INT32_MAX) return PUMD_HIGHLIGHT_INTERNAL_FAILURE;
  parser = ts_parser_new();
  if (parser == NULL || !ts_parser_set_language(parser, spec->language)) goto done;
  tree = ts_parser_parse_string_encoding(parser, NULL, (const char *)source,
                                         source_length, TSInputEncodingUTF8);
  if (tree == NULL) {
    result = PUMD_HIGHLIGHT_PARSE_FAILURE;
    goto done;
  }
  result = pumd_add_query_spans_to_tree(spec, tree, offset, spans);
done:
  if (tree != NULL) ts_tree_delete(tree);
  if (parser != NULL) ts_parser_delete(parser);
  return result;
}

static PumdLanguageSpec pumd_spec_for(const uint8_t *language, int32_t length,
                                      int *is_console) {
  *is_console = 0;
#define PUMD_ALIAS(name, index)                                                \
  if (pumd_bytes_equal(language, length, name))                                \
    return pumd_spec_from_vendor(&pumd_vendor_specs[index]);
  PUMD_ALIAS("javascript", PUMD_VENDOR_JAVASCRIPT)
  PUMD_ALIAS("js", PUMD_VENDOR_JAVASCRIPT)
  PUMD_ALIAS("jsx", PUMD_VENDOR_JSX)
  PUMD_ALIAS("typescript", PUMD_VENDOR_TYPESCRIPT)
  PUMD_ALIAS("ts", PUMD_VENDOR_TYPESCRIPT)
  PUMD_ALIAS("tsx", PUMD_VENDOR_TSX)
  PUMD_ALIAS("shell", PUMD_VENDOR_SHELL)
  PUMD_ALIAS("sh", PUMD_VENDOR_SHELL)
  PUMD_ALIAS("bash", PUMD_VENDOR_SHELL)
  PUMD_ALIAS("zsh", PUMD_VENDOR_SHELL)
  PUMD_ALIAS("powershell", PUMD_VENDOR_POWERSHELL)
  PUMD_ALIAS("ps1", PUMD_VENDOR_POWERSHELL)
  PUMD_ALIAS("json", PUMD_VENDOR_JSON)
  PUMD_ALIAS("yaml", PUMD_VENDOR_YAML)
  PUMD_ALIAS("yml", PUMD_VENDOR_YAML)
  PUMD_ALIAS("toml", PUMD_VENDOR_TOML)
  PUMD_ALIAS("html", PUMD_VENDOR_HTML)
  PUMD_ALIAS("css", PUMD_VENDOR_CSS)
  PUMD_ALIAS("xml", PUMD_VENDOR_XML)
  PUMD_ALIAS("sql", PUMD_VENDOR_SQL)
  PUMD_ALIAS("markdown", PUMD_VENDOR_MARKDOWN)
  PUMD_ALIAS("md", PUMD_VENDOR_MARKDOWN)
  PUMD_ALIAS("http", PUMD_VENDOR_HTTP)
  PUMD_ALIAS("protobuf", PUMD_VENDOR_PROTOBUF)
  PUMD_ALIAS("proto", PUMD_VENDOR_PROTOBUF)
#undef PUMD_ALIAS
  if (pumd_bytes_equal(language, length, "console")) {
    PumdLanguageSpec spec =
        pumd_spec_from_vendor(&pumd_vendor_specs[PUMD_VENDOR_SHELL]);
    *is_console = 1;
    return spec;
  }
  return (PumdLanguageSpec){0};
}

static int pumd_add_console_spans(const PumdLanguageSpec *spec,
                                  const uint8_t *source, uint32_t source_length,
                                  PumdSpanList *spans) {
  uint32_t line_start = 0;
  while (line_start < source_length) {
    uint32_t line_end = line_start;
    uint32_t command_start;
    while (line_end < source_length && source[line_end] != '\n') line_end++;
    command_start = line_start;
    /* Common transcript prompts; output lines deliberately remain unstyled. */
    if (line_end - line_start >= 2 &&
        (source[line_start] == '$' || source[line_start] == '#' ||
         source[line_start] == '>') &&
        (source[line_start + 1] == ' ' || source[line_start + 1] == '\t')) {
      command_start += 2;
      if (command_start < line_end) {
        int result = pumd_add_query_spans(spec, source + command_start,
                                           line_end - command_start,
                                           command_start, spans);
        if (result != 0) return result;
      }
    }
    if (line_end == source_length) break;
    line_start = line_end + 1;
  }
  return 0;
}

static int pumd_node_type_is(TSNode node, const char *expected) {
  uint32_t length = 0;
  const char *type = ts_node_type(node);
  if (type == NULL) return 0;
  while (expected[length] != '\0') {
    if (type[length] != expected[length]) return 0;
    length++;
  }
  return type[length] == '\0';
}

static void pumd_add_html_injection_nodes(TSNode node, const uint8_t *source,
                                          uint32_t source_length,
                                          PumdSpanList *spans) {
  uint32_t child_count;
  uint32_t child_index;
  const int is_script = pumd_node_type_is(node, "script_element");
  const int is_style = pumd_node_type_is(node, "style_element");
  if (is_script || is_style) {
    for (child_index = 0, child_count = ts_node_child_count(node);
         child_index < child_count; child_index++) {
      TSNode child = ts_node_child(node, child_index);
      if (pumd_node_type_is(child, "raw_text")) {
        uint32_t start_byte = ts_node_start_byte(child);
        uint32_t end_byte = ts_node_end_byte(child);
        PumdLanguageSpec inner = is_script
            ? pumd_spec_from_vendor(&pumd_vendor_specs[PUMD_VENDOR_JAVASCRIPT])
            : pumd_spec_from_vendor(&pumd_vendor_specs[PUMD_VENDOR_CSS]);
        /* An inner failure only suppresses that injection, never outer HTML. */
        if (end_byte <= source_length && start_byte < end_byte)
          (void)pumd_add_query_spans(&inner, source + start_byte,
                                     end_byte - start_byte, start_byte, spans);
      }
    }
  }
  child_count = ts_node_child_count(node);
  for (child_index = 0; child_index < child_count; child_index++)
    pumd_add_html_injection_nodes(ts_node_child(node, child_index), source,
                                  source_length, spans);
}

static void pumd_add_markdown_injection_nodes(TSNode node,
                                              const uint8_t *source,
                                              uint32_t source_length,
                                              PumdSpanList *spans) {
  uint32_t child_count = ts_node_child_count(node);
  uint32_t child_index;
  if (pumd_node_type_is(node, "fenced_code_block")) {
    TSNode language = {0};
    TSNode content = {0};
    for (child_index = 0; child_index < child_count; child_index++) {
      TSNode child = ts_node_child(node, child_index);
      uint32_t nested_count;
      uint32_t nested_index;
      if (pumd_node_type_is(child, "code_fence_content")) content = child;
      nested_count = ts_node_child_count(child);
      for (nested_index = 0; nested_index < nested_count; nested_index++) {
        TSNode nested = ts_node_child(child, nested_index);
        if (pumd_node_type_is(nested, "language")) language = nested;
      }
    }
    if (!ts_node_is_null(language) && !ts_node_is_null(content)) {
      uint32_t language_start = ts_node_start_byte(language);
      uint32_t language_end = ts_node_end_byte(language);
      uint32_t content_start = ts_node_start_byte(content);
      uint32_t content_end = ts_node_end_byte(content);
      int ignored_console;
      if (language_end <= source_length && content_end <= source_length &&
          language_start < language_end && content_start < content_end) {
        PumdLanguageSpec inner = pumd_spec_for(
            source + language_start, (int32_t)(language_end - language_start),
            &ignored_console);
        if (inner.language != NULL && !ignored_console)
          (void)pumd_add_query_spans(&inner, source + content_start,
                                     content_end - content_start, content_start,
                                     spans);
      }
    }
  }
  for (child_index = 0; child_index < child_count; child_index++)
    pumd_add_markdown_injection_nodes(ts_node_child(node, child_index), source,
                                      source_length, spans);
}

static void pumd_add_static_injections(const PumdLanguageSpec *spec,
                                       TSTree *tree,
                                       const uint8_t *source,
                                       uint32_t source_length,
                                       PumdSpanList *spans) {
  TSNode root;
  if (tree == NULL || (!spec->html_injections &&
                       spec->language != tree_sitter_markdown()))
    return;
  root = ts_tree_root_node(tree);
  if (spec->html_injections)
    pumd_add_html_injection_nodes(root, source, source_length, spans);
  else
    pumd_add_markdown_injection_nodes(root, source, source_length, spans);
}

/*
 * Highlight one input. `html_injections` is intentionally constrained to the
 * two language names in the HTML grammar's reviewed query: javascript and css.
 * The parser's raw-text nodes have no generic token capture, so nested spans do
 * not compete with outer HTML tag captures.
 */
static int pumd_collect(const uint8_t *language, int32_t language_length,
                        const uint8_t *source, int32_t source_length,
                        PumdSpanList *spans) {
  PumdLanguageSpec spec;
  int is_console;
  int result;
  if (language == NULL || source == NULL || language_length <= 0 ||
      source_length < 0)
    return PUMD_HIGHLIGHT_UNKNOWN_LANGUAGE;
  spec = pumd_spec_for(language, language_length, &is_console);
  if (spec.language == NULL) return PUMD_HIGHLIGHT_UNKNOWN_LANGUAGE;
  if (is_console)
    result = pumd_add_console_spans(&spec, source, (uint32_t)source_length, spans);
  else {
    TSParser *parser = ts_parser_new();
    TSTree *tree = NULL;
    if (parser == NULL || !ts_parser_set_language(parser, spec.language)) {
      if (parser != NULL) ts_parser_delete(parser);
      return PUMD_HIGHLIGHT_INTERNAL_FAILURE;
    }
    tree = ts_parser_parse_string_encoding(parser, NULL, (const char *)source,
                                           (uint32_t)source_length,
                                           TSInputEncodingUTF8);
    if (tree == NULL) {
      if (tree != NULL) ts_tree_delete(tree);
      ts_parser_delete(parser);
      return PUMD_HIGHLIGHT_PARSE_FAILURE;
    }
    result = pumd_add_query_spans_to_tree(&spec, tree, 0, spans);
    if (result == 0)
      pumd_add_static_injections(&spec, tree, source, (uint32_t)source_length,
                                 spans);
    ts_tree_delete(tree);
    ts_parser_delete(parser);
  }
  return result;
}

static int pumd_query_assets_are_present(void) {
  /* Keep every generated query blob live without reading an .scm file at build/runtime. */
  return pumd_query_html_injections_len > 0 &&
         pumd_query_javascript_injections_len > 0 &&
         pumd_query_markdown_injections_len > 0 &&
         pumd_query_http_injections_len > 0 &&
         pumd_query_html_injections[0] != 0 &&
         pumd_query_javascript_injections[0] != 0 &&
         pumd_query_markdown_injections[0] != 0 &&
         pumd_query_http_injections[0] != 0;
}

static int pumd_is_immutable_revision(const char *revision) {
  uint32_t index;
  if (revision == NULL) return 0;
  for (index = 0; index < 40; index++) {
    char byte = revision[index];
    if (!((byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'f')))
      return 0;
  }
  return revision[40] == '\0';
}

/*
 * Test-only contract for pinned, compiled assets. It deliberately validates
 * build-time metadata and query compatibility without reading vendored files
 * or checksumming generated sources at runtime.
 */
MOONBIT_FFI_EXPORT int32_t pumd_syntax_highlight_vendor_contract(void) {
  uint32_t index;
  if (!pumd_query_assets_are_present()) return PUMD_HIGHLIGHT_INTERNAL_FAILURE;
  for (index = 0; index < PUMD_VENDOR_SPEC_COUNT; index++) {
    const PumdVendorSpec *vendor = &pumd_vendor_specs[index];
    PumdLanguageSpec spec;
    PumdSpanList spans = {0};
    uint32_t abi_version;
    int result;
    if (vendor->canonical_tag == NULL || vendor->canonical_tag[0] == '\0' ||
        !pumd_is_immutable_revision(vendor->revision) ||
        vendor->spdx_license == NULL || vendor->spdx_license[0] == '\0' ||
        vendor->language_factory == NULL || vendor->query == NULL ||
        vendor->query_length == 0 || vendor->query[0] == 0)
      return PUMD_HIGHLIGHT_INTERNAL_FAILURE;
    spec = pumd_spec_from_vendor(vendor);
    if (spec.language == NULL) return PUMD_HIGHLIGHT_INTERNAL_FAILURE;
    abi_version = ts_language_abi_version(spec.language);
    if (abi_version < TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION ||
        abi_version > TREE_SITTER_LANGUAGE_VERSION)
      return PUMD_HIGHLIGHT_INTERNAL_FAILURE;
    /* This compiles the primary query and its configured supplement. */
    result = pumd_add_query_spans(&spec, (const uint8_t *)"", 0, 0, &spans);
    free(spans.items);
    if (result != 0) return result;
  }
  return PUMD_VENDOR_SPEC_COUNT;
}

MOONBIT_FFI_EXPORT int32_t pumd_highlight_write(
    moonbit_bytes_t language, int32_t language_length, moonbit_bytes_t source,
    int32_t source_length, moonbit_bytes_t output, int32_t output_capacity) {
  PumdSpanList spans = {0};
  uint8_t *bytes = (uint8_t *)output;
  size_t index;
  int result;
  if (!pumd_query_assets_are_present()) return PUMD_HIGHLIGHT_INTERNAL_FAILURE;
  if (output_capacity < 0) return PUMD_HIGHLIGHT_OUTPUT_FAILURE;
  result = pumd_collect((const uint8_t *)language, language_length,
                        (const uint8_t *)source, source_length, &spans);
  if (result == 0 &&
      !pumd_normalize_spans(&spans, (const uint8_t *)source,
                            (uint32_t)source_length))
    result = PUMD_HIGHLIGHT_INTERNAL_FAILURE;
  if (result == 0 && (spans.length > INT32_MAX / PUMD_HIGHLIGHT_RECORD_BYTES ||
                      (size_t)output_capacity <
                          spans.length * PUMD_HIGHLIGHT_RECORD_BYTES ||
                      (spans.length > 0 && bytes == NULL)))
    result = PUMD_HIGHLIGHT_OUTPUT_FAILURE;
  if (result == 0) {
    for (index = 0; index < spans.length; index++) {
      const PumdHighlightSpan span = spans.items[index];
      uint8_t *record = bytes + index * PUMD_HIGHLIGHT_RECORD_BYTES;
      record[0] = (uint8_t)(span.start_byte & 0xffu);
      record[1] = (uint8_t)((span.start_byte >> 8) & 0xffu);
      record[2] = (uint8_t)((span.start_byte >> 16) & 0xffu);
      record[3] = (uint8_t)((span.start_byte >> 24) & 0xffu);
      record[4] = (uint8_t)(span.end_byte & 0xffu);
      record[5] = (uint8_t)((span.end_byte >> 8) & 0xffu);
      record[6] = (uint8_t)((span.end_byte >> 16) & 0xffu);
      record[7] = (uint8_t)((span.end_byte >> 24) & 0xffu);
      record[8] = (uint8_t)(span.token & 0xffu);
      record[9] = (uint8_t)((span.token >> 8) & 0xffu);
      record[10] = (uint8_t)((span.token >> 16) & 0xffu);
      record[11] = (uint8_t)((span.token >> 24) & 0xffu);
    }
    result = (int32_t)(spans.length * PUMD_HIGHLIGHT_RECORD_BYTES);
  }
  free(spans.items);
  return result;
}

#if defined(PUMD_SYNTAX_HIGHLIGHT_SMOKE)
#include <stdio.h>
int main(void) {
  const uint8_t language[] = "javascript";
  const uint8_t source[] = "const greeting = \"hello\";\n";
  uint8_t *output;
  int32_t written;
  const int32_t output_capacity =
      ((int32_t)sizeof(source) - 1) * PUMD_HIGHLIGHT_RECORD_BYTES;
  output = (uint8_t *)malloc((size_t)output_capacity);
  if (output == NULL) return 1;
  written = pumd_highlight_write((moonbit_bytes_t)language, 10,
                                 (moonbit_bytes_t)source,
                                 (int32_t)sizeof(source) - 1, output,
                                 output_capacity);
  free(output);
  if (written <= 0 || written > output_capacity) return 1;
  printf("tree-sitter syntax highlight smoke: %d bytes\n", (int)written);
  return 0;
}
#endif
