// js/themejob.mjs: a theme job's helper and argv (the two live consents
// kept apart), the result it leaves, and that result's line, tone and
// kept-copy note across the whole matrix of actions and outcomes.
import assert from "node:assert/strict"
import { errorOf } from "../../js/copy.mjs"
import { backupWhen } from "../../js/format.mjs"
import { jobCommand, keptCopy, keptText, liveFlags, resultDetails, resultIssues, resultLinks, resultOf, resultText, resultTone, writeStartedOf } from "../../js/themejob.mjs"

assert.deepEqual(liveFlags(true, false), ["--allow-live"])
assert.deepEqual(liveFlags(true, true), ["--allow-live", "--confirm-live"])
assert.deepEqual(liveFlags(false, true), [], "never confirm without the opt-in")
assert.deepEqual(liveFlags(false, false), [])
assert.deepEqual(liveFlags("yes", "yes"), [], "only true counts")

const D = "acme.myshopify.com"
assert.deepEqual(jobCommand("push", D, { folder: "/f", target: "live", allowLive: true, confirmLive: true }),
  { helper: "push-theme", args: ["--store=" + D, "--folder=/f", "--target=live", "--allow-live", "--confirm-live"] })
assert.deepEqual(jobCommand("push", D, { folder: "/f", target: "123" }).args, ["--store=" + D, "--folder=/f", "--target=123"])
assert.deepEqual(jobCommand("pull", D, { folder: "/f", target: "live", allowLive: true, confirmLive: true }),
  { helper: "pull-theme", args: ["--store=" + D, "--folder=/f", "--target=live"] }, "a pull takes no live consent")
assert.deepEqual(jobCommand("restore", D, { backupId: "1762500000-1", allowLive: true }),
  { helper: "restore-backup", args: ["--store=" + D, "--backup=1762500000-1", "--allow-live"] })

// writeStarted: only the helper's own true/false counts; a line it never
// printed (synthesized terminated, timeout, bad_response) is unknown.
assert.equal(writeStartedOf({ ok: false, writeStarted: false }), false)
assert.equal(writeStartedOf({ ok: false, writeStarted: true }), true)
assert.equal(writeStartedOf({ ok: false, error: { code: "terminated" } }), null, "a synthesized line is unknown")
assert.equal(writeStartedOf({ writeStarted: "true" }), null, "only booleans count")
assert.equal(writeStartedOf(null), null)
assert.equal(writeStartedOf({ ok: false, error: { code: "failed_to_start" } }), false, "a helper that never started wrote nothing")

// ---- resultOf: the result a job leaves, every field bounded ----
const NOW = 1762520400000
const BACKUP = "1762500000-1"
const COPY = "1762500001"
const pushJob = { action: "push", name: "Dawn", folder: "/home/u/acme" }
const pullJob = { action: "pull", name: "Dawn", folder: "/home/u/acme" }
const restoreJob = { action: "restore", name: "", folder: "", restoredBackupId: "1762400000-7" }
let r = resultOf(pushJob, { ok: true, theme: { id: 1, name: "Dawn\u0007", role: "live" }, folder: "/home/u/acme", backupId: BACKUP, writeStarted: true, warnings: [] }, { nowMs: NOW })
assert.deepEqual(r, { ok: true, action: "push", theme: { id: "1", name: "Dawn", role: "live" }, folder: "/home/u/acme", backupId: BACKUP, folderCopy: null,
  restoredBackupId: null, partial: false, warnings: [], writeStarted: true, at: NOW, error: null, details: [] })
r = resultOf(pushJob, { ok: false, error: { code: "timeout", message: "slow" }, backupId: "../x", folderCopy: "nope", writeStarted: false, details: ["a\u0007b"] }, { nowMs: NOW })
assert.deepEqual([r.theme, r.backupId, r.folderCopy, r.error.code, r.details, r.writeStarted], [{ id: "", name: "Dawn", role: "" }, null, null, "timeout", ["a b"], false], "a failure names the job's target, drops malformed ids")
assert.equal(resultOf(pushJob, { ok: false, error: { code: "cli_failed", message: "x" } }, { canceled: true }).error.code, "terminated", "a stop the user asked for reads terminated")
assert.equal(resultOf(pushJob, { ok: false, error: { code: "terminated" } }, {}).writeStarted, null, "a synthesized line is unknown")
assert.equal(resultOf({ action: "pull" }, { ok: true, folderCopy: COPY }, {}).folderCopy, COPY)
assert.equal(resultOf(restoreJob, { ok: true }, {}).restoredBackupId, "1762400000-7")
const many = []
for (let i = 0; i < 30; i++) many.push({ kind: i === 0 ? "symlink" : "weird", path: "p" + i, message: "m".repeat(300) })
r = resultOf(pushJob, { ok: true, partial: true, warnings: many }, {})
assert.deepEqual([r.warnings.length, r.warnings[0].kind, r.warnings[1].kind, r.warnings[1].message.length], [20, "symlink", "issue", 200], "rows capped, unknown kinds are issues, text capped")
assert.deepEqual(resultOf(null, null, {}).action, "", "no job, no line")

