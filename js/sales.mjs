// A store's sales record: the reducers that fold fetch-sales and grant
// results into it, the new-order rule, and its cache.json form. Reducers
// return a new record and never mutate their input.
import { previousDate } from "./dates.mjs"
import { fromHelper } from "./errors.mjs"
import { isNum } from "./format.mjs"
import { todayBaseline, hourlyBuckets, salesHourlyBuckets } from "./hourly.mjs"

// cache.json records of any other version are ignored (no migration).
export const CACHE_VERSION = 5

function copy(o) {
  return Object.assign({}, o)
}

export function emptyRecord() {
  return {
    currency: "", timezone: "", utcOffsetMinutes: 0, dayEndsAt: 0, localDate: "",
    salesAccess: "unknown", salesAccessError: null,
    sales: {
      status: "idle", error: null,
      fetchedAt: { today: 0, traffic: 0, history: 0 },
      today: null, history: null, todayHourly: [], yesterdayHourly: [], newOrderAt: 0
    },
    historyLocalDate: "",
    yesterday: null,
    lastSeen: null
  }
}

// The store's place and day from a fetch-sales line (or the cache entry's
// fields): currency, timezone, utcOffsetMinutes, dayEndsAt, localDate.
// Missing or malformed fields keep what st holds.
export function withMeta(st, r) {
  const next = copy(st)
  if (typeof r.currency === "string" && r.currency) next.currency = r.currency
  if (typeof r.timezone === "string" && r.timezone) next.timezone = r.timezone
  if (isNum(r.utcOffsetMinutes)) next.utcOffsetMinutes = r.utcOffsetMinutes
  if (isNum(r.dayEndsAt)) next.dayEndsAt = r.dayEndsAt
  if (typeof r.localDate === "string" && r.localDate) next.localDate = r.localDate
  return next
}

function salesCopy(st) {
  const s = copy(st.sales)
  s.fetchedAt = copy(st.sales.fetchedAt)
  return s
}

// The sales error once a result for `range` arrived: null when the error
// was for that range (or there was none), else the error unchanged.
export function clearRangeError(error, range) {
  return error && error.range !== range ? error : null
}

// A successful fetch proves the sales scope: access granted, any grant
// error dropped.
export function markGranted(st) {
  const next = copy(st)
  next.salesAccess = "granted"
  next.salesAccessError = null
  return next
}

// The baseline for today's figures, when the yesterday payload held is for
// the day before the today data's local date.
function withBaseline(st) {
  const t = st.sales.today
  if (!t) return st
  const y = st.yesterday
  let baseline = null
  if (y && st.localDate && y.date === previousDate(st.localDate)) baseline = todayBaseline(y, st.sales.fetchedAt.today)
  const next = copy(st)
  next.sales = salesCopy(st)
  next.sales.today = Object.assign({}, t, { baseline: baseline })
  return next
}

// A fetch-sales --range=today result. withTraffic says whether traffic was
// asked for: without it the previous traffic (the funnel and the hourly
// sessions) is kept within the same day. The hourly chart (todayHourly)
// is rebuilt on every tick from today.orderPoints, with the current hour
// marked partial.
function applyToday(st, r, withTraffic) {
  const prevDate = st.localDate
  const next = withMeta(st, r)
  const sales = salesCopy(st)
  const t = r.today || {}
  const fetchedAt = isNum(r.fetchedAt) ? r.fetchedAt : 0
  let traffic = null
  let trafficHourly = null
  if (withTraffic) {
    traffic = t.traffic || null
    trafficHourly = Array.isArray(t.trafficHourly) ? t.trafficHourly : null
    sales.fetchedAt.traffic = fetchedAt
  } else if (st.sales.today && prevDate === next.localDate) {
    traffic = st.sales.today.traffic || null
    trafficHourly = st.sales.today.trafficHourly || null
  } else {
    sales.fetchedAt.traffic = 0
  }
  const latest = t.latestOrder && typeof t.latestOrder === "object" ? t.latestOrder : null
  // fetch-sales says `truncated` at the top level of its line (paging
  // stopped early: the order cap, or a throttle/timeout mid-paging turned
  // into a partial total), never inside the range object.
  sales.today = {
    sales: isNum(t.sales) ? t.sales : 0,
    orders: isNum(t.orders) ? t.orders : 0,
    truncated: r.truncated === true,
    latestOrder: latest,
    traffic: traffic,
    trafficHourly: trafficHourly,
    baseline: null
  }
  sales.todayHourly = hourlyBuckets({ startEpoch: t.startEpoch, endEpoch: isNum(r.dayEndsAt) ? r.dayEndsAt / 1000 : undefined,
                                      orderPoints: Array.isArray(t.orderPoints) ? t.orderPoints : [], trafficHourly: trafficHourly }, fetchedAt)
  sales.fetchedAt.today = fetchedAt
  sales.status = "ok"
  sales.error = clearRangeError(sales.error, "today")
  next.sales = sales
  return withBaseline(markGranted(next))
}

