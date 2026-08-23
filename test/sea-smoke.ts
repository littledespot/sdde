import * as assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { test } from "node:test";

const rootDirectory = resolve(__dirname, "../../..");
const executableName = process.platform === "win32" ? "sdde.exe" : "sdde";
const executablePath = resolve(rootDirectory, "dist", executableName);

test("the SEA runs without the source tree or node_modules", async () => {
  const temporaryDirectory = await mkdtemp(join(tmpdir(), "sdde-sea-smoke-"));

  try {
    const result = spawnSync(executablePath, [], {
      cwd: temporaryDirectory,
      encoding: "utf8",
      env: { PATH: process.env.PATH ?? "" },
      shell: false,
    });

    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, "Hello, world!\n");
    assert.equal(result.stderr, "");
  } finally {
    await rm(temporaryDirectory, { force: true, recursive: true });
  }
});
