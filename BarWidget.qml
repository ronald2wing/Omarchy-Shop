import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as M

// Shop bar widget: one bar button per store (today's sales · orders) and a
// keyboard-driven popup with per-store detail, Push/Pull theme sync, and store
// management. All state comes from the service's files — no IPC round-trips for
// display. The service (Service.qml) owns the IPC target, so this widget holds
// no IpcHandler of its own (manageIpc: false) and only *sends* actions.
Panel {
  id: root
  moduleName: "shop"
  manageIpc: false

  readonly property string pluginId: "shop"
  readonly property string home: Quickshell.env("HOME")
  // Runtime state (sales ranges, syncing, authed, lastError/lastSyncError) written by the service.
  readonly property string statePath: home + "/.local/state/shop/state.json"
  // Store config (name/domain/themeDir), also owned by the service.
  readonly property string configPath: home + "/.config/shop/config.json"
  // Stores the service discovers via discoverStores(); written after each run.
  readonly property string discoveredPath: home + "/.local/state/shop/discovered.json"
  // Pre-push snapshots the service's bin/theme.sh takes before every push.
  readonly property string backupsDir: home + "/.local/state/shop/backups"

  // The bar injects `bar` after creation; guard every read until then.
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  // Trend polarity. No dedicated success/danger token exists in qs.Commons.Color
  // (only foreground/background/accent/urgent/muted), so "up" derives from the
  // theme's accent token and "down" reuses the danger semantic (`urgent`) that
  // errors and destructive actions already use. No hardcoded hex.
  readonly property color trendUpColor: Color.accent
  readonly property color trendDownColor: urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Merged store list (state + config). One entry per store, flattened so the
  // Repeater delegates read plain fields; null sales survive as null so a
  // store that has not polled yet renders "—"/"…" instead of a false $0.
  property var stores: []
  // Selected sparkline range per store, keyed by domain. Lives on the root
  // (not the StoreCard delegate) so it survives the Repeater rebuild that every
  // state.json poll triggers.
  property var rangeByDomain: Object.create(null)

  // Global settings read from the service's state file (state.json), mirrored
  // here so the config-mode Toggle and warning banner stay file-driven.
  property bool notifyNewOrders: true
  property bool cliMissing: false
  property bool cliInstalling: false
  property string cliInstallError: ""

  // Only stores with showOnBar set appear on the bar; the panel still lists
  // every store. The service defaults a new store to shown only while fewer
  // than 3 are already shown (Service.qml addStore), but the "Show on bar"
  // toggle can push the count past 3.
  readonly property var barStores: stores.filter(function(s) { return s && s.showOnBar })

  property string mode: "overview" // overview | config
  // Set when the empty-state button is clicked so the panel opens straight
  // into config (the only thing worth doing before any store exists).
  property bool openInConfig: false
  // Which edit field to focus after a ConfigRow expands ("name" or "themeDir").
  property string focusField: "name"
  property int cursorIndex: 0
  property bool cursorActive: false

  // Index of the store row expanded inline (-1 = none). The edit fields live
  // inside each ConfigRow; their in-progress values are mirrored here (never
  // via `text:` bindings, which QQC2 TextField breaks on first keystroke) so a
  // background poll that rebuilds the store list and its delegates preserves
  // what the user is typing.
  property int expandedIndex: -1
  property string editName: ""
  property string editDomain: ""
  property string editThemeDir: ""
  property string editTheme: "live"

  // Store awaiting delete confirmation ("" = no prompt open).
  property string pendingDeleteDomain: ""

  // domain -> [{id, name, role}] fetched by the widget's own theme-list Process
  // when a ConfigRow expands; drives the Theme dropdown options.
  property var themesByDomain: Object.create(null)
  property string themesLoadingDomain: ""

  // domain -> [{epoch, label}] of pre-push backups, fetched by the widget's own
  // `ls` Process when a ConfigRow expands; drives the Restore-backup dropdown.
  property var backupsByDomain: Object.create(null)
  property string backupsLoadingDomain: ""
  // Selected backup epoch for the expanded store's Restore dropdown.
  property string restoreEpoch: ""
  // Store + epoch awaiting restore confirmation ("" = no prompt open).
  property string pendingRestoreDomain: ""
  property string pendingRestoreEpoch: ""

  // Stores discovered by the service's discoverStores() action (delivered via
  // discovered.json); clicking one autofills the add-store form.
  property var discovered: []
  property bool discovering: false

  // Discovered stores the user hasn't added yet. The discovered list would
  // otherwise re-list already-added stores (dimmed "Added" rows) on every open,
  // duplicating the config list below and — with 3+ stores — pushing the form
  // past the panel's capped height so the config list gets covered.
  readonly property var addableDiscovered: {
    var out = []
    for (var i = 0; i < discovered.length; i++) {
      var d = discovered[i]
      if (d && !isAdded(d.domain)) out.push(d)
    }
    return out
  }

  // >0 while a text field holds keyboard focus; the key catcher must stand
  // down then so typed characters reach the field, not the nav shortcuts.
  property int inputFocusCount: 0
  readonly property bool inputActive: inputFocusCount > 0

  // Drag-to-reorder state for the config store list. The Repeater model is NOT
  // mutated mid-drag; the pointer position drives a target index and the new
  // order is persisted once, on release, via the reorderStore IPC action.
  property string draggingDomain: ""
  property int dragFromIndex: -1
  property int dragDropIndex: -1
  property string dragGhostName: ""
  property string dragGhostDomain: ""
  // Ghost + drop-indicator geometry, in the Flickable's content coordinates.
  property real dragGhostY: 0
  property real dragIndicatorY: 0

  implicitWidth: barRow.implicitWidth
  implicitHeight: barRow.implicitHeight

  // ------------------------------------------------------------- actions

  function runIpc(args) {
    Quickshell.execDetached(["omarchy-shell", "-q", root.pluginId].concat(args))
  }

  function refresh() { runIpc(["refresh"]) }
  function refreshStore(domain) { runIpc(["refreshStore", String(domain || "")]) }
  function push(domain) { runIpc(["push", String(domain || "")]) }
  function pull(domain) { runIpc(["pull", String(domain || "")]) }
  function authStore(domain) { runIpc(["authStore", String(domain || "")]) }
  function startDev(domain) { runIpc(["startDev", String(domain || "")]) }
  function stopDev(domain) { runIpc(["stopDev", String(domain || "")]) }
  function reorderStore(domain, index) { runIpc(["reorderStore", String(domain || ""), String(index)]) }

  // Open the dev preview URL in the default browser.
  function openPreview(url) {
    if (url) Quickshell.execDetached(["xdg-open", String(url)])
  }

  // Opens the store's Shopify admin in the default browser. The myshopify.com
  // /admin path redirects to admin.shopify.com/store/<handle> regardless of the
  // store's handle, so the domain alone is enough.
  function openAdmin(domain) {
    if (domain) Quickshell.execDetached(["xdg-open", "https://" + String(domain) + "/admin"])
  }

  // FolderDialog.selectedFolder is a QML url (file:///... with %-encoding).
  // Convert it to a plain filesystem path: strip the file:// prefix, then
  // percent-decode (%20 → space). decodeURIComponent throws on a stray literal
  // %, so fall back to the raw string on error (matches shell idiom).
  function pathFromFolderUrl(u) {
    var s = String(u || "")
    if (s.indexOf("file://") === 0) s = s.substring(7)
    try { return decodeURIComponent(s) } catch (e) { return s }
  }

  function removeStore(domain) {
    var dm = String(domain || "")
    runIpc(["removeStore", dm])
    if (expandedIndex !== -1) {
      var s = storeAt(expandedIndex)
      if (s && s.domain === dm) collapse()
    }
  }

  // Deletion is destructive (a `pull` can clobber a local theme dir, a
  // `push` a live theme), so every removal path routes through a confirm
  // dialog instead of firing immediately.
  function requestDelete(domain) {
    pendingDeleteDomain = String(domain || "")
  }

  function confirmDelete() {
    var dm = pendingDeleteDomain
    pendingDeleteDomain = ""
    if (dm !== "") removeStore(dm)
  }

  function storeNameFor(domain) {
    for (var i = 0; i < stores.length; i++) {
      if (stores[i] && stores[i].domain === domain) return stores[i].name
    }
    return domain
  }

  function updateStore(domain, field, value) {
    runIpc(["updateStore", String(domain || ""), String(field || ""), value === undefined ? "" : value])
  }

  function addStore() {
    var nm = String(addNameInput.text || "").trim()
    var dm = String(addDomainInput.text || "").trim()
    if (nm === "" || dm === "") return
    runIpc(["addStore", nm, dm, String(addThemeDirInput.text || "").trim()])
    addNameInput.text = ""
    addDomainInput.text = ""
    addThemeDirInput.text = ""
  }

  function discoverStores() {
    if (discovering) return
    discovering = true
    runIpc(["discoverStores"])
  }

  function addDiscovered(entry) {
    var dm = String(entry && entry.domain ? entry.domain : "")
    if (dm === "") return
    runIpc(["addStore", String(entry.name || ""), dm, ""])
  }

  function isAdded(domain) {
    for (var i = 0; i < stores.length; i++) {
      if (stores[i] && String(stores[i].domain) === domain) return true
    }
    return false
  }

  // ------------------------------------------------------------- drag reorder

  // Begin a config-list drag from a row's grip handle. Only the pointer
  // position is tracked from here on; the model is left untouched until the
  // drag is released (configDragEnd). The dragged row is collapsed so every
  // row has a uniform height for the drop-slot math and the editor doesn't
  // animate while the list is being reshuffled.
  function configDragStart(domain, index) {
    var s = storeAt(index)
    draggingDomain = String(domain || "")
    dragFromIndex = index
    dragDropIndex = index
    dragGhostName = s ? String(s.name || "") : ""
    dragGhostDomain = String(domain || "")
    collapse()
  }

  // Track the pointer while dragging: float the ghost under the pointer and
  // derive the target index + drop-indicator line from the pointer's position
  // among the (uniform-height) row centers.
  function configDragMove(handle, mouseX, mouseY) {
    if (draggingDomain === "") return
    var p = handle.mapToItem(configList, mouseX, mouseY)
    var c = handle.mapToItem(column, mouseX, mouseY)
    dragGhostY = c.y - Style.space(20)

    var n = stores.length
    var idx = 0
    for (var i = 0; i < n; i++) {
      var item = configRepeater.itemAt(i)
      if (!item) continue
      if (p.y < item.mapToItem(configList, 0, item.height / 2).y) break
      idx = i + 1
    }
    // idx is the insertion boundary counting every row (the dragged one still
    // occupies its slot); removing it first shifts later boundaries up by one.
    dragDropIndex = Math.max(0, Math.min(n - 1, idx > dragFromIndex ? idx - 1 : idx))

    if (idx < n) dragIndicatorY = configRepeater.itemAt(idx).mapToItem(column, 0, 0).y - 1
    else dragIndicatorY = configRepeater.itemAt(n - 1).mapToItem(column, 0, configRepeater.itemAt(n - 1).height).y - 1
  }

  function configDragEnd() {
    var dm = draggingDomain
    var from = dragFromIndex
    var to = dragDropIndex
    draggingDomain = ""
    dragFromIndex = -1
    dragDropIndex = -1
    if (dm !== "" && to >= 0 && to !== from) reorderStore(dm, to)
  }

  // Abort without committing: the grab was interrupted, so leave the order
  // untouched and just clear the drag visuals.
  function configDragCancel() {
    draggingDomain = ""
    dragFromIndex = -1
    dragDropIndex = -1
  }

  // ------------------------------------------------------------- state

  function reloadDiscovered() {
    var d = {}
    try { d = JSON.parse(String(discoveredFile.text() || "")) } catch (e) {
      // A malformed discovered.json yields an empty list, not a crash.
    }
    discovered = (d && Array.isArray(d.stores)) ? d.stores : []
    discovering = false
  }

  function parseStores(raw) {
    var d = {}
    try { d = JSON.parse(String(raw || "")) } catch (e) {
      // A malformed config yields an empty list, not a crash.
    }
    return (d && Array.isArray(d.stores)) ? d.stores : []
  }

  function stateStoreFor(list, domain) {
    for (var i = 0; i < list.length; i++) {
      if (list[i] && String(list[i].domain) === domain) return list[i]
    }
    return null
  }

  function rebuildStores() {
    // A background poll can write state.json while a reorder drag is mid-air;
    // defer the rebuild so the dragged delegate (and its mouse grab) isn't
    // destroyed underneath the pointer. Re-run once the drag is released.
    if (draggingDomain !== "") { Qt.callLater(rebuildStores); return }
    var stateRaw = {}
    try { stateRaw = JSON.parse(String(stateFile.text() || "")) } catch (e) {}
    root.notifyNewOrders = (stateRaw && stateRaw.notifyNewOrders) !== false
    root.cliMissing = (stateRaw && stateRaw.cliMissing) === true
    root.cliInstalling = (stateRaw && stateRaw.cliInstalling) === true
    root.cliInstallError = (stateRaw && stateRaw.cliInstallError) ? String(stateRaw.cliInstallError) : ""
    var stateStores = (stateRaw && Array.isArray(stateRaw.stores)) ? stateRaw.stores : []
    var cfgStores = parseStores(configFile.text())
    var merged = []
    var seen = {}

    function push(s, c) {
      var dm = String((s && s.domain) || (c && c.domain) || "")
      if (dm === "" || seen[dm]) return
      seen[dm] = true
      s = s || {}
      c = c || {}
      merged.push({
        name: String(s.name || c.name || ""),
        domain: dm,
        currency: String(s.currency || "$"),
        themeDir: String(c.themeDir || ""),
        theme: String(c.theme || "live"),
        showOnBar: c.showOnBar !== false,
        today: s.today || null,
        yesterday: s.yesterday || null,
        yesterdaySoFar: s.yesterdaySoFar || null,
        week: s.week || null,
        biweek: s.biweek || null,
        month: s.month || null,
        allTime: s.allTime || null,
        statsToday: s.statsToday || null,
        statsYesterday: s.statsYesterday || null,
        yesterdayStatsSoFar: s.yesterdayStatsSoFar || null,
        statsWeek: s.statsWeek || null,
        statsBiweek: s.statsBiweek || null,
        statsMonth: s.statsMonth || null,
        statsAll: s.statsAll || null,
        weekSeries: Array.isArray(s.weekSeries) ? s.weekSeries : [],
        biweekSeries: Array.isArray(s.biweekSeries) ? s.biweekSeries : [],
        monthSeries: Array.isArray(s.monthSeries) ? s.monthSeries : [],
        allTimeSeries: Array.isArray(s.allTimeSeries) ? s.allTimeSeries : [],
        lastUpdated: Number(s.lastUpdated) || 0,
        lastError: s.lastError != null ? String(s.lastError) : "",
        lastSyncOutput: String(s.lastSyncOutput || ""),
        lastSyncError: String(s.lastSyncError || ""),
        syncing: s.syncing === true,
        themeSyncing: s.themeSyncing === true,
        themeAction: String(s.themeAction || ""),
        authed: s.authed === true,
        devRunning: s.devRunning === true,
        devUrl: String(s.devUrl || "")
      })
    }

    // Config order first (a just-added store shows up even before the first
    // poll writes it into state), then any state-only stores.
    for (var i = 0; i < cfgStores.length; i++) {
      var c = cfgStores[i]
      if (!c || !c.domain) continue
      push(stateStoreFor(stateStores, String(c.domain)), c)
    }
    for (var j = 0; j < stateStores.length; j++) {
      var s = stateStores[j]
      if (!s || !s.domain) continue
      push(s, null)
    }

    stores = merged
    if (cursorIndex >= stores.length) cursorIndex = Math.max(0, stores.length - 1)
    if (expandedIndex >= stores.length) collapse()
  }

  function storeAt(i) {
    return (i >= 0 && i < stores.length) ? stores[i] : null
  }

  // ------------------------------------------------------------- themes

  // Copy a null-proto domain map, set one key, and reassign (QML binds on the
  // reassignment, not the in-place mutation).
  function setByDomain(map, dm, list) {
    var next = Object.create(null)
    for (var k in map) next[k] = map[k]
    next[dm] = list
    return next
  }

  // Fetch a store's theme list (live included) into themesByDomain for the
  // ConfigRow Theme dropdown. The service owns the IPC target, but a
  // synchronous IPC return isn't possible, so the widget runs its own Process.
  function fetchThemes(domain) {
    var dm = String(domain || "")
    if (dm === "" || themeListProcess.running) return
    themesLoadingDomain = dm
    themeListProcess.command = ["shopify", "theme", "list", "--json", "--store", dm]
    themeListProcess.running = true
  }

  function handleThemeList(exitCode, stdoutText) {
    var dm = themesLoadingDomain
    themesLoadingDomain = ""
    var list = []
    if (exitCode === 0) {
      try {
        var parsed = JSON.parse(String(stdoutText || "[]"))
        if (Array.isArray(parsed)) {
          for (var i = 0; i < parsed.length; i++) {
            var t = parsed[i]
            if (!t) continue
            list.push({ id: t.id, name: String(t.name || ""), role: String(t.role || "") })
          }
        }
      } catch (e) {
        // A malformed list response yields an empty list, not a crash.
      }
    }
    themesByDomain = setByDomain(themesByDomain, dm, list)
  }

  // "Live (default)" always first, then one entry per theme with a role hint.
  function themeOptionsFor(domain) {
    var list = themesByDomain[String(domain || "")] || []
    var liveName = ""
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      if (t && String(t.role) === "live") liveName = t.name ? String(t.name) : ""
    }
    // The live theme's entry uses its real name (with a (live) hint) instead of
    // a generic "Live (default)" label; its value stays "live" (the sentinel).
    var opts = [{ value: "live", label: liveName !== "" ? liveName + "  (live)" : "Live (default)" }]
    for (var j = 0; j < list.length; j++) {
      var t2 = list[j]
      if (!t2 || String(t2.role) === "live") continue
      var label = t2.name ? String(t2.name) : String(t2.id)
      if (t2.role) label += "  (" + t2.role + ")"
      opts.push({ value: String(t2.id), label: label })
    }
    return opts
  }

  // ------------------------------------------------------------- backups

  // Fetch a store's pre-push backups into backupsByDomain for the ConfigRow
  // Restore dropdown. Runs the widget's own `ls` Process (same pattern as
  // fetchThemes); the dir is `ls -1`-ed and each epoch dir name becomes one
  // option with a readable label.
  function fetchBackups(domain) {
    var dm = String(domain || "")
    if (dm === "" || backupListProcess.running) return
    backupsLoadingDomain = dm
    backupListProcess.command = ["ls", "-1", root.backupsDir + "/" + dm]
    backupListProcess.running = true
  }

  function handleBackupList(exitCode, stdoutText) {
    var dm = backupsLoadingDomain
    backupsLoadingDomain = ""
    var list = []
    if (exitCode === 0) {
      var lines = String(stdoutText || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var ep = lines[i].trim()
        if (!/^\d+$/.test(ep)) continue
        list.push({ epoch: ep, label: M.formatEpoch(Number(ep)) })
      }
      list.sort(function(a, b) { return Number(b.epoch) - Number(a.epoch) })
    }
    backupsByDomain = setByDomain(backupsByDomain, dm, list)
    restoreEpoch = list.length > 0 ? list[0].epoch : ""
  }

  function backupsFor(domain) {
    return backupsByDomain[String(domain || "")] || []
  }

  function backupOptionsFor(domain) {
    var list = backupsFor(domain)
    var opts = []
    for (var i = 0; i < list.length; i++) {
      opts.push({ value: list[i].epoch, label: list[i].label })
    }
    return opts
  }

  function restoreLabelFor(domain, epoch) {
    var list = backupsFor(domain)
    for (var i = 0; i < list.length; i++) {
      if (list[i].epoch === epoch) return list[i].label
    }
    return epoch
  }

  function requestRestore(domain, epoch) {
    pendingRestoreDomain = String(domain || "")
    pendingRestoreEpoch = String(epoch || "")
  }

  function confirmRestore() {
    var dm = pendingRestoreDomain
    var ep = pendingRestoreEpoch
    pendingRestoreDomain = ""
    pendingRestoreEpoch = ""
    if (dm !== "" && ep !== "") runIpc(["restoreBackup", dm, ep])
  }

  // ------------------------------------------------------------- display

  function todaySales(s) {
    var t = s && s.today
    return (t && t.sales != null) ? Number(t.sales) : null
  }

  function yesterdaySoFarSales(s) {
    var y = s && s.yesterdaySoFar
    return (y && y.sales != null) ? Number(y.sales) : null
  }

  function todayOrders(s) {
    var t = s && s.today
    return (t && t.orders != null) ? Number(t.orders) : null
  }

  // Trend vs yesterday. Null when there is nothing to compare against (no
  // yesterday figure, or yesterday was zero), which renders no indicator.
  function trend(s) {
    var t = todaySales(s)
    var y = yesterdaySoFarSales(s)
    if (t == null || y == null) return null
    if (y === 0) return t > 0 ? { glyph: "▲", up: true } : null
    if (t > y) return { glyph: "▲", up: true }
    if (t < y) return { glyph: "▼", up: false }
    return null
  }

  function trendPctText(s) {
    var t = todaySales(s)
    var y = yesterdaySoFarSales(s)
    if (t == null || y == null || y === 0) return ""
    var pct = (t - y) / y * 100
    return (pct >= 0 ? "+" : "") + pct.toFixed(1) + "%"
  }

  function todayMoney(s) {
    var t = todaySales(s)
    return t == null ? "—" : M.formatMoney(t, s.currency)
  }

  // Formats a rate field off a range-selected stats object. Stats objects are
  // null when the range has no data, so `s ? s[field] : null` guards the read.
  function pct(s, field) { return M.formatPercent(s ? s[field] : null) }

  function heroSummaryText() {
    var total = null
    var count = 0
    var currency = null
    var mixed = false
    for (var i = 0; i < stores.length; i++) {
      var s = stores[i]
      var v = todaySales(s)
      if (v != null) {
        var cur = (s && s.currency) ? String(s.currency) : null
        if (currency === null) currency = cur
        else if (currency !== cur) mixed = true
        total = (total == null ? 0 : total) + v; count++
      }
    }
    if (total == null) return "Today: —"
    var amount = mixed ? M.formatCount(total) : M.formatMoney(total, currency)
    return "Today: " + amount + " across " + (count === 1 ? "1 store" : count + " stores")
  }

  function timeAgo(at) {
    var t = Number(at)
    if (!t) return "never"
    var s = Math.floor((Date.now() - t) / 1000)
    if (s < 60) return "just now"
    if (s < 3600) return Math.floor(s / 60) + "m ago"
    if (s < 86400) return Math.floor(s / 3600) + "h ago"
    return Math.floor(s / 86400) + "d ago"
  }

  function barTooltip(s) {
    var parts = []
    if (s.name) parts.push(s.name)
    if (s.domain) parts.push(s.domain)
    if (s.lastError) parts.push(s.lastError)
    else if (s.syncing) parts.push("󰓦 syncing")
    else parts.push("updated " + timeAgo(s.lastUpdated))
    return parts.join(" — ")
  }

  // ------------------------------------------------------------- keyboard

  function setCursor(i) {
    cursorActive = true
    cursorIndex = Math.max(0, Math.min(stores.length - 1, i))
  }

  // Track how many text fields hold focus so the key catcher can step aside
  // while the user types. When the last field blurs, hand focus back to the
  // key catcher so arrow keys keep driving the store cursor.
  function inputFocusChanged(focused) {
    inputFocusCount = focused ? inputFocusCount + 1 : Math.max(0, inputFocusCount - 1)
    if (!focused && inputFocusCount === 0) {
      Qt.callLater(function() {
        if (keyCatcher && !root.inputActive && root.opened) keyCatcher.forceActiveFocus()
      })
    }
  }

  function moveCursor(dy) {
    if (stores.length === 0) { cursorActive = false; return }
    setCursor(cursorIndex + dy)
    scrollCursorIntoView()
  }

  function selectedDomain() {
    var s = storeAt(cursorIndex)
    return s ? s.domain : ""
  }

  function activateCursor() {
    if (!cursorActive) return
    if (mode === "config") toggleExpand(cursorIndex)
    else {
      var s = stores[cursorIndex]
      if (s) refreshStore(s.domain)
    }
  }

  function toggleExpand(i) {
    if (expandedIndex === i) {
      expandedIndex = -1
      return
    }
    // Seed the edit mirrors BEFORE flipping expandedIndex: the ConfigRow's
    // onExpandedChanged → seedFields() fires the instant `row.expanded` goes
    // true (driven by expandedIndex), so it must already see the new values.
    var s = storeAt(i)
    editName = s ? String(s.name || "") : ""
    editDomain = s ? String(s.domain || "") : ""
    editThemeDir = s ? String(s.themeDir || "") : ""
    editTheme = s ? String(s.theme || "live") : "live"
    expandedIndex = i
    Qt.callLater(scrollCursorIntoView)
  }

  // Jump straight to a store's edit form and focus its theme directory field,
  // so a "no theme directory" hint is actionable in one click.
  function jumpToThemeDir(domain) {
    for (var i = 0; i < stores.length; i++) {
      if (stores[i] && stores[i].domain === domain) {
        mode = "config"
        focusField = "themeDir"
        collapse()
        setCursor(i)
        toggleExpand(i)
        return
      }
    }
  }

  function collapse() {
    expandedIndex = -1
    restoreEpoch = ""
  }

  function toggleMode() {
    mode = (mode === "overview") ? "config" : "overview"
    cursorActive = false
    collapse()
    if (flick) flick.contentY = 0
  }

  function scrollCursorIntoView() {
    var repeater = (mode === "config") ? configRepeater : storeRepeater
    var item = repeater ? repeater.itemAt(cursorIndex) : null
    if (!item || !flick) return
    Qt.callLater(function() {
      if (!item || !flick) return
      var margin = Style.space(6)
      var point = item.mapToItem(flick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = flick.contentY
      var viewBottom = viewTop + flick.height
      var maxY = Math.max(0, flick.contentHeight - flick.height)
      var targetY = null
      if (top < viewTop + margin) targetY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) targetY = Math.min(maxY, bottom + margin - flick.height)
      if (targetY !== null) {
        scrollAnim.stop()
        scrollAnim.from = flick.contentY
        scrollAnim.to = targetY
        scrollAnim.start()
      }
    })
  }

  NumberAnimation {
    id: scrollAnim
    target: flick
    property: "contentY"
    duration: 200
    easing.type: Easing.OutCubic
  }

  // ------------------------------------------------------------- files

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onLoaded: root.rebuildStores()
    onLoadFailed: root.rebuildStores()
    onFileChanged: reload()
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.rebuildStores()
    onLoadFailed: root.rebuildStores()
    onFileChanged: reload()
  }

  FileView {
    id: discoveredFile
    path: root.discoveredPath
    watchChanges: true
    printErrors: false
    onLoaded: root.reloadDiscovered()
    onLoadFailed: root.reloadDiscovered()
    onFileChanged: reload()
  }

  // Fetches a store's theme list on demand (ConfigRow expand). One Process is
  // enough: only one row can be expanded at a time.
  Process {
    id: themeListProcess
    command: []
    stdout: StdioCollector { id: themeListStdout; waitForEnd: true }
    stderr: StdioCollector { id: themeListStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.handleThemeList(exitCode, themeListStdout.text)
    }
  }

  // Fetches a store's pre-push backup list on demand (ConfigRow expand).
  Process {
    id: backupListProcess
    command: []
    stdout: StdioCollector { id: backupListStdout; waitForEnd: true }
    stderr: StdioCollector { id: backupListStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.handleBackupList(exitCode, backupListStdout.text)
    }
  }

  onOpenedChanged: {
    if (opened) {
      mode = openInConfig ? "config" : "overview"
      openInConfig = false
      cursorActive = false
      inputFocusCount = 0
      collapse()
      rebuildStores()
      Qt.callLater(function() {
        if (flick) flick.contentY = 0
        if (keyCatcher) keyCatcher.forceActiveFocus()
      })
    }
  }

  // ------------------------------------------------------------- bar

  Row {
    id: barRow
    spacing: Style.space(2)

    // With no stores there is nothing to show and no per-store button to open
    // the panel with — so keep a placeholder button that drops straight into
    // the add-store form. Hidden once the first store exists.
    WidgetButton {
      id: emptyButton
      visible: root.barStores.length === 0
      bar: root.bar
      text: "󰒚"
      labelVisible: true
      hasVisualContent: true
      horizontalMargin: Style.space(6)
      tooltipText: "Shop — no stores yet. Click to add one."
      onPressed: function(b) {
        if (b === Qt.LeftButton) { root.openInConfig = true; root.toggle() }
      }
    }

    Repeater {
      model: root.barStores

      delegate: StoreBarButton {
        required property var modelData

        bar: root.bar
        store: modelData
        dimmed: modelData.lastError !== ""
        tooltipText: root.barTooltip(modelData)

        onPressed: function(b) {
          if (b === Qt.RightButton) root.refreshStore(modelData.domain)
          else if (b === Qt.MiddleButton) root.toggleMode()
          else root.toggle()
        }
      }
    }
  }

  // Popup anchor: right-aligned to the barRow (the shop's bar widget is
  // right-aligned, so its right edge is a stable screen x), but with the
  // WIDTH capped at one full button (~220). Without the cap, centering under
  // the whole barRow makes the card drift left as store buttons are added;
  // without right-alignment it lands at the far screen edge. The cap keeps the
  // card under the shop for a few stores and holds it right-of-center for many.
  Item {
    id: anchorStub
    anchors.right: barRow.right
    anchors.verticalCenter: barRow.verticalCenter
    width: Math.min(barRow.width, Style.space(220))
    height: 1
  }

  // ------------------------------------------------------------- popup

  KeyboardPanel {
    id: popup
    anchorItem: anchorStub
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(440))
    contentHeight: popup.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.inputActive || root.pendingDeleteDomain !== "" || root.pendingRestoreDomain !== ""

      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onDeleteRequested: {
        if (root.cursorActive && root.mode === "config") {
          var dm = root.selectedDomain()
          if (dm !== "") root.requestDelete(dm)
        }
      }
      onTabRequested: root.toggleMode
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "c" || t === "C") root.toggleMode()
        else if ((t === "p" || t === "P") && root.cursorActive) root.push(root.selectedDomain())
        else if ((t === "u" || t === "U") && root.cursorActive) root.pull(root.selectedDomain())
        else if ((t === "a" || t === "A") && root.cursorActive) root.authStore(root.selectedDomain())
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }

        Column {
          id: column
          // Reserve the right gutter the vertical scrollbar overlays (QQC2
          // Basic: 6px thumb + 2px padding per side) so the scrollbar covers
          // empty space instead of the form fields and store cards.
          width: flick.width - Style.space(10)
          spacing: Style.space(14)

          // Warning banner: shown when the service's last sales poll could not
          // find the `shopify` CLI. Sits above the hero so it reads regardless
          // of which panel mode is active.
          BorderSurface {
            id: cliWarning
            visible: root.cliMissing
            width: parent.width
            radius: Style.cornerRadius
            color: Util.alpha(root.urgent, 0.08)
            borderSpec: Border.flat(root.urgent, 1)
            implicitHeight: cliWarningRow.implicitHeight + Style.space(16)

            Row {
              id: cliWarningRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(8)

              Text {
                id: cliWarningGlyph
                anchors.verticalCenter: parent.verticalCenter
                text: "󰀨"
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - cliWarningGlyph.width
                       - (installButton.visible ? installButton.width + parent.spacing * 2 : parent.spacing)
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: root.cliInstalling ? "Installing Shopify CLI…" : "Shopify CLI not found"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }

                Text {
                  visible: root.cliInstallError !== ""
                  width: parent.width
                  text: root.cliInstallError
                  color: root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              Button {
                id: installButton
                visible: root.cliMissing && !root.cliInstalling
                enabled: !root.cliInstalling
                text: "Install"
                foreground: root.foreground
                bordered: true
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.runIpc(["installCli"])
              }
            }
          }

          PanelHero {
            width: parent.width
            title: "Shop"
            meta: root.mode === "overview" ? "Sales overview" : "Store management"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "󰒚"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              Row {
                spacing: Style.space(8)
                Button {
                  text: "Refresh"
                  iconText: "󰓦"
                  foreground: root.foreground
                  tooltipText: "Refresh sales for every store (r)"
                  onClicked: root.refresh()
                }
                Button {
                  text: root.mode === "overview" ? "Configure" : "Back"
                  iconText: root.mode === "overview" ? "󰒓" : "󰁍"
                  foreground: root.foreground
                  tooltipText: root.mode === "overview" ? "Manage stores (c)" : "Back to stores"
                  onClicked: root.toggleMode()
                }
              }
            }
          }

          Text {
            id: heroSummary
            visible: root.mode === "overview"
            width: parent.width
            text: root.heroSummaryText()
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
            elide: Text.ElideRight
          }

          PanelSeparator { foreground: root.foreground }

          // ---------------- overview: per-store detail ----------------

          PanelSectionHeader {
            visible: root.mode === "overview"
            text: "󰓜  STORES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: root.mode === "overview" && root.stores.length === 0
            width: parent.width
            text: "No stores yet\nOpen Configure to add one."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Column {
            id: storesColumn
            visible: root.mode === "overview"
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              id: storeRepeater
              model: root.stores

              delegate: StoreCard {
                required property var modelData
                required property int index
                width: storesColumn.width
                store: modelData
                rowIndex: index
              }
            }
          }

          // ---------------- config: store management ----------------

          Column {
            id: configSection
            visible: root.mode === "config"
            width: parent.width
            spacing: Style.space(8)

            Toggle {
              width: parent.width
              checked: root.notifyNewOrders
              label: "New-order notifications"
              description: "Show a desktop notification when a store gets a new order"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.runIpc(["setNotifyNewOrders", root.notifyNewOrders ? "false" : "true"])
            }

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "󰐕  ADD STORE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Field {
              id: addNameInput
              label: "Name"
              placeholder: "My Store"
              onFieldFocusChanged: (focused) => root.inputFocusChanged(focused)
            }
            Field {
              id: addDomainInput
              label: "Domain"
              placeholder: "my-store.myshopify.com"
              onFieldFocusChanged: (focused) => root.inputFocusChanged(focused)
            }
            Field {
              id: addThemeDirInput
              label: "Theme directory (optional)"
              placeholder: "/path/to/theme"
              onFieldFocusChanged: (focused) => root.inputFocusChanged(focused)
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                text: "Add store"
                iconText: "󰐕"
                foreground: root.foreground
                bordered: true
                onClicked: root.addStore()
              }

              Button {
                text: "Discover stores"
                iconText: "󰍉"
                foreground: root.foreground
                bordered: true
                tooltipText: "Find stores you can access via the Shopify CLI"
                onClicked: root.discoverStores()
              }
            }

            Column {
              id: discoveredList
              width: parent.width
              spacing: Style.space(4)
              visible: root.discovering || root.addableDiscovered.length > 0

              Text {
                visible: root.discovering
                width: parent.width
                text: "󰓦 Discovering stores…"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Repeater {
                model: root.addableDiscovered
                delegate: DiscoveredRow {
                  required property var modelData
                  width: discoveredList.width
                  store: modelData
                }
              }
            }

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "󰓜  STORES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: root.stores.length > 1
              width: parent.width
              text: "Drag 󰇙 to reorder"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              visible: root.stores.length === 0
              width: parent.width
              text: "No stores configured"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Column {
              id: configList
              visible: root.stores.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                id: configRepeater
                model: root.stores

                delegate: ConfigRow {
                  required property var modelData
                  required property int index
                  width: configList.width
                  store: modelData
                  rowIndex: index
                }
              }
            }
          }
        }

        // Drag ghost: a lightweight replica of the dragged store header that
        // floats under the pointer while a reorder drag is in flight. Sibling of
        // `column`, so its coordinates live in the same (content) space and it
        // draws above every row. It never touches the Repeater model.
        BorderSurface {
          id: dragGhost
          visible: root.draggingDomain !== ""
          z: 100
          width: configList.width
          height: Style.space(40)
          x: 0
          y: root.dragGhostY
          radius: Style.cornerRadius
          color: Style.selectedFillFor(root.foreground, Color.accent)
          borderSpec: Border.controlSpec("selected", root.foreground, Color.accent)
          opacity: 0.92

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            Text {
              id: ghostGrip
              anchors.verticalCenter: parent.verticalCenter
              text: "󰇙"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconSmall
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - ghostGrip.width - parent.spacing
              spacing: Style.space(1)

              Text {
                width: parent.width
                text: root.dragGhostName
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: root.dragGhostDomain
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }
        }

        // Drop indicator: a 2px accent line marking the insertion boundary the
        // dragged store will land at on release.
        Rectangle {
          id: dropIndicator
          visible: root.draggingDomain !== ""
          z: 99
          width: configList.width
          height: 2
          x: 0
          y: root.dragIndicatorY
          radius: 1
          color: Color.accent
        }
      }

      ConfirmDialog {
        id: deleteDialog
        anchors.fill: parent
        opened: root.pendingDeleteDomain !== ""
        message: "Remove store " + (root.pendingDeleteDomain !== "" ? root.storeNameFor(root.pendingDeleteDomain) : "") + "?"
        confirmText: "Remove"
        foreground: root.foreground
        fontFamily: root.fontFamily
        Keys.onPressed: function(event) { event.accepted = deleteDialog.handleKey(event) }
        onOpenedChanged: {
          if (opened) {
            selectedIndex = 0
            forceActiveFocus()
          } else {
            keyCatcher.forceActiveFocus()
          }
        }
        onCanceled: root.pendingDeleteDomain = ""
        onConfirmed: root.confirmDelete()
      }

      ConfirmDialog {
        id: restoreDialog
        anchors.fill: parent
        opened: root.pendingRestoreDomain !== ""
        message: root.pendingRestoreDomain !== ""
          ? ("Restore the backup from " + root.restoreLabelFor(root.pendingRestoreDomain, root.pendingRestoreEpoch)
             + "?\nThis overwrites the live theme of " + root.storeNameFor(root.pendingRestoreDomain) + ".")
          : ""
        confirmText: "Restore"
        foreground: root.foreground
        fontFamily: root.fontFamily
        Keys.onPressed: function(event) { event.accepted = restoreDialog.handleKey(event) }
        onOpenedChanged: {
          if (opened) {
            selectedIndex = 0
            forceActiveFocus()
          } else {
            keyCatcher.forceActiveFocus()
          }
        }
        onCanceled: {
          root.pendingRestoreDomain = ""
          root.pendingRestoreEpoch = ""
        }
        onConfirmed: root.confirmRestore()
      }

    }
  }

  // ------------------------------------------------------------- components

  // Per-store bar button. Mirrors WidgetButton's click/tooltip contract
  // (registerClickTarget + triggerPress + tooltipHovered) so the bar's
  // click-forwarding and tooltip machinery keeps working, but paints a richer
  // label: dim store name · bold today amount · trend glyph.
  component StoreBarButton: Item {
    id: btn
    property var bar: null
    property var store: null
    property string fontFamily: bar ? bar.fontFamily : Style.font.family
    property color foreground: bar ? bar.barForeground : Color.foreground
    property color dim: Qt.darker(foreground, 1.5)
    property bool interactive: true
    property bool pressable: true
    property bool concealed: false
    property bool dimmed: false
    property string tooltipText: ""
    property real horizontalMargin: Style.space(6)
    property real verticalPadding: Style.space(6)

    signal pressed(int button)

    readonly property bool vertical: bar ? bar.vertical : false
    readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
    readonly property bool tooltipHovered: visible && interactive && !concealed && mouseArea.containsMouse
    readonly property var trendInfo: root.trend(store)

    // Cap the whole bar button so a long store name (or a large amount) can't
    // widen the bar widget past a normal slot. The name elides into whatever
    // width the fixed glyphs (icon · amount trend) leave over; the amount and
    // trend always keep their natural width so the figure stays readable.
    // Shrink each button dynamically as the store count grows: the total budget
    // is a third of the bar width, so any number of stores fits without the row
    // overflowing horizontally. Below ~120px a button collapses to icon+amount.
    readonly property real maxButtonWidth: {
      var barW = (btn.bar && btn.bar.width) ? btn.bar.width : 0
      var budget = barW > 0 ? barW * 0.33 : Style.space(500)
      return Math.max(Style.space(70), Math.min(Style.space(220), budget / Math.max(1, root.barStores.length)))
    }
    readonly property bool compact: !vertical && maxButtonWidth < Style.space(120)
    readonly property real maxNameWidth: {
      if (vertical) return Style.space(120)
      var fixed = iconText.width + dotText.width + moneyText.width
                + (trendText.visible ? trendText.width : 0)
                + contentRow.spacing * 4
      return Math.max(0, maxButtonWidth - horizontalMargin * 2 - fixed)
    }

    visible: store !== null
    opacity: dimmed ? 0.45 : 1
    implicitWidth: vertical ? barSize : Math.min(maxButtonWidth, Math.max(12, contentRow.implicitWidth + horizontalMargin * 2))
    implicitHeight: vertical ? Math.max(12, contentRow.implicitHeight + verticalPadding * 2) : barSize

    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    property var registeredBar: null

    function triggerPress(button) {
      if (btn.bar) btn.bar.hideTooltip(btn)
      btn.pressed(button)
    }

    function hideOwnTooltip() {
      if (btn.bar) btn.bar.hideTooltip(btn)
    }

    function syncClickRegistration() {
      if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(btn)
      registeredBar = btn.bar
      if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(btn)
    }

    onBarChanged: syncClickRegistration()
    onVisibleChanged: if (!visible) hideOwnTooltip()
    onInteractiveChanged: if (!interactive) hideOwnTooltip()
    onConcealedChanged: if (concealed) hideOwnTooltip()
    Component.onCompleted: syncClickRegistration()
    Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(btn)

    Row {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.space(3)

      Text {
        id: iconText
        anchors.verticalCenter: parent.verticalCenter
        visible: btn.store !== null
        text: "󰒚"
        color: btn.foreground
        font.family: btn.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        id: nameText
        anchors.verticalCenter: parent.verticalCenter
        visible: btn.store !== null && !btn.compact
        width: Math.min(implicitWidth, btn.maxNameWidth)
        text: btn.store ? btn.store.name : ""
        color: btn.dim
        font.family: btn.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        id: dotText
        anchors.verticalCenter: parent.verticalCenter
        text: (btn.store && btn.store.name && !btn.compact) ? "·" : ""
        color: btn.dim
        font.family: btn.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        id: moneyText
        anchors.verticalCenter: parent.verticalCenter
        text: root.todayMoney(btn.store)
        color: btn.foreground
        font.family: btn.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        id: trendText
        anchors.verticalCenter: parent.verticalCenter
        visible: !btn.compact && btn.trendInfo !== null
        text: btn.trendInfo ? btn.trendInfo.glyph : ""
        color: btn.trendInfo && btn.trendInfo.up ? root.trendUpColor : root.trendDownColor
        font.family: btn.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      enabled: btn.interactive
      hoverEnabled: true
      cursorShape: btn.pressable ? Qt.PointingHandCursor : Qt.ArrowCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onEntered: if (btn.bar) btn.bar.showTooltip(btn, btn.tooltipText)
      onExited: if (btn.bar) btn.bar.hideTooltip(btn)
      onClicked: function(mouse) { if (btn.pressable) btn.triggerPress(mouse.button) }
    }
  }

  component Field: Column {
    id: self
    property string label: ""
    property string placeholder: ""
    property alias text: input.text
    signal fieldFocusChanged(bool focused)
    signal fieldTextChanged(string text)
    function focusInput() { input.forceActiveFocus() }
    width: parent.width
    spacing: Style.spacing.sm

    Text {
      width: parent.width
      text: self.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    TextField {
      id: input
      width: parent.width
      placeholderText: self.placeholder
      foreground: root.foreground
      font.family: root.fontFamily
      onActiveFocusChanged: self.fieldFocusChanged(activeFocus)
      onTextChanged: self.fieldTextChanged(text)
      Keys.onEscapePressed: focus = false
    }
  }

  // A dim label over a bold value — the store card's KPI stat cell. `trend`
  // carries an optional {up} from StoreCard's same-time-of-day comparison;
  // when set, a ▲/▼ glyph renders next to the value.
  component StatCell: Column {
    property string label: ""
    property string value: ""
    property var trend: null
    spacing: Style.space(1)
    Text {
      width: parent.width
      text: label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
    Row {
      width: parent.width
      spacing: Style.space(3)
      Text {
        width: Math.max(0, parent.width - (trendText.visible ? trendText.implicitWidth + parent.spacing : 0))
        text: value
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        id: trendText
        anchors.verticalCenter: parent.verticalCenter
        visible: trend !== null
        text: trend ? (trend.up ? "▲" : "▼") : ""
        color: trend && trend.up ? root.trendUpColor : root.trendDownColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
    }
  }

  component StoreCard: BorderSurface {
    id: card
    property var store: null
    property int rowIndex: 0
    property color foreground: root.foreground

    readonly property string domain: store ? store.domain : ""
    readonly property bool canSync: store ? store.themeDir !== "" : false
    readonly property bool busy: store ? store.syncing : false
    readonly property bool themeBusy: store ? (store.themeSyncing === true) : false
    function themeBusyText() {
      return (store && store.themeAction === "pull") ? "pulling theme" : "pushing theme"
    }
    // `authed` starts false and flips true on the first successful poll, so any
    // store that has not yet authenticated shows the Authenticate action.
    readonly property bool needsAuth: store ? !store.authed : false
    readonly property bool devRunning: store ? (store.devRunning === true) : false
    readonly property string devUrl: store ? String(store.devUrl || "") : ""
    readonly property bool devEnabled: card.devRunning || (card.canSync && !card.themeBusy)
    readonly property bool hasCursor: root.cursorActive && root.mode === "overview" && root.cursorIndex === rowIndex
    readonly property var trendInfo: root.trend(store)
    // Range selector index. The range* constants are the single source of
    // truth for this index; four parallel arrays consume it at different
    // offsets:
    //   rangeSales  -> [today, yesterday, week, biweek, month, allTime]       (offset 0)
    //   rangeStats  -> [statsToday, statsYesterday, statsWeek, statsBiweek, statsMonth, statsAll]
    //   series      -> [weekSeries, biweekSeries, monthSeries, allTimeSeries] (offset rangeWeek)
    //   rangeLabels -> ["Today", ...]                                         (offset 0)
    readonly property int rangeToday: 0
    readonly property int rangeYesterday: 1
    readonly property int rangeWeek: 2
    readonly property int rangeBiweek: 3
    readonly property int rangeMonth: 4
    readonly property int rangeAll: 5
    property int range: rangeWeek
    // Restore the user's last-selected range. Delegates are rebuilt on every
    // state poll, so a per-card `range` would otherwise reset to 7d.
    Component.onCompleted: {
      var r = root.rangeByDomain[store.domain]
      if (typeof r === "number") range = r
    }
    readonly property var rangeLabels: ["Today", "Yesterday", "7d", "14d", "30d", "All"]
    // Sparkline series for the selected range. Single-day ranges (Today/
    // Yesterday) have no timeseries, so they yield an empty array (the
    // sparkline hides); rangeWeek..rangeAll map onto the week/biweek/month/
    // all-time series.
    readonly property var series: {
      if (!store || range < rangeWeek) return []
      var a = [store.weekSeries, store.biweekSeries, store.monthSeries, store.allTimeSeries]
      return (a[range - rangeWeek] || [])
    }
    readonly property string todayCaption: {
      var o = root.todayOrders(store)
      return o != null ? ("Today · " + M.formatCount(o) + " orders") : "Today"
    }
    // Bar currently under the pointer in the sparkline (-1 = none).
    property int hoveredSpark: -1
    function sparkTipText() {
      if (hoveredSpark < 0 || hoveredSpark >= series.length) return ""
      var d = series[hoveredSpark]
      if (!d) return ""
      var label = String(d.day || "")
      var day = range === rangeAll ? label.slice(0, 7) : label.slice(5)
      return day + " · " + M.formatMoney(d.sales, store ? String(store.currency || "$") : "$")
    }
    // Highest single-day sales across the current range; bars scale against it.
    readonly property real sparkMax: {
      var m = 0
      for (var i = 0; i < series.length; i++) {
        var v = Number(series[i] && series[i].sales)
        if (!isNaN(v) && v > m) m = v
      }
      return m
    }
    // Even-width bar so the bars tile the card without a half-pixel seam.
    readonly property real sparkBarWidth: {
      var n = series.length
      if (n === 0) return Style.space(4)
      var w = Math.floor((body.width - (n - 1) * Style.space(2)) / n)
      if (w % 2 !== 0) w -= 1
      return Math.max(2, w)
    }
    // Uniform width for the four KPI stat cells in each row (four columns
    // with three Style.space(10) gutters).
    readonly property real statWidth: (body.width - Style.space(10) * 3) / 4

    // The {sales, orders} pair for the selected range. Today reads the
    // real-time orders figure; Yesterday reads the full-calendar-day ShopifyQL
    // aggregate; 7d/14d/30d/All read the ShopifyQL aggregates.
    function rangeSales(s) {
      if (!s) return null
      var a = [s.today, s.yesterday, s.week, s.biweek, s.month, s.allTime]
      return a[range] || null
    }

    // The sessions stats object for the selected range. Every range (Today
    // included) reads its own stats object; they share one shape.
    function rangeStats(s) {
      if (!s) return null
      var a = [s.statsToday, s.statsYesterday, s.statsWeek, s.statsBiweek, s.statsMonth, s.statsAll]
      return a[range] || null
    }

    // Individual KPI values for the stat-cell grid, ordered most-important
    // first. AOV is computed from sales ÷ orders since the sessions schema has
    // no average-order-value column. Each reads `range`, so the StatCell
    // bindings below re-evaluate whenever the range selector changes.
    function salesValue() { var r = rangeSales(store); return r ? M.formatMoney(r.sales, store.currency) : "—" }
    function ordersValue() { var r = rangeSales(store); return r ? M.formatCount(r.orders) : "—" }
    function aovValue() {
      var r = rangeSales(store)
      return (r && r.orders) ? M.formatMoney(r.sales / r.orders, store.currency) : "—"
    }
    function cvrValue() { return root.pct(rangeStats(store), "cvr") }
    function visitorsValue() { var s = rangeStats(store); return M.formatCount(s ? s.visitors : null) }
    function checkoutValue() { return root.pct(rangeStats(store), "checkoutCvr") }
    function atcValue() { return root.pct(rangeStats(store), "atc") }
    function bounceValue() { return root.pct(rangeStats(store), "bounce") }

    // Same-time-of-day comparison for a single KPI. Returns {up} when both
    // sides are present numbers and differ, else null (no glyph).
    function sameTimeTrend(same, base) {
      if (same == null || base == null) return null
      var a = Number(same)
      var b = Number(base)
      if (isNaN(a) || isNaN(b) || a === b) return null
      return { up: a > b }
    }
    // Trend objects for the 8 KPI cells, gated to the Today range (the only
    // range with a same-time-of-day baseline). Sales/Orders/AOV compare against
    // the real-time yesterdaySoFar query; the sessions stats compare against
    // yesterdayStatsSoFar (the local ~24h snapshot; null until snapshots accumulate).
    function salesTrend() {
      if (range !== rangeToday || !store) return null
      return sameTimeTrend(store.today && store.today.sales, store.yesterdaySoFar && store.yesterdaySoFar.sales)
    }
    function ordersTrend() {
      if (range !== rangeToday || !store) return null
      return sameTimeTrend(store.today && store.today.orders, store.yesterdaySoFar && store.yesterdaySoFar.orders)
    }
    function aovTrend() {
      if (range !== rangeToday || !store) return null
      var t = store.today, y = store.yesterdaySoFar
      var todayAov = (t && t.orders) ? (t.sales / t.orders) : null
      var yestAov = (y && y.orders) ? (y.sales / y.orders) : null
      return sameTimeTrend(todayAov, yestAov)
    }
    function cvrTrend() { return statsTodayTrend("cvr") }
    function visitorsTrend() { return statsTodayTrend("visitors") }
    function bounceTrend() { return statsTodayTrend("bounce") }
    function atcTrend() { return statsTodayTrend("atc") }
    function checkoutTrend() { return statsTodayTrend("checkoutCvr") }
    function statsTodayTrend(field) {
      if (range !== rangeToday || !store) return null
      return sameTimeTrend(store.statsToday ? store.statsToday[field] : null, store.yesterdayStatsSoFar ? store.yesterdayStatsSoFar[field] : null)
    }

    function sparkBarHeight(day) {
      var v = Number(day && day.sales)
      if (isNaN(v) || v <= 0 || sparkMax <= 0) return 2
      return Math.max(2, (v / sparkMax) * Style.space(28))
    }

    function sparkBarColor(day) {
      var v = Number(day && day.sales)
      return (!isNaN(v) && v > 0) ? Color.accent : root.dim
    }

    radius: Style.cornerRadius
    color: hasCursor
      ? Style.hoverFillFor(foreground, Color.accent)
      : Style.normalFillFor(foreground, Color.accent)
    borderSpec: hasCursor
      ? Border.controlSpec("hover-cursor", foreground, Color.accent)
      : Border.controlSpec("normal", foreground, Color.accent)
    Behavior on color { ColorAnimation { duration: 60 } }

    implicitHeight: body.implicitHeight + Style.space(24)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor(rowIndex)
      onClicked: root.refreshStore(card.domain)
    }

    Column {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(14)
      anchors.rightMargin: Style.space(14)
      spacing: Style.space(6)

      // Header: dim store name (with domain under it) on the left, today's
      // sales as a large number with a "Today" caption and trend line on the
      // right. The number is the primary datum, so it dominates the row.
      Row {
        width: parent.width
        spacing: Style.space(8)

        Column {
          id: headerLeft
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(0, parent.width - headerRight.width - parent.spacing)
          spacing: Style.space(1)

          Text {
            id: nameText
            width: parent.width
            text: card.store ? card.store.name : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            text: card.domain + (card.needsAuth ? "  󰌆" : "")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            opacity: 0.7
            elide: Text.ElideRight
            visible: card.domain !== ""
          }
        }

        Column {
          id: headerRight
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(todayCaptionText.implicitWidth, todayNumberText.implicitWidth, trendText.implicitWidth)

          Text {
            id: todayCaptionText
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: card.todayCaption
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            id: todayNumberText
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: root.todayMoney(card.store)
            color: card.store && card.store.lastError !== "" ? root.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
          }

          Text {
            id: trendText
            width: parent.width
            horizontalAlignment: Text.AlignRight
            visible: card.trendInfo !== null
            text: {
              if (!card.trendInfo) return ""
              var pct = root.trendPctText(card.store)
              return pct === "" ? card.trendInfo.glyph : (card.trendInfo.glyph + " " + pct + " vs yesterday")
            }
            color: card.trendInfo && card.trendInfo.up ? root.trendUpColor : root.trendDownColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }

      Row {
        id: rangeSelector
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: card.rangeLabels
          delegate: Button {
            required property var modelData
            required property int index
            text: String(modelData)
            selected: card.range === index
            foreground: card.range === index ? Color.accent : root.dim
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(3)
            onClicked: {
              card.range = index
              if (card.store) root.rangeByDomain[card.store.domain] = index
            }
          }
        }
      }

      Item {
        id: sparkline
        width: parent.width
        height: Style.space(28)
        clip: true
        visible: card.series.length > 0

        Row {
          anchors.fill: parent
          spacing: Style.space(2)

          Repeater {
            model: card.series
            delegate: Rectangle {
              required property var modelData
              anchors.bottom: parent.bottom
              width: card.sparkBarWidth
              height: card.sparkBarHeight(modelData)
              color: card.sparkBarColor(modelData)
              radius: Style.space(1)
            }
          }
        }

        // Hover tooltip: shows the hovered day + its sales.
        Rectangle {
          id: sparkTip
          visible: card.hoveredSpark >= 0 && card.sparkTipText() !== ""
          y: Style.space(1)
          height: Style.space(20)
          radius: Style.cornerRadius
          color: Color.background
          border.width: 1
          border.color: root.dim
          width: sparkTipText.implicitWidth + Style.space(8)
          x: {
            var pitch = card.sparkBarWidth + Style.space(2)
            var cx = card.hoveredSpark * pitch + pitch / 2
            return Math.min(Math.max(0, cx - width / 2), sparkline.width - width)
          }
          Text {
            id: sparkTipText
            anchors.centerIn: parent
            text: card.sparkTipText()
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onPositionChanged: function(mouse) {
            var pitch = card.sparkBarWidth + Style.space(2)
            card.hoveredSpark = (pitch > 0)
              ? Math.min(Math.floor(mouse.x / pitch), card.series.length - 1)
              : -1
          }
          onExited: card.hoveredSpark = -1
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(6)

        Row {
          width: parent.width
          spacing: Style.space(10)
          StatCell { width: card.statWidth; label: "Sales"; value: card.salesValue(); trend: card.salesTrend() }
          StatCell { width: card.statWidth; label: "Orders"; value: card.ordersValue(); trend: card.ordersTrend() }
          StatCell { width: card.statWidth; label: "AOV"; value: card.aovValue(); trend: card.aovTrend() }
          StatCell { width: card.statWidth; label: "CVR"; value: card.cvrValue(); trend: card.cvrTrend() }
        }

        Row {
          width: parent.width
          spacing: Style.space(10)
          StatCell { width: card.statWidth; label: "Visitors"; value: card.visitorsValue(); trend: card.visitorsTrend() }
          StatCell { width: card.statWidth; label: "Checkout CVR"; value: card.checkoutValue(); trend: card.checkoutTrend() }
          StatCell { width: card.statWidth; label: "ATC"; value: card.atcValue(); trend: card.atcTrend() }
          StatCell { width: card.statWidth; label: "Bounce"; value: card.bounceValue(); trend: card.bounceTrend() }
        }
      }

      Text {
        width: parent.width
        text: card.themeBusy
          ? ("󰓦 " + card.themeBusyText())
          : (card.busy ? "󰓦 syncing" : "updated " + root.timeAgo(card.store ? card.store.lastUpdated : 0))
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        visible: card.store && card.store.lastError !== ""
        text: card.store
          ? (root.cliInstalling ? "󰀨 Installing Shopify CLI…" : "󰀨 " + card.store.lastError)
          : ""
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        visible: card.store && card.store.lastSyncError !== ""
        text: card.store ? ("󰀨 " + card.store.lastSyncError) : ""
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: card.store && card.store.lastSyncOutput !== ""
        text: card.store ? card.store.lastSyncOutput : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
      }

      PanelSeparator { foreground: root.foreground; strength: 0.08 }

      // Theme actions (Push/Pull/Dev) grouped; the "Set theme directory" button
      // stands in for the whole group when no local theme dir is configured.
      Row {
        width: parent.width
        spacing: Style.space(6)

        Button {
          text: "Push"
          iconText: "󰕒"
          foreground: root.foreground
          visible: card.canSync
          opacity: card.themeBusy ? 0.4 : 1.0
          tooltipText: card.themeBusy ? ("󰓦 " + card.themeBusyText()) : "Push theme to " + card.domain
          onClicked: if (!card.themeBusy) root.push(card.domain)
        }

        Button {
          text: "Pull"
          iconText: "󰇚"
          foreground: root.foreground
          visible: card.canSync
          opacity: card.themeBusy ? 0.4 : 1.0
          tooltipText: card.themeBusy ? ("󰓦 " + card.themeBusyText()) : "Pull theme from " + card.domain
          onClicked: if (!card.themeBusy) root.pull(card.domain)
        }

        Button {
          text: card.devRunning ? "Stop" : "Dev"
          foreground: root.foreground
          visible: card.canSync
          opacity: card.devEnabled ? 1.0 : 0.4
          tooltipText: card.devRunning ? "Stop live preview for " + card.domain : "Start live preview for " + card.domain
          onClicked: {
            if (card.devRunning) root.stopDev(card.domain)
            else if (card.devEnabled) root.startDev(card.domain)
          }
        }

        Button {
          text: "Open preview"
          iconText: "󰏌"
          foreground: root.foreground
          visible: card.devRunning && card.devUrl !== ""
          tooltipText: card.devUrl !== "" ? ("Open preview: " + card.devUrl) : "Open preview"
          onClicked: root.openPreview(card.devUrl)
        }

        Button {
          text: "Set theme directory"
          iconText: "󰉋"
          foreground: root.foreground
          bordered: true
          visible: !card.canSync
          tooltipText: "Choose the local theme folder for " + card.domain
          onClicked: root.jumpToThemeDir(card.domain)
        }
      }

      PanelSeparator { foreground: root.foreground; strength: 0.06 }

      // Store actions (admin + auth) grouped separately from theme actions.
      Row {
        width: parent.width
        spacing: Style.space(6)

        Button {
          text: "Open admin"
          iconText: "󰏌"
          foreground: root.foreground
          tooltipText: "Open " + card.domain + " in the Shopify admin"
          onClicked: root.openAdmin(card.domain)
        }

        Button {
          text: "Authenticate"
          iconText: "󰌆"
          foreground: root.foreground
          visible: card.needsAuth
          tooltipText: "Open Shopify auth for " + card.domain
          onClicked: root.authStore(card.domain)
        }
      }
    }
  }

  component ConfigRow: CursorSurface {
    id: row
    property var store: null
    property int rowIndex: 0

    readonly property bool expanded: root.expandedIndex === rowIndex
    readonly property bool needsAuth: row.store ? !row.store.authed : false
    // True while this row is the one being drag-reordered; drives the lift/dim
    // visual and the grip highlight. Matched by domain so the state survives
    // the delegate staying alive while the model order is left untouched.
    readonly property bool dragging: root.draggingDomain !== "" && root.draggingDomain === (row.store ? String(row.store.domain) : "")

    hasCursor: root.cursorActive && root.mode === "config" && root.cursorIndex === rowIndex
    current: row.expanded
    foreground: root.foreground
    radius: Style.cornerRadius
    implicitHeight: header.height + editor.height
    opacity: row.dragging ? 0.45 : 1
    scale: row.dragging ? 1.02 : 1
    z: row.dragging ? 10 : 0
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    // Seed the inline fields from the root mirror each time the row expands or
    // its delegate is recreated; persist any changed fields back over IPC.
    // Domain is sent last so the name/themeDir updates still address the store
    // by its current domain.
    function seedFields() {
      nameInput.text = root.editName
      domainInput.text = root.editDomain
      themeDirInput.text = root.editThemeDir
    }

    function save() {
      var s = row.store
      if (!s) return
      var nm = String(root.editName || "").trim()
      var dm = String(root.editDomain || "").trim()
      var td = String(root.editThemeDir || "")
      var th = String(root.editTheme || "live")
      if (nm !== "" && nm !== String(s.name || "")) root.updateStore(s.domain, "name", nm)
      if (td !== String(s.themeDir || "")) root.updateStore(s.domain, "themeDir", td)
      if (th !== String(s.theme || "live")) root.updateStore(s.domain, "theme", th)
      if (dm !== "" && dm !== String(s.domain || "")) root.updateStore(s.domain, "domain", dm)
      root.collapse()
    }

    Component.onCompleted: if (row.expanded) seedFields()
    onExpandedChanged: if (expanded) {
      seedFields()
      root.fetchThemes(row.store ? String(row.store.domain || "") : "")
      if (row.store && String(row.store.themeDir || "") !== "") {
        root.fetchBackups(String(row.store.domain || ""))
      }
      focusTimer.restart()
    }

    Timer {
      id: focusTimer
      interval: 180
      repeat: false
      onTriggered: {
        if (!row.expanded) return
        if (root.focusField === "themeDir") {
          themeDirInput.focusInput()
          root.focusField = "name"
        } else {
          nameInput.focusInput()
        }
        root.scrollCursorIntoView()
      }
    }

    Column {
      id: content
      width: parent.width

      Item {
        id: header
        width: parent.width
        height: Style.space(40)

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.setCursor(rowIndex)
          onClicked: root.toggleExpand(rowIndex)
        }

        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(6)
          spacing: Style.space(8)

          MouseArea {
            id: dragHandle
            width: Style.space(22)
            height: parent.height
            anchors.verticalCenter: parent.verticalCenter
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            // Keep the grip's press out of the Flickable's scroll gesture: a
            // drag on the handle reorders, a drag elsewhere scrolls the list.
            preventStealing: true
            cursorShape: Qt.PointingHandCursor

            property bool dragging: false
            property real pressY: 0

            onEntered: root.setCursor(rowIndex)
            onPressed: function(mouse) { dragging = false; pressY = mouse.y }
            onPositionChanged: function(mouse) {
              if (!(mouse.buttons & Qt.LeftButton)) return
              if (!dragging) {
                if (Math.abs(mouse.y - pressY) < Style.space(4)) return
                dragging = true
                root.configDragStart(row.store ? String(row.store.domain) : "", rowIndex)
              }
              root.configDragMove(dragHandle, mouse.x, mouse.y)
            }
            onReleased: function(mouse) {
              if (dragging) { dragging = false; root.configDragEnd() }
            }
            onCanceled: function() {
              if (dragging) { dragging = false; root.configDragCancel() }
            }

            Text {
              anchors.centerIn: parent
              text: "󰇙"
              color: row.dragging ? Color.accent : (dragHandle.containsMouse ? root.foreground : root.dim)
              font.family: root.fontFamily
              font.pixelSize: Style.font.icon
            }
          }

          Column {
            width: parent.width - dragHandle.width - editBtn.width - removeBtn.width - parent.spacing * 3
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            Text {
              width: parent.width
              text: row.store ? row.store.name : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: row.store ? row.store.domain : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          PanelActionButton {
            id: editBtn
            anchors.verticalCenter: parent.verticalCenter
            iconText: row.expanded ? "󰅃" : "󰅀"
            tooltipText: row.expanded ? "Collapse" : "Edit " + (row.store ? row.store.name : "")
            foreground: root.dim
            hoverColor: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.toggleExpand(row.rowIndex)
          }

          PanelActionButton {
            id: removeBtn
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰆴"
            tooltipText: "Remove " + (row.store ? row.store.name : "")
            foreground: root.dim
            hoverColor: root.urgent
            fontFamily: root.fontFamily
            onClicked: {
              var dm = row.store ? row.store.domain : ""
              if (dm !== "") root.requestDelete(dm)
            }
          }
        }
      }

      Column {
        id: editor
        width: parent.width
        spacing: Style.space(6)
        topPadding: Style.space(2)
        bottomPadding: Style.space(10)
        clip: true
        enabled: row.expanded
        // Height jumps to the final value instantly so the ConfigRow
        // implicitHeight → content column → Flickable/KeyboardPanel
        // contentHeight chain settles at the FULL expanded size on the first
        // layout pass (an animated height under-reports mid-transition and
        // after a mid-animation delegate rebuild, permanently shrinking the
        // card and disabling scrolling). The expand still feels smooth via the
        // opacity fade below.
        height: row.expanded ? implicitHeight : 0
        opacity: row.expanded ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Field {
          id: nameInput
          label: "Name"
          placeholder: "My Store"
          onFieldFocusChanged: (focused) => root.inputFocusChanged(focused)
          onFieldTextChanged: (text) => root.editName = text
        }
        Field {
          id: domainInput
          label: "Domain"
          placeholder: "my-store.myshopify.com"
          onFieldFocusChanged: (focused) => root.inputFocusChanged(focused)
          onFieldTextChanged: (text) => root.editDomain = text
        }
        Row {
          width: parent.width
          spacing: Style.space(6)

          Field {
            id: themeDirInput
            width: parent.width - browseBtn.width - parent.spacing
            label: "Theme directory"
            placeholder: "/path/to/theme"
            onFieldFocusChanged: (focused) => root.inputFocusChanged(focused)
            onFieldTextChanged: (text) => root.editThemeDir = text
          }
          Button {
            id: browseBtn
            text: "Browse"
            iconText: "󰉋"
            foreground: root.foreground
            bordered: true
            anchors.bottom: parent.bottom
            tooltipText: "Choose a theme folder"
            onClicked: folderDialog.open()
          }
        }

        Dropdown {
          id: themeDropdown
          width: parent.width
          label: "Theme"
          foreground: root.foreground
          fontFamily: root.fontFamily
          options: root.themeOptionsFor(row.store ? String(row.store.domain || "") : "")
          value: root.editTheme
          onChanged: function(v) { root.editTheme = v }
        }

        Toggle {
          width: parent.width
          checked: row.store ? row.store.showOnBar : false
          label: "Show on bar"
          description: "Show this store's sales on the bar"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: {
            var s = row.store
            if (s) root.updateStore(String(s.domain), "showOnBar", s.showOnBar ? "false" : "true")
          }
        }

        // Restore a pre-push backup over the live theme. Only shown when the
        // store has a theme directory and at least one backup exists.
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: row.store && String(row.store.themeDir || "") !== ""
            && root.backupsFor(row.store ? String(row.store.domain || "") : "").length > 0

          PanelSeparator { foreground: root.foreground; strength: 0.06 }

          Text {
            width: parent.width
            text: "Restore backup"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            Dropdown {
              id: backupDropdown
              width: parent.width - restoreBtn.width - parent.spacing
              showLabel: false
              foreground: root.foreground
              fontFamily: root.fontFamily
              options: root.backupOptionsFor(row.store ? String(row.store.domain || "") : "")
              value: root.restoreEpoch
              onChanged: function(v) { root.restoreEpoch = v }
            }

            Button {
              id: restoreBtn
              text: "Restore"
              iconText: "󰘓"
              foreground: root.foreground
              bordered: true
              anchors.bottom: parent.bottom
              tooltipText: "Push this backup to the live theme for " + (row.store ? String(row.store.domain) : "")
              onClicked: {
                var dm = row.store ? String(row.store.domain || "") : ""
                if (dm !== "" && root.restoreEpoch !== "") root.requestRestore(dm, root.restoreEpoch)
              }
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(6)

          Button {
            text: "Save"
            iconText: "󰆓"
            foreground: root.foreground
            bordered: true
            onClicked: row.save()
          }
          Button {
            text: "Authenticate"
            iconText: "󰌆"
            foreground: root.foreground
            visible: row.needsAuth
            tooltipText: "Open Shopify auth for " + (row.store ? row.store.domain : "")
            onClicked: root.authStore(row.store ? row.store.domain : "")
          }
        }
      }
    }

    FolderDialog {
      id: folderDialog
      title: "Select theme directory"
      onAccepted: {
        var path = root.pathFromFolderUrl(selectedFolder)
        themeDirInput.text = path
        root.editThemeDir = path
      }
    }
  }

  // A store the service discovered; clicking adds it directly (themeDir set later).
  component DiscoveredRow: Rectangle {
    id: row
    property var store: null
    readonly property bool added: root.isAdded(store ? String(store.domain) : "")
    width: parent.width
    height: Style.space(40)
    radius: Style.cornerRadius
    opacity: row.added ? 0.45 : 1.0
    color: rowMouse.containsMouse && !row.added ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: !row.added
      cursorShape: row.added ? Qt.ArrowCursor : Qt.PointingHandCursor
      onClicked: if (!row.added) root.addDiscovered(row.store)
    }

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Column {
        width: parent.width - pickGlyph.implicitWidth - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: row.store ? row.store.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: row.store ? row.store.domain : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        id: pickGlyph
        anchors.verticalCenter: parent.verticalCenter
        text: row.added ? "Added" : "󰐕"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: row.added ? Style.font.bodySmall : Style.font.icon
      }
    }
  }
}
