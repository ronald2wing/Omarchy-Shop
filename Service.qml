pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "model"
import "js/config.mjs" as Config
import "js/errors.mjs" as Errors
import "js/snapshot.mjs" as Snapshot
import "js/text.mjs" as TextUtil

// Shop's headless service: the API the bar widget calls, the IpcHandler,
// and the composition of model/*. It publishes one immutable `snapshot`
// (at most every 250 ms). The IpcHandler carries only reads, refreshes,
// non-destructive actions, cancels and request* methods: every push, pull,
// restore, install, sign-out, removal and config change is a QML-only
// method reachable from this plugin's own widget, and a request only opens
// the panel's confirmation dialog.
//
// A service gets no `settings`; tunables live in ~/.config/shop/config.json.
Item {
  id: root

  // Injected by the shell's ensureService (only manifest is used).
  property var manifest: null
  // Tests inject Consent's clock (a function returning ms).
  property alias consentClock: consent.clock

  readonly property string home: Quickshell.env("HOME")
  // manifest.json is the one place the version lives.
  readonly property string version: root.manifest && root.manifest.version ? String(root.manifest.version) : ""

  // The published snapshot (shape documented in CONTRIBUTING). A new
  // object on every publish, with per-store objects reused when nothing
  // about that store changed; never mutate it.
  readonly property var snapshot: internal.snapshot
  // Valid store domains in display order; reassigned only when it changes.
  readonly property var storeOrder: internal.storeOrder

  // ---- reads -------------------------------------------------------------

  // The last published snapshot (at most 250 ms old), never a fresh build.
  function status() {
    return Snapshot.statusSummary(internal.lastBuild.snapshot, root.version)
  }

  // ---- refresh -----------------------------------------------------------

  function refresh() {
    if (internal.throttled("")) return Errors.rateLimitedLocally()
    if (!stateDir.ready) stateDir.prepare()
    account.check()
    scheduler.refresh(configStore.domains(), false)
    internal.publish()
    return Errors.started()
  }

  function refreshStore(domain) {
    return internal.withStore(domain, s => {
      if (internal.throttled(s.domain)) return Errors.rateLimitedLocally()
      scheduler.refresh([s.domain], true)
      internal.publish()
      return Errors.started()
    })
  }

  // One history fetch now: Home calls it by itself when the chosen period
  // has no figures for a store (never on IPC: a script could make a store
  // fetch its whole history on a loop).
  function refreshHistory(domain) {
    return internal.withStore(domain, s => {
      const refused = preflight.requireCli() || scheduler.refreshHistory(s.domain)
      if (refused) return refused
      internal.publish()
      return Errors.started()
    })
  }

  // ---- stores (config; QML-only) ------------------------------------------

  function addStore(domain, label) {
    const r = configStore.mutate(c => Config.addStore(c, String(domain || ""), label, discovery.result.stores))
    if (!r.ok) return { ok: false, error: r.error }
    return { ok: true, domain: r.domain, showInBar: r.showInBar, shownCount: r.shownCount }
  }

  // label, showInBar and theme (theme.folder, theme.target,
  // theme.allowLive, or null to unlink).
  function updateStore(domain, patchJson) {
    const p = Config.parsePatch(patchJson)
    if (p.error) return { ok: false, error: p.error }
    const before = configStore.store(domain)
    const r = configStore.mutate(c => {
      const next = Config.applyStorePatch(c, String(domain || ""), p.value, root.home, { allowThemeKeys: true })
      // A new folder or target under a running job, preview or grant would
      // leave it working on the old one (a preview with no Stop button, a
      // pull writing into a folder the store no longer names): refused
      // like removeStore, before anything is written. A label or showInBar
      // change never waits.
      if (next.error) return next
      if (Config.sameThemeLink(before.theme, Config.findStore(next.config, before.domain).theme)) return next
      const busy = preflight.requireStoreIdle(before)
      return busy ? { config: c, error: busy.error } : next
    })
    if (!r.ok) return { ok: false, error: r.error }
    // A folder change is re-inspected by configUpdated (the one owner); a
    // first theme link fetches the themes list once.
    const after = configStore.store(domain)
    if (p.value.theme !== undefined && after.theme && account.cli.status === "ready") themeInfo.listThemesIfStale(after.domain, Infinity)
    return Errors.ok()
  }

  function moveStore(domain, index) {
    return internal.withStore(domain, s => internal.okOrError(configStore.mutate(c => Config.moveStore(c, s.domain, index))))
  }

  function updateSettings(patchJson) {
    const p = Config.parsePatch(patchJson)
    if (p.error) return { ok: false, error: p.error }
    return internal.okOrError(configStore.mutate(c => Config.applySettingsPatch(c, p.value)))
  }

  function removeStore(domain) {
    return internal.withStore(domain, s => {
      // Removing stops the store's helpers: never mid push, pull, restore,
      // preview or grant (the result would be thrown away and the dialog
      // says nothing is touched).
      const busy = preflight.requireStoreIdle(s)
      if (busy) return busy
      // A written removal forgets the store (configUpdated); a refused one
      // (config_busy, config_unavailable) keeps everything.
      return internal.okOrError(configStore.mutate(c => Config.removeStore(c, s.domain)))
    })
  }

  // Settings' "Reset config" (behind the panel's Dialog): keeps the old
  // file as config.json.old and starts from an empty v2 config, which
  // forgets every store and so stops its helpers (Preflight.requireResetIdle;
  // the dialog says theme folders and Shopify access aren't touched). While
  // config.json is unreadable the snapshot has no stores, so the panel
  // pre-checks the top-level `themesBusy`/`granting` instead.
  function resetConfig() {
    return preflight.requireResetIdle() || configStore.resetConfig()
  }

  function dismissConfigWriteError() {
    configStore.dismissWriteError()
  }

  // ---- sales access ------------------------------------------------------

  // origin "ipc": a script asked. The grant runs (it is the browser's own
  // consent flow), but its verified shop name never relabels the store:
  // config writes stay panel-only, except requestAddStore's dialog.
  function grantSalesAccess(domain, origin) {
    return internal.withStore(domain, s => {
      const cli = preflight.requireCli()
      if (cli) return cli
      const r = salesAccess.grant(s.domain, origin)
      if (r.ok) internal.publish()
      return r
    })
  }

  function cancelSalesAccess(domain) {
    return internal.withStore(domain, s => {
      salesAccess.cancel(s.domain)
      internal.publish()
      return Errors.ok()
    })
  }

  // ---- account and CLI ---------------------------------------------------

  function discoverStores() {
    const cli = preflight.requireCli()
    if (cli) return cli
    if (!discovery.discover()) return Errors.accountBusy()
    return Errors.started()
  }

  // Sign-in and sign-out rewrite the CLI's account session store, so they
  // wait for running theme work (Preflight.requireThemesIdle). A discovery
  // started under the old session is cancelled: its account report would
  // otherwise land after the change and undo it.
  function signIn() {
    const refused = preflight.requireCli() || preflight.requireThemesIdle()
    if (refused) return refused
    const res = account.signIn()
    if (res.ok) discovery.cancel()
    return res
  }

  function cancelSignIn() {
    return account.cancelSignIn()
  }

  function signOut() {
    const refused = preflight.requireCli() || preflight.requireThemesIdle()
    if (refused) return refused
    const res = account.signOut()
    if (res.ok) discovery.cancel()
    return res
  }

  function installCli() {
    return account.installCli()
  }

  function cancelInstall() {
    return account.cancelInstall()
  }

  // ---- theme (non-destructive) -------------------------------------------

  function cancelThemeJob(domain) {
    return internal.withStore(domain, s => {
      themeJobs.cancelJob(s.domain)
      return Errors.ok()
    })
  }

  // opts.autoOpen: the panel's Preview button opens the browser on the first
  // ready; without opts (IPC) nothing opens.
  function startPreview(domain, opts) {
    const s = configStore.store(domain)
    const refused = preflight.checkPreview(s)
    if (refused) return refused
    previews.start(s.domain, s.theme.folder, !!(opts && opts.autoOpen === true))
    return Errors.started()
  }

  function stopPreview(domain) {
    return internal.withStore(domain, s => {
      previews.stop(s.domain)
      return Errors.ok()
    })
  }

  function listThemes(domain) {
    return internal.withStore(domain, s => {
      const cli = preflight.requireCli()
      if (cli) return cli
      themeInfo.listThemes(s.domain)
      return Errors.started()
    })
  }

  function listBackups(domain) {
    return internal.withStore(domain, s => {
      themeInfo.listBackups(s.domain)
      return Errors.started()
    })
  }

  function inspectFolder(domain) {
    return internal.withStore(domain, s => {
      if (!s.theme || !s.theme.folder) return Errors.noThemeFolder()
      themeInfo.inspectFolder(s.domain, s.theme.folder)
      return Errors.started()
    })
  }

  function dismissThemeResult(domain) {
    return internal.withStore(domain, s => {
      themeJobs.dismiss(s.domain)
      return Errors.ok()
    })
  }

  // ---- confirmation requests (IPC-safe: they only open the dialog) -------

  // Each request runs the preflight of the action it confirms (model/
  // Preflight.qml). Only the IpcHandler calls them: the panel runs actions
  // through its own Dialog.
  function requestPush(domain) {
    const s = configStore.store(domain)
    const refused = preflight.checkPush(s)
    if (refused) return refused
    return internal.request({ action: "push", domain: s.domain, live: themeInfo.target(s.domain, s.theme).live })
  }

  function requestPull(domain) {
    const s = configStore.store(domain)
    const refused = preflight.checkPull(s)
    if (refused) return refused
    return internal.request({ action: "pull", domain: s.domain })
  }

  function requestRestore(domain, backupId) {
    const s = configStore.store(domain)
    const refused = preflight.checkRestore(s, backupId)
    if (refused) return refused
    const id = String(backupId)
    return internal.request({ action: "restore", domain: s.domain, backupId: id, live: themeInfo.restoreIsLive(s.domain, id) })
  }

  function requestInstallCli() {
    const r = preflight.requireCli()
    if (!r) return Errors.ok()
    return r.error.code === "cli_missing" ? internal.request({ action: "installCli" }) : r
  }

  // The IPC way to add a store: the dialog shows the domain and name. The
  // label is checked here, before anyone is asked: the dialog renders it,
  // so it only ever shows a cleanLabel-valid label.
  function requestAddStore(domain, label) {
    const nd = Config.normalizeDomain(String(domain || ""))
    if (nd === null) return Errors.invalidDomain()
    const given = label === undefined || label === null ? "" : String(label)
    const cleaned = given.trim() === "" ? null : Config.cleanLabel(given)
    if (given.trim() !== "" && cleaned === null) return Errors.invalidPatch("label must be 1-80 characters without control characters")
    if (configStore.configError) return Errors.configInvalid(configStore.configError)
    if (!configStore.loaded) return Errors.configUnavailable()
    // A dry run of the write the accepted dialog makes: duplicate, cap, label.
    const dry = Config.addStore(configStore.config, nd, cleaned, discovery.result.stores)
    if (dry.error) return { ok: false, error: dry.error }
    return internal.request({ action: "addStore", domain: dry.domain, label: dry.label })
  }

  // Called by the panel's Dialog (ui/Dialog.qml) only. On accept, runs the
  // operation with exactly the consent the dialog showed (pendingConfirm.live).
  function resolvePending(id, accepted) {
    const r = consent.resolve(id, accepted)
    internal.publish()
    if (!r.ok) return r
    if (!r.accepted) return Errors.ok()
    const p = r.spec
    if (p.action === "push") return root.pushTheme(p.domain, { confirmLive: p.live })
    if (p.action === "pull") return root.pullTheme(p.domain)
    if (p.action === "restore") return root.restoreBackup(p.domain, p.backupId, { confirmLive: p.live })
    if (p.action === "installCli") return root.installCli()
    // addStore: the last of the five actions internal.request issues (a new
    // one needs its own line above).
    return root.addStore(p.domain, p.label)
  }

  // ---- destructive operations (QML-only, never on IPC) --------------------

  // A live target needs theme.allowLive (--allow-live) and opts.confirmLive
  // from the live Dialog (--confirm-live). They are sent separately, so a
  // target that went live after the themes list was cached comes back as
  // live_not_confirmed and the store view asks for the live consent.
  function pushTheme(domain, opts) {
    const s = configStore.store(domain)
    const refused = preflight.checkPush(s)
    if (refused) return refused
    themeJobs.push(s.domain, {
      folder: s.theme.folder, target: s.theme.target, name: themeInfo.target(s.domain, s.theme).name,
      allowLive: s.theme.allowLive === true, confirmLive: !!(opts && opts.confirmLive === true)
    })
    return Errors.started()
  }

  function pullTheme(domain) {
    const s = configStore.store(domain)
    const refused = preflight.checkPull(s)
    if (refused) return refused
    themeJobs.pull(s.domain, { folder: s.theme.folder, target: s.theme.target, name: themeInfo.target(s.domain, s.theme).name })
    return Errors.started()
  }

  function restoreBackup(domain, backupId, opts) {
    const s = configStore.store(domain)
    const refused = preflight.checkRestore(s, backupId)
    if (refused) return refused
    const id = String(backupId)
    const allowLive = !!(s.theme && s.theme.allowLive)
    // The result names the backup's theme (the row's name; without a row
    // the result line says "Theme <id>" from the id).
    const b = themeInfo.backupById(s.domain, id)
    themeJobs.restore(s.domain, id, allowLive, !!(opts && opts.confirmLive === true), b && b.theme ? String(b.theme.name || "") : "")
    return Errors.started()
  }

  // A paste into a panel field (QML-only, never IPC): done({ok, text} |
  // {ok: false, error}) once helpers/read-clipboard answers.
  function readClipboard(done) {
    clipboard.read(done)
  }

  function sendTestAlert() {
    alerts.test(configStore.settings.alerts.sound)
    return Errors.started()
  }

  // ---- panel hooks -------------------------------------------------------

  // A panel opened or closed (SalesScheduler fetches the stores whose
  // today figures aren't fresh when the first one opens).
  function setPanelOpen(ownerKey, open) {
    consent.setPanelOpen(ownerKey, open)
    internal.publish()
  }

  // A panel shows (or closed) its Dialog. While any is open, request* is
  // refused, so IPC can never take over consent the user is giving.
  function setDialogOpen(ownerKey, open) {
    consent.setDialogOpen(ownerKey, open)
  }

  // The panel opened a store's view: refresh what that view shows.
  function storeViewOpened(domain) {
    const s = configStore.store(domain)
    if (!s) return
    const d = s.domain
    scheduler.storeViewed(d)
    if (s.theme && account.cli.status === "ready") themeInfo.listThemesIfStale(d, 300000)
    const ti = themeInfo.stateFor(d)
    if (s.theme && s.theme.folder && (!ti || ti.folder.status === "unknown")) themeInfo.inspectFolder(d, s.theme.folder)
  }

  // ---- internals ---------------------------------------------------------

  QtObject {
    id: internal
    // A complete, empty snapshot until the first publish, so readers never
    // see null.
    property var snapshot: Snapshot.initialSnapshot()
    // The last buildSnapshot result ({snapshot, memo}); its store objects
    // are reused by the next build when their inputs did not change.
    property var lastBuild: ({ snapshot: internal.snapshot, memo: null })
    property var storeOrder: []
    property bool started: false
    // When each refresh last ran: "" for the global one, else the domain.
    property var refreshAt: Object.create(null)
    // The config entries startup or the last valid config change saw.
    property var knownStores: Object.create(null)

    function okOrError(r) {
      return r.ok ? Errors.ok() : { ok: false, error: r.error }
    }

    // fn(store) for the domain's config entry, else why there is none.
    function withStore(domain, fn) {
      const s = configStore.store(domain)
      return s ? fn(s) : preflight.storeLookupFailed()
    }

    // A refresh within 2 s of the last one with the same key ("" for the
    // global refresh, else a domain) is refused; otherwise it is recorded.
    function throttled(key) {
      const now = Date.now()
      if (now - (internal.refreshAt[key] || 0) < 2000) return true
      internal.refreshAt[key] = now
      return false
    }

    function request(spec) {
      const r = consent.request(spec)
      if (r.ok) internal.publish()
      return r
    }

    function fetched(domain, range, result, withTraffic) {
      const cfg = configStore.store(domain)
      if (!cfg) return
      const out = salesData.applyFetch(domain, range, result, withTraffic)
      if (!out) return
      const prefs = configStore.settings.alerts
      if (out.newOrders > 0 && prefs.notify) {
        const st = salesData.record(domain)
        alerts.notify(cfg.label, st.sales.today, st.currency, out.newOrders, prefs.sound)
      }
      if (out.errorCode === "signed_out") account.noteSession("signed_out")
      else if (out.errorCode === "cli_missing") account.check()
    }

    // SalesAccess results carry no arrays, so no Os.plain round trip.
    function accessFinished(domain, r) {
      const cfg = configStore.store(domain)
      if (!cfg) return
      salesData.applyGrant(domain, r)
      if (r.ok) {
        scheduler.addStore(domain)
        // A store still labelled with its subdomain takes the shop name the
        // grant verified ({ shop { name } }), when the panel asked: an IPC
        // grant never writes config.json.
        if (r.origin === "panel" && r.name && cfg.label === TextUtil.subdomainLabel(domain) && r.name !== cfg.label)
          configStore.mutate(c => Config.applyStorePatch(c, domain, { label: r.name }, root.home, { allowThemeKeys: false }))
      } else if (r.error.code === "cli_missing") {
        account.check()
      }
    }

    function jobFinished(domain, result) {
      const s = configStore.store(domain)
      if (!s) return
      themeInfo.refreshAfterJob(domain, s.theme, result)
      if (result.error && result.error.code === "signed_out") account.noteSession("signed_out")
    }

    function signedIn() {
      // A fresh account session answers any "session expired" theme
      // result; leaving it would keep offering a sign-in that signs out.
      themeJobs.dismissSessionExpired()
      // Restart discovery under the new session: an older run still going
      // would refuse the new one.
      discovery.cancel()
      root.discoverStores()
    }

    function forgetStore(domain) {
      scheduler.forget(domain)
      previews.forget(domain)
      themeInfo.forget(domain)
      themeJobs.forget(domain)
      salesAccess.cancel(domain)
      consent.clear(domain)
      delete internal.refreshAt[domain]
      salesData.forget(domain)
      internal.publish()
    }

    // Startup: prepare-state, config + cache, publish from the cache,
    // check-account, then the scheduler (once the CLI is ready). Theme
    // lists are fetched when a store view opens, never here.
    function maybeStart() {
      if (internal.started || !stateDir.ready || !configStore.loaded || !salesData.loaded) return
      const stores = configStore.stores
      for (let i = 0; i < stores.length; i++) {
        salesData.warm(stores[i].domain)
        internal.knownStores[stores[i].domain] = stores[i]
      }
      // An unreadable config lists no stores; pruning the cache against it
      // would drop every store's cached figures.
      if (!configStore.configError) salesData.retain(configStore.domains())
      internal.started = true
      account.check()
      scheduler.startup()
      internal.publish()
    }

    // Config diff by domain: added -> warm and fetch, removed -> forget,
    // folder change -> re-inspect; everything else needs no fetch. Stores
    // are forgotten (jobs, previews, grants, cached figures) only when a
    // valid config removes them: while the file is unreadable (a typo, or
    // an editor's truncate-then-write window) the known stores and their
    // running work are kept.
    function configUpdated() {
      if (configStore.configError) {
        internal.maybeStart()
        internal.publish()
        return
      }
      const stores = configStore.stores
      const next = Object.create(null)
      for (let i = 0; i < stores.length; i++) next[stores[i].domain] = stores[i]
      if (internal.started) {
        const old = Object.keys(internal.knownStores)
        for (let i = 0; i < old.length; i++) if (!next[old[i]]) internal.forgetStore(old[i])
        for (let i = 0; i < stores.length; i++) {
          const s = stores[i]
          const prev = internal.knownStores[s.domain]
          if (!prev) {
            salesData.warm(s.domain)
            scheduler.addStore(s.domain)
            continue
          }
          const oldFolder = prev.theme ? prev.theme.folder : ""
          const newFolder = s.theme ? s.theme.folder : ""
          if (oldFolder !== newFolder) themeInfo.inspectFolder(s.domain, newFolder)
        }
      }
      internal.knownStores = next
      internal.maybeStart()
      internal.publish()
    }

    function publish() {
      if (!publishTimer.running) publishTimer.start()
    }

    // One build from every model's current state, reusing the last one's
    // unchanged store objects.
    function build() {
      const stores = configStore.stores
      const parts = []
      for (let i = 0; i < stores.length; i++) {
        const d = stores[i].domain
        parts.push({
          cfg: stores[i],
          sales: salesData.records[d] || null,
          info: themeInfo.stateFor(d),
          job: themeJobs.stateFor(d),
          preview: previews.stateFor(d),
          pending: scheduler.isPending(d),
          granting: salesAccess.isGranting(d),
          retryAt: scheduler.retryAt(d)
        })
      }
      // Preflight.requireThemesIdle is the one source of the job-then-preview rule.
      const tb = preflight.requireThemesIdle()
      return Snapshot.buildSnapshot({
        configError: configStore.configError,
        configWriteError: configStore.configWriteError,
        stateError: stateDir.error,
        invalidStores: configStore.invalidStores,
        cli: account.cli,
        account: account.account,
        alertTools: alerts.health,
        pendingConfirm: consent.pending,
        themesBusy: tb ? tb.error.what : "",
        granting: salesAccess.grantingAny(),
        discovery: discovery.result,
        settings: configStore.settings,
        salesPaused: !scheduler.enabled,
        stores: parts
      }, internal.lastBuild)
    }

    function publishNow() {
      internal.lastBuild = internal.build()
      internal.snapshot = internal.lastBuild.snapshot
      const order = configStore.domains()
      if (order.join("\n") !== internal.storeOrder.join("\n")) internal.storeOrder = order
    }
  }

  StateDir {
    id: stateDir
    onReadyChanged: internal.maybeStart()
    onErrorChanged: internal.publish()
  }

  ConfigStore {
    id: configStore
    prepared: stateDir.ready
    home: root.home
    onConfigChanged: internal.configUpdated()
    onLoadedChanged: internal.maybeStart()
    onInvalidStoresChanged: internal.publish()
    onConfigWriteErrorChanged: internal.publish()
  }

  SalesData {
    id: salesData
    prepared: stateDir.ready
    home: root.home
    pollSeconds: configStore.settings.pollSeconds
    onLoadedChanged: internal.maybeStart()
    onRevisionChanged: internal.publish()
  }

  Account {
    id: account
    home: root.home
    onCliChanged: internal.publish()
    onAccountChanged: internal.publish()
    onSignedIn: internal.signedIn()
  }

  Preflight {
    id: preflight
    account: account
    configStore: configStore
    previews: previews
    salesAccess: salesAccess
    themeInfo: themeInfo
    themeJobs: themeJobs
  }

  Discovery {
    id: discovery
    onResultChanged: internal.publish()
    onSessionKnown: (session, startedAt) => account.noteSession(session, startedAt)
  }

  Consent {
    id: consent
    onPendingChanged: internal.publish()
  }

  SalesAccess {
    id: salesAccess
    onRevisionChanged: internal.publish()
    onFinished: (domain, result) => internal.accessFinished(domain, result)
  }

  SalesScheduler {
    id: scheduler
    stores: configStore.stores
    settings: configStore.settings
    salesData: salesData
    panelOpen: consent.panelOpen
    // Not gated on the account session: store-auth sessions live in the
    // CLI's own store config and survive `auth logout`, so sales keep
    // working after sign-out. A store that does fail signed_out backs off.
    enabled: internal.started && account.cli.status === "ready"
    onPendingRevisionChanged: internal.publish()
    onFetched: (domain, range, result, withTraffic) => internal.fetched(domain, range, result, withTraffic)
  }

  Clipboard {
    id: clipboard
  }

  OrderAlerts {
    id: alerts
    onHealthChanged: internal.publish()
  }

  ThemeInfo {
    id: themeInfo
    onRevisionChanged: internal.publish()
  }

  ThemeJobs {
    id: themeJobs
    onRevisionChanged: internal.publish()
    onJobFinished: (domain, result) => internal.jobFinished(domain, result)
  }

  Previews {
    id: previews
    onRevisionChanged: internal.publish()
  }

  Timer {
    id: publishTimer
    interval: 250
    repeat: false
    onTriggered: internal.publishNow()
  }

  // Scripts and keybindings: reads, refreshes, non-destructive actions,
  // cancels and request* (which only open the panel's confirmation dialog).
  IpcHandler {
    target: "shop"

    function status(): string { return JSON.stringify(root.status()) }
    function refresh(): string { return JSON.stringify(root.refresh()) }
    function refreshStore(domain: string): string { return JSON.stringify(root.refreshStore(domain)) }
    function requestAddStore(domain: string, label: string): string { return JSON.stringify(root.requestAddStore(domain, label)) }
    function grantSalesAccess(domain: string): string { return JSON.stringify(root.grantSalesAccess(domain, "ipc")) }
    function cancelSalesAccess(domain: string): string { return JSON.stringify(root.cancelSalesAccess(domain)) }
    function discoverStores(): string { return JSON.stringify(root.discoverStores()) }
    function signIn(): string { return JSON.stringify(root.signIn()) }
    function cancelSignIn(): string { return JSON.stringify(root.cancelSignIn()) }
    function cancelInstall(): string { return JSON.stringify(root.cancelInstall()) }
    function cancelThemeJob(domain: string): string { return JSON.stringify(root.cancelThemeJob(domain)) }
    function startPreview(domain: string): string { return JSON.stringify(root.startPreview(domain)) }
    function stopPreview(domain: string): string { return JSON.stringify(root.stopPreview(domain)) }
    function listThemes(domain: string): string { return JSON.stringify(root.listThemes(domain)) }
    function listBackups(domain: string): string { return JSON.stringify(root.listBackups(domain)) }
    function inspectFolder(domain: string): string { return JSON.stringify(root.inspectFolder(domain)) }
    function dismissThemeResult(domain: string): string { return JSON.stringify(root.dismissThemeResult(domain)) }
    function requestPush(domain: string): string { return JSON.stringify(root.requestPush(domain)) }
    function requestPull(domain: string): string { return JSON.stringify(root.requestPull(domain)) }
    function requestRestore(domain: string, backupId: string): string { return JSON.stringify(root.requestRestore(domain, backupId)) }
    function requestInstallCli(): string { return JSON.stringify(root.requestInstallCli()) }
  }

  Component.onCompleted: stateDir.prepare()
}
