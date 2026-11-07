// js/sales.mjs: the sales record reducers, fetch and grant results, the
// new-order rule and the cache record.
import assert from "node:assert/strict"
import { load } from "./fixture.mjs"
import * as S from "../../js/sales.mjs"
import { salesFailed, needsAccess } from "../../js/snapshot.mjs"

const today = load("today.json")
const yRes = load("yesterday.json")
const y = Object.assign({}, yRes.yesterday, { fetchedAt: yRes.fetchedAt })
const history = load("history.json")
const NOW = today.fetchedAt
// The reducers run through applyFetchResult, the one entry point: a
// fetch-sales result for `range`, or a failure for it.
const run = (st, r, range, o) => S.applyFetchResult(st, Object.assign({ ok: true }, r), Object.assign({ domain: r.domain, range: range, nowMs: NOW, pollSeconds: 60 }, o)).record
const tick = (st, r, withTraffic) => run(st, r, "today", { withTraffic: withTraffic })
const fail = (st, range, error) => S.applyFetchResult(st, { ok: false, error: error }, { range: range }).record
const withDay = (fields) => Object.assign({}, yRes, { yesterday: Object.assign({}, yRes.yesterday, fields) })

assert.equal(S.CACHE_VERSION, 5)

// emptyRecord
const e = S.emptyRecord()
assert.equal(e.salesAccess, "unknown")
assert.equal(e.sales.status, "idle")
assert.deepEqual(e.sales.fetchedAt, { today: 0, traffic: 0, history: 0 })
assert.equal(e.sales.history, null)

// A today result: meta, today, access, baseline null without yesterday.
let st = tick(e, today, true)
assert.equal(e.sales.today, null, "input untouched")
assert.equal(st.currency, "USD")
assert.equal(st.timezone, "America/Toronto")
assert.equal(st.localDate, "2025-11-07")
assert.equal(st.dayEndsAt, 1762578000000)
assert.equal(st.salesAccess, "granted")
assert.equal(st.sales.status, "ok")
assert.equal(st.sales.today.sales, 812)
assert.equal(st.sales.today.orders, 21)
assert.equal(st.sales.today.traffic.sessions, 1621)
assert.equal(st.sales.today.baseline, null)
assert.equal(st.sales.today.truncated, false)
// fetch-sales says `truncated` at the top level of its line, never inside
// `today`: a cut paging run (order cap, throttle or timeout mid-paging)
// marks the day's figure partial.
assert.equal(tick(e, Object.assign({}, today, { truncated: true }), true).sales.today.truncated, true, "top-level truncated reaches sales.today")
assert.equal("truncated" in today.today, false, "the fixture matches the helper (truncated is top-level only)")
assert.equal(tick(e, Object.assign({}, today, { today: Object.assign({}, today.today, { truncated: true }) }), true).sales.today.truncated, false, "a flag inside the range object is not read (fetch-sales never puts one there)")
assert.equal(st.sales.fetchedAt.today, today.fetchedAt)
assert.equal(st.sales.fetchedAt.traffic, today.fetchedAt)
// The hourly chart for today: 24 buckets from startEpoch, the orders binned by
// orderPoints, the sessions from trafficHourly, the current hour (08:00 local at
// fetchedAt) partial, later hours empty.
assert.equal(st.sales.todayHourly.length, 24)
assert.deepEqual(st.sales.todayHourly[1], { hour: 1, sales: 100, sessions: 110 })
assert.deepEqual(st.sales.todayHourly[6], { hour: 6, sales: 200.5, sessions: 160 })
assert.deepEqual(st.sales.todayHourly[7], { hour: 7, sales: 511.5, sessions: 170 })
assert.deepEqual(st.sales.todayHourly[8], { hour: 8, sales: 0, sessions: 180, partial: true })
assert.deepEqual(st.sales.todayHourly[23], { hour: 23, sales: 0, sessions: null })
assert.equal(st.sales.todayHourly.reduce((a, b) => a + b.sales, 0), 812)

