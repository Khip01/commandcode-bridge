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

## Key Bindings

| Key | Context | Action |
|-----|---------|--------|
| `1-6` | Always | Switch info page |
| `r` | Always | Refresh all API data |
| `o` | Always | Copy OpenAI endpoint URL to clipboard |
| `a` | Always | Copy Anthropic URL to clipboard |
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

## Authentication

The bridge reads credentials from `~/.commandcode/auth.json` (created by `cmd login`).

1. Run `cmd login` in your terminal (opens browser for OAuth with GitHub)
2. Or press `[l]` in the bridge TUI for login panel
3. After login, press `[r]` to refresh data
