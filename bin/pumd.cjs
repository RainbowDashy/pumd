#!/usr/bin/env node
"use strict";

const path = require("node:path");
const { spawnSync } = require("node:child_process");

const BINARIES = Object.freeze({
  "darwin-arm64": ["darwin-arm64", "pumd"],
  "linux-x64": ["linux-x64", "pumd"],
  "win32-x64": ["win32-x64", "pumd.exe"]
});

function resolveBinary(platform = process.platform, arch = process.arch) {
  const target = `${platform}-${arch}`;
  const binary = BINARIES[target];
  if (!binary) {
    throw new Error(`pumd does not support ${target}`);
  }
  return path.join(__dirname, "..", "npm-binaries", ...binary);
}

function main(args = process.argv.slice(2)) {
  let executable;
  try {
    executable = resolveBinary();
  } catch (error) {
    console.error(error.message);
    return 1;
  }

  const result = spawnSync(executable, args, { stdio: "inherit" });
  if (result.error) {
    console.error(`failed to start pumd: ${result.error.message}`);
    return 1;
  }
  return result.status ?? 1;
}

if (require.main === module) {
  process.exitCode = main();
}

module.exports = { main, resolveBinary };
