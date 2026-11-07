// js/schedule.mjs: backoff table, eligibility, the history cadence and the
// yesterday baseline rule.
import assert from "node:assert/strict"
import * as S from "../../js/schedule.mjs"

const zero = () => 0
const one = () => 1
assert.equal(S.nextDelayMs("rate_limited", 1, zero), 60000)
assert.equal(S.nextDelayMs("rate_limited", 2, zero), 120000)
assert.equal(S.nextDelayMs("rate_limited", 10, zero), 900000)
assert.equal(S.nextDelayMs("rate_limited", 1, one), 72000, "+20% jitter at most")
assert.equal(S.nextDelayMs("timeout", 1, zero), 60000)
assert.equal(S.nextDelayMs("cli_failed", 4, zero), 480000)
assert.equal(S.nextDelayMs("terminated", 9, zero), 600000)
assert.equal(S.nextDelayMs("bad_response", 1, zero), 300000)
assert.equal(S.nextDelayMs("output_too_large", 5, zero), 3600000)
for (const c of ["sales_access_required", "signed_out", "cli_missing"]) assert.equal(S.nextDelayMs(c, 1, zero), 60000, c)
assert.equal(S.nextDelayMs("store_unavailable", 2, zero), 120000)
assert.equal(S.nextDelayMs("something_new", 1, zero), 60000)

assert(S.liveEligible({ showInBar: true }, { alerts: { notify: false } }, false))
assert(S.liveEligible({ showInBar: false }, { alerts: { notify: true } }, false))
assert(S.liveEligible({ showInBar: false }, { alerts: { notify: false } }, true))
assert(!S.liveEligible({ showInBar: false }, { alerts: { notify: false } }, false))

const NOW = Date.UTC(2025, 10, 7, 13, 0)
assert.equal(S.storeLocalDate(NOW, -300), "2025-11-07")
assert.equal(S.storeLocalDate(Date.UTC(2025, 10, 7, 3, 0), -300), "2025-11-06")
assert.equal(S.storeLocalDate(Date.UTC(2025, 10, 7, 23, 30), 60), "2025-11-08")
// Store-local midnight that starts a local date, in ms (the oracle below).
const dayStartMs = (localDate, offset) => Date.parse(localDate + "T00:00:00Z") - offset * 60000

// historyStale: the startup rule.
assert(S.historyStale({ historyFetchedAt: 0 }, NOW))
assert(S.historyStale({ historyFetchedAt: NOW - 6 * 3600000 - 1 }, NOW))
assert(!S.historyStale({ historyFetchedAt: NOW - 6 * 3600000 }, NOW))

// historyDue: never fetched, 10 min after rollover, once more 6 h after.
const MIN = 60000
const H = 3600000
const start = dayStartMs("2025-11-07", -300)
assert.equal(start, Date.UTC(2025, 10, 7, 5, 0))
assert(S.historyDue({ historyFetchedAt: 0 }, NOW, "2025-11-07"))
assert(!S.historyDue({ historyFetchedAt: 5, historyLocalDate: "2025-11-07", utcOffsetMinutes: -300 }, NOW, ""), "no local date: nothing to compare")
const prevDay = { historyFetchedAt: start - H, historyLocalDate: "2025-11-06", utcOffsetMinutes: -300 }
assert(!S.historyDue(prevDay, start + 9 * MIN, "2025-11-07"), "rollover waits 10 min")
assert(S.historyDue(prevDay, start + 10 * MIN, "2025-11-07"), "+10 min mark")
const early = { historyFetchedAt: start + 30 * MIN, historyLocalDate: "2025-11-07", utcOffsetMinutes: -300 }
assert(!S.historyDue(early, start + H, "2025-11-07"), "no hourly refetch")
assert(!S.historyDue(early, start + 6 * H + 9 * MIN, "2025-11-07"))
assert(S.historyDue(early, start + 6 * H + 10 * MIN, "2025-11-07"), "+6 h 10 min backfill")
const late = { historyFetchedAt: start + 7 * H, historyLocalDate: "2025-11-07", utcOffsetMinutes: -300 }
assert(!S.historyDue(late, start + 12 * H, "2025-11-07"), "fetched after the backfill mark: done for the day")
assert(!S.historyDue(late, start + 23 * H + 59 * MIN, "2025-11-07"))
assert.equal(S.historyNextAt(early, start + H, "2025-11-07"), start + 6 * H + 10 * MIN)
assert.equal(S.historyNextAt(late, start + 12 * H, "2025-11-07"), start + 24 * H + 10 * MIN)
assert.equal(S.historyNextAt(prevDay, start + 5 * MIN, "2025-11-07"), start + 10 * MIN)
assert(!S.historyDue(early, NOW, "bad"), "a malformed local date is never due")
assert.equal(S.historyNextAt(early, NOW, "bad"), NOW + H, "a malformed local date re-checks in an hour")

