import QtQuick
import QtTest
import Quickshell
import "../../ui" as Shop
import "../../js/keymap.mjs" as Keymap
import "../../js/sales.mjs" as Sales
import "../../js/snapshot.mjs" as Snapshot
import "../../js/themes.mjs" as Themes

// What the panel_*_smoke.qml files share: the real ui/ShopPanel in a window
// against the shell's qs.Ui / qs.Commons, driven by a stand-in service whose
// snapshot has the shape the real Service publishes (Snapshot.buildSnapshot)
// and is swapped per step; plus the scene builders and the probes the
// checks read. Each smoke publishes its own start state.
Scope {
  id: harness

  readonly property string acme: "acme.myshopify.com"
  readonly property string beta: "beta.myshopify.com"
  readonly property string gamma: "gamma.myshopify.com"
  readonly property var brokenConfig: ({ code: "config_invalid", message: "unexpected end of input" })
  readonly property var cliMissing: ({ status: "missing", missing: "cli", installs: "~/.local/share/mise/installs", error: null })
  readonly property var backupRow: ({ id: "1762500001-160258293983", at: 1762500001000, theme: { id: "160258293983", name: "Dawn", role: "live" }, before: "push", files: 12, bytes: 4096 })
  readonly property var folderCopyRow: ({ id: "1762500002", at: 1762500002000, path: "/state/acme/1762500002", files: 12, bytes: 4096 })

  property alias panel: panel
  property alias service: fakeService
  property alias window: win
  // The window's focus item.
  readonly property var focused: probe.focused
  // How often a view asked the host for a folder (the folder dialog).
  property int folderAsks: 0

  // The stand-in service: the properties the panel binds and the methods
  // the views call while loading or on the keys the smokes press.
  QtObject {
    id: fakeService
    // Empty until the first publish (the panel treats {} as nothing loaded).
    property var snapshot: ({})
    property var storeOrder: []
    property var calls: []
    function note(what) { fakeService.calls = fakeService.calls.concat([what]) }
    function storeViewOpened(domain) { fakeService.note("storeViewOpened " + domain) }
    function listBackups(domain) { fakeService.note("listBackups " + domain); return { ok: true } }
    function refreshHistory(domain) { fakeService.note("refreshHistory " + domain); return { ok: true } }
    function discoverStores() { fakeService.note("discoverStores"); return { ok: true } }
    function grantSalesAccess(domain) { fakeService.note("grantSalesAccess " + domain); return { ok: true } }
    function listThemes(domain) { fakeService.note("listThemes " + domain); return { ok: true } }
    function inspectFolder(domain) { fakeService.note("inspectFolder " + domain); return { ok: true } }
    function updateStore(domain, json) { fakeService.note("updateStore " + domain + " " + json); return { ok: true } }
    function updateSettings(json) { fakeService.note("updateSettings " + json); return { ok: true } }
    function signIn() { fakeService.note("signIn"); return { ok: true } }
    function stopPreview(domain) { fakeService.note("stopPreview " + domain); return { ok: true } }
    function pullTheme(domain) { fakeService.note("pullTheme " + domain); return { ok: true } }
    function resetConfig() { fakeService.note("resetConfig"); return { ok: true } }
    function refresh() { fakeService.note("refresh"); return { ok: true } }
    function setDialogOpen(ownerKey, open) {}
    // The capped helper read behind every LineEdit paste.
    property var clipboard: ({ ok: true, text: "~/pasted folder" })
    function readClipboard(done) { fakeService.note("readClipboard"); done(fakeService.clipboard) }
  }

  FloatingWindow {
    id: win
    implicitWidth: 440
    // A small-screen fold: BarWidget caps the panel at Style.space(680),
    // clamped to the screen; this one scrolls sooner.
    implicitHeight: 560
    visible: true

    Shop.ShopPanel {
      id: panel
      width: win.width
      height: win.height
      service: fakeService
      opened: true
      ownerKey: "smoke"
      onChooseFolderRequested: (domain) => harness.folderAsks++
    }

    // Real key events, delivered to the focus window (this one).
    TestEvent { id: keyEvents }

    Item {
      id: probe
      readonly property var focused: Window.activeFocusItem
    }
  }

  // ----- scenes -----

  function cfgStore(domain, label, folder) {
    return { domain: domain, label: label, showInBar: true, theme: { folder: folder || "", target: "live", allowLive: false } }
  }

  // Acme linked to /work/acme, the store most scenes are about.
  function acmeLinked() { return harness.cfgStore(harness.acme, "Acme", "/work/acme") }

  // A store that has today's figures (the period switch shows).
  function figuresState() {
    var st = Sales.emptyRecord()
    st.currency = "USD"
    st.salesAccess = "granted"
    st.sales.status = "ok"
    st.sales.fetchedAt = { today: Date.now(), traffic: 0, history: 0 }
    st.sales.today = { sales: 60.01, orders: 3, truncated: false, latestOrder: null, traffic: null, trafficHourly: null, baseline: null }
    return st
  }

  // A store still waiting for sales access (no figures, no period switch).
  function accessState() {
    var st = Sales.emptyRecord()
    st.salesAccess = "required"
    return st
  }

  // A map keyed by Acme's domain, as the scenes' per-store maps are.
  function forAcme(value) {
    var out = {}
    out[harness.acme] = value
    return out
  }

  function salesOf(st) { return harness.forAcme(st) }

  function infoOf(themes, backups) {
    var info = Themes.emptyThemeState()
    if (themes) info.themes = themes
    if (backups) info.backups = backups
    return harness.forAcme(info)
  }

  // A scene: { stores (config entries), salesState, infoState, jobState,
  // previewState (maps keyed by domain), configError, cli, account,
  // discovery, themesBusy, granting } -> the snapshot the real Service
  // would publish for it.
  function snap(o) {
    return Snapshot.buildSnapshot({
      configError: o.configError || null,
      cli: o.cli || { status: "ready", missing: null, error: null },
      account: o.account || { status: "signed_in", error: null },
      alertTools: { notify: null, sound: null },
      settings: { pollSeconds: 60, alerts: { notify: false, sound: false }, bar: { display: "stores" } },
      discovery: o.discovery || null,
      themesBusy: o.themesBusy || "",
      granting: o.granting === true,
      stores: harness.storeParts(o)
    }, null).snapshot
  }

  // The per-store parts the real Service hands buildSnapshot.
  function storeParts(o) {
    var by = function(map, d) { return map && map[d] ? map[d] : null }
    return (o.stores || []).map(function(cfg) {
      var d = cfg.domain
      return { cfg: cfg, sales: by(o.salesState, d), info: by(o.infoState, d), job: by(o.jobState, d), preview: by(o.previewState, d) }
    })
  }

  function publish(o) {
    fakeService.snapshot = harness.snap(o)
    fakeService.storeOrder = (o.stores || []).map(function(s) { return s.domain })
  }

  // Acme linked, with figures, plus whatever `o` adds.
  function publishAcme(o) {
    harness.publish(Object.assign({ stores: [harness.acmeLinked()], salesState: harness.salesOf(harness.figuresState()) }, o || {}))
  }

  // config.json unreadable: no stores, plus whatever `o` adds.
  function publishBroken(o) {
    harness.publish(Object.assign({ stores: [], configError: harness.brokenConfig }, o || {}))
  }

  // Acme (folder /work/acme) with an inspection of that folder.
  function publishFolderState(fields) {
    var info = harness.infoOf(null, null)
    info[harness.acme].folder = Themes.reduceFolder("/work/acme", Object.assign({ ok: true }, fields))
    harness.publishAcme({ infoState: info })
  }

  // A job that ended without success, as ThemeJobs keeps it: stopped
  // (terminated) unless `fields` names another error. writeStarted is the
  // helper's own word (true | false), or null when no line came (a killed
  // helper: HelperProcess synthesizes the error).
  function ended(action, fields) {
    var r = { ok: false, action: action, at: Date.now(), error: { code: "terminated", message: "stopped" }, details: [], backupId: null, folderCopy: null, writeStarted: null }
    for (var k in fields) r[k] = fields[k]
    return harness.forAcme({ job: null, lastResult: r })
  }

  function publishEnded(action, fields) {
    harness.publishAcme({ jobState: harness.ended(action, fields) })
  }

  // ----- probes -----

  function t(key, vars) { return Shop.Copy.t(key, vars) }
  function errorOf(error) { return Shop.Copy.errorOf(error) }
  function emptySales() { return Sales.emptyRecord() }

  // The key sheet's rows of a group ("view" by default): their keys, and
  // the text of the row with `key`.
  function sheetRows(group) {
    var sheet = panel.keySheetItem
    return group === "navigate" ? sheet.navigateRows : (group === "panel" ? sheet.panelRows : sheet.viewRows)
  }
  function sheetKeys(group) {
    return harness.sheetRows(group).map(function(r) { return String(r[0]) })
  }
  function sheetText(key, group) {
    var rows = harness.sheetRows(group)
    for (var i = 0; i < rows.length; i++) if (String(rows[i][0]) === key) return String(rows[i][1])
    return ""
  }

  // The footer as the Copy keys of its pieces: the view's footer rows
  // (js/keymap.mjs footerRows, by short label), then hints.broken while
  // config.json is unreadable, then hints.back above the bottom of the view
  // stack. The words are tests/js/test_keymap.mjs's to check; here the
  // footer must be the view's keymap for the scene, rendered with the
  // panel's own state.
  function footerKeys() {
    var out = Keymap.footerRows(panel.keymap).map(function(r) { return r.short })
    if (panel.configInvalid) out.push("hints.broken")
    if (panel.viewStack.length > 1) out.push("hints.back")
    return out
  }
  function footerIs(want) {
    var expected = want.slice()
    if (panel.viewStack.length > 1) expected.push("hints.back")
    var got = harness.footerKeys()
    var rendered = Keymap.footerText(panel.keymap, { broken: panel.configInvalid, canGoBack: panel.viewStack.length > 1 })
    return got.join(",") === expected.join(",") && panel.footerText === rendered
  }
  function footerHas(key) { return harness.footerKeys().indexOf(key) >= 0 }

  // How many stand-in service calls start with `prefix`.
  function callsNamed(prefix) {
    return fakeService.calls.filter(function(c) { return c.indexOf(prefix) === 0 }).length
  }
  function callsSince(n) { return fakeService.calls.slice(n) }

  // A visible item under `item` whose text is `text`.
  function findText(item, text) {
    if (!item) return null
    if (item.visible !== false && typeof item.text === "string" && item.text === text) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) {
      var hit = harness.findText(kids[i], text)
      if (hit) return hit
    }
    return null
  }

  // Visible items under `item` whose text is `text` (a Button counts once,
  // not again for its inner label).
  function countVisibleText(item, text) {
    if (!item || item.visible === false) return 0
    if (item.text === text) return 1
    var n = 0
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) n += harness.countVisibleText(kids[i], text)
    return n
  }

  // A QQuickTextInput (TextInput, TextField, a SpinBox's editor) under item:
  // the native text entry whose paste reads the clipboard unbounded.
  function findNativeTextInput(item) {
    if (!item) return null
    if (item.hasOwnProperty("echoMode") || String(item).indexOf("QQuickTextInput") === 0) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) {
      var hit = harness.findNativeTextInput(kids[i])
      if (hit) return hit
    }
    return null
  }

  function isTextInput(i) {
    return !!i && typeof i.cursorPosition === "number" && typeof i.selectAll === "function"
  }

  function focusedText() {
    return probe.focused ? probe.focused.text : "no focus"
  }

  // A real key press and release.
  function key(k, modifiers) {
    keyEvents.keyClick(k, modifiers || Qt.NoModifier, -1)
  }

  // The store card's result line is the Copy text for `key`.
  function resultIs(key, vars) {
    return panel.view.resultShown && panel.view.card.resultLine === harness.t(key, vars)
  }
  function themeMayHaveChanged() {
    return { mayHaveChanged: harness.t("result.mayHaveChanged.theme", { theme: harness.t("theme.liveTheme") }) }
  }
}
