import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as M

// Shop — headless service. Owns the IPC target the bar widget talks to,
// polls per-store sales, and runs theme push/pull. All external work shells
// out to `shopify` via bin/sales.sh and bin/theme.sh; no credentials live here
// (auth stays in the Shopify CLI state, one `store auth` per store).
//
// A `service` kind receives no `settings` property, so every tunable lives in
// the plugin's own config file (~/.config/shop/config.json), read through
// FileView and mutated over IPC.
Item {
  id: root

  // Injected by Omarchy's ensureService.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "shop"
  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: home + "/.config/shop"
  readonly property string configPath: configDir + "/config.json"
  readonly property string stateDir: home + "/.local/state/shop"
  readonly property string statePath: stateDir + "/state.json"
  // Pre-push snapshots of each store's live theme, taken by bin/theme.sh.
  readonly property string backupsDir: stateDir + "/backups"
  readonly property string sourceDir:
    manifest && manifest.__sourceDir
      ? String(manifest.__sourceDir)
      : home + "/.config/omarchy/plugins/" + pluginId

  property var config: ({ stores: [] })
  // domain -> poll-result object. resultFor() seeds the full field shape and is
  // the single source of truth for it, so the shape isn't repeated here.
  // Null-prototype so a domain like "constructor"/"__proto__" can't collide
  // with Object.prototype members.
  property var results: Object.create(null)
  // domain -> bool (a sales poll is in flight for this store)
  property var syncing: Object.create(null)
  // domain -> bool (a theme push/pull is in flight for this store). Split from
  // `syncing` so a theme op doesn't make the card show the sales "syncing" state.
  property var themeSyncing: Object.create(null)
  // domain -> bool (last poll authenticated; unset until first poll result)
  property var authed: Object.create(null)
  // domain -> number (last-seen today order count). Set on the first successful
  // poll; a later poll with a higher count fires a new-order notification.
  property var prevOrders: Object.create(null)
  // domain -> bool (a `theme dev` live-preview is running for this store)
  property var devRunning: Object.create(null)
  // domain -> string (preview URL captured from the dev process stdout)
  property var devUrl: Object.create(null)
  // domain -> live `theme dev` Process (one per store, long-running)
  property var devProcesses: Object.create(null)

  readonly property int refreshIntervalSec:
    Math.max(1, parseInt(String(config.refreshIntervalSec), 10) || 60)

  // New-order notifications are on by default; `notifyNewOrders: false` in
  // config.json (or the config-mode toggle) silences the notify-send.
  readonly property bool notifyNewOrders: config.notifyNewOrders !== false
  // Set when a sales poll fails because the `shopify` binary is absent, and
  // cleared on the next successful poll — drives the panel's warning banner.
  property bool cliMissing: false
  // True while `npm install -g @shopify/cli@latest` is in flight; the banner
  // shows "Installing…" and hides the Install button.
  property bool cliInstalling: false
  // stderr from a failed CLI install, surfaced as a second line in the banner.
  property string cliInstallError: ""

  // domain -> live sales Process instance. One Process per store, all fetched
  // concurrently; startFetch dedups so a store already in flight isn't
  // re-spawned.
  property var fetches: Object.create(null)

  // Theme op bookkeeping: which store and direction the running op belongs to.
  property string themeAction: ""
  property string themeDomain: ""
  property bool themeTimedOut: false

  // Store discovery (discoverStores): read the connected stores from the auth
  // session list, then enrich each one's real name with a fast per-store
  // `shop { name }` query, writing the {name, domain} list to discovered.json
  // for the widget to pick from. Discovery is async, so the IPC method only
  // fires it; the result lands in the state file.
  property bool discovering: false
  property bool discoveryTimedOut: false
  property var discoveryFound: []    // accumulated {name, domain}
  property var discoveryPending: null // subdomain -> true (phase-1 names still to enrich)

  // ------------------------------------------------------------- helpers

  function findStore(domain) {
    var dm = String(domain || "")
    var list = config.stores || []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && String(list[i].domain) === dm) return list[i]
    }
    return null
  }

  function resultFor(domain) {
    var dm = String(domain || "")
    var r = results[dm]
    if (!r) {
      r = { today: null, week: null, month: null, biweek: null, allTime: null, yesterday: null, yesterdaySoFar: null, statsToday: null, statsYesterday: null, statsWeek: null, statsBiweek: null, statsMonth: null, statsAll: null, weekSeries: [], biweekSeries: [], monthSeries: [], allTimeSeries: [], lastError: null,
            lastUpdated: 0, lastSyncOutput: "", lastSyncError: "" }
      results[dm] = r
    }
    return r
  }

  // Every parsed range maps to the same {sales, orders} shape, with nulls
  // preserved so a store that has not reported a figure yet stays null.
  function pickRange(x) {
    return { sales: x ? x.sales : null, orders: x ? x.orders : null }
  }

  // The widget's contract: one entry per store, merging config + poll results.
  function stateObject() {
    var stores = []
    var list = config.stores || []
    for (var i = 0; i < list.length; i++) {
      var s = list[i]
      if (!s || !s.domain) continue
      var dm = String(s.domain)
      var r = results[dm]
      stores.push({
        name: String(s.name || ""),
        domain: dm,
        currency: (r && r.currency) ? r.currency : "$",
        today: r && r.today ? r.today : null,
        week: r && r.week ? r.week : null,
        month: r && r.month ? r.month : null,
        biweek: r && r.biweek ? r.biweek : null,
        allTime: r && r.allTime ? r.allTime : null,
        yesterday: r && r.yesterday ? r.yesterday : null,
        yesterdaySoFar: r && r.yesterdaySoFar ? r.yesterdaySoFar : null,
        statsToday: r && r.statsToday ? r.statsToday : null,
        statsYesterday: r && r.statsYesterday ? r.statsYesterday : null,
        statsWeek: r && r.statsWeek ? r.statsWeek : null,
        statsBiweek: r && r.statsBiweek ? r.statsBiweek : null,
        statsMonth: r && r.statsMonth ? r.statsMonth : null,
        statsAll: r && r.statsAll ? r.statsAll : null,
        weekSeries: r && r.weekSeries ? r.weekSeries : [],
        biweekSeries: r && r.biweekSeries ? r.biweekSeries : [],
        monthSeries: r && r.monthSeries ? r.monthSeries : [],
        allTimeSeries: r && r.allTimeSeries ? r.allTimeSeries : [],
        lastUpdated: r && r.lastUpdated ? r.lastUpdated : 0,
        lastError: r && r.lastError != null ? r.lastError : null,
        lastSyncOutput: r && r.lastSyncOutput ? r.lastSyncOutput : "",
        lastSyncError: r && r.lastSyncError ? r.lastSyncError : "",
        syncing: syncing[dm] === true,
        themeSyncing: themeSyncing[dm] === true,
        themeAction: root.themeAction,
        authed: authed[dm] === true,
        devRunning: devRunning[dm] === true,
        devUrl: devUrl[dm] ? devUrl[dm] : ""
      })
    }
    return { notifyNewOrders: root.notifyNewOrders, cliMissing: root.cliMissing,
             cliInstalling: root.cliInstalling,
             cliInstallError: root.cliInstallError, stores: stores }
  }

  function writeState() {
    stateFile.setText(JSON.stringify(stateObject(), null, 2) + "\n")
  }

  function persistConfig() {
    configFile.setText(JSON.stringify(config, null, 2) + "\n")
  }

  function applyConfig(raw) {
    var parsed
    try {
      parsed = JSON.parse(String(raw || ""))
    } catch (e) {
      parsed = null
    }
    if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.stores)) {
      config = { refreshIntervalSec: 60, stores: [] }
    } else {
      config = parsed
    }
    writeState()
    // First load and any later edit (own write or external) both repoll soon,
    // so a new store shows figures without waiting out the full interval.
    refreshDebounce.restart()
  }

  // ------------------------------------------------------------- sales poll

  // `refresh` (IPC/manual) repolls everything for freshness; the two cadences
  // (live 60s / historical hourly) each call their own half.
  function refresh() {
    var list = config.stores || []
    if (list.length === 0) {
      writeState()
      return "ok"
    }
    refreshLive()
    refreshHistorical()
    return "ok"
  }

  // Live cadence: today's orders + today's sessions only — the fields that
  // change during the day. Completed periods are polled hourly, not here.
  function refreshLive() {
    var list = config.stores || []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].domain) startFetch(String(list[i].domain), "live")
    }
  }

  // Historical cadence: completed periods (week/biweek/month/allTime/yesterday)
  // + their sessions + timeseries. Cached; does not change during the day.
  function refreshHistorical() {
    var list = config.stores || []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].domain) startFetch(String(list[i].domain), "historical")
    }
  }

  // Refresh a single store on demand (bar right-click / card glyph). Runs
  // immediately, concurrent with any other stores' in-flight fetches.
  function refreshStore(domain) {
    var dm = String(domain || "")
    if (dm === "") return "error: no domain"
    startFetch(dm, "live")
    startFetch(dm, "historical")
    return "ok"
  }

  // Dedup per domain+mode, so a live and historical fetch for the same store
  // can run concurrently and neither blocks the other.
  function startFetch(domain, mode) {
    var dm = String(domain || "")
    var md = String(mode || "live")
    var key = dm + ":" + md
    if (dm === "" || fetches[key]) return
    syncing[dm] = true
    writeState()
    var f = salesFetchComponent.createObject(root, { svc: root, dm: dm, mode: md })
    if (!f) {
      syncing[dm] = !!(fetches[dm + ":live"] || fetches[dm + ":historical"])
      writeState()
      return
    }
    fetches[key] = f
    f.startedAt = Date.now()
    f.running = true
  }

  // `syncing` reflects "any fetch in flight": cleared only when both modes are
  // done (no live or historical ref left in the fetches map).
  function finishFetch(domain, mode) {
    var dm = String(domain || "")
    var md = String(mode || "live")
    fetches[dm + ":" + md] = undefined
    syncing[dm] = !!(fetches[dm + ":live"] || fetches[dm + ":historical"])
    writeState()
  }

  function handleSales(domain, mode, exitCode, stdoutText, stderrText) {
    var dm = String(domain || "")
    var md = String(mode || "live")
    var errText = String(stderrText || "")
    var r = resultFor(dm)
    // The bin/sales.sh guard reports a missing CLI on stderr and exits 127;
    // flag it centrally so the widget can surface a warning banner.
    if (/not found|command not found/i.test(errText)) {
      root.cliMissing = true
    }
    var authDenied = /access scope|ACCESS_DENIED|read_reports/i.test(errText)
    if (authDenied) {
      // Only an auth denial flips authed off. A network/parse error leaves the
      // store's auth status alone, since it may still hold a valid session.
      authed[dm] = false
      r.lastError = "Authentication required"
    } else if (/throttl|rate.?limit|429/i.test(errText)) {
      // Defensive: the CLI has no way to read the shopifyqlCost extension, so
      // proactive throttling isn't possible — surface a friendly message when
      // Shopify does throttle us instead of dumping raw stderr.
      r.lastError = "Rate limited — retrying soon"
    } else if (exitCode !== 0) {
      r.lastError = errText.trim() !== "" ? errText.trim() : "Sales query failed"
    } else {
      try {
        var parsed = M.parseSales(JSON.parse(String(stdoutText || "{}")))
        if (parsed.currency != null) r.currency = parsed.currency
        r.lastError = null
        r.lastUpdated = Date.now()
        authed[dm] = true
        root.cliMissing = false

        if (md === "live") {
          // Today-only fields change throughout the day; assign unconditionally
          // so a failed/empty poll reflects "no data yet" rather than stale.
          r.today = pickRange(parsed.today)
          if (parsed.statsToday != null) r.statsToday = parsed.statsToday

          // New-order notification: only once a store has a baseline, and only
          // when today's order count has actually grown between polls.
          var todayOrders = (parsed.today && parsed.today.orders != null) ? parsed.today.orders : null
          if (todayOrders != null) {
            var prev = prevOrders[dm]
            if (root.notifyNewOrders && prev !== undefined && todayOrders > prev) {
              var store = findStore(dm)
              var name = store ? String(store.name || dm) : dm
              var money = M.formatMoney(parsed.today.sales, r.currency)
              Quickshell.execDetached(["notify-send", "-a", "Shop", "New order",
                                       name + ": now " + todayOrders + " orders today (" + money + ")"])
              Quickshell.execDetached(["paplay", root.sourceDir + "/sounds/coin.oga"])
            }
            prevOrders[dm] = todayOrders
          }
        } else {
          // Historical fields are cached; a null parse must not clobber a prior
          // good value (e.g. a single throttled field mid-poll), so each is
          // guarded before assignment. `yesterdaySoFar` (same-time-of-day) keeps
          // its own line; the {sales, orders} ranges and the stats/series
          // passthrough fields fold into name loops with identical null-guard
          // semantics.
          var rangeFields = ["week", "month", "biweek", "allTime", "yesterday"]
          for (var i = 0; i < rangeFields.length; i++) {
            var f = rangeFields[i]
            if (parsed[f] != null) r[f] = pickRange(parsed[f])
          }
          if (parsed.yesterdaySoFar != null) r.yesterdaySoFar = pickRange(parsed.yesterdaySoFar)
          var passthroughFields = ["statsYesterday", "statsWeek", "statsBiweek", "statsMonth", "statsAll", "weekSeries", "biweekSeries", "monthSeries", "allTimeSeries"]
          for (var j = 0; j < passthroughFields.length; j++) {
            var g = passthroughFields[j]
            if (parsed[g] != null) r[g] = parsed[g]
          }
        }
      } catch (e) {
        r.lastError = "Failed to parse sales response"
      }
    }
  }

  function handleSalesTimeout(domain) {
    var dm = String(domain || "")
    var r = resultFor(dm)
    r.lastError = "Sales query timed out"
  }

  // One-click CLI install. `npm install -g` runs under mise's user-owned node,
  // so no sudo is needed. A successful install is picked up by the next sales
  // poll (up to refreshIntervalSec later), which clears cliMissing on its own.
  function installCli() {
    if (cliInstalling) return "error: already installing"
    cliInstalling = true
    cliInstallError = ""
    writeState()
    cliInstallProcess.command = ["npm", "install", "-g", "@shopify/cli@latest"]
    cliInstallProcess.running = true
    return "ok"
  }

  // ------------------------------------------------------------- theme ops

  function push(domain) { return startTheme("push", domain) }
  function pull(domain) { return startTheme("pull", domain) }

  function startTheme(action, domain, overrideDir, overrideTheme) {
    var dm = String(domain || "")
    if (themeProcess.running) return "error: a theme operation is already running"
    var store = findStore(dm)
    if (!store) return "error: unknown store"
    var dir = (overrideDir !== undefined && overrideDir !== null && overrideDir !== "")
      ? String(overrideDir)
      : String(store.themeDir || "")
    if (dir === "") return "error: no theme directory — set it in the store's edit form"
    var theme = (overrideTheme !== undefined && overrideTheme !== null && overrideTheme !== "")
      ? String(overrideTheme)
      : String(store.theme || "live")
    themeAction = action
    themeDomain = dm
    themeSyncing[dm] = true
    writeState()
    themeProcess.command = ["bash", root.sourceDir + "/bin/theme.sh", action, dm, dir, theme]
    themeWatchdog.restart()
    themeProcess.running = true
    return "ok"
  }

  // Revert a push by pushing a saved pre-push snapshot back to the live theme.
  // Reuses the same theme.sh push path (which snapshots the current live theme
  // first, so the restore itself is reversible), but with the backup dir as the
  // source and "live" as the target. `epoch` must be a bare integer dir name —
  // anything else (a path, "..", an empty string) is rejected up front.
  function restoreBackup(domain, epoch) {
    var dm = String(domain || "")
    var ep = String(epoch || "").trim()
    if (!/^\d+$/.test(ep)) return "error: invalid backup"
    return startTheme("push", dm, root.backupsDir + "/" + dm + "/" + ep, "live")
  }

  // ------------------------------------------------------------- theme dev

  // Start a long-lived `shopify theme dev` live-preview for one store. Resolves
  // the store's selected theme: "live" -> --allow-live, otherwise -t <theme>.
  // The process streams its output (waitForEnd: false) so the preview URL can be
  // captured the moment the CLI prints it, rather than at exit — a dev server
  // only exits on kill or crash.
  function startDev(domain) {
    var dm = String(domain || "")
    if (dm === "") return "error: no domain"
    var store = findStore(dm)
    if (!store) return "error: unknown store"
    if (!store.themeDir) return "error: no theme directory"
    if (devRunning[dm]) return "error: theme dev already running"
    var args = ["shopify", "theme", "dev", "-s", dm]
    var theme = String(store.theme || "live")
    if (theme === "live") args.push("--allow-live")
    else args.push("-t", theme)
    args.push("--no-color", "--path", String(store.themeDir))

    devRunning[dm] = true
    devUrl[dm] = ""
    writeState()
    // The URL is scraped by devScanTimer (polling) as a reliable fallback to the
    // StdioCollector dataChanged fast-path; start it now so it begins watching.
    devScanTimer.restart()

    var p = devProcessComponent.createObject(root, { svc: root, dm: dm })
    if (!p) {
      devRunning[dm] = false
      writeState()
      return "error: failed to spawn theme dev"
    }
    devProcesses[dm] = p
    p.command = args
    p.running = true
    return "ok"
  }

  function stopDev(domain) {
    var dm = String(domain || "")
    var p = devProcesses[dm]
    if (p) {
      devProcesses[dm] = undefined
      // Kill the dev server; onExited sees devRunning already cleared and no-ops.
      p.running = false
    }
    devRunning[dm] = false
    devUrl[dm] = ""
    writeState()
    return "ok"
  }

  function setDevUrl(domain, url) {
    devUrl[String(domain || "")] = url
    // The Dev button is expected to pop the preview in the browser, so open it
    // as soon as the URL is scraped (setDevUrl fires once — captureUrl returns
    // early once devUrl is already set).
    if (url) Quickshell.execDetached(["xdg-open", String(url)])
    writeState()
  }

  // Fired by the dev Process on exit. stopDev clears devRunning before the kill
  // lands, so a still-set flag here means the process exited on its own
  // (crash/error) — surface the stderr rather than leaving the store "running".
  function devExited(domain, exitCode, stderrText) {
    var dm = String(domain || "")
    devProcesses[dm] = undefined
    if (!devRunning[dm]) return
    devRunning[dm] = false
    devUrl[dm] = ""
    var r = resultFor(dm)
    var errText = M.stripAnsi(String(stderrText || ""))
    r.lastSyncError = errText !== "" ? errText : ("theme dev exited (code " + exitCode + ")")
    writeState()
  }

  // ------------------------------------------------------------- store discovery

  function discoverStores() {
    if (discovering) return "error: discovery already running"
    discovering = true
    discoveryTimedOut = false
    discoveryFound = []
    discoveryPending = Object.create(null)
    // Phase 1: the auth session list already knows every connected store, so the
    // widget can show entries ~1s after `discover` instead of waiting out a walk
    // of all 19 orgs. Phase 2 (handleShopName) enriches real names per store.
    authProcess.command = ["shopify", "store", "auth", "list", "--json"]
    authProcess.running = true
    discoveryWatchdog.interval = 30000
    discoveryWatchdog.restart()
    return "ok"
  }

  function handleAuthList(exitCode, stdoutText) {
    if (exitCode !== 0) { finishDiscovery([]); return }
    var sessions = []
    try {
      var parsed = JSON.parse(String(stdoutText || "{}"))
      if (parsed && Array.isArray(parsed.sessions)) sessions = parsed.sessions
    } catch (e) { finishDiscovery([]); return }
    discoveryFound = []
    discoveryPending = Object.create(null)
    for (var i = 0; i < sessions.length; i++) {
      var s = sessions[i]
      if (!s || !s.subdomain) continue
      var sub = String(s.subdomain)
      if (sub === "" || discoveryPending[sub]) continue
      discoveryPending[sub] = true
      discoveryFound.push({ name: sub, domain: sub + ".myshopify.com" })
    }
    if (discoveryFound.length === 0) { finishDiscovery([]); return }
    // Land the phase-1 result now; discovery stays in flight to enrich names.
    writeDiscovery()
    // Phase 2: resolve each store's real name with a fast per-store
    // `shop { name }` query. The store count is tiny (a handful), so spawn them
    // all at once rather than bounding like the old 19-org walk.
    for (var j = 0; j < discoveryFound.length; j++) {
      var entry = discoveryFound[j]
      if (!entry || !entry.domain) continue
      var p = shopNameComponent.createObject(root, { svc: root, dm: String(entry.domain) })
      if (p) p.running = true
    }
    discoveryWatchdog.interval = 30000
    discoveryWatchdog.restart()
  }

  function handleShopName(exitCode, stdoutText, dm) {
    if (!discovering) return
    var sub = dm.slice(-14) === ".myshopify.com" ? dm.slice(0, -14) : dm
    if (exitCode === 0) {
      try {
        // `store execute -j` returns the data object directly — no `data`
        // wrapper — so the name is parsed.shop.name.
        var parsed = JSON.parse(String(stdoutText || "{}"))
        if (parsed && parsed.shop && typeof parsed.shop.name === "string" && parsed.shop.name !== "") {
          for (var i = 0; i < discoveryFound.length; i++) {
            if (discoveryFound[i] && discoveryFound[i].domain === dm) {
              discoveryFound[i].name = parsed.shop.name
              break
            }
          }
        }
      } catch (e) {
        // A malformed response keeps the subdomain name (graceful degradation).
      }
    }
    // Count this store resolved regardless of success so discovery always settles.
    if (sub !== "" && discoveryPending) delete discoveryPending[sub]
    if (Object.keys(discoveryPending).length === 0) finishDiscovery(discoveryFound)
  }

  function writeDiscovery() {
    // Include a timestamp so the payload never equals the previous one — otherwise
    // FileView.setText() skips the write when content is unchanged and the widget's
    // onFileChanged never fires, leaving the picker stuck on "Discovering…".
    discoveryFile.setText(JSON.stringify({ stores: discoveryFound, discoveredAt: Date.now() }, null, 2) + "\n")
  }

  function finishDiscovery(list) {
    discovering = false
    discoveryWatchdog.stop()
    discoveryFound = list || []
    discoveryFound.sort(function(a, b) { return M.naturalCompare(a ? a.name : "", b ? b.name : "") })
    writeDiscovery()
  }

  // ------------------------------------------------------------- config mutation

  function addStore(name, domain, themeDir) {
    var nm = String(name || "").trim()
    var dm = String(domain || "").trim()
    if (nm === "") return "error: name must not be empty"
    if (dm === "") return "error: domain must not be empty"
    if (findStore(dm)) return "error: a store with this domain already exists"
    var stores = (config.stores || []).slice()
    // Default the new store to shown only if fewer than 3 stores are already on
    // the bar; otherwise it starts hidden (the user must free a slot first).
    var shown = 0
    for (var i = 0; i < stores.length; i++) {
      if (stores[i] && stores[i].showOnBar !== false) shown++
    }
    stores.push({ name: nm, domain: dm, themeDir: String(themeDir || "").trim(), theme: "live", showOnBar: shown < 3 })
    config = Object.assign({}, config, { stores: stores })
    persistConfig()
    // Auth happens here, not as a manual setup step; authed stays false until
    // a later poll succeeds.
    return authStore(dm)
  }

  function updateStore(domain, field, value) {
    var dm = String(domain || "")
    if (!findStore(dm)) return "error: unknown store"
    var f = String(field || "")
    var v = value === undefined ? "" : value
    var stores = (config.stores || []).slice()
    for (var i = 0; i < stores.length; i++) {
      if (String(stores[i].domain) !== dm) continue
      var updated = Object.assign({}, stores[i])
      if (f === "domain") {
        var nd = String(v || "").trim()
        if (nd === "") return "error: domain must not be empty"
        if (nd !== dm && findStore(nd)) return "error: a store with this domain already exists"
        updated.domain = nd
        if (nd !== dm) {
          results[nd] = results[dm]; delete results[dm]
          syncing[nd] = syncing[dm]; delete syncing[dm]
          authed[nd] = authed[dm]; delete authed[dm]
          prevOrders[nd] = prevOrders[dm]; delete prevOrders[dm]
          themeSyncing[nd] = themeSyncing[dm]; delete themeSyncing[dm]
          devRunning[nd] = devRunning[dm]; delete devRunning[dm]
          devUrl[nd] = devUrl[dm]; delete devUrl[dm]
          devProcesses[nd] = devProcesses[dm]; delete devProcesses[dm]
          fetches[nd + ":live"] = fetches[dm + ":live"]; delete fetches[dm + ":live"]
          fetches[nd + ":historical"] = fetches[dm + ":historical"]; delete fetches[dm + ":historical"]
          // If a `theme dev` Process was running during the rename, its captured
          // `dm` stays the old value; devExited(oldDm) will no-op on the missing
          // key (extreme edge case — a rename mid-dev — acceptable).
        }
      } else if (f === "name") {
        var nn = String(v || "").trim()
        if (nn === "") return "error: name must not be empty"
        updated.name = nn
      } else if (f === "themeDir") {
        updated.themeDir = String(v || "").trim()
      } else if (f === "theme") {
        updated.theme = String(v || "live").trim()
      } else if (f === "showOnBar") {
        updated.showOnBar = (String(v) === "true" || String(v) === "1")
      } else {
        return "error: unknown field: " + f
      }
      stores[i] = updated
    }
    config = Object.assign({}, config, { stores: stores })
    persistConfig()
    writeState()
    return "ok"
  }

  function removeStore(domain) {
    var dm = String(domain || "")
    if (!findStore(dm)) return "error: unknown store"
    // A store removed while `theme dev` is running would orphan its long-lived
    // dev Process (it only exits on kill/crash), so stop it before scrubbing.
    if (devRunning[dm]) stopDev(dm)
    var stores = []
    var list = config.stores || []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].domain) !== dm) stores.push(list[i])
    }
    config = Object.assign({}, config, { stores: stores })
    persistConfig()
    delete results[dm]
    delete syncing[dm]
    delete authed[dm]
    delete prevOrders[dm]
    delete themeSyncing[dm]
    delete devRunning[dm]
    delete devUrl[dm]
    delete devProcesses[dm]
    delete fetches[dm + ":live"]
    delete fetches[dm + ":historical"]
    writeState()
    return "ok"
  }

  function reorderStore(domain, newIndex) {
    var dm = String(domain || "")
    var idx = -1
    for (var i = 0; i < config.stores.length; i++) {
      if (config.stores[i] && String(config.stores[i].domain) === dm) { idx = i; break }
    }
    if (idx < 0) return "error: unknown store"
    var n = Math.max(0, Math.min(config.stores.length - 1, Math.round(newIndex)))
    if (idx === n) return "ok"
    var item = config.stores.splice(idx, 1)[0]
    config.stores.splice(n, 0, item)
    persistConfig()
    writeState()
    return "ok"
  }

  function setNotifyNewOrders(enabled) {
    var e = String(enabled || "")
    config = Object.assign({}, config, { notifyNewOrders: e === "true" || e === "1" })
    persistConfig()
    writeState()
    return "ok"
  }

  function authStore(domain) {
    var dm = String(domain || "")
    if (!findStore(dm)) return "error: unknown store"
    authed[dm] = false
    writeState()
    Quickshell.execDetached(["shopify", "store", "auth", "-s", dm, "--scopes", "read_reports,read_orders"])
    return "ok"
  }

  // ------------------------------------------------------------- files

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyConfig(text())
    onLoadFailed: root.applyConfig("")
    onFileChanged: reload()
  }

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    printErrors: false
    onSaveFailed: {
      // First write can race the mkdir in Component.onCompleted; ensure the
      // directory exists and retry once.
      Quickshell.execDetached(["mkdir", "-p", root.stateDir])
      stateRetryTimer.restart()
    }
  }

  FileView {
    id: discoveryFile
    path: root.stateDir + "/discovered.json"
    atomicWrites: true
    printErrors: false
  }

  // ------------------------------------------------------------- processes

  // One Process per store, spawned on demand by startFetch so every store's
  // sales query runs concurrently. The service keeps a live reference in
  // `fetches` for dedup; on exit it reports back, clears the reference, and
  // destroys itself (createObject parents it to the service, so without an
  // explicit destroy it would linger for the service's lifetime).
  Component {
    id: salesFetchComponent
    Process {
      id: self
      property var svc: null
      property string dm: ""
      property string mode: "live"
      property bool timedOut: false
      property real startedAt: 0

      command: ["bash", svc.sourceDir + "/bin/sales.sh", dm, mode]
      stdout: StdioCollector { id: out; waitForEnd: true }
      stderr: StdioCollector { id: err; waitForEnd: true }

      onExited: function(exitCode) {
        if (self.timedOut) {
          self.svc.handleSalesTimeout(self.dm)
        } else {
          self.svc.handleSales(self.dm, self.mode, exitCode, out.text, err.text)
        }
        self.svc.finishFetch(self.dm, self.mode)
        self.destroy()
      }
    }
  }

  // Long-running `shopify theme dev` per store, spawned by startDev. Unlike the
  // sales/theme collectors above (waitForEnd: true, which only delivers output
  // once the process exits), this one streams: the preview URL is scraped from
  // the output (dataChanged fires per chunk as a fast path; devScanTimer polls
  // as the reliable path) and the server is killed with `running = false` on
  // stop. On its own exit, devExited clears the flags and surfaces stderr as
  // lastSyncError.
  Component {
    id: devProcessComponent
    Process {
      id: self
      property var svc: null
      property string dm: ""

      stdout: StdioCollector {
        id: devStdout
        waitForEnd: false
        onDataChanged: self.captureUrl()
      }
      stderr: StdioCollector { id: devStderr; waitForEnd: false }

      function captureUrl() {
        if (self.svc.devUrl[self.dm]) return
        // The banner (and its preview URL) lands on stderr, not stdout — the
        // CLI routes the interactive menu there. Check both so the URL is
        // caught regardless of which stream the current CLI build uses.
        var m = /https?:\/\/[^\s"' ]+/.exec(devStdout.text)
        if (!m) m = /https?:\/\/[^\s"' ]+/.exec(devStderr.text)
        if (m) {
          // The CLI may frame the URL with box-drawing glyphs or punctuation;
          // neither can terminate a real URL, so strip them from the tail.
          self.svc.setDevUrl(self.dm, String(m[0]).replace(/[),.;:\u2500-\u257F]+$/, ""))
        }
      }

      onExited: function(exitCode) {
        self.svc.devExited(self.dm, exitCode, devStderr.text)
        self.destroy()
      }
    }
  }

  Process {
    id: themeProcess
    command: []
    stdout: StdioCollector { id: themeStdout; waitForEnd: true }
    stderr: StdioCollector { id: themeStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var dm = root.themeDomain
      var action = root.themeAction
      root.themeDomain = ""
      root.themeAction = ""
      themeSyncing[dm] = false
      var r = root.resultFor(dm)
      if (root.themeTimedOut) {
        root.themeTimedOut = false
        r.lastSyncOutput = ""
        r.lastSyncError = (action === "pull" ? "Pull" : "Push") + " timed out"
      } else if (exitCode === 0) {
        r.lastSyncOutput = M.stripAnsi(String(themeStdout.text || ""))
        r.lastSyncError = ""
      } else {
        r.lastSyncOutput = M.stripAnsi(String(themeStdout.text || ""))
        r.lastSyncError = M.stripAnsi(String(themeStderr.text || "")) || (action + " failed")
      }
      root.writeState()
    }
  }

  Process {
    id: authProcess
    command: []
    stdout: StdioCollector { id: authStdout; waitForEnd: true }
    stderr: StdioCollector { id: authStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (root.discoveryTimedOut) {
        root.discoveryTimedOut = false
        root.finishDiscovery([])
      } else {
        root.handleAuthList(exitCode, authStdout.text)
      }
    }
  }

  // One-shot global Shopify CLI install. stdout is collected (npm logs there)
  // but only stderr is surfaced on failure.
  // After a successful CLI install, re-poll every few seconds until the mise
  // npm hook has reshimmmed (created the `shopify` shim) and cliMissing clears.
  // Keeps cliInstalling true the whole time so the banner shows "Installing…"
  // without flashing the Install button again.
  Timer {
    id: installRefreshTimer
    interval: 3000
    repeat: true
    property int tries: 0
    onTriggered: {
      tries += 1
      if (root.cliMissing && tries < 10) {
        root.refreshLive()
      } else {
        root.cliInstalling = false
        tries = 0
        stop()
        root.writeState()
      }
    }
  }

  Process {
    id: cliInstallProcess
    command: []
    stdout: StdioCollector { id: cliInstallStdout; waitForEnd: true }
    stderr: StdioCollector { id: cliInstallStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var err = M.stripAnsi(String(cliInstallStderr.text || "")).trim()
        root.cliInstallError = err !== "" ? err : "CLI install failed"
        root.cliInstalling = false
      } else {
        root.cliInstallError = ""
        // Keep cliInstalling true so the banner keeps showing "Installing…"
        // (and hides the Install button) until the retry loop confirms the
        // shopify shim has resolved — the timer clears cliInstalling then.
        installRefreshTimer.tries = 0
        installRefreshTimer.restart()
      }
      root.writeState()
    }
  }

  // One `shopify store execute` process per discovered store, spawned all at
  // once by handleAuthList (the store count is tiny, so no bounding is needed).
  // Each onExited reports back through handleShopName and destroys itself — the
  // same concurrent-Process idiom as salesFetchComponent.
  Component {
    id: shopNameComponent
    Process {
      id: self
      property var svc: null
      property string dm: ""

      command: ["shopify", "store", "execute", "-j", "-s", dm, "-q", "{ shop { name } }"]
      stdout: StdioCollector { id: out; waitForEnd: true }
      stderr: StdioCollector { id: err; waitForEnd: true }

      onExited: function(exitCode) {
        if (!self.svc.discoveryTimedOut) {
          self.svc.handleShopName(exitCode, out.text, self.dm)
        }
        self.destroy()
      }
    }
  }

  // ------------------------------------------------------------- timers

  Timer {
    id: pollTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refreshLive()
  }

  // Completed periods don't change during the day, so refresh them once an hour
  // (Shopify's guidance: cache completed periods rather than re-querying).
  Timer {
    id: historicalPollTimer
    interval: 3600000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refreshHistorical()
  }

  Timer {
    id: refreshDebounce
    interval: 600
    repeat: false
    onTriggered: root.refresh()
  }

  // Force-kill a hung theme op (push/pull can be slow, hence the 120s window).
  Timer {
    id: themeWatchdog
    interval: 120000
    repeat: false
    onTriggered: {
      if (themeProcess.running) {
        root.themeTimedOut = true
        themeProcess.running = false
      }
    }
  }

  // Concurrent sales fetches have no per-fetch watchdog (Process has no
  // default property for a child Timer), so one timer here sweeps the live and
  // historical fetches and force-kills any that overrun 15s.
  Timer {
    id: salesWatchdog
    interval: 5000
    repeat: true
    running: true
    onTriggered: {
      var now = Date.now()
      for (var key in root.fetches) {
        var f = root.fetches[key]
        if (f && (now - f.startedAt) > 15000) {
          f.timedOut = true
          f.running = false
        }
      }
    }
  }

  // Polls `theme dev` output to capture the preview URL. StdioCollector's
  // dataChanged does not fire reliably in this Quickshell build, so this timer
  // is the reliable path; it runs only while some store's dev server is live.
  Timer {
    id: devScanTimer
    interval: 500
    repeat: true
    onTriggered: {
      var any = false
      for (var dm in root.devRunning) {
        if (!root.devRunning[dm]) continue
        any = true
        var p = root.devProcesses[dm]
        if (p && !root.devUrl[dm]) p.captureUrl()
      }
      devScanTimer.running = any
    }
  }

  // Per-call watchdog for discovery. Phase 1 (auth list) is guarded per call;
  // phase 2 (the concurrent `shop { name }` batch) is guarded as a whole with
  // the window set in handleAuthList. A stalled phase-1 process is killed; a
  // stalled phase-2 batch settles to the subdomain names already landed.
  Timer {
    id: discoveryWatchdog
    interval: 30000
    repeat: false
    onTriggered: {
      if (authProcess.running) {
        root.discoveryTimedOut = true
        authProcess.running = false
      } else if (root.discovering) {
        // Phase-2 batch guard: the subdomain names are already written, so
        // settle to whatever we have rather than aborting to [].
        root.discoveryTimedOut = true
        root.finishDiscovery(root.discoveryFound)
      }
    }
  }

  Timer {
    id: stateRetryTimer
    interval: 500
    repeat: false
    onTriggered: root.writeState()
  }

  // ------------------------------------------------------------- IPC

  IpcHandler {
    target: root.pluginId

    function ping(): string { return "ok" }
    function refresh(): string { return root.refresh() }
    function refreshStore(domain: string): string { return root.refreshStore(domain) }
    function push(domain: string): string { return root.push(domain) }
    function pull(domain: string): string { return root.pull(domain) }
    function addStore(name: string, domain: string, themeDir: string): string { return root.addStore(name, domain, themeDir) }
    function updateStore(domain: string, field: string, value: string): string { return root.updateStore(domain, field, value) }
    function removeStore(domain: string): string { return root.removeStore(domain) }
    function reorderStore(domain: string, newIndex: string): string { return root.reorderStore(domain, parseInt(newIndex, 10)) }
    function setNotifyNewOrders(enabled: string): string { return root.setNotifyNewOrders(enabled) }
    function authStore(domain: string): string { return root.authStore(domain) }
    function discoverStores(): string { return root.discoverStores() }
    function installCli(): string { return root.installCli() }
    function restoreBackup(domain: string, epoch: string): string { return root.restoreBackup(domain, epoch) }
    function startDev(domain: string): string { return root.startDev(domain) }
    function stopDev(domain: string): string { return root.stopDev(domain) }
  }

  Component.onCompleted: {
    Quickshell.execDetached(["mkdir", "-p", configDir])
    Quickshell.execDetached(["mkdir", "-p", stateDir])
  }
}
