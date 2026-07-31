# Proxy Endpoints

All endpoints at `http://127.0.0.1:17077`.

## OpenAI Compatible

Base URL: `http://127.0.0.1:17077/v1`

| Path | Method | Description |
|------|--------|-------------|
| `/v1/chat/completions` | POST | Chat completions (stream + non-stream) |
| `/v1/models` | GET | List 44 available models |
| `/v1/health` | GET | Health check |
| `/v1/token` | GET | Get current access token |
| `/v1/info` | GET | Bridge info and config |

## Anthropic Compatible

Base URL: `http://127.0.0.1:17077`

| Path | Method | Description |
|------|--------|-------------|
| `/v1/messages` | POST | Messages API (stream + non-stream) |
| `/messages` | POST | Messages API (alternative path) |

## API Key

Any value works. The bridge uses your saved Command Code auth from `~/.commandcode/auth.json`.

## Client Configuration

### OpenCode (OpenAI Compatible)

```jsonc
"Command Code": {
  "name": "Command Code",
  "options": {
    "baseURL": "http://127.0.0.1:17077/v1",
    "apiKey": "anything"
  },
  "models": {
    "deepseek/deepseek-v4-pro": {
      "name": "Command Code - DeepSeek V4 Pro /Op",
      "tool_call": true,
      "reasoning": true,
      "limit": { "context": 1048576, "input": 1048576, "output": 8192 }
    }
  }
}
```

### OpenCode (Anthropic Compatible)

```jsonc
"Command Code Anthropic": {
  "npm": "@ai-sdk/anthropic",
  "name": "Command Code Anthropic",
  "options": {
    "baseURL": "http://127.0.0.1:17077/v1",
    "apiKey": "anything"
  },
  "models": {
    "deepseek/deepseek-v4-pro": {
      "name": "Command Code - DeepSeek V4 Pro /An",
      "tool_call": true,
      "reasoning": true,
      "limit": { "context": 1048576, "input": 1048576, "output": 8192 }
    }
  }
}
```

### Zed (Anthropic Compatible)

Zed reads providers from `settings.json` under `language_models.anthropic_compatible`.
The API key must be entered through **Agent Settings** (`agent: open settings` -> LLM Providers).

`api_url` must be the base URL **without** `/v1` — Zed auto-appends `/v1/messages`.

```jsonc
"Anthropic Command Code (Go Plan) - Khip01 Local": {
  "api_url": "http://127.0.0.1:17077",
  "available_models": [
    {
      "name": "deepseek/deepseek-v4-pro",
      "display_name": "DeepSeek V4 Pro - CommandCode",
      "max_tokens": 1000000,
      "max_output_tokens": 64000,
      "extra_beta_headers": [],
      "capabilities": {
        "tools": true,
        "images": false,
        "prompt_caching": false
      }
    }
  ]
}
```

After saving, open Agent Settings, find the provider, enter any API key
(the bridge uses your saved Command Code auth, the value does not matter),
and the model will appear in the model dropdown.

## Cost Tracking

To make your CLI agent report real Command Code costs, run:

```bash
commandcode-bridge cost-sync
```

or press `[c]` on the Cost Sync page in the TUI. This writes per-model cost
fields (input, output, cache_read per 1M tokens) into your agent configs.
The pricing table is validated against the live bridge `/v1/models` endpoint
before syncing.
