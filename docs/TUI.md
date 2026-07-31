# TUI Reference

## Pages

| Key | Page | Data Source | Visuals |
|-----|------|-------------|---------|
| `1` | Account | `/alpha/whoami` | Text info (name, email, user ID) |
| `2` | Plan & Billing | `/alpha/billing/subscriptions` + credits | Progress bars for billing period, credit usage |
| `3` | Usage | `/alpha/usage/summary` | Success rate bar, token bars, cost breakdown |
| `4` | Rate Limits | `/alpha/billing/credits` | 5-hour and weekly usage bars with exceed warnings |
| `5` | Models | 44 models sorted by plan access | Scrollable list, Enter to copy codename |
| `6` | Proxy Config | Bridge state | Port, API URL, endpoints, uptime |
| `7` | Cost Sync | Local CLI agent configs | Detected agents, provider list, model pricing, sync status |

## Key Bindings

| Key | Context | Action |
|-----|---------|--------|
| `1-7` | Always | Switch info page |
| `r` | Always | Refresh all API data |
| `o` | Always | Copy OpenAI endpoint URL to clipboard |
| `a` | Always | Copy Anthropic URL to clipboard |
| `p` | Always | Configure proxy port (with availability scan) |
| `h` | Always | Open help |
| `q` | Always | Quit (with confirmation) |
| `Ctrl+C` | Always | Status bar hint (use [q] to quit) |
| `up/down` | Main | Scroll content / navigate models / select cost sync agent |
| `PgUp/PgDn` | Main | Scroll 10 lines |
| `Enter` | Models page | Copy selected model codename to clipboard |
| `c` | Cost Sync page | Sync model pricing to selected agent |
| `Ctrl+L` | Always | Toggle log sidebar |
| `f` | Log open | Toggle log fullscreen / sidebar |
| `Shift+C` | Log open | Clear all logs (with Y/N confirmation) |
| `O` | Log open | Clear old entries (with Y/N confirmation) |
| `l` | Not authenticated | Open login instructions |

## Status Notifications

- **Green**: Success (data refreshed, clipboard copied)
- **Cyan**: Info (fetching data, processing)
- **Yellow**: Warning (confirmation needed, restart required)
- **Red**: Error (failed, invalid input, port in use)

## Port Configuration

Press `[p]` to open port config panel:
- Enter any port (1024-65535), tested before saving
- Empty input resets to default (17077)
- Available ports scanned dynamically
- Config saved to `~/.config/commandcode-bridge/config.json`
- Restart required for change to take effect

If the configured port is in use at startup, the bridge auto-increments
(port+1, port+2, ...) up to 100 attempts until it finds a free port.
The switch is logged and the running port is shown in the header.

## Plan Access

Models in page 5 are prioritized by your plan:

| Plan | Sort Order | Accessible |
|------|-----------|------------|
| individual-go | Opensource first (green), Premium dimmed | Opensource only |
| individual-pro | Premium first | Premium + opensource (blocked: top Claude + Fugu) |
| individual-max | Premium first | All models |
| individual-ultra | Premium first | All models |
| teams-pro | Premium first | All models |

### Go Plan Accessible Models

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

## Cost Sync (Page 7)

Syncs Command Code model pricing into your CLI agent configs so that
agent-side cost tracking shows real per-token rates.

- `[7]` opens the Cost Sync page
- `[c]` syncs pricing for the selected agent (hint shown on the page)
- `[up/down]` selects the agent (OpenCode, Aider, Goose)
- Detected agents are listed with their config paths
- Bridge providers are listed by name and endpoint, for example
  `Khip01 - Command Code (Go Plan) [127.0.0.1:17077]`
- All Command Code models with pricing are shown, grouped by Open Source and Premium
- Models in your config appear bright white with "(will be implemented)"
- Models not in your config are greyed out
- Pricing is validated against the live bridge `/v1/models` before syncing

The equivalent CLI command is `commandcode-bridge cost-sync`.

## Authentication

The bridge reads credentials from `~/.commandcode/auth.json` (created by `cmd login`).

1. Run `cmd login` in your terminal (opens browser for OAuth with GitHub)
2. Or press `[l]` in the bridge TUI for login panel
3. After login, press `[r]` to refresh data
