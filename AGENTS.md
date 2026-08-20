# AGENTS.md

Omarchy desktop-shell plugin (QML/Quickshell) for Shopify theme push/pull + per-store sales. Plugin id `shop`.

## Verify

Run all checks before claiming done (validate → lint → scripts → tests):

```bash
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell Service.qml
qmllint -I /usr/share/omarchy/shell BarWidget.qml
bash -n bin/sales.sh bin/theme.sh tests/test-sales.sh tests/test-theme.sh tests/fake-shopify
node tests/test-model.js
bash tests/test-sales.sh
bash tests/test-theme.sh
```

- `qmllint` REQUIRES `-I /usr/share/omarchy/shell` or the `qs.Commons`/`qs.Ui` imports won't resolve.
- `omarchy plugin validate .` checks the manifest schema and that entry points exist.
- `tests/fake-shopify` is a test double that shadows the real `shopify` CLI; it is not shipped with the plugin.

## Architecture

Dual-kind plugin: `service` (headless, owns IPC) + `bar-widget` (UI).

- `Service.qml` does all work: loads config, polls sales, runs theme push/pull/dev, owns the `IpcHandler` (target = plugin id `shop`).
- `BarWidget.qml` reads state from `~/.local/state/shop/state.json` via `FileView{watchChanges:true}` — display is FILE-DRIVEN. IPC is only for ACTIONS (not for reading state).
- `Model.js` is the only unit-tested logic: ShopifyQL parsing + money/percent/count formatting + natural sort. It is `module.exports`-guarded so it loads under both Node (tests) and QML (`import "Model.js" as M`). Keep parsing/formatting here, not in QML.
- `bin/sales.sh <domain> [live|historical]` / `bin/theme.sh` are thin wrappers over the `shopify` CLI. Both start with a `command -v shopify` guard that emits a friendly "install it from https://shopify.dev/docs/api/shopify-cli" message + exit 127 when the CLI is missing. No credentials live in the plugin; all Shopify access shells out to the CLI.
- **Sales polling is split into two cadences** to cut GraphQL cost: `refreshLive()` (60s `pollTimer`) fetches only `today` + today `stats`; `refreshHistorical()` (hourly `historicalPollTimer`, `triggeredOnStart`) fetches the completed-period ranges + TIMESERIES + range stats. `startFetch(dm, mode)` dedups per `dm:mode`. A manual `refresh()`/`refreshStore(dm)` triggers both.
- **New-order alert** (in `handleSales` live branch): when a store's today order count rises vs `prevOrders[dm]`, fires `notify-send` AND plays the bundled sound via `paplay <sourceDir>/sounds/coin.oga`, both gated by `notifyNewOrders`.

**IPC surface** (`omarchy-shell shop <method>`): `ping`, `refresh`, `refreshStore <domain>`, `push <domain>`, `pull <domain>`, `addStore <name> <domain> <themeDir>`, `updateStore <domain> <field> <value>`, `removeStore <domain>`, `reorderStore <domain> <index>`, `authStore <domain>`, `discoverStores`, `restoreBackup <domain> <epoch>`, `startDev <domain>`, `stopDev <domain>`, `setNotifyNewOrders <bool>`, `installCli`.

## Config & state

Config `~/.config/shop/config.json`:

```json
{ "refreshIntervalSec": 60, "notifyNewOrders": true, "stores": [ { "name", "domain", "themeDir", "theme", "showOnBar" } ] }
```

