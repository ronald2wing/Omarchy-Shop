// js/hourly.mjs: today's same-time-yesterday baseline and the hourly
// chart buckets (one per elapsed hour, DST days included).
import assert from "node:assert/strict"
import { load } from "./fixture.mjs"
import * as H from "../../js/hourly.mjs"
import { emptyRecord, applyFetchResult } from "../../js/sales.mjs"

// todayBaseline: 08:00 local, yesterday's orders before 08:00 and 8 full hours of traffic.
const yRes = load("yesterday.json")
// The day the helper nests under `yesterday`, epochs in seconds.
const y = Object.assign({}, yRes.yesterday, { fetchedAt: yRes.fetchedAt })
const today = load("today.json")
const b = H.todayBaseline(y, today.fetchedAt)
assert.deepEqual(b, { sales: 150.5, orders: 2, traffic: { sessions: 140, cartAdds: 13, reachedCheckout: 5, completed: 2 } })
// Half-way through hour 8 prorates hour 8.
const b2 = H.todayBaseline(y, today.fetchedAt + 30 * 60000)
assert.equal(b2.traffic.sessions, 170)
assert.equal(H.todayBaseline(Object.assign({}, y, { trafficHourly: null }), today.fetchedAt).traffic, null)
assert.equal(H.todayBaseline(y, y.endEpoch * 1000 - 1), null, "before today started")

// A truncated yesterday (paging stopped early, oldest orders first): the
// baseline holds only while the cutoff is before the newest fetched order.
const newest = Math.max.apply(null, y.orderPoints.map(o => o[0]))
const yCut = Object.assign({}, y, { truncated: true })
assert.equal(H.todayBaseline(yCut, newest - y.startEpoch * 1000 + y.endEpoch * 1000 + 60000), null, "truncated, cutoff past the last fetched order")
assert.deepEqual(H.todayBaseline(yCut, newest - y.startEpoch * 1000 + y.endEpoch * 1000 - 60000), H.todayBaseline(y, newest - y.startEpoch * 1000 + y.endEpoch * 1000 - 60000), "truncated, cutoff before the last fetched order")
assert.equal(H.todayBaseline(Object.assign({}, yCut, { orderPoints: [] }), today.fetchedAt), null, "truncated with no orders")

// salesHourlyBuckets: the Analytics series in the same hour grid; no
// series, no chart (never a fallback to order totals); a refund day with
// no orders draws its negative hour.
{
  const start = Date.UTC(2026, 10, 1, 4) / 1000
  const fall = H.salesHourlyBuckets({ startEpoch: start, endEpoch: start + 25 * 3600, orderPoints: [[(start + 60) * 1000, 9]],
                                      salesHourly: [{ hour: 24, sales: 12.5 }, { hour: 25, sales: 1 }], trafficHourly: [{ hour: 24, sessions: 7 }] })
  assert.equal(fall.length, 25)
  assert.deepEqual(fall[24], { hour: 24, sales: 12.5, sessions: 7 })
  assert.deepEqual(fall[0], { hour: 0, sales: 0, sessions: null }, "orders are not the chart")
  assert.deepEqual(H.salesHourlyBuckets({ startEpoch: start, endEpoch: start + 86400, orderPoints: [[(start + 60) * 1000, 9]], salesHourly: null }), [])
  const refund = H.salesHourlyBuckets({ startEpoch: start, endEpoch: start + 86400, orderPoints: [], salesHourly: [{ hour: 10, sales: -55 }] })
  assert.equal(refund[10].sales, -55)
  const st = applyFetchResult(emptyRecord(), { ok: true, yesterday: { date: "2026-10-22", startEpoch: start, endEpoch: start + 86400, orderPoints: [],
                                                                    salesHourly: [{ hour: 10, sales: -55 }], trafficHourly: null } }, { range: "yesterday" }).record
  assert.equal(st.sales.yesterdayHourly[10].sales, -55, "a return-only day charts its negative hour")
}

// hourlyBuckets: one bucket per elapsed hour, 25 on a fall-back day; a
// partial mark for the hour in progress.
{
  const start = Date.UTC(2026, 10, 1, 4) / 1000 // 2026-11-01 00:00 America/New_York
  const fall = H.hourlyBuckets({
    startEpoch: start, endEpoch: start + 25 * 3600,
    orderPoints: [[(start + 24 * 3600 + 60) * 1000, 12.5], [(start + 60) * 1000, 2]],
    trafficHourly: [{ hour: 24, sessions: 7 }, { hour: 0, sessions: 3 }]
  })
  assert.equal(fall.length, 25)
  assert.deepEqual(fall[24], { hour: 24, sales: 12.5, sessions: 7 })
  assert.deepEqual(fall[0], { hour: 0, sales: 2, sessions: 3 })
  const spring = H.hourlyBuckets({ startEpoch: start, endEpoch: start + 23 * 3600, orderPoints: [[(start + 23 * 3600) * 1000, 5]] })
  assert.equal(spring.length, 23)
  assert.equal(spring.reduce((a, b) => a + b.sales, 0), 0, "an order at the end of a 23-hour day is outside it")
  assert.equal(H.hourlyBuckets({ startEpoch: start, endEpoch: start + 86400, orderPoints: [] }).length, 24)
  assert.equal(H.hourlyBuckets({ startEpoch: start, orderPoints: [] }).length, 24, "no endEpoch: 24 hours")
  const partial = H.hourlyBuckets({ startEpoch: start, orderPoints: [] }, (start + 5 * 3600 + 1800) * 1000)
  assert.equal(partial[5].partial, true, "the hour in progress is partial")
  assert.equal("partial" in partial[4], false, "completed hours carry no partial key")
  assert.equal("partial" in H.hourlyBuckets({ startEpoch: start, orderPoints: [] }, (start + 30 * 3600) * 1000)[23], false, "a time past the day marks nothing")
}
