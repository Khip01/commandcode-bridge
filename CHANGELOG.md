# Changelog

All notable changes to this project will be documented in this file.

## v1.0.0 (2026-07-27)

Initial stable release of CommandCode Bridge, a single-account proxy bridge for Command Code CLI with TUI dashboard.

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
