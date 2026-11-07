// js/metrics.mjs: rates, trends (one case per trend-table row), the eight
// KPI slots, totals and the stale threshold.
import assert from "node:assert/strict"
import { load } from "./fixture.mjs"
import * as M from "../../js/metrics.mjs"
import { todayBaseline } from "../../js/hourly.mjs"
import * as Sales from "../../js/sales.mjs"

const near = (a, b, msg) => assert(Math.abs(a - b) < 1e-9, msg + ": " + a + " vs " + b)

assert.deepEqual(M.PERIOD_IDS, ["today", "yesterday", "last7d", "last14d", "last30d", "last12m"])
assert.deepEqual(M.KPI_SLOTS, ["orders", "sessions", "aov", "salesPerSession", "conversion", "addToCart", "reachedCheckout", "checkoutCompletion"])
const slot = id => M.KPI_SLOTS.indexOf(id)

// The funnel rate KPIs (fractions) of a today with this traffic.
const rateOf = (traffic, id) => M.kpi({ sales: { today: { sales: 0, orders: 0, traffic: traffic } } }, "today", slot(id)).value
const counts = { sessions: 1000, cartAdds: 60, reachedCheckout: 30, completed: 16 }
near(rateOf(counts, "conversion"), 0.016, "conversion")
near(rateOf(counts, "addToCart"), 0.06, "addToCart")
near(rateOf(counts, "reachedCheckout"), 0.03, "reachedCheckout")
near(rateOf(counts, "checkoutCompletion"), 16 / 30, "checkoutCompletion")
assert.equal(rateOf(null, "conversion"), null)
assert.equal(rateOf({ sessions: 0, cartAdds: 0, reachedCheckout: 0, completed: 0 }, "conversion"), null)
// No counts, no rates: a rate-shaped payload is not a traffic object.
assert.equal(rateOf({ sessions: 10, conversion: 0.1, addToCart: 0.2, checkoutCompletion: 0.5 }, "conversion"), null)

// trend
assert.deepEqual(M.trend(118, 100), { direction: "up", pct: 18 })
assert.equal(M.trend(90, 100).direction, "down")
assert.equal(M.trend(100.4, 100).direction, "flat")
assert.equal(M.trend(10, 0), null)
assert.equal(M.trend(10, null), null)
assert.equal(M.trend(null, 10), null)

// A truncated yesterday baseline (js/hourly.mjs): no trend against it.
const yRes = load("yesterday.json")
const y = Object.assign({}, yRes.yesterday, { fetchedAt: yRes.fetchedAt })
const today = load("today.json")
const newest = Math.max.apply(null, y.orderPoints.map(o => o[0]))
const yCut = Object.assign({}, y, { truncated: true })
{
  const lateNow = newest - y.startEpoch * 1000 + y.endEpoch * 1000 + 60000
  const pv = M.periodView({ sales: { today: { sales: 500, orders: 9, traffic: null, baseline: todayBaseline(yCut, lateNow) } } }, "today")
  assert.equal(pv.sales, 500)
  assert.equal(pv.salesTrend, null, "no trend against a truncated baseline")
  assert.equal(pv.ordersTrend, null)
}

// A store built through the reducers.
const fold = (st, r, range) => Sales.applyFetchResult(st, r, { domain: r.domain, range: range, withTraffic: true, nowMs: r.fetchedAt, pollSeconds: 60 }).record
let st = Sales.emptyRecord()
st = fold(st, yRes, "yesterday")
st = fold(st, today, "today")
st = fold(st, load("history.json"), "history")
const store = { sales: st.sales }

// Trend table row: today vs baseline, traffic included.
const tv = M.periodView(store, "today")
assert.equal(tv.sales, 812)
assert.equal(tv.sessions, 1621)
assert.equal(tv.buckets.length, 24, "today has the hourly chart like yesterday")
assert.equal(tv.buckets[8].partial, true)
assert.equal(tv.buckets[7].sales, 511.5)
near(tv.salesTrend.pct, (812 - 150.5) / 150.5 * 100, "today sales trend")
near(tv.ordersTrend.pct, (21 - 2) / 2 * 100, "today orders trend")
near(tv.sessionsTrend.pct, (1621 - 140) / 140 * 100, "today sessions trend")