// ---- resultIssues / resultLinks / resultDetails ----
const partial = { ok: true, partial: true, warnings: [
  { kind: "issue", path: "sections/x.liquid", message: "Liquid syntax error" },
  { kind: "symlink", path: "snippets/a.liquid" },
  { kind: "hardlink", path: "assets/b.js" }
] }
assert.deepEqual(resultIssues(partial), [{ kind: "issue", path: "sections/x.liquid", message: "Liquid syntax error" }])
assert.deepEqual(resultLinks(partial).map(w => w.kind + ":" + w.path), ["symlink:snippets/a.liquid", "hardlink:assets/b.js"])
assert.deepEqual(resultDetails(partial), ["sections/x.liquid: Liquid syntax error", "symlink snippets/a.liquid", "hardlink assets/b.js"])
assert.deepEqual(resultDetails({ ok: false, details: ["Error: 401"], warnings: [{ kind: "issue", path: "x" }] }), ["Error: 401"], "a failure's details are the CLI's")
assert.deepEqual(resultDetails({ ok: true, warnings: [] }), [])
assert.deepEqual(resultDetails(null), [])
assert.deepEqual(resultDetails({ ok: true, warnings: { length: 1, 0: { kind: "issue", path: "p", message: "m" } } }), ["p: m"], "array-likes read")

