// js/banner.mjs: one banner at a time, in the fixed priority.
import assert from "node:assert/strict"
import { bannerFor } from "../../js/banner.mjs"
import { clockLocal } from "../../js/format.mjs"
import * as S from "../../js/snapshot.mjs"
import { accountBlock } from "../../js/snapshot.mjs"
import * as T from "../../js/themes.mjs"

// Every banner is asserted as the text it shows (js/copy.mjs).
const NOW = 1762520400000
const STOPPED = { status: "stopped", url: "", error: null }
const base = () => ({
  configError: null, configWriteError: null, stateError: null, pins: { cli: S.CLI_PIN, node: S.NODE_PIN },
  cli: { status: "ready", missing: null, error: null },
  account: { status: "signed_in", error: null },
  settings: { pollSeconds: 60, alerts: { notify: true, sound: true }, bar: { display: "stores" } },
  stores: {}
})
const storeWith = (sales, extra) => Object.assign({
  domain: "acme.myshopify.com", label: "Acme", salesAccess: "granted",
  sales: Object.assign({ status: "ok", pending: false, paused: false, error: null, fetchedAt: { today: NOW - 60000, traffic: 0, history: 0 } }, sales),
  themeState: Object.assign(T.emptyThemeState(), { job: null, lastResult: null, preview: STOPPED })
}, extra || {})

assert.equal(bannerFor(base(), NOW, null), null, "nothing to say")
assert.equal(bannerFor(null, NOW, null), null)

// Config errors first, with Open file and Reset.
let s = base()
s.configError = { code: "config_invalid", message: "bad json" }
s.cli.status = "missing"
let b = bannerFor(s, NOW, null)
assert.equal(b.id, "configError")
assert.equal(b.tone, "error")
assert.equal(b.title, "config.json couldn't be read")
assert.equal(b.body, "bad json. Shop won't change the file until you fix or reset it.")
assert.deepEqual(b.actions, [{ id: "openConfig", label: "Open file" }, { id: "resetConfig", label: "Reset config…" }])
// The body adds its own period after the message: none doubled.
s.configError = { code: "config_invalid", message: "config.json is not valid JSON." }
assert.equal(bannerFor(s, NOW, null).body, "config.json is not valid JSON. Shop won't change the file until you fix or reset it.")
s.configError = { code: "config_invalid", message: "bad json" }
assert.equal(b.busy, false)
s.configError = { code: "config_unsupported", message: "old" }
assert.equal(bannerFor(s, NOW, null).body, "This config.json is from a different Shop version.")

// The state error beats everything.
s.stateError = { code: "unsafe_state_dir", message: "m" }
b = bannerFor(s, NOW, null)
assert.equal(b.id, "stateError")
assert.equal(b.title, "Shop's state folder is a link or owned by someone else")
s.stateError = { code: "no_such_code", message: "m" }
b = bannerFor(s, NOW, null)
assert.equal(b.title, "Something went wrong: m", "an unknown code falls back")
assert.deepEqual(b.actions, [])

// A write error, dismissable, skipped once dismissed.
s = base()
s.configWriteError = { code: "config_write_failed", message: "disk" }
b = bannerFor(s, NOW, null)
assert.equal(b.id, "configWriteError")
assert.equal(b.body, "Couldn't save config.json: disk")
assert.deepEqual(b.actions, [{ id: "dismissWriteError", label: "Dismiss" }])
assert.equal(bannerFor(s, NOW, JSON.stringify(s.configWriteError)), null)
assert.equal(bannerFor(s, NOW, JSON.stringify({ code: "config_write_failed", message: "other" })).id, "configWriteError")
// The banner is display only: a write error shown above a missing CLI
// hides the CLI banner until dismissed, but what is blocked (Home's rows,
// the store view, the bar pill) is Preflight.accountBlock's, from the raw
// fields, whatever banner shows.
s.cli = { status: "missing", missing: "cli", installs: "~/i", error: null }
assert.equal(bannerFor(s, NOW, null).id, "configWriteError")
assert.equal(accountBlock(s), "cli")
assert.equal(bannerFor(s, NOW, JSON.stringify(s.configWriteError)).id, "cliMissing", "dismissed: the CLI banner")

