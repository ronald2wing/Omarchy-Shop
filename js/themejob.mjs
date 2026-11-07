// A theme job (push, pull, restore): the helper and argv it runs, the
// result it leaves (model/ThemeJobs.qml keeps it as themeState.lastResult)
// and that result's wording and tone. Pure, so the live consents' flags and
// every result line are unit-tested where they are built. The wording
// lives here, beside the result's shape and its writes rule, rather than in
// copy.mjs: copy.mjs holds the strings, and like confirm.mjs and banner.mjs
// this module decides which one a state gets.
import { t, errorOf, themeName } from "./copy.mjs"
import { fromHelper } from "./errors.mjs"
import { backupWhen, homeRelative } from "./format.mjs"
import { asClause, scrubControl } from "./text.mjs"
import { EPOCH_RE, parseBackupId } from "./themes.mjs"

const HELPERS = { push: "push-theme", pull: "pull-theme", restore: "restore-backup" }
// The helper's lists are already capped; these bound what a result keeps.
const MAX_ROWS = 20
const MAX_TEXT = 200

// The helper flags for the two live consents, kept separate: allowLive is
// the store's opt-in (--allow-live), confirmLive is a live confirmation the
// user accepted (--confirm-live). Never confirm without the opt-in.
export function liveFlags(allowLive, confirmLive) {
  const out = []
  if (allowLive === true) {
    out.push("--allow-live")
    if (confirmLive === true) out.push("--confirm-live")
  }
  return out
}

// action: push | pull | restore. opts: { folder, target } (push, pull),
// { backupId } (restore), and { allowLive, confirmLive } (push, restore;
// a pull takes no live consent). -> { helper, args }.
export function jobCommand(action, domain, opts) {
  const o = opts || {}
  const store = "--store=" + domain
  let args
  if (action === "restore") args = [store, "--backup=" + o.backupId].concat(liveFlags(o.allowLive === true, o.confirmLive === true))
  else {
    args = [store, "--folder=" + o.folder, "--target=" + o.target]
    if (action === "push") args = args.concat(liveFlags(o.allowLive === true, o.confirmLive === true))
  }
  return { helper: HELPERS[action], args: args }
}

// ---- the result ------------------------------------------------------------

function isObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v)
}

// A list that crossed a QML `var` boundary may be array-like, not an Array.
function listOf(x) {
  return x && typeof x === "object" && typeof x.length === "number" ? Array.prototype.slice.call(x) : []
}

// Whether a job's writes had begun, from its helper line: the helper's own
// writeStarted (true: the CLI push, restore push or pull into the folder
// had started; false: nothing was written), else null: unknown, for a line
// the helper never printed (a killed helper's synthesized terminated,
// timeout or bad_response). A result keeps this, never a guess.
export function writeStartedOf(line) {
  if (!isObject(line)) return null
  // A helper that never started wrote nothing.
  if (isObject(line.error) && line.error.code === "failed_to_start") return false
  const v = line.writeStarted
  return v === true ? true : (v === false ? false : null)
}

// The helper's `warnings`: {kind: issue|symlink|hardlink, path, message?}
// rows and nothing else, each field bounded.
function cleanWarnings(list) {
  const out = []
  const rows = listOf(list)
  for (let i = 0; i < rows.length && out.length < MAX_ROWS; i++) {
    const w = rows[i]
    if (!isObject(w)) continue
    const kind = w.kind === "symlink" || w.kind === "hardlink" ? w.kind : "issue"
    out.push({ kind: kind, path: scrubControl(w.path, MAX_TEXT), message: scrubControl(w.message, MAX_TEXT) })
  }
  return out
}

function cleanDetails(list) {
  return listOf(list).slice(0, MAX_ROWS).map(line => scrubControl(line, MAX_TEXT))
}

// The theme a result names: the helper's row ({id, name, role}, success
// lines only), else the job's target name, else null.
function resultTheme(t, fallbackName) {
  if (isObject(t)) return { id: String(t.id == null ? "" : t.id), name: scrubControl(t.name, MAX_TEXT), role: String(t.role || "") }
  return fallbackName ? { id: "", name: String(fallbackName), role: "" } : null
}

// The result a finished job leaves, from the job ({action, name, folder,
// restoredBackupId}: ThemeJobs' running job) and its helper's line (a plain
// object: the helper's JSON, or the error HelperProcess synthesized).
// opts: { canceled (the user stopped it: its error reads terminated),
// nowMs }. -> { ok, action, theme, folder, backupId, folderCopy,
// restoredBackupId, partial, warnings, writeStarted (true | false | null),
// at, error, details }. backupId is a failed push's or restore's backup
// (a success's too), folderCopy a pull's folder copy; restoredBackupId the
// backup a restore pushed back.
export function resultOf(job, line, opts) {
  const j = job || {}
  const r = isObject(line) ? line : {}
  const o = opts || {}
  const ok = r.ok === true
  let error = null
  if (!ok) {
    error = fromHelper(r.error)
    if (o.canceled === true) error.code = "terminated"
  }
  return {
    ok: ok,
    action: String(j.action || ""),
    theme: resultTheme(ok ? r.theme : null, j.name),
    folder: ok && typeof r.folder === "string" ? r.folder : String(j.folder || ""),
    backupId: parseBackupId(r.backupId) ? r.backupId : null,
    folderCopy: typeof r.folderCopy === "string" && EPOCH_RE.test(r.folderCopy) ? r.folderCopy : null,
    restoredBackupId: j.restoredBackupId || null,
    // The CLI rejected some files (status "partial"); warnings hold them.
    partial: ok && r.partial === true,
    warnings: ok ? cleanWarnings(r.warnings) : [],
    writeStarted: writeStartedOf(r),
    at: Number(o.nowMs) || 0,
    error: error,
    details: ok ? [] : cleanDetails(r.details)
  }
}

