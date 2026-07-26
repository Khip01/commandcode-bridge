# CommandCode Bridge

Single-account proxy bridge for [Command Code](https://commandcode.ai) CLI (`cmd`). TUI dashboard with progress bars + OpenAI-compatible HTTP proxy endpoint.

Turn your Command Code Go plan ($1/month) into an OpenAI-compatible API for use with OpenCode, Cursor, or any OpenAI client.

<img width="1901" height="927" alt="Screenshot" src="https://github.com/user-attachments/assets/c174095e-0bdd-4197-a152-bf6fd7f34056" />

## Features

- **TUI Dashboard** -- 6 info pages (account, plan, usage, rate limits, models, proxy config)
- **Progress Bars** -- Visual bars for credit usage, billing period, success rate, token ratios, rate limits
- **Plan-Aware UI** -- Models sorted by plan (Go = opensource first, Pro+ = premium first)
- **OpenAI-Compatible Proxy** -- Use any OpenAI SDK/CLI pointing to `http://127.0.0.1:17077/v1`
- **Real-time Log** -- Sidebar with timestamped activity, fullscreen mode, confirmation before clear
- **Port Config** -- Change port via `[p]` panel with availability scan, persisted in config
- **Clipboard** -- Copy endpoint URL (`[c]`) or model codename (`[Enter]`)
- **Color-coded Notifications** -- Green (success), Cyan (info), Yellow (warning), Red (error)
- **Config Persistence** -- `~/.config/commandcode-bridge/config.json` survives updates
- **Cross-platform** -- Linux (primary), macOS (experimental), Windows (experimental)

## Prerequisites

- A Command Code account with active plan
- Dart SDK 3.10+ (for building from source)

## Platform Support

| Platform | Status | Clipboard | Build |
|----------|--------|-----------|-------|
| Linux | Primary (fully tested) | `wl-copy` -> `xclip` -> OSC 52 | `./build` |
| macOS | Experimental | `pbcopy` -> OSC 52 | `./build` |
| Windows | Experimental | `clip` -> OSC 52 | `build.bat` |

## Quick Start

```bash
# Login to Command Code (one-time)
cmd login

# Run the bridge (Linux/macOS)
./run             # TUI mode (proxy auto-starts at 17077)
./run server      # Headless server mode

# Run the bridge (Windows)
run.bat           # TUI mode
run.bat server    # Headless server mode
```

The bridge reads credentials from `~/.commandcode/auth.json` (same file as `cmd`).

If you have not logged in yet, run `cmd login` in any terminal, or press `[l]` from the bridge TUI for instructions.

## Proxy Endpoints

All at `http://127.0.0.1:17077/v1`:

| Path | Method | Description |
|------|--------|-------------|
| `/v1/chat/completions` | POST | OpenAI-compatible chat (stream + non-stream) |
| `/v1/models` | GET | List 44 available models |
| `/v1/health` | GET | Health check |
| `/v1/token` | GET | Get current access token |
| `/v1/info` | GET | Bridge info and config |

**API Key**: Any value works. The bridge uses your saved Command Code auth.

## OpenCode / Cursor Configuration

```jsonc
"CommandCode": {
  "name": "Command Code",
  "options": {
    "baseURL": "http://127.0.0.1:17077/v1",
    "apiKey": "anything"
  },
  "models": {
    "deepseek/deepseek-v4-flash": {
      "name": "DeepSeek V4 Flash",
      "tool_call": true,
      "reasoning": true,
      "limit": {
        "context": 1000000,
        "input": 1000000,
        "output": 8000
      }
    },
    "MiniMaxAI/MiniMax-M3-Free": {
      "name": "MiniMax M3 Free",
      "limit": { "context": 1000000 }
    },
    "Qwen/Qwen3.7-Max": {
      "name": "Qwen 3.7 Max",
      "limit": { "context": 1000000 }
    }
  }
}
```

## TUI

### Header
```
CommandCode Bridge  OpenAI Compatible | Khip01 (user@email.com)           Go Plan  RUNNING
  http://127.0.0.1:17077/v1  [c]opy endpoint url                   Last used: deepseek/deepseek-v4-flash
```

### Pages

| Key | Page | Data Source | Visuals |
|-----|------|-------------|---------|
| `1` | Account | `/alpha/whoami` | Text info (name, email, user ID) |
| `2` | Plan & Billing | `/alpha/billing/subscriptions` + `/alpha/billing/credits` | Progress bars for billing period, credit usage |
| `3` | Usage | `/alpha/usage/summary` | Success rate bar, token bars, cost breakdown |
| `4` | Rate Limits | `/alpha/billing/credits` windowLimits | 5-hour and weekly usage bars with exceed warnings |
| `5` | Models | 44 models sorted by plan access | Scrollable list, Enter to copy codename |
| `6` | Proxy Config | Bridge state | Port, API URL, endpoints, uptime |

### Visualizations (Pages 2-4)

**Plan & Billing:**
```
Plan:  Go Plan (individual-go)  ● Active
Billing Period:
  2026-07-26 to 2026-08-26
  ████████████████████░░░  15d / 30d elapsed
  Renewal: Auto-renews

Credits
  Total: $10.00  (Used: $0.02)
  ██░░░░░░░░░░░░░░░░░░░░  0% used
  Monthly: $10.00
  Purchased: $0.00
  Free: $0.00
  Threshold: $0.00
```

**Usage:**
```
Usage Summary
  Requests: 3 completed / 0 failed (3 total)

Success Rate
  ██████████████████████  100.0%

Token Usage
  Input:  28.2K     ██████████████████████
  Output: 209       ░░░░░░░░░░░░░░░░░░░░░░
  Total:  28.4K

Cost
  Total: $0.0235  Avg: $0.000008/req

Credits Breakdown
  Monthly: $0.0235  ██████████████████████
  Free:    $0.0000  ░░░░░░░░░░░░░░░░░░░░░░
```

**Rate Limits:**
```
5-Hour Window
  ████████░░░░░░░░░░░░░░  $0.02 / $3.00
  Remaining: $2.98
  Resets at: 2026-07-26 15:00

Weekly Window
  ████░░░░░░░░░░░░░░░░░░  $0.02 / $6.00
  Remaining: $5.98
  Resets at: 2026-08-01 15:00
```

### Key Bindings

| Key | Context | Action |
|-----|---------|--------|
| `1-6` | Always | Switch info page |
| `r` | Always | Refresh all API data |
| `c` | Always | Copy endpoint URL (`http://.../v1`) to clipboard |
| `p` | Always | Configure proxy port (with availability scan) |
| `h` | Always | Open help |
| `q` | Always | Quit (with confirmation) |
| `up/down` | Main | Scroll content / navigate models |
| `PgUp/PgDn` | Main | Scroll 10 lines |
| `Enter` | Models page | Copy selected model codename to clipboard |
| `Ctrl+L` | Always | Toggle log sidebar |
| `f` | Log open | Toggle log fullscreen / sidebar |
| `Shift+C` | Log open | Clear all logs (with Y/N confirmation) |
| `O` | Log open | Clear old entries (with Y/N confirmation) |
| `l` | Not auth'd | Open login instructions |

### Status Notifications

Dedicated bar between content and keymap. Color-coded:
- **Green**: Data refreshed, clipboard copied
- **Cyan**: Fetching data, processing
- **Yellow**: Confirmation needed, restart required
- **Red**: Errors, invalid input, port in use

### Port Configuration

Press `[p]` to open port config panel:
- Enter any port (1024-65535), tested before saving
- Empty input = reset to default (17077)
- Available ports scanned dynamically
- Config saved to `~/.config/commandcode-bridge/config.json`
- Restart required for change to take effect

## Plan Access

Models in page 5 are prioritized by your plan. Sorted as:

| Plan | Sort Order | Accessible |
|------|-----------|------------|
| individual-go | Opensource first (green), Premium dimmed | Opensource only |
| individual-pro | Premium first | Premium + opensource (blocked: top Claude + Fugu) |
| individual-max | Premium first | All models |
| individual-ultra | Premium first | All models |
| teams-pro | Premium first | All models |

### Go Plan Accessible Models

Open source models accessible on Go plan:
- DeepSeek V4 Pro, DeepSeek V4 Flash
- MiniMax M3 Free, M3, M2.7, M2.5
- Kimi K2.7 Code, K2.6, K2.5
- Qwen 3.7 Max/Plus, 3.6 Max Preview/Plus
- GLM 5.2, 5.2 Fast, 5.1, 5
- MiMo V2.5 Pro, V2.5
- Step 3.7 Flash, 3.5 Flash
- Tencent HY3 Paid, HY3
- Meta Muse Spark 1.1
- Nvidia Nemotron 3 Ultra

## Authentication

The bridge reads credentials from `~/.commandcode/auth.json` (created by `cmd login`).

For new users:
1. Run `cmd login` in your terminal (opens browser for OAuth with GitHub)
2. Or press `[l]` in the bridge TUI for login panel
3. After login, press `[r]` to refresh data

The bridge proxies your auth to the Command Code API. No separate API key needed.

## Build from Source

```bash
git clone <repo-url>
cd commandcode-bridge
./build           # dart pub get + dart compile exe
./run             # Start TUI
```

## Architecture

```
commandcode-bridge/
├── bin/commandcode_bridge.dart      # Entry point
├── lib/src/
│   ├── main.dart                    # CLI wiring (TUI / server modes)
│   ├── models/
│   │   ├── account.dart             # Account + config store (port persist)
│   │   └── models_db.dart           # 44 models with goAccessible field
│   ├── services/
│   │   ├── api_client.dart          # HTTP to api.commandcode.ai
│   │   └── log_store.dart           # JSONL activity log (2000 entries)
│   ├── server/
│   │   └── proxy.dart               # OpenAI-compatible proxy
│   └── tui/
│       └── app.dart                 # Nocterm TUI (9 panels + log)
├── test/
├── AGENTS.md
├── build / run                       # Shell scripts
├── build.bat / run.bat               # Windows batch scripts
├── LICENSE
└── pubspec.yaml
```

## Proxy Flow

```
OpenAI Client  ->  POST /v1/chat/completions  ->  Translate to CC wire format
                     |
                POST https://api.commandcode.ai/alpha/generate
                     |
                Translate SSE events back to OpenAI format
                     |
OpenAI Client  <-  data: {"choices":[...]}  <-  data: [DONE]
```

Request translation:
- OpenAI messages -> CC wire format (text, image, tool-call, tool-result)
- OpenAI params (model, stream, max_tokens, temperature) -> CC params
- Reasoning effort mapped to CC `reasoning_effort`

Response translation:
- `text-delta` -> `data: {"choices":[{"delta":{"content":"..."}}]}`
- `reasoning-delta` -> `data: {"choices":[{"delta":{"reasoning_content":"..."}}]}`
- `finish` -> final chunk with `finish_reason`
- `error` -> `data: {"error":{...}}`

## License

See LICENSE file.