// A 72 h minute-by-minute simulation of the scheduler loop: after the first
// day, exactly two history fetches per store per day, whatever the clock
// offset, and never one within 10 min of the rollover.
for (const offset of [-300, 0, 60, 330]) {
  const entry = { historyFetchedAt: 0, historyLocalDate: "", utcOffsetMinutes: offset }
  const fetches = []
  const t0 = Date.UTC(2025, 10, 7, 13, 0)
  for (let t = t0; t < t0 + 72 * H; t += MIN) {
    const localDate = S.storeLocalDate(t, offset)
    if (S.historyDue(entry, t, localDate)) {
      entry.historyFetchedAt = t
      entry.historyLocalDate = localDate
      fetches.push(t)
    }
  }
  const perDay = {}
  for (const t of fetches) {
    const d = S.storeLocalDate(t, offset)
    perDay[d] = (perDay[d] || 0) + 1
    const dayStart = dayStartMs(d, offset)
    assert(t === fetches[0] || t - dayStart >= 10 * MIN, "no fetch inside the first 10 min of a day")
  }
  const days = Object.keys(perDay).sort()
  for (const d of days.slice(1, -1)) assert.equal(perDay[d], 2, "offset " + offset + " day " + d + ": " + JSON.stringify(perDay))
  assert(fetches.length <= 2 * days.length, "offset " + offset + ": at most two per day")
}

// yesterdayDue
assert(S.yesterdayDue({ localDate: "2025-11-07", yesterdayDate: "2025-11-05", dayEndsAt: start + 86400000 }, NOW))
assert(!S.yesterdayDue({ localDate: "2025-11-07", yesterdayDate: "2025-11-06", dayEndsAt: start + 86400000 }, NOW))
const ended = { localDate: "2025-11-07", yesterdayDate: "2025-11-06", dayEndsAt: start + 86400000, yesterdayFetchedAt: NOW }
assert(S.yesterdayDue(ended, start + 86400000 + 1000), "day ended: refetch")
assert(!S.yesterdayDue(Object.assign({}, ended, { yesterdayFetchedAt: start + 86400000 + 500 }), start + 86400000 + 1000))
assert(S.dayRolledOver({ dayEndsAt: NOW }, NOW))
assert(!S.dayRolledOver({ dayEndsAt: NOW + 1 }, NOW))
assert(!S.dayRolledOver({}, NOW))

// effectiveLocalDate: the cached date until the store day ends, then the
// date from the cached offset; nothing without a timezone.
{
  const MIN2 = 60000
  const ends = Date.UTC(2025, 10, 8, 5, 0) // store midnight at UTC-5
  const clock = { timezone: "America/New_York", utcOffsetMinutes: -300, localDate: "2025-11-07", dayEndsAt: ends }
  assert.equal(S.effectiveLocalDate(clock, ends - MIN2), "2025-11-07")
  assert.equal(S.effectiveLocalDate(clock, ends + MIN2), "2025-11-08", "rolled over: the new date")
  assert.equal(S.effectiveLocalDate(Object.assign({}, clock, { localDate: "" }), ends - MIN2), "2025-11-07", "no cached date: from the offset")
  assert.equal(S.effectiveLocalDate({ localDate: "", timezone: "" }, ends), "")
  assert.equal(S.effectiveLocalDate({ localDate: "2025-11-07", timezone: "", dayEndsAt: ends }, ends + MIN2), "", "rolled over without a timezone")

  // Rolled over: history next-at uses the new date. The history was
  // fetched on the 7th after its backfill mark; just past midnight the
  // next mark is 10 min into the 8th, not a mark of the 7th (which would
  // re-arm for the 8th's backfill and skip the rollover fetch).
  const c = Object.assign({}, clock, { historyFetchedAt: ends - 60 * MIN2, historyLocalDate: "2025-11-07" })
  const now = ends + MIN2
  assert.equal(S.historyNextAt(c, now, S.effectiveLocalDate(c, now)), ends + 10 * MIN2)
  assert.equal(S.historyDue(c, ends + 10 * MIN2, S.effectiveLocalDate(c, ends + 10 * MIN2)), true)
  // Past the rollover mark with the fetch still held back (a backoff):
  // the next mark is the new day's backfill, never the old date's mark,
  // which lies in the past and would re-arm the timer every second.
  const later = ends + 30 * MIN2
  assert.equal(S.historyNextAt(c, later, S.effectiveLocalDate(c, later)), ends + (6 * 60 + 10) * MIN2)
  assert.ok(S.historyNextAt(c, later, c.localDate) < later, "the stale date's mark is already past")
}