// A today tick without traffic keeps the day's traffic.
const noTraffic = Object.assign({}, today, { fetchedAt: today.fetchedAt + 60000, today: Object.assign({}, today.today, { traffic: null }) })
let st2 = tick(st, noTraffic, false)
assert.equal(st2.sales.today.traffic.sessions, 1621)
assert.equal(st2.sales.fetchedAt.traffic, today.fetchedAt)
assert.equal(st2.sales.todayHourly[1].sessions, 110, "the hourly sessions are kept too")
assert.equal(st2.sales.todayHourly[8].partial, true, "a tick a minute later: still hour 8")
const laterTick = tick(st, Object.assign({}, noTraffic, { fetchedAt: today.fetchedAt + 3600000 }), false)
assert.equal(laterTick.sales.todayHourly[9].partial, true, "the partial hour follows the tick's time")
assert.equal("partial" in laterTick.sales.todayHourly[8], false)
// ... but not across a new local day.
const nextDay = Object.assign({}, noTraffic, { localDate: "2025-11-08" })
assert.equal(tick(st, nextDay, false).sales.today.traffic, null)
assert.equal(tick(st, nextDay, false).sales.todayHourly[1].sessions, null)
// With traffic asked for and unsupported, it is null.
assert.equal(tick(st, noTraffic, true).sales.today.traffic, null)
// A today payload without the chart fields (startEpoch) draws nothing.
const bare = Object.assign({}, today, { today: { sales: 1, orders: 1 } })
assert.deepEqual(tick(e, bare, false).sales.todayHourly, [])

// Yesterday then baseline (yesterday for the day before localDate).
st = run(st, yRes, "yesterday")
assert.equal(st.yesterday.date, "2025-11-06")
assert.equal(st.yesterday.truncated, false)
assert.equal(run(st, Object.assign({}, yRes, { truncated: true }), "yesterday").yesterday.truncated, true, "top-level truncated reaches yesterday")
assert.equal(S.fromCache({ yesterday: Object.assign({}, y, { truncated: true }) }).yesterday.truncated, true, "a flat cache record keeps its own flag")
assert.equal(st.yesterday.startEpoch, 1762405200, "epochs kept as the helper prints them (seconds)")
assert.equal(st.sales.yesterdayHourly.length, 24)
assert.equal(st.sales.yesterdayHourly[22].sales, -25, "the chart is salesHourly (Analytics), not the order totals")
assert.equal(st.sales.yesterdayHourly[23].sales, 35)
assert.deepEqual(S.fromCache({ yesterday: Object.assign({}, y, { salesHourly: null }) }).sales.yesterdayHourly, [], "no Analytics series, no chart")
assert.deepEqual(run(st, withDay({ salesHourly: null }), "yesterday").sales.today.baseline.sales, 150.5, "the baseline still reads the orders")
assert.deepEqual(st.sales.today.baseline, { sales: 150.5, orders: 2, traffic: { sessions: 140, cartAdds: 13, reachedCheckout: 5, completed: 2 } })
// A yesterday for another day gives no baseline.
const stale = run(tick(S.emptyRecord(), today, true), withDay({ date: "2025-11-01" }), "yesterday")
assert.equal(stale.sales.today.baseline, null)

// History
st = run(st, history, "history")
assert.equal(st.sales.history.last7d.sales, 5412.8)
assert.equal(st.sales.fetchedAt.history, history.fetchedAt)
assert.equal(st.historyLocalDate, "2025-11-07")

