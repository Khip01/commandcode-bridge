# CommandCode Bridge

Single-account proxy bridge for Command Code CLI (`cmd` from `commandcode.ai`). TUI dashboard + OpenAI-compatible HTTP proxy.

## Auth

Command Code auth is stored at `~/.commandcode/auth.json`. The bridge reads the API key from this file. Run `cmd login` to authenticate first. You can also press `[l]` in the bridge TUI for login instructions.

## Architecture

### Stack
- Language: Dart 3.10+
- TUI: `nocterm` v0.8.0
- Server: `dart:io` `HttpServer`
- HTTP client: `package:http`
- Compile: `dart compile exe` -> single binary

### File Structure
```
commandcode-bridge/
├── bin/commandcode_bridge.dart      # Entry point
├── lib/
│   ├── commandcode_bridge.dart      # Barrel
│   └── src/
│       ├── main.dart                # CLI wiring
│       ├── models/
│       │   ├── account.dart         # Account + config store (port persist)
│       │   └── models_db.dart       # 44 models with goAccessible field
│       ├── services/
│       │   ├── api_client.dart      # HTTP client for api.commandcode.ai
│       │   └── log_store.dart       # JSONL activity log (2000 entries)
│       ├── server/
│       │   └── proxy.dart           # OpenAI-compatible proxy
│       └── tui/
│           └── app.dart             # Nocterm TUI (9 panels + log)
├── test/
├── AGENTS.md
├── README.md
├── build                            # Build script
├── run                              # Run script
├── LICENSE
└── pubspec.yaml
```

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
| `/v1/chat/completions` | POST | OpenAI-compatible chat (stream + non-stream) |
| `/v1/models` | GET | List 44 available models |
| `/v1/health` | GET | Health check |
| `/v1/token` | GET | Get access token |
| `/v1/info` | GET | Bridge info + config |

## OpenCode Configuration

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

Status bar between content and footer, color-coded:
- Green: success (data refreshed, copied)
- Cyan: info (fetching, copying)
- Yellow: warning (clear confirm, restart required)
- Red: error (failed, invalid, port in use)

## Clipboard

Copy to clipboard via `wl-copy` -> `xclip` -> OSC 52 fallback.
- `[c]` -- Copy endpoint URL (`http://127.0.0.1:17077/v1`)
- `[Enter]` on model page -- Copy selected model codename

## TUI Pages

| Key | Page | API Endpoints Used |
|-----|------|--------------------|
| `1` | Account | `/alpha/whoami` |
| `2` | Plan & Billing | `/alpha/billing/subscriptions` + `/alpha/billing/credits` |
| `3` | Usage | `/alpha/usage/summary` |
| `4` | Rate Limits | `/alpha/billing/credits` (windowLimits) |
| `5` | Models | `_orderedModels` (sorted by plan, 44 total) |
| `6` | Proxy Config | Bridge state + endpoints |

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
| `Shift+C` | Log open | Clear all logs (with confirmation) |
| `O` | Log open | Clear logs before today (with confirmation) |
| `l` | Not auth'd | Open login instructions panel |
| `Esc` | Sub-panels | Back to main |

## Build & Run

```bash
./build           # Compile single binary
./run             # TUI mode (proxy auto-starts at 17077)
./run server      # Headless server mode
```
