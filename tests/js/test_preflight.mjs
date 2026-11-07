// js/preflight.mjs: every refusal and blocking rule, over plain facts (the
// Service's, gathered by model/Preflight.qml) and over the snapshot (the
// panel's, via factsOf), so the two can never disagree.
import assert from "node:assert/strict"
import * as P from "../../js/preflight.mjs"
import * as T from "../../js/themes.mjs"

const code = r => r ? r.error.code : null

const READY = { cliStatus: "ready", accountStatus: "signed_in" }
const f = extra => Object.assign({}, READY, extra)
const CFG = { domain: "acme.myshopify.com", label: "Acme", showInBar: true, theme: { folder: "/home/u/acme", target: "live", allowLive: false } }

// ---- storeLookupFailed / requireCli / requireAccountIdle ----
assert.equal(code(P.storeLookupFailed({})), "unknown_store")
assert.equal(code(P.storeLookupFailed(null)), "unknown_store")
assert.deepEqual(P.storeLookupFailed({ configError: { code: "config_invalid", message: "bad" } }).error, { code: "config_invalid", message: "bad" })
// One answer per CLI state: only a missing CLI (or a failed install) says
// it isn't installed; anything not yet known is still checking.
const cliAnswers = { ready: null, checking: "cli_checking", unknown: "cli_checking", installing: "cli_installing", missing: "cli_missing", install_failed: "cli_missing" }
for (const st of Object.keys(cliAnswers)) assert.equal(code(P.requireCli({ cliStatus: st })), cliAnswers[st], st)
assert.equal(code(P.requireCli({})), "cli_checking", "no CLI status yet")
assert.equal(P.requireCli({ cliStatus: "missing", cliMissing: "node" }).error.missing, "node")
assert.equal(P.requireCli({ cliStatus: "missing" }).error.missing, undefined)
// Signed out is no rule (the CLI's stored theme tokens may still work); a
// sign-in or sign-out in flight is.
for (const st of ["signed_in", "signed_out", "unknown"]) assert.equal(P.requireAccountIdle({ accountStatus: st }), null, st)
for (const st of ["signing_in", "signing_out"]) assert.equal(code(P.requireAccountIdle({ accountStatus: st })), "account_busy", st)

// ---- requireThemesIdle / requireResetIdle: any store ----
assert.equal(P.requireThemesIdle({}), null)
assert.deepEqual(P.requireThemesIdle({ anyJob: true, anyPreview: true }).error, { code: "store_busy", message: "Wait for the running theme action to finish", what: "job", anyStore: true })
assert.equal(P.requireThemesIdle({ anyPreview: true }).error.what, "preview")
assert.equal(P.requireThemesIdle({ anyGrant: true }), null, "a grant does not hold the account session")
assert.equal(P.requireResetIdle({ anyGrant: true }).error.what, "access")
assert.equal(P.requireResetIdle({ anyJob: true, anyGrant: true }).error.what, "job")
assert.equal(P.requireResetIdle({}), null)

// ---- requireStoreIdle: names the work, and what a preview blocks ----
assert.equal(P.requireStoreIdle({}), null)
assert.equal(P.requireStoreIdle({ previewStatus: "failed" }), null)
assert.equal(P.requireStoreIdle({ previewStatus: "stopped" }), null)
let r = P.requireStoreIdle({ job: { action: "pull" }, previewStatus: "ready", granting: true }, "push").error
assert.deepEqual([r.code, r.action, r.blocked], ["store_busy", "pull", undefined], "a job first")
r = P.requireStoreIdle({ previewStatus: "ready", granting: true }, "push").error
assert.deepEqual([r.action, r.blocked], ["preview", "push"], "a ready preview blocks a push: stop it first")
r = P.requireStoreIdle({ previewStatus: "starting" }, "restore").error
assert.equal(r.blocked, "restore")
r = P.requireStoreIdle({ previewStatus: "stopping" }, "push").error
assert.deepEqual([r.action, r.blocked], ["preview", undefined], "a stopping preview: wait for it")
r = P.requireStoreIdle({ previewStatus: "ready" }, "remove").error
assert.equal(r.blocked, undefined, "only push, pull and restore are blocked by name")
r = P.requireStoreIdle({ previewStatus: "ready" }, "preview").error
assert.deepEqual([r.action, r.blocked], ["preview", undefined])
assert.equal(P.requireStoreIdle({ granting: true }, "pull").error.action, "grant")