// Errors: a today error flips status; access errors set access.
let er = fail(st, "history", { code: "timeout", message: "slow" })
assert.equal(er.sales.status, "ok", "a history error keeps the today status")
assert.deepEqual(er.sales.error, { code: "timeout", message: "slow", range: "history" })
er = run(er, history, "history")
assert.equal(er.sales.error, null, "history success clears a history error")
er = fail(st, "today", { code: "rate_limited", message: "x", retryAfter: 30 })
assert.equal(er.sales.status, "error")
assert.equal(er.sales.error.retryAfter, 30)
er = fail(st, "today", load("fetch-error.json").error)
assert.equal(er.salesAccess, "required")
assert.equal(fail(st, "today", { code: "store_unavailable" }).salesAccess, "granted", "a paused store keeps its access")
assert.equal(tick(er, today, false).salesAccess, "granted")
assert.equal(tick(er, today, false).sales.error, null)
assert.equal(fail(S.emptyRecord(), "history", { code: "timeout" }).sales.status, "error", "no figures yet: any error shows")

// The new-order rule: today's result (21 orders) against the last-seen record.
const latestId = today.today.latestOrder.id
const seen = { orderCount: 20, latestOrderId: "gid://shopify/Order/0", localDate: "2025-11-07", at: NOW - 60000 }
const after = lastSeen => S.applyFetchResult(Object.assign(S.emptyRecord(), { lastSeen: lastSeen }), today, { domain: today.domain, range: "today", withTraffic: true, nowMs: NOW, pollSeconds: 60 })
const d = after(seen)
assert.equal(d.newOrders, 1)
assert.equal(d.record.sales.newOrderAt, NOW)
assert.deepEqual(d.record.lastSeen, { orderCount: 21, latestOrderId: latestId, localDate: "2025-11-07", at: NOW })
assert.equal(after(Object.assign({}, seen, { latestOrderId: latestId })).newOrders, 0, "same latest order")
assert.equal(after(Object.assign({}, seen, { localDate: "2025-11-06" })).newOrders, 0, "new day")
assert.equal(after(Object.assign({}, seen, { at: NOW - 181000 })).newOrders, 0, "gap > 3 polls")
assert.equal(after(Object.assign({}, seen, { orderCount: 21 })).newOrders, 0, "no rise")
assert.equal(after(Object.assign({}, seen, { orderCount: 18 })).newOrders, 3)

// Cache round trip warms the history and baseline but not today's figures.
st = Object.assign({}, st, { lastSeen: d.record.lastSeen })
const rec = JSON.parse(JSON.stringify(S.cacheRecord(st)))
assert.deepEqual(Object.keys(rec).sort(), ["currency", "dayEndsAt", "history", "historyFetchedAt", "historyLocalDate", "lastSeen", "timezone", "utcOffsetMinutes", "yesterday"])
const warm = S.fromCache(rec)
assert.equal(warm.sales.today, null)
assert.equal(warm.sales.history.last7d.sales, 5412.8)
assert.equal(warm.sales.fetchedAt.history, history.fetchedAt)
assert.equal(warm.yesterday.date, "2025-11-06")
assert.deepEqual(warm.sales.yesterdayHourly, st.sales.yesterdayHourly, "the cached day redraws the same Analytics chart")
assert.equal(warm.currency, "USD")
assert.equal(warm.salesAccess, "unknown")
assert.equal(warm.localDate, "", "the cached local date is never trusted")
assert.deepEqual(warm.lastSeen, d.record.lastSeen)
assert.equal(S.fromCache(null).sales.status, "idle")
assert.equal(S.fromCache({ history: "junk" }).sales.history, null)

