# Shop

Shopify sales + theme management, right from your Omarchy bar.

Shop is an Omarchy desktop-shell plugin. It shows live sales for each of your
Shopify stores in the bar and gives you full theme sync (push/pull/dev) without
leaving the shell. No token is stored by the plugin — authentication lives in the
Shopify CLI (`shopify`).

## Features

- **Live sales per store** — today's revenue + order count in the bar, with an
  ▲/▼ trend versus yesterday at the same time of day.
- **Per-store dashboard** — a six-range selector (Today, Yesterday, 7d, 14d, 30d,
  All) drives the Sales/Orders figures, a sparkline whose bar height is that
  period's sales and whose bar color is its per-day Revenue/Session Index
  (hover a bar for the day, amount, and RSI %), and an eight-stat grid: Sales,
  Orders, AOV, CVR, Visitors, Checkout CVR, ATC, and RSI. **RSI (Revenue/Session
  Index)** is today's revenue-per-session as a percentage of the all-time
  baseline — 100% is average, above means more revenue per session than usual,
  below less.
- **New-order notifications** — when a store's today order count rises, a desktop
  notification fires and a short coin sound plays (both toggleable together).
- **Theme sync** — push/pull with a per-store theme picker (defaults to the live
  theme; pick any draft/dev theme), a safety snapshot of the live theme before
  every push, one-click restore of any snapshot, and a live-preview `theme dev`
  mode with an "Open preview" link.
- **Store discovery** — pull your accessible stores from the Shopify CLI and add
  them in one click; auth is triggered in-app.
- **Per-store control** — toggle which stores show on the bar, and drag-to-reorder
  them.
- **Automatic CLI setup** — if the Shopify CLI is missing, the panel shows a
  warning with a one-click **Install** button (installs via
  `npm install -g @shopify/cli@latest`).

## Requirements

- [Omarchy](https://github.com/basecamp/omarchy) desktop shell
- [Shopify CLI](https://shopify.dev/docs/api/shopify-cli) (`shopify`) on PATH —
  or let the plugin install it for you (Node.js/npm ships with Omarchy via mise)
- `paplay` for the new-order sound (ships with PipeWire/PulseAudio — standard on
  Omarchy)
- No sudo required

## Install

```bash
omarchy plugin add https://github.com/ronald2wing/Omarchy-Shop --enable
```

After installing, add a store (Configure → Add store, or Discover stores). Adding
a store triggers a one-time browser authorization (Shopify `read_reports,read_orders`
scope); the token is stored by the Shopify CLI, not by this plugin.

## Removal

```bash
omarchy plugin remove shop
```

## Configuration

Config lives at `~/.config/shop/config.json`:

```json
{
  "refreshIntervalSec": 60,
  "notifyNewOrders": true,
  "stores": [
    {
      "name": "My Store",
      "domain": "my-store.myshopify.com",
      "themeDir": "/path/to/theme",
      "theme": "live",
      "showOnBar": true
    }
  ]
}
```

- `refreshIntervalSec` — how often (seconds) the service polls live sales. Theme
  history and completed-period stats refresh once an hour.
- `notifyNewOrders` — whether to notify (desktop notification + coin sound) when a
  store's today order count rises (default `true`; toggle it in Configure).
- `stores` — one entry per store:
  - `name`, `domain` (the `*.myshopify.com` subdomain) — required.
  - `themeDir` — optional local theme path (Push/Pull/Dev are disabled without it).
  - `theme` — `"live"` (default) or a specific theme id, set via the theme picker.
  - `showOnBar` — whether this store appears on the bar (a new store defaults to
    hidden once 3 stores are already shown).
- Currency is auto-detected from Shopify — there is no `currency` field.

Runtime state is written by the service to `~/.local/state/shop/state.json`.
`~/.local/state/shop/history.json` holds a rolling 48h of 5-minute same-time
stats snapshots used for the per-stat ▲/▼ trends.
Theme snapshots are stored under `~/.local/state/shop/backups/<domain>/`.

## Keyboard shortcuts (with the popup open)

`r` refresh all · `c` configure / back · `p` push · `u` pull · `a` auth

## Troubleshooting

**Theme push/pull fails with "Theme CLI authentication failed"** — your Shopify
OAuth session is stale. Run in a terminal:

```bash
shopify auth logout && shopify auth login
```

(logout first — login alone is often insufficient to clear a stale session.)

**"Shopify CLI not found"** — the Shopify CLI is missing from your PATH. Click
**Install** in the banner to install it via npm (takes a few seconds), or install
it yourself from <https://shopify.dev/docs/api/shopify-cli>.
