"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const workflowRoot = path.join(__dirname, "..", ".github", "workflows");

function namedSteps(workflow) {
  const starts = [...workflow.matchAll(/^ {6}- name: (.+)$/gm)];
  return starts.map((match, index) => ({
    name: match[1],
    source: workflow.slice(
      match.index,
      starts[index + 1]?.index ?? workflow.length
    )
  }));
}

test("PowerShell steps accepting native failures explicitly exit successfully", () => {
  const failures = [];

  for (const filename of fs.readdirSync(workflowRoot)) {
    if (!filename.endsWith(".yml") && !filename.endsWith(".yaml")) {
      continue;
    }

    const workflow = fs.readFileSync(path.join(workflowRoot, filename), "utf8");
    for (const step of namedSteps(workflow)) {
      if (!step.source.includes("shell: pwsh")) {
        continue;
      }
      if (!/\$LASTEXITCODE\s+-ne\s+[1-9]/.test(step.source)) {
        continue;
      }

      const lastLine = step.source.trimEnd().split("\n").at(-1).trim();
      if (lastLine !== "exit 0") {
        failures.push(`${filename}: ${step.name}`);
      }
    }
  }

  assert.deepEqual(
    failures,
    [],
    "GitHub Actions propagates a stale nonzero $LASTEXITCODE unless the step resets it"
  );
});
