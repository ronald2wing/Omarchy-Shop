// js/results.mjs: the helper-error normaliser and one builder per
// service-level refusal, whose message is the panel's sentence for it.
import assert from "node:assert/strict"
import { errorOf } from "../../js/copy.mjs"
import * as E from "../../js/results.mjs"

// fromHelper: code, message, reason, retryAfter, missing, range
assert.deepEqual(E.fromHelper(null), { code: "cli_failed", message: "" })
assert.deepEqual(E.fromHelper({ code: "", message: 5 }), { code: "cli_failed", message: "" })
const ce = E.fromHelper({ code: "rate_limited", message: "m", reason: "r", retryAfter: 12, junk: 1 }, "today")
assert.deepEqual(ce, { code: "rate_limited", message: "m", reason: "r", retryAfter: 12, range: "today" })
assert.equal(E.fromHelper({ code: "cli_missing", missing: "node" }).missing, "node")
assert.equal("missing" in E.fromHelper({ code: "cli_missing", missing: "npm" }), false)

// A builder is { ok: false, error } with its extras merged into the error.
assert.deepEqual(E.cliMissing("node"), { ok: false, error: { code: "cli_missing", message: "The Shopify CLI isn't installed", missing: "node" } })
assert.deepEqual(E.refused({ code: "x", message: "m" }), { ok: false, error: { code: "x", message: "m" } })

const codes = {
  unknownStore: "unknown_store", cliChecking: "cli_checking", cliInstalling: "cli_installing", accountBusy: "account_busy",
  confirmOpen: "confirm_open", configUnavailable: "config_unavailable",
  recentlyDeclined: "recently_declined", noPending: "no_pending", rateLimitedLocally: "rate_limited_locally",
  noThemeFolder: "no_theme_folder", salesAccessRequired: "sales_access_required", liveNotAllowed: "live_not_allowed",
  invalidDomain: "invalid_domain", duplicateStore: "duplicate_store"
}
for (const fn of Object.keys(codes)) {
  const r = E[fn]()
  assert.equal(r.ok, false, fn)
  assert.equal(r.error.code, codes[fn], fn)
  assert.equal(r.error.message, errorOf(r.error), fn + ": the panel's sentence")
}

assert.deepEqual(E.configBusy("resetting").error, { code: "config_busy", message: "resetting" })
assert.equal(E.configUnavailable("broken").error.message, "broken")
assert.equal(E.configUnavailable().error.code, "config_unavailable")
assert.equal(E.cliMissing("node").error.code, "cli_missing")
assert.equal(E.cliMissing("node").error.missing, "node")
assert.equal("missing" in E.cliMissing(null).error, false)
assert.deepEqual(E.storeBusy("pull").error, { code: "store_busy", message: "Wait for the pull to finish", action: "pull" })
assert.equal("blocked" in E.storeBusy("preview").error, false, "blocked only when named")
assert.deepEqual(E.storeBusy("preview", "push").error, { code: "store_busy", message: "Stop the preview before you push", action: "preview", blocked: "push" })
assert.deepEqual(E.folderUnusable("push", "empty").error, { code: "folder_unusable", message: "Can't push an empty folder: pull a theme into it first", action: "push", state: "empty" })
assert.equal(E.isRateLimit("rate_limited"), true)
assert.equal(E.isRateLimit("throttled"), false, "only rate_limited is a rate limit")
assert.deepEqual(E.ok(), { ok: true })
assert.deepEqual(E.started(), { ok: true, started: true })
assert(E.ok() !== E.ok(), "a fresh object per call")
assert.deepEqual(E.internalError("boom"), { ok: false, error: { code: "internal_error", message: "boom" } })
assert.deepEqual(E.anyStoreBusy("preview").error, { code: "store_busy", message: "Wait for the running push, pull, restore or preview to finish", what: "preview", anyStore: true })
assert.equal(E.anyStoreBusy("grant").error.message, "Wait for the sales access grant in your browser to finish")
assert.deepEqual([E.anyStoreBusy("grant").error.what, E.anyStoreBusy("grant").error.anyStore], ["grant", true], "Reset config during a grant")

// The bare error object and the wrap around one.
assert.deepEqual(E.error("x", "m"), { code: "x", message: "m" })
assert.deepEqual(E.error("x"), { code: "x", message: "" })
assert.deepEqual(E.error("x", "m", { retryAfter: 2 }), { code: "x", message: "m", retryAfter: 2 })
// Messages that carry their detail.
assert.deepEqual(E.tooManyStores(50).error, { code: "too_many_stores", message: "Shop keeps at most 50 stores", max: 50 })
assert.deepEqual(E.invalidBackupId().error, { code: "invalid_argument", message: "Not a backup id" })
assert.deepEqual(E.invalidPatch("empty patch").error, { code: "invalid_patch", message: "empty patch" })
assert.deepEqual(E.configWriteFailed("disk full").error, { code: "config_write_failed", message: "disk full" })
assert.equal(E.accountBusy("signing in").error.message, "signing in")
// HelperProcess's own results for a helper that gave no usable line.
for (const [fn, code] of [["badResponse", "bad_response"], ["timeout", "timeout"], ["terminated", "terminated"],
                          ["outputTooLarge", "output_too_large"], ["failedToStart", "failed_to_start"]]) {
  assert.deepEqual(E[fn]("m"), { ok: false, error: { code: code, message: "m" } }, fn)
}

// A store lookup while config.json is unusable names the config, never
// "That store isn't in Shop".
assert.deepEqual(E.configInvalid({ code: "config_invalid", message: "config.json couldn't be read (parse)" }),
  { ok: false, error: { code: "config_invalid", message: "config.json couldn't be read (parse)" } })
assert.equal(E.configInvalid({ code: "config_unsupported", message: "v1" }).error.code, "config_unsupported")
