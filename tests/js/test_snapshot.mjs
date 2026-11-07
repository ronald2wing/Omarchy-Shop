// js/snapshot.mjs: the pins, the selectors views share and the snapshot
// builder (with per-store identity).
import assert from "node:assert/strict"
import { load } from "./fixture.mjs"
import * as S from "../../js/snapshot.mjs"
import * as T from "../../js/themes.mjs"
import { emptyRecord, applyFetchResult } from "../../js/sales.mjs"
import { bannerFor } from "../../js/banner.mjs"

const today = load("today.json")
const yRes = load("yesterday.json")
const history = load("history.json")
// A store record with today, yesterday and history (js/sales.mjs), and one
// whose today fetch needs access.
const fold = (st, r, range, withTraffic) => applyFetchResult(st, r, { domain: r.domain, range: range, withTraffic: withTraffic, nowMs: r.fetchedAt, pollSeconds: 60 }).record
const st = fold(fold(fold(emptyRecord(), today, "today", true), yRes, "yesterday"), history, "history")
const er = fold(st, load("fetch-error.json"), "today")
const STOPPED = { status: "stopped", url: "", error: null }
const noTraffic = Object.assign({}, today, { fetchedAt: today.fetchedAt + 60000, today: Object.assign({}, today.today, { traffic: null }) })

// The pins themselves are checked against Shop::CLI_PIN / NODE_PIN by
// tests/ruby/test_source_contracts.rb; no test spells a version.
assert.match(S.CLI_PIN, /^\d+\.\d+\.\d+$/)
assert.match(S.NODE_PIN, /^\d+\.\d+\.\d+$/)

// Selectors over a snapshot store.
const themed = {
  domain: "acme.myshopify.com", theme: { folder: "/home/u/themes/acme", target: "live", allowLive: false },
  themeState: {
    themes: { status: "ok", items: [{ id: "1", name: "Dawn", role: "live" }, { id: "2", name: "Dev", role: "unpublished" }], fetchedAt: 1, error: null },
    folder: Object.assign(T.emptyFolder(), { status: "ok", requested: "/home/u/themes/acme", rootFiles: ["AGENTS.md"] }),
    backups: { status: "ok", items: [{ id: "1762500000-1", at: 1762500000000, theme: { id: "1", name: "Dawn", role: "live" }, before: "push", files: 3, bytes: 9 }], folderCopies: [], error: null }
  }
}
assert.deepEqual(S.targetTheme(themed), { id: "1", name: "Dawn", live: true })
assert.deepEqual(S.targetTheme(Object.assign({}, themed, { theme: { folder: "/x", target: "2", allowLive: false } })), { id: "2", name: "Dev", live: false })
assert.deepEqual(S.targetTheme(Object.assign({}, themed, { theme: { folder: "/x", target: "9", allowLive: false } })), { id: "9", name: "", live: false })
assert.deepEqual(S.targetTheme({ theme: { target: "live" } }), { id: "", name: "", live: true }, "no themes list yet")
assert.deepEqual(S.targetTheme(null), { id: "", name: "", live: true })

// buildSnapshot
const cfgStores = [
  { domain: "acme.myshopify.com", label: "Acme", showInBar: true, theme: { folder: "/x", target: "live", allowLive: false } },
  { domain: "beta.myshopify.com", label: "Beta", showInBar: false, theme: null }
]
const acmePart = { cfg: cfgStores[0], sales: st, info: null, job: null, preview: { status: "ready", url: "http://127.0.0.1:9292/", error: null }, pending: false, granting: false, retryAt: 0 }
const betaPart = { cfg: cfgStores[1], sales: null, info: Object.assign(T.emptyThemeState(), { folder: Object.assign(T.emptyFolder(), { status: "ok" }) }),
  job: { job: { action: "push", startedAt: 1 }, lastResult: null }, preview: null, pending: true, granting: true, retryAt: 0 }