// ---- checkThemeAction: CLI, then the account, then the store ----
for (const action of ["push", "pull", "restore", "preview"]) {
  assert.equal(P.checkThemeAction(f({}), action), null, action)
  assert.equal(P.checkThemeAction(f({ accountStatus: "signed_out" }), action), null, action + " while signed out")
  assert.equal(code(P.checkThemeAction(f({ accountStatus: "signing_in" }), action)), "account_busy", action + " while signing in")
  assert.equal(code(P.checkThemeAction(f({ accountStatus: "signing_out" }), action)), "account_busy", action + " while signing out")
  assert.equal(P.checkThemeAction(f({ granting: true }), action).error.action, "grant", action + " during a grant")
  for (const st of Object.keys(cliAnswers)) assert.equal(code(P.checkThemeAction(f({ cliStatus: st }), action)), cliAnswers[st], action + " with the CLI " + st)
}
assert.equal(code(P.checkThemeAction(f({ cliStatus: "missing", accountStatus: "signing_in", job: { action: "push" } }), "push")), "cli_missing", "the CLI comes first")
assert.equal(code(P.checkThemeAction(f({ accountStatus: "signing_in", job: { action: "push" } }), "push")), "account_busy", "then the account")

// ---- checkPush / checkPull / checkPreview / checkRestore: what the Service checks on accept ----
for (const check of [P.checkPull, P.checkPreview, P.checkPush]) {
  assert.equal(code(check(f({ store: null }))), "unknown_store")
  assert.equal(code(check(f({ store: null, configError: { code: "config_unsupported", message: "old" } }))), "config_unsupported")
  assert.equal(code(check(f({ store: Object.assign({}, CFG, { theme: null }), cliStatus: "missing" }))), "no_theme_folder", "the folder before the CLI")
  assert.equal(code(check(f({ store: Object.assign({}, CFG, { theme: { folder: "", target: "live" } }) }))), "no_theme_folder")
  assert.equal(check(f({ store: CFG })), null, "an unknown folder state is no refusal")
  assert.equal(check(f({ store: CFG, folderState: "usable" })), null)
  for (const st of ["missing", "unsafe", "notTheme", "error"]) {
    const e = check(f({ store: CFG, folderState: st })).error
    assert.deepEqual([e.code, e.state], ["folder_unusable", st], st)
  }
  assert.equal(code(check(f({ store: CFG, folderState: "unsafe", job: { action: "pull" } }))), "store_busy", "busy before the folder")
}
// An empty folder is a pull target only (ThemeFolder.check!).
assert.equal(P.checkPull(f({ store: CFG, folderState: "empty" })), null)
assert.deepEqual(P.checkPush(f({ store: CFG, folderState: "empty" })).error.action, "push")
assert.deepEqual(P.checkPreview(f({ store: CFG, folderState: "empty" })).error.state, "empty")
assert.equal(P.checkPreview(f({ store: CFG, previewStatus: "ready" })).error.blocked, undefined, "a preview on a preview: wait")
assert.equal(P.checkPull(f({ store: CFG, previewStatus: "ready" })).error.blocked, "pull")
assert.equal(code(P.checkPush(f({ store: CFG, targetLive: true }))), "live_not_allowed")
const ALLOW = Object.assign({}, CFG, { theme: Object.assign({}, CFG.theme, { allowLive: true }) })
assert.equal(P.checkPush(f({ store: ALLOW, targetLive: true })), null)
assert.equal(P.checkPush(f({ store: CFG, previewStatus: "starting", targetLive: true })).error.blocked, "push", "busy before live")
assert.equal(code(P.checkPush(f({ store: CFG, folderState: "unsafe", targetLive: true }))), "folder_unusable", "the folder before live")
assert.equal(code(P.checkRestore(f({ store: null, backupId: "1762500000-1" }))), "unknown_store")
assert.equal(code(P.checkRestore(f({ store: CFG, backupId: "nope" }))), "invalid_argument")
assert.equal(code(P.checkRestore(f({ store: CFG }))), "invalid_argument", "no backup id")
assert.equal(code(P.checkRestore(f({ store: CFG, cliStatus: "checking", backupId: "nope" }))), "invalid_argument", "the id before the CLI")
assert.equal(P.checkRestore(f({ store: CFG, backupId: "1762500000-1" })), null)
assert.equal(code(P.checkRestore(f({ store: CFG, backupId: "1762500000-1", backupLive: true }))), "live_not_allowed")
assert.equal(P.checkRestore(f({ store: ALLOW, backupId: "1762500000-1", backupLive: true })), null)
assert.equal(P.checkRestore(f({ store: Object.assign({}, CFG, { theme: null }), backupId: "1762500000-1", backupLive: false })), null, "a restore needs no folder")
assert.equal(code(P.checkRestore(f({ store: Object.assign({}, CFG, { theme: null }), backupId: "1762500000-1", backupLive: true }))), "live_not_allowed")
assert.equal(P.checkRestore(f({ store: CFG, backupId: "1762500000-1", previewStatus: "ready" })).error.blocked, "restore")

