# Changelog

All notable changes to this project will be documented in this file.

## v1.2.0 (2026-07-31)

### Features

- Cost sync: sync Command Code model pricing to CLI agent configs
  - `commandcode-bridge cost-sync` CLI command with interactive agent selection
  - Detects installed CLI agents (OpenCode, Aider, Goose)
  - Filters models by bridge provider only (matches "Command Code" in provider name, localhost only)
  - Reads user's configured models from each agent's config
  - Adds/updates per-model cost fields (input, output, cache_read per 1M tokens)
  - Hardcoded pricing table with 44 models, exactly matching the bridge `/v1/models` API
  - Live API validation: pricing is checked against the bridge `/v1/models` before syncing
  - Lists ALL bridge providers found in config (OpenAI and Anthropic compatible), not just one
  - JSONC parser with trailing comma support for OpenCode configs
- TUI page 7 "Cost Sync" with keymap [7]
  - Shows ALL Command Code models with pricing (grouped: Open Source, Premium)
  - Models in bridge config: bright white + "(will be implemented)"
  - Models not in config: greyed out
  - [c] keymap triggers sync with progress feedback (hint shown on the page)
  - [up/down] agent selection when multiple agents detected

## v1.1.1 (2026-07-29)

### Fixes

- Ctrl+C: status bar notification only (no quit panel). Use [q] to quit.
- Auto-increment port: if configured port is in use, bridge tries port+1, +2, ... up to 100 attempts, logs the switch
- Help screen now includes `-v` / `--version` flag

## v1.1.0 (2026-07-28)

### Features

- Anthropic-compatible Messages API (`/v1/messages` and `/messages`)
  - Full SSE streaming: content_block_start/delta/stop + message_start/delta/stop
  - Tool use blocks with input_json_delta streaming
  - Thinking blocks (reasoning mapped to Anthropic format)
  - Non-streaming endpoint with proper Anthropic response shape
  - Anthropic Messages protocol -> CC wire format conversion (system, tools, messages)
  - stop_reason mapping: tool-calls -> tool_use, length -> max_tokens
- Self-update CLI command
  - `commandcode-bridge update` -- download latest release `.tgz` from GitHub and install via `npm install -g`
  - `--version` / `-v` flag prints version string
  - Update cache in `~/.config/commandcode-bridge/update-cache.json` (1-hour TTL, avoids rate limits)

### TUI

- Dual endpoint header: OpenAI (`http://127.0.0.1:{port}/v1`) + Anthropic (`http://127.0.0.1:{port}`)
- Keymaps: `[o]` copies OpenAI URL, `[a]` copies Anthropic base URL
- Ctrl+C now opens quit confirmation panel (not force exit)
  - Quit panel: Y / Enter / second Ctrl+C all confirm quit
  - Status bar shows red quit hint when panel is open
- Footer, help page, and Proxy Config (page 6) synced with both endpoints

### Refactor

- Server code split into three clean files:
  - `server_controller.dart` -- HTTP server, request routing, shared endpoints (/models, /health, /token, /info)
  - `openai_handler.dart` -- OpenAI-compatible handler (streaming + non-streaming)
  - `anthropic_handler.dart` -- Anthropic-compatible handler (streaming + non-streaming)
- Common upstream body builder shared between handlers
- Removed diagnostic/debug logging; production-level logging only
- Renamed ProxyServer -> ServerController, extracted handlers to own classes
- Update OpenCode protocol mapping for production upstream format
- Fixed config.date field missing from OpenAI handler (was broken after refactor)
- Extracted version into `lib/src/models/version.dart` constant

### Docs

- README.md trimmed to preview; detailed docs moved to `docs/`
- New docs: INSTALL.md, API-REFERENCE.md, TUI.md, ARCHITECTURE.md
- API-REFERENCE.md covers OpenAI, Anthropic, and Zed client configurations
- AGENTS.md synced with new file structure, endpoints, and naming conventions

## v1.0.0 (2026-07-27)

Initial stable release of CommandCode Bridge, a single-account proxy bridge for
Command Code CLI with TUI dashboard.

### Features

- TUI dashboard with 6 info pages (account, plan, usage, rate limits, models, proxy config)
- Progress bars for credit usage, billing period, success rate, token ratios, rate limits
- Plan-aware model sorting (Go = opensource first, Pro+ = premium first)
- OpenAI-compatible HTTP proxy (`/v1/chat/completions`, `/v1/models`, `/v1/health`, `/v1/token`, `/v1/info`)
- Real-time log sidebar with fullscreen mode
- Port configuration panel with availability scan (persisted across restarts)
- Clipboard integration for endpoint URL and model codenames
- Color-coded notification system (success, info, warning, error)
- Cross-platform support: Linux (primary), macOS (experimental), Windows (experimental)

### Proxy

- Full OpenAI-compatible chat completions (streaming + non-streaming)
- Mapping of system, tool, and assistant messages to Command Code wire format
- Tool-call round-trip support (assistant tool calls -> tool results)
- Completion token translation (`max_tokens` / `max_completion_tokens`)
- Correct UTF-8 multi-byte character handling in streaming responses
- `finish_reason` override to `"tool_calls"` when tool calls present

### TUI

- Auto-refresh active page with background refresh
- Header displaying last-used model, updateable in real-time
- Relative time display on billing period and reset countdowns
- Log panel toggle (`Ctrl+L`) with half-screen width
- 44 models with plan-coded access display (green accessible, grey blocked)
- Scrollable model list with Enter-to-copy

### Distribution

- npm tarball packaging with native Dart binary
- Cross-platform binary compilation (Linux, macOS, Windows)
- Zero overhead Node.js launcher (`commandcode-bridge` command)
- No Dart SDK required for end-users
- GitHub Actions CI/CD: test, release, and post-release validation workflows

### Fixes

- Signal handling: SIGINT/SIGTERM properly captured in headless server mode
- UTF-8 chunk boundary decoding: no more `FormatException` on multi-byte sequences
- Non-streaming chunk-boundary leftover handling
- Tool-call preservation across subsequent tool-result turns
- Log ordering: newest entries displayed at top

### Infrastructure

- GitHub Actions matrix build across 3 platforms
- Automated tarball packaging via `npm pack`
- Post-release user simulation (install, smoke test, uninstall)
- Bug report issue template
