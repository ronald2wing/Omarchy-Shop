// js/bar.mjs: the bar widget's rules (pills, the account pill, the total
// pill's state and tooltip), with the text from js/copy.mjs.
import assert from "node:assert/strict"
import { bannerFor } from "../../js/banner.mjs"
import * as B from "../../js/bar.mjs"
import * as T from "../../js/themes.mjs"

const NOW = Date.UTC(2025, 10, 7, 15, 0)

function store(domain, extra, salesExtra) {
  return Object.assign({
    domain: domain, label: domain.split(".")[0], showInBar: true, theme: null, currency: "USD", salesAccess: "granted", salesAccessError: null,
    sales: Object.assign({ status: "ok", pending: false, paused: false, retryAt: 0, error: null, fetchedAt: { today: NOW - 30000 }, today: { sales: 10, orders: 2 }, newOrderAt: 0, history: null }, salesExtra),
    themeState: Object.assign(T.emptyThemeState(), { job: null, lastResult: null, preview: T.emptyPreview() })
  }, extra)
}
function snapshot(stores, extra) {
  const map = {}
  for (const s of stores) map[s.domain] = s
  return Object.assign({ configError: null, configWriteError: null, stateError: null, cli: { status: "ready", missing: null, installs: "~/i", error: null }, account: { status: "signed_in", error: null },
    pins: { cli: "1", node: "2" }, settings: { pollSeconds: 60, alerts: { notify: false, sound: false }, bar: { display: "stores" } }, themesBusy: "", granting: false, stores: map }, extra)
}
const A = "a.myshopify.com"
const Bd = "b.myshopify.com"
const model = (snap, order, shown, vertical) => B.barModel(snap, order, shown || order, !!vertical, NOW)

// Store pills while everything loads.
let m = model(snapshot([store(A), store(Bd)]), [A, Bd])
assert.equal(m.accountPill, null)
assert.equal(m.showStores, true)
assert.equal(m.autoTotal, false)
assert.equal(m.singleDisplay, "icon")
assert.equal(m.totalLoading, false)
assert.deepEqual(m.totalTooltipLines, ["a — $10.00 · 2 orders", "b — $10.00 · 2 orders"])
assert.equal(m.totals.byCurrency[0].sales, 20)
assert.equal(m.initials, false, "two pills keep their labels")
// From BAR_INITIALS pills on (up to BAR_PILLS), the pills show initials.
for (let n = 1; n <= 5; n++) {
  const ds = ["a", "b", "c", "d", "e"].slice(0, n).map(x => x + ".myshopify.com")
  assert.equal(model(snapshot(ds.map(d => store(d))), ds).initials, n >= 4, n + " pills")
}
// Above five bar stores: one auto total over them.
const six = ["a", "b", "c", "d", "e", "f"].map(x => x + ".myshopify.com")
m = model(snapshot(six.map(d => store(d))), six)
assert.equal(m.autoTotal, true)
assert.equal(m.showStores, false)
assert.equal(m.singleDisplay, "total")
assert.equal(m.initials, false, "no pills, no initials")
assert.equal(m.totalTooltipLines.length, 6, "the auto total counts the bar stores")
// Vertical: the icon, with the banner's title over the lines and its dot.
m = model(snapshot([store(A, null, { fetchedAt: { today: NOW - 20 * 60000 } })]), [A], [A], true)
assert.equal(m.singleDisplay, "icon")
assert.equal(m.showStores, false)
assert.equal(m.dotTone, "warn", "the stale banner's tone")
assert.equal(m.totalTooltipLines[0], bannerFor(snapshot([store(A, null, { fetchedAt: { today: NOW - 20 * 60000 } })]), NOW, "").title)
// Settings: total / icon.
m = model(snapshot([store(A)], { settings: { pollSeconds: 60, alerts: {}, bar: { display: "total" } } }), [A])
assert.equal(m.singleDisplay, "total")
assert.equal(m.showStores, false)

