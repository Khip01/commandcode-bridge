# TUI Reference

## Pages

| Key | Page | Data Source | Visuals |
|-----|------|-------------|---------|
| `1` | Account | `/alpha/whoami` | Text info (name, email, user ID) |
| `2` | Plan & Billing | `/alpha/billing/subscriptions` + credits | Progress bars for billing period, credit usage |
| `3` | Usage | `/alpha/usage/summary` | Success rate bar, token bars, cost breakdown |
| `4` | Rate Limits | `/alpha/billing/credits` | 5-hour and weekly usage bars with exceed warnings |
| `5` | Models | Live API + bundled models, dynamic availability (active / new / expired) | Scrollable list, Enter to copy codename |
| `6` | Proxy Config | Bridge state | Port, API URL, endpoints, uptime |
| `7` | Cost Sync | Local CLI agent configs | Detected agents, provider list, model pricing, sync status |

## Refresh Behavior

Data is fetched from Command Code only when you press `[r]` (manual foreground
refresh) or once in the background when you open a page (throttled to once per
10 seconds). The bridge does not poll the API continuously while you stay on a
page, so viewing the Models or Cost page does not spam the Command Code
endpoints.

## Key Bindings

| Key | Context | Action |
|-----|---------|--------|
| `1-7` | Always | Switch info page |
| `r` | Always | Refresh all API data (manual) |
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
| `Shift+O` | Log open | Clear old entries (with Y/N confirmation) |
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

Page 5 renders the **live model list** (fetched from `/provider/v1/models` on
refresh, merged with bundled models) and groups models by what your plan can
actually use. Availability is classified dynamically via `ModelsDb.classify`,
mirroring the CLI (no hardcoded list): active models first, then a "New /
Coming soon" section (newly released, in the API but not yet bundled), then an
"Expired / No longer provided" section at the very bottom (free promo ended by
timestamp or dropped from the catalog). Rules mirror the official Command Code
CLI:

| Plan | Accessible |
|------|-----------|
| individual-go | Open source models + GPT-5.6 Luna, Grok 4.5, Qwen Max & Plus |
| individual-pro | Premium + opensource, blocked: Claude Fable 5, Opus 5/4.8/4.7/4.6, Fugu Ultra |
| individual-provider / max / ultra / teams-pro | All models |

**Credits override:** if you have purchased or free credits
(`purchasedCredits > 0` or `freeCredits > 0`), every model becomes accessible
regardless of plan.

### Page 5 Layout

Models are grouped top-level by plan access first (all "available on your
plan" models together at the top), then:

1. **Usage:** free models (`Free usage`) before billed models (`Billing`)
2. **Provider:** within Billing, sub-grouped by provider (DeepSeek, Moonshot,
   ZAI, MiniMax, Xiaomi, Qwen, StepFun, Tencent, Nvidia, Thinking Machines,
   OpenAI, xAI, ...)

Blocked premium models are listed below under their own header. Use `up/down`
to select a model and `Enter` to copy its ID; the copy always matches the
highlighted row.

### Go Plan Accessible Models

Open source models plus the premium exceptions included on Go:
GPT-5.6 Luna, Grok 4.5, and Qwen Max & Plus. The rest of the premium lineup
(Claude, other GPT, Gemini, Muse Spark) is blocked on Go.

- DeepSeek V4 Pro, DeepSeek V4 Flash
- Kimi K3, K2.7 Code, K2.7 Code HighSpeed, K2.6, K2.5
- MiniMax M3 Free, M3, M2.7, M2.5
- Qwen 3.7 Max/Plus/Flash, 3.6 Max Preview/Plus
- GLM 5.2, 5.2 Fast, 5.1, 5
- MiMo V2.5 Pro, V2.5
- Step 3.7 Flash, 3.5 Flash
- Tencent HY3 Paid, HY3
- Thinking Machines Inkling, Inkling Small
- Poolside Laguna S 2.1 Free (Free usage), InclusionAI Ling 3.0 Flash Free (Free usage)
- Nvidia Nemotron 3 Ultra
- GPT-5.6 Luna, Grok 4.5

## Cost Sync (Page 7)

Syncs Command Code model pricing into your CLI agent configs so that
agent-side cost tracking shows real per-token rates.

- `[7]` opens the Cost Sync page
- `[c]` syncs pricing for the selected agent (hint shown on the page)
- Sync progress and result appear as a status-bar notification: green on success
  (e.g. "Cost sync OpenCode: 5 updated, 2 already configured"), red if any
  models failed, so the result is always visible without scrolling the page
- `[up/down]` selects the agent (OpenCode, Aider, Goose)
- Detected agents are listed with their config paths
- Bridge providers are listed by name and endpoint, for example
  `Khip01 - Command Code (Go Plan) [127.0.0.1:17077]`
- All Command Code models with pricing are shown, grouped by plan access first
  ("Available on Go" / "Requires Pro / Max", or "Available on your plan" /
  "Blocked on your plan" for other plans)
- Live-known models without local pricing data appear as "no pricing data" (yellow)
- Models in your config appear bright white with "(will be implemented)"
- Models not in your config are greyed out
- Pricing is validated against the live bridge `/v1/models` before syncing

The equivalent CLI command is `commandcode-bridge cost-sync`.

## Authentication

The bridge reads credentials from `~/.commandcode/auth.json` (created by `cmd login`).

1. Run `cmd login` in your terminal (opens browser for OAuth with GitHub)
2. Or press `[l]` in the bridge TUI for login panel
3. After login, press `[r]` to refresh data