const parts = {
  configError: null, invalidStores: [{ index: 2, domain: null, problem: "missing domain" }],
  cli: { status: "ready" }, account: { status: "signed_in", error: null }, alertTools: { notify: true, sound: null },
  pendingConfirm: null, settings: { pollSeconds: 60, alerts: { notify: true, sound: true }, bar: { display: "stores" } },
  discovery: { status: "done", stores: [{ domain: "acme.myshopify.com", name: "Acme" }, { domain: "delta.myshopify.com", name: "Delta" }], truncated: false, finishedAt: 5, error: null },
  salesPaused: false,
  stores: [acmePart, betaPart]
}
const build = S.buildSnapshot(parts, null)
const snap = build.snapshot
assert.deepEqual(Object.keys(build.memo), ["acme.myshopify.com", "beta.myshopify.com"], "the memo holds each store's inputs")
assert.deepEqual(snap.pins, { cli: S.CLI_PIN, node: S.NODE_PIN })
assert.deepEqual(snap.stores["beta.myshopify.com"].themeState.preview, STOPPED, "a store without a preview reads as stopped")
assert.deepEqual(Object.keys(snap.stores), ["acme.myshopify.com", "beta.myshopify.com"])
assert.equal(snap.storeOrder, undefined, "storeOrder is not in the snapshot")
const a = snap.stores["acme.myshopify.com"]
assert.equal(a.label, "Acme")
assert.equal(a.currency, "USD")
assert.equal(a.salesAccess, "granted")
assert.equal(a.sales.today.sales, 812)
assert.equal(a.sales.pending, false)
assert.equal(a.sales.paused, false)
assert.equal(a.themeState.preview.status, "ready")
assert.equal(a.themeState.folder.status, "unknown")
assert.equal(a.themeState.job, null)
const bta = snap.stores["beta.myshopify.com"]
assert.equal(bta.sales.status, "loading", "idle + pending reads as loading")
assert.equal(bta.sales.pending, true)
assert.equal(bta.salesAccess, "granting", "the grant in flight overlays the stored access")
assert.equal(bta.themeState.folder.status, "ok")
assert.equal(bta.themeState.job.action, "push")
// Discovery's result (already clean) passes through as is.
assert.equal(snap.discovery, parts.discovery)
assert.deepEqual(S.buildSnapshot({ stores: [] }, null).snapshot.discovery, S.emptyDiscovery())
// The cache-only record (yesterday orders) never reaches the snapshot.
assert(!JSON.stringify(snap).includes("1762405300000"))
// The scheduler's retryAt lands on sales.retryAt; salesPaused on every store.
const failing = S.buildSnapshot({ salesPaused: true, stores: [{ cfg: cfgStores[0], sales: er, retryAt: 77 }] }, null).snapshot
assert.equal(failing.stores["acme.myshopify.com"].sales.retryAt, 77)
assert.equal(failing.stores["acme.myshopify.com"].sales.paused, true)
assert.equal(failing.stores["acme.myshopify.com"].sales.error.code, "sales_access_required")

// Identity: a rebuild with the same inputs (and the previous build)
// reuses each store object; a change to one store rebuilds only that
// store. buildSnapshot keeps no state of its own: the caller hands back
// the build it published.
const withParts = (base, i, change) => Object.assign({}, base, { stores: base.stores.map((p, k) => k === i ? Object.assign({}, p, change) : p) })
const buildA = S.buildSnapshot(parts, build)
assert(buildA.snapshot !== snap)
assert(buildA.snapshot.stores["acme.myshopify.com"] === a, "acme reused")
assert(buildA.snapshot.stores["beta.myshopify.com"] === bta, "beta reused")
assert(S.buildSnapshot(parts, { snapshot: snap, memo: null }).snapshot.stores["acme.myshopify.com"] !== a, "no memo: fresh objects")
const buildB = S.buildSnapshot(parts, build)
assert(buildB.snapshot.stores["acme.myshopify.com"] === a, "an older build is just as good: no hidden module state")
const parts2 = withParts(parts, 0, { sales: fold(st, noTraffic, "today", false) })
const buildC = S.buildSnapshot(parts2, buildA)
assert(buildC.snapshot.stores["acme.myshopify.com"] !== a, "acme rebuilt")
assert(buildC.snapshot.stores["beta.myshopify.com"] === bta, "beta still reused")
const buildD = S.buildSnapshot(withParts(parts2, 1, { retryAt: 5 }), buildC)
assert(buildD.snapshot.stores["beta.myshopify.com"] !== bta, "a retryAt change rebuilds the store")
assert(buildD.snapshot.stores["acme.myshopify.com"] === buildC.snapshot.stores["acme.myshopify.com"])
assert(S.buildSnapshot(withParts(parts2, 1, { retryAt: 5, granting: false }), buildD).snapshot.stores["beta.myshopify.com"] !== buildD.snapshot.stores["beta.myshopify.com"], "access overlay change rebuilds")
const pausedAll = S.buildSnapshot(Object.assign({}, parts, { salesPaused: true }), build).snapshot
assert(pausedAll.stores["acme.myshopify.com"] !== a && pausedAll.stores["acme.myshopify.com"].sales.paused === true, "salesPaused rebuilds every store")
// A store object is never mutated by a later build.
assert.equal(a.sales.today.sales, 812)
assert.equal(S.buildSnapshot(parts, null).snapshot.stores["acme.myshopify.com"] !== a, true, "no previous: fresh objects")
// A store without any state keeps its identity too (the shared empty record).
const bare = { stores: [{ cfg: cfgStores[1] }] }
const bare1 = S.buildSnapshot(bare, null)
assert(S.buildSnapshot(bare, bare1).snapshot.stores["beta.myshopify.com"] === bare1.snapshot.stores["beta.myshopify.com"])

