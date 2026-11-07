// js/themes.mjs: the theme-state shapes, the reducers ThemeInfo runs on a
// helper's result, and the selectors over a themeState.
import assert from "node:assert/strict"
import * as T from "../../js/themes.mjs"

assert.deepEqual(T.emptyFolder(), { status: "unknown", requested: "", exists: false, themeShaped: false, empty: false, safe: false, reason: null, rootFiles: [], error: null })
assert.deepEqual(T.emptyThemeState(), { themes: { status: "idle", items: [], fetchedAt: 0, error: null }, folder: T.emptyFolder(),
  backups: { status: "idle", items: [], folderCopies: [], error: null } })
assert.deepEqual(T.emptyPreview(), { status: "stopped", url: "", error: null })
assert.deepEqual(T.emptyThemes(), T.emptyThemeState().themes)
assert.deepEqual(T.emptyBackups(), T.emptyThemeState().backups)

// reduceThemes
const loading = { status: "loading", items: [{ id: "1", name: "Old", role: "live" }], fetchedAt: 5, error: null }
let th = T.reduceThemes(loading, { ok: true, themes: [{ id: "1", name: "Dawn", role: "live", processing: false }, { id: 2, name: "Dev", role: "unpublished" }, "junk", { name: "no id" }, null] }, 99)
assert.deepEqual(th, { status: "ok", items: [{ id: "1", name: "Dawn", role: "live", processing: false }, { id: 2, name: "Dev", role: "unpublished" }], fetchedAt: 99, error: null }, "rows without an id are dropped")
assert.deepEqual(T.reduceThemes(loading, { ok: true, themes: "nope" }, 1).items, [], "a non-list reads as empty")
th = T.reduceThemes(loading, { ok: false, error: { code: "rate_limited", message: "slow", retryAfter: 30 } }, 99)
assert.deepEqual(th, { status: "error", items: loading.items, fetchedAt: 5, error: { code: "rate_limited", message: "slow", retryAfter: 30 } }, "a failure keeps the cached list")
assert.equal(T.reduceThemes(loading, { ok: false }, 1).error.code, "cli_failed")

// reduceBackups
const theme = { id: "1", name: "Dawn", role: "live" }
let bk = T.reduceBackups(T.emptyBackups(), { ok: true, backups: [{ id: "1762500000-1", at: 1, theme: theme, before: "push" }, { id: "1762500001-1", at: 2 }], folderCopies: [{ id: "1762500002", path: "/p" }, { path: "/no-id" }] })
assert.deepEqual(bk.items.map(b => b.id), ["1762500000-1"], "a backup row needs its theme")
assert.deepEqual(bk.folderCopies.map(c => c.id), ["1762500002"])
assert.equal(bk.status, "ok")
bk = T.reduceBackups(bk, { ok: false, error: { code: "timeout", message: "" } })
assert.equal(bk.status, "error")
assert.equal(bk.items.length, 1, "a failure keeps the last list")
assert.equal(bk.error.code, "timeout")

// reduceFolder
let fo = T.reduceFolder("/home/u/acme", { ok: true, exists: true, themeShaped: true, empty: false, safe: false, reason: "x".repeat(60), rootFiles: ["AGENTS.md", "evil.md", "DESIGN.md"] })
assert.deepEqual(fo, { status: "ok", requested: "/home/u/acme", exists: true, themeShaped: true, empty: false, safe: false, reason: "x".repeat(40), rootFiles: ["AGENTS.md", "DESIGN.md"], error: null })
assert.equal(T.reduceFolder("/f", { ok: true, exists: "yes" }).exists, false, "only true is true")
assert.deepEqual(T.reduceFolder("/f", { ok: true, rootFiles: "AGENTS.md" }).rootFiles, [])
fo = T.reduceFolder("/f", { ok: false, error: { code: "unsafe_folder", message: "m", reason: "symlink" } })
assert.deepEqual(fo, Object.assign(T.emptyFolder(), { status: "error", requested: "/f", error: { code: "unsafe_folder", message: "m", reason: "symlink" } }))

