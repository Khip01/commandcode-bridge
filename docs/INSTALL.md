# Installation

## Quick Install (from npm tarball)

Download the `.tgz` from [GitHub Releases](https://github.com/Khip01/commandcode-bridge/releases/latest), then:

```bash
npm install -g ./commandcode-bridge-vX.Y.Z.tgz
commandcode-bridge run
```

## Updating

Once installed, update from the bridge itself:

```bash
commandcode-bridge update
```

The update command fetches the latest release tag from GitHub API, downloads the
`.tgz` asset, removes the previous install, and runs `npm install -g`. The API
call is cached locally for 1 hour to avoid rate limits. A restart is required
after updating.

## Build from Source

```bash
git clone https://github.com/Khip01/commandcode-bridge
cd commandcode-bridge
./build           # dart pub get + dart compile exe
./run             # TUI mode
./run --server    # Headless server mode
```

Requires Dart SDK 3.10+.

## Platform Support

| Platform | Status | Clipboard |
|----------|--------|-----------|
| Linux | Primary (fully tested) | `wl-copy` -> `xclip` -> OSC 52 |
| macOS | Experimental | `pbcopy` -> OSC 52 |
| Windows | Experimental | `clip` -> OSC 52 |

## Prerequisites

- Node.js 18+ (for npm launcher)
- A Command Code account with active plan
- Run `cmd login` to authenticate first
