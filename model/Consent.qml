pragma ComponentBehavior: Bound
import QtQuick
import "../js/errors.mjs" as Errors

// The one pending confirmation and the dialog/panel bookkeeping around it.
// A request only records what the user is asked; the Service runs the
// action after resolve(id, true). Requests come only from IPC. Never two
// at once, never while a dialog is open, and for 30 s after the user
// declines one every request is refused (whatever it asks), so a script
// cannot pester the user into accepting by rotating stores, backups or
// actions.
Item {
  id: root

  // { id, action, domain, backupId, label, live } or null.
  readonly property var pending: internal.pending
  // Any panel has its Dialog (ui/Dialog.qml) open.
  readonly property bool dialogOpen: Object.keys(internal.dialogOwners).length > 0
  readonly property bool panelOpen: internal.panelOpen
  // Tests inject a clock: a function returning ms.
  property var clock: null

  // spec: { action, domain, backupId, label, live }.
  // -> { ok: true, pending: "confirm", id } or confirm_open | recently_declined.
  function request(spec) {
    if (internal.pending || root.dialogOpen) return Errors.confirmOpen()
    const now = internal.now()
    if (internal.declinedAt > 0 && now - internal.declinedAt < internal.declineHoldMs)
      return Errors.recentlyDeclined()
    internal.seq++
    internal.pending = {
      id: String(now) + "-" + internal.seq,
      action: String(spec.action), domain: spec.domain || null, backupId: spec.backupId || null,
      label: spec.label || null, live: spec.live === true
    }
    expiry.restart()
    return { ok: true, pending: "confirm", id: internal.pending.id }
  }

  // -> { ok: true, accepted, spec } or no_pending.
  function resolve(id, accepted) {
    const p = internal.pending
    if (!p || p.id !== id) return Errors.noPending()
    internal.pending = null
    expiry.stop()
    if (!accepted) internal.declinedAt = internal.now()
    return { ok: true, accepted: accepted === true, spec: p }
  }

  // A store was removed: its pending request is void.
  function clear(domain) {
    if (internal.pending && internal.pending.domain === domain) {
      internal.pending = null
      expiry.stop()
    }
  }

  function setDialogOpen(ownerKey, open) {
    const key = String(ownerKey || "")
    const next = Object.assign({}, internal.dialogOwners)
    if (open) next[key] = true
    else delete next[key]
    internal.dialogOwners = next
  }

  // -> true when the panel just opened (closed -> open).
  function setPanelOpen(ownerKey, open) {
    const key = String(ownerKey || "")
    const was = internal.panelOpen
    if (open) internal.panelOwners[key] = true
    else { delete internal.panelOwners[key]; root.setDialogOpen(key, false) }
    internal.panelOpen = Object.keys(internal.panelOwners).length > 0
    return internal.panelOpen && !was
  }

  QtObject {
    id: internal
    readonly property int declineHoldMs: 30000
    property var pending: null
    property var dialogOwners: ({})
    property var panelOwners: Object.create(null)
    property bool panelOpen: false
    // When the user last declined a request (ms), 0 for never.
    property real declinedAt: 0
    property int seq: 0

    function now() {
      return typeof root.clock === "function" ? root.clock() : Date.now()
    }
  }

  // A request nobody answers expires after 120 s.
  Timer {
    id: expiry
    interval: 120000
    repeat: false
    onTriggered: internal.pending = null
  }
}