// applyGrantResult. A grant succeeded: the access error a fetch left is
// cleared at once (no "Sales access needed" until the next fetch); other
// errors stay. A failed grant keeps its error as salesAccessError.
{
  const base = tick(S.emptyRecord(), today, true)
  const denied = fail(base, "today", { code: "sales_access_required", message: "no" })
  assert.equal(salesFailed({ sales: denied.sales }), true, "denied: the row is red")
  assert.equal(needsAccess(denied.salesAccess), true)
  const granted = S.applyGrantResult(denied, { ok: true, name: "Acme" })
  assert.equal(granted.salesAccess, "granted")
  assert.equal(granted.salesAccessError, null)
  assert.equal(needsAccess(granted.salesAccess), false)
  assert.equal(salesFailed({ sales: granted.sales }), false, "granted: no stale access error")
  assert.equal(granted.sales.status, "ok", "figures held: ok")
  const fresh = S.applyGrantResult(fail(S.emptyRecord(), "today", { code: "sales_access_required" }), { ok: true })
  assert.equal(fresh.sales.status, "idle", "no figures yet: idle (loading only while a fetch is pending)")
  const other = S.applyGrantResult(fail(base, "today", { code: "timeout" }), { ok: true })
  assert.equal(other.sales.error.code, "timeout", "other errors are left alone")
  const refused = S.applyGrantResult(base, { ok: false, error: { code: "sales_access_required", message: "m" } })
  assert.equal(refused.salesAccess, "required")
  assert.deepEqual(refused.salesAccessError, { code: "sales_access_required", message: "m" })
  assert.equal(refused.sales, base.sales, "a failed grant leaves the figures")
  const cancelled = S.applyGrantResult(base, { ok: false, error: { code: "terminated", message: "" } })
  assert.equal(cancelled.salesAccess, "granted", "any other failure keeps the access held")
  assert.equal(cancelled.salesAccessError.code, "terminated")
}

// applyFetchResult: one finished fetch-sales run, with the new-order rule
// and whether cache.json changes.
{
  const opts = { domain: "acme.myshopify.com", range: "today", withTraffic: true, nowMs: today.fetchedAt, pollSeconds: 60 }
  assert.equal(S.applyFetchResult(S.emptyRecord(), Object.assign({}, today, { domain: "other.myshopify.com" }), opts), null, "a result for another store is ignored")
  const first = S.applyFetchResult(S.emptyRecord(), today, opts)
  assert.equal(first.record.sales.today.orders, 21)
  assert.equal(first.newOrders, 0, "first sight is silent")
  assert.equal(first.cache, true, "the first last-seen record is cached")
  assert.equal(first.errorCode, "")
  assert.deepEqual(first.record.lastSeen, { orderCount: 21, latestOrderId: today.today.latestOrder.id, localDate: "2025-11-07", at: today.fetchedAt })
  assert.equal(first.record.sales.newOrderAt, 0)
  const same = S.applyFetchResult(first.record, today, Object.assign({}, opts, { nowMs: today.fetchedAt + 60000 }))
  assert.equal(same.cache, false, "a tick with the same last order writes nothing")
  assert.equal(same.newOrders, 0)
  const more = Object.assign({}, today, { today: Object.assign({}, today.today, { orders: 23, latestOrder: Object.assign({}, today.today.latestOrder, { id: "gid://shopify/Order/new" }) }) })
  const rise = S.applyFetchResult(first.record, more, Object.assign({}, opts, { nowMs: today.fetchedAt + 60000 }))
  assert.equal(rise.newOrders, 2)
  assert.equal(rise.cache, true)
  assert.equal(rise.record.sales.newOrderAt, today.fetchedAt + 60000)
  const hist = S.applyFetchResult(first.record, history, Object.assign({}, opts, { range: "history" }))
  assert.equal(hist.record.sales.history.last7d.sales, 5412.8)
  assert.deepEqual([hist.newOrders, hist.cache, hist.errorCode], [0, true, ""])
  const yest = S.applyFetchResult(first.record, yRes, Object.assign({}, opts, { range: "yesterday" }))
  assert.equal(yest.record.yesterday.date, "2025-11-06")
  assert.equal(yest.cache, true)
  const failed = S.applyFetchResult(first.record, { ok: false, error: { code: "signed_out", message: "x" } }, opts)
  assert.equal(failed.errorCode, "signed_out")
  assert.equal(failed.cache, false)
  assert.equal(failed.record.sales.error.range, "today")
}