// Selectors take a themeState.
const ts = {
  themes: { status: "ok", items: [{ id: "1", name: "Dawn", role: "live" }, { id: "2", name: "Dev", role: "unpublished" }], fetchedAt: 1, error: null },
  folder: Object.assign(T.emptyFolder(), { status: "ok", requested: "/home/u/acme", safe: false }),
  backups: { status: "ok", items: [{ id: "1762500000-1", at: 1, theme: { id: "1", name: "Dawn", role: "live" }, before: "push" }, { id: "1762500000-2", at: 1, theme: { id: "2", name: "Dev", role: "unpublished" }, before: "restore" }], folderCopies: [], error: null }
}
assert.deepEqual(T.themeById(ts, "2"), { id: "2", name: "Dev", role: "unpublished" })
assert.deepEqual(T.themeById(ts, 1), { id: "1", name: "Dawn", role: "live" })
assert.equal(T.themeById(ts, "9"), null)
assert.equal(T.themeById(null, "1"), null)
assert.equal(T.backupById(ts, "1762500000-1").before, "push")
assert.equal(T.backupById(ts, "x"), null)
assert.equal(T.backupById(null, "x"), null)
assert.deepEqual(T.targetOf({ target: "live" }, ts), { id: "1", name: "Dawn", live: true })
assert.deepEqual(T.targetOf({ target: "2" }, ts), { id: "2", name: "Dev", live: false })
assert.deepEqual(T.targetOf({ target: "9" }, ts), { id: "9", name: "", live: false })
assert.deepEqual(T.targetOf({ target: "live" }, null), { id: "", name: "", live: true }, "no themes list yet")
assert.deepEqual(T.targetOf(null, ts), { id: "1", name: "Dawn", live: true })

// Backup ids: <epoch>-<themeId>.
assert(T.EPOCH_RE.test("1762500000") && !T.EPOCH_RE.test("0762500000") && !T.EPOCH_RE.test("17625000001"))
assert(T.BACKUP_ID_RE.test("1762500000-160258293983") && !T.BACKUP_ID_RE.test("1762500000") && !T.BACKUP_ID_RE.test("../1762500000-1"))
assert.deepEqual(T.parseBackupId("1762500000-160258293983"), { epochMs: 1762500000000, themeId: "160258293983" })
for (const bad of ["", null, "1762500000", "x-1", "1762500000-0"]) assert.equal(T.parseBackupId(bad), null, String(bad))

// restoreIsLive: the row says live, or the row's theme (else the id's) is
// live in the themes list now.
assert.equal(T.restoreIsLive(ts, "1762500000-1"), true, "taken from the live theme")
assert.equal(T.restoreIsLive(ts, "1762500000-2"), false)
assert.equal(T.restoreIsLive(ts, "nope"), false)
assert.equal(T.restoreIsLive(ts, "1762500009-1"), true, "no row: the id's theme is live now")
assert.equal(T.restoreIsLive(ts, "1762500009-2"), false)
const published = Object.assign({}, ts, { themes: Object.assign({}, ts.themes, { items: [{ id: "1", name: "Dawn", role: "unpublished" }, { id: "2", name: "Dev", role: "live" }] }) })
assert.equal(T.restoreIsLive(published, "1762500000-2"), true, "a theme that became live since")
assert.equal(T.restoreIsLive(published, "1762500000-1"), true, "a row taken from the live theme stays live")
assert.equal(T.restoreIsLive(null, "1762500000-1"), false)

// folderState / inspectionOf / rootFiles read only an inspection of that folder.
const fold = (f) => Object.assign({}, ts, { folder: Object.assign(T.emptyFolder(), { status: "ok", requested: "/f" }, f) })
assert.equal(T.folderState(null, "/f"), "unknown")
assert.equal(T.folderState(fold({ status: "loading" }), "/f"), "unknown")
assert.equal(T.folderState(fold({ exists: true, safe: true, themeShaped: true }), "/other"), "unknown", "another folder's inspection")
assert.equal(T.folderState(fold({ status: "error", error: { code: "timeout", message: "" } }), "/f"), "error")
assert.equal(T.folderState(fold({ exists: false }), "/f"), "missing")
assert.equal(T.folderState(fold({ exists: false, reason: "not_absolute" }), "/f"), "unsafe", "a reason without a folder is unsafe")
assert.equal(T.folderState(fold({ exists: true, safe: false, reason: "symlink" }), "/f"), "unsafe")
assert.equal(T.folderState(fold({ exists: true, safe: true, themeShaped: true }), "/f"), "usable")
assert.equal(T.folderState(fold({ exists: true, safe: true, empty: true }), "/f"), "empty")
assert.equal(T.folderState(fold({ exists: true, safe: true }), "/f"), "notTheme")
assert.equal(T.inspectionOf(fold({ exists: true }), "/f").requested, "/f")
assert.equal(T.inspectionOf(fold({ status: "error" }), "/f"), null)
assert.deepEqual(T.rootFiles(fold({ rootFiles: ["AGENTS.md"] }), "/f"), ["AGENTS.md"])
assert.deepEqual(T.rootFiles(fold({}), "/f"), [])
assert.equal(T.rootFiles(fold({ rootFiles: ["AGENTS.md"] }), "/other"), null, "not inspected yet")
