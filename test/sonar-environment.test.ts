import * as assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { test } from "node:test";

const rootDirectory = resolve(__dirname, "../../..");
const preflightScript = resolve(
  rootDirectory,
  "dist",
  "compiled",
  "scripts",
  "validate-sonar-environment.js",
);

test("SonarQube preflight rejects a missing token", () => {
  const result = spawnSync(process.execPath, [preflightScript], {
    encoding: "utf8",
    env: { SONAR_HOST_URL: "https://sonarqube.example.test" },
    shell: false,
  });

  assert.equal(result.status, 1);
  assert.match(result.stderr, /SONAR_TOKEN must be set/);
});

test("SonarQube preflight accepts a token for the local server", () => {
  const result = spawnSync(process.execPath, [preflightScript], {
    encoding: "utf8",
    env: { SONAR_TOKEN: "test-token" },
    shell: false,
  });

  assert.equal(result.status, 0, result.stderr);
});

test("SonarQube validation loads the optional local environment file", () => {
  const packageJson = readFileSync(resolve(rootDirectory, "package.json"), "utf8");

  assert.match(
    packageJson,
    /"sonar": "npm run build && node --env-file-if-exists=\.env dist\/compiled\/scripts\/run-sonar\.js"/,
  );
  assert.doesNotMatch(packageJson, /"sonar:/);
});
