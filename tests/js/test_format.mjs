// js/format.mjs: hand-rolled formatting (no Intl).
import assert from "node:assert/strict"
import * as F from "../../js/format.mjs"

assert.deepEqual([1, 0, -2.5, NaN, Infinity, "1", null].map(F.isNum), [true, true, true, false, false, false, false])

assert.equal(F.money(812, "USD"), "$812.00")
assert.equal(F.money(1284.5, "USD"), "$1,284.50")
assert.equal(F.money(1234567.891, "EUR"), "€1,234,567.89")
assert.equal(F.money(812, "CHF"), "CHF 812.00")
assert.equal(F.money(812, "JPY"), "¥812")
assert.equal(F.money(812, "CAD"), "CA$812.00")
assert.equal(F.money(-12.5, "GBP"), "-£12.50")
assert.equal(F.money(-0.001, "USD"), "$0.00")
assert.equal(F.money(null, "USD"), "—")
assert.equal(F.money(NaN, "USD"), "—")
assert.equal(F.money(812.4, "USD", { compact: true }), "$812")
assert.equal(F.money(1284.5, "USD", { compact: true }), "$1.3k")
assert.equal(F.money(1000, "USD", { compact: true }), "$1k")
assert.equal(F.money(250000, "USD", { compact: true }), "$250k")
assert.equal(F.money(2500000, "USD", { compact: true }), "$2.5M")
assert.equal(F.money(5, "", {}), "5.00")

assert.equal(F.count(1234567), "1,234,567")
assert.equal(F.count(0), "0")
assert.equal(F.count(null), "—")

assert.equal(F.percent(0.016), "1.6%")
assert.equal(F.percent(0.5332), "53.3%")
assert.equal(F.percent(null), "—")

// The trend size: whole percent from 10, one decimal under, no ".0".
const up = pct => F.trendText({ direction: "up", pct: pct })
assert.deepEqual([up(18.2), up(0.04), up(5), up(9.96)], ["▲ 18%", "▲ 0%", "▲ 5%", "▲ 10%"])
assert.equal(F.trendGlyph("up"), "▲")
assert.equal(F.trendGlyph("down"), "▼")
assert.equal(F.trendGlyph("flat"), "")

const now = 1762500000000
assert.equal(F.timeAgo(now - 10000, now), "just now")
assert.equal(F.timeAgo(now - 60000, now), "1 min ago")
assert.equal(F.timeAgo(now - 3 * 3600000, now), "3 h ago")
assert.equal(F.timeAgo(now - 26 * 3600000, now), "1 day ago")
assert.equal(F.timeAgo(0, now), "")

assert.equal(F.clockLocal(new Date(2025, 0, 1, 8, 5).getTime()), "08:05")
assert.equal(F.clockLocal(null), "")
assert.equal(F.dayLabel("2025-11-03"), "Mon 3 Nov")
assert.equal(F.dayLabel("bad"), "")
assert.equal(F.monthLabel("2025-12"), "Dec 2025")
assert.equal(F.monthLabel("2025-13"), "")

// backupWhen on this machine's clock.
{
  const at = new Date(2025, 10, 6, 11, 35).getTime() // Thu 6 Nov 2025
  assert.equal(F.backupWhen(at, new Date(2025, 10, 6, 18, 0).getTime()), "Today 11:35")
  assert.equal(F.backupWhen(at, new Date(2025, 10, 7, 0, 10).getTime()), "Yesterday 11:35")
  assert.equal(F.backupWhen(at, new Date(2025, 10, 20, 9, 0).getTime()), "Thu 6 Nov, 11:35")
  assert.equal(F.backupWhen(at, new Date(2026, 0, 2, 9, 0).getTime()), "Thu 6 Nov 2025, 11:35")
  assert.equal(F.backupWhen(0, now), "")
  assert.equal(F.backupWhen(null, now), "")
}

assert.equal(F.bytes(512), "512 B")
assert.equal(F.bytes(4718123), "4.5 MB")
assert.equal(F.bytes(-1), "—")
assert.equal(F.homeRelative("/home/u/themes/acme", "/home/u"), "~/themes/acme")
assert.equal(F.homeRelative("/home/u", "/home/u/"), "~")
assert.equal(F.homeRelative("/home/uu/x", "/home/u"), "/home/uu/x")
assert.equal(F.elapsed(42000), "0:42")
assert.equal(F.elapsed(3723000), "1:02:03")

// trendText: glyph + percent, nothing for flat or missing.
assert.equal(F.trendText({ direction: "up", pct: 18.2 }), "▲ 18%")
assert.equal(F.trendText({ direction: "down", pct: -2.46 }), "▼ 2.5%")
assert.equal(F.trendText({ direction: "flat", pct: 0 }), "")
assert.equal(F.trendText(null), "")

// pad2: the hour ticks ("07", "14").
assert.deepEqual([F.pad2(7), F.pad2(14)], ["07", "14"])
