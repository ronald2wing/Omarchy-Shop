// Calendar dates as "YYYY-MM-DD" strings (a store-local day, a history
// bucket): the one parser, and the day before. Pure; dates are built from
// their parts, never parsed by the Date constructor (the V4 subset).

const DAY_MS = 86400000

// "2025-11-03" -> { year: 2025, month: 11, day: 3 }; anything else -> null.
export function parseYmd(text) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(text == null ? "" : text))
  if (!m) return null
  return { year: parseInt(m[1], 10), month: parseInt(m[2], 10), day: parseInt(m[3], 10) }
}

// The ms of UTC midnight that starts the date, or null.
export function utcMidnightMs(text) {
  const d = parseYmd(text)
  return d ? Date.UTC(d.year, d.month - 1, d.day) : null
}

// "2025-03-01" -> "2025-02-28"; "" for anything that is not a date.
export function previousDate(text) {
  const t = utcMidnightMs(text)
  return t === null ? "" : new Date(t - DAY_MS).toISOString().slice(0, 10)
}
