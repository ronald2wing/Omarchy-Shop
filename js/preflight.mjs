// Every refusal and blocking rule, in one place: pure functions over a
// plain facts object. The Service checks them before it starts anything
// (model/Preflight.qml gathers the facts from the models), and the panel
// checks the same functions over the snapshot (factsOf) so it refuses
// before a dialog opens and its buttons, tooltips and keys say the same
// thing. Each check returns the {ok: false, error} result (Results.*; the UI
// renders it with Copy.errorOf) or null when the action may run.
//
// facts (every field optional; missing means "nothing known against it"):
//   configError    ConfigStore's configError, or null
//   cliStatus      cli.status (unknown|checking|ready|missing|installing|install_failed)
//   cliMissing     cli.missing ("node" | "cli" | null)
//   accountStatus  account.status
//   anyJob         a push, pull or restore runs on any store
//   anyPreview     a preview runs (starting to stopping) on any store
//   anyGrant       a sales-access grant runs on any store
//   store          the store's config entry (or snapshot store), or null
//   job            the store's running theme job ({action}), or null
//   previewStatus  the store's preview status (stopped|starting|ready|stopping|failed)
//   granting       a sales-access grant runs for the store
//   folderState    Themes.folderState of the store's folder (unknown|usable|
//                  empty|missing|unsafe|notTheme|error)
//   targetLive     the store's target theme is the live theme
//   backupId       (restore) the backup to restore
//   backupLive     (restore) Themes.restoreIsLive of that backup
// themeFacts builds the last four from a themeState, for both sides.
import * as Results from "./results.mjs"
import { accountStatus, cliStatus, themeState } from "./snapshot.mjs"
import { folderState, parseBackupId, restoreIsLive, targetOf } from "./themes.mjs"

const THEME_ACTIONS = ["push", "pull", "restore"]

function previewHolds(status) {
  return status === "starting" || status === "ready" || status === "stopping"
}

// The facts read from a store's theme state (ThemeInfo's, or the
// snapshot's themeState): folderState, targetLive, and for a restore
// backupId and backupLive.
export function themeFacts(store, ts, backupId) {
  const theme = store && store.theme ? store.theme : null
  const out = {
    folderState: theme && theme.folder ? folderState(ts, theme.folder) : "unknown",
    targetLive: !!theme && targetOf(theme, ts).live
  }
  if (backupId !== undefined && backupId !== null) {
    out.backupId = String(backupId)
    out.backupLive = restoreIsLive(ts, out.backupId)
  }
  return out
}

// Why a domain has no config entry: config.json is unreadable (its stores
// are unknown, not gone), else the store really isn't in Shop.
export function storeLookupFailed(f) {
  return f && f.configError ? Results.configInvalid(f.configError) : Results.unknownStore()
}

// The pinned CLI is ready.
export function requireCli(f) {
  const s = f.cliStatus
  if (s === "ready") return null
  if (s === "installing") return Results.cliInstalling()
  if (s === "missing" || s === "install_failed") return Results.cliMissing(f.cliMissing || null)
  return Results.cliChecking()
}

// No sign-in or sign-out in flight: theme commands read their token from
// the account session those rewrite. Why, and why signed out is no
// refusal: CONTRIBUTING › Error and exit codes (account_busy).
export function requireAccountIdle(f) {
  const s = f.accountStatus
  return s === "signing_in" || s === "signing_out" ? Results.accountBusy("Signing in or out") : null
}

// The mirror of requireAccountIdle: a push, pull, restore or preview on any
// store holds the account session, so sign-in and sign-out wait.
export function requireThemesIdle(f) {
  if (f.anyJob) return Results.anyStoreBusy("job")
  if (f.anyPreview) return Results.anyStoreBusy("preview")
  return null
}

// Nothing holds the store: a theme job, a preview or a sales-access grant.
// action (optional): what is asking (push | pull | restore | preview |
// remove ...). The error names the work that holds the store, and a
// starting or ready preview in the way of a push, pull or restore says the
// fix is to stop it (`blocked`).
export function requireStoreIdle(f, action) {
  if (f.job) return Results.storeBusy(String(f.job.action || ""))
  if (previewHolds(f.previewStatus)) {
    const blocks = THEME_ACTIONS.indexOf(action) >= 0 && f.previewStatus !== "stopping"
    return Results.storeBusy("preview", blocks ? action : "")
  }
  if (f.granting) return Results.storeBusy("grant")
  return null
}