// The building blocks: withMeta (place and day), withHistory (the figures
// alone), markGranted (the access a live fetch proves), normalizeYesterday
// (the one yesterday shape) and clearRangeError.
{
  const base = S.emptyRecord()
  const m = S.withMeta(base, { currency: "EUR", timezone: "", utcOffsetMinutes: "60", dayEndsAt: 7, localDate: "2025-11-07" })
  assert.deepEqual([m.currency, m.timezone, m.utcOffsetMinutes, m.dayEndsAt, m.localDate], ["EUR", "", 0, 7, "2025-11-07"], "malformed meta fields keep the old value")
  assert.equal(base.currency, "", "withMeta leaves its input")
  const h = S.withHistory(base, history)
  assert.equal(h.sales.history.last7d.sales, 5412.8)
  assert.equal(h.sales.fetchedAt.history, history.fetchedAt)
  assert.equal(h.historyLocalDate, "2025-11-07")
  assert.equal(h.sales.status, "ok", "idle becomes ok")
  assert.equal(h.salesAccess, "unknown", "withHistory leaves access alone")
  assert.equal(h.localDate, "", "withHistory leaves the meta alone")
  assert.equal(h.currency, "")
  assert.equal(base.sales.history, null, "withHistory leaves its input")
  assert.equal(S.withHistory(base, { history: "junk", fetchedAt: "x", localDate: 3 }).sales.history, null)
  const errored = Object.assign({}, base, { sales: Object.assign({}, base.sales, { status: "error", error: { code: "timeout", range: "today" } }) })
  assert.equal(S.withHistory(errored, history).sales.status, "error", "an error status stays")
  assert.equal(S.withHistory(errored, history).sales.error.range, "today", "another range's error stays")
  const g = S.markGranted(Object.assign({}, base, { salesAccess: "required", salesAccessError: { code: "x" } }))
  assert.deepEqual([g.salesAccess, g.salesAccessError], ["granted", null])
  assert.equal(g.sales, base.sales, "markGranted touches nothing else")
  assert.deepEqual(S.normalizeYesterday(y), { date: "2025-11-06", startEpoch: y.startEpoch, endEpoch: y.endEpoch, orderPoints: y.orderPoints,
    truncated: false, salesHourly: y.salesHourly, trafficHourly: y.trafficHourly, fetchedAt: yRes.fetchedAt })
  assert.deepEqual(S.normalizeYesterday({ date: 1, orderPoints: "x", truncated: 1, salesHourly: {}, fetchedAt: "now" }),
    { date: "", startEpoch: undefined, endEpoch: undefined, orderPoints: [], truncated: true, salesHourly: null, trafficHourly: null, fetchedAt: 0 })
  // The helper's nested line and the cache's flat day give the same record.
  assert.deepEqual(run(base, yRes, "yesterday").yesterday, S.normalizeYesterday(y))
  const err = { code: "timeout", range: "history" }
  assert.equal(S.clearRangeError(err, "history"), null)
  assert.equal(S.clearRangeError(err, "today"), err)
  assert.equal(S.clearRangeError(null, "today"), null)
}

// fromCache warms the data only: the same record the live reducers build,
// minus what only a live fetch proves (access, the local date).
{
  const live = run(run(S.emptyRecord(), history, "history"), yRes, "yesterday")
  const warmed = S.fromCache(JSON.parse(JSON.stringify(S.cacheRecord(live))))
  const expected = Object.assign({}, live, { salesAccess: "unknown", localDate: "" })
  assert.deepEqual(warmed, JSON.parse(JSON.stringify(expected)))
  assert.equal(S.fromCache({ localDate: "2025-11-07", currency: "EUR" }).localDate, "", "a cached local date is ignored")
  assert.equal(S.fromCache({ localDate: "2025-11-07", currency: "EUR" }).currency, "EUR")
  assert.equal(S.fromCache({ history: history.history, historyFetchedAt: 1 }).salesAccess, "unknown")
}

// Only the three ranges are folded in; any other is ignored (null), a
// failure included.
assert.equal(S.applyFetchResult(S.emptyRecord(), Object.assign({ ok: true }, yRes), { domain: yRes.domain, range: "week" }), null)
assert.equal(S.applyFetchResult(S.emptyRecord(), { ok: false, error: { code: "timeout" } }, { range: "" }), null)
