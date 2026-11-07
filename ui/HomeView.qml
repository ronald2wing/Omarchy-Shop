pragma ComponentBehavior: Bound
import QtQuick
import qs.Ui
import "../js/keymap.mjs" as Keymap
import "../js/metrics.mjs" as Metrics
import "../js/format.mjs" as Format
import "../js/snapshot.mjs" as Snapshot

// Home: the total across stores for Today / 7d / 30d (TotalCard), one row
// per store, the invalid config-entry lines, and on first run the "Set up
// Shop" checklist.
//
// Contract: PanelView (snapshot, service, panel); periodId; cursorId (the
// selected store's domain); signals storeOpenRequested(domain), addRequested(manual),
// settingsRequested(), removeRequested(domain), editRequested(domain),
// periodPicked(id). Keyboard entry points called by ShopPanel: moveCursor,
// activate, reorder, deleteSelected, textKey.
PanelView {
  id: root

  property string periodId: "today"
  // The selected store, by domain: it follows its store across a reorder
  // and is kept while config.json is unreadable (the order is empty then).
  property alias cursorId: cursor.rowId
  readonly property int cursorIndex: cursor.rowIndex
  // First run: the checklist step whose button the cursor lights, and which
  // of its buttons. A step that loses its buttons (the CLI finished
  // installing, the account signed in) hands the cursor to the next step
  // that still has one.
  property int setupStep: 0
  property int setupAction: 0
  readonly property int setupCursor: checklist.actionCount(root.setupStep) > 0 ? root.setupStep : root.setupStepFrom(0, 1)
  // Config error: which empty-state button the cursor lights.
  property int emptyCursor: 0
  // Stores whose history was asked for after a period switch (once).
  property var historyAsked: ({})

  signal storeOpenRequested(string domain)
  signal addRequested(bool manual)
  signal settingsRequested()
  signal removeRequested(string domain)
  signal editRequested(string domain)
  signal periodPicked(string id)

  readonly property var order: root.service && root.service.storeOrder ? root.service.storeOrder : []
  readonly property var stores: root.snapshot && root.snapshot.stores ? root.snapshot.stores : ({})
  readonly property var pins: root.snapshot && root.snapshot.pins ? root.snapshot.pins : ({})
  readonly property var cli: root.snapshot && root.snapshot.cli ? root.snapshot.cli : ({})
  readonly property var account: root.snapshot && root.snapshot.account ? root.snapshot.account : ({})
  // Account-level states live in the banner; rows then show "—" only.
  // Snapshot.figuresBlocked is the one rule (StoreView and the bar read
  // it too): signed out (or signing in) blanks only the stores without
  // their own sales access, and the hero totals exactly the rows that show
  // figures, so one screen never says both "$180" and "—".
  function rowMuted(store) {
    return Snapshot.figuresBlocked(root.snapshot, store)
  }
  // The stores whose rows show figures: what the hero totals. A store still
  // waiting for sales access (required or granting) can show none, so it
  // neither counts in "N stores" nor keeps the hero up on its own.
  readonly property var countedOrder: {
    var out = []
    for (var i = 0; i < root.order.length; i++) {
      var s = root.stores[root.order[i]]
      if (!s || root.rowMuted(s) || Snapshot.needsAccess(s.salesAccess)) continue
      out.push(root.order[i])
    }
    return out
  }
  // The hero and its period switch show only while some row shows figures;
  // h/l and the footer's "h/l period" follow it.
  readonly property bool periodSwitchShown: root.countedOrder.length > 0
  readonly property bool firstRun: root.order.length === 0 && !root.configInvalid
  readonly property var invalid: root.snapshot && Array.isArray(root.snapshot.invalidStores) ? root.snapshot.invalidStores : []
  // The view's keys (js/keymap.mjs): the key sheet, the footer and textKey
  // read them.
  keymap: Keymap.home({ broken: root.configInvalid, firstRun: root.firstRun, periodSwitch: root.periodSwitchShown })
  readonly property string selectedDomain: cursor.rowIndex >= 0 ? cursor.rowId : ""

  RowCursor {
    id: cursor
    ids: root.order
    view: root
    panel: root.panel
    // The panel keeps the selection across store visits (this view is
    // rebuilt each time): seeded from it (the first move replaces the
    // binding) and written back on every move.
    rowId: root.panel ? root.panel.homeCursorDomain : ""
    onRowIdChanged: if (root.panel) root.panel.homeCursorDomain = cursor.rowId
  }

  readonly property bool anyPending: {
    for (var i = 0; i < root.order.length; i++) {
      var s = root.stores[root.order[i]]
      if (s && s.sales && s.sales.pending) return true
    }
    return false
  }

  readonly property real lastUpdated: {
    var best = 0
    for (var i = 0; i < root.countedOrder.length; i++) {
      var s = root.stores[root.countedOrder[i]]
      var at = s && s.sales && s.sales.fetchedAt ? Number(s.sales.fetchedAt.today) || 0 : 0
      if (at > best) best = at
    }
    return best
  }

  // Every store has a 7-day history: the rows show sparklines, else none.
  readonly property bool sparkAll: {
    if (root.order.length === 0) return false
    for (var i = 0; i < root.order.length; i++) {
      var s = root.stores[root.order[i]]
      if (!s || Metrics.periodView(s, "last7d").buckets.length < 2) return false
    }
    return true
  }

  // The chosen period across stores, formatted: {amount, orders, storeCount,
  // trend, baseline, multi}. Mixed currencies list each total
  // and carry no trend (Metrics.periodTotals decides).
  readonly property var totals: {
    var t = Metrics.periodTotals(root.snapshot, root.countedOrder, root.periodId)
    var one = t.byCurrency.length === 1
    var parts = []
    for (var k = 0; k < t.byCurrency.length; k++) {
      var e = t.byCurrency[k]
      var m = Format.money(e.sales, e.currency)
      parts.push(one ? m : e.currency + " " + m)
    }
    return {
      amount: parts.length === 0 ? (t.loading ? "…" : "—") : parts.join(" · "),
      // `any`: some store contributed a figure; without one no order count
      // exists (it would read "0 orders" for data never read).
      any: t.any,
      orders: t.orders, storeCount: t.storeCount,
      trend: t.trend,
      baseline: t.baseline === null ? "" : Format.money(t.baseline, t.currency),
      multi: t.byCurrency.length > 1
    }
  }

  // ----- first-run checklist -----
  readonly property var setupSteps: {
    var cliStatus = String(root.cli.status || "unknown")
    var cliReady = cliStatus === "ready"
    var acc = String(root.account.status || "unknown")
    var steps = []
    var s1 = { id: "cli", label: cliReady ? Copy.t("setup.cli", { cli: root.pins.cli }) : Copy.t("setup.cli.missing"), done: cliReady, actions: [], help: "" }
    if (cliStatus === "missing" || cliStatus === "install_failed") s1.actions = [{ id: "install", label: Copy.t("action.install") }]
    else if (cliStatus === "installing") s1.help = Copy.t("banner.installing.title")
    else if (cliStatus === "unknown" && root.cli.error) {
      // The check failed (the banner's Retry, here too): not "Checking…".
      s1.help = Copy.errorOf(root.cli.error)
      s1.actions = [{ id: "retryCheck", label: Copy.t("action.retry") }]
    }
    else if (!cliReady) s1.help = Copy.t("status.checking")
    steps.push(s1)
    var s2 = { id: "signIn", label: Copy.t(acc === "signed_in" ? "setup.signedIn" : "setup.signIn"), done: acc === "signed_in", actions: [], help: "" }
    if (acc === "signing_in") s2.help = Copy.t("banner.signingIn.title")
    else if (!cliReady) s2.help = Copy.t("settings.account.needsCli")
    else if (acc !== "signed_in") s2.actions = [{ id: "signIn", label: Copy.t("action.signIn") }]
    steps.push(s2)
    steps.push({ id: "addStore", label: Copy.t("add.title"), done: false, help: "",
                 actions: [{ id: "find", label: Copy.t("setup.findStores") }, { id: "manual", label: Copy.t("add.manual") }] })
    steps.push({ id: "access", label: Copy.t("setup.access"), done: false, actions: [], help: Copy.t("setup.folderHint") })
    return steps
  }

  function setupActivate(id) {
    if (id === "install") { root.panel.confirm({ action: "installCli" }); return }
    if (id === "signIn") { if (root.service) root.panel.run(root.service.signIn()); return }
    if (id === "retryCheck") { root.refresh(); return }
    if (id === "find") { root.addRequested(false); return }
    if (id === "manual") { root.addRequested(true); return }
  }

  // The nearest step with a button, searching from `from` in direction dir.
  function setupStepFrom(from, dir) {
    var steps = root.setupSteps
    for (var i = from; i >= 0 && i < steps.length; i += dir) if (checklist.actionCount(i) > 0) return i
    return -1
  }

  function emptyActivate(id) {
    if (id === "openFile") root.panel.openConfigFile()
    else if (id === "resetConfig") root.panel.confirm({ action: "resetConfig" })
  }

  // ----- keyboard (called by ShopPanel) -----
  function moveCursor(dx, dy) {
    if (root.configInvalid) {
      var step = dx !== 0 ? dx : dy
      if (step !== 0) root.emptyCursor = Math.max(0, Math.min(1, root.emptyCursor + step))
      return
    }
    if (root.firstRun) {
      if (dy !== 0) {
        var next = root.setupStepFrom(root.setupCursor + dy, dy)
        if (next >= 0) { root.setupStep = next; root.setupAction = 0 }
      } else if (dx !== 0) {
        root.setupStep = root.setupCursor
        root.setupAction = Math.max(0, Math.min(checklist.actionCount(root.setupCursor) - 1, root.setupAction + dx))
      }
      return
    }
    if (dx !== 0) { if (root.periodSwitchShown) root.periodPicked(totalCard.step(dx)); return }
    cursor.moveBy(dy)
  }
  function itemFor(domain) {
    return rows.itemAt(root.order.indexOf(domain))
  }
  function activate() {
    if (root.configInvalid) { emptyState.activate(); return }
    if (root.firstRun) { checklist.activate(); return }
    if (root.selectedDomain !== "") root.storeOpenRequested(root.selectedDomain)
  }
  function reorder(dy) {
    if (root.selectedDomain === "" || !root.service) return
    // The cursor follows the store (it is kept by domain).
    var to = Math.max(0, Math.min(root.order.length - 1, cursor.rowIndex + dy))
    if (to !== cursor.rowIndex) root.panel.run(root.service.moveStore(root.selectedDomain, to))
  }
  function deleteSelected() {
    if (root.selectedDomain !== "") root.removeRequested(root.selectedDomain)
  }
  function refresh() {
    if (root.service) root.panel.run(root.service.refresh())
  }
  function textKey(t) {
    var row = Keymap.rowForKey(root.keymap, t)
    if (!row) return
    if (row.id === "refresh") root.refresh()
    // Add always opens Add: while config.json is unusable that view says
    // why nothing can be added (the reset stays with the banner, the empty
    // state and Shift+i).
    else if (row.id === "add") root.addRequested(false)
    else if (row.id === "settings") root.settingsRequested()
    else if (row.id === "edit") { if (root.selectedDomain !== "") root.editRequested(root.selectedDomain) }
    else if (row.id === "admin") { if (root.selectedDomain !== "") root.panel.openAdmin(root.selectedDomain) }
  }

  // A completed-period view needs history; a store without it is asked
  // once per visit (the service dedups further).
  function requestHistory() {
    if (root.periodId === "today" || !root.service) return
    var asked = Object.assign({}, root.historyAsked)
    var changed = false
    for (var i = 0; i < root.order.length; i++) {
      var d = root.order[i]
      var s = root.stores[d]
      if (!s || asked[d] || Snapshot.needsAccess(s.salesAccess)) continue
      if (typeof Metrics.periodView(s, root.periodId).sales === "number") continue
      root.service.refreshHistory(d)
      asked[d] = true
      changed = true
    }
    if (changed) root.historyAsked = asked
  }

  onPeriodIdChanged: root.requestHistory()

  // Bring a restored selection below the first row into view once laid out.
  Component.onCompleted: {
    if (cursor.rowIndex > 0) revealTimer.start()
    root.requestHistory()
  }

  Timer {
    id: revealTimer
    interval: 30
    onTriggered: cursor.reveal()
  }

  spacing: Look.block

  ViewHeader {
    width: parent.width
    title: Copy.t("home.title")
    icon: "󰒚"
    actions: [
      { id: "refresh", icon: "󰑓", tooltip: Copy.t("action.refresh") },
      { id: "add", icon: "󰐕", tooltip: Copy.t("action.add") },
      { id: "settings", icon: "󰒓", tooltip: Copy.t("action.settings") }
    ]
    busyIds: root.anyPending ? ["refresh"] : []
    onActionPicked: (id) => {
      if (id === "refresh") root.refresh()
      else if (id === "add") root.addRequested(false)
      else if (id === "settings") root.settingsRequested()
    }
  }

  // ----- hero: the chosen period across the stores that show figures -----
  TotalCard {
    id: totalCard
    visible: root.periodSwitchShown
    width: parent.width
    periodId: root.periodId
    totals: root.totals
    baselineText: Copy.baselineText(root.periodId, root.totals.baseline)
    // The stale banner's threshold, so the two never disagree.
    stale: Metrics.isStale(root.lastUpdated, root.nowMs, root.snapshot && root.snapshot.settings ? root.snapshot.settings.pollSeconds : 60)
    summary: root.totals.any
      ? Copy.t("home.summary", { orders: Copy.ordersText(root.totals.orders), stores: Copy.storesText(root.totals.storeCount), updated: Copy.updatedText(root.lastUpdated, root.nowMs) })
      : Copy.t("home.summary.noFigures", { stores: Copy.storesText(root.totals.storeCount), updated: Copy.updatedText(root.lastUpdated, root.nowMs) })
    onPeriodPicked: (id) => root.periodPicked(id)
  }

  // ----- first run -----
  Checklist {
    id: checklist
    visible: root.firstRun
    width: parent.width
    title: Copy.t("setup.title")
    steps: root.setupSteps
    cursorStep: root.setupCursor
    cursorAction: root.setupAction
    onActivated: (id) => root.setupActivate(id)
  }

  // ----- config.json unusable: the banner says why -----
  EmptyState {
    id: emptyState
    visible: root.configInvalid
    width: parent.width
    icon: "󰒚"
    body: Copy.t("status.configError")
    actions: [{ id: "openFile", label: Copy.t("home.openFile") }, { id: "resetConfig", label: Copy.t("settings.resetConfig") }]
    cursorIndex: root.emptyCursor
    onActionPicked: (id) => root.emptyActivate(id)
  }

  // ----- store rows -----
  Column {
    visible: root.order.length > 0
    width: parent.width
    spacing: Look.listGap

    PanelSeparator {}

    Repeater {
      id: rows
      model: root.order

      delegate: StoreRow {
        required property string modelData
        width: parent ? parent.width : 0
        store: root.stores[modelData] || null
        periodId: root.periodId
        selected: root.cursorId === modelData
        showSpark: root.sparkAll
        muted: root.rowMuted(store)
        onHoveredRow: cursor.moveTo(modelData)
        onActivated: root.storeOpenRequested(modelData)
        onAccessToggled: root.panel.toggleAccess(modelData)
      }
    }
  }

  // ----- entries config.json has that Shop can't read -----
  Column {
    visible: root.invalid.length > 0
    width: parent.width
    spacing: Look.gapSm

    StatusLine {
      width: parent.width
      tone: "warn"
      text: root.invalid.length === 1
        ? Copy.t("home.invalidEntries.one", { what: root.invalidWhat(root.invalid[0]) })
        : Copy.t("home.invalidEntries", { n: root.invalid.length })
      actions: [{ id: "openFile", label: Copy.t("home.openFile") }]
      onAction: (id) => { if (id === "openFile") root.panel.openConfigFile() }
    }

    Repeater {
      model: root.invalid.length > 1 ? root.invalid : []

      delegate: PlainLabel {
        required property var modelData
        x: Look.indent
        width: parent ? parent.width - Look.indent : 0
        text: "· " + root.invalidWhat(modelData)
        color: Look.muted
        font.pixelSize: Look.small
        elide: Text.ElideRight
      }
    }
  }

  // The entry's domain, or its position when the domain is unreadable.
  function invalidWhat(entry) {
    if (entry.domain) return String(entry.domain)
    return "#" + (Number(entry.index) + 1)
  }
}
