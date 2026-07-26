#!/usr/bin/env node
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const platform = process.platform;
let binaryName = "";

if (platform === "win32") {
  binaryName = "app-win.exe";
} else if (platform === "darwin") {
  binaryName = "app-mac";
} else if (platform === "linux") {
  binaryName = "app-linux";
} else {
  console.error(`Unsupported operating system: ${platform}`);
  process.exit(1);
}

const __dirname = dirname(dirname(fileURLToPath(import.meta.url)));
const binaryPath = join(__dirname, "bin-executables", binaryName);

if (!existsSync(binaryPath)) {
  console.error(`Binary not found: ${binaryPath}`);
  console.error("The commandcode-bridge package appears to be corrupted or incomplete.");
  console.error("Try reinstalling from a fresh tarball.");
  process.exit(1);
}

const child = spawn(binaryPath, process.argv.slice(2), {
  stdio: "inherit",
  shell: false,
});

child.on("exit", (code) => {
  process.exit(code ?? 0);
});
