# CommandCode Bridge

Single-account proxy bridge for Command Code CLI (`cmd` from `commandcode.ai`).
TUI dashboard with progress bars + OpenAI-compatible and Anthropic-compatible HTTP proxy.

## Auth

Command Code auth is stored at `~/.commandcode/auth.json`. The bridge reads the
API key from this file. Run `cmd login` to authenticate first. You can also
press `[l]` in the bridge TUI for login instructions.

## Architecture

### Stack
- Language: Dart 3.10+
- TUI: `nocterm` v0.8.0 (ProgressBar for visualizations)
- Server: `dart:io` `HttpServer`
- HTTP client: `dart:io` `HttpClient`
- Compile: `dart compile exe` -> single binary
- Distribution: npm tarball with Node.js launcher wrapper

### File Structure
```
commandcode-bridge/
├── bin/
│   ├── commandcode_bridge.dart       # Entry point
│   └── commandcode-bridge.js         # npm wrapper: OS detection + binary spawn
├── lib/
│   ├── commandcode_bridge.dart       # Barrel
│   └── src/
│       ├── main.dart                 # CLI wiring (run, run --server, help)
│       ├── models/
│       │   ├── account.dart          # Account + config store (port persist)
│       │   └── models_db.dart        # 44 models with goAccessible field
│       ├── services/
│       │   ├── api_client.dart       # HTTP client for api.commandcode.ai
│       │   └── log_store.dart        # JSONL activity log (2000 entries)
│       ├── server/
│       │   ├── server_controller.dart # HTTP server + routing
│       │   ├── openai_handler.dart    # OpenAI-compatible proxy
│       │   └── anthropic_handler.dart # Anthropic-compatible proxy
│       └── tui/
│       └── app.dart              # Nocterm TUI (9 panels + log + bars)
├── docs/
│   ├── INSTALL.md                  # Install options, platform support
│   ├── API-REFERENCE.md           # Proxy endpoints, client configs
│   ├── TUI.md                     # TUI pages, key bindings, plan access
│   └── ARCHITECTURE.md            # File structure, proxy flow, protocol translation
├── scripts/
│   └── stage-npm-package.mjs        # CI packaging helper: assembles release tarball
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   └── bug-report.md            # Bug report template
│   └── workflows/
│       ├── test.yml                  # Dart analyze + test + smoke
│       ├── release.yml               # Matrix build + tarball + GitHub release
│       └── post-release.yml          # Install simulation from real asset
├── test/
├── AGENTS.md
├── CHANGELOG.md
├── README.md
├── package.json
├── build / run                      # Linux/macOS scripts
├── build.bat / run.bat              # Windows batch scripts
├── LICENSE
└── pubspec.yaml
```

### CLI Contract

```bash
commandcode-bridge run          Start the bridge in TUI mode
commandcode-bridge run --server Start the bridge in headless server mode
commandcode-bridge help         Show this help screen
commandcode-bridge (no args)    Show this help screen
commandcode-bridge <invalid>    Show help screen, exit 1
```

The npm wrapper (`bin/commandcode-bridge.js`) detects `process.platform`, maps to the correct native binary (`app-linux`, `app-mac`, `app-win.exe`), and spawns it with `stdio: 'inherit'`. All args are forwarded. Once launched, Node.js goes idle and the Dart binary takes full control.

## Distribution

### End-user install

Users install from a `.tgz` asset attached to a GitHub Release:

```bash
npm install -g ./commandcode-bridge-vX.Y.Z.tgz
commandcode-bridge run
```

Requirements: Node.js 18+ (for the npm launcher), a Command Code account.

No Dart SDK needed for end-users.

### Release workflow

Triggered by pushing a tag matching `v*` or `[0-9]*`:

1. **Build matrix** (3 OS):
   - ubuntu-latest -> `app-linux`
   - macos-latest -> `app-mac`
   - windows-latest -> `app-win.exe`
   - Each: `dart compile exe` + upload artifact
2. **Package job** (ubuntu-latest, stable releases only):
   - Download 3 binary artifacts
   - Run `scripts/stage-npm-package.mjs` which assembles the npm package folder
   - Run `npm pack` to produce `commandcode-bridge-vX.Y.Z.tgz`
   - Upload tarball artifact
3. **Release job** (stable releases only):
   - Create GitHub Release with the tarball asset