- `domain` is the `*.myshopify.com` subdomain (the CLI's `--store`). `themeDir` optional (theme ops disabled without it). `theme` = `"live"` or a numeric theme id. `showOnBar` = bool (bar visibility). No `currency` field — it's auto-detected from Shopify.

State `~/.local/state/shop/state.json` — top-level `notifyNewOrders`, `cliMissing`, `cliInstalling`, `cliInstallError`; per store: `name, domain, currency, today, week, biweek, month, allTime, yesterdaySoFar, yesterday, yesterdayStatsSoFar, statsToday, statsYesterday, statsWeek, statsBiweek, statsMonth, statsAll, weekSeries, biweekSeries, monthSeries, allTimeSeries, weekSessionsSeries, biweekSessionsSeries, monthSessionsSeries, allTimeSessionsSeries, lastUpdated, lastError, lastSyncOutput, lastSyncError, syncing, themeSyncing, themeAction, authed, devRunning, devUrl, showOnBar`. `yesterdayStatsSoFar` is a per-store `{sessions,visitors,cvr,atc,checkoutCvr}` object = the ~24h-ago same-time snapshot (null when no snapshot is within ±15 min, so the sessions-stats trend stays hidden until 24h of snapshots accumulate). The `*SessionsSeries` arrays are `[{day, sessions}]` (monthly for `allTimeSessionsSeries`), zipped index-for-index with the matching `*Series` sales arrays to render the RSI sparkline.

## Gotchas (hard-earned — do not re-learn these)

- **A `service` kind receives NO `settings` property.** The shell injects only `omarchyPath`/`shell`/`manifest`/`barWidgetRegistry`/`pluginRegistry` (see `ensureService` in `/usr/share/omarchy/shell/shell.qml`). `barWidget.defaults`/`schema` bind to the WIDGET only. Put service tunables (e.g. `refreshIntervalSec`) in `~/.config/shop/config.json`, read via `FileView` — do NOT add a `setting()` helper that reads `settings`.
- **Config/state MUST live OUTSIDE the plugin dir.** Writing inside the plugin dir trips the shell hot-reload watcher. Use `Quickshell.env("HOME")`, never hardcoded `/home/...` paths.
- **The bar-widget must NOT register a second `IpcHandler`.** Root is `Panel { moduleName; manageIpc: false }` — the service owns the target.
- **Don't declare signals that shadow base QML signals** (a component `signal focusChanged` shadows `Item.focusChanged` and can fail to load). Prefix custom signals (e.g. `fieldFocusChanged`).
- **QML property names must start with a lowercase letter.** `readonly property int RANGE_TODAY` PASSES `qmllint` but fails at RUNTIME with "Property names cannot begin with an upper case letter" (widget silently fails to load → bar icon vanishes). Always camelCase properties (`rangeToday`).
- **Qt 6.11 dropped implicit signal-param injection.** Handlers must use arrow functions — `onFieldTextChanged: (text) => root.editName = text`, NOT `onFieldTextChanged: root.editName = text`.
- **Changing IPC method names does NOT take effect via `disable`/`enable` or hot-reload.** The running `quickshell` caches the old QML component. Run `omarchy-restart-shell` (see `/usr/share/omarchy/shell/README.md:195`). Test IPC with `omarchy-shell [-q] <id> <method> [args...]`.
- **`FileView.setText()` skips the write when content is unchanged.** If the write is used as a change SIGNAL (e.g. discovery completion), include an always-changing field (`discoveredAt: Date.now()`) or the watcher never fires.
- **Store names come from `shop { name }`**, not the org walk. `shopify store execute -j -s <domain> -q '{ shop { name } }'` returns the display name in one fast call (the org walk was ~20s and was removed).
- **"today" is real-time `orders`; the ranges are ShopifyQL.** `FROM sales` analytics LAGS the current day, so `today` (and `yesterdaySoFar`, the same-time-of-day comparison for the ▲/▼ trend) use `orders(first:250, query:"created_at:>=$today")`; `week`/`biweek`/`month`/`allTime`/`yesterday` (calendar) use `shopifyqlQuery`. ShopifyQL `SINCE -1d UNTIL -1d` is a zero-width window ($0) — calendar "yesterday" is `SINCE -1d UNTIL -0d`; the sparkline drops today's always-zero bucket.
- **Rates are FRACTIONS** (e.g. `0.005` = 0.5%); `formatPercent` ×100 renders them. ShopifyQL returns `conversion_rate` etc. as fractions.
- **`statsAll` is bounded to `SINCE -365d UNTIL -0d`.** A no-filter `FROM sessions` query costs the full 1000-point shopifyqlCost budget and always throttles, so the "All" tab shows all-time Sales/Orders/AOV but only trailing-year Visitors/CVR/ATC/Checkout. The sales `allTime` range (`FROM sales`, no filter) is genuinely unbounded.
- **`npm install -g @shopify/cli` takes ~6-9s for the mise shim to resolve.** The install process itself returns in ~1.4s, but `~/.local/share/mise/shims/shopify` only appears 6-9s later (mise reshim). The install flow therefore keeps `cliInstalling` true after npm exits and RETRIES the sales poll (`installRefreshTimer`, 3s interval, up to 10 tries) until `cliMissing` clears — never use a one-shot short delay here.

## Shopify data path (verified against a live store)

- Sales: `shopify store execute -j -s <domain> -q '<GraphQL>'`. Scope **`read_reports,read_orders`** (NOT `read_analytics`). One-time per store: `shopify store auth -s <domain> --scopes read_reports,read_orders` (the plugin runs this in-app via `authStore`).
- `-j` output has **no top-level `data` wrapper** — queried fields are top-level, all cell values are strings.
- Theme: `shopify theme push|pull --store <domain>` uses the existing OAuth session (`shop.admin.themes` scope) — no separate auth. Theme auth 401 ("Service is not valid for authentication") = stale session → `shopify auth logout && shopify auth login`.

## QML idiom references

- `~/.config/omarchy/plugins/genesis/` — the user's own service+widget plugin (Process/StdioCollector/IpcHandler/FileView idioms; the canonical bar-widget Panel + KeyboardPanel pattern).
- `/tmp/opencode/omarchy-ref/` — cloned community plugins (wireguard: `actionRejection`/watchdog; flight-radar; docker: `Model.js` pattern).
- `/usr/share/omarchy/shell/plugins/` — first-party (media = service+widget; weather = FileView state; tailscale/dropbox = canonical scrollable-panel Flickable idiom).

## Notes

- Publishing target is `https://github.com/ronald2wing/Omarchy-Shop` (manifest `homepage`/`repository`; git remote `origin` → `git@github.com:ronald2wing/Omarchy-Shop.git`).
- Nerd-font glyphs in UI strings are fine (project convention, matches `genesis`); this overrides the global "no emoji" rule for UI strings only — keep comments emoji-free.
