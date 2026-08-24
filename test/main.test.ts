import * as assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { test } from "node:test";

import { GREETING, main } from "../src/main.js";

test("main writes the Hello World greeting", () => {
  const output: string[] = [];

  main((value) => {
    output.push(value);
  });

  assert.deepEqual(output, [`${GREETING}\n`]);
});

test("the compiled entry point writes the Hello World greeting", () => {
  const entryPoint = resolve(__dirname, "..", "src", "main.js");
  const result = spawnSync(process.execPath, [entryPoint], {
    encoding: "utf8",
    shell: false,
  });

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, `${GREETING}\n`);
  assert.equal(result.stderr, "");
});