Stable releases exclude tags with `-rc`, `-beta`, `-alpha`. Prerelease tags produce binaries but skip packaging and release jobs.

### Post-release validation

Triggered by `release: published` or manual dispatch:

1. Download the real published tarball from GitHub Releases
2. Install to isolated npm prefix
3. Verify `commandcode-bridge` command exists
4. Smoke test headless mode (`commandcode-bridge run --server`)
5. Uninstall

### Tag strategy

| Pattern | Type | Release behavior |
|---------|------|------------------|
| `v1.0.0` | Stable | Full build + package + GitHub Release |
| `v1.0.1-rc1` | Prerelease | Build binaries only, no packaging or release |
| `v1.0.1-beta1` | Prerelease | Build binaries only, no packaging or release |
| `v1.0.1-alpha1` | Prerelease | Build binaries only, no packaging or release |

### Why npm tarball instead of `npm install -g <git-url>`?

npm v11 has a bug installing global git deps: the install appears to succeed (`added 1 package`) but the binary is missing. Always install from a local tarball. This pattern matches the approach used by `opencode-rich-presence`.

## Platform Support

| Platform | Status | Clipboard | Build |
|----------|--------|-----------|-------|
| Linux | Primary | `wl-copy` -> `xclip` -> OSC 52 | `./build` |
| macOS | Experimental | `pbcopy` -> OSC 52 | `./build` |
| Windows | Experimental | `clip` -> OSC 52 | `build.bat` |

## API Endpoints (Command Code)

| Endpoint | Method | Data |
|----------|--------|------|
| `/alpha/whoami` | GET | User identity |
| `/alpha/billing/credits` | GET | Credits + rate limits |
| `/alpha/billing/subscriptions` | GET | Subscription/plan |
| `/alpha/usage/summary` | GET | Usage statistics |
| `/alpha/generate` | POST | AI chat completions |

## Proxy Endpoints

| Path | Method | Description |
|------|--------|-------------|
| `/v1/chat/completions` | POST | OpenAI-compatible chat completions |
| `/v1/messages` | POST | Anthropic-compatible Messages API |
| `/messages` | POST | Anthropic-compatible Messages API (alt path) |
| `/v1/models` | GET | List 44 available models |
| `/v1/health` | GET | Health check |
| `/v1/token` | GET | Get access token |
| `/v1/info` | GET | Bridge info + config |

## OpenCode Configuration

### OpenAI Compatible

```jsonc
"Khip01 - Command Code": {
  "name": "Command Code",
  "options": {
    "baseURL": "http://127.0.0.1:17077/v1",
    "apiKey": "anything"
  },
  "models": {
    "deepseek/deepseek-v4-pro": {
      "name": "DeepSeek V4 Pro",
      "tool_call": true,
      "reasoning": true,
      "limit": { "context": 1048576, "input": 1048576, "output": 8192 }
    }
  }
}
```

### Anthropic Compatible

```jsonc
"Khip01 - Command Code Anthropic": {
  "npm": "@ai-sdk/anthropic",
  "name": "Command Code Anthropic",
  "options": {
    "baseURL": "http://127.0.0.1:17077/v1",
    "apiKey": "anything"
  },
  "models": {
    "deepseek/deepseek-v4-pro": {
      "name": "DeepSeek V4 Pro",
      "tool_call": true,
      "reasoning": true,
      "limit": { "context": 1048576, "input": 1048576, "output": 8192 }
    }
  }
}
```

## Plan Access

Plan model access rules (from cli.mjs):

| Plan | Allowed Categories | Blocked Premium Models |
|------|-------------------|----------------------|
| `individual-go` | opensource only | (all premium blocked) |
| `individual-pro` | premium + opensource | claude-fable-5, claude-opus-5/4.8/4.7/4.6, sakana/fugu-ultra |
| `individual-provider` | premium + opensource | (none) |
| `individual-max` | premium + opensource | (none) |
| `individual-ultra` | premium + opensource | (none) |
| `teams-pro` | premium + opensource | (none) |

Model list in TUI page 5 uses `_orderedModels` (sorted by plan). Go shows opensource first (green), premium dimmed (grey). Pro+ shows premium first.

## Port