// Reset config forgets every store, which stops its helpers: refused while
// a theme job or preview runs on any store, or a grant does.
export function requireResetIdle(f) {
  return requireThemesIdle(f) || (f.anyGrant ? Results.anyStoreBusy("grant") : null)
}

// What every theme action (push | pull | preview | restore) needs: the
// CLI, no sign-in or sign-out in flight, and the store to itself. Stopping
// a running preview is not a theme action (never refused).
export function checkThemeAction(f, action) {
  return requireCli(f) || requireAccountIdle(f) || requireStoreIdle(f, action)
}

// The store's opt-in to live theme changes (theme.allowLive).
export function liveAllowed(f) {
  return !!(f.store && f.store.theme && f.store.theme.allowLive === true)
}

// A push (or, with action "restore", a restore of facts.backupId) changes
// the live theme while the opt-in is off: refused with live_not_allowed,
// and the panel asks to allow it first.
export function liveLocked(f, action) {
  const live = action === "restore" ? f.backupLive === true : f.targetLive === true
  return live && !liveAllowed(f)
}

// The folder rules the helpers apply (ThemeFolder.check!), from the last
// inspection: a missing, unsafe or not theme-shaped folder (or one the
// inspection failed on) can't be used at all; an empty one only as a pull
// target. An unknown state is no refusal: the helper checks it again.
function checkFolder(f, action) {
  const s = f.folderState
  if (s === "missing" || s === "unsafe" || s === "notTheme" || s === "error") return Results.folderUnusable(action, s)
  if (s === "empty" && action !== "pull") return Results.folderUnusable(action, s)
  return null
}

// A push, pull or preview: the store, its linked folder, the theme action
// and the folder rules, in that order.
function checkFolderAction(f, action) {
  const store = f.store
  if (!store) return storeLookupFailed(f)
  if (!store.theme || !store.theme.folder) return Results.noThemeFolder()
  return checkThemeAction(f, action) || checkFolder(f, action)
}

export function checkPull(f) {
  return checkFolderAction(f, "pull")
}

export function checkPreview(f) {
  return checkFolderAction(f, "preview")
}

// A push: the folder action, plus a live target needs the store's
// theme.allowLive (the live dialog then adds --confirm-live).
export function checkPush(f) {
  return checkFolderAction(f, "push") || (liveLocked(f, "push") ? Results.liveNotAllowed() : null)
}

// A restore of f.backupId (the store needs no folder): a well-formed id,
// the theme action, and the live opt-in for a backup that counts as live.
function checkRestoreAction(f) {
  if (!f.store) return storeLookupFailed(f)
  if (!parseBackupId(f.backupId)) return Results.invalidBackupId()
  return checkThemeAction(f, "restore")
}

export function checkRestore(f) {
  return checkRestoreAction(f) || (liveLocked(f, "restore") ? Results.liveNotAllowed() : null)
}

// What the service would refuse on accepting `action`'s dialog (push |
// pull | restore | remove | signOut | resetConfig), checked before the
// dialog opens. The live opt-in is not checked here: the panel asks to
// allow live changes as the dialog's first stage.
export function beforeDialog(f, action) {
  if (action === "push") return checkFolderAction(f, "push")
  if (action === "pull") return checkPull(f)
  if (action === "restore") return checkRestoreAction(f)
  if (action === "remove") return f.store ? requireStoreIdle(f, "remove") : storeLookupFailed(f)
  if (action === "signOut") return requireCli(f) || requireThemesIdle(f)
  if (action === "resetConfig") return requireResetIdle(f)
  return null
}

// ---- the panel's view: the same facts, read from the snapshot -------------

// facts for one snapshot store (or null for account-level checks); backupId
// for a restore. The snapshot's top-level themesBusy/granting count work
// on stores it no longer lists (config.json unreadable).
export function factsOf(snapshot, store, backupId) {
  const s = snapshot || {}
  const ts = themeState(store)
  return Object.assign({
    configError: s.configError || null,
    cliStatus: cliStatus(s),
    cliMissing: s.cli && s.cli.missing ? s.cli.missing : null,
    accountStatus: accountStatus(s),
    anyJob: s.themesBusy === "job",
    anyPreview: s.themesBusy === "preview",
    anyGrant: s.granting === true,
    store: store || null,
    job: ts && ts.job ? ts.job : null,
    previewStatus: ts && ts.preview ? String(ts.preview.status || "stopped") : "stopped",
    granting: !!store && store.salesAccess === "granting"
  }, themeFacts(store, ts, backupId))
}