// CLI: install failed › missing › installing.
s = base()
s.cli = { status: "install_failed", missing: "cli", error: { code: "mise_missing", message: "" } }
b = bannerFor(s, NOW, null)
assert.equal(b.id, "installFailed")
assert.equal(b.tone, "error")
assert.equal(b.body, "mise isn't installed")
assert.deepEqual(b.actions, [{ id: "install", label: "Retry" }])
s.cli = { status: "missing", missing: "node", installs: "~/.local/share/mise/installs", error: null }
b = bannerFor(s, NOW, null)
assert.equal(b.id, "cliMissing")
assert.equal(b.tone, "warn")
assert.equal(b.title, "The Shopify CLI isn't installed")
// What is missing comes first (an elided body keeps it); the versions are
// said once, inside {missing}.
assert.equal(b.body, "Node " + S.NODE_PIN + " isn't in ~/.local/share/mise/installs. Shop uses only its own pinned copy.")
assert.deepEqual(b.actions, [{ id: "install", label: "Install…" }])
s.cli.missing = "cli"
assert(bannerFor(s, NOW, null).body.startsWith("Shopify CLI " + S.CLI_PIN + " isn't in "))
s.cli = { status: "installing", missing: null, error: null }
b = bannerFor(s, NOW, null)
assert.equal(b.id, "installing")
assert.equal(b.tone, "info")
assert.equal(b.body, "This can take a few minutes.")
assert.equal(b.busy, true)
assert.deepEqual(b.actions, [{ id: "cancelInstall", label: "Cancel" }])
// Checking, or unknown with no error: no banner.
s.cli = { status: "checking" }
assert.equal(bannerFor(s, NOW, null), null)
s.cli = { status: "unknown", error: null }
assert.equal(bannerFor(s, NOW, null), null)
// The check itself failed (check-account timed out): say so, offer Retry.
s.cli = { status: "unknown", missing: null, error: { code: "timeout", message: "check-account took too long" } }
b = bannerFor(s, NOW, null)
assert.equal(b.id, "cliCheckFailed")
assert.equal(b.tone, "warn")
assert.equal(b.title, "Couldn't check the Shopify CLI")
assert.equal(b.body, "Shopify took too long to respond")
assert.deepEqual(b.actions, [{ id: "retryCheck", label: "Retry" }])
// It ranks below a broken config.json.
s.configError = { code: "config_invalid", message: "x" }
assert.equal(bannerFor(s, NOW, null).id, "configError")
s.configError = null

// Session expired (a theme job's result) › signed out › signing in.
s = base()
s.account.status = "signed_out"
s.stores = { "acme.myshopify.com": storeWith({}) }
s.stores["acme.myshopify.com"].themeState.lastResult = { ok: false, error: { code: "theme_session_expired", message: "" } }
b = bannerFor(s, NOW, null)
assert.equal(b.id, "sessionExpired")
assert.equal(b.body, "Your Shopify session expired. Sign in again.")
assert.deepEqual(b.actions, [{ id: "resignIn", label: "Sign in again" }])
s.stores["acme.myshopify.com"].themeState.lastResult = null
b = bannerFor(s, NOW, null)
assert.equal(b.id, "signedOut")
assert.equal(b.tone, "warn")
assert.equal(b.title, "You're signed out of Shopify")
assert.equal(b.body, "Push, pull and preview may keep working until Shopify asks you to sign in again.")
assert.deepEqual(b.actions, [{ id: "signIn", label: "Sign in" }])
s.account.status = "signing_in"
b = bannerFor(s, NOW, null)
assert.equal(b.id, "signingIn")
assert.equal(b.busy, true)
assert.deepEqual(b.actions, [{ id: "cancelSignIn", label: "Cancel" }])
s.account.status = "signing_out"
assert.equal(bannerFor(s, NOW, null), null)

// Rate limited, with the retry time.
s = base()
s.stores = { "acme.myshopify.com": storeWith({ error: { code: "rate_limited", message: "" }, retryAt: NOW + 300000 }) }
b = bannerFor(s, NOW, null)
assert.equal(b.id, "rateLimited")
assert.equal(b.tone, "info")
assert.equal(b.title, "Shopify is limiting requests")
assert.equal(b.body, "Retrying at " + clockLocal(NOW + 300000) + ".")
assert.deepEqual(b.actions, [])
s.stores["acme.myshopify.com"].sales.retryAt = 0
assert.equal(bannerFor(s, NOW, null).body, "")

// Stale: every eligible store stale; info under 10 min, warn from 10 min.
s = base()
s.stores = {
  "acme.myshopify.com": storeWith({ fetchedAt: { today: NOW - 5 * 60000 } }),
  "beta.myshopify.com": storeWith({ fetchedAt: { today: NOW - 4 * 60000 } }, { domain: "beta.myshopify.com" })
}
b = bannerFor(s, NOW, null)
assert.equal(b.id, "stale")
assert.equal(b.tone, "info")
assert.equal(b.title, "Sales haven't updated for 5 min")
s.stores["acme.myshopify.com"].sales.fetchedAt.today = NOW - 10 * 60000
assert.equal(bannerFor(s, NOW, null).tone, "warn")
assert.equal(bannerFor(s, NOW, null).title, "Sales haven't updated for 10 min")
// One fresh store: not stale.
s.stores["beta.myshopify.com"].sales.fetchedAt.today = NOW - 30000
assert.equal(bannerFor(s, NOW, null), null)
// A loading store does not count either way; a store waiting on access is skipped.
s.stores["beta.myshopify.com"].sales.pending = true
assert.equal(bannerFor(s, NOW, null).id, "stale")
s.stores["beta.myshopify.com"].sales.pending = false
s.stores["beta.myshopify.com"].salesAccess = "required"
assert.equal(bannerFor(s, NOW, null).id, "stale")
// Paused (CLI missing just resolved, scheduler off) or never fetched: nothing.
s.stores = { "acme.myshopify.com": storeWith({ fetchedAt: { today: NOW - 20 * 60000 }, paused: true }) }
assert.equal(bannerFor(s, NOW, null), null)
s.stores = { "acme.myshopify.com": storeWith({ fetchedAt: { today: 0 } }) }
assert.equal(bannerFor(s, NOW, null), null)
// Rate limited beats stale.
s.stores = { "acme.myshopify.com": storeWith({ fetchedAt: { today: NOW - 20 * 60000 }, error: { code: "rate_limited", message: "" } }) }
assert.equal(bannerFor(s, NOW, null).id, "rateLimited")
