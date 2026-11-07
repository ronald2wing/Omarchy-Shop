// Numbers as figures: the one finite-number test and the rounding to
// cents, shared by every module that reads or sums figures (format.mjs
// only formats them).

// The one finite-number predicate.
export function isNum(n) {
  return typeof n === "number" && isFinite(n)
}

// Rounded to cents.
export function cents(n) {
  return Math.round(n * 100) / 100
}
