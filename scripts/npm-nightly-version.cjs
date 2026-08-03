#!/usr/bin/env node
"use strict";

const MINIMUM_SHORT_SHA_LENGTH = 7;

function semverSafeShortSha(commitSha) {
  const normalizedSha = commitSha.toLowerCase();
  if (!/^[0-9a-f]{40}$/.test(normalizedSha)) {
    throw new Error("expected a full 40-character Git commit SHA");
  }

  let length = MINIMUM_SHORT_SHA_LENGTH;
  let shortSha = normalizedSha.slice(0, length);
  while (/^0[0-9]+$/.test(shortSha) && length < normalizedSha.length) {
    length += 1;
    shortSha = normalizedSha.slice(0, length);
  }
  if (/^0[0-9]+$/.test(shortSha)) {
    throw new Error("commit SHA cannot form a SemVer-safe abbreviated identifier");
  }
  return shortSha;
}

function formatNightlyVersion(baseVersion, commitSha) {
  if (!/^\d+\.\d+\.\d+$/.test(baseVersion)) {
    throw new Error("npm package base version must be stable SemVer");
  }
  return `${baseVersion}-nightly.${semverSafeShortSha(commitSha)}`;
}

if (require.main === module) {
  const [baseVersion, commitSha] = process.argv.slice(2);
  try {
    console.log(formatNightlyVersion(baseVersion, commitSha));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = { formatNightlyVersion, semverSafeShortSha };