// KPI slots: format, value, trend and Copy keys.
const orders = M.kpi(store, "today", slot("orders"))
assert.deepEqual([orders.format, orders.value, orders.label, orders.tip], ["count", 21, "kpi.orders", ""])
near(orders.trend.pct, (21 - 2) / 2 * 100, "orders trend is the orders trend")
const sessions = M.kpi(store, "today", slot("sessions"))
assert.deepEqual([sessions.format, sessions.value, sessions.label, sessions.tip], ["count", 1621, "kpi.sessions", ""])
assert.equal(sessions.trend.direction, "up")
const aovToday = M.kpi(store, "today", slot("aov"))
assert.equal(aovToday.format, "money")
assert.equal(aovToday.label, "kpi.aov")
assert.equal(aovToday.tip, "kpi.tip.aov")
near(aovToday.value, 812 / 21, "aov")
near(aovToday.trend.pct, ((812 / 21) - (150.5 / 2)) / (150.5 / 2) * 100, "aov trend")
const sps = M.kpi(store, "today", slot("salesPerSession"))
assert.equal(sps.format, "money")
near(sps.value, 812 / 1621, "sales per session")
const convToday = M.kpi(store, "today", slot("conversion"))
assert.equal(convToday.format, "percent")
assert.equal(convToday.tip, "kpi.tip.conversion")
near(convToday.value, 8 / 1621, "conversion today")
assert(convToday.trend !== null)
for (const id of ["addToCart", "reachedCheckout", "checkoutCompletion"]) {
  const k = M.kpi(store, "today", slot(id))
  assert.equal(k.format, "percent", id)
  assert.equal(k.label, "kpi." + id)
  assert.equal(k.tip, "kpi.tip." + id)
  assert(k.value !== null, id)
}
// Today without baseline traffic: money-per-order trend yes, traffic KPIs none.
let noTraffic = fold(Sales.emptyRecord(), Object.assign({}, yRes, { yesterday: Object.assign({}, yRes.yesterday, { trafficHourly: null }) }), "yesterday")
noTraffic = fold(noTraffic, today, "today")
const nt = { sales: noTraffic.sales }
assert(M.kpi(nt, "today", slot("aov")).trend !== null)
assert(M.kpi(nt, "today", slot("orders")).trend !== null)
assert.equal(M.kpi(nt, "today", slot("sessions")).trend, null)
assert.equal(M.kpi(nt, "today", slot("salesPerSession")).trend, null)
assert.equal(M.kpi(nt, "today", slot("conversion")).trend, null)
assert.equal(M.periodView(nt, "today").sessionsTrend, null)

// Row: yesterday vs the day before.
const yv = M.periodView(store, "yesterday")
near(yv.salesTrend.pct, (360.5 - 300) / 300 * 100, "yesterday trend")
assert.equal(yv.buckets.length, 24)
assert.equal(yv.buckets[0].sales, 100)
// The Yesterday chart is the hourly Analytics series (salesHourly), the
// headline's measure: its hours add up to the headline, a return-only
// hour is negative, and the order totals (10.00 at 23:00) are not drawn.
near(yv.buckets.reduce((a, b) => a + b.sales, 0), yv.sales, "yesterday chart adds up to its headline")
assert.deepEqual(yv.buckets[22], { hour: 22, sales: -25, sessions: null })
assert.equal(yv.buckets[23].sales, 35)
assert.equal(yv.buckets[7].sessions, 100, "sessions joined per hour")
assert.equal(yv.buckets[0].sessions, 40)
assert(M.kpi(store, "yesterday", slot("salesPerSession")).trend !== null)

// Row: 7d vs previous 7d, with buckets.
const w = M.periodView(store, "last7d")
assert.equal(w.buckets.length, 7)
near(w.salesTrend.pct, (5412.8 - 4965.87) / 4965.87 * 100, "7d trend")
assert(w.sessionsTrend.direction === "down")
assert(M.kpi(store, "last7d", slot("sessions")).trend !== null)
// 30d vs previous 30d, with daily buckets.
const m30 = M.periodView(store, "last30d")
assert.equal(m30.buckets.length, 30)
assert(m30.salesTrend !== null && m30.sessionsTrend !== null)
assert(M.kpi(store, "last30d", slot("conversion")).trend !== null)
// A previous period without traffic (its traffic query failed): sales
// trend yes, traffic KPI trends none.
{
  const h = store.sales.history
  const noPrevTraffic = { sales: Object.assign({}, store.sales, { history: Object.assign({}, h, {
    last30d: Object.assign({}, h.last30d, { previous: Object.assign({}, h.last30d.previous, { traffic: null }) }) }) }) }
  const pv = M.periodView(noPrevTraffic, "last30d")
  assert(pv.salesTrend !== null)
  assert.equal(pv.sessionsTrend, null)
  assert.equal(M.kpi(noPrevTraffic, "last30d", slot("conversion")).trend, null)
  assert(M.kpi(noPrevTraffic, "last30d", slot("aov")).trend !== null)
  assert(M.kpi(noPrevTraffic, "last30d", slot("orders")).trend !== null)
}

