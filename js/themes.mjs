// A store's read-only theme state (model/ThemeInfo.qml): its shapes, the
// reducers that turn a helper result into each part, and the selectors
// over a themeState. Pure; ThemeInfo owns the processes and timers.
//
// themeState: { themes: {status, items: [{id, name, role}], fetchedAt, error},
//   folder: {status, requested, exists, themeShaped, empty, safe, reason,
//            rootFiles, error},
//   backups: {status, items: [{id, at, theme {id, name, role}, before,
//             files, bytes}], folderCopies: [{id, at, path, files, bytes}],
//             error} }
// (the snapshot adds job, lastResult and preview).
import { fromHelper } from "./errors.mjs"

// A backup id is <unix seconds>-<theme id> (Backups.take!); a folder copy's
// id, and so EPOCH_RE, is the first half alone.
export const EPOCH_RE = /^[1-9]\d{9}$/
export const BACKUP_ID_RE = /^[1-9]\d{9}-[1-9]\d{0,19}$/

// "1762500000-160258293983" -> { epochMs: 1762500000000, themeId:
// "160258293983" }; anything that is not a backup id -> null.
export function parseBackupId(id) {
  const s = typeof id === "string" ? id : ""
  if (!BACKUP_ID_RE.test(s)) return null
  const dash = s.indexOf("-")
  return { epochMs: Number(s.substring(0, dash)) * 1000, themeId: s.substring(dash + 1) }
}

export function emptyFolder() {
  return { status: "unknown", requested: "", exists: false, themeShaped: false, empty: false, safe: false, reason: null, rootFiles: [], error: null }
}

export function emptyThemes() {
  return { status: "idle", items: [], fetchedAt: 0, error: null }
}

export function emptyBackups() {
  return { status: "idle", items: [], folderCopies: [], error: null }
}

export function emptyPreview() {
  return { status: "stopped", url: "", error: null }
}

// The read-only half of a store's theme state, before anything was asked
// for the store.
export function emptyThemeState() {
  return { themes: emptyThemes(), folder: emptyFolder(), backups: emptyBackups() }
}

// ---- reducers: (the part's previous state, the helper's plain result) ----

function isObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v)
}

function hasId(v) {
  return isObject(v) && (typeof v.id === "string" || typeof v.id === "number")
}

// Rows of a list result: an array of objects with an id, each passing
// `extra`; anything else is dropped (a helper that printed the wrong shape
// never reaches a view or a preflight).
function rows(list, extra) {
  if (!Array.isArray(list)) return []
  return list.filter(r => hasId(r) && (!extra || extra(r)))
}

// list-themes: { ok, themes: [{id, name, role, processing}] }.
export function reduceThemes(prev, r, nowMs) {
  if (r.ok) return { status: "ok", items: rows(r.themes), fetchedAt: nowMs, error: null }
  return Object.assign({}, prev, { status: "error", error: fromHelper(r.error) })
}

// list-backups: { ok, backups: [{id, at, theme {id, name, role}, ...}],
// folderCopies: [{id, at, path, ...}] }. A backup row needs its theme (the
// live rule reads its role).
export function reduceBackups(prev, r) {
  if (r.ok) return Object.assign({}, prev, { status: "ok", items: rows(r.backups, b => isObject(b.theme)), folderCopies: rows(r.folderCopies), error: null })
  return Object.assign({}, prev, { status: "error", error: fromHelper(r.error) })
}

// inspect-folder for `requested` (the folder asked about).
export function reduceFolder(requested, r) {
  if (!r.ok) return Object.assign(emptyFolder(), { status: "error", requested: requested, error: fromHelper(r.error) })
  const reason = typeof r.reason === "string" ? r.reason : null
  return {
    status: "ok", requested: requested,
    exists: r.exists === true, themeShaped: r.themeShaped === true, empty: r.empty === true,
    safe: r.safe === true, reason: reason ? reason.substring(0, 40) : null,
    rootFiles: Array.isArray(r.rootFiles) ? r.rootFiles.filter(f => f === "AGENTS.md" || f === "DESIGN.md") : [],
    error: null
  }
}

// ---- selectors over a themeState (null-safe) -------------------------------

function themeItems(ts) {
  const t = ts && ts.themes ? ts.themes.items : null
  return Array.isArray(t) ? t : []
}

function backupItems(ts) {
  const b = ts && ts.backups ? ts.backups.items : null
  return Array.isArray(b) ? b : []
}

function byId(items, id) {
  const want = String(id == null ? "" : id)
  for (let i = 0; i < items.length; i++) if (String(items[i].id) === want) return items[i]
  return null
}

export function themeById(ts, id) {
  return byId(themeItems(ts), id)
}

export function backupById(ts, id) {
  return byId(backupItems(ts), id)
}

// The theme a config `theme` ({folder, target, ...}) pushes to and pulls
// from: { id, name, live }. A "live" target resolves through the cached
// themes list; an unknown id keeps the id with an empty name.
export function targetOf(theme, ts) {
  const target = theme && typeof theme.target === "string" ? theme.target : "live"
  const items = themeItems(ts)
  if (target === "live") {
    for (let i = 0; i < items.length; i++) if (items[i].role === "live") return { id: String(items[i].id), name: String(items[i].name || ""), live: true }
    return { id: "", name: "", live: true }
  }
  const t = themeById(ts, target)
  if (t) return { id: String(t.id), name: String(t.name || ""), live: t.role === "live" }
  return { id: target, name: "", live: false }
}

// A restore of backupId counts as live, so it needs the store's live
// opt-in and the live confirmation: the backup's list row says it was
// taken from the live theme, or the cached themes list says the backup's
// theme (the row's, else the id's) is live now. The helper decides by the
// role it finds and refuses a theme that went live since
// (live_not_confirmed), so the panel asks again.
export function restoreIsLive(ts, backupId) {
  const row = backupById(ts, backupId)
  const rowTheme = row && row.theme ? row.theme : null
  if (rowTheme && rowTheme.role === "live") return true
  const parsed = parseBackupId(backupId)
  const known = themeById(ts, rowTheme ? rowTheme.id : (parsed ? parsed.themeId : ""))
  return !!known && known.role === "live"
}

// The last inspection when it answered for exactly this folder, else null
// (never asked, still checking, failed, or about another folder).
export function inspectionOf(ts, folder) {
  const f = ts ? ts.folder : null
  return f && folder && f.status === "ok" && f.requested === folder ? f : null
}

// What the last inspection of `folder` says, as one word: "unknown" (not
// inspected, or still checking), "error" (the inspection failed),
// "missing", "unsafe", "notTheme" (files, but not config/, layout/ and
// templates/), "empty" (a pull target only) or "usable" (theme-shaped).
// The helpers' own folder check (ThemeFolder.check!) has the same order:
// a refusal reason (not_absolute has no folder behind it) is unsafe.
export function folderState(ts, folder) {
  const f = ts ? ts.folder : null
  if (!f || !folder || f.requested !== folder) return "unknown"
  if (f.status === "error") return "error"
  if (f.status !== "ok") return "unknown"
  if (!f.exists && !f.reason) return "missing"
  if (!f.safe) return "unsafe"
  if (f.themeShaped) return "usable"
  return f.empty ? "empty" : "notTheme"
}

// The AGENTS.md / DESIGN.md files a push also uploads: null before the
// folder is inspected, else the names found.
export function rootFiles(ts, folder) {
  const f = inspectionOf(ts, folder)
  if (!f) return null
  return Array.isArray(f.rootFiles) ? f.rootFiles : []
}
