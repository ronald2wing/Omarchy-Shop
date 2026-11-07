# Contributing to Shop

Shop is a dual-kind Omarchy plugin (id `shop`): a headless `service`
(`Service.qml`) that owns all state, scheduling, child processes and the IPC
target, and a `bar-widget` (`BarWidget.qml`) that binds to the service object
and draws. Every Shopify call goes through extensionless Ruby helpers in
`helpers/`, which run the pinned Shopify CLI under supervision.

## Vocabulary

The same word means the same thing in Ruby, JS, QML, UI copy and these docs:

- `label` is the display string the user edits; `name` is a string Shopify
  reported (a theme, a shop).
- `folder` is the user's theme directory (`theme.folder`, `--folder=`);
  `dir` is only Shop's own state and config dirs (`Paths.*_dir`).
- `range` is the sales fetch dimension (`today|yesterday|history`); `scope`
  is only ever an OAuth scope.
- `action` is a job or confirm kind (`push|pull|restore|remove|addStore|
  installCli|signOut|resetConfig|allowLive`; a store's work in `store_busy`
  adds `preview|grant`);
  `format` is a KPI's rendering (`money|percent|count`).
- `result` is a helper's last outcome; `status` is an enum; `error` is
  `{code, message, …}`.
- The CLI login is the **account** (`sign-in`, `sign-out`, `signed_out`);
  per-store app access (`store auth`) is **sales access**
  (`grant-sales-access`, `sales_access_required`); listing the account's
  stores is **discovery** (`discover-stores`, "Find my stores").
- A **backup** is the copy of a remote theme taken before a push or
  restore (`Backups.take!`, `backupId`); a **folder copy** is the copy of
  a theme folder taken before a pull (`FolderCopies`, `folderCopy`,
  `folderCopies`; on disk it stays `backups/<domain>/local/`). `snapshot`
  is only the service snapshot.

## Layout

