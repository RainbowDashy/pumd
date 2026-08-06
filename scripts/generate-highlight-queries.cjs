#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const REPOSITORY_ROOT = path.resolve(__dirname, "..");
const OUTPUT_PATH = path.join(
  REPOSITORY_ROOT,
  "vendor",
  "tree-sitter",
  "generated",
  "highlight_queries.h",
);

const QUERY_ASSETS = [
  ["pumd_query_javascript", "javascript/highlights.scm"],
  ["pumd_query_javascript_jsx", "javascript/highlights-jsx.scm"],
  ["pumd_query_typescript", "typescript/highlights.scm"],
  ["pumd_query_tsx", "tsx/highlights.scm"],
  ["pumd_query_bash", "bash/highlights.scm"],
  ["pumd_query_powershell", "powershell/highlights.scm"],
  ["pumd_query_json", "json/highlights.scm"],
  ["pumd_query_yaml", "yaml/highlights.scm"],
  ["pumd_query_toml", "toml/highlights.scm"],
  ["pumd_query_html", "html/highlights.scm"],
  ["pumd_query_css", "css/highlights.scm"],
  ["pumd_query_xml", "xml/highlights.scm"],
  ["pumd_query_sql", "sql/highlights.scm"],
  ["pumd_query_markdown", "markdown/highlights.scm"],
  ["pumd_query_http", "http/highlights.scm"],
  ["pumd_query_protobuf", "protobuf/highlights.scm"],
  ["pumd_query_html_injections", "html/injections.scm"],
  ["pumd_query_javascript_injections", "javascript/injections.scm"],
  ["pumd_query_markdown_injections", "markdown/injections.scm"],
  ["pumd_query_http_injections", "http/injections.scm"],
];

function renderByteArray(name, bytes) {
  const lines = [];
  for (let offset = 0; offset < bytes.length; offset += 12) {
    const chunk = bytes.subarray(offset, offset + 12);
    const values = Array.from(chunk, (byte) =>
      `0x${byte.toString(16).padStart(2, "0")}`,
    );
    const suffix = offset + chunk.length < bytes.length ? "," : "";
    lines.push(`  ${values.join(", ")}${suffix}`);
  }
  return [
    `static const unsigned char ${name}[] = {`,
    ...lines,
    "};",
  ].join("\n");
}

function renderHighlightQueriesHeader() {
  const queryRoot = path.join(
    REPOSITORY_ROOT,
    "vendor",
    "tree-sitter",
    "queries",
  );
  const arrays = QUERY_ASSETS.map(([name, relativePath]) =>
    renderByteArray(name, fs.readFileSync(path.join(queryRoot, relativePath))),
  );
  return [
    "/* Generated from vetted vendored .scm files. Do not edit by hand. */",
    "#ifndef PUMD_TREE_SITTER_HIGHLIGHT_QUERIES_H_",
    "#define PUMD_TREE_SITTER_HIGHLIGHT_QUERIES_H_",
    "",
    ...arrays.flatMap((array) => [array, ""]),
    "#endif",
    "",
  ].join("\n");
}

function main(argument) {
  const generated = renderHighlightQueriesHeader();
  if (argument === "--check") {
    const checkedIn = fs.readFileSync(OUTPUT_PATH, "utf8");
    if (checkedIn !== generated) {
      throw new Error(
        "highlight_queries.h is stale; run npm run generate:highlight-queries",
      );
    }
    return;
  }
  if (argument !== undefined) {
    throw new Error(`unknown argument: ${argument}`);
  }
  fs.writeFileSync(OUTPUT_PATH, generated);
}

if (require.main === module) {
  try {
    main(process.argv[2]);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = {
  OUTPUT_PATH,
  QUERY_ASSETS,
  renderByteArray,
  renderHighlightQueriesHeader,
};
