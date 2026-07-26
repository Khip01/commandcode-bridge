#!/usr/bin/env node
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { execSync } from "node:child_process";

const outDir = resolve(process.argv.indexOf("--out") !== -1 ? process.argv[process.argv.indexOf("--out") + 1] || "." : ".");
const stageDir = join(outDir, "stage");

// Clean and create staging directory
if (existsSync(stageDir)) {
  execSync(`rm -rf "${stageDir}"`, { shell: true });
}
mkdirSync(join(stageDir, "bin"), { recursive: true });
mkdirSync(join(stageDir, "bin-executables"), { recursive: true });

// Copy package files
copyFileSync("package.json", join(stageDir, "package.json"));
copyFileSync("LICENSE", join(stageDir, "LICENSE"));
copyFileSync("README.md", join(stageDir, "README.md"));
copyFileSync("bin/commandcode-bridge.js", join(stageDir, "bin", "commandcode-bridge.js"));

// Copy binaries (source dir = cwd)
for (const bin of ["app-linux", "app-mac", "app-win.exe"]) {
  if (existsSync(bin)) {
    copyFileSync(bin, join(stageDir, "bin-executables", bin));
  } else {
    console.error(`Warning: ${bin} not found, skipping`);
  }
}

// Set executable bit on Unix binaries
for (const f of ["bin-executables/app-linux", "bin-executables/app-mac", "bin/commandcode-bridge.js"]) {
  const full = join(stageDir, f);
  if (existsSync(full)) {
    execSync(`chmod 755 "${full}"`, { shell: true });
  }
}

// Read version from package.json
const pkg = JSON.parse(readFileSync(join(stageDir, "package.json"), "utf-8"));
const version = pkg.version;

// Write .npmignore
writeFileSync(join(stageDir, ".npmignore"), [
  "node_modules/",
  ".dart_tool/",
  "test/",
  "lib/",
  "pubspec.*",
  "build",
  "build.bat",
  "run",
  "run.bat",
  "AGENTS.md",
  "scripts/",
  ".commandcode/",
  "bin/commandcode_bridge.dart",
].join("\n") + "\n", "utf-8");

// Pack
execSync(`npm pack 2>&1`, { cwd: stageDir, stdio: "inherit", shell: true });

// Find the resulting tarball
const stageFiles = readdirSync(stageDir).filter(f => f.endsWith(".tgz"));
if (stageFiles.length === 0) {
  console.error("npm pack produced no .tgz");
  process.exit(1);
}

const tgzName = `commandcode-bridge-v${version}.tgz`;
const src = join(stageDir, stageFiles[0]);
const dst = join(outDir, tgzName);
copyFileSync(src, dst);
console.log(`Packaged: ${dst}`);

// Cleanup
execSync(`rm -rf "${stageDir}"`, { shell: true });