// freshEntry / clearBackoff / entryAfter: the scheduler's entry rules.
{
  const e0 = S.freshEntry()
  assert.deepEqual(e0.failures, { today: 0, history: 0, yesterday: 0 })
  assert.deepEqual(e0.backoffUntil, { today: 0, history: 0, yesterday: 0 })
  assert.equal(e0.suspended, false)
  const T = 1000000
  const POLL = 60000
  // Today ok: due again after one poll; traffic stamped when asked.
  let e = S.entryAfter(e0, "today", { ok: true }, T, POLL, true)
  assert.equal(e.lastTodayAt, T)
  assert.equal(e.todayDueAt, T + POLL)
  assert.equal(e.lastTrafficAt, T)
  assert.equal(e0.lastTodayAt, 0, "the input entry is not touched")
  // A failure backs off and counts; a rate limit drops traffic and honours retryAfter.
  e = S.entryAfter(e, "today", { ok: false, error: { code: "rate_limited", retryAfter: 600 } }, T, POLL, true, zero)
  assert.equal(e.failures.today, 1)
  assert.equal(e.backoffUntil.today, T + 600000)
  assert.equal(e.todayDueAt, T + 600000)
  assert.equal(e.dropTraffic, true)
  e = S.entryAfter(e, "today", { ok: false, error: { code: "cli_failed" } }, T, POLL, false, zero)
  assert.equal(e.failures.today, 2)
  assert.equal(e.backoffUntil.today, T + 120000)
  // Success clears that range only.
  e = S.entryAfter(e, "history", { ok: false, error: { code: "timeout" } }, T, POLL, false, zero)
  e = S.entryAfter(e, "today", { ok: true }, T, POLL, false)
  assert.equal(e.failures.today, 0)
  assert.equal(e.backoffUntil.today, 0)
  assert.equal(e.dropTraffic, false)
  assert.equal(e.failures.history, 1)
  // History and yesterday successes keep a 5 min floor; history ends a forced refetch.
  e.forceHistory = true
  e = S.entryAfter(e, "history", { ok: true }, T, POLL, false)
  assert.equal(e.failures.history, 0)
  assert.equal(e.backoffUntil.history, T + 300000)
  assert.equal(e.forceHistory, false)
  e = S.entryAfter(e, "yesterday", { ok: true }, T, POLL, false)
  assert.equal(e.backoffUntil.yesterday, T + 300000)
  // sales_access_required suspends the store.
  assert.equal(S.entryAfter(e0, "today", { ok: false, error: { code: "sales_access_required" } }, T, POLL, false, zero).suspended, true)
  // clearBackoff: the named ranges, or all.
  const failed = S.entryAfter(S.entryAfter(e0, "today", { ok: false, error: { code: "timeout" } }, T, POLL, false, zero), "history", { ok: false, error: { code: "timeout" } }, T, POLL, false, zero)
  const h = S.clearBackoff(failed, ["history"])
  assert.equal(h.failures.history, 0)
  assert.equal(h.failures.today, 1)
  assert.equal(failed.failures.history, 1, "the input entry is not touched")
  const all = S.clearBackoff(failed)
  assert.deepEqual(all.failures, { today: 0, history: 0, yesterday: 0 })
  assert.deepEqual(all.backoffUntil, { today: 0, history: 0, yesterday: 0 })
  assert.deepEqual(S.RANGES, ["today", "history", "yesterday"])
}
