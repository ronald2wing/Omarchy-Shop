// Sales scheduling rules: backoff, eligibility, and when the history and
// the yesterday baseline are due. Pure; the SalesScheduler owns the timers.
import { previousDate, utcMidnightMs } from "./dates.mjs"
import { isRateLimit } from "./errors.mjs"

const MIN = 60000
const HOUR = 3600000
const DAY = 86400000

// Cached history older than this at startup is fetched again right away.
const HISTORY_STALE_MS = 6 * HOUR
// Completed periods change at the store's day rollover: fetch 10 min after
// it (Analytics needs a moment), and once more 6 h later for the backfill.
const HISTORY_AFTER_ROLLOVER_MS = 10 * MIN
const HISTORY_BACKFILL_MS = 6 * HOUR + 10 * MIN

// Codes that retry at a flat 60 s instead of backing off (SalesScheduler
// also suspends the store on sales_access_required).
const FIXED_RETRY = ["sales_access_required", "signed_out", "cli_missing"]

// The delay before the next attempt after a fetch that failed with `code`.
// failures is the consecutive failure count including this one.
export function nextDelayMs(code, failures, rand) {
  const r = typeof rand === "function" ? rand : Math.random
  // signed_out retries at the poll cadence (store sessions usually outlive
  // the account session); cli_missing disables the scheduler and this delay
  // only guards against a loop.
  if (FIXED_RETRY.includes(code)) return MIN
  const n = Math.min(16, failures - 1)
  const p = Math.pow(2, n)
  if (isRateLimit(code)) return Math.round(Math.min(60 * p, 900) * 1000 * (1 + r() * 0.2))
  if (code === "bad_response" || code === "output_too_large") return Math.min(300 * p, 3600) * 1000
  return Math.min(60 * p, 600) * 1000
}

// Today polling runs for stores in the bar, with alerts on, or while the
// panel is open.
export function liveEligible(storeCfg, settings, panelOpen) {
  return !!(storeCfg.showInBar || settings.alerts.notify || panelOpen)
}

// "YYYY-MM-DD" in the store's zone at nowMs.
export function storeLocalDate(nowMs, utcOffsetMinutes) {
  return new Date(nowMs + utcOffsetMinutes * 60000).toISOString().slice(0, 10)
}

// The ms of store-local midnight that starts localDate.
function dayStartMs(localDate, utcOffsetMinutes) {
  const t = utcMidnightMs(localDate)
  if (t === null) return null
  return t - utcOffsetMinutes * 60000
}

// Startup rule: history fetched over HISTORY_STALE_MS ago (or never) is
// fetched again before anything else.
export function historyStale(entry, nowMs) {
  if (!entry.historyFetchedAt) return true
  return nowMs - entry.historyFetchedAt > HISTORY_STALE_MS
}

// entry: { historyFetchedAt, historyLocalDate, utcOffsetMinutes }.
// Due with no data; 10 min after the store-local date rolled over; and once
// more 6 h after that mark when the last fetch came before it. Never on a
// fixed timer: two fetches per store per day.
export function historyDue(entry, nowMs, localDate) {
  if (!entry.historyFetchedAt || !entry.historyLocalDate) return true
  const start = dayStartMs(localDate, entry.utcOffsetMinutes)
  if (start === null) return false
  if (entry.historyLocalDate !== localDate) return nowMs >= start + HISTORY_AFTER_ROLLOVER_MS
  const backfill = start + HISTORY_BACKFILL_MS
  return nowMs >= backfill && entry.historyFetchedAt < backfill
}

// The next time historyDue can turn true, for re-arming the timer (entry
// has a historyFetchedAt).
export function historyNextAt(entry, nowMs, localDate) {
  const start = dayStartMs(localDate, entry.utcOffsetMinutes)
  if (start === null) return nowMs + HOUR
  const marks = [start + HISTORY_AFTER_ROLLOVER_MS, start + HISTORY_BACKFILL_MS, start + DAY + HISTORY_AFTER_ROLLOVER_MS]
  for (let i = 0; i < marks.length; i++) if (marks[i] > nowMs && entry.historyFetchedAt < marks[i]) return marks[i]
  return start + DAY + HISTORY_AFTER_ROLLOVER_MS
}

