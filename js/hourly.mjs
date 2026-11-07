// A store day hour by hour, built when a fetch lands: the chart buckets
// for Today and Yesterday, and today's "this time yesterday" baseline.
// Pure; `hour` is always whole hours elapsed since the store-local start
// of the day (23, 24 or 25 of them on DST days).
import { isNum, cents } from "./format.mjs"

// startEpoch/endEpoch are seconds (the helper's unit).
function toMs(v) {
  return isNum(v) ? v * 1000 : null
}

// Yesterday at this time of day: orders before the same elapsed time since
// yesterday's start, and hourly traffic with the current hour prorated.
// yesterday: the fetch-sales yesterday payload ({startEpoch, endEpoch,
// orderPoints: [[ms, amount]], trafficHourly, truncated}). null when it cannot
// be lined up, or when a truncated payload stops before the cutoff.
// trafficHourly[].hour is whole hours since startEpoch (elapsed, so DST days
// line up with the elapsed-time weighting below).
export function todayBaseline(yesterday, nowMs) {
  const start = toMs(yesterday.startEpoch)
  const end = toMs(yesterday.endEpoch)
  if (start === null || end === null || end <= start) return null
  const elapsedMs = nowMs - end
  if (elapsedMs < 0 || elapsedMs > (end - start) + 3600000) return null
  const cutoff = start + elapsedMs
  let sales = 0
  let orders = 0
  let newest = null
  for (let i = 0; i < yesterday.orderPoints.length; i++) {
    const row = yesterday.orderPoints[i]
    if (!Array.isArray(row) || !isNum(row[0]) || !isNum(row[1])) continue
    if (newest === null || row[0] > newest) newest = row[0]
    if (row[0] < cutoff) { sales += row[1]; orders++ }
  }
  // Paging stopped early (truncated): orders come oldest first, so every
  // order before the newest fetched one is there, the rest of the day is
  // not. Past that point the baseline would undercount: no baseline.
  if (yesterday.truncated === true && (newest === null || cutoff > newest)) return null
  let traffic = null
  if (Array.isArray(yesterday.trafficHourly)) {
    const hours = elapsedMs / 3600000
    const full = Math.floor(hours)
    const frac = hours - full
    traffic = { sessions: 0, cartAdds: 0, reachedCheckout: 0, completed: 0 }
    const keys = ["sessions", "cartAdds", "reachedCheckout", "completed"]
    for (let i = 0; i < yesterday.trafficHourly.length; i++) {
      const h = yesterday.trafficHourly[i]
      if (!h || !isNum(h.hour)) continue
      const w = h.hour < full ? 1 : (h.hour === full ? frac : 0)
      if (w === 0) continue
      for (let k = 0; k < keys.length; k++) if (isNum(h[keys[k]])) traffic[keys[k]] += h[keys[k]] * w
    }
    for (let k = 0; k < keys.length; k++) traffic[keys[k]] = Math.round(traffic[keys[k]])
  }
  return { sales: cents(sales), orders: orders, traffic: traffic }
}


// The empty hourly grid of one store day: one bucket per elapsed hour since
// the store-local start (23, 24 or 25 on DST days, from endEpoch -
// startEpoch), with its sessions from trafficHourly. null without a start.
function hourGrid(raw) {
  const start = toMs(raw.startEpoch)
  if (start === null) return null
  const end = toMs(raw.endEpoch)
  const span = end !== null && end > start ? Math.round((end - start) / 3600000) : 24
  const hours = Math.max(23, Math.min(25, span))
  const out = []
  for (let h = 0; h < hours; h++) out.push({ hour: h, sales: 0, sessions: null })
  if (Array.isArray(raw.trafficHourly)) {
    for (let i = 0; i < raw.trafficHourly.length; i++) {
      const t = raw.trafficHourly[i]
      if (t && isNum(t.hour) && t.hour >= 0 && t.hour < hours && isNum(t.sessions)) out[t.hour].sessions = t.sessions
    }
  }
  return { start: start, hours: hours, out: out }
}

function roundSales(out) {
  for (let h = 0; h < out.length; h++) out[h].sales = cents(out[h].sales)
  return out
}

// Today's orders binned per elapsed hour since the store-local start of
// the day, joined with its hourly sessions: [{hour, sales, sessions,
// partial?}] with one bucket per hour of the day, or [] without data.
// `hour` is the elapsed hour, like trafficHourly[].hour. raw: {startEpoch,
// endEpoch, orderPoints: [[ms, amount]], trafficHourly} (today's
// startEpoch/orderPoints/trafficHourly; its endEpoch is the envelope's
// dayEndsAt / 1000). partialAtMs (today's
// fetch time) marks the hour still in progress `partial: true`; the hours
// after it have no orders yet and stay 0, so the axis reads 00 … 23 all day.
// Order totals, like today's headline and its same-time baseline.
export function hourlyBuckets(raw, partialAtMs) {
  const g = hourGrid(raw)
  if (!g) return []
  const out = g.out
  if (isNum(partialAtMs)) {
    const cur = Math.floor((partialAtMs - g.start) / 3600000)
    if (cur >= 0 && cur < g.hours) out[cur].partial = true
  }
  for (let i = 0; i < raw.orderPoints.length; i++) {
    const row = raw.orderPoints[i]
    if (!Array.isArray(row) || !isNum(row[0]) || !isNum(row[1])) continue
    const h = Math.floor((row[0] - g.start) / 3600000)
    if (h < 0 || h >= g.hours) continue
    out[h].sales += row[1]
  }
  return roundSales(out)
}

// Yesterday's chart: the hourly Analytics total sales
// (salesHourly: [{hour, sales}], the measure of the Yesterday
// headline and its day-before comparison) joined with the hourly sessions,
// in the same buckets as hourlyBuckets. An hour can be negative (a return
// booked then). [] when the series is unavailable: the chart never falls
// back to order totals, which would not add up to the headline.
export function salesHourlyBuckets(raw) {
  if (!Array.isArray(raw.salesHourly)) return []
  const g = hourGrid(raw)
  if (!g) return []
  const out = g.out
  for (let i = 0; i < raw.salesHourly.length; i++) {
    const r = raw.salesHourly[i]
    if (!r || !isNum(r.hour) || r.hour < 0 || r.hour >= g.hours) continue
    if (isNum(r.sales)) out[r.hour].sales += r.sales
  }
  return roundSales(out)
}