// The history figures alone (no meta, no access): r is { history,
// fetchedAt, localDate } (a fetch-sales --range=history line, or the
// cache entry's history fields). A history error is cleared and an idle or
// loading status becomes ok.
export function withHistory(st, r) {
  const next = copy(st)
  const sales = salesCopy(st)
  sales.history = r.history && typeof r.history === "object" ? r.history : null
  sales.fetchedAt.history = isNum(r.fetchedAt) ? r.fetchedAt : 0
  sales.error = clearRangeError(sales.error, "history")
  if (sales.status === "idle" || sales.status === "loading") sales.status = "ok"
  next.sales = sales
  next.historyLocalDate = typeof r.localDate === "string" ? r.localDate : ""
  return next
}

// A fetch-sales --range=history result: the completed periods.
function applyHistory(st, r) {
  return markGranted(withHistory(withMeta(st, r), r))
}

// The yesterday record from its one input shape, the flat day as
// cacheRecord stores it: { date, startEpoch, endEpoch (seconds),
// orderPoints ([ms, amount]), truncated, salesHourly, trafficHourly,
// fetchedAt }. Malformed fields become their empty value.
export function normalizeYesterday(d) {
  return {
    date: typeof d.date === "string" ? d.date : "",
    startEpoch: d.startEpoch, endEpoch: d.endEpoch,
    orderPoints: Array.isArray(d.orderPoints) ? d.orderPoints : [],
    truncated: !!d.truncated,
    salesHourly: Array.isArray(d.salesHourly) ? d.salesHourly : null,
    trafficHourly: Array.isArray(d.trafficHourly) ? d.trafficHourly : null,
    fetchedAt: isNum(d.fetchedAt) ? d.fetchedAt : 0
  }
}

// A fetch-sales --range=yesterday line as a flat day: the day sits under
// `yesterday`, `truncated` and `fetchedAt` at the top level. (A line
// without a `yesterday` object is read as flat itself.)
function yesterdayDay(r) {
  const d = r.yesterday && typeof r.yesterday === "object" ? r.yesterday : r
  return Object.assign({}, d, { truncated: !!(r.truncated || d.truncated), fetchedAt: r.fetchedAt })
}

// y: a normalizeYesterday record. The order points feed only today's
// same-time baseline (order totals, like today); the chart
// (yesterdayHourly) is salesHourly, Analytics total sales, the measure of
// the Yesterday headline from the history.
function withYesterday(st, y) {
  const next = copy(st)
  next.yesterday = y
  const sales = salesCopy(st)
  sales.yesterdayHourly = salesHourlyBuckets(y)
  sales.error = clearRangeError(sales.error, "yesterday")
  next.sales = sales
  return withBaseline(next)
}

// A fetch-sales --range=yesterday result.
function applyYesterday(st, r) {
  return withYesterday(withMeta(st, r), normalizeYesterday(yesterdayDay(r)))
}

function applyFetchError(st, range, error) {
  const next = copy(st)
  const sales = salesCopy(st)
  const e = fromHelper(error, range)
  sales.error = e
  if (range === "today" || !sales.today) sales.status = "error"
  if (e.code === "sales_access_required") {
    next.salesAccess = "required"
    sales.status = "error"
  }
  next.sales = sales
  return next
}

// The new-order rule: a rise in today's count with a new latest order,
// on the same local day, seen recently enough that the gap is not a restart.
// -> { detected, delta, lastSeen } where lastSeen is the record to keep.
function detectNewOrder(lastSeen, today, localDate, nowMs, pollSeconds) {
  const count = today.orders
  const latestId = today.latestOrder && typeof today.latestOrder.id === "string" ? today.latestOrder.id : ""
  const seen = { orderCount: count, latestOrderId: latestId, localDate: localDate, at: nowMs }
  if (!lastSeen) return { detected: false, delta: 0, lastSeen: seen }
  const recent = isNum(lastSeen.at) && nowMs - lastSeen.at <= 3 * pollSeconds * 1000
  const detected = count > (lastSeen.orderCount || 0) && latestId !== "" && latestId !== lastSeen.latestOrderId && lastSeen.localDate === localDate && recent
  return { detected: detected, delta: detected ? count - (lastSeen.orderCount || 0) : 0, lastSeen: seen }
}

