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
│       ├── main.dart                  # CLI wiring (TUI / server modes)
│       ├── models/
│       │   ├── account.dart           # Account + config store (port persist)
│       │   ├── models_db.dart         # 44 models with plan access metadata
│       │   └── version.dart           # Bridge version constant
│       ├── services/
│       │   ├── api_client.dart        # HTTP client for api.commandcode.ai
│       │   ├── log_store.dart         # JSONL activity log (2000 entries max)
│       │   └── updater.dart           # Self-update: API cache + download .tgz + npm install -g
│       ├── server/
│       │   ├── server_controller.dart  # HTTP server, routing, shared endpoints
│       │   ├── openai_handler.dart     # OpenAI-compatible proxy
│       │   └── anthropic_handler.dart  # Anthropic-compatible proxy
│       └── tui/
│           └── app.dart               # Nocterm TUI (9 panels + log sidebar)
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