const init = S.initialSnapshot()
assert.deepEqual(init.stores, {})
assert.equal(init.cli.status, "unknown")
assert.equal(init.stateError, null)
assert.equal(init.pendingConfirm, null)
assert.equal(init.pins.cli, S.CLI_PIN)
assert.equal(init.themesBusy, "", "nothing busy at start")
assert.equal(init.granting, false)
assert.equal(S.buildSnapshot({ themesBusy: "job", granting: true, stores: [] }, null).snapshot.themesBusy, "job", "themesBusy passes through")
assert.equal(S.buildSnapshot({ themesBusy: "bogus", stores: [] }, null).snapshot.themesBusy, "", "unknown themesBusy reads as idle")
assert.equal(S.buildSnapshot({ granting: true, stores: [] }, null).snapshot.granting, true)
assert.deepEqual(S.buildSnapshot({ stateError: { code: "x", message: "m" }, stores: [] }, null).snapshot.stateError, { code: "x", message: "m" }, "stateError passes through")

// statusSummary: the snapshot's stores, in config order.
const sum = S.statusSummary(snap, "2.0.0")
assert.equal(sum.ok, true)
assert.equal(sum.version, "2.0.0")
assert.equal(sum.pins.node, S.NODE_PIN)
assert.deepEqual(sum.stores.map(s => s.domain), ["acme.myshopify.com", "beta.myshopify.com"])
assert.deepEqual(sum.stores[0].today, { sales: 812, orders: 21, fetchedAt: today.fetchedAt })
assert.equal(sum.stores[0].trend.direction, "up")
assert.equal(sum.stores[1].today.sales, null)
assert.equal(sum.stores[1].salesAccess, "granting")

// needsAccess: the one access predicate every view shares.
assert.deepEqual(["required", "granting", "granted", "unknown", "authorizing", undefined].map(S.needsAccess), [true, true, false, false, false, false])

// storeOf / themeState / salesFailed / salesRateLimited: the selectors
// the bar, the rows and the views share.
const snapStores = { stores: { "acme.myshopify.com": { domain: "acme.myshopify.com", themeState: { job: null } } } }
assert.equal(S.storeOf(snapStores, "acme.myshopify.com").domain, "acme.myshopify.com")
assert.equal(S.storeOf(snapStores, "nope"), null)
assert.equal(S.storeOf(null, "x"), null)
assert.deepEqual(S.themeState(S.storeOf(snapStores, "acme.myshopify.com")), { job: null })
assert.equal(S.themeState(null), null)
const failedStore = { sales: { status: "error", error: { code: "cli_failed", message: "" } } }
const limitedStore = { sales: { status: "ok", error: { code: "rate_limited", message: "" } } }
assert.equal(S.salesFailed(failedStore), true)
assert.equal(S.salesFailed(limitedStore), false)
assert.equal(S.salesFailed({ sales: { status: "ok", error: null } }), false)
assert.equal(S.salesFailed(null), false)
assert.equal(S.salesRateLimited(limitedStore), true)
assert.equal(S.salesRateLimited(failedStore), false)
assert.equal(S.salesRateLimited(null), false)

