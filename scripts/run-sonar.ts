import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

const rootDirectory = resolve(__dirname, "../../..");
const npmExecutable = process.platform === "win32" ? "npm.cmd" : "npm";
const scannerExecutable = resolve(
  rootDirectory,
  "node_modules",
  ".bin",
  process.platform === "win32" ? "sonar-scanner-npm.cmd" : "sonar-scanner-npm",
);
const sonarEnvironmentPreflight = resolve(
  __dirname,
  "validate-sonar-environment.js",
);

function run(command: string, argumentsList: readonly string[]): void {
  const result = spawnSync(command, argumentsList, {
    cwd: rootDirectory,
    shell: false,
    stdio: "inherit",
  });

  if (result.error !== undefined) {
    throw new Error(`Unable to start ${command}: ${result.error.message}`);
  }

  if (result.status !== 0) {
    throw new Error(`${command} exited with status ${String(result.status)}`);
  }
}

run(process.execPath, [sonarEnvironmentPreflight]);
run(npmExecutable, ["run", "test:coverage"]);
run("docker-compose", [
  "-f",
  "docker-compose.sonarqube.yml",
  "up",
  "--detach",
  "--wait",
  "--wait-timeout",
  "300",
]);
run(scannerExecutable, []);
