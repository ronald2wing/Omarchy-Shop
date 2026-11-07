// The figures views derive from a snapshot store: rates, trends,
// per-period views, KPI slots, period totals across stores, the stale
// threshold and the "figures on their way" rule. Pure.
import { isRateLimit } from "./errors.mjs"
import { isNum, cents } from "./format.mjs"

export const PERIOD_IDS = ["today", "yesterday", "last7d", "last14d", "last30d", "last12m"]
// The eight KPI tiles, in grid order (3 per row).
export const KPI_SLOTS = ["orders", "sessions", "aov", "salesPerSession", "conversion", "addToCart", "reachedCheckout", "checkoutCompletion"]
const KPI_FORMAT = { orders: "count", sessions: "count", aov: "money", salesPerSession: "money" }
export const KPI_TIPS = ["aov", "salesPerSession", "conversion", "addToCart", "reachedCheckout", "checkoutCompletion"]

function ratio(a, b) {
  return isNum(a) && isNum(b) && b > 0 ? a / b : null
}

// Funnel rates as fractions, from count-based traffic
// ({sessions, cartAdds, reachedCheckout, completed}); null without counts.
function rates(traffic) {
  if (!traffic || typeof traffic !== "object") return null
  if (!isNum(traffic.cartAdds) && !isNum(traffic.completed) && !isNum(traffic.reachedCheckout)) return null
  return {
    conversion: ratio(traffic.completed, traffic.sessions),
    addToCart: ratio(traffic.cartAdds, traffic.sessions),
    reachedCheckout: ratio(traffic.reachedCheckout, traffic.sessions),
    checkoutCompletion: ratio(traffic.completed, traffic.reachedCheckout)
  }
}

// { direction: "up"|"down"|"flat", pct } with pct in percent units (18 =
// 18%); flat when |pct| < 0.5; null without a usable baseline.
export function trend(current, baseline) {
  if (!isNum(current) || !isNum(baseline) || baseline === 0) return null
  const pct = (current - baseline) / Math.abs(baseline) * 100
  const direction = Math.abs(pct) < 0.5 ? "flat" : (pct > 0 ? "up" : "down")
  return { direction: direction, pct: pct }
}

function sessionsOf(traffic) {
  return traffic && isNum(traffic.sessions) ? traffic.sessions : null
}

// The figures the store view shows for one period, with their comparison
// (today vs this time yesterday, yesterday vs the day before, 7/14/30d vs
// the previous window).
export function periodView(store, periodId) {
  const empty = { sales: null, orders: null, sessions: null, traffic: null, salesTrend: null, ordersTrend: null, sessionsTrend: null, compare: null, buckets: [], lifetime: null, partial: false }
  const sales = store && store.sales
  if (!sales) return empty
  if (periodId === "today") {
    const t = sales.today
    if (!t) return empty
    const b = t.baseline || null
    // A busy store's today is truncated: the order count and sessions are
    // exact but the money sums only the oldest pages, so no money
    // comparison (sales trend, AOV, sales per session) is made against
    // the complete baseline; compare keeps orders and traffic only.
    const cut = !!t.truncated
    const compare = b && cut ? { sales: null, orders: b.orders, traffic: b.traffic || null } : b
    return {
      sales: isNum(t.sales) ? t.sales : null,
      orders: isNum(t.orders) ? t.orders : null,
      sessions: sessionsOf(t.traffic),
      traffic: t.traffic || null,
      salesTrend: b && !cut ? trend(t.sales, b.sales) : null,
      ordersTrend: b ? trend(t.orders, b.orders) : null,
      sessionsTrend: b && b.traffic ? trend(sessionsOf(t.traffic), sessionsOf(b.traffic)) : null,
      compare: compare,
      buckets: sales.todayHourly,
      lifetime: null,
      partial: cut
    }
  }
  const history = sales.history
  const p = history && history[periodId]
  if (!p) return empty
  const prev = p.previous || null
  const buckets = periodId === "yesterday" ? sales.yesterdayHourly : (Array.isArray(p.buckets) ? p.buckets : [])
  return {
    sales: isNum(p.sales) ? p.sales : null,
    orders: isNum(p.orders) ? p.orders : null,
    sessions: sessionsOf(p.traffic),
    traffic: p.traffic || null,
    salesTrend: prev ? trend(p.sales, prev.sales) : null,
    ordersTrend: prev ? trend(p.orders, prev.orders) : null,
    sessionsTrend: prev ? trend(sessionsOf(p.traffic), sessionsOf(prev.traffic)) : null,
    compare: prev,
    buckets: buckets,
    lifetime: periodId === "last12m" && history.lifetime ? history.lifetime : null,
    partial: false
  }
}

