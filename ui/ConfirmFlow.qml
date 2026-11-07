pragma ComponentBehavior: Bound
import QtQuick
import "../js/confirm.mjs" as Confirm
import "../js/preflight.mjs" as Preflight
import "../js/snapshot.mjs" as Snapshot

// The panel's confirmations: turns a request (a view's push, pull,
// restore, remove, installCli, signOut or resetConfig, or an IPC request*)
// into the Dialog it shows, runs the accepted request, and closes a dialog
// whose subject went away. ShopPanel holds one, filling the panel above
// the views and the key sheet.
//
// Contract:
//   panel                ShopPanel: opened, service, snapshot, home, run(),
//                        showToast(), restoreFocus(), navigate(), pop(),
//                        viewName, hideKeySheet(), ownerKey
//   confirm(spec)        spec is a request {action, domain?, backupId?, live?}
//                        expanded by Confirm.confirmSpec(). Returns false when
//                        the panel is closed, a dialog is open, or the
//                        request is refused before asking
//                        (Preflight.beforeDialog: a toast says why). A live
//                        push/restore on a store with allowLive off first
//                        asks "Allow changes to the live theme?".
//   confirmPending(pc)   the same dialog for an IPC request*, resolved
//                        through the service (declined when it can't show)
//   close(accepted)      answers the open dialog (Dialog only emits accepted
//                        once armed)
//   syncWithSnapshot(s)  closes a dialog that can no longer apply
//   opened, cardHeight, activeSpec; rearm(), focusDialog()
Item {
  id: root

  property var panel: null
  property var activeSpec: null
  property string activePendingId: ""

  readonly property bool opened: dlg.opened
  readonly property real cardHeight: dlg.cardHeight

  function rearm() {
    dlg.rearm()
  }

  function focusDialog() {
    dlg.forceActiveFocus()
  }

  // A restore started from Backups: go back to the store, whose theme card
  // shows the running job (with Cancel) and its result.
  function afterRestoreStarted(res) {
    if (res && res.ok === false) return
    if (root.panel.viewName === "backups") root.panel.pop()
  }

  // The service call a panel-originated request runs once accepted.
  function runRequest(req, spec) {
    var panel = root.panel
    var svc = panel.service
    var domain = String(req.domain || "")
    var a = String(req.action)
    if (a === "push") panel.run(svc.pushTheme(domain, { confirmLive: !!spec.live }))
    else if (a === "pull") panel.run(svc.pullTheme(domain))
    else if (a === "restore") root.afterRestoreStarted(panel.run(svc.restoreBackup(domain, String(req.backupId || ""), { confirmLive: !!spec.live })))
    else if (a === "remove") {
      let res = panel.run(svc.removeStore(domain))
      if (!res || res.ok !== false) panel.navigate({ view: "home" })
    }
    else if (a === "installCli") panel.run(svc.installCli())
    else if (a === "signOut") panel.run(svc.signOut())
    else if (a === "resetConfig") panel.run(svc.resetConfig())
  }

  // Stage one of the live flow: allow live pushes, then ask again.
  function allowLiveSpec(req, store, andThen) {
    var panel = root.panel
    var domain = String(req.domain || "")
    // The request rides along: before a restore the dialog names the
    // backup's theme, not the push target.
    var allow = root.specFor({ action: "allowLive", domain: domain, forAction: String(req.action), backupId: req.backupId, live: req.live }, store)
    // The store the dialog is about: it closes if that store goes away.
    allow.domain = domain
    allow.onConfirm = function() {
      var r = panel.run(panel.service.updateStore(domain, JSON.stringify({ theme: { allowLive: true } })))
      if (r && r.ok === false) { if (typeof allow.onCancel === "function") allow.onCancel(); return }
      Qt.callLater(andThen)
    }
    return allow
  }

  // The Dialog spec for a request (js/confirm.mjs), with Copy as the lookup.
  function specFor(req, store) {
    return Confirm.confirmSpec(req, store, root.panel.home, { pins: root.panel.snapshot.pins, installs: root.panel.snapshot.cli.installs, nowMs: Date.now() })
  }

  // Opens the Dialog with a full spec. An open dialog is never replaced:
  // the call is refused (false) and the user finishes what they are
  // reading first. A closed panel never opens one: nobody would see it,
  // yet it would block every IPC request* until the panel is reopened.
  function openDialog(spec) {
    if (!root.panel.opened || dlg.opened) return false
    root.panel.hideKeySheet()
    root.activeSpec = spec
    dlg.show(spec)
    return true
  }

  // A panel request: refused before any dialog when the service would
  // refuse it on accept (js/preflight.mjs beforeDialog, over the snapshot;
  // while config.json is unreadable the snapshot lists no stores, so Sign
  // out and Reset read its top-level themesBusy/granting), else shown.
  function confirm(spec) {
    var panel = root.panel
    if (!spec || !panel || !panel.service) return false
    var store = Snapshot.storeOf(panel.snapshot, String(spec.domain || ""))
    var refused = Preflight.beforeDialog(Preflight.factsOf(panel.snapshot, store, spec.backupId), String(spec.action))
    if (refused) {
      panel.showToast(Copy.errorOf(refused.error))
      return false
    }
    return root.present(spec, "")
  }

  // A `request*` from IPC: the same dialog, resolved through the service
  // (which ran the same preflight before publishing it).
  function confirmPending(pc) {
    if (!pc || !pc.id || !root.panel.service) return
    var svc = root.panel.service
    var id = String(pc.id)
    var domain = String(pc.domain || "")
    // Load the backup rows (theme name, role, date) for later requests.
    if (pc.action === "restore") svc.listBackups(domain)
    // Another dialog is open: decline rather than replace it.
    if (dlg.opened) {
      if (root.activePendingId !== id) svc.resolvePending(id, false)
      return
    }
    root.present({ action: pc.action, domain: domain, backupId: pc.backupId, label: pc.label, live: pc.live === true }, id)
  }

  // Opens the request's dialog: a panel request (pendingId "") runs its
  // service call on accept, an IPC one (its pendingConfirm id) resolves
  // through the service with the consent it was published with, and is
  // declined whenever it can't show. A live dialog on a store whose live
  // opt-in is off first opens the allow stage, then comes back here with
  // `liveAllowed` set: the opt-in's config write is in flight, and the
  // snapshot may still say allowLive false.
  function present(req, pendingId) {
    var panel = root.panel
    var svc = panel.service
    var ipc = pendingId !== ""
    var decline = function() { if (ipc) svc.resolvePending(pendingId, false) }
    var domain = String(req.domain || "")
    var store = Snapshot.storeOf(panel.snapshot, domain)
    var full = root.specFor(req, store)
    if (!full) { decline(); return false }
    // The store the dialog is about: it closes if that store goes away.
    full.domain = domain
    var spec = full
    if (req.liveAllowed !== true && full.live && !Preflight.liveAllowed(Preflight.factsOf(panel.snapshot, store))) {
      let allowed = Object.assign({}, req, { liveAllowed: true })
      spec = root.allowLiveSpec(req, store, function() { if (ipc) root.present(allowed, pendingId); else root.confirm(allowed) })
    } else if (ipc) {
      spec.onConfirm = function() { panel.run(svc.resolvePending(pendingId, true)) }
    } else {
      spec.onConfirm = function() { root.runRequest(req, full) }
    }
    if (ipc) {
      // The dialog came unasked and took the keyboard: Ctrl+Enter only.
      spec.origin = "ipc"
      spec.onCancel = decline
    }
    var opened = root.openDialog(spec)
    if (!opened) decline()
    else if (ipc) root.activePendingId = pendingId
    return opened
  }

  function close(accepted) {
    var spec = root.activeSpec
    root.dismiss()
    if (!spec) return
    if (accepted) { if (typeof spec.onConfirm === "function") spec.onConfirm() }
    else if (typeof spec.onCancel === "function") spec.onCancel()
  }

  // Closes without running onCancel (nothing to resolve, or resolved
  // elsewhere).
  function dismiss() {
    root.activeSpec = null
    root.activePendingId = ""
    dlg.hide()
    root.panel.restoreFocus()
  }

  function syncWithSnapshot(s) {
    // A pending confirmation that expired or was resolved elsewhere.
    if (root.activePendingId !== "" && (!s.pendingConfirm || String(s.pendingConfirm.id) !== root.activePendingId)) {
      root.dismiss()
    }
    // A panel dialog about a store that was removed (elsewhere, or by a
    // config edit): accepting it could only fail. Closed without its
    // onCancel (a panel spec has no pending request to resolve). Waits
    // while config.json is unreadable: the store list is unknown then.
    if (!s.configError && dlg.opened && root.activePendingId === "" && root.activeSpec && root.activeSpec.domain
        && !Snapshot.storeOf(s, root.activeSpec.domain)) {
      root.dismiss()
    }
    // Reset config is only offered while config.json is unreadable: once
    // the file reads again (the user's fix, or the end of an editor's
    // truncate-then-write) accepting would wipe a good config.
    if (!s.configError && dlg.opened && root.activePendingId === "" && root.activeSpec && root.activeSpec.action === "resetConfig") {
      root.dismiss()
    }
  }

  Dialog {
    id: dlg
    anchors.fill: parent
    onOpenedChanged: if (root.panel.service) root.panel.service.setDialogOpen(root.panel.ownerKey, dlg.opened)
    onAccepted: root.close(true)
    onCanceled: root.close(false)
  }
}