// A finished fetch-sales run folded into the store's record.
// o: { domain, range (today|history|yesterday), withTraffic, nowMs,
// pollSeconds }. -> { record, newOrders, cache, errorCode }: newOrders is
// how many new orders the today result revealed (0 if none), cache says
// whether what cache.json keeps changed (a today tick writes only when
// its last-seen order changed), errorCode is the failure's code or "".
// null when the result names another store or the range is none of the
// three (ignored, success or failure alike).
export function applyFetchResult(st, r, o) {
  if (o.range !== "today" && o.range !== "history" && o.range !== "yesterday") return null
  if (r.ok && r.domain && r.domain !== o.domain) return null
  if (!r.ok) {
    const record = applyFetchError(st, o.range, r.error)
    return { record: record, newOrders: 0, cache: false, errorCode: record.sales.error.code }
  }
  if (o.range === "history") return { record: applyHistory(st, r), newOrders: 0, cache: true, errorCode: "" }
  if (o.range === "yesterday") return { record: applyYesterday(st, r), newOrders: 0, cache: true, errorCode: "" }
  let next = applyToday(st, r, o.withTraffic)
  const prev = next.lastSeen
  const det = detectNewOrder(prev, next.sales.today, next.localDate, o.nowMs, o.pollSeconds)
  next = Object.assign({}, next, { lastSeen: det.lastSeen })
  if (det.detected) next.sales = Object.assign({}, next.sales, { newOrderAt: o.nowMs })
  const seen = det.lastSeen
  const changed = !prev || prev.orderCount !== seen.orderCount || prev.latestOrderId !== seen.latestOrderId || prev.localDate !== seen.localDate
  return { record: next, newOrders: det.delta, cache: changed, errorCode: "" }
}

// A finished grant-sales-access run ({ok: true, name} or {ok: false,
// error}). On success access is granted and the sales error a fetch left
// for missing access is cleared, so the view never says "Sales access
// needed" while the first fetch with access runs ("idle", not "loading":
// the snapshot turns it into "loading" only while a fetch is pending;
// other errors stay). On failure the grant's error is kept as salesAccessError.
export function applyGrantResult(st, r) {
  const next = copy(st)
  if (!r.ok) {
    const e = fromHelper(r.error)
    if (e.code === "sales_access_required") next.salesAccess = "required"
    next.salesAccessError = e
    return next
  }
  next.salesAccess = "granted"
  next.salesAccessError = null
  const sales = salesCopy(st)
  if (sales.error && sales.error.code === "sales_access_required") {
    sales.error = null
    sales.status = sales.today ? "ok" : "idle"
  }
  next.sales = sales
  return next
}

// What cache.json keeps per store (record version CACHE_VERSION).
export function cacheRecord(st) {
  return {
    currency: st.currency, timezone: st.timezone, utcOffsetMinutes: st.utcOffsetMinutes, dayEndsAt: st.dayEndsAt,
    history: st.sales.history, historyFetchedAt: st.sales.fetchedAt.history, historyLocalDate: st.historyLocalDate,
    yesterday: st.yesterday, lastSeen: st.lastSeen
  }
}

// A store record warmed from a cache.json entry (bad fields are skipped).
// Only the data is warmed: access stays unknown until a live fetch, and
// the store-local date comes from a live fetch, never from the cache.
export function fromCache(rec) {
  let st = emptyRecord()
  if (!rec || typeof rec !== "object") return st
  st = withMeta(st, { currency: rec.currency, timezone: rec.timezone, utcOffsetMinutes: rec.utcOffsetMinutes, dayEndsAt: rec.dayEndsAt })
  if (rec.history && typeof rec.history === "object" && isNum(rec.historyFetchedAt)) {
    st = withHistory(st, { history: rec.history, fetchedAt: rec.historyFetchedAt, localDate: rec.historyLocalDate })
  }
  if (rec.yesterday && typeof rec.yesterday === "object" && Array.isArray(rec.yesterday.orderPoints)) {
    st = withYesterday(st, normalizeYesterday(rec.yesterday))
  }
  if (rec.lastSeen && typeof rec.lastSeen === "object") st.lastSeen = rec.lastSeen
  return st
}