// The account pill reads the raw state, never the banner.
// A config write error banner never hides the CLI-missing pill.
let snap = snapshot([store(A)], { configWriteError: { code: "config_write_failed", message: "x" }, cli: { status: "missing", missing: "cli", installs: "~/i" } })
assert.equal(bannerFor(snap, NOW, "").id, "configWriteError")
assert.deepEqual(model(snap, [A]).accountPill, { text: "󰒚 Install CLI", tone: "warn", tooltip: "The Shopify CLI isn't installed", view: "home" })
assert.equal(model(snap, [A]).showStores, false)
assert.equal(model(snapshot([store(A)], { cli: { status: "install_failed", error: { code: "cli_failed" } } }), [A]).accountPill.tone, "error")
assert.equal(model(snapshot([], { configError: { code: "config_invalid", message: "m" } }), []).accountPill.text, "󰒚 Config error")
assert.equal(model(snapshot([], { stateError: { code: "unsafe_state_dir", message: "m" } }), []).accountPill.tooltip, "Shop's state folder is a link or owned by someone else")
assert.equal(model(snapshot([store(A)], { cli: { status: "installing" } }), [A]).accountPill.text, "󰒚 Installing…")
// Signed out: the pill only while no store shows figures; a granted store
// keeps its pill. A store without access shows no figures (figuresBlocked),
// even with cached ones.
const noAccess = store(Bd, { salesAccess: "unknown" })
snap = snapshot([store(A), noAccess], { account: { status: "signed_out" } })
assert.equal(model(snap, [A, Bd]).accountPill, null, "a granted store keeps working")
assert.equal(B.anyFigures(snap, [A, Bd]), true)
snap = snapshot([noAccess], { account: { status: "signed_out" } })
assert.equal(B.anyFigures(snap, [Bd]), false, "cached figures of a muted store do not count")
assert.deepEqual(model(snap, [Bd]).accountPill, { text: "󰒚 Signed out", tone: "warn", tooltip: "You're signed out of Shopify", view: "home" })
// Signed out under a session-expired banner: still the signed-out pill.
const expired = store(Bd, { salesAccess: "unknown" }, { today: null })
expired.themeState = Object.assign({}, expired.themeState, { lastResult: { ok: false, error: { code: "theme_session_expired" } } })
snap = snapshot([expired], { account: { status: "signed_out" } })
assert.equal(bannerFor(snap, NOW, "").id, "sessionExpired")
assert.equal(model(snap, [Bd]).accountPill.text, "󰒚 Signed out")
assert.equal(model(snapshot([noAccess], { account: { status: "signing_in" } }), [Bd]).accountPill.text, "󰒚 Signing in…")
// The CLI check: failed says so (opening Settings), running says checking;
// neither with no stores or with figures.
const noFigures = store(A, null, { status: "idle", today: null, fetchedAt: { today: 0 } })
assert.deepEqual(model(snapshot([noFigures], { cli: { status: "unknown", error: { code: "timeout" } } }), [A]).accountPill, { text: "󰒚 CLI error", tone: "error", tooltip: "Shopify took too long to respond", view: "settings" })
assert.equal(model(snapshot([noFigures], { cli: { status: "checking" } }), [A]).accountPill.text, "󰒚 Checking…")
assert.equal(model(snapshot([], { cli: { status: "checking" } }), []).accountPill, null)
assert.equal(model(snapshot([store(A)], { cli: { status: "checking" } }), [A]).accountPill, null)

// storeLine and totalLoading share Metrics.awaitingFigures: a rate-limited
// store with a retry scheduled is loading ("…"), one without a retry is not.
const limited = store(A, null, { status: "error", today: null, error: { code: "rate_limited", message: "" }, retryAt: NOW + 60000 })
m = model(snapshot([limited]), [A])
assert.equal(B.storeLine(limited), "…")
assert.equal(m.totalLoading, true)
assert.equal(m.limited, true)
assert.equal(m.totalProblem, false)
assert.deepEqual(m.totalTooltipLines, ["a — …", "Shopify is limiting requests"])
const limitedNoRetry = store(A, null, { status: "error", today: null, error: { code: "rate_limited", message: "" }, retryAt: 0 })
assert.equal(B.storeLine(limitedNoRetry), "—")
assert.equal(model(snapshot([limitedNoRetry]), [A]).totalLoading, false)
// Pending, idle: loading. Paused: "—". Needs access: its own line, never loading.
assert.equal(B.storeLine(store(A, null, { status: "idle", today: null })), "…")
assert.equal(model(snapshot([store(A, null, { pending: true })]), [A]).totalLoading, true, "a pending refetch over figures")
assert.equal(B.storeLine(store(A, null, { status: "idle", today: null, paused: true })), "—")
const needs = store(A, { salesAccess: "required" }, { status: "idle", today: null, pending: true })
assert.equal(B.storeLine(needs), "Sales access needed")
m = model(snapshot([needs]), [A])
assert.equal(m.totalLoading, false)
assert.equal(m.totalProblem, true)
// A failed store: the figure and the error, and the problem glyph.
const failed = store(A, null, { status: "error", error: { code: "cli_failed", message: "" } })
assert.equal(B.storeLine(failed), "$10.00 · 2 orders · 󰀨 The Shopify CLI failed: ")
assert.equal(B.storeLine(store(A, null, { status: "error", today: null, error: { code: "cli_failed", message: "" } })), "󰀨 The Shopify CLI failed: ")
assert.equal(model(snapshot([failed]), [A]).totalProblem, true)

// latestNewOrderAt: the newest across every store, shown or not.
m = model(snapshot([store(A, null, { newOrderAt: 5 }), store(Bd, { showInBar: false }, { newOrderAt: 9 })]), [A, Bd], [A])
assert.equal(m.latestNewOrderAt, 9)
assert.equal(model(null, [], []).accountPill, null)
assert.equal(model(null, [], []).totals, null)
