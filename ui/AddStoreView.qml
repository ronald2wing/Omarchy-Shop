pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../js/format.mjs" as Format
import "../js/keymap.mjs" as Keymap
import "../js/snapshot.mjs" as Snapshot

// Discover-first add: the stores on the signed-in account, filterable, with
// a manual domain entry underneath. Adding never opens a browser; the new
// store opens as soon as it is added.
//
// Contract: PanelView (snapshot, service, panel); manualOpen; signal
// added(domain) (also for a listed store already in Shop: it opens);
// cursorId (a discovered domain, or manualId). Keyboard entry points
// called by ShopPanel and the filter: moveCursor, activate, textKey,
// dropHiddenInput.
PanelView {
  id: root

  property bool manualOpen: false

  // A store was added: the panel opens it (Home-rooted).
  signal added(string domain)

  readonly property var discovery: root.snapshot ? (root.snapshot.discovery || null) : null
  readonly property string discoveryStatus: root.discovery ? String(root.discovery.status || "idle") : "idle"
  readonly property var discovered: root.discovery && root.discovery.stores ? root.discovery.stores : []
  readonly property string filterText: filterField.text.toLowerCase()

  // Repeater model: domains, reassigned only when the join changes.
  property var discoveredDomains: []
  property string manualError: ""

  readonly property bool cliReady: !!root.panel && root.panel.cliReady
  // config.json is unusable (configInvalid): every add would be refused,
  // so the status row says why and the list, the filter and the manual
  // entry are hidden instead of offering rows that do nothing.
  readonly property bool signedOut: !!root.snapshot && !!root.snapshot.account && root.snapshot.account.status === "signed_out"
  // The keyboard cursor walks the discovered rows, then the manual-entry
  // row (manualId, never a domain), so a store can always be added without
  // a mouse, even with nothing discovered.
  readonly property string manualId: ":manual"
  readonly property var rowIds: root.discoveredDomains.concat([root.manualId])
  property alias cursorId: cursor.rowId
  readonly property int cursorIndex: cursor.rowIndex
  readonly property bool onManual: root.cursorId === root.manualId
  RowCursor {
    id: cursor
    ids: root.rowIds
    view: root
    panel: root.panel
  }
  // The view's keys (js/keymap.mjs). Enter follows the cursor's row: a
  // store already in Shop opens, the manual row opens the domain field
  // (with no CLI and nothing discovered it is the only row: no filter),
  // any other store is added; r needs the CLI.
  keymap: Keymap.add({
    broken: root.configInvalid,
    manualRow: root.onManual,
    manualOnly: root.onManual && !root.cliReady && root.discovered.length === 0,
    inShop: !root.onManual && cursor.rowIndex >= 0 && root.inShop(root.cursorId),
    canDiscover: root.cliReady
  })
  // Status reads the source rows (matchCount), never the synced model
  // list, which lags a tick behind.
  readonly property int matchCount: root.matchingDomains().length
  readonly property string statusText: {
    if (root.configInvalid) return Copy.t("status.configError")
    if (root.discoveryStatus === "running") return Copy.t("add.finding")
    if (root.matchCount === 0) {
      if (!root.cliReady) return Copy.t("add.cliMissing")
      if (root.signedOut) return Copy.t("add.signedOut")
    }
    if (root.discoveryStatus === "failed") return Copy.errorOf(root.discovery ? root.discovery.error : null)
    if (root.discoveryStatus === "done" && root.matchCount === 0)
      return root.discovered.length === 0 ? Copy.t("add.none") : Copy.t("add.noMatches")
    return ""
  }
  // Signed out or no CLI is a setup state (warn), not a failure.
  readonly property string statusTone: root.configInvalid ? "warn"
    : (root.matchCount === 0 && (!root.cliReady || root.signedOut)) ? "warn"
    : root.discoveryStatus === "failed" ? "error" : "info"
  readonly property var statusActions: {
    if (root.configInvalid || root.discoveryStatus === "running") return []
    if (root.matchCount === 0 && root.cliReady && root.signedOut) return [{ id: "signIn", label: Copy.t("action.signIn") }]
    if (root.discoveryStatus === "failed") return [{ id: "retry", label: Copy.t("action.tryAgain") }]
    return []
  }

  function rowFor(domain) {
    for (var i = 0; i < root.discovered.length; i++) if (root.discovered[i].domain === domain) return root.discovered[i]
    return null
  }

  function inShop(domain) {
    return !!Snapshot.storeOf(root.snapshot, domain)
  }

  // The discovered domains that pass the filter, in list order.
  function matchingDomains() {
    var q = root.filterText
    var out = []
    for (var i = 0; i < root.discovered.length; i++) {
      var r = root.discovered[i]
      if (!r || !r.domain) continue
      if (q !== "" && String(r.name || "").toLowerCase().indexOf(q) === -1 && String(r.domain).indexOf(q) === -1) continue
      out.push(String(r.domain))
    }
    return out
  }

  function syncDomains() {
    var out = root.matchingDomains()
    if (out.join("\n") === root.discoveredDomains.join("\n")) return
    // With no rows the cursor rests on the manual row only because nothing
    // else is there: the first stores to arrive take it, unless the manual
    // entry is open.
    var rested = root.discoveredDomains.length === 0 && root.onManual && !root.manualOpen
    root.discoveredDomains = out
    if (rested && out.length > 0) cursor.rowId = out[0]
  }

  // Both adds end in the new store's view; a store the bar cannot show
  // gets one toast on the way.
  function finishAdd(res) {
    if (res.showInBar === false) root.panel.showToast(Copy.t("bar.hiddenFromBar", { n: res.shownCount }))
    root.added(res.domain)
  }

  function addDiscovered(domain) {
    var row = root.rowFor(domain)
    if (!row || !root.service || root.configInvalid) return
    if (root.inShop(domain)) { root.added(domain); return }
    var res = root.service.addStore(domain, String(row.name || ""))
    if (res.ok === false) { root.panel.run(res); return }
    root.finishAdd(res)
  }

  function addManual() {
    if (root.configInvalid) return
    // Config.normalizeDomain (in the service) owns the domain rules.
    var domain = manualField.text.trim()
    if (domain === "" || !root.service) { root.manualError = Copy.t("error.invalid_domain"); return }
    // An empty label lets the service use the shop's name, else the
    // subdomain.
    var res = root.service.addStore(domain, "")
    if (res.ok === false) { root.manualError = Copy.errorOf(res.error); return }
    root.manualError = ""
    manualField.text = ""
    manualField.focus = false
    root.panel.restoreFocus()
    root.finishAdd(res)
  }

  function discoverAgain() {
    if (root.service && root.discoveryStatus !== "running") root.panel.run(root.service.discoverStores())
  }

  function statusAction(id) {
    if (id === "signIn") { if (root.service) root.panel.run(root.service.signIn()) }
    else if (id === "retry") root.discoverAgain()
  }

  // config.json broke: the filter and the manual entry are hidden, so drop
  // their text and their focus (a hidden field would keep eating keys).
  function dropHiddenInput() {
    filterField.clear()
    manualField.text = ""
    manualField.focus = false
    if (root.panel) root.panel.restoreFocus()
  }
  onConfigInvalidChanged: if (root.configInvalid) root.dropHiddenInput()

  function focusFilter() {
    filterField.focusInput()
  }

  function openManual() {
    if (root.configInvalid) return
    root.manualOpen = true
    cursor.rowId = root.manualId
    Qt.callLater(function() { manualField.forceActiveFocus() })
  }

  // ----- keyboard (called by ShopPanel and the filter) -----
  // While config.json is unusable the list, the filter and the manual
  // entry are hidden (nothing could be added), so the keys have no target.
  function moveCursor(dx, dy) {
    if (root.configInvalid) return
    cursor.moveBy(dy)
  }
  function itemFor(id) {
    return id === root.manualId ? manualToggle : rows.itemAt(root.discoveredDomains.indexOf(id))
  }
  function activate() {
    if (root.configInvalid || cursor.rowIndex < 0) return
    if (root.onManual) root.openManual()
    else root.addDiscovered(root.cursorId)
  }
  function textKey(t) {
    if (root.configInvalid) return
    var row = Keymap.rowForKey(root.keymap, t)
    if (!row) return
    if (row.id === "filter") root.focusFilter()
    else if (row.id === "discover") root.discoverAgain()
    else if (row.id === "manual") root.openManual()
  }

  // Deferred: `discovered` changes while bindings are still being set up
  // on a revisit, and a synchronous model write there is a binding loop.
  // A Timer (not Qt.callLater) dies with the view, so leaving Add right
  // after an add never runs the sync on a destroyed item.
  onDiscoveredChanged: syncLater.restart()
  // A new filter puts the cursor on its first match.
  onFilterTextChanged: {
    root.syncDomains()
    cursor.rowId = root.rowIds[0]
  }

  Timer {
    id: syncLater
    interval: 0
    onTriggered: root.syncDomains()
  }

  Component.onCompleted: {
    root.syncDomains()
    var stale = !root.discovery || !root.discovery.finishedAt || Date.now() - Number(root.discovery.finishedAt) > 300000
    if (root.cliReady && !root.configInvalid && root.discoveryStatus !== "running" && stale && root.service) root.service.discoverStores()
    if (root.manualOpen) root.openManual()
  }

  spacing: Look.gapLg

  ViewHeader {
    width: parent.width
    canGoBack: true
    title: Copy.t("add.title")
    actions: [{ id: "discover", icon: "󰑓", tooltip: Copy.t("keys.discoverAgain") }]
    busyIds: root.discoveryStatus === "running" ? ["discover"] : []
    disabledIds: root.cliReady && !root.configInvalid ? [] : ["discover"]
    onBack: root.panel.pop()
    onActionPicked: (id) => { if (id === "discover") root.discoverAgain() }
  }

  FilterField {
    id: filterField
    visible: !root.configInvalid
    width: parent.width
    placeholder: Copy.t("add.filter")
    paste: root.panel ? root.panel.paste : null
    onMoveRequested: (dy) => root.moveCursor(0, dy)
    onSubmitted: root.activate()
    onReleased: root.panel.restoreFocus()
  }

  SectionHeader {
    visible: !root.configInvalid
    text: root.discovered.length > 0 && root.discoveryStatus !== "done" ? Copy.t("add.lastSession") : Copy.t("add.yourStores")
  }

  StatusLine {
    visible: root.statusText !== ""
    width: parent.width
    tone: root.statusTone
    icon: root.discoveryStatus === "running" && !root.configInvalid ? "󰔟" : ""
    text: root.statusText
    actions: root.statusActions
    onAction: (id) => root.statusAction(id)
  }

  // The discovered rows; hidden with the status "Nothing to show until
  // config.json is fixed.", which they would otherwise contradict.
  Column {
    visible: !root.configInvalid
    width: parent.width
    spacing: Look.listGap

    Repeater {
      id: rows
      model: root.discoveredDomains

      delegate: DiscoveredStoreRow {
        required property string modelData
        width: parent ? parent.width : 0
        row: root.rowFor(modelData)
        selected: root.cursorId === modelData
        inShop: root.inShop(modelData)
        onHoveredRow: cursor.moveTo(modelData)
        onActivated: root.addDiscovered(modelData)
      }
    }
  }

  // The merged list was cut (by the CLI per organization, or by the
  // helper's cap): say how many made it, not a fixed number.
  PlainLabel {
    visible: !root.configInvalid && !!root.discovery && !!root.discovery.truncated && root.discovered.length > 0
    text: Copy.t("add.truncated", { n: Format.count(root.discovered.length) })
    color: Look.muted
    font.pixelSize: Look.caption
  }

  PanelSeparator { visible: !root.configInvalid }

  Button {
    id: manualToggle
    visible: !root.configInvalid
    text: (root.manualOpen ? "▾ " : "▸ ") + Copy.t("add.manual")
    fontSize: Look.small
    horizontalPadding: Style.spacing.sm
    hasCursor: root.onManual
    onClicked: {
      if (root.manualOpen) root.manualOpen = false
      else root.openManual()
    }
    Accessible.role: Accessible.Button
    Accessible.name: Copy.t("add.manual")
    Accessible.onPressAction: root.openManual()
  }

  Column {
    visible: root.manualOpen && !root.configInvalid
    width: parent.width
    spacing: Look.gapXs

    Row {
      width: parent.width
      spacing: Look.gapMd

      LineEdit {
        id: manualField
        width: parent.width - domainSuffix.implicitWidth - addButton.implicitWidth - parent.spacing * 2
        placeholderText: Copy.t("add.domainPlaceholder")
        verticalPadding: Style.spacing.xs
        maximumLength: 255
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhUrlCharactersOnly
        paste: root.panel ? root.panel.paste : null
        Accessible.name: Copy.t("add.manual")
        onTextChanged: root.manualError = ""
        onAccepted: root.addManual()
        Keys.onEscapePressed: (event) => {
          event.accepted = true
          manualField.focus = false
          root.panel.restoreFocus()
        }
      }

      PlainLabel {
        id: domainSuffix
        anchors.verticalCenter: manualField.verticalCenter
        text: manualField.text.indexOf(".") === -1 ? ".myshopify.com" : ""
        color: Look.muted
      }

      SmallButton {
        id: addButton
        anchors.verticalCenter: manualField.verticalCenter
        text: Copy.t("add.add")
        onClicked: root.addManual()
      }
    }

    PlainLabel {
      visible: root.manualError !== ""
      width: parent.width
      text: root.manualError
      color: Look.negative
      font.pixelSize: Look.caption
      wrapMode: Text.WordWrap
    }
  }
}