// ---- resultText / resultTone / keptText: the matrix ----
const O = { targetName: "Card target", folder: "/home/u/acme", home: "/home/u" }
const line = (job, l, canceled) => resultOf(job, l, { canceled: canceled === true, nowMs: NOW })
const text = r => resultText(r, O)
const okPush = line(pushJob, { ok: true, theme: { id: "1", name: "Dawn", role: "live" }, backupId: BACKUP, writeStarted: true, warnings: [] })
const okDev = line(pushJob, { ok: true, theme: { id: "2", name: "Dev", role: "unpublished" }, backupId: BACKUP, writeStarted: true })
assert.equal(text(okPush), "Pushed to Dawn (live)")
assert.equal(text(okDev), "Pushed to Dev")
assert.equal(resultTone(okPush), "ok")
assert.equal(keptText(okPush, NOW), "", "a success keeps no note")
assert.equal(text(line(pullJob, { ok: true, theme: { id: "2", name: "Dev", role: "unpublished" }, folder: "/home/u/acme", folderCopy: COPY, writeStarted: true })), "Pulled Dev into ~/acme")
assert.equal(text(line(restoreJob, { ok: true, theme: { id: "7", name: "Old", role: "unpublished" }, backupId: BACKUP, writeStarted: true })), "Restored backup to Old")
assert.equal(text(line(restoreJob, { ok: false, error: { code: "terminated" } }, true)), "Stopped. Files on Theme 7 may have changed: check the theme.", "a restore with no name: the backup's theme id")
// Partial and links.
const issue = n => { const w = []; for (let i = 0; i < n; i++) w.push({ kind: "issue", path: "s" + i, message: "bad" }); return w }
assert.equal(text(line(pushJob, { ok: true, theme: { id: "2", name: "Dev", role: "" }, partial: true, warnings: issue(1) })), "Pushed to Dev with a file problem")
assert.equal(text(line(pushJob, { ok: true, theme: { id: "2", name: "Dev", role: "" }, partial: true, warnings: issue(3) })), "Pushed to Dev with 3 file problems")
assert.equal(text(line(pushJob, { ok: true, theme: { id: "2", name: "Dev", role: "" }, partial: true, warnings: [] })), "Pushed to Dev with a file problem", "partial without issue rows")
assert.equal(resultTone(line(pushJob, { ok: true, partial: true, warnings: [] })), "warn")
const links = n => { const w = []; for (let i = 0; i < n; i++) w.push({ kind: "symlink", path: "l" + i }); return w }
assert.equal(text(line(pullJob, { ok: true, theme: { id: "2", name: "Dev", role: "" }, warnings: links(1) })), "Pulled, but 1 file in the folder is a link Shop won't push. See Details.")
assert.equal(text(line(pullJob, { ok: true, theme: { id: "2", name: "Dev", role: "" }, warnings: links(2) })), "Pulled, but 2 files in the folder are links Shop won't push. See Details.")
assert.equal(resultTone(line(pullJob, { ok: true, warnings: links(1) })), "warn")
// Stopped: nothing written only on the helper's own writeStarted false.
const stop = (job, extra) => line(job, Object.assign({ ok: false, error: { code: "terminated", message: "" } }, extra), true)
assert.equal(text(stop(pushJob, { writeStarted: false })), "Stopped before anything was pushed to Dawn")
assert.equal(text(stop(restoreJob, { writeStarted: false })), "Stopped before anything was restored to Theme 7")
assert.equal(text(stop(pullJob, { writeStarted: false })), "Stopped before anything in ~/acme changed")
for (const ws of [true, undefined]) {
  assert.equal(text(stop(pushJob, { writeStarted: ws, backupId: BACKUP })), "Stopped. Files on Dawn may have changed: check the theme.", "push writeStarted " + ws)
  assert.equal(text(stop(pullJob, { writeStarted: ws, folderCopy: COPY })), "Stopped. Files in ~/acme may have changed: check the folder.", "pull writeStarted " + ws)
}
assert.equal(text(stop(pullJob, { writeStarted: true, folderCopy: null })), "Stopped. ~/acme may now hold part of the theme.", "an empty folder has no copy")
assert.equal(text(stop(pullJob, {})), "Stopped. Files in ~/acme may have changed: check the folder.", "unknown, no copy: still hedged")
assert.equal(resultTone(stop(pushJob, {})), "warn")
// Failed: the message as a clause, hedged unless nothing was written.
const fail = (job, error, extra) => line(job, Object.assign({ ok: false, error: error }, extra))
const cli = { code: "cli_failed", message: "The theme 'Dawn' could not be pushed." }
assert.equal(text(fail(pushJob, cli, { writeStarted: false })), "Push failed: The theme 'Dawn' could not be pushed")
assert.equal(text(fail(pushJob, cli, { writeStarted: true, backupId: BACKUP })), "Push failed: The theme 'Dawn' could not be pushed. Files on Dawn may have changed: check the theme.")
assert.equal(text(fail(pushJob, { code: "timeout", message: "x" })), "Push failed: " + errorOf({ code: "timeout", message: "x" }).replace(/[.\s]+$/, "") + ". Files on Dawn may have changed: check the theme.", "a timeout is unknown: hedged")
assert.equal(text(fail(pullJob, cli, { writeStarted: false })), "Pull failed: The theme 'Dawn' could not be pushed")
assert.equal(text(fail(pullJob, cli, { writeStarted: true, folderCopy: COPY })), "Pull failed: The theme 'Dawn' could not be pushed. Files in ~/acme may have changed: check the folder.")
assert.equal(text(fail(restoreJob, { code: "cli_failed", message: "" }, { writeStarted: false })), "Restore failed: " + errorOf({ code: "cli_failed", message: "" }).replace(/[.\s]+$/, ""), "an empty CLI message: errorOf's words")
assert.equal(text(fail(pushJob, { code: "cli_failed", message: "sections/a.liquid: Liquid syntax error (+2 more)" }, { writeStarted: true })).split("failed:").length - 1, 1, "no double 'failed:'")
assert.equal(resultTone(fail(pushJob, cli, {})), "error")
assert.equal(text(fail({ action: "push", name: "" }, cli, { writeStarted: false })), "Push failed: The theme 'Dawn' could not be pushed", "no theme anywhere")
assert.equal(text(fail({ action: "push", name: "" }, cli, { writeStarted: true })), "Push failed: The theme 'Dawn' could not be pushed. Files on Card target may have changed: check the theme.", "the card's target")
// Kept copies: a failed or stopped job whose writes may have begun.
assert.deepEqual(keptCopy(fail(pushJob, cli, { writeStarted: true, backupId: BACKUP })), { kind: "backup", atMs: 1762500000000 })
assert.equal(keptText(fail(pushJob, cli, { writeStarted: true, backupId: BACKUP }), NOW), "Backup kept · " + backupWhen(1762500000000, NOW))
assert.equal(keptText(stop(pushJob, { backupId: BACKUP }), NOW), "Backup kept · " + backupWhen(1762500000000, NOW), "a stop with unknown writes")
assert.equal(keptText(fail(pushJob, cli, { writeStarted: false, backupId: BACKUP }), NOW), "", "nothing written: nothing to take back")
assert.equal(keptText(fail(pushJob, cli, { writeStarted: true }), NOW), "", "no backup taken")
assert.equal(keptText(stop(pullJob, { writeStarted: true, folderCopy: COPY }), NOW), "Folder copy kept · " + backupWhen(1762500001000, NOW))
assert.equal(keptText(stop(pullJob, { writeStarted: true }), NOW), "", "an empty folder has no copy")
assert.equal(keptText(null, NOW), "")
assert.equal(resultText(null, O), "")
assert.equal(resultTone(null), "info")
