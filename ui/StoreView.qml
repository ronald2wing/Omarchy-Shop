pragma ComponentBehavior: Bound
import QtQuick
import "../js/keymap.mjs" as Keymap
import "../js/metrics.mjs" as Metrics
import "../js/snapshot.mjs" as Snapshot

// One store: period tabs, its figures (SalesCard), then the Theme block
// (ThemeCard). Account-level states (signed out, no CLI) replace the
// figures with one empty state; a store that still needs sales access gets
// a one-step checklist instead.
//
// Contract: PanelView (snapshot, service, panel); domain; periodId;
// signals periodPicked(id), editRequested(), backupsRequested(),
// chooseFolderRequested(); keymap (js/keymap.mjs rows). Keyboard entry
// points called by ShopPanel: moveCursor, activate, textKey, deleteSelected.
PanelView {
  id: root

  property string domain: ""
  property string periodId: "today"

  signal periodPicked(string id)
  signal editRequested()
  signal backupsRequested()
  signal chooseFolderRequested()

  readonly property var store: Snapshot.storeOf(root.snapshot, root.domain)
  readonly property var sales: root.store && root.store.sales ? root.store.sales : null
  readonly property string access: root.store ? String(root.store.salesAccess || "unknown") : "unknown"
  readonly property bool linked: themeCard.linked
  readonly property var lastResult: themeCard.result
  readonly property string cliStatus: root.snapshot && root.snapshot.cli ? String(root.snapshot.cli.status || "unknown") : "unknown"
  readonly property string accountStatus: root.snapshot && root.snapshot.account ? String(root.snapshot.account.status || "unknown") : "unknown"
  readonly property bool needsAccess: Snapshot.needsAccess(root.access)
  // Cached history (from a previous session) still gives the other periods
  // something to show, so tabs stay even when today has nothing.
  readonly property bool hasAnyFigures: salesCard.hasFigures || (!!root.sales && (!!root.sales.history || !!root.sales.today))
  // No figures can come while the CLI is missing, or while signed out for a
  // store that never got its own access: say so once, with the fix. The
  // account-level state is Snapshot.accountBlock / figuresBlocked, the
  // rule Home's rows and the bar read.
  readonly property string accountBlock: Snapshot.accountBlock(root.snapshot)
  readonly property bool cliBlocked: root.accountBlock === "cli"
  readonly property bool signedOutBlocked: root.accountBlock === "signedOut" && Snapshot.figuresBlocked(root.snapshot, root.store)
  readonly property bool emptyShown: !!root.store && !root.needsAccess && !root.hasAnyFigures && (root.cliBlocked || root.signedOutBlocked)
  readonly property bool figuresShown: !!root.store && !root.needsAccess && !root.emptyShown
  // Signed out with figures on screen: the period switch and the theme
  // actions are not refused (Service does not: the CLI's stored theme
  // tokens may still work, and a command that finds none fails on its own);
  // Enter signs in.
  readonly property bool signedOut: root.accountStatus === "signed_out"
  // The view's keys (js/keymap.mjs): the key sheet lists them, the footer
  // shows the leading ones, textKey dispatches from them.
  keymap: Keymap.store({
    broken: root.configInvalid,
    granting: root.access === "granting",
    job: !!themeCard.job,
    previewOn: themeCard.previewOn,
    previewReady: root.previewReady,
    previewFailed: themeCard.previewStatus === "failed",
    needsAccess: root.needsAccess,
    linked: root.linked,
    cliBlocked: root.cliBlocked && !!root.store,
    accountBusy: root.accountStatus === "signing_in" || root.accountStatus === "signing_out",
    signInStep: root.emptyShown || (root.signedOut && !root.cliBlocked),
    figuresShown: root.figuresShown,
    hasResult: root.resultShown,
    hasDetails: root.resultHasDetails
  })
  // What the theme keys can act on right now (the key sheet lists t, x and
  // v only when they would do something): a result line, details under
  // it, a preview URL.
  readonly property bool resultShown: themeCard.resultShown
  readonly property bool resultHasDetails: themeCard.resultShown && themeCard.hasDetails
  readonly property bool previewReady: !!themeCard.preview && !!themeCard.preview.url
  // The theme card itself, for the panel smoke's checks on its rows and
  // result line.
  readonly property Item card: themeCard

  function subtitle() {
    if (!root.store) return root.domain
    var at = root.sales && root.sales.fetchedAt ? Number(root.sales.fetchedAt.today) || 0 : 0
    return Copy.t("store.subtitle", { domain: root.domain, updated: Copy.updatedText(at, root.nowMs) })
  }

  // ----- account and access -----
  function emptyAction() {
    if (root.cliBlocked) root.panel.confirm({ action: "installCli" })
    else if (root.service) root.panel.run(root.service.signIn())
  }

  // ----- theme actions -----
  // The one folder CTA: the card's Choose folder… button, Enter on a store
  // without a folder, and p/u/d before a folder is linked. Refused while
  // config.json is unusable (the write would be).
  function chooseFolder() {
    if (root.configInvalid) root.refuseBroken()
    else root.chooseFolderRequested()
  }

  // The p/u/d keys refuse exactly what the disabled buttons refuse, and the
  // toast says why. Live-ness (the lock, the two-stage consent) is the
  // panel's: it asks to allow live pushes first when the store forbids them.
  // kind: "push" | "pull".
  function requestJob(kind) {
    if (!root.store) return
    if (!root.linked) { root.chooseFolder(); return }
    var why = themeCard.refusal(kind)
    if (why !== "") { root.panel.showToast(why); return }
    root.panel.confirm({ action: kind, domain: root.domain })
  }
  function togglePreview() {
    if (!root.service) return
    // A running preview always stops first, as the footer says (even if
    // its folder was unlinked under it).
    if (themeCard.previewOn) { root.panel.run(root.service.stopPreview(root.domain)); return }
    if (!root.linked) { root.chooseFolder(); return }
    var why = themeCard.refusal("preview")
    if (why !== "") { root.panel.showToast(why); return }
    root.panel.run(root.service.startPreview(root.domain, { autoOpen: true }))
  }
  function openPreview() {
    if (root.previewReady) root.panel.openUrl(themeCard.preview.url, root.domain)
  }

  // ----- keyboard (called by ShopPanel) -----
  // h/l step the period only while the period switch is shown (a blocked
  // store would otherwise change period invisibly).
  function moveCursor(dx, dy) {
    if (dx !== 0) { if (!tabs.visible) return; let next = tabs.step(dx); if (next !== root.periodId) root.periodPicked(next) }
    else if (dy !== 0) root.panel.scrollBy(dy)
  }
  // Enter runs the one button a blocked store shows (grant access, sign
  // in, install; over cached figures too, which have no such button: the
  // footer says Enter install / sign in), or Choose folder… on a store with figures but no theme
  // folder; a linked store with figures has nothing to activate.
  function activate() {
    if (root.configInvalid) { root.refuseBroken(); return }
    if (accessSteps.visible) accessSteps.activate()
    else if (emptyState.visible) emptyState.activate()
    else if (root.figuresShown && (root.cliBlocked || root.signedOut)) root.emptyAction()
    else if (root.figuresShown && !root.linked) root.chooseFolder()
  }
  // config.json is unreadable: nothing on this store can be read or
  // changed until it is fixed or reset (the banner's i / Shift+i).
  function refuseBroken() {
    root.panel.showToast(Copy.t("error.config_invalid"))
  }
  function textKey(t) {
    var row = Keymap.rowForKey(root.keymap, t)
    if (row) root.runKey(row.id, t)
  }
  function runKey(id, t) {
    // 1–6 jump to a period, under the same guard as h/l: hidden tabs
    // would otherwise change the period invisibly, for Home as well.
    if (id === "periodJump") {
      if (!tabs.visible) return
      root.periodPicked(Metrics.PERIOD_IDS[Number(t) - 1])
      return
    }
    if (!root.service) return
    if (root.configInvalid && "aebpudvct".indexOf(t) >= 0) { root.refuseBroken(); return }
    if (id === "refresh") root.refreshStore()
    else if (id === "access") { if (root.access !== "granted") root.panel.toggleAccess(root.domain) }
    else if (id === "edit") root.editRequested()
    else if (id === "admin") root.panel.openAdmin(root.domain)
    else if (id === "push" || id === "pull") root.requestJob(id)
    else if (id === "preview") root.togglePreview()
    else if (id === "openPreview") root.openPreview()
    else if (id === "cancelJob") { if (themeCard.job) root.cancelThemeJob() }
    else if (id === "backups") root.backupsRequested()
    else if (id === "details") root.toggleDetails()
  }
  function refreshStore() {
    if (root.service) root.panel.run(root.service.refreshStore(root.domain))
  }
  function cancelThemeJob() {
    if (root.service) root.panel.run(root.service.cancelThemeJob(root.domain))
  }
  function dismissThemeResult() {
    if (root.service) root.panel.run(root.service.dismissThemeResult(root.domain))
  }
  // x / Delete (the catcher's delete key): dismiss the theme result.
  function deleteSelected() {
    if (root.resultShown) root.dismissThemeResult()
  }
  function toggleDetails() {
    if (!root.resultHasDetails) return
    themeCard.detailsOpen = !themeCard.detailsOpen
    root.revealDetails()
  }
  // A store view with figures and a failed result already fills the
  // panel, so the details box opens below the fold: lay the card and this
  // view out now and scroll the box into view (the panel lays its own
  // body out before measuring).
  function revealDetails() {
    if (!themeCard.detailsOpen) return
    themeCard.layoutDetails()
    root.forceLayout()
    root.panel.ensureVisible(themeCard.detailsItem)
  }

  property string announced: ""
  // Once per store: the service refreshes what the view shows (sales,
  // themes, folder); the backups count is a local listing the view asks
  // for itself when nothing has loaded it yet. Backups are kept per store,
  // not per folder, and restoring needs no folder, so an unlinked store
  // counts them too.
  function announce() {
    if (root.domain === root.announced || !root.service || root.domain === "") return
    root.announced = root.domain
    root.service.storeViewOpened(root.domain)
    // Read the snapshot directly: on a domain change the derived
    // properties may not have caught up yet.
    var s = Snapshot.storeOf(root.snapshot, root.domain)
    var ts = Snapshot.themeState(s)
    var b = ts ? ts.backups : null
    if (s && (!b || b.status === "idle")) root.service.listBackups(root.domain)
  }

  Component.onCompleted: { root.announce(); root.checkLivePrompt() }
  onDomainChanged: root.announce()

  // The helper decides live-ness authoritatively; if it says the push or
  // restore needed live confirmation (the theme was published since the
  // list was cached, or the request came over IPC), ask again, once per
  // result: the panel remembers which result was asked about, so revisiting
  // the store never re-asks for a push the user already declined. Only an
  // open panel asks; a result that lands while the panel is closed is asked
  // about on reopen.
  function checkLivePrompt() {
    var r = root.lastResult
    if (!root.panel || !root.panel.opened) return
    if (!r || r.ok || !r.error || !r.at || root.panel.livePrompted[root.domain] === r.at) return
    if (r.error.code !== "live_not_confirmed") return
    var shown = false
    // `live: true`: the helper found the target live when the dialog did
    // not know it, so the re-prompt carries the live consent.
    if (r.action === "push") shown = root.panel.confirm({ action: "push", domain: root.domain, live: true })
    else if (r.action === "restore" && r.restoredBackupId)
      shown = root.panel.confirm({ action: "restore", domain: root.domain, backupId: String(r.restoredBackupId), live: true })
    if (shown) {
      let next = Object.assign({}, root.panel.livePrompted)
      next[root.domain] = r.at
      root.panel.livePrompted = next
    }
  }
  onLastResultChanged: root.checkLivePrompt()
  Connections {
    target: root.panel
    function onOpenedChanged() { if (root.panel.opened) Qt.callLater(root.checkLivePrompt) }
  }

  spacing: Look.gapLg

  ViewHeader {
    width: parent.width
    canGoBack: true
    title: root.store ? root.store.label : root.domain
    subtitle: root.subtitle()
    actions: [
      { id: "admin", icon: "󰏌", label: Copy.t("action.admin"), tooltip: Copy.t("keys.admin") },
      { id: "edit", icon: "󰏫", tooltip: Copy.t("action.edit") }
    ]
    onBack: root.panel.pop()
    onActionPicked: (id) => {
      if (id === "admin") { root.panel.openAdmin(root.domain) }
      else if (id === "edit") root.editRequested()
    }
  }

  PeriodTabs {
    id: tabs
    visible: root.figuresShown
    periodId: root.periodId
    onPeriodPicked: (id) => root.periodPicked(id)
  }

  // Sales access still to grant: the one step that unblocks the figures.
  Checklist {
    id: accessSteps
    visible: !!root.store && root.needsAccess
    width: parent.width
    cursorStep: 0
    steps: [{
      id: "access",
      label: Copy.t("access.step"),
      done: false,
      help: root.access === "granting" ? Copy.t("access.granting")
        : (root.store && root.store.salesAccessError && root.store.salesAccessError.code !== "sales_access_required" ? Copy.errorOf(root.store.salesAccessError) : ""),
      actions: [{ id: "grant", label: root.access === "granting" ? Copy.t("action.cancel") : Copy.t("access.grant") }]
    }]
    onActivated: root.panel.toggleAccess(root.domain)
  }

  // Signed out or no CLI, and nothing cached to show.
  EmptyState {
    id: emptyState
    visible: root.emptyShown
    width: parent.width
    icon: root.cliBlocked ? "󰏗" : "󰌾"
    body: Copy.t(root.cliBlocked ? "store.installToSee" : "store.signInToSee")
    actions: [{ id: "fix", label: Copy.t(root.cliBlocked ? "action.install" : "action.signIn") }]
    cursorIndex: 0
    onActionPicked: root.emptyAction()
  }

  SalesCard {
    id: salesCard
    visible: salesCard.shown
    width: parent.width
    store: root.store
    periodId: root.periodId
    nowMs: root.nowMs
    figuresShown: root.figuresShown
    limitBannerShown: !!root.panel && !!root.panel.banner && root.panel.banner.id === "rateLimited"
    onRetryRequested: root.refreshStore()
  }

  // Block gap before the Theme section.
  Item {
    visible: !!root.store
    width: 1
    height: Math.max(0, Look.block - Look.gapLg * 2)
  }

  ThemeCard {
    id: themeCard
    visible: !!root.store
    width: parent.width
    store: root.store
    nowMs: root.nowMs
    home: root.panel ? root.panel.home : ""
    snapshot: root.snapshot
    onPush: root.requestJob("push")
    onPull: root.requestJob("pull")
    onTogglePreview: root.togglePreview()
    onOpenPreview: root.openPreview()
    onBackups: root.backupsRequested()
    onChooseFolder: root.chooseFolder()
    onDismissThemeResult: root.dismissThemeResult()
    onCancelJob: root.cancelThemeJob()
    onDetailsFocusReleased: root.panel.restoreFocus()
    onDetailsToggled: root.revealDetails()
  }
}