| Path | Role and invariants |
| --- | --- |
| `manifest.json` | The plugin manifest. Its `version` is the only version string; `Service.version` is its one reader (no Ruby reads it) |
| `Service.qml` | The service facade: the API (each method checks `Preflight`, then calls a model), the `IpcHandler` (opens dialogs, never changes state), the `model/*` composition and the published `snapshot` and `storeOrder`. `Snapshot.buildSnapshot` is pure; `status()` reads the build that was published |
| `BarWidget.qml` | The bar: binds `bar.shell.serviceFor("shop")`, draws the pills (`js/bar.mjs` `barModel`) and hosts the lazy `ShopPanel` and the `FolderDialog`. It holds no state the service owns |
| `model/` | Non-visual QML, one concern per file: helper runners (`HelperProcess`, `HelperStream`), stores on disk (`ConfigStore`, `CacheStore`, `StateDir`), sales (`SalesData`, `SalesScheduler`, `SalesAccess`, `OrderAlerts`), the account (`Account`, `Discovery`), themes (`ThemeInfo`, `ThemeJobs`, `Previews`), `Preflight`, `Consent` and `Clipboard`. Only `HelperProcess`/`HelperStream` start processes, with the deadline and cap from `js/timing.mjs`; every FileView writes atomically; a result with arrays goes through `Os.plain` before it is read (QML gotchas) |
| `js/` | Pure ES modules in the V4 subset, each with its own `tests/js/test_<module>.mjs`: the config schema and patches (`config`), the snapshot and its selectors (`snapshot`), sales and figures (`sales`, `hourly`, `metrics`, `schedule`, `dates`, `format`), themes (`themes`, `themejob`), the refusal rules (`preflight`), the UI's words and keys (`copy`, `errors`, `banner`, `confirm`, `keymap`, `bar`), and `timing`, `urls`, `os`, `text`. `copy` is the only home of UI text; `preflight` decides what is blocked, `banner` only displays it |
| `ui/` | One QML module of views and parts (UI conventions below). `Look` holds every size, colour and gap; `Copy` forwards `js/copy.mjs` and holds no string; `PlainLabel` is the only `Text`; `LineEdit` is the only text entry. `ShopPanel` owns navigation, keys, toasts and links; each view is a `PanelView` |
| `helpers/` | The 17 extensionless Ruby helpers, mode 755, hardened shebang, one JSON line each (Helper contract) |
| `lib/shop.rb` | The pins, `API_VERSION`, `SCOPES`, `TIMING` (the deadline table below) and test overrides; requires every module |
| `lib/shop/` | One module per file, named after it (`tree_walk.rb` holds `Shop::TreeWalk`). `child` holds the only `Process.spawn`, and only `shopify` and `tools` call `command`; `json` holds the nil-safe `Json.dig` for CLI data; `tree_walk` is the one lstat walker. A method name ends in `!` when it changes disk or process state (`Backups.prune!`) or when refusing with a `Shop::Failure` is its job (`Validate.domain!`); a query that only reads never does (`ThemeFolder.report`), even when bad input makes it raise |
| `assets/sounds/new-order.oga` | The order sound (fixed path; `notify-order` plays it) |
| `tests/run` | Every check, or the tests named on its command line (Checks) |
| `tests/ruby/` | Plain-assert Ruby tests, silent when they pass: `test_helper_<helper>.rb` per helper (dashes as underscores), `test_<module>.rb` per `lib/shop/<module>.rb` (`child` runs only under `command`, so `test_command.rb` covers it; `helper_main` is `test_main.rb`, since the `test_helper_` prefix belongs to helpers), and the source contracts: `test_contracts_helpers.rb` (helpers, lib, process rules, pins, queries, `Command`'s callers), `test_contracts_qml.rb` (QML and JS rules, qmldirs), `test_contracts_docs.rb` (every README and CONTRIBUTING claim the code can check), `test_contracts_payload.rb` (agent files, internal ids, the archive), `test_contracts_fixtures.rb` (`tests/js/fixtures/` against real `fetch-sales` output) and `test_contracts_parity.rb` (this naming). `support.rb` is shared (the throwaway `FakeHome`, `run_helper`, the asserts); `launcher.rb` runs one helper in a fresh interpreter with test overrides (tool paths, PATH, deadlines, the clock) |
| `tests/js/` | Node tests, silent when they pass: `test_<module>.mjs` per `js/<module>.mjs`, plus `test_copy_keys.mjs` (the Copy key grammar and coverage) and `test_js_subset.mjs` (`js_subset.json`, the V4 denylist). `fixture.mjs` reads `fixtures/` (canned `fetch-sales` results with `fetch-sales`'s exact shape, and config files) and the shared `tests/fixtures/` |
| `tests/qml/` | The smokes, one `<name>_smoke.qml` each: `js_modules`, `consent`, `service`, `bar_widget`, `dialog`, `model_doubles` and the panel's, one per view (`panel_home`, `panel_store`, `panel_add`, `panel_edit`, `panel_backups`, `panel_settings`). `Smoke.qml` runs every smoke's steps and prints its token; `PanelHarness.qml` is the real `ShopPanel` against a stand-in service for the panel smokes; `fake-home.sh` fills the throwaway HOME each smoke runs in |
| `tests/fixtures/` | `bin/`: `fake-shopify` (the CLI's `run.js` with scenarios), `fake-node`, `fake-mise`, `fake-npm`, `fake-tool` (the notify-send/pw-play/paplay double), `fake-wl-paste` (the clipboard `read-clipboard` reads), and the `stub-<helper>` doubles `model_doubles_smoke.qml` runs as helpers. `cli/*.json`: canned CLI output. `control-codepoints.json`: Ruby's control-character set, which `js/text.mjs` must match |

Each `qmldir` (`model/`, `ui/`) lists every `.qml` beside it and has no `module` line.

Rules the models own:

- `Account`: a failed account check, or one that answers `unknown` with an
  error, re-runs by itself after 30 s, doubling up to 5 min; a good answer
  resets it. `cli` `unknown` with an `error` shows that error (Settings, a
  `CLI error` bar pill), never "Checking…".
- `Discovery`: Sign in and Sign out cancel a running discovery and a
  finished sign-in restarts it; a report from a run that started before the
  last sign-in or sign-out finished is dropped.
- `ThemeInfo`: a rate-limited theme list retries itself once, at
  `retryAfter`; any other `listThemes` call replaces that retry.
- `HelperProcess`/`HelperStream`: a helper killed by a signal ends as
  `terminated` in both modes (a theme job ending that way has unknown
  writes); a plain non-zero exit does not.
- `Previews`: a preview stays `stopping` from a stop or its `exited` line
  until the stream ends, then `stopped` or `failed`.
- `SalesScheduler`: the stale stores' today is queued when the first panel
  opens, a store's stale history and traffic on `storeViewed(domain)`.
- `StepperField` (Settings' refresh interval): a debounced save that typing
  back to the saved value disarms; Enter and blur commit, Esc reverts and
  saves nothing, and an armed save is made when the view closes.

Fixture binaries never carry the bare names `shopify`, `mise`, `node` or
`npm`, and none is a symlink (`omarchy plugin validate` allows none in the
plugin folder). Tests build a throwaway HOME and link them into the pinned
layout under the names Shop looks for.

## Pins and the CLI runtime

- `Shop::NODE_PIN = "26.13.0"`, `Shop::CLI_PIN = "5.0.1"` are the source.
  Ruby reads the constants; QML reads `snapshot.pins` (`{cli, node}`),
  which `js/snapshot.mjs` builds from its own `CLI_PIN` / `NODE_PIN`
  copies, and `Copy` fills `{cli}`/`{node}` from it. The installs dir the
  UI names is Ruby's (`Runtime.status` `installs`, read into `snapshot.cli`).
  `tests/run` and `tests/qml/fake-home.sh` read the pins from `lib/shop.rb`.
  The pins are also spelled in prose and commands in `README.md` and this
  file. No other file spells a version (tests build their expected values
  from `Snapshot.CLI_PIN` / `Shop::CLI_PIN`).
  `tests/ruby/test_contracts_helpers.rb` fails when the JS copy differs from
  the Ruby constants or any other tracked file spells a pin, and
  `test_contracts_docs.rb` when a Node/CLI version literal in the two docs
  does, so a bump is all four files at once.
- `Shop::Runtime.locate` is pure (no writes) and resolves exactly two files
  under `${MISE_DATA_DIR:-~/.local/share/mise}/installs`:
  - `node/26.13.0/bin/node`
  - the CLI's `bin/run.js`, tried in this order under
    `npm-shopify-cli/5.0.1/`: `lib/node_modules/@shopify/cli/` (npm layout),
    `node_modules/@shopify/cli/`, then
    `node_modules/.mise/@shopify+cli@5.0.1/node_modules/@shopify/cli/` (mise's
    default aube layout).
  The `package.json` beside `bin/` must be a JSON object saying
  `"version": "5.0.1"` (anything else, including a truncated or foreign
  file, is a missing CLI, never an internal error), and node, `run.js`
  and `package.json` must be regular files (after resolving links) owned
  by the user or root and writable by nobody else
  (`Runtime.trusted_file?` on `Paths.trusted_stat?`, the one owner-and-mode
  rule `ThemeFolder.ancestor_reason` also holds a theme folder's ancestors
  to: a group-writable node or `run.js` is `cli_missing`, since these files
  are executed, not just read).
- `Runtime.ensure_node_link!` is the only writer of `<state>/bin/node` (the
  link the CLI's `PATH` points at). `Runtime.status` is what
  `check-account` reports as `cli`.
- Every CLI call is `[node, run_js, *args]`. No shim (the aube
  `node_modules/.bin/shopify` is a shell script and is never used), no
  `mise exec`, no PATH lookup.
- `install-cli --consent=install` runs `/usr/bin/mise install node@26.13.0`,
  then `/usr/bin/mise exec node@26.13.0 -- /usr/bin/mise install
  npm:@shopify/cli@5.0.1`, then checks `run.js version`. It never runs
  `mise use` and never passes `-g`. It never passes `--ignore-scripts`:
  esbuild's postinstall is part of a working CLI.

### Shopify CLI 5.0.1 output contract

- Pass `--no-input` on every non-interactive call, and run it with `CI=1`;
  without them the CLI may open a browser or prompt and hang in the
  background.
- stdout is the JSON result. stderr is NDJSON progress lines; keep only a
  bounded tail for diagnostics. **stderr is never classified**: it is
  attached to `cli_failed` as `details` (≤20 cleaned lines) and nothing else.
- A failure exits 1 and prints `{"error":{"type":"abort","message":…,
  "tryMessage"?:…,"nextSteps"?:[…]}}` on stdout, or a GraphQL body with
  `errors[].extensions.code` / `extensions.app_errors`.
  `Shop::Classify.failure(result, body, theme:)` decides, in Ruby only and in this
  order (first match wins): the structured parts first (`body_code`:
  `body.errors[].extensions.code`,
  `body.extensions.app_errors.errors[].category` and an explicit
  `retryAfter`), then the CLI's own text (`message_code`:
  `body.error.message` and `body.error.tryMessage`), row by row:

  | Source text or code | code |
  | --- | --- |
  | `extensions.code == ACCESS_DENIED`, `app_errors` category `access_denied` (not on a theme command, see the text row below) | `sales_access_required` |
  | `extensions.code` in `THROTTLED`, `"429"`; a `retryAfter` present | `rate_limited` (+ `retryAfter`) |
  | "No stored app authentication found for <domain>.", "Stored app authentication for <domain> is no longer valid.", "Token refresh failed for <domain> (HTTP …).", "Token refresh returned an invalid response for <domain>.", "No refresh token stored for <domain>.", "The preview store <domain> has likely been claimed", "You are not authorized to use the CLI to develop in the provided store", "You don't have the necessary permissions to perform this action" | `sales_access_required` (never on a theme command: CLI 5.0.1 theme commands exchange the account session for their Admin token, so a grant cannot fix them; they fall through to the rows below and usually `cli_failed` with the CLI's own sentence) |
  | "An organization ID is required" | `multi_org` (internal: signed in, several organizations) |
  | "Too Many Requests" | `rate_limited` (+ `retryAfter`) |
  | "Error validating auth session", "We've cleared the current session", "Authorization is required to continue" (what 5.0.1 prints under CI when signed out), "log in to Shopify", "You are not logged in", "No authenticated account found", "Device authorization failed", "The BusinessPlatform GraphQL API responded unsuccessfully with the HTTP status 401" (the account API's 401; the Admin API's is the `theme_session_expired` row) | `signed_out` |
  | "The Admin GraphQL API responded unsuccessfully with the HTTP status 401" or "… 403" **on a theme command** (`Classify.check!(result, theme: true)`; `Shopify.spec` sets `theme` from `Shopify.theme?(args)`) | `theme_session_expired` (off a theme command this text matches no code: `cli_failed`, without the rows below) |
  | "is currently unavailable" (HTTP 402, a paused store) | `store_unavailable` |
  | "returned a server error", "HTTP status 5…" | `cli_failed` with `retryAfter: 60` |
  | anything else | `cli_failed` |

  `body.error.tryMessage` is read only when it is the CLI's own prose: for
  a `"GraphQL operation failed."` body the pinned CLI copies the raw
  GraphQL error list into `tryMessage` (and `details.errors`), so
  `Classify.own_text` drops `tryMessage` when the message is that wrapper
  or `tryMessage` is a JSON dump, and GraphQL errors classify only through
  `extensions.code` / `app_errors`. The fixtures `error-scope.json`,
  `error-graphql.json` and `error-throttled.json` carry that dump.
  Phrases match whole, in those fields only. A bare "login", "authenticat",
  "access denied", "throttl" or "rate limit" in a GraphQL message, a file
  name or stderr is not enough: every theme has
  `templates/customers/login.liquid`, and a theme can ship
  `assets/ACCESS_DENIED.js`.
- `store execute -j` wraps its result: read `data.*`; `extensions.cost` and
  `extensions.shopifyqlCost` drive paging under throttle (the helper reads
  them and never emits them). ShopifyQL rows are objects keyed by column
  name, with `columns: [{name}]`; parse by name, never by
  position. All cell values are strings. Amounts must match
  `/\A-?\d+(?:\.\d+)?\z/`, and a sum that is not finite is `bad_response`.
- `store list --json` → `{"stores":[{"store","name",…}], "notice"?}`; at most
  250 rows, so `Stores.from_store_list` returns `[rows, truncated]`, and an
  empty list with a `notice` means `unknown`, never `signed_in`. In
  `check-account` a `store list` that times out is still `ok:true` with
  the found `cli` and `account: {status: unknown, error: {code: timeout}}`
  (a found CLI stays `ready`, so sales start and report their own errors);
  `terminated` still fails the helper.
  `store auth list --json` → `{"sessions":[{"store","scopes":[…]}]}`; a
  session is sales access when it holds `SCOPES` once write scopes are
  expanded (`Stores.implied_scopes`: `write_X` implies `read_X`, as the
  CLI's own scope check does; its grant merge stores `write_orders`
  without `read_orders`).
  `organization list --json` → `{"organizations":[{"id", "shopCount", …}]}`
  (skip `shopCount: 0`). `theme list --json` → `{"themes":[{"id", "name",
  "role", "processing"}]}`.

## Helper contract

- Invocation: `[<plugin root>/helpers/<name>, ...args]`. Long flags only,
  `--flag=value` or `--flag value`. Unknown flags, stray positionals, a
  missing value, or an argument that is not valid UTF-8 fail `invalid_argument`. `--help`
  prints usage and exits 0.
- Helper flags, exactly each helper's `values:`/`switches:` (anything else
  fails `invalid_argument`, and so does a `required:` flag left out;
  `test_contracts_docs.rb` checks this list against them):
  `push-theme --store=<domain> --folder=<path> --target=live|<id> [--allow-live] [--confirm-live]`;
  `pull-theme --store=<domain> --folder=<path> --target=live|<id>`;
  `restore-backup --store=<domain> --backup=<id> [--allow-live] [--confirm-live]`;
  `fetch-sales --store=<domain> --range=today|yesterday|history [--timezone=<Area/City>] [--with-traffic]`;
  `preview-theme --store=<domain> --folder=<path>`;
  `list-themes`, `list-backups`, `grant-sales-access --store=<domain>`;
  `inspect-folder --folder=<path>`;
  `install-cli --consent=install`;
  `notify-order --title=<text> --body=<text> [--sound]`;
  `check-account`, `discover-stores`, `prepare-state`, `read-clipboard`, `sign-in`, `sign-out`: none.
- **stdout is exactly one JSON line**: `{"ok":true,…}` or
  `{"ok":false,"error":{"code","message"}}` (message ≤200 chars, cleaned).
  A message is a lowercase fragment with no trailing period that names no
  flag or environment variable (the panel puts it after its own sentence);
  a value it echoes goes through `Text.quote` (quoted, cleaned, at most
  `Text::ECHO_MAX` chars) and an OS error through `Text.os_error` (the
  reason only: "no such file or directory", without Ruby's
  ` @ rb_sysopen - <path>`).
  Streamers (`discover-stores`, `preview-theme`) print JSON lines and always
  end with `{"event":"done",…}` or `{"event":"exited",…}`.
  `HelperMain.emit` scrubs any string that is not valid UTF-8 (a realpath,
  a refused entry's name) to `?`, so such a name never turns a result into
  an internal error; values the helper works with (a folder handed to the
  CLI as `--path`) stay raw.
- stderr is diagnostics only. QML never parses it, and there are no stderr
  regexes in QML or JS.
- First line, exactly:
  `#!/usr/bin/env -S -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_PATH -u BUNDLE_BIN_PATH -u GEM_HOME -u GEM_PATH /usr/bin/ruby --disable-gems`.
- Shape: `module Shop::Helpers::<Name>` with `NAME`, `USAGE`,
  `module_function` and `def run(argv, **overrides)`, plus
  `Shop::Helpers::<Name>.run(ARGV) if $PROGRAM_NAME == __FILE__` as the
  last line (`test_contracts_helpers.rb` asserts this spelling). The body
  is `HelperMain.main(argv, overrides, helper: NAME, usage: USAGE, values:
  %w[…], switches: %w[…], required: %w[…], last_event:, prepare:) {
  |options, overall| … }`, which first calls
  `HelperMain.scrub_interpreter_env!`, then applies the test overrides,
  `File.umask(0o077)` and `Shop::Signals.install!` before anything spawns,
  starts the overall deadline (`overall`, a `Deadline` of the row's H;
  `HelperMain.overall_cap(seconds)` caps any step by what is left of it,
  and every folder walk is capped by it too), parses argv (`Argv.parse`),
  and writes the one JSON line. `helper:` names the `Shop::TIMING` row
  whose H and output cap apply; `fetch-sales` passes a lambda that picks
  its row from the parsed `--range`, so its usage errors fail under
  `HelperMain::DEFAULT_STDOUT_CAP`. `last_event:` (`'done'` or `'exited'`)
  makes a streamer's failure line its last event. Every per-call deadline
  is `overall.cap(Shop.seconds(:call, NAME, step))`. Every supervisor tick checks `Process.ppid` (parent lost →
  kill children, emit `terminated`, exit 143).
- Child CLI arguments use the single-argument form (`--store=D`,
  `--theme=ID`, `--path=P`, `--organization-id=O`). GraphQL data goes only in
  `--variables=<json>`; query text is a frozen constant in `Shop::Queries`
  (the seven: `SHOP_NAME`, `SHOP_META`, `TODAY`, `TODAY_WITH_TRAFFIC`,
  `YESTERDAY`, `ORDERS_PAGE` for every later page of either day, and
  `HISTORY`; the orders filter is always `$filter`), and every `store
  execute` passes `--version=2026-10`.
- Never anywhere: `--allow-mutations`, `--publish`, `--theme-editor-sync`,
  `--notify`, `--open`, `--password`, `-e`/`--environment`.
- Push, pull and restore always pass `--nodelete`. Pull (the user's pull
  and the backup pull) also passes `--force`: under `--no-input` the pinned
  CLI's pull throws ("This command must run from a theme directory when
  user input is unavailable") instead of prompting whenever the target is
  not theme-shaped or is a git working tree with uncommitted or untracked
  changes, which is the normal state of a developer's checkout. Shop's own
  gate runs first and is stronger (`ThemeFolder.check!(mode: :pull)`: theme
  shaped or empty, plus `FolderCopies.create!`), so the CLI's prompt is
  redundant. Pull argv: `theme pull --store=D --theme=ID --path=P --nodelete
  --force --json --no-input`. `--allow-live` is passed only when the target
  is live and the helper got both `--allow-live` and `--confirm-live`.
- `fetch-sales` output: `--range=today` → `today` (`orders` count, `sales`,
  `latestOrder`, the store day's `startEpoch` in seconds (its end is the
  envelope's `dayEndsAt`), `orderPoints: [[ms, amount]]` per order for the
  hourly chart, plus `traffic` and hourly `trafficHourly` with
  `--with-traffic`; every order
  page asks `createdAt`), `--range=yesterday` → `yesterday` (`orderPoints:
  [[ms, amount]]` only for today's same-time-of-day baseline; `salesHourly:
  [{hour, sales}]`, ShopifyQL `total_sales` per hour (can be
  negative), for the Yesterday chart, or `null` when unavailable; and
  `trafficHourly`), `--range=history` → `history {yesterday, last7d,
  last14d, last30d, last12m, lifetime}` from ShopifyQL, every figure ending
  yesterday (last12m: the 365 days to yesterday, a month `partial` when
  the window starts or ends inside it, by date and month key, so none on
  the 1st; lifetime: up to yesterday).
  One measure per screen: Today's headline, chart and "at this time
  yesterday" baseline are order `totalPriceSet` sums (live; both order
  filters end in `AND test:false`, so test orders never count there or in
  new-order alerts; cancellations still do, gross as placed); Yesterday's
  headline, orders, chart and "the day before", and every completed
  period, are ShopifyQL `total_sales` (Shopify's net "Total sales": gross −
  discounts + returns + taxes + shipping, returns booked on the day of the
  return, test orders excluded). The Yesterday chart never falls back to
  order totals.
  Under `rate_limited` or `timeout` mid-paging the helper returns what it
  has with `truncated: true`, and between pages it sleeps from the cost
  budget (≤5 s, cancellable). A truncated Today keeps its exact `orders`
  count but a partial `sales` sum, so `js/metrics.mjs` makes no money
  comparison for it: `periodView` gives no
  `salesTrend` and a `compare` without `sales`, `kpi` gives no AOV or sales
  per session, and `periodTotals` shows no trend.
- `push-theme`, `pull-theme` and `restore-backup` report file problems as
  `warnings: [{kind: "issue"|"symlink"|"hardlink", path, message?}]`: the
  CLI's rejected files (`issue`, with its message) plus a link a pull left
  behind. A push's result is `{ok, theme, folder, backupId, warnings,
  partial, writeStarted}`, a restore's `{ok, theme, backupId, warnings,
  partial, writeStarted}`, a pull's `{ok, theme, folder, folderCopy,
  warnings, writeStarted}`.
  Every line the three print (success, failure, usage error, a stop, an
  internal error) carries top-level `"writeStarted"`: false while what the
  job writes is provably untouched (a refusal, the theme list, the backup
  or folder copy, the recheck), true from the moment the call that writes
  starts (the CLI push of a push or restore, the CLI pull of a pull).
  These are the helper's line fields: `HelperMain.main(..., line_fields:
  {...})` declares them with their starting values (push and restore
  `{'writeStarted' => false, 'backupId' => nil}`, pull `{'writeStarted' =>
  false, 'folderCopy' => nil}`) and `HelperMain.set_line_fields!` changes
  them: `backupId` right after the backup is taken, `folderCopy` right
  after the folder copy is made, `writeStarted` true right before the
  call that writes. `Shop::ThemeJob` owns all three (`backed_up!`,
  `folder_copied!`, `writing!`; nothing else outside `HelperMain` calls
  `set_line_fields!`) and the order of a theme job: `ThemeJob.run(domain,
  helper:, keep:)` locates the runtime and holds `Lock.with(domain)` from
  the theme list (`job.target!`) to retention (`Backups.prune!`);
  `job.push_with_backup!` (push, restore) runs the live gate, the backup,
  the caller's recheck of the source, then the push, and
  `job.pull_with_copy!` (pull) the folder copy, the recheck, then the pull. Every line
  the helper prints from then on carries them (a failure, a TERM, an
  internal error, the `output_too_large` line; a success's own value
  wins), so a push that fails after its backup says the backup was kept
  and a failed pull names its folder copy (or null). A line the helper
  never printed (killed by a signal, its QML deadline, a crash:
  `HelperProcess` synthesizes `terminated`, `timeout` or `bad_response`)
  has no `writeStarted`: `ThemeJob.writeStartedOf` keeps that as null
  (unknown; `failed_to_start` is false), and the result keeps the one
  value `writeStarted` (true, false or null). Only false says "Stopped
  before anything was pushed / restored / changed"
  (`result.stopped.none.<action>`) or gives a bare "Push failed: …"
  (`result.failed.none`); true or null hedges with what may have changed
  (`result.stopped.maybe`, `result.failed.maybe` with
  `result.mayHaveChanged.theme|folder|emptyFolder`), and the card adds
  "Backup kept · …" or "Folder copy kept · …" when the line named one
  (`ThemeJob.resultText`, `resultTone`, `keptText`).
  The backup pull itself must be complete. The pinned CLI's pull result
  is `{status: "success", changed, directory, theme}` (or `skipped`); it
  has no `partial` status and no `issues`. A file that fails to download
  throws mid-pull: the CLI prints its error JSON and exits non-zero with
  the files written so far left behind, which Classify maps like any CLI
  error (`cli_failed` for a user pull) and `Backups.take!` turns into
  `backup_failed`, removes the half-written directory, and the push or
  restore stops before touching the remote theme; a pull status other
  than `success` fails the backup the same way. An incomplete pull never becomes a listed backup: it is pulled into
  `.partial-<epoch>-<pid>`, and only after a `success` pull is its
  `meta.json` written and the dir renamed to `<epoch>-<themeId>`.
- `inspect-folder`'s `themeShaped` needs `config/`, `layout/` and
  `templates/` as directories: the pinned CLI's `theme push` and `theme
  dev` refuse a folder missing any of them under `--no-input`, and
  `push-theme`/`pull-theme`/`preview-theme` refuse such a folder (`not_a_theme_folder`)
  before the backup or the lock.
- `list-backups` rows carry the backup `meta`: `before` (`push|restore`),
  `files`, `bytes`, and the theme `{id, name, role}` at the time.
- `preview-theme` holds the store's lock (`Lock.with(domain)`) for its whole
  lifetime, so a `push-theme`, `pull-theme` or `restore-backup` started meanwhile fails
  `store_busy`, and the service refuses push, pull and restore for that
  store while a preview runs.
- `notify-order`: in both the title and the body every `://` becomes
  `:⁄⁄` (U+2044 fraction slashes, before the 300-char cap): Omarchy's daemon
  offers the first http(s) URL of either field as the card's click target
  and linkifies bare URLs in the body, so a product title or shop name
  carrying `https://…` would turn the normal click on a Shop toast into a
  phishing link. The app name goes as is; in the body `< > &` are **neutralised** to the look-alikes
  `‹ › ＆`, never entity-escaped: Omarchy's notification daemon decodes
  entities up to three times before it restores `b/i/u/s/em/strong` and
  `<a href>`, so an escaped `&lt;a href=…&gt;` in a product title would come
  back as a live link, while mako/dunst treat the body as Pango (no bare
  `&` or `<` may reach them). `Text.notification(value, neutralise:)`
  (at most `NOTIFICATION_MAX` = 300 chars) does both;
  `Text.clean` strips control and format characters except `\n` and the
  zero-width joiner (emoji sequences survive).
- **`Shop::Command`** supervises every child (each a `Shop::Child` state
  machine; `Shop::ProcessGroup` signals the group and reads `/proc`): argv prefix
  `/usr/bin/setpriv --pdeathsig KILL --`, its own process group,
  `unsetenv_others`, `close_others`, stdin `/dev/null`, cwd `Paths.run_dir` (private, empty, 0700). On deadline or
  cancel: TERM `-pgid`, 3 s grace, KILL `-pgid`, reap, wait for the group to
  be gone, then unregister. stdout is byte-capped; stderr is a capped tail.
  One single-threaded `IO.select` loop; **no `Thread` or `Mutex`** in `lib/`
  or `helpers/`. After the child's pipes hit EOF the supervisor finishes the
  job on the same tick, and "the group is gone" is
  one `kill(0, -pgid)` (ESRCH means empty, zombies included); the `/proc`
  scan runs only when that call says something is still in the group. So a
  trivial child returns in well under 50 ms whatever the machine's load.
- **`Shop::Env`** builds allowlisted environments (`for_cli(interactive:)`,
  `for_tool(:mise | :notify | :clipboard | :sound)`, any other profile an
  `ArgumentError`); nothing is inherited by default.
  `for_cli` sets `PATH=<state>/bin:/usr/bin:/bin` (that dir holds only a
  `node` link), `NO_COLOR=1`, `FORCE_COLOR=0`, `SHOPIFY_CLI_NO_ANALYTICS=1`,
  `npm_config_dry_run=true`, `npm_config_update_notifier=false`, and `CI=1`
  unless interactive.
- **`Shop::Tools`**: every spawn uses an absolute argv0 (`/usr/bin/setpriv`,
  `/usr/bin/mise`, `/usr/bin/notify-send`, `/usr/bin/pw-play`,
  `/usr/bin/paplay`, `/usr/bin/wl-paste`, or the resolved pinned node).
  `Command.run` is called in exactly two places: `Shopify.run`/`call_all`
  (the pinned node from `Shopify.spec`) and `Tools.run(name, args, …)`
  (`Tools.path(name)` under the tool's `Tools::PROFILES` environment;
  `Tools.available?(name)` checks it is installed). A spawn that fails is
  `cli_failed` for a CLI call and `tool_failed` for a tool. Every CLI call's
  stdout cap is `Shopify::JSON_CAP` (2 MiB) or, with `json: false`,
  `Shopify::TEXT_CAP` (64 KiB).
- **`Shop::ThemeFolder`** owns the folder rules (`report`, of which
  `inspect-folder` prints a subset, and `check!`); **`Shop::TreeWalk`** is the
  single tree walker (`walk(root, entries = nil)`: the top-level names to
  visit, default all), called by `ThemeFolder.report` (the theme dirs and
  root files of a folder), `TreeWalk.stats` (backup and copy sizes) and
  `Backups.tree_reason` (whole backup trees; `Backups.find!` goes through
  it); **`Shop::ThemeToml`** finds a `shopify.theme.toml` in a folder or
  any ancestor (`ThemeToml.refuse!` runs before every theme command, from
  `Shopify.spec`). Every walk, whichever
  helper runs it, has inspect-folder's walk cap (10 s, `Shop.seconds(:walk,
  'inspect-folder')`). Per entry: a symlink →
  `symlink`; a directory → descend (owner and mode checked); a regular file
  with `nlink > 1` → `hardlink`; anything else (FIFO, socket, device) →
  `special_file`; a failing `lstat` (`EACCES`, `ENOENT`, `ENAMETOOLONG`,
  `ELOOP`, any `SystemCallError`) → `unreadable`. The top-level `AGENTS.md`
  and `DESIGN.md` must be regular files too. `FolderCopies.create!` and
  `Backups.take!` build their copy in `Backups.stage!(dir, suffix:) {
  |partial| … }`, which removes the partial on any exception and renames
  it to its id only when the block returns; both rescue `StandardError`
  and raise `backup_failed`. `create!` lets any `Shop::Failure` through
  (`folder_too_large`, `terminated`); `take!` only the codes in
  `Backups::PASS_THROUGH` (`terminated unsafe_folder signed_out
  theme_session_expired rate_limited timeout output_too_large
  store_unavailable`; the backup pull is a theme command, so it never
  fails `sales_access_required`).

### Error and exit codes

A helper exits 0 on success, 124 on `timeout`, 143 when `terminated` and 1
for every other code.

| code | meaning |
| --- | --- |
| `cli_failed` | CLI failed, unclassified; CLI-reported failures carry `details` (≤20 cleaned lines); a 5xx adds `retryAfter: 60`; a push the CLI rejected with per-file `issues` has the first one as its message (`path: message`, plus ` (+N more)`), the CLI's sentence and every issue staying in `details`; a stderr-only failure's message is the last stderr line. The panel prefixes "The Shopify CLI failed:", so no message starts with "Shopify CLI" |
| `tool_failed` | a system tool (`mise`, `wl-paste`, `notify-send`, `pw-play`, `paplay`, or `setpriv` in front of one) could not be started, or `mise install` failed; never the Shopify CLI |
| `internal_error` | a helper bug: an exception that is not a `Shop::Failure` (`unexpected <Class>: <message>`); the service also returns it for a config transform that throws |
| `backup_failed` | pre-operation backup failed (a CLI error, including a download that failed mid-pull); nothing was changed |
| `theme_not_found` | target or backup source theme is gone |
| `backup_not_found` | not a completed backup |
| `store_unavailable` | the store is paused or otherwise unavailable (HTTP 402) |
| `invalid_argument` | validation or usage, including argv that is not valid UTF-8 |
| `not_a_theme_folder` | folder fails the shape checks |
| `unsafe_folder` | folder rules; `error.reason` is one of `theme_toml`, `symlink`, `hardlink`, `special_file`, `unreadable`, `too_many_files`, `root`, `home`, `plugin`, `state`, `config`, `not_owned`, `world_writable`, `group_writable`, `unsafe_parent`, `not_absolute`, `not_directory` |
| `folder_too_large` | pre-pull copy would exceed 200 MiB |
| `live_not_allowed` | live target without `--allow-live` |
| `live_not_confirmed` | live target without `--confirm-live` |
| `consent_required` | `install-cli` without `--consent=install` |
| `clipboard_too_large` | `read-clipboard`: wl-paste sent more than 16 KiB; it was stopped |
| `clipboard_unavailable` | `read-clipboard`: no `/usr/bin/wl-paste` |
| `bad_response` | unparseable or unexpected CLI output (including valid JSON of the wrong shape: CLI-derived JSON is walked only with `Json.dig`, never `Hash#dig`, and a classifier ignores a non-object part instead of failing), a malformed amount, a non-finite sum |
| `output_too_large` | a child exceeded its stdout cap |
| `mise_missing` | `/usr/bin/mise` absent |
| `unsafe_state_dir` | a state/config dir is a link or not the user's |
| `store_busy` | the per-store lock is held (a theme job, restore or preview) |
| `rate_limited` | throttled / 429; always `retryAfter` (whole seconds, 1-3600) |
| `sales_access_required` | the store needs `grant-sales-access` (no stored app auth, expired token, missing scope or access denied — one code, one remedy) |
| `theme_session_expired` | theme 401/403 |
| `signed_out` | no account session |
| `timeout` | helper deadline; group killed and reaped |
| `cli_missing` | pinned node or CLI not found; `error.missing` is `node` or `cli` |
| `terminated` | TERM/INT/HUP or parent lost; group reaped. QML also reports it for a helper killed by any signal before it printed a result |

Every code except `consent_required` (Shop always passes `--consent=install`, so the panel never sees it; it would show as `error.default`) has text in `js/copy.mjs` (`error.<code>`). The service also
refuses without running a helper. Every refusal and blocking rule is one
pure function in `js/preflight.mjs` over a plain facts object:
`model/Preflight.qml` gathers the facts from the models for the service,
and the panel calls the same functions over the snapshot
(`Preflight.factsOf(snapshot, store, backupId)`): `ConfirmFlow` before any
dialog and Backups before a restore (`beforeDialog(facts, action)`: what
the service would refuse on accept, the live opt-in aside, which the
dialog asks for as its first stage), the theme card and the p/u/d keys
(`beforeDialog` for push and pull, `checkPreview`; the lock icon is
`liveLocked`), Settings (`requireCli`), all rendered with `Copy.errorOf`.
The service runs `checkPush`, `checkPull`, `checkPreview` and
`checkRestore` (each the shared `checkThemeAction` plus its own rules).
The facts include the store's theme facts (`themeFacts`: `folderState`
from `Themes.folderState`, `targetLive`, and for a restore `backupLive`
from `Themes.restoreIsLive`), so the folder rules the helpers apply
(`ThemeFolder.check!`: a missing, unsafe or not theme-shaped folder is
refused, an empty one is a pull target only) refuse before a spawn as
`folder_unusable` with `action` and `state`.
Which stores show no figures is `Snapshot.accountBlock(snapshot)` (`state`,
`config`, `cli`, `installing`, `signedOut`, `signingIn` or "", from the raw
fields) and `Snapshot.figuresBlocked(snapshot, store)` (signed out or signing in
blocks only the stores whose sales access is not granted), read by Home's
rows, the store view and the bar; the banner is display only, so a banner
shown above the state (a write error, an expired session) never changes
what is blocked. The results come from the builders in
`js/errors.mjs` (one function per code, so `Service.qml`, the models and
`js/config.mjs` never spell a code twice): `cli_checking` (the account
check has not finished), `cli_installing`, `cli_missing`, `account_busy`
(sign-in, sign-out or install running; also theme push/pull, restore and
preview while a sign-in or sign-out runs, `requireAccountIdle`:
CLI 5.0.1 theme commands take their Admin token from the CLI's account
session store (kit `sessionStore`), which `auth logout` deletes and `auth
login` replaces; a `store auth` session would serve them only with
`read_themes` (pull) or `read_themes`+`write_themes` (push/dev), and Shop
grants only `read_reports,read_orders`, so its store sessions are used by
`store execute` alone. Signed out after a BusinessPlatform 401 is no
refusal: the stored Admin tokens still work, and when they expire the
command fails `theme_session_expired`. After Sign out a theme command
finds no session and fails), `store_busy` (a job, preview or
access flow on this store; push, pull, restore, preview, theme
folder/target changes and `removeStore`; also `signIn`/`signOut` while a
job or preview runs on any store, `requireThemesIdle` (`Errors.anyStoreBusy`), the mirror
of `requireAccountIdle`, marked `anyStore: true` with `what` `job` or
`preview`; `resetConfig` the same, and also during a grant
(`what` `access`, `requireResetIdle`), since the empty config forgets every
store and stops its helpers; Reset of a `config.json` that reads again is a
no-op `{ok, skipped}` and its open dialog closes. A per-store `store_busy`
from `requireStoreIdle` names the work holding the store in `action`
(`push|pull|restore|preview|grant`) and, when a starting or ready preview
is in the way of a push, pull or restore, that action in `blocked`, so
`Copy.errorOf` says "Wait for the pull to finish" or "Stop the preview
before you push"), `confirm_open` (a dialog or pending confirm
exists), `recently_declined` (an IPC `request*` within 30 s of a decline),
`config_busy` (a write in flight), `config_unavailable` (config not loaded
yet), `config_write_failed`, `too_many_stores` (50, the cap in `js/config.mjs`),
`rate_limited_locally` (a refresh within 2 s of the last), `no_theme_folder`,
`folder_unusable` (the last inspection of the linked folder says the
action can't use it), `sales_access_required` (Home's automatic history
fetch for a store that waits for a new grant),
`unknown_store`, `invalid_domain`, `duplicate_store`, `invalid_patch`
(a change `js/config.mjs` refuses, returned as `{error}`; a transform that
throws is a bug, logged and returned as `internal_error`),
`no_pending`, `failed_to_start`, and `live_not_allowed` and
`invalid_argument` (a malformed backup id) when the service can tell before
spawning. `config_invalid` and `config_unsupported` are set by
`js/config.mjs` and `ConfigStore` when the file is read, and every store
action returns them (`Errors.configInvalid`) while `config.json` is
unreadable, instead of `unknown_store`.

### Timing

Invariants: QML deadline = helper deadline H + 5 s. QML kill grace (5 s) >
helper KILL grace (3 s) + group-gone wait (≤1 s), so a helper always reaps its
group before QML would SIGKILL it; if QML does, `--pdeathsig` kills the CLI.
`Shop::TIMING` in `lib/shop.rb` is the single source of this table
(`Shop.seconds(:helper, name)` reads it); `test_contracts_docs.rb` parses
the table below and fails when the two differ. QML's copy is the `HELPERS`
table in `js/timing.mjs` (per helper, fetch-sales per range: `deadlineMs`
= H + 5 s, 0 for the preview stream, and `cap`, a streamer's line cap):
`HelperProcess` and `HelperStream` default `deadline` and
`maxStdoutBytes`/`maxLineBytes` from their `helper` (and `range`), so no
model spells a deadline or a cap. `test_contracts_qml.rb` parses that
table and fails when a row differs from `Shop::TIMING`, or when any QML
file outside those two passes a deadline or cap literal.

| helper | H | per call | stdout cap | QML deadline |
| --- | --- | --- | --- | --- |
| prepare-state | 5 s | – | 4 KiB | 10 s |
| check-account | 20 s | 20 s | 64 KiB | 25 s |
| sign-in | 900 s | probe 20 s, logout 30 s, login 900 s | 64 KiB | 905 s |
| sign-out | 30 s | 30 s | 4 KiB | 35 s |
| install-cli | 900 s | node 400 s, cli 400 s, verify 20 s | 4 KiB | 905 s |
| grant-sales-access | 600 s | auth 600 s, verify 20 s | 4 KiB | 605 s |
| discover-stores | 45 s | 15 s, concurrency 6 | 2 MiB | 50 s |
| fetch-sales today | 25 s | 20 s, ≤40 pages | 1 MiB | 30 s |
| fetch-sales history | 45 s | 40 s | 1 MiB | 50 s |
| fetch-sales yesterday | 45 s | 20 s, ≤40 pages | 2 MiB | 50 s |
| list-themes | 20 s | 20 s | 256 KiB | 25 s |
| inspect-folder | 15 s | walk 10 s | 16 KiB | 20 s |
| list-backups | 5 s | – | 256 KiB | 10 s |
| push-theme | 600 s | list 20 s, backup 240 s, push 300 s | 32 KiB | 605 s |
| pull-theme | 600 s | list 20 s, pull 300 s | 32 KiB | 605 s |
| restore-backup | 600 s | list 20 s, backup 240 s, push 300 s | 32 KiB | 605 s |
| notify-order | 10 s | 5 s | 1 KiB | 15 s |
| read-clipboard | 4 s | 2 s | 32 KiB | 9 s |
| preview-theme | ready ≤120 s, lifetime ≤8 h | – | lines ≤4 KiB | none; stop = close stdin + SIGTERM, SIGKILL after 8 s |

### Supervisor limits

`Shop::Command` kills by process group, and `--pdeathsig KILL` covers the
direct child when its helper dies. Neither reaches a grandchild that calls
`setsid()` into a new session and keeps the helper's pipes open: TERM and
KILL to the old group miss it, and the helper's drain cap (3 s after the
child exits) is what returns control, with the pipes still held by the
escapee. The Shopify CLI does not do this, and Shop runs no other
third-party program, so the limit is documented instead of papered over
(`systemd-run --scope` would add a dependency). The user-facing effect, if
it ever happened: a helper reports `timeout` or `terminated` while a stray
process lingers until it exits on its own.

## Consent model

- IPC carries only reads, refreshes, non-destructive actions, cancels and
  `request*` methods. The `IpcHandler` names exactly the methods in
  README › IPC reference, nothing else.
- Everything that changes config or a theme is QML-only (the panel calls the
  service object): `pushTheme`, `pullTheme`, `restoreBackup`, `installCli`,
  `signOut`, `addStore`, `removeStore`, `updateStore`, `moveStore`,
  `updateSettings`, `resolvePending`. `test_contracts_qml.rb`
  fails if the `IpcHandler` block names any of them or `allowLive`.
- `model/Consent.qml` owns requests (only the IPC `request*` methods make
  them): `request(spec)` publishes `snapshot.pendingConfirm` (expires after
  120 s); the focused monitor's widget opens the matching `Dialog`. A
  request is refused with `confirm_open` while a confirmation is pending or
  any panel has a dialog open (an open dialog is never replaced), and every
  request is refused with `recently_declined` for 30 s after a decline.
  The dialog (`ui/Dialog.qml`) guards against a
  confirmation the user did not mean: for 400 ms after it shows (and again
  after the panel reopens with it up) clicks, hover and keys are ignored and
  the buttons render unarmed; the keys are Left/Right/Tab/Shift+Tab to
  move, Enter to activate and Esc to cancel, never text keys or Space; a key
  counts only after some key was released since the dialog appeared and
  never as an auto-repeat, so a key burst or a held key that began before
  the dialog appeared cannot move the selection and activate it; and a
  dialog opened by an `ipc`-origin request (which opened the panel and took
  the keyboard unasked; `spec.origin === "ipc"`) accepts from the keyboard
  only with Ctrl+Enter, which its caption says (Ctrl+Enter confirms
  even while Cancel is selected). `tests/qml/dialog_smoke.qml`
  feeds a typed `ls⏎` and Tab/Space/Enter bursts and checks the dialog is
  still open.
- `requestAddStore domain [label]` is the only IPC path into config: it opens
  "Add {domain} to Shop?"; the add happens on accept, and `Config.addStore`
  refuses the 51st store with `too_many_stores` (the 50-store cap lives only in
  `js/config.mjs`; the helpers never read config.json, so Ruby has no copy).
  The label is validated before the request (`Config.cleanLabel`: 1–80
  characters, no control characters, else `invalid_patch`), so the dialog
  only renders a clean label.
  `grantSalesAccess domain` over IPC runs the grant (the browser's own
  consent flow) but never relabels: only a panel grant gives a store still
  named after its subdomain the shop name the grant verified.
- A live push or restore needs the store's `theme.allowLive` (helper flag
  `--allow-live`) and a QML call carrying `{confirmLive: true}` from the
  dialog (`--confirm-live`). The flags are sent separately, so a target that
  went live since the themes list was cached fails `live_not_confirmed` and
  the store view asks for the live confirmation. `allowLive` resets whenever
  `target` or `folder` changes. While `allowLive` is off, `p` on a live
  target opens a first dialog ("Allow changes to the live theme?"); accepting
  it calls `updateStore(domain, {theme: {allowLive: true}})` and immediately
  opens the normal live push dialog. A live restore goes through the same
  two stages, through the same question (the opt-in covers pushes and
  restores alike); before a restore it names the backup's theme
  (`forAction: restore`), which need not be the target.

## Schemas

### Config (`~/.config/shop/config.json`)

The example file and the per-field rules (ranges, defaults, what each key
means) are in README › Config reference; `js/config.mjs` implements them.
The contract on top of that:

- `version` other than `2` sets `configError` `config_unsupported`; invalid
  JSON sets `config_invalid`; either refuses every mutation until fixed or
  reset (README › Config reference has what the user sees). There is no
  migration.
- A missing file is an empty v2 config. Unknown top-level keys are kept;
  invalid store entries are reported as `invalidStores`.
- No write before `prepare-state` succeeds; `atomicWrites: true`; output is
  `JSON.stringify(cfg, null, 2) + "\n"`.
- `applyStorePatch`: `label`/`showInBar` replace; `{"theme": {…}}` merges
  (null becomes `{folder:"", target:"live", allowLive:false}` first);
  `{"theme": null}` unlinks; a leading `~/` expands.

### Service snapshot (in memory)

`Service.snapshot` is republished at most every 250 ms, and a store whose
inputs did not change keeps its object identity between builds (so pills
and rows bound to `snapshot.stores[domain]` do not re-evaluate for other
stores' ticks). The widget binds `service.storeOrder` (never
`snapshot.storeOrder`). Top-level keys: `pins, configError,
configWriteError, stateError, invalidStores, cli, account, alertTools,
pendingConfirm, themesBusy, granting, discovery, settings, stores`.

- `pins`: `{cli: "5.0.1", node: "26.13.0"}`.
- `cli`: `{status, missing, installs, error}` (`installs`: mise's
  installs dir as `check-account` resolved it, home-relative).
- `themesBusy`: `job|preview|""` (a theme job, else a preview, on any store
  Shop runs work for) and `granting` (a sales-access grant on any store):
  read by `Preflight.factsOf` (ConfirmFlow's Sign out and Reset checks), because `stores` is empty
  while `config.json` is unreadable and work keeps running then.
- Each store carries `domain, label, showInBar, theme {folder, target,
  allowLive}, currency, salesAccess, salesAccessError, sales, themeState`.
- `sales`: `{status, pending, paused, retryAt, error, fetchedAt,
  today, todayHourly, yesterdayHourly, history {last7d, last14d, last30d,
  last12m, lifetime}, newOrderAt}`. `today` is `{sales, orders,
  truncated, latestOrder, traffic, trafficHourly, baseline}`;
  `todayHourly` and `yesterdayHourly` are the hourly chart buckets
  `[{hour, sales, sessions, partial?}]` (`Hourly.
  hourlyBuckets` from today's orders, today's current hour `partial`;
  `Hourly.salesHourlyBuckets` from yesterday's `salesHourly`, `[]` without
  it). The cached `yesterday` record keeps `salesHourly` (cache version 5). `Metrics.
  awaitingFigures(sales)` is the one rule for "…" (a fetch pending or not
  yet run, or throttled with a retry scheduled) that Home's hero and rows,
  the store hero and the KPI tiles share; `paused` (nothing will be fetched,
  e.g. the CLI is missing) and every other error read "—", and Home never
  prints an order count while no store has a figure.
- `themeState`: `{themes, folder, backups, job, lastResult, preview}`, merged
  from `ThemeInfo` (`themes`, `folder {status, requested, exists, themeShaped,
  empty, safe, reason, rootFiles, error}`, `backups {status, items: [{id, at, theme {id, name, role},
  before, files, bytes}], folderCopies: [{id, at, path, files?, bytes}], error}`), `ThemeJobs` (`job`, `lastResult`:
  `ThemeJob.resultOf`'s `{ok, action, theme, folder, backupId, folderCopy,
  restoredBackupId, partial, warnings, writeStarted, at, error, details}`;
  `backupId` / `folderCopy` name the copy a job took, `writeStarted` is
  true, false or null for unknown) and `Previews` (`preview`).
  `Snapshot.targetTheme(store)` → `{id, name, live}`, and the
  `js/themes.mjs` selectors over a themeState (`themeById`, `backupById`,
  `targetOf`, `restoreIsLive`, `folderState`, `inspectionOf`, `rootFiles`,
  `parseBackupId`; the module also holds the theme-state shapes and the
  reducers `ThemeInfo` runs on each helper result, validating each row)
  are what views and preflight read.
- All `at` fields are ms.

Enumerations:

- `cli.status`: `unknown|checking|ready|missing|installing|install_failed`
- `account.status`: `unknown|signed_in|signed_out|signing_in|signing_out`
- `discovery.status`: `idle|running|done|failed`; `discovery.stores` rows
  are exactly `{domain, name}` (whether a row is already in Shop is read
  from `stores`, not from a flag on the row)
- `salesAccess`: `unknown|granted|required|granting`
- `sales.status`: `idle|loading|ok|error`
- `preview.status`: `stopped|starting|ready|stopping|failed`
- `pendingConfirm`: `{id, action: push|pull|restore|installCli|addStore,
  domain, backupId, label, live}` or null;
  `live` is a boolean, true only when the dialog asks consent to change the
  live theme

### Cache (`~/.local/state/shop/cache.json`)

`{"version": 5, "stores": {"<domain>": {…}}}`, written by `CacheStore`
(owned by `SalesData`) from `Sales.cacheRecord(store)`. Per store: `currency`, `timezone`,
`utcOffsetMinutes`, `dayEndsAt`, `history` with `historyFetchedAt` and
`historyLocalDate` (so the first snapshot after a restart shows the
completed periods and `Schedule.historyDue` knows whether the day rolled
over), `yesterday` (`{date, startEpoch, endEpoch, orderPoints [[ms, amount]],
truncated, salesHourly, trafficHourly, fetchedAt}`: the order points feed
today's same-time baseline, salesHourly redraws the Yesterday chart after
a restart), and `lastSeen` (`{at,
orderCount, latestOrderId, localDate}`, for new-order alerts after a
restart). `Sales.fromCache` skips any field with the wrong shape and warms
only the data (`withHistory`, the yesterday day through
`normalizeYesterday`): access stays `unknown` and the local date empty
until a live fetch. A file
whose `version` is not `5` (`Sales.CACHE_VERSION`) is ignored and overwritten; nothing in it is
user-edited. Version 5 renamed the yesterday record's `orders` to
`orderPoints` (the name fetch-sales uses for both days); a version 4 file
is dropped and refetched.

### Files on disk (0700 dirs, 0600 files)

| path | writer |
| --- | --- |
| `~/.config/shop/config.json` | ConfigStore |
| `~/.local/state/shop/cache.json` | CacheStore (≤1 write / 2 s; live ticks write only when today's order count changes) |
| `~/.local/state/shop/backups/<domain>/<epoch>-<themeId>/{files/,meta.json}` | push-theme, restore-backup (10 kept) |
| `~/.local/state/shop/backups/<domain>/local/<epoch>/` | pull-theme (5 kept) |
| `~/.local/state/shop/locks/<domain>.lock` | helpers (flock); preview-theme holds it while it runs |
| `~/.local/state/shop/run/` | helpers (empty CLI cwd) |
| `~/.local/state/shop/bin/node` | `Runtime.ensure_node_link!` (link to the pinned node) |

QML can't set a file mode: a FileView creates a new file at the shell's umask
(the 0700 dirs keep it private), and every `prepare-state` run brings an
existing `config.json`, `config.json.old` and `cache.json` back to 0600.

## The V4 subset

QML's JavaScript engine is not Node. `js/*.mjs` and every QML JS block stay
inside this subset. The denylist is the one file `tests/js/js_subset.json`:
`tests/js/test_js_subset.mjs` greps the sources against it, and
`tests/qml/js_modules_smoke.qml` loads every module in the real engine.

Each Forbidden entry is a `note` from `js_subset.json`
(`test_contracts_docs.rb` checks that every note appears here and that no
Allowed example matches a pattern):

- **Forbidden:** object spread/rest (`{...a}`); Intl;
  String.prototype.replaceAll; Array.prototype.at; Object.fromEntries;
  flat/flatMap; TextEncoder; \p{} property escapes; \A anchor; \z anchor;
  trimStart/trimEnd; setTimeout/setInterval/queueMicrotask;
  new Date("YYYY-MM-DD"); regex s flag; named capture groups; toLocale*
  with options; localeCompare with locales/options; nullish coalescing
  (`??`); optional chaining (`?.`); structuredClone; globalThis; BigInt;
  matchAll; padStart/padEnd (use pad2); promises and async (`Promise`,
  `async`, `await`); console.error/warn (quickshell logs them as the
  shell's errors; use `console.log`); WeakMap/WeakSet/WeakRef (QV4 6.12
  segfaults in sameValueZero once a key is collected).
- **Also avoid (not enforced by a pattern):** class fields
  (`class A { x = 1 }`).
- **Allowed:** `[...a]` (array spread), `const { a = 1 } = o`
  (destructuring with defaults), `Object.assign`, `Object.entries`,
  `Object.values`, `includes`, `Number.isInteger`, and `import` between
  `.mjs` files.

## QML gotchas

- **The service gets no `settings`.** The shell injects only
  `omarchyPath`/`shell`/`manifest`/`barWidgetRegistry`/`pluginRegistry` into
  a `service`. Service tunables live in `config.json`.
- **State lives outside the plugin directory.** Writing inside it trips the
  shell's hot-reload watcher. Use `Quickshell.env("HOME")`.
- **No uppercase QML property names.** `property int RANGE_TODAY` passes
  qmllint but fails at runtime, and the widget silently doesn't load.
- **Arrow-function handlers.** Qt 6.12 (installed; Quickshell 0.3.2) doesn't
  inject signal parameters: write `onExited: (code, status) => …`.
- **Never name a property `state`** (it collides with `Item.state`; hence
  `snapshot`), and don't declare signals that shadow base signals (prefix
  them, e.g. `fieldFocusChanged`).
- **`FileView.setText` skips identical content**, so a write can't be used as
  a change signal unless something in it always changes.
- **Arrays don't survive a `var` signal parameter.** A JS object emitted
  through `signal finished(var result)` arrives as a QVariantMap whose arrays
  are sequence wrappers: indexing works, `Array.isArray()` is false, so every
  `Array.isArray` guard silently drops the data. Receivers call
  `Os.plain(value)` (a JSON round trip) first: `ThemeInfo`, `ThemeJobs` and
  `Discovery` on their own HelperProcess results, `SalesData.applyFetch` on
  the result `SalesScheduler.fetched` relays through `Service`.
  `SalesScheduler` and `SalesAccess` read only non-array fields (`ok`,
  `error` and its `retryAfter`, `name`), and neither may inspect an array
  in a result before relaying it. `Service` reads the `SalesAccess.finished`
  result directly: it carries no arrays (`name`, `origin`, or an `error`
  from `Errors.fromHelper`); a grant result that gains an array must go
  through `Os.plain` first. `tests/qml/js_modules_smoke.qml` checks the
  round trip.
- **`PlainLabel`, never `Text`.** Every string in `ui/` and `BarWidget.qml`
  renders through `ui/PlainLabel.qml` (`textFormat: Text.PlainText`, the
  panel font and colour preset). Store and theme names, CLI errors and URLs
  come from outside and must never be parsed as rich text;
  `test_contracts_qml.rb` fails on a bare `Text {` anywhere else.
- **`LineEdit`, never a TextInput, and no clipboard reads.** Qt reads
  Wayland clipboard data with no size or time bound, inside the shared
  shell: a TextInput (so `TextField`, `SpinBox`, the kit's `FilterInput` and
  `NumberField`) reads the whole clipboard on every clipboard change and on
  every native paste, and `Quickshell.clipboardText` reads it too. Text
  entry is `ui/LineEdit.qml`, a PlainText `TextEdit` (it checks offered
  formats only) whose paste keys (`StandardKey.Paste`, Shift+Insert) call
  `panel.paste`, which runs `helpers/read-clipboard`: wl-paste as a
  supervised child, 16 KiB and 2 s at most. Middle-click (primary
  selection) and dropped text are swallowed. Writing the clipboard (Copy
  command) is fine. No kit component that embeds native text entry
  either: `SearchableDropdown` (a `TextField` in its popup),
  `MultiSelect`, `FilterInput`, `NumberField` and `TextField` (the kit's
  `Dropdown` has none). Edit's theme target is `ui/ThemePicker.qml`, a
  list picker whose filter is a `LineEdit` wired to `panel.paste`.
  `test_contracts_qml.rb` derives the forbidden set from the kit
  (`$OMARCHY_PATH/shell/Ui/*.qml`, default `/usr/share/omarchy`): Qt's
  `TextInput`, `TextField`, `TextArea`, `SpinBox` and `ComboBox`, plus
  every kit component that instantiates one of them or, transitively,
  another such kit component (a fixed list is the fallback when the kit
  is missing), and fails when `ui/`, `model/`, `Service.qml` or
  `BarWidget.qml` instantiates any of them, or reads `clipboardText`.
- **A `LineEdit` `keyHandler` must stay visible.** LineEdit forwards its
  keys to it with `Keys.forwardTo`, which silently skips an item that is
  `visible: false`, so the handler is a visible 0×0 `Item` (FilterField's
  `keyRelay`), never `visible: false`.
- **qmllint doesn't check members reached through an id** (`root.foo`,
  `panel.bar`) when the root type comes from `qs.*`, and it misses unknown
  properties on instances inside such files. Only a runtime load catches
  those, so load the panel in a harness after UI changes.
- **`--alias` for login.** `auth login` needs `--alias=shop` outside a TTY,
  or it exits "Flag not specified: --alias" without opening the browser.
- **Log out before logging in.** With any session stored, an expired one
  included, `auth login` asks "Which account would you like to use?", which
  fails without a TTY. `helpers/sign-in` probes first and runs
  `auth logout --no-input` before `auth login`, but only when the probe
  says signed out: a probe that fails any other way (network, rate limit)
  exits with that error and never logs out a working session.

## UI conventions

- **Copy keys.** Every string the UI shows is a `js/copy.mjs` `STRINGS`
  entry, read through `Copy.t(key, vars)` (a missing key renders as the
  key, so a miss is visible). A key is `<area>.<thing>[.<variant>]`:
  - the area is the view or part that shows it (`home`, `store`, `edit`,
    `confirm`, `banner`, …), or a shared area: `status.*` (states the bar
    and the views share), `access.*` (sales access), `action.*` (generic
    buttons), `error.<code>` (one per error code), `keys.*` (the key
    sheet), `hints.*` (the footer's short labels), `alert.*` (order
    notifications);
  - the thing is what it is; a dialog's or banner's is `<id>.<part>`
    (`confirm.push.title`);
  - a variant chosen at run time is one more dotted segment, never a camel
    suffix (`count.orders.one`, `confirm.push.title.live`,
    `error.store_busy.anyStore`), and no camel segment extends a sibling
    key or prefix (`theme.preview.starting` beside `theme.preview`);
  - segments are lowerCamel, except error codes and folder reasons.

  `tests/js/test_copy_keys.mjs` checks the grammar, that every key the
  code names or builds exists, and that every key is read.
- **Keymaps.** Each view publishes one `keymap`, the `js/keymap.mjs` rows
  `{id, key, label, short, footerKey, chars, on, footer, sheet, group}`
  that its flags build. The key sheet lists the rows that are `on`; the
  footer (`KeyHints`, from `ShopPanel.footerText`) shows `footerRows`, at
  most `FOOTER_ROWS` rows that are `on` and have a `short` label, then the
  config-broken keys and `Esc back`; the view's `textKey` runs the row
  whose `chars` hold the typed key, `on` or not (`on` only decides what is
  listed). The footer's words are `test_keymap.mjs`'s to check; the panel
  smokes check which rows (`hints.*` keys) a screen shows.
- **Cursors.** A view's keyboard cursor is a `RowCursor` on a row id
  (`cursorId`; `cursorIndex` is derived), never an index, so a relist (a new
  backup on top), a reorder or a row that hides leaves it on its row. When
  its row goes, it moves to the nearest surviving one: in Settings the row
  above it in the fixed order, in a list the row now at its old position,
  clamped. Home keeps the selected store's domain in
  `ShopPanel.homeCursorDomain`, which survives an unreadable config.json.
  `rowIds` is each view's list of ids (Backups prefixes `b:`/`f:`; Add's
  manual row is `manualId`).
- **Text entry.** A focused `LineEdit` or an open picker owns the keys
  (`ShopPanel.inputFocused`). A field (`InputRow`, `StepperField`)
  commits on Enter, Tab or blur when its text changed; Enter and Esc give
  the keyboard back to the view (Esc reverts that field and saves nothing),
  Tab moves to the next field and keeps it. A field that hides (config.json
  unreadable) lets go of the keyboard and drops its draft.
- **Views.** Each view is a `PanelView` (`snapshot`, `service`, `panel`,
  `configInvalid` and `nowMs` from the panel, `keymap`, and no-op
  `textKey`, `deleteSelected`, `reorder`, `dropHiddenInput` it replaces
  when it has that key). `ShopPanel.route` is the view on top of the stack.
  `ViewHeader` action lists carry no reactive state (`busyIds` and
  `disabledIds` do).

## Checks

```sh
tests/run                                # every step
tests/run tests/qml/panel_edit_smoke.qml # one test (or several) of any kind
tests/run tests/ruby/test_text.rb tests/js/test_text.mjs
```

`tests/run` stops at the first failure and prints `ok <file>` for each test
that passes; the tests themselves print nothing unless they fail. Given
paths, it runs just those, each exactly as its step would (a smoke gets the
same throwaway HOME). Node is resolved from PATH, then
`$MISE_DATA_DIR/installs/node/26.13.0/bin/node`, then
`${XDG_DATA_HOME:-~/.local/share}/mise/installs/node/26.13.0/bin/node`.

1. **manifest**: `omarchy plugin validate .` (skipped with a notice when
   `omarchy` is absent); `manifest.json` parses and its `version` is
   `MAJOR.MINOR.PATCH`.
2. **syntax**: `ruby --disable-gems -c` on `lib/**/*.rb`, `helpers/*`,
   `tests/ruby/*.rb` and `tests/fixtures/bin/*`; `node --check` on
   `js/*.mjs` and `tests/js/*.mjs`; `bash -n` on `tests/run` and
   `tests/qml/fake-home.sh`.
3. **qmllint** over every `.qml` with `--ignore-settings` (no
   `.qmllint.ini` can relax it), a temp `qs` import root and every
   `qmldir` passed with `-i`. A quickshell smoke is linted from a copy
   beside a `shop` link, the layout it runs in. Any warning fails, except
   qmllint's `QObject` missing-property noise on the shell's style tokens.
4. **executables**: nothing outside `helpers/`, `tests/run` and
   `tests/fixtures/bin/` is executable, on disk or in the index.
5. **ruby**: every `tests/ruby/test_*.rb`.
6. **js**: every `tests/js/test_*.mjs`.
7. **smokes**: `js_modules_smoke.qml` first (every module in the real QML
   engine), then every other `tests/qml/*_smoke.qml`. Each runs offscreen
   in a fresh mktemp HOME under `$XDG_RUNTIME_DIR` (Shop refuses theme
   folders under `/tmp`; the step fails without a writable runtime dir),
   never one whose name spells yarn, pnpm or bun (Shop refuses the CLI
   there), with `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`,
   `XDG_CACHE_HOME` and `MISE_DATA_DIR` under it and nothing else from the
   caller's environment. `tests/qml/fake-home.sh` fills it with links to
   the fakes and fails if mise's installs dir holds anything else. A smoke
   whose first line is `// runner: quickshell` runs under `quickshell -p`
   from a config dir in that HOME (`shop`, `Ui` and `Commons` links), any
   other under `qml`. It passes when it prints `<NAME>_OK`, NAME being its
   file name upper-cased without `_smoke` (`consent_smoke.qml` prints
   `CONSENT_OK`), and no `unavailable`, `TypeError`, `ReferenceError`,
   `SyntaxError`, `is not defined` or `Cannot assign` line.
8. **payload**: prints `HEAD` and the dirty flag; fails if
   `git ls-files --others --exclude-standard` lists anything (the steps
   above test the worktree, a release commit carries only tracked files),
   or if a `.qml` named in `ui/qmldir` or `model/qmldir` is not tracked.

No test reaches the network or a real Shopify store; the fake CLI covers
the scenarios.

A smoke is a `Smoke { name; steps }` (`tests/qml/Smoke.qml`): each step is
a function, `smoke.waitFor(condition, what)` (prefer it to a fixed delay)
or `smoke.pause(ms)` (only where time itself is the point, such as "not yet
after 400 ms"). `smoke.check(ok, what)` records a failure; at the end it
prints `<name>_OK`, or `<name>_FAIL` with every failed check. A panel smoke
builds on `PanelHarness`, imported as `"shop/tests/qml"`.

Any ad-hoc run of a helper or a QML harness uses the same isolation as
step 7: a throwaway `HOME` with every XDG dir and `MISE_DATA_DIR` under
it, set explicitly (not merely unset), and `ls "$MISE_DATA_DIR/installs"`
showing only the fakes before anything runs. Inheriting the real
`XDG_DATA_HOME` points the helpers at the real CLI and the real Shopify
session.

## Manual checks

- **Running shell.** After a QML change: `omarchy-restart-shell`, wait for
  the plugins to load, then `omarchy-shell shop status`, and read the shell
  log for `ReferenceError`, `TypeError`, `is not defined` and
  `Cannot assign`. IPC changes (new, renamed or re-signed methods) are not
  visible until the restart (the running quickshell caches the old
  component across disable/enable and hot reload); test a method with
  `omarchy-shell [-q] shop <method> [args…]`.
- **UX harness.** An offscreen `shell.qml` that loads the plugin against
  the shell's `Commons`/`Ui` (only `KeyboardPanel` stubbed), drives the
  panel through one scene per state with the fake CLI and grabs
  screenshots, run under the isolation above with its theme folders under
  `$XDG_RUNTIME_DIR`. After a UI change, render at least `full`, `bars`,
  `job`, `push-fails`, `signed-out`, `throttled`, `needs-access`,
  `cli-missing`, `config-broken` and `empty`; grep the log for
  `ReferenceError`, `TypeError`, `is not defined`, `Cannot assign`,
  `Unable to assign` and `Binding loop`; look at every screenshot and check
  that no string renders as its `Copy` key.
- **Memory soak.** With an offscreen harness of the same kind (a local
  `shell.qml` you build, as for the UX harness; none ships in the repo) and
  the fake CLI, run the service with 12 stores (scenario `ok`,
  `pollSeconds` 60) for 15 minutes and sample that quickshell process every
  10 s. The PID must be the harness's own quickshell, never the running
  shell (`pgrep -x quickshell` matches both):

  ```sh
  QT_QPA_PLATFORM=offscreen quickshell -p "$harness_dir" & pid=$!
  for i in $(seq 90); do awk '/VmRSS/{print systime(), $2/1024 " MB"}' "/proc/$pid/status"; sleep 10; done
  ```

  Read RSS at 1, 5, 10 and 15 minutes. The slope after minute 5 must stay
  under 0.5 MB/min; baseline is 81 → 96 MB over the first four minutes and
  flat after. Expect 8–12 CLI spawns per minute for 12 stores, and exactly
  two `history` fetches per store per day after the first (10 min after
  the store's day rolls over, and once more 6 h later).

## Release rule

1. `tests/run` is green on a clean tree at commit `<SHA>`.
2. Tag `v<version>` on exactly `<SHA>` and push once.
3. The marketplace submission includes the SHA; the output of
   `omarchy plugin validate .` and `tests/run` at that SHA; the
   `git archive <SHA> | tar -t` listing (no agent files); the dependency
   classes (README › Requirements); and the data, network and process
   statements (README › Privacy, network and processes) and the consent
   ones (README › Theme safety, IPC reference).
4. Any change after that needs a new SHA, a new tag and a new validation
   request.

Contributions arrive as GitHub pull requests.