// Row: 12m has no trends (Ruby sends no previous for it); lifetime rides along.
const yr = M.periodView(store, "last12m")
assert.equal(yr.salesTrend, null)
assert.deepEqual(yr.lifetime, { sales: 184120, orders: 5310 })
for (const id of ["today", "yesterday", "last7d", "last14d", "last30d"]) assert.equal(M.periodView(store, id).lifetime, null, id + " carries no lifetime")
for (let i = 0; i < 8; i++) assert.equal(M.kpi(store, "last12m", i).trend, null)

// Unknown inputs never throw.
assert.equal(M.periodView(null, "today").sales, null)
assert.equal(M.periodView({ sales: Sales.emptyRecord().sales }, "last7d").sales, null)

// periodTotals today (the bar's total pill)
const snap = { stores: {
  "a.myshopify.com": { showInBar: true, currency: "USD", sales: { today: { sales: 100, orders: 2, baseline: { sales: 80 } } } },
  "b.myshopify.com": { showInBar: false, currency: "USD", sales: { today: { sales: 50, orders: 1, baseline: { sales: 20 } } } },
  "c.myshopify.com": { showInBar: true, currency: "EUR", sales: { today: { sales: 10, orders: 1, baseline: null } } }
} }
const all = M.periodTotals(snap, ["a.myshopify.com", "b.myshopify.com", "c.myshopify.com"], "today")
assert.deepEqual(all.byCurrency, [{ currency: "USD", sales: 150 }, { currency: "EUR", sales: 10 }])
assert.equal(all.orders, 4)
assert.equal(all.trend, null, "mixed currencies: no trend")
const usd = M.periodTotals(snap, ["a.myshopify.com", "b.myshopify.com"], "today")
near(usd.trend.pct, 50, "usd trend")

// periodTotals: today sums with baselines; history periods with previous;
// a store without the period breaks completeness (no trend) and says
// loading only while a fetch is pending; mixed currencies list each total.
const week = (sales, prev) => ({ last7d: { sales: sales, orders: 10, traffic: null, previous: prev === null ? null : { sales: prev, orders: 8, traffic: null }, buckets: [] } })
const hsnap = { stores: {
  "a.myshopify.com": { currency: "USD", sales: { status: "ok", pending: false, today: { sales: 100, orders: 2, baseline: { sales: 80 } }, history: week(700, 500) } },
  "b.myshopify.com": { currency: "USD", sales: { status: "ok", pending: false, today: { sales: 50, orders: 1, baseline: { sales: 20 } }, history: week(300, 300) } },
  "c.myshopify.com": { currency: "USD", sales: { status: "loading", pending: true, today: null, history: null } },
  "e.myshopify.com": { currency: "USD", sales: { status: "error", pending: false, error: { code: "rate_limited" }, retryAt: 1762520460000, today: null, history: null } },
  "d.myshopify.com": { currency: "EUR", sales: { status: "ok", pending: false, today: { sales: 10, orders: 1, baseline: { sales: 5 } }, history: week(10, null) } }
} }
const ab = ["a.myshopify.com", "b.myshopify.com"]
const pt = M.periodTotals(hsnap, ab, "today")
assert.deepEqual(pt.byCurrency, [{ currency: "USD", sales: 150 }])
assert.equal(pt.currency, "USD")
assert.equal(pt.orders, 3)
assert.equal(pt.storeCount, 2)
assert.equal(pt.baseline, 100)
near(pt.trend.pct, 50, "today trend")
assert(pt.complete && pt.any && !pt.loading)
const p7 = M.periodTotals(hsnap, ab, "last7d")
assert.deepEqual(p7.byCurrency, [{ currency: "USD", sales: 1000 }])
assert.equal(p7.baseline, 800)
near(p7.trend.pct, 25, "7d trend")
const withC = M.periodTotals(hsnap, ab.concat(["c.myshopify.com"]), "last7d")
assert.equal(withC.trend, null, "a store without the period: no trend")
assert.equal(withC.baseline, null)
assert(withC.loading && !withC.complete && withC.any, "its fetch is pending")
assert.equal(withC.storeCount, 3)
const mixed = M.periodTotals(hsnap, ab.concat(["d.myshopify.com"]), "today")
assert.deepEqual(mixed.byCurrency, [{ currency: "USD", sales: 150 }, { currency: "EUR", sales: 10 }])
assert.equal(mixed.currency, "")
assert.equal(mixed.trend, null, "mixed currencies: no trend")
const noPrev = M.periodTotals(hsnap, ["d.myshopify.com"], "last7d")
assert.equal(noPrev.trend, null, "no previous period: no trend")
assert(!noPrev.complete && noPrev.any && !noPrev.loading)
const none = M.periodTotals({ stores: {} }, ["x.myshopify.com"], "today")
assert.deepEqual(none.byCurrency, [])
assert(!none.any && !none.loading && none.trend === null)
// Throttled before the first fetch: nothing counted, no orders claimed, and
// the hero waits ("…") like the rows do.
const throttled = M.periodTotals(hsnap, ["e.myshopify.com"], "today")
assert(!throttled.any && throttled.loading && throttled.orders === 0 && throttled.storeCount === 1)

