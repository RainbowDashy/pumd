"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

const {
  OUTPUT_PATH,
  QUERY_ASSETS,
  renderHighlightQueriesHeader,
} = require("../scripts/generate-highlight-queries.cjs");

test("highlight query header is reproducible without generated lengths", () => {
  const generated = renderHighlightQueriesHeader();

  assert.equal(generated, fs.readFileSync(OUTPUT_PATH, "utf8"));
  assert.doesNotMatch(generated, /pumd_query_[a-z0-9_]+_len/);
  assert.equal(QUERY_ASSETS.length, 20);
});