Default port: `17077` (no neighbor conflicts with cobuddy-bridge 20130).
Config persisted at `~/.config/commandcode-bridge/config.json` (survives updates).
Port can be changed via `[p]` panel (with availability scan).
Empty input = reset to default.

## Notifications

Status bar between content and keymap footer, color-coded:
- Green: success (data refreshed, copied)
- Cyan: info (fetching, copying)
- Yellow: warning (clear confirm, restart required)
- Red: error (failed, invalid, port in use)

## Clipboard

Copy to clipboard via platform-specific tools, fallback to OSC 52:
- Linux: `wl-copy` -> `xclip` -> OSC 52
- macOS: `pbcopy` -> OSC 52
- Windows: `clip` -> OSC 52

Copy triggers:
- `[c]` -- Copy endpoint URL (`http://127.0.0.1:17077/v1`)
- `[Enter]` on model page -- Copy selected model codename

## TUI Pages

| Key | Page | API Endpoints Used | Visuals |
|-----|------|--------------------|---------|
| `1` | Account | `/alpha/whoami` | Text info |
| `2` | Plan & Billing | `/alpha/billing/subscriptions` + `/alpha/billing/credits` | Progress bars for period elapsed, credit usage, individual credit types |
| `3` | Usage | `/alpha/usage/summary` | Success rate bar, input/output token bars, credit breakdown bars, cost |
| `4` | Rate Limits | `/alpha/billing/credits` (windowLimits) | 5-hour and weekly usage bars with exceed warnings, remaining, reset times |
| `5` | Models | `_orderedModels` (sorted by plan, 44 total) | Text list with copy-on-Enter |
| `6` | Proxy Config | Bridge state + endpoints | Text info |

Visualization uses `ProgressBar` from nocterm with color-coded fill:
- Green: good (< 80% usage)
- Yellow: warning (80-100% usage)
- Red: critical (> 100%, over limit, exceeded)

## Key Bindings

| Key | Context | Action |
|-----|---------|--------|
| `1-6` | Always | Switch info page |
| `r` | Always | Refresh all API data |
| `c` | Always | Copy endpoint URL to clipboard |
| `p` | Always | Open port configuration panel |
| `h` | Always | Open help panel |
| `q` | Always | Open quit confirmation |
| `up/down` | Main | Scroll / navigate models |
| `PgUp/PgDn` | Main | Scroll 10 lines |
| `Enter` | Models page | Copy selected model ID to clipboard |
| `Ctrl+L` | Always | Toggle log sidebar |
| `f` | Log open | Toggle log fullscreen / sidebar |
| `Shift+C` | Log open | Clear all logs (with Y/N confirmation) |
| `O` | Log open | Clear logs before today (with Y/N confirmation) |
| `l` | Not auth'd | Open login instructions panel |
| `Esc` | Sub-panels | Back to main |

## Build & Run

### Developer (from source)

```bash
# Linux / macOS
./build           # dart pub get + dart compile exe
./run             # TUI mode (proxy auto-starts at 17077)
./run server      # Headless server mode
./run help        # Show help

# Windows
build.bat         # Compile
run.bat           # Run TUI
run.bat server    # Headless server mode
```

### End-user (from npm tarball)

```bash
npm install -g ./commandcode-bridge-vX.Y.Z.tgz
commandcode-bridge run          # TUI mode
commandcode-bridge run --server # Headless server mode
commandcode-bridge help         # Show help
```

## Changelog

This project maintains a `CHANGELOG.md` file. Release bodies include a short summary with a link to the changelog for full details.

## Agent Maintenance Rules

When making changes to this project, the AI agent must:

1. **Sync CHANGELOG.md for every functional change.** Any feature, fix, or infrastructure change that affects end-users or developers must be recorded in CHANGELOG.md before the commit. This includes TUI changes, proxy fixes, infrastructure workflows, distribution changes, and documentation updates.

2. **Sync versioning in release body when creating a release tag.** Before pushing a tag (stable, rc, beta, or alpha), verify that:
   - The CHANGELOG.md has an entry for the new version
   - The `package.json` version reflects the tag version (for stable releases)
   - The release body in the workflow (`.github/workflows/release.yml`) generates accurate notes with the correct tag reference

3. **Keep AGENTS.md in sync with the actual project state.** When adding new files, changing the CLI contract, or altering the build/distribution process, update the relevant sections in AGENTS.md in the same commit.