// ---- liveAllowed / liveLocked ----
assert.equal(P.liveAllowed(f({ store: CFG })), false)
assert.equal(P.liveAllowed(f({ store: ALLOW })), true)
assert.equal(P.liveAllowed(f({})), false)
assert.equal(P.liveLocked(f({ store: CFG, targetLive: true }), "push"), true)
assert.equal(P.liveLocked(f({ store: CFG, targetLive: true }), "restore"), false, "a restore reads backupLive")
assert.equal(P.liveLocked(f({ store: CFG, backupLive: true }), "restore"), true)
assert.equal(P.liveLocked(f({ store: ALLOW, targetLive: true }), "push"), false)

// ---- beforeDialog: what the service would refuse on accept, live aside ----
assert.equal(P.beforeDialog(f({ store: CFG, targetLive: true }), "push"), null, "the live opt-in is the dialog's first stage")
assert.equal(code(P.beforeDialog(f({ store: CFG, folderState: "empty" }), "push")), "folder_unusable")
assert.equal(P.beforeDialog(f({ store: CFG, folderState: "empty" }), "pull"), null)
assert.equal(P.beforeDialog(f({ store: CFG, backupId: "1762500000-1", backupLive: true }), "restore"), null)
assert.equal(code(P.beforeDialog(f({ store: CFG, backupId: "x" }), "restore")), "invalid_argument")
assert.equal(code(P.beforeDialog(f({ store: null }), "remove")), "unknown_store")
assert.equal(P.beforeDialog(f({ store: CFG, previewStatus: "ready" }), "remove").error.action, "preview")
assert.equal(P.beforeDialog(f({ store: CFG, cliStatus: "missing" }), "remove"), null, "remove needs no CLI")
assert.equal(code(P.beforeDialog(f({ cliStatus: "missing" }), "signOut")), "cli_missing")
assert.equal(P.beforeDialog(f({ anyPreview: true }), "signOut").error.what, "preview")
assert.equal(P.beforeDialog(f({ anyGrant: true }), "signOut"), null)
assert.equal(P.beforeDialog(f({ anyGrant: true }), "resetConfig").error.what, "access")
assert.equal(P.beforeDialog(f({ cliStatus: "missing" }), "installCli"), null)

