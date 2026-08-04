# Changelog

All notable changes to this project will be documented in this file.

## v1.3.2 (2026-08-04)

### Features

- Dynamic model classification mirrors the official `cmd` CLI instead of a
  hardcoded list. Availability is computed at runtime:
  - Expired models (free promotion ended by timestamp, or bundled but dropped
    from the current Command Code catalog) are kept in the registry for history
    but grouped into an "Expired / No longer provided (kept for history)"
    section at the very bottom of TUI page 5, tagged `[Expired]`
  - Newly released models present in the live API but absent from the bundled
    registry appear in a "New / Coming soon (in cmd catalog)" section above the
    expired ones, tagged `[New]`; they stay fully dynamic with no code change
  - Model ID comparison is case-insensitive and strips `-YYYYMMDD` date suffixes
    (e.g. `claude-haiku-4-5-20251001` == `claude-haiku-4-5`), mirroring the CLI
  - The free-promo expiry schedule (`modelExpiryUtc`) follows the CLI's own
    date-based checks such as `isLingFlashFreeEnded()` (`2026-08-03T13:00:00Z`)
- `/v1/models` (OpenAI/Anthropic clients) no longer advertises expired models:
  the bridge never serves a model that Command Code no longer provides, while
  still merging new live releases immediately
- TUI page 7 (Cost): expired and new models are excluded from pricing display
  and from cost sync, so pricing is only written for current offerings

## v1.3.1 (2026-08-02)

### Fixes

- Removed continuous API polling: staying on a TUI page (e.g. Models or Cost)
  no longer re-fetches Command Code data every few seconds. Data is refreshed
  once in the background when a page is opened (throttled to once per 10s to
  avoid spamming the API during rapid page switching) and on manual `[r]`
  refresh. This avoids hammering the Command Code endpoints just by viewing a
  page.

## v1.3.0 (2026-08-02)

### Features

- Dynamic model list: bridge now fetches the live Command Code model catalog from `/provider/v1/models` on refresh and merges it with the bundled list, so newly released models (e.g. `inclusionai/ling-3.0-flash-free`, `poolside/laguna-s-2.1-free`) appear in `/v1/models` and the TUI without a bridge release
- Served `/v1/models` endpoint is now dynamic too: it merges the live API list with the bundled registry, so OpenAI/Anthropic clients see newly released Command Code models immediately
- TUI page 5 (Models): renders the live model list with correct per-plan access grouping (Go/Pro/Max + credits override), showing which models are actually usable on the user's plan
- TUI page 5 (Models): all "available on your plan" models grouped together at the top, then sub-grouped by usage (Free usage vs Billing) and by provider (DeepSeek, Moonshot, ZAI, MiniMax, Xiaomi, Qwen, StepFun, Tencent, Nvidia, Thinking Machines, OpenAI, xAI, ...); Enter-to-copy stays in sync with the highlighted row
- TUI page 7 (Cost): pricing grouped by plan access first (Available on Go vs Requires Pro/Max), not by opensource/premium; live-known models without local pricing are shown as "no pricing data" (yellow) instead of being hidden
- TUI page 7 (Cost): sync result now appears as a status-bar notification (green on success, red on failure) instead of being rendered at the bottom of the page where it could go unnoticed
- Plan access model mirrors the official CLI (`evaluateModelAccess`): Go = open source + `gpt-5.6-luna`, `xai/grok-4.5`; Pro blocks Fable/Opus + Fugu Ultra; credits override grants everything
- Expanded bundled model registry from 44 to 52 models (added Kimi-K3, Qwen 3.7 Flash, Gemini 3.6 Flash, Gemini 3.5 Flash Lite, Inkling, Inkling Small, Laguna S 2.1, Ling 3.0 Flash)

### Fixes

- Keymap: `o` now always copies the OpenAI endpoint URL; "Clear entries before today" moved to `Shift+O` (previously `o` in the log panel cleared old logs instead of copying the endpoint)

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
