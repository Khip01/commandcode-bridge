# Architecture

## Stack

- Language: Dart 3.10+
- TUI: `nocterm` v0.8.0
- Server: `dart:io` `HttpServer`
- HTTP client: `dart:io` `HttpClient`
- Compile: `dart compile exe` -> single native binary
- Distribution: npm tarball with Node.js launcher wrapper

## File Structure

```
commandcode-bridge/
├── bin/
│   ├── commandcode_bridge.dart        # Dart entry point
│   └── commandcode-bridge.js          # npm wrapper (spawns native binary)
├── lib/
│   ├── commandcode_bridge.dart        # Barrel export
│   └── src/
│       ├── main.dart                  # CLI wiring (TUI / server / cost-sync modes)
│       ├── models/
│       │   ├── account.dart           # Account + config store (port persist)
│       │   ├── models_db.dart         # 52 bundled models + plan access metadata
│       │   └── version.dart           # Bridge version constant
│       ├── services/
│       │   ├── api_client.dart        # HTTP client for api.commandcode.ai (incl. /provider/v1/models)
│       │   ├── cost_sync.dart         # Cost sync: detect agents, update configs
│       │   ├── log_store.dart         # JSONL activity log (2000 entries max)
│       │   ├── pricing_db.dart        # Hardcoded pricing table (52 models)
│       │   └── updater.dart           # Self-update: API cache + download .tgz + npm install -g
│       ├── server/
│       │   ├── server_controller.dart  # HTTP server, routing, shared endpoints
│       │   ├── openai_handler.dart     # OpenAI-compatible proxy
│       │   └── anthropic_handler.dart  # Anthropic-compatible proxy
│       └── tui/
│           └── app.dart               # Nocterm TUI (10 panels + log sidebar)
├── scripts/
│   └── stage-npm-package.mjs         # CI packaging helper
├── docs/
├── test/
├── AGENTS.md
├── CHANGELOG.md
├── build / run                        # Shell scripts
├── build.bat / run.bat                # Windows batch scripts
├── LICENSE
├── package.json
└── pubspec.yaml
```

## Proxy Flow

```
Client -> POST /v1/chat/completions  -> Translate to CC wire format
                  |                         |
            POST https://api.commandcode.ai/alpha/generate
                  |                         |
            Translate NDJSON events back to target format
                  |
Client <- OpenAI SSE / Anthropic SSE

Client -> POST /v1/messages           -> Same flow, Anthropic format
```

## Cost Sync

The `cost-sync` CLI command and TUI page 7 keep CLI agent cost tracking in
sync with Command Code pricing.

- `pricing_db.dart` holds a hardcoded pricing table (52 models) matching the
  live bridge `/v1/models` API
- `cost_sync.dart` detects installed CLI agents (OpenCode, Aider, Goose),
  reads each agent's configured models, and writes per-model cost fields
  (input, output, cache_read per 1M tokens)
- Only providers that point at the bridge (localhost base URL) and are named
  "Command Code" are considered bridge providers; all are listed
- Pricing is validated against the live `/v1/models` endpoint before syncing
- OpenCode configs (JSONC) are parsed with comment and trailing-comma support

## Dynamic Model List

The bridge does not rely solely on its bundled registry. On every TUI refresh
(`[r]` or auto-refresh) it calls the official Command Code endpoint
`GET /provider/v1/models`, caches the result in memory, and merges it with the
52 bundled `ModelsDb` models. This means newly released models (for example
`inclusionai/ling-3.0-flash-free`, `poolside/laguna-s-2.1-free`) are served by
`/v1/models` and shown in the TUI without needing a bridge release.

- `api_client.fetchModels()` returns the live model list from the API
- `ServerController.setLiveModelIds()` updates the in-memory cache used by `/v1/models`
- Unknown live models are still proxyable and appear with `owned_by: command-code`
- TUI page 5 groups models by plan access (Go/Pro/Max) using `PlanAccess`, which
  mirrors the official CLI's `evaluateModelAccess`: Go = open source + GPT-5.6
  Luna / Grok 4.5, Pro blocks Fable/Opus + Fugu Ultra, and a credits override
  (purchased or free credits) grants access to everything

## Protocol Translation

### OpenAI Compatible

Request translation:
- System messages extracted to `system` field
- Tool messages converted to `{role: "tool", content: [{type: "tool-result", ...}]}`
- Assistant tool_calls converted to `{type: "tool-call", ...}` blocks
- OpenAI params (model, stream, max_tokens, temperature) mapped to CC params

Response translation:
- `text-delta` -> `data: {"choices":[{"delta":{"content":"..."}}]}`
- `reasoning-delta` -> `data: {"choices":[{"delta":{"reasoning_content":"..."}}]}`
- `tool-call` -> `data: {"choices":[{"delta":{"tool_calls":[...]}}]}`
- `finish` -> final SSE chunk with `finish_reason`
- `error` -> `data: {"error":{...}}`

### Anthropic Compatible

Request translation:
- System prompt extracted from top-level `system` field (string or content blocks)
- Anthropic content blocks (`text`, `tool_use`, `tool_result`, `image`) converted to CC wire format
- Anthropic tools (`input_schema`) mapped to CC tools
- `tool_choice` and `thinking` settings translated

Response translation:
- `message_start` -> SSE event initiating the message
- `text-delta` -> `content_block_start(text)` + `content_block_delta(text_delta)` + `content_block_stop`
- `reasoning-delta` -> `content_block_start(thinking)` + `content_block_stop` (if available)
- `tool-call` -> `content_block_start(tool_use, input:{})` + `content_block_delta(input_json_delta)` + `content_block_stop`
- `finish` -> `message_delta(stop_reason)` + `message_stop`
- `error` -> SSE error event
