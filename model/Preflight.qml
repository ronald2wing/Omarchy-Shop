pragma ComponentBehavior: Bound
import QtQuick
import "../js/preflight.mjs" as Rules

// The refusals the Service checks before it starts anything. The rules are
// js/preflight.mjs (the panel checks the same functions over the snapshot);
// this only gathers their facts from the models. Each check returns the
// {ok: false} result to hand back, or null when the action may run. A
// request* runs the same check as the action it confirms, so a dialog
// never opens for an action that can only fail on accept.
Item {
  id: root

  required property Account account
  required property ConfigStore configStore
  required property Previews previews
  required property SalesAccess salesAccess
  required property ThemeInfo themeInfo
  required property ThemeJobs themeJobs

  // The facts js/preflight.mjs reads; store: the config entry or null;
  // backupId: the backup a restore would push, when checking one.
  function facts(store, backupId) {
    const d = store ? store.domain : ""
    const job = d ? root.themeJobs.stateFor(d) : null
    const ps = d ? root.previews.stateFor(d) : null
    return Object.assign({
      configError: root.configStore.configError,
      cliStatus: root.account.cli.status,
      cliMissing: root.account.cli.missing,
      accountStatus: root.account.account.status,
      anyJob: root.themeJobs.busyAny(),
      anyPreview: root.previews.runningAny(),
      anyGrant: root.salesAccess.grantingAny(),
      store: store || null,
      job: job && job.job ? job.job : null,
      // Previews keeps "stopping" until the stream has ended (the helper
      // holds the store's lock until then).
      previewStatus: ps ? String(ps.status || "stopped") : "stopped",
      granting: !!d && root.salesAccess.isGranting(d)
    }, Rules.themeFacts(store, d ? root.themeInfo.stateFor(d) : null, backupId))
  }

  function storeLookupFailed() { return Rules.storeLookupFailed(root.facts(null)) }
  function requireCli() { return Rules.requireCli(root.facts(null)) }
  function requireThemesIdle() { return Rules.requireThemesIdle(root.facts(null)) }
  function requireResetIdle() { return Rules.requireResetIdle(root.facts(null)) }
  // store: a config entry (never null).
  function requireStoreIdle(store) { return Rules.requireStoreIdle(root.facts(store)) }
  function checkPush(store) { return Rules.checkPush(root.facts(store)) }
  function checkPull(store) { return Rules.checkPull(root.facts(store)) }
  function checkPreview(store) { return Rules.checkPreview(root.facts(store)) }
  function checkRestore(store, backupId) { return Rules.checkRestore(root.facts(store, backupId === undefined ? "" : backupId)) }
}