// ---- factsOf: the snapshot's view of the same facts ----
const ts = extra => Object.assign(T.emptyThemeState(), { job: null, lastResult: null, preview: T.emptyPreview() }, extra)
const store = (extra, tsExtra) => Object.assign({ domain: CFG.domain, label: "Acme", theme: CFG.theme, salesAccess: "granted", sales: { status: "ok", today: { sales: 10, orders: 1 } }, themeState: ts(tsExtra) }, extra)
const snapshot = extra => Object.assign({ configError: null, configWriteError: null, stateError: null, cli: { status: "ready", missing: null }, account: { status: "signed_in" }, themesBusy: "", granting: false, stores: {} }, extra)
let facts = P.factsOf(snapshot({}), store({}, { job: { action: "push" }, preview: { status: "ready" } }))
assert.equal(facts.job.action, "push")
assert.equal(facts.previewStatus, "ready")
assert.equal(facts.granting, false)
assert.equal(P.factsOf(snapshot({}), store({ salesAccess: "granting" })).granting, true)
facts = P.factsOf(snapshot({ themesBusy: "preview", granting: true, cli: { status: "missing", missing: "cli" } }), null)
assert.deepEqual([facts.anyJob, facts.anyPreview, facts.anyGrant, facts.cliStatus, facts.cliMissing, facts.store, facts.previewStatus], [false, true, true, "missing", "cli", null, "stopped"])
assert.equal(P.factsOf(null, null).cliStatus, "unknown")
assert.equal(P.factsOf(null, null).accountStatus, "unknown")
// The theme facts: the folder state, a live target, a live restore.
const inspected = { folder: Object.assign(T.emptyFolder(), { status: "ok", requested: CFG.theme.folder, exists: true, safe: true, empty: true }),
  themes: { status: "ok", items: [{ id: "1", name: "Dawn", role: "live" }, { id: "2", name: "Dev", role: "unpublished" }], fetchedAt: 1, error: null } }
facts = P.factsOf(snapshot({}), store({}, inspected))
assert.deepEqual([facts.folderState, facts.targetLive, "backupId" in facts], ["empty", true, false])
assert.equal(P.factsOf(snapshot({}), store({ theme: { folder: "/other", target: "2" } }, inspected)).folderState, "unknown", "another folder's inspection")
assert.equal(P.factsOf(snapshot({}), store({ theme: { folder: "/x", target: "2" } }, inspected)).targetLive, false)
assert.equal(P.factsOf(snapshot({}), store({ theme: null }, inspected)).targetLive, false, "no theme config: no target")
facts = P.factsOf(snapshot({}), store({}, inspected), "1762500000-1")
assert.deepEqual([facts.backupId, facts.backupLive], ["1762500000-1", true], "the id's theme is live now")
assert.equal(P.factsOf(snapshot({}), store({}, inspected), "1762500000-2").backupLive, false)
assert.deepEqual(P.themeFacts(CFG, null), { folderState: "unknown", targetLive: true }, "live by name before the list loads")
// The panel and the Service answer alike: a running pull refuses a push
// with the same error from either side, and an empty folder refuses it the same.
assert.deepEqual(P.checkPush(P.factsOf(snapshot({}), store({}, { job: { action: "pull" } }))),
  P.checkPush(f({ store: CFG, job: { action: "pull" } })))
assert.deepEqual(P.beforeDialog(P.factsOf(snapshot({}), store({}, inspected)), "push"),
  P.checkPush(f({ store: Object.assign({}, CFG, { theme: Object.assign({}, CFG.theme, { allowLive: true }) }), folderState: "empty" })))
assert.deepEqual(P.requireResetIdle(P.factsOf(snapshot({ themesBusy: "job" }), null)), P.requireResetIdle({ anyJob: true }))
