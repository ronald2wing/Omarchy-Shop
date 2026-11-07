pragma ComponentBehavior: Bound
import QtQuick
import "../js/keymap.mjs" as Keymap
import "../js/preflight.mjs" as Preflight
import "../js/snapshot.mjs" as Snapshot
import "../js/themes.mjs" as Themes

// Theme backups (restorable, newest first) and the folder copies taken
// before pulls. A row click or Enter on it restores (or opens the folder
// copy) through the panel's confirmation.
//
// Contract: PanelView (snapshot, service, panel); domain; signals
// restoreRequested(row), openFolderRequested(path); cursorId ("b:<id>" on
// a backup, "f:<id>" on a folder copy). Keyboard entry points called by
// ShopPanel: moveCursor, activate, textKey.
PanelView {
  id: root

  property string domain: ""

  // Restore goes through the panel's confirmation; a folder copy opens
  // in the file manager (the panel checks the path).
  signal restoreRequested(var row)
  signal openFolderRequested(string path)

  readonly property var store: Snapshot.storeOf(root.snapshot, root.domain)
  readonly property var ts: Snapshot.themeState(root.store)
  readonly property var backups: root.ts ? root.ts.backups : null
  readonly property string backupsStatus: root.backups ? String(root.backups.status || "idle") : "idle"
  readonly property bool loadFailed: root.backupsStatus === "error"
  // No list yet: never fetched (idle) or fetching.
  readonly property bool loading: root.backupsStatus === "loading" || root.backupsStatus === "idle"

  // Repeater models: id lists reassigned only when their join changes.
  property var backupIds: []
  property var folderCopyIds: []
  readonly property int rowCount: root.backupIds.length + root.folderCopyIds.length
  // The cursor's row, by kind and id: a relist that puts a new backup on
  // top leaves it on the same row.
  readonly property var rowIds: root.backupIds.map(function(id) { return "b:" + id }).concat(root.folderCopyIds.map(function(id) { return "f:" + id }))
  property alias cursorId: cursor.rowId
  readonly property int cursorIndex: cursor.rowIndex
  readonly property bool onFolderCopy: cursor.rowIndex >= 0 && root.cursorId.indexOf("f:") === 0
  RowCursor {
    id: cursor
    ids: root.rowIds
    view: root
    panel: root.panel
  }
  // While config.json is unreadable the store is unknown, the list can't
  // load and only the banner's keys work.
  // The view's keys (js/keymap.mjs): Enter opens a folder copy when the
  // cursor is on one (or only folder copies are listed), else restores; o
  // opens a folder copy only when one is listed; an empty list has only r.
  keymap: Keymap.backups({
    broken: root.configInvalid,
    empty: root.rowCount === 0,
    noCopies: root.folderCopyIds.length === 0,
    onFolderCopy: root.onFolderCopy
  })

  function itemsOf(kind) {
    if (!root.backups) return []
    var list = kind === "folderCopy" ? root.backups.folderCopies : root.backups.items
    return list || []
  }
  function rowFor(kind, id) {
    var list = root.itemsOf(kind)
    for (var i = 0; i < list.length; i++) if (String(list[i].id) === id) return list[i]
    return null
  }
  function idsOf(kind) {
    var list = root.itemsOf(kind)
    var out = []
    for (var i = 0; i < list.length; i++) out.push(String(list[i].id))
    return out
  }
  function syncIds() {
    var b = root.idsOf("backup")
    if (b.join("\n") !== root.backupIds.join("\n")) root.backupIds = b
    var l = root.idsOf("folderCopy")
    if (l.join("\n") !== root.folderCopyIds.join("\n")) root.folderCopyIds = l
  }

  // What the service would refuse on accepting the restore of `id`
  // (Preflight.beforeDialog), said before the dialog.
  function refusal(id) {
    var refused = Preflight.beforeDialog(Preflight.factsOf(root.snapshot, root.store, id), "restore")
    return refused ? Copy.errorOf(refused.error) : ""
  }

  function activateRow(kind, id) {
    var row = root.rowFor(kind, id)
    if (!row) return
    if (kind === "folderCopy") { root.openFolderRequested(String(row.path || "")); return }
    var why = root.refusal(String(row.id))
    if (why !== "") { root.panel.showToast(why); return }
    root.restoreRequested(row)
  }

  // o: the folder copy under the cursor, else the first one.
  function openFolderCopy() {
    var id = root.onFolderCopy ? root.cursorId.substring(2) : root.folderCopyIds[0]
    if (id) root.activateRow("folderCopy", id)
  }

  function reload() {
    if (root.service && root.domain !== "") root.service.listBackups(root.domain)
  }

  // ----- keyboard (called by ShopPanel) -----
  function moveCursor(dx, dy) {
    cursor.moveBy(dy)
  }
  function itemFor(rowId) {
    var id = rowId.substring(2)
    return rowId.indexOf("f:") === 0 ? folderCopyRows.itemAt(root.folderCopyIds.indexOf(id)) : backupRows.itemAt(root.backupIds.indexOf(id))
  }
  function activate() {
    if (root.configInvalid || cursor.rowIndex < 0) return
    root.activateRow(root.onFolderCopy ? "folderCopy" : "backup", root.cursorId.substring(2))
  }
  function textKey(t) {
    if (root.configInvalid) return
    var row = Keymap.rowForKey(root.keymap, t)
    if (!row) return
    if (row.id === "reload") root.reload()
    else if (row.id === "openFolder") root.openFolderCopy()
  }

  // Deferred: on a revisit `backups` changes while bindings are still being
  // set up, and a synchronous write to backupIds there is a binding loop.
  // A Timer dies with the view; Qt.callLater could fire after it is gone.
  onBackupsChanged: syncLater.restart()

  Timer {
    id: syncLater
    interval: 0
    onTriggered: root.syncIds()
  }
  Component.onCompleted: {
    root.syncIds()
    root.reload()
  }

  spacing: Look.gapLg

  ViewHeader {
    width: parent.width
    canGoBack: true
    title: Copy.t("backups.title", { label: root.store ? root.store.label : root.domain })
    actions: [{ id: "refresh", icon: "󰑓", tooltip: Copy.t("action.refresh") }]
    busyIds: root.backupsStatus === "loading" ? ["refresh"] : []
    onBack: root.panel.pop()
    onActionPicked: (id) => { if (id === "refresh") root.reload() }
  }

  // What the list holds and how many are kept: a full-width line that
  // wraps (the header's subtitle slot is a single elided line).
  PlainLabel {
    width: parent.width
    text: Copy.t("backups.intro")
    color: Look.muted
    font.pixelSize: Look.small
    wrapMode: Text.WordWrap
  }

  // config.json can't be read: one line instead of a list that never loads.
  StatusLine {
    visible: root.configInvalid
    width: parent.width
    tone: "error"
    text: Copy.t("error.config_invalid")
  }

  StatusLine {
    visible: !root.configInvalid && root.loadFailed
    width: parent.width
    tone: "error"
    text: Copy.errorOf(root.backups ? root.backups.error : null)
    actions: [{ id: "retry", label: Copy.t("action.retry") }]
    onAction: root.reload()
  }

  // Under a load error the list is unknown, not empty. Visibility reads the
  // source lists, never the synced id lists syncIds writes. Folder copies
  // below are something to show, so "No backups yet" waits for both.
  StatusLine {
    visible: !root.configInvalid && !root.loadFailed && (root.loading
      || (root.itemsOf("backup").length === 0 && root.itemsOf("folderCopy").length === 0))
    width: parent.width
    tone: "info"
    icon: root.loading ? "󰔟" : ""
    text: root.loading ? Copy.t("backups.loading") : Copy.t("backups.empty")
  }

  Column {
    width: parent.width
    spacing: Look.listGap

    Repeater {
      id: backupRows
      model: root.backupIds

      delegate: BackupRow {
        required property string modelData
        width: parent ? parent.width : 0
        row: root.rowFor("backup", modelData)
        selected: root.cursorId === "b:" + modelData
        live: !!row && Themes.restoreIsLive(root.ts, String(row.id))
        nowMs: root.nowMs
        onHoveredRow: cursor.moveTo("b:" + modelData)
        onActivated: root.activateRow("backup", modelData)
      }
    }
  }

  SectionHeader {
    visible: root.itemsOf("folderCopy").length > 0
    text: Copy.t("backups.folderCopies")
  }

  Column {
    visible: root.itemsOf("folderCopy").length > 0
    width: parent.width
    spacing: Look.listGap

    Repeater {
      id: folderCopyRows
      model: root.folderCopyIds

      delegate: BackupRow {
        required property string modelData
        width: parent ? parent.width : 0
        folderCopy: true
        row: root.rowFor("folderCopy", modelData)
        selected: root.cursorId === "f:" + modelData
        nowMs: root.nowMs
        onHoveredRow: cursor.moveTo("f:" + modelData)
        onActivated: root.activateRow("folderCopy", modelData)
      }
    }
  }
}
