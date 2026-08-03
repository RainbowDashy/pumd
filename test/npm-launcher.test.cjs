"use strict";

const assert = require("node:assert/strict");
const path = require("node:path");
const test = require("node:test");

const { resolveBinary } = require("../bin/pumd.cjs");

const binaryRoot = path.join(__dirname, "..", "npm-binaries");

test("resolves each published platform to its native binary", () => {
  assert.equal(
    resolveBinary("darwin", "arm64"),
    path.join(binaryRoot, "darwin-arm64", "pumd")
  );
  assert.equal(
    resolveBinary("linux", "x64"),
    path.join(binaryRoot, "linux-x64", "pumd")
  );
  assert.equal(
    resolveBinary("win32", "x64"),
    path.join(binaryRoot, "win32-x64", "pumd.exe")
  );
});

test("rejects platforms without a published binary", () => {
  assert.throws(
    () => resolveBinary("darwin", "x64"),
    /pumd does not support darwin-x64/
  );
});
