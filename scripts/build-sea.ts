import { spawnSync } from "node:child_process";
import { chmodSync, copyFileSync, existsSync, rmSync } from "node:fs";
import { resolve } from "node:path";

const sentinelFuse = "NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2";
const supportedPlatforms = new Set(["darwin", "linux", "win32"]);
const rootDirectory = resolve(__dirname, "../../..");
const outputDirectory = resolve(rootDirectory, "dist");
const blobPath = resolve(outputDirectory, "sea-prep.blob");
const executableName = process.platform === "win32" ? "sdde.exe" : "sdde";
const executablePath = resolve(outputDirectory, executableName);
const postjectExecutable = resolve(
  rootDirectory,
  "node_modules",
  ".bin",
  process.platform === "win32" ? "postject.cmd" : "postject",
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

if (!supportedPlatforms.has(process.platform)) {
  throw new Error(`Unsupported SEA build platform: ${process.platform}`);
}

if (!existsSync(postjectExecutable)) {
  throw new Error("postject is missing; run npm install before building the SEA");
}

rmSync(blobPath, { force: true });
rmSync(executablePath, { force: true });
run(process.execPath, ["--experimental-sea-config", "sea-config.json"]);
copyFileSync(process.execPath, executablePath);
chmodSync(executablePath, 0o755);

if (process.platform === "darwin") {
  run("codesign", ["--remove-signature", executablePath]);
}

const postjectArguments = [
  executablePath,
  "NODE_SEA_BLOB",
  blobPath,
  "--sentinel-fuse",
  sentinelFuse,
];

if (process.platform === "darwin") {
  postjectArguments.push("--macho-segment-name", "NODE_SEA");
}

run(postjectExecutable, postjectArguments);

if (process.platform === "darwin") {
  run("codesign", ["--sign", "-", executablePath]);
}