function kpiValue(id, sales, orders, traffic) {
  if (id === "orders") return isNum(orders) ? orders : null
  if (id === "sessions") return sessionsOf(traffic)
  if (id === "aov") return ratio(sales, orders)
  if (id === "salesPerSession") return ratio(sales, sessionsOf(traffic))
  const r = rates(traffic)
  return r ? r[id] : null
}

// One KPI slot (0-7) of the fixed grid: { format, value, trend, label,
// tip }. format is "count" (orders, sessions), "money" (the store
// currency) or "percent" (a fraction). label and tip are Copy keys
// ("kpi.<id>", "kpi.tip.<id>" or "" when the tile has no tooltip): the
// model never builds UI strings.
export function kpi(store, periodId, slotIndex) {
  const id = KPI_SLOTS[slotIndex]
  const format = KPI_FORMAT[id] || "percent"
  const v = periodView(store, periodId)
  // A partial (truncated) today sums fewer orders than it counts: no
  // per-order or per-session money figure.
  const value = v.partial && (id === "aov" || id === "salesPerSession") ? null : kpiValue(id, v.sales, v.orders, v.traffic)
  let t = null
  if (id === "orders") t = v.ordersTrend
  else if (id === "sessions") t = v.sessionsTrend
  else {
    const c = v.compare
    if (c) {
      const needsTraffic = id !== "aov"
      if (!needsTraffic || c.traffic) t = trend(value, kpiValue(id, c.sales, c.orders, c.traffic || null))
    }
  }
  return { format: format, value: value, trend: t, label: "kpi." + id, tip: KPI_TIPS.includes(id) ? "kpi.tip." + id : "" }
}

// One period summed across stores (Home's hero): {byCurrency: [{currency,
// sales}], currency ("" when mixed), orders, storeCount, trend, baseline,
// complete, any, loading}. A trend and a baseline amount exist
// only with one currency and every store's comparison present (complete);
// loading says a missing figure is still on its way (awaitingFigures)
// rather than absent. `orders` counts only the stores with a figure: with
// `any` false nothing was read and no count should be shown.
export function periodTotals(snapshot, storeOrder, periodId) {
  const stores = snapshot && snapshot.stores ? snapshot.stores : {}
  const sums = Object.create(null)
  const currencies = []
  let orders = 0
  let current = 0
  let base = 0
  let complete = true
  let any = false
  let loading = false
  for (let i = 0; i < storeOrder.length; i++) {
    const s = stores[storeOrder[i]]
    if (!s) continue
    const v = periodView(s, periodId)
    if (!isNum(v.sales)) {
      complete = false
      if (awaitingFigures(s.sales)) loading = true
      continue
    }
    any = true
    const c = String(s.currency || "")
    if (!(c in sums)) { sums[c] = 0; currencies.push(c) }
    sums[c] += v.sales
    current += v.sales
    if (isNum(v.orders)) orders += v.orders
    if (v.compare && isNum(v.compare.sales)) base += v.compare.sales
    else complete = false
  }
  const byCurrency = currencies.map(c => ({ currency: c, sales: cents(sums[c]) }))
  const comparable = byCurrency.length === 1 && complete && any
  return {
    byCurrency: byCurrency,
    currency: byCurrency.length === 1 ? byCurrency[0].currency : "",
    orders: orders,
    storeCount: storeOrder.length,
    trend: comparable ? trend(current, base) : null,
    baseline: comparable ? cents(base) : null,
    complete: complete,
    any: any,
    loading: loading
  }
}

// The one rule for "figures are on their way" (rendered "…"), shared by
// Home's hero and rows, the store hero and the KPI tiles so one state never
// reads "…" in one place and "—" in another: a fetch is pending or has not
// run yet, or Shopify is throttling and a retry is scheduled. A paused
// store (nothing will be fetched) and every other error read "—".
export function awaitingFigures(sales) {
  if (!sales || sales.paused === true) return false
  if (sales.pending || sales.status === "idle" || sales.status === "loading") return true
  const e = sales.error
  return !!e && isRateLimit(e.code) && isNum(sales.retryAt) && sales.retryAt > 0
}

// The one stale threshold (banner, Home "Updated" line, the panel-open
// refresh): a today fetch
// older than 2.5 poll intervals plus 15 s. Never-fetched (0) is not stale.
export function isStale(todayMs, nowMs, pollSeconds) {
  if (!isNum(todayMs) || todayMs <= 0) return false
  const pollMs = pollSeconds * 1000
  return nowMs - todayMs > pollMs * 2.5 + 15000
}
