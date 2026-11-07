// js/dates.mjs: the one YYYY-MM-DD parser and the day before.
import assert from "node:assert/strict"
import * as D from "../../js/dates.mjs"

assert.deepEqual(D.parseYmd("2025-11-03"), { year: 2025, month: 11, day: 3 })
for (const bad of ["", null, undefined, "2025-11-3", "2025-11-03T00:00", " 2025-11-03", "bad"]) assert.equal(D.parseYmd(bad), null, String(bad))
assert.equal(D.utcMidnightMs("2025-11-03"), Date.UTC(2025, 10, 3))
assert.equal(D.utcMidnightMs("nope"), null)
assert.equal(D.previousDate("2025-03-01"), "2025-02-28")
assert.equal(D.previousDate("2024-03-01"), "2024-02-29")
assert.equal(D.previousDate("2026-01-01"), "2025-12-31")
assert.equal(D.previousDate("bad"), "")
