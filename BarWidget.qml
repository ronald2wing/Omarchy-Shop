pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "ui"
import "js/os.mjs" as Os
import "js/bar.mjs" as Bar
import "js/text.mjs" as TextUtil

// Shop's bar entry: the pills and the panel host. All data comes from the
// service object (`service.snapshot`); the widget keeps no files of its own
// and registers no IPC target (the service owns it).
//
// Pills: one per bar-visible store up to five (short codes
// from four), one auto total above five, the total or icon when settings
// say so, one account-state pill while nothing can load (the CLI is
// missing, or signed out with no store that has its own access), and "Add
// store" with no stores.
Panel {
  id: root

  moduleName: "shop"
  manageIpc: false

  // ----- service binding -----
  // serviceFor() is a plain call, not a notifying property, so a tick
  // re-evaluates it until the service turns up.
  property int resolveTick: 0
  property int resolveAttempts: 0
  readonly property var service: {
    root.resolveTick
    var shell = root.bar ? root.bar.shell : null
    return shell && typeof shell.serviceFor === "function" ? shell.serviceFor("shop") : null
  }
  readonly property bool unavailable: !root.service && root.resolveAttempts >= 20
  // Panel has no `vertical`; the bar facade carries it (PluginBarApi).
  readonly property bool vertical: root.bar ? !!root.bar.vertical : false
  readonly property var snapshot: root.service && root.service.snapshot ? root.service.snapshot : null
  readonly property var stores: root.snapshot && root.snapshot.stores ? root.snapshot.stores : ({})
  readonly property var storeOrder: root.service && root.service.storeOrder ? root.service.storeOrder : []
  // Every rule of the bar (which pills, the account pill, the total pill's
  // state and tooltip) is js/bar.mjs; the pills bind its fields.
  readonly property var model: Bar.barModel(root.snapshot, root.storeOrder, root.barDomains, root.vertical, root.nowMs)

  // Pill model: bar-visible domains and their short codes, reassigned only
  // when the list changes (a reassigned model rebuilds every pill).
  property var barDomains: []
  property var pillCodes: ({})
  property string barKey: ""

  // ----- panel state -----
  property var pendingView: ({ view: "home" })
  property string lastPendingId: ""
  property var folderReturn: null
  property real nowMs: Date.now()
  readonly property string instanceId: Math.random().toString(36).slice(2, 10)
  readonly property string screenName: {
    var w = root.QsWindow.window
    return w && w.screen ? String(w.screen.name) : ""
  }
  readonly property string ownerKey: root.screenName + ":" + root.instanceId
  readonly property string home: Quickshell.env("HOME") || ""
  // The lazily built ShopPanel (null until the first open), untyped so its
  // own functions are reachable.
  readonly property var panelContent: popup.loadedContent

  function syncBarDomains() {
    var out = []
    var labels = []
    for (var i = 0; i < root.storeOrder.length; i++) {
      var s = root.stores[root.storeOrder[i]]
      if (s && s.showInBar) { out.push(root.storeOrder[i]); labels.push(String(s.label)) }
    }
    var key = out.join("\n") + "\u001e" + labels.join("\n")
    if (key !== root.barKey) {
      root.barKey = key
      root.barDomains = out
      // Initials per visible store; a repeat gets a digit suffix (AA, AA2).
      var codes = TextUtil.shortCodes(labels)
      var map = {}
      for (var k = 0; k < out.length; k++) map[out[k]] = codes[k]
      root.pillCodes = map
    }
  }

  function openAt(view) {
    root.pendingView = view
    if (root.opened) {
      var c = popup.ensureContent()
      if (c) c.navigate(view)
      root.pendingView = { view: "home" }
    } else {
      root.open()
    }
  }

  // Left click on a pill: open the panel at that store, or close it when it
  // already shows that view.
  function togglePanelAt(view) {
    var c = root.panelContent
    if (root.opened && c) {
      var cur = c.route
      if (cur && cur.view === view.view && String(cur.domain || "") === String(view.domain || "")) { root.close(); return }
    }
    root.openAt(view)
  }

  function syncPanelOpen() {
    if (root.service) root.service.setPanelOpen(root.ownerKey, root.opened)
  }

  // An IPC request* publishes pendingConfirm; the widget on the focused
  // monitor opens its panel where the dialog belongs and asks the panel to
  // show it.
  function checkPending() {
    var pc = root.snapshot ? root.snapshot.pendingConfirm : null
    if (!pc || !pc.id) return
    if (String(pc.id) === root.lastPendingId) return
    root.lastPendingId = String(pc.id)
    var focused = Hyprland.focusedMonitor
    if (!focused || focused.name !== root.screenName) return
    var action = String(pc.action || "")
    var view = action === "installCli" ? { view: "settings" }
      : (action === "addStore" ? { view: "home" } : { view: "store", domain: String(pc.domain || "") })
    root.openAt(view)
    Qt.callLater(function() {
      var c = root.panelContent
      if (c) c.confirmPending(pc)
    })
  }

  // The folder dialog is a separate window; the overlay panel closes first
  // so the dialog is never hidden under it, then reopens where it was.
  function chooseFolder(domain) {
    if (!domain) return
    root.folderReturn = root.panelContent.route
    folderDialog.domain = domain
    var s = root.stores[domain]
    var folder = s && s.theme && s.theme.folder ? String(s.theme.folder) : root.home
    folderDialog.currentFolder = Util.fileUrl(folder)
    root.close()
    folderDialog.open()
  }

  implicitWidth: pillRow.implicitWidth
  implicitHeight: pillRow.implicitHeight

  onOpenedChanged: {
    root.syncPanelOpen()
    if (!root.opened) return
    root.nowMs = Date.now()
    var c = popup.ensureContent()
    if (c) c.navigate(root.pendingView)
    root.pendingView = { view: "home" }
  }

  onServiceChanged: {
    root.syncBarDomains()
    if (root.opened) root.syncPanelOpen()
  }

  Component.onDestruction: {
    if (root.service) root.service.setPanelOpen(root.ownerKey, false)
  }

  Connections {
    target: root.service
    // Service.snapshot is reassigned on every publish; syncBarDomains and
    // checkPending skip repeats themselves.
    function onSnapshotChanged() {
      root.syncBarDomains()
      root.checkPending()
    }
    function onStoreOrderChanged() { root.syncBarDomains() }
  }

  Timer {
    interval: root.unavailable ? 5000 : 500
    repeat: true
    running: !root.service
    onTriggered: {
      root.resolveAttempts++
      root.resolveTick++
    }
  }

  // Tooltip ages and the stale banner's clock.
  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: root.nowMs = Date.now()
  }

  Row {
    id: pillRow
    spacing: 0

    // Service not bound yet, or not available on this bar.
    StorePill {
      visible: !root.service
      bar: root.bar
      fixedText: root.unavailable ? "󰒚 !" : "󰒚 …"
      fixedTooltip: root.unavailable ? Copy.t("bar.unavailable") : Copy.t("status.checking")
      tailTip: false
      tone: root.unavailable ? "error" : "info"
    }

    // CLI missing, signed out, installing, config unreadable: one pill in
    // the banner's tone, opening Home where the banner has the action.
    StorePill {
      visible: !!root.service && !!root.model.accountPill && !root.vertical
      bar: root.bar
      fixedText: root.model.accountPill ? root.model.accountPill.text : ""
      fixedTooltip: root.model.accountPill ? root.model.accountPill.tooltip : ""
      tone: root.model.accountPill ? root.model.accountPill.tone : ""
      onOpenRequested: root.togglePanelAt({ view: root.model.accountPill ? root.model.accountPill.view : "home" })
      onRefreshRequested: { if (root.service) root.service.refresh() }
    }

    // No stores yet: one click opens Add.
    StorePill {
      visible: !!root.service && !root.model.accountPill && root.storeOrder.length === 0 && !root.vertical
      bar: root.bar
      fixedText: "󰒚 " + Copy.t("action.add")
      fixedTooltip: Copy.t("add.title")
      tailTip: false
      onOpenRequested: root.togglePanelAt({ view: "add" })
    }

    Repeater {
      model: root.model.showStores ? root.barDomains : []

      delegate: StorePill {
        required property string modelData
        bar: root.bar
        code: root.model.initials ? String(root.pillCodes[modelData] || "") : ""
        nowMs: root.nowMs
        store: root.stores[modelData] || null
        pulseKey: store && store.sales ? Number(store.sales.newOrderAt) || 0 : 0
        onOpenRequested: (domain) => root.togglePanelAt({ view: "store", domain: domain })
        onRefreshRequested: (domain) => { if (root.service) root.service.refreshStore(domain) }
      }
    }

    // Total, auto total, or icon.
    StorePill {
      visible: !!root.service && (root.vertical || (!root.model.accountPill && root.storeOrder.length > 0 && !root.model.showStores))
      bar: root.bar
      display: root.model.singleDisplay
      nowMs: root.nowMs
      totals: root.model.totals
      storeCount: root.model.autoTotal ? root.barDomains.length : 0
      pulseKey: root.model.latestNewOrderAt
      dotTone: root.model.dotTone
      loading: root.model.totalLoading
      tooltipLines: root.model.totalTooltipLines
      problem: root.model.totalProblem
      limited: root.model.limited
      onOpenRequested: root.togglePanelAt({ view: "home" })
      onRefreshRequested: { if (root.service) root.service.refresh() }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: pillRow
    bar: root.bar
    owner: root
    open: root.opened
    focusTarget: popup.loadedContent
    contentWidth: popup.fittedContentWidth(Style.space(440))
    contentHeight: popup.fittedContentHeight(popup.loadedContentHeight, Style.space(680))

    content: Component {
      ShopPanel {
        service: root.service
        opened: root.opened
        ownerKey: root.ownerKey
        onDismissRequested: root.close()
        onSwitchRequested: (direction) => root.switchPanel(direction)
        onChooseFolderRequested: (domain) => root.chooseFolder(domain)
      }
    }
  }

  FolderDialog {
    id: folderDialog
    property string domain: ""
    title: Copy.t("edit.folder")
    onAccepted: {
      var d = folderDialog.domain
      var path = Os.fileUrlToPath(String(folderDialog.selectedFolder))
      var res = root.service ? root.service.updateStore(d, JSON.stringify({ theme: { folder: path } })) : null
      root.openAt({ view: "edit", domain: d })
      var c = root.panelContent
      if (c && res) c.run(res)
    }
    onRejected: root.openAt(root.folderReturn)
  }
}
