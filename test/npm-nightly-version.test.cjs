"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  formatNightlyVersion,
  semverSafeShortSha
} = require("../scripts/npm-nightly-version.cjs");

test("formats the nightly version with the normal short commit", () => {
  assert.equal(
    formatNightlyVersion("0.1.0", "985c0e33ec51073408002a36d5acf412c8a3a67d"),
    "0.1.0-nightly.985c0e3"
  );
});

test("extends a numeric leading-zero prefix until it is SemVer-safe", () => {
  assert.equal(
    semverSafeShortSha("0123456a89abcdef0123456789abcdef01234567"),
    "0123456a"
  );
});

test("keeps a numeric prefix when it has no leading zero", () => {
  assert.equal(
    semverSafeShortSha("123456789abcdef0123456789abcdef012345678"),
    "1234567"
  );
});

test("rejects malformed commit SHAs", () => {
  assert.throws(
    () => formatNightlyVersion("0.1.0", "not-a-commit"),
    /expected a full 40-character Git commit SHA/
  );
});
