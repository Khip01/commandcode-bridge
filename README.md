# CommandCode Bridge

Single-account proxy bridge for [Command Code](https://commandcode.ai) CLI (`cmd`).
TUI dashboard with progress bars + OpenAI-compatible and Anthropic-compatible HTTP
proxy endpoints.

Turn your Command Code Go plan ($1/month) into OpenAI and Anthropic-compatible
APIs for use with OpenCode, Zed, Cursor, or any compatible client.

<img width="1901" height="927" alt="Screenshot" src="https://github.com/user-attachments/assets/c174095e-0bdd-4197-a152-bf6fd7f34056" />

## Features

- **OpenAI Compatible** — `/v1/chat/completions` endpoint, streaming + non-streaming
- **Anthropic Compatible** — `/v1/messages` endpoint with full SSE streaming
- **TUI Dashboard** — 6 info pages with progress bars and real-time log
- **Plan-Aware** — Models sorted by plan access level
- **Port Config** — Change port via TUI with availability scan, persisted across restarts
- **Cross-platform** — Linux (primary), macOS/Windows (experimental)

## Quick Install

```
npm install -g ./commandcode-bridge-v1.1.1.tgz
commandcode-bridge run
```

Update when a new release is available:

```
commandcode-bridge update
```

Requirements: Node.js 18+, a Command Code account.

## Documentation

- [Installation](docs/INSTALL.md) — install options, prerequisites, platform support
- [API Reference](docs/API-REFERENCE.md) — proxy endpoints, client configs (OpenCode, Zed, Cursor)
- [TUI](docs/TUI.md) — pages, key bindings, plan access, port config
- [Architecture](docs/ARCHITECTURE.md) — file structure, proxy flow, protocol translation
- [Changelog](CHANGELOG.md) — release history

## License

MIT. See [LICENSE](LICENSE).