// The CLI's per-file problems: [{kind: "issue", path, message}].
export function resultIssues(r) {
  return r ? listOf(r.warnings).filter(w => w.kind === "issue") : []
}

// The links a pull left in the folder: [{kind: "symlink"|"hardlink", path}].
export function resultLinks(r) {
  return r ? listOf(r.warnings).filter(w => w.kind === "symlink" || w.kind === "hardlink") : []
}

// The lines behind "Details": the CLI's stderr tail on a failure; on a
// success the per-file problems ("path: message") then the links
// ("symlink path").
export function resultDetails(r) {
  if (!r) return []
  if (r.ok !== true) return listOf(r.details)
  return resultIssues(r).map(w => w.path + (w.message ? ": " + w.message : ""))
    .concat(resultLinks(r).map(w => w.kind + " " + w.path))
}

// A job that failed or was stopped may have written: only the helper's own
// writeStarted: false says it did not (a killed helper is unknown, null).
function mayHaveWritten(r) {
  return !!r && r.ok !== true && r.writeStarted !== false
}

function stopped(r) {
  return !!r && !!r.error && r.error.code === "terminated"
}

// The status line's tone: ok, warn (a success that needs a look, or a
// stop) or error.
export function resultTone(r) {
  if (!r) return "info"
  if (r.ok === true) return r.partial === true || listOf(r.warnings).length > 0 ? "warn" : "ok"
  return stopped(r) ? "warn" : "error"
}

// The copy a failed or stopped job kept from before its writes, when the
// writes may have begun (so the user may want it back): { kind: "backup" |
// "folderCopy", atMs } or null. A push or restore keeps a theme backup, a
// pull a folder copy.
export function keptCopy(r) {
  if (!mayHaveWritten(r)) return null
  if (r.action === "pull") return r.folderCopy ? { kind: "folderCopy", atMs: Number(r.folderCopy) * 1000 } : null
  const b = parseBackupId(r.backupId)
  return b ? { kind: "backup", atMs: b.epochMs } : null
}

// "Backup kept · Today 11:35" / "Folder copy kept · …" under the line, or "".
export function keptText(r, nowMs) {
  const k = keptCopy(r)
  if (!k) return ""
  return t(k.kind === "folderCopy" ? "result.folderCopyKept" : "result.backupKept", { when: backupWhen(k.atMs, nowMs) })
}

// The theme a result names, as the line says it: its name (with " (live)"
// on a live one), else a restore's backup theme by id, else the card's
// current target.
function themeText(r, targetName) {
  const th = r.theme
  if (th && th.name) return th.role === "live" ? t("result.theme.live", { theme: th.name }) : th.name
  const b = r.action === "restore" ? parseBackupId(r.restoredBackupId) : null
  if (b) return themeName({ id: b.themeId })
  return targetName
}

// What may have changed, when a job's writes may have begun: the theme
// (push, restore), the folder (pull; a pull with no folder copy and its
// own writeStarted: true went into an empty folder).
function mayHaveChangedText(r, theme, folder) {
  if (r.action !== "pull") return t("result.mayHaveChanged.theme", { theme: theme })
  if (!r.folderCopy && r.writeStarted === true) return t("result.mayHaveChanged.emptyFolder", { folder: folder })
  return t("result.mayHaveChanged.folder", { folder: folder })
}

// The failure's message: the CLI's own words for cli_failed (errorOf would
// say "The Shopify CLI failed: …", which stutters inside "Push failed: …"),
// else errorOf's; as a clause either way.
function failureMessage(error) {
  if (error && error.code === "cli_failed" && typeof error.message === "string" && error.message !== "") return asClause(error.message)
  return asClause(errorOf(error))
}

// The result's status line. opts: { targetName (the card's target, for a
// result that names no theme), folder (the linked folder, for one that
// names none), home }. A stopped or failed job says nothing changed only
// on the helper's own writeStarted: false; otherwise it says what may have.
export function resultText(r, opts) {
  if (!r) return ""
  const o = opts || {}
  const theme = themeText(r, String(o.targetName || ""))
  const folder = homeRelative(String(r.folder || o.folder || ""), o.home)
  if (r.ok === true) {
    const done = r.action === "pull" ? t("result.pulled", { theme: theme, folder: folder })
      : r.action === "restore" ? t("result.restored", { theme: theme })
      : t("result.pushed", { theme: theme })
    const issues = resultIssues(r).length
    if (r.partial === true || issues > 0)
      return issues > 1 ? t("result.partial", { action: done, n: issues }) : t("result.partial.one", { action: done })
    const links = resultLinks(r).length
    if (r.action === "pull" && links > 0) return links === 1 ? t("result.links.one") : t("result.links", { n: links })
    return done
  }
  const changed = mayHaveWritten(r) ? mayHaveChangedText(r, theme, folder) : ""
  if (stopped(r)) {
    if (changed !== "") return t("result.stopped.maybe", { mayHaveChanged: changed })
    return t("result.stopped.none." + (r.action === "pull" || r.action === "restore" ? r.action : "push"), { theme: theme, folder: folder })
  }
  const failed = { action: t("job.title." + (r.action === "pull" || r.action === "restore" ? r.action : "push")), message: failureMessage(r.error) }
  if (changed !== "") return t("result.failed.maybe", Object.assign(failed, { mayHaveChanged: changed }))
  return t("result.failed.none", failed)
}