const now = 1762500000000
// isStale: the shared threshold (2.5 x poll + 15 s); 166 s is stale at a 60 s poll, 165 s is not.
assert.equal(M.isStale(now - 165000, now, 60), false)
assert.equal(M.isStale(now - 166000, now, 60), true)
assert.equal(M.isStale(0, now, 60), false, "never fetched is not stale")

// awaitingFigures: the one "…" rule shared by Home, the store hero and the KPI tiles.
assert.equal(M.awaitingFigures(null), false)
assert.equal(M.awaitingFigures({ status: "idle", pending: false, error: null, retryAt: 0 }), true, "not fetched yet")
assert.equal(M.awaitingFigures({ status: "loading", pending: true }), true)
assert.equal(M.awaitingFigures({ status: "ok", pending: true }), true, "a refresh in flight")
assert.equal(M.awaitingFigures({ status: "idle", paused: true }), false, "paused: nothing will come")
assert.equal(M.awaitingFigures({ status: "error", pending: false, error: { code: "rate_limited" }, retryAt: 1762520460000 }), true, "throttled with a retry scheduled")
assert.equal(M.awaitingFigures({ status: "error", pending: false, error: { code: "rate_limited" }, retryAt: 0 }), false, "throttled without a retry")
assert.equal(M.awaitingFigures({ status: "error", pending: false, error: { code: "timeout" }, retryAt: 1762520460000 }), false, "other errors read as absent")

// A busy store's truncated today (1,200 orders counted, the oldest 750
// summed at $40) against a complete baseline: no money comparison, no
// per-order money, orders and sessions trends stay (both exact).
{
  const baseline = { sales: 46000, orders: 1150, traffic: { sessions: 9000, conversion: 0.12 } }
  const cutToday = { sales: 30000, orders: 1200, traffic: { sessions: 9500, conversion: 0.125 }, truncated: true, baseline: baseline }
  const busy = { domain: "busy.myshopify.com", currency: "USD", showInBar: true, sales: { today: cutToday } }
  const pv = M.periodView(busy, "today")
  assert.equal(pv.partial, true)
  assert.equal(pv.salesTrend, null, "truncated today: no sales trend")
  assert.notEqual(pv.ordersTrend, null, "truncated today: the exact order count keeps its trend")
  assert.notEqual(pv.sessionsTrend, null, "truncated today: sessions keep their trend")
  assert.equal(pv.compare.sales, null, "truncated today: compare carries no money")
  const slot = id => M.kpi(busy, "today", M.KPI_SLOTS.indexOf(id))
  assert.equal(slot("aov").value, null, "truncated today: no AOV")
  assert.equal(slot("aov").trend, null)
  assert.equal(slot("salesPerSession").value, null, "truncated today: no sales per session")
  const snap = { stores: { "busy.myshopify.com": busy } }
  const pt = M.periodTotals(snap, ["busy.myshopify.com"], "today")
  assert.equal(pt.complete, false, "truncated today: hero comparison incomplete")
  assert.equal(pt.trend, null, "truncated today: no bar/Home trend")
  // Control: the same store untruncated compares as before.
  const whole = Object.assign({}, busy, { sales: { today: Object.assign({}, cutToday, { truncated: false }) } })
  assert.notEqual(M.periodView(whole, "today").salesTrend, null)
  assert.notEqual(M.periodTotals({ stores: { "busy.myshopify.com": whole } }, ["busy.myshopify.com"], "today").trend, null)
}