// ---- accountBlock / figuresBlocked: raw fields, never the banner ----
const abT = (key, vars) => vars ? key + JSON.stringify(vars) : key
const abErrorOf = e => e ? "error." + e.code : ""
const abTs = extra => Object.assign(T.emptyThemeState(), { job: null, lastResult: null, preview: T.emptyPreview() }, extra)
const abStore = (extra, tsExtra) => Object.assign({ domain: "acme.myshopify.com", label: "Acme", theme: { folder: "/home/u/acme", target: "live", allowLive: false }, salesAccess: "granted", sales: { status: "ok", today: { sales: 10, orders: 1 } }, themeState: abTs(tsExtra) }, extra)
const abSnapshot = extra => Object.assign({ configError: null, configWriteError: null, stateError: null, cli: { status: "ready", missing: null }, account: { status: "signed_in" }, themesBusy: "", granting: false, stores: {} }, extra)
assert.equal(S.accountBlock(null), "")
assert.equal(S.accountBlock(abSnapshot({})), "")
assert.equal(S.accountBlock(abSnapshot({ stateError: { code: "unsafe_state_dir" }, configError: { code: "config_invalid" } })), "state")
assert.equal(S.accountBlock(abSnapshot({ configError: { code: "config_invalid" }, cli: { status: "missing" } })), "config")
assert.equal(S.accountBlock(abSnapshot({ cli: { status: "missing" }, account: { status: "signed_out" } })), "cli")
assert.equal(S.accountBlock(abSnapshot({ cli: { status: "install_failed" } })), "cli")
assert.equal(S.accountBlock(abSnapshot({ cli: { status: "installing" }, account: { status: "signed_out" } })), "installing")
assert.equal(S.accountBlock(abSnapshot({ account: { status: "signed_out" } })), "signedOut")
assert.equal(S.accountBlock(abSnapshot({ account: { status: "signing_in" } })), "signingIn")
assert.equal(S.accountBlock(abSnapshot({ account: { status: "signing_out" } })), "", "signing out blocks no figures")
assert.equal(S.accountBlock(abSnapshot({ cli: { status: "unknown", error: { code: "timeout" } } })), "", "a failed check is no block")
assert.equal(S.accountBlock(abSnapshot({ configWriteError: { code: "config_write_failed" } })), "", "a write error is no block")
const granted = abStore({})
const required = abStore({ salesAccess: "required" })
const unknown = abStore({ salesAccess: "unknown" })
for (const extra of [{ stateError: { code: "x" } }, { configError: { code: "config_invalid" } }, { cli: { status: "missing" } }, { cli: { status: "installing" } }])
  for (const s of [granted, required, null]) assert.equal(S.figuresBlocked(abSnapshot(extra), s), true, JSON.stringify(extra))
for (const acc of ["signed_out", "signing_in"]) {
  assert.equal(S.figuresBlocked(abSnapshot({ account: { status: acc } }), granted), false, acc + ": a granted store keeps fetching")
  assert.equal(S.figuresBlocked(abSnapshot({ account: { status: acc } }), unknown), true, acc)
  assert.equal(S.figuresBlocked(abSnapshot({ account: { status: acc } }), null), true, acc)
}
assert.equal(S.figuresBlocked(abSnapshot({}), unknown), false)

// The disagreements this module ended: the banner shows one state while
// the raw state blocks figures; Home, the store view and the bar all read
// accountBlock / figuresBlocked, so they agree whatever banner shows.
// 1. A config write error banner over a missing CLI.
let abSnap = abSnapshot({ configWriteError: { code: "config_write_failed", message: "disk full" }, cli: { status: "missing", missing: "cli", installs: "~/x" }, pins: { cli: "1", node: "2" } })
assert.equal(bannerFor(abSnap, 0, "", abT, abErrorOf).id, "configWriteError")
assert.equal(S.accountBlock(abSnap), "cli")
assert.equal(S.figuresBlocked(abSnap, granted), true)
// 2. A session-expired banner while signed out.
const expired = abStore({ salesAccess: "unknown" }, { lastResult: { ok: false, error: { code: "theme_session_expired" } } })
abSnap = abSnapshot({ account: { status: "signed_out" }, stores: { "acme.myshopify.com": expired } })
assert.equal(bannerFor(abSnap, 0, "", abT, abErrorOf).id, "sessionExpired")
assert.equal(S.accountBlock(abSnap), "signedOut")
assert.equal(S.figuresBlocked(abSnap, expired), true)
