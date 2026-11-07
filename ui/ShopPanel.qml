pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import qs.Commons
import qs.Ui
import "../js/keymap.mjs" as Keymap
import "../js/urls.mjs" as Urls
import "../js/snapshot.mjs" as Snapshot

// The panel body, built lazily by the KeyboardPanel. Its root is the key
// catcher so the host can hand it focus directly. It owns navigation (a
// view stack), the single banner slot, the confirmations (ConfirmFlow and
// its Dialog), the key sheet, the toast, link opening, and the keyboard
// dispatch to whichever view shows.
//
// Contract for views:
//   every view is a PanelView: it receives `snapshot`, `service` and `panel`
//   (this item) and reads configInvalid and nowMs from it; list views keep
//   their cursor in a RowCursor (by row id)
//   panel.run(res)           shows an immediate {ok:false, error} as a toast; returns res
//   panel.confirm(spec)      ConfirmFlow.confirm: a request
//                            {action: push|pull|restore|remove|installCli|signOut|resetConfig,
//                             domain?, backupId?, live?}; false when no dialog opened
//   panel.openUrl(url, domain) / openAdmin(domain) /
//   panel.openConfigFile()   every Qt.openUrlExternally goes through Urls.isSafeOpenUrl
//   panel.paste(done)        a capped clipboard read for LineEdit; done(text)
//   panel.showToast(text), copyText(text), restoreFocus(), takeKeyboard(),
//   panel.ensureVisible(item),
//   panel.home, panel.banner, panel.nowMs, panel.periodId (store view),
//   panel.livePrompted, panel.showKeys(), panel.toastText
PanelKeyCatcher {
  id: root

  property var service: null
  property bool opened: false
  // The host's panel owner key; the service refuses IPC request* while any
  // owner has a dialog open.
  property string ownerKey: ""

  // The catcher's own closeRequested fires on every Esc (and pops a view);
  // the host closes the panel on dismissRequested, emitted at the root view.
  signal dismissRequested()
  signal switchRequested(int direction)
  signal chooseFolderRequested(string domain)

  readonly property var snapshot: root.service && root.service.snapshot ? root.service.snapshot : ({})
  readonly property string home: Quickshell.env("HOME") || ""

  // ----- navigation -----
  property var viewStack: [{ view: "home" }]
  // The view on top of the stack: {view, domain?, manual?}.
  readonly property var route: root.viewStack[root.viewStack.length - 1]
  readonly property string viewName: String(root.route.view)
  readonly property var view: viewLoader.item
  // The store view's period and Home's period / selected store, kept here
  // because the views are rebuilt on every visit.
  property string periodId: "today"
  property string homePeriodId: "today"
  property string homeCursorDomain: ""
  property real nowMs: Date.now()

  // Per-session UI memory.
  // domain -> `at` of the live_not_confirmed result already re-prompted for.
  property var livePrompted: ({})
  // The toast's current text ("" while nothing shows): the panel smoke and
  // the harness read it (the ToastHost's id is not reachable from outside).
  readonly property string toastText: toast.text
  // The confirmation flow (the panel smoke and the harness read its
  // activeSpec, the open Dialog's spec).
  readonly property var confirmFlow: confirmLayer
  // The key sheet (the panel smoke reads its rows and canGoBack).
  readonly property var keySheetItem: keySheet

  readonly property bool inputFocused: root.isTextEntry(Window.activeFocusItem)
    || (!!root.view && root.view.popupOpen === true)

  // A visible text field with the keyboard (`visible` is effective: a
  // field under a hidden form is not typing, and must not block the keys).
  function isTextEntry(i) {
    return !!i && i.visible === true && typeof i.cursorPosition === "number" && typeof i.selectAll === "function"
  }

  // A text field that kept the keyboard while its form was hidden.
  function isHiddenTextEntry(i) {
    return !!i && !i.visible && typeof i.cursorPosition === "number"
  }

  // config.json broke under a focused field whose form is now hidden (Add's
  // filter or manual domain, Edit's Name or Folder): the view drops its
  // draft (dropHiddenInput) so nothing typed survives into a later save,
  // then the panel takes the keyboard back for the banner's keys.
  function dropHiddenInput() {
    if (!root.isHiddenTextEntry(Window.activeFocusItem)) return
    if (root.view) root.view.dropHiddenInput()
    root.forceActiveFocus()
  }

  function navigate(target) {
    // A store keeps Home underneath, and Edit and Backups keep their store
    // (and Home) underneath, so Back and Esc walk down to Home instead of
    // closing the panel: a store opened from a bar pill is otherwise the only
    // way in, and Home is where Settings, Add and the total live.
    if (target.view === "store") root.viewStack = [{ view: "home" }, target]
    else if (target.view === "edit" || target.view === "backups") root.viewStack = [{ view: "home" }, { view: "store", domain: target.domain }, target]
    else root.viewStack = [target]
    root.afterNavigate()
  }

  function push(target) {
    root.viewStack = root.viewStack.concat([target])
    root.afterNavigate()
  }

  function pop() {
    if (root.viewStack.length > 1) {
      root.viewStack = root.viewStack.slice(0, root.viewStack.length - 1)
      root.afterNavigate()
    } else {
      root.dismissRequested()
    }
  }

  function afterNavigate() {
    flick.contentY = 0
    keySheet.hide()
    root.restoreFocus()
  }

  // Deferred, and re-checked when it runs: a field that blurs while focus
  // moves straight into another one (Tab from Name to Folder, a click from
  // one field into the next) leaves that field's focus alone.
  function restoreFocus() {
    Qt.callLater(function() {
      if (!confirmLayer.opened && !keySheet.visible && !root.isTextEntry(Window.activeFocusItem)) root.forceActiveFocus()
    })
  }

  // Now, and whatever has focus: for a popup that just closed, where Qt
  // may have put focus into a field nobody chose.
  function takeKeyboard() {
    if (!confirmLayer.opened && !keySheet.visible) root.forceActiveFocus()
  }

  // Settings > Keyboard shortcuts.
  function showKeys() {
    if (!root.opened || confirmLayer.opened) return
    keySheet.show()
  }

  // Shared by the views: config.json is unusable; the pinned CLI is ready.
  readonly property bool configInvalid: !!root.snapshot.configError
  readonly property bool cliReady: !!root.snapshot.cli && root.snapshot.cli.status === "ready"

  // The store's sales-access button: starts the browser grant, or cancels
  // the one running.
  function toggleAccess(domain) {
    if (!root.service) return
    var store = Snapshot.storeOf(root.snapshot, domain)
    if (store && store.salesAccess === "granting") root.run(root.service.cancelSalesAccess(domain))
    else root.run(root.service.grantSalesAccess(domain))
  }

  function scrollBy(dy) {
    flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + dy * Style.space(48)))
  }

  // Scrolls the body so `item` shows. The body's Column is laid out before
  // measuring: a caller that just made the item visible (a cursor row, the
  // failure details box) would otherwise read its position from before
  // the polish.
  function ensureVisible(item) {
    if (!item || !item.mapToItem) return
    bodyColumn.forceLayout()
    var p = item.mapToItem(flick.contentItem, 0, 0)
    var margin = Style.space(8)
    if (p.y - margin < flick.contentY) flick.contentY = Math.max(0, p.y - margin)
    else if (p.y + item.height + margin > flick.contentY + flick.height)
      flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), p.y + item.height + margin - flick.height)
  }

  // ----- feedback -----
  function showToast(text) {
    toast.show(text)
  }

  // Immediate {ok:false, error} results from service calls show briefly;
  // the result comes back so callers can chain on it.
  function run(res) {
    if (res && res.ok === false && res.error) root.showToast(Copy.errorOf(res.error))
    return res
  }

  // A paste into a LineEdit: the service reads the clipboard through its
  // capped helper (never Qt: see LineEdit); done(text) runs only for
  // non-empty text, and a failure shows as a toast.
  function paste(done) {
    if (!root.service) return
    root.service.readClipboard(function(r) {
      if (r.ok) { if (r.text !== "") done(r.text) }
      else if (r.error) root.showToast(Copy.errorOf(r.error))
    })
  }

  function copyText(text) {
    Quickshell.clipboardText = String(text)
    root.showToast("✓ " + Copy.t("settings.copied"))
  }

  function openUrl(url, domain) {
    var u = String(url || "")
    if (Urls.isSafeOpenUrl(u, String(domain || ""), root.home)) Qt.openUrlExternally(u)
  }

  function openAdmin(domain) {
    root.openUrl(Urls.adminUrl(domain), domain)
  }

  // The banner's and Home's "Open file": config.json in the user's editor.
  function openConfigFile() {
    root.openUrl(Urls.configFileUrl(root.home), "")
  }

  // ----- confirmations (ConfirmFlow) -----
  function confirm(spec) {
    return confirmLayer.confirm(spec)
  }

  // A `request*` from IPC (the host calls it once the panel is open).
  function confirmPending(pc) {
    confirmLayer.confirmPending(pc)
  }

  function hideKeySheet() {
    keySheet.hide()
  }

  // The view's keymap (js/keymap.mjs rows): the key sheet lists it, the
  // footer shows its leading rows, the view's textKey dispatches from it.
  readonly property var keymap: root.view ? root.view.keymap : []
  // The footer line before "? keys": the view's footer rows, the banner's
  // i / Shift+i while config.json is unreadable, then Esc back above the
  // bottom of the view stack.
  readonly property string footerText: Keymap.footerText(root.keymap, { broken: root.configInvalid, canGoBack: root.viewStack.length > 1 })

  // ----- banner (PanelBanner; the pure rule is js/banner.mjs) -----
  readonly property var banner: bannerSlot.spec
  readonly property var bannerActions: bannerSlot.actions

  function bannerAction(id) {
    bannerSlot.run(id)
  }

  // ----- reactions to the service -----
  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onSnapshotChanged() {
      var s = root.snapshot
      if (s.configError) root.dropHiddenInput()
      confirmLayer.syncWithSnapshot(s)
      // The store being viewed was removed. While config.json is unreadable
      // the store list is unknown (empty), so stay put: the file usually
      // comes back a moment later (an editor's truncate-then-write).
      if (!s.configError && (root.viewName === "store" || root.viewName === "edit" || root.viewName === "backups") && !Snapshot.storeOf(root.snapshot, root.route.domain))
        root.navigate({ view: "home" })
    }
  }

  Component.onDestruction: {
    if (root.service) root.service.setDialogOpen(root.ownerKey, false)
  }

  onOpenedChanged: {
    if (root.opened) {
      root.nowMs = Date.now()
      // A dialog already up is content that just appeared: restart the
      // click guard. Focus goes back to it via onActiveFocusChanged when
      // the host hands the catcher focus.
      if (confirmLayer.opened) confirmLayer.rearm()
      root.restoreFocus()
    } else {
      keySheet.hide()
      if (confirmLayer.opened) confirmLayer.close(false)
    }
  }

  // The host (KeyboardPanel.focusTarget) and restoreFocus hand the catcher
  // focus; while the dialog is open it is the dialog's, or Esc, Tab and
  // Return would reach neither (the catcher is blocked).
  onActiveFocusChanged: if (root.activeFocus && confirmLayer.opened) confirmLayer.focusDialog()

  // ----- keyboard -----
  blocked: root.inputFocused || confirmLayer.opened || keySheet.visible
  reorderable: root.viewName === "home"

  onMoveRequested: (dx, dy) => { if (root.view) root.view.moveCursor(dx, dy) }
  onReorderRequested: (dy) => { if (root.view) root.view.reorder(dy) }
  onActivateRequested: { if (root.view) root.view.activate() }
  onDeleteRequested: { if (root.view) root.view.deleteSelected() }
  onCloseRequested: root.pop()
  onTabRequested: (direction) => root.switchRequested(direction)
  onTextKey: (text, modifiers) => {
    if (modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    if (text === "?") {
      // Toggles, so a "?" that reaches the panel while the sheet is up
      // (focus not yet on the sheet) closes it instead of re-showing it.
      if (keySheet.visible) keySheet.hide()
      else keySheet.show()
      return
    }
    if (text === "\b") { if (root.viewName !== "home") root.pop(); return }
    // i / I run the banner's first / second action (Open file, Reset,
    // Install...), so no banner button needs the mouse.
    if (text === "i" || text === "I") {
      let a = root.bannerActions[text === "i" ? 0 : 1]
      if (a) { root.bannerAction(String(a.id)); return }
    }
    if (root.view) root.view.textKey(text)
  }

  // Natural height for the host; leaves room for the dialog or key sheet.
  implicitHeight: Math.max(
    confirmLayer.opened ? confirmLayer.cardHeight + Style.space(48) : 0,
    keySheet.visible ? keySheet.implicitHeight : 0,
    bodyColumn.implicitHeight + footer.implicitHeight + Look.gapLg)

  Timer {
    interval: 15000
    repeat: true
    running: root.opened
    onTriggered: root.nowMs = Date.now()
  }

  Flickable {
    id: flick
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: footer.top
    anchors.bottomMargin: Look.gapLg
    contentWidth: width
    contentHeight: bodyColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height
    // The handle stays visible whenever the body overflows: the only cue
    // that more sits below the fold (offscreen and between scrolls an
    // AsNeeded bar is hidden).
    QQC.ScrollBar.vertical: QQC.ScrollBar {
      id: scrollBar
      policy: flick.interactive ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff
    }

    Column {
      id: bodyColumn
      // A pixel of inset on both sides keeps edge-aligned borders unclipped.
      x: 1
      // The scroll bar's gutter is always reserved, so the view never
      // shifts sideways when content starts or stops overflowing.
      width: flick.width - 2 - Math.max(scrollBar.width, scrollBar.implicitWidth) - Style.space(4)
      spacing: Style.spacing.panelGap

      PanelBanner {
        id: bannerSlot
        width: parent.width
        panel: root
        service: root.service
        snapshot: root.snapshot
        nowMs: root.nowMs
      }

      Loader {
        id: viewLoader
        width: parent.width
        sourceComponent: {
          var v = root.viewName
          if (v === "store") return storeComponent
          if (v === "edit") return editComponent
          if (v === "add") return addComponent
          if (v === "backups") return backupsComponent
          if (v === "settings") return settingsComponent
          return homeComponent
        }
      }
    }
  }

  Column {
    id: footer
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    spacing: Look.gapSm

    ToastHost {
      id: toast
      width: parent.width
    }

    PanelSeparator {}

    KeyHints {
      width: parent.width
      hints: root.footerText
    }
  }

  KeySheet {
    id: keySheet
    anchors.fill: parent
    // Above the views; the confirm dialog stacks above it.
    z: 50
    view: root.viewName
    keymap: root.keymap
    bannerActions: root.bannerActions.length
    canGoBack: root.viewStack.length > 1
    onClosed: root.restoreFocus()
  }

  ConfirmFlow {
    id: confirmLayer
    anchors.fill: parent
    z: 100
    panel: root
  }

  // ----- views -----
  Component {
    id: homeComponent
    HomeView {
      snapshot: root.snapshot
      service: root.service
      panel: root
      periodId: root.homePeriodId
      onPeriodPicked: (id) => root.homePeriodId = id
      onStoreOpenRequested: (domain) => root.push({ view: "store", domain: domain })
      onAddRequested: (manual) => root.push({ view: "add", manual: manual })
      onSettingsRequested: root.push({ view: "settings" })
      onRemoveRequested: (domain) => root.confirm({ action: "remove", domain: domain })
      onEditRequested: (domain) => root.push({ view: "edit", domain: domain })
    }
  }

  Component {
    id: storeComponent
    StoreView {
      snapshot: root.snapshot
      service: root.service
      panel: root
      domain: String(root.route.domain || "")
      periodId: root.periodId
      onPeriodPicked: (id) => root.periodId = id
      onEditRequested: root.push({ view: "edit", domain: root.route.domain })
      onBackupsRequested: root.push({ view: "backups", domain: root.route.domain })
      onChooseFolderRequested: root.chooseFolderRequested(String(root.route.domain || ""))
    }
  }

  Component {
    id: editComponent
    EditStoreView {
      snapshot: root.snapshot
      service: root.service
      panel: root
      domain: String(root.route.domain || "")
      onBack: root.pop()
      onRemoveRequested: root.confirm({ action: "remove", domain: root.route.domain })
      onChooseFolderRequested: root.chooseFolderRequested(String(root.route.domain || ""))
    }
  }

  Component {
    id: addComponent
    AddStoreView {
      snapshot: root.snapshot
      service: root.service
      panel: root
      manualOpen: !!root.route.manual
      onAdded: (domain) => root.navigate({ view: "store", domain: domain })
    }
  }

  Component {
    id: backupsComponent
    BackupsView {
      snapshot: root.snapshot
      service: root.service
      panel: root
      domain: String(root.route.domain || "")
      onRestoreRequested: (row) => root.confirm({ action: "restore", domain: root.route.domain, backupId: row.id })
      onOpenFolderRequested: (path) => root.openUrl("file://" + path, String(root.route.domain || ""))
    }
  }

  Component {
    id: settingsComponent
    SettingsView {
      snapshot: root.snapshot
      service: root.service
      panel: root
    }
  }
}