// Past dayEndsAt the cached offset may be stale (DST): treat it as a new day
// whose today fetch must run first to refresh localDate and the offset.
export function dayRolledOver(entry, nowMs) {
  return !!(entry.dayEndsAt && nowMs >= entry.dayEndsAt)
}

// entry: { localDate, yesterdayDate, yesterdayFetchedAt, dayEndsAt }. Due
// when the baseline held is not for the day before entry.localDate, or once
// the store day has ended and no fetch has run since (the helper computes
// its own window).
export function yesterdayDue(entry, nowMs) {
  if (dayRolledOver(entry, nowMs)) return !(entry.yesterdayFetchedAt >= entry.dayEndsAt)
  return entry.yesterdayDate !== previousDate(entry.localDate)
}

// ---- the scheduler's per-store entry ---------------------------------------

// The fetch ranges; failures and backoffUntil hold one counter per range.
export const RANGES = ["today", "history", "yesterday"]
// A floor between scheduled history and yesterday refetches after a
// success, so a bad clock cannot loop.
const REFETCH_FLOOR_MS = 5 * MIN

function perRange(value) {
  const out = {}
  for (let i = 0; i < RANGES.length; i++) out[RANGES[i]] = value
  return out
}

function copyEntry(e) {
  const out = Object.assign({}, e)
  out.failures = Object.assign({}, e.failures)
  out.backoffUntil = Object.assign({}, e.backoffUntil)
  return out
}

// A store the scheduler has not seen yet.
export function freshEntry() {
  return {
    todayDueAt: 0, lastTodayAt: 0, lastTrafficAt: 0, todayTicks: 0, dropTraffic: false, notBefore: 0,
    failures: perRange(0), backoffUntil: perRange(0),
    suspended: false, forceHistory: false
  }
}

// The entry with no failures and no backoff for `ranges` (default all).
export function clearBackoff(entry, ranges) {
  const out = copyEntry(entry)
  const list = ranges || RANGES
  for (let i = 0; i < list.length; i++) {
    out.failures[list[i]] = 0
    out.backoffUntil[list[i]] = 0
  }
  return out
}

// The entry after a fetch of `range` finished with `result` (the helper's
// object, ok or not) at nowMs. pollMs: the poll interval; withTraffic: the
// today fetch asked for traffic; rand: nextDelayMs' jitter source.
export function entryAfter(entry, range, result, nowMs, pollMs, withTraffic, rand) {
  if (result.ok) {
    const e = clearBackoff(entry, [range])
    if (range === "today") {
      e.lastTodayAt = nowMs
      e.todayDueAt = nowMs + pollMs
      if (withTraffic) e.lastTrafficAt = nowMs
      e.dropTraffic = false
    } else {
      if (range === "history") e.forceHistory = false
      e.backoffUntil[range] = nowMs + REFETCH_FLOOR_MS
    }
    return e
  }
  const e = copyEntry(entry)
  const code = result.error.code
  e.failures[range]++
  let delay = nextDelayMs(code, e.failures[range], rand)
  if (code === "sales_access_required") e.suspended = true
  if (typeof result.error.retryAfter === "number") delay = Math.max(delay, result.error.retryAfter * 1000)
  e.backoffUntil[range] = nowMs + delay
  if (range === "today") {
    e.todayDueAt = nowMs + delay
    if (isRateLimit(code)) e.dropTraffic = true
  }
  return e
}

// The store-local date the history rule uses at nowMs (clock: the
// scheduler's clock entry): the cached one until the store day ends, then
// the date from the cached offset ("" without a timezone yet). The tick
// and the re-arm both read this, so after a rollover the next history
// mark is computed from the new date.
export function effectiveLocalDate(clock, nowMs) {
  if (clock.localDate && !dayRolledOver(clock, nowMs)) return clock.localDate
  return clock.timezone ? storeLocalDate(nowMs, clock.utcOffsetMinutes) : ""
}
