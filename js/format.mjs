// Display formatting, hand-rolled (the QML engine has no Intl).
import { parseYmd } from "./dates.mjs"

const SYMBOLS = {
  USD: "$", CAD: "CA$", AUD: "A$", NZD: "NZ$", HKD: "HK$", SGD: "S$", MXN: "MX$",
  EUR: "€", GBP: "£", JPY: "¥", CNY: "CN¥", INR: "₹", KRW: "₩", BRL: "R$",
  ILS: "₪", PHP: "₱", THB: "฿", VND: "₫", TRY: "₺", PLN: "zł", UAH: "₴"
}
const ZERO_DECIMAL = ["JPY", "KRW", "VND", "CLP", "ISK", "HUF", "TWD", "UGX"]
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const NONE = "—"

// The one finite-number predicate (shared by every module that reads figures).
export function isNum(n) {
  return typeof n === "number" && isFinite(n)
}

// Rounded to cents.
export function cents(n) {
  return Math.round(n * 100) / 100
}

function group(intDigits) {
  return intDigits.replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

// A plain number with grouping and fixed decimals: 1234.5 -> "1,234.50".
function grouped(n, decimals) {
  const fixed = Math.abs(n).toFixed(decimals)
  const dot = fixed.indexOf(".")
  const intPart = dot === -1 ? fixed : fixed.substring(0, dot)
  const frac = dot === -1 ? "" : fixed.substring(dot)
  return group(intPart) + frac
}

function compactNumber(abs) {
  const units = [[1e9, "B"], [1e6, "M"], [1e3, "k"]]
  for (let i = 0; i < units.length; i++) {
    if (abs >= units[i][0]) {
      let v = (abs / units[i][0]).toFixed(abs / units[i][0] >= 100 ? 0 : 1)
      if (v.endsWith(".0")) v = v.substring(0, v.length - 2)
      return v + units[i][1]
    }
  }
  return String(Math.round(abs))
}

// money(812, "USD") -> "$812.00"; compact -> "$812", "$1.3k"; unknown
// currency -> "CHF 812.00"; null -> "—".
export function money(amount, currency, opts) {
  if (!isNum(amount)) return NONE
  const compact = !!(opts && opts.compact)
  const c = String(currency || "").toUpperCase()
  const sym = Object.prototype.hasOwnProperty.call(SYMBOLS, c) ? SYMBOLS[c] : ""
  const decimals = ZERO_DECIMAL.includes(c) ? 0 : 2
  const abs = Math.abs(amount)
  const body = compact ? compactNumber(abs) : grouped(abs, decimals)
  const sign = amount < 0 && (compact ? Math.round(abs) > 0 : Number(abs.toFixed(decimals)) > 0) ? "-" : ""
  if (sym) return sign + sym + body
  if (/^[A-Z]{3}$/.test(c)) return sign + c + " " + body
  return sign + body
}

export function count(n) {
  if (!isNum(n)) return NONE
  return (n < 0 ? "-" : "") + group(String(Math.round(Math.abs(n))))
}

// A fraction as a percent: 0.016 -> "1.6%".
export function percent(fraction) {
  if (!isNum(fraction)) return NONE
  return (fraction * 100).toFixed(1) + "%"
}

// The size of a trend change already in percent units, without a sign (the
// trend glyph carries the direction): 18.2 -> "18%", -2.46 -> "2.5%".
// Under 10 keeps one decimal; a trailing ".0" is dropped.
function trendPercent(pct) {
  const abs = Math.abs(pct)
  let body = abs >= 10 ? String(Math.round(abs)) : abs.toFixed(1)
  if (body.endsWith(".0")) body = body.substring(0, body.length - 2)
  return body + "%"
}

// The trend direction glyph: "▲" up, "▼" down, else empty.
export function trendGlyph(direction) {
  if (direction === "up") return "▲"
  if (direction === "down") return "▼"
  return ""
}

// "▲ 18%" for a trend {direction, pct}; "" for a flat or missing one (the
// figure beside it already says what happened).
export function trendText(trend) {
  if (!trend || (trend.direction !== "up" && trend.direction !== "down")) return ""
  return trendGlyph(trend.direction) + " " + trendPercent(trend.pct)
}

export function timeAgo(ms, nowMs) {
  if (!isNum(ms) || ms <= 0) return ""
  const s = Math.max(0, Math.round((nowMs - ms) / 1000))
  if (s < 45) return "just now"
  const m = Math.round(s / 60)
  if (m < 60) return m + " min ago"
  const h = Math.round(m / 60)
  if (h < 24) return h + " h ago"
  const d = Math.round(h / 24)
  return d + (d === 1 ? " day ago" : " days ago")
}

export function pad2(n) {
  return n < 10 ? "0" + n : String(n)
}

// A local Date -> "Tue 3 Nov".
function weekdayDayMonth(d) {
  return WEEKDAYS[d.getDay()] + " " + d.getDate() + " " + MONTHS[d.getMonth()]
}

// "HH:MM" on this machine's clock (retry times, backup times).
export function clockLocal(ms) {
  if (!isNum(ms)) return ""
  const d = new Date(ms)
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

// "2026-11-03" -> "Tue 3 Nov".
export function dayLabel(ymd) {
  const d = parseYmd(ymd)
  return d ? weekdayDayMonth(new Date(d.year, d.month - 1, d.day)) : ""
}

// "2025-12" -> "Dec 2025".
export function monthLabel(ym) {
  const m = /^(\d{4})-(\d{2})$/.exec(String(ym || ""))
  if (!m) return ""
  const i = parseInt(m[2], 10) - 1
  if (i < 0 || i > 11) return ""
  return MONTHS[i] + " " + m[1]
}

function sameLocalDay(a, b) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}

// When a backup was taken, on this machine's clock: "Today 11:35",
// "Yesterday 09:12", "Thu 6 Nov, 11:35" or, in another year,
// "Thu 6 Nov 2025, 11:35". 0 or a bad value -> "".
export function backupWhen(ms, nowMs) {
  if (!isNum(ms) || ms <= 0) return ""
  const d = new Date(ms)
  const now = new Date(nowMs)
  const time = clockLocal(ms)
  if (sameLocalDay(d, now)) return "Today " + time
  if (sameLocalDay(d, new Date(now.getTime() - 86400000))) return "Yesterday " + time
  return weekdayDayMonth(d) + (d.getFullYear() === now.getFullYear() ? "" : " " + d.getFullYear()) + ", " + time
}

export function bytes(n) {
  if (!isNum(n) || n < 0) return NONE
  if (n < 1024) return Math.round(n) + " B"
  const units = ["KB", "MB", "GB", "TB"]
  let v = n
  let i = -1
  while (v >= 1024 && i < units.length - 1) { v = v / 1024; i++ }
  return (v >= 100 ? Math.round(v) : v.toFixed(1)) + " " + units[i]
}

// "/home/u/themes/acme" -> "~/themes/acme".
export function homeRelative(path, home) {
  const p = String(path == null ? "" : path)
  const h = String(home == null ? "" : home).replace(/\/+$/, "")
  if (!h) return p
  if (p === h) return "~"
  if (p.startsWith(h + "/")) return "~" + p.substring(h.length)
  return p
}

// "0:42", "12:05", "1:02:03".
export function elapsed(ms) {
  if (!isNum(ms) || ms < 0) return "0:00"
  const total = Math.floor(ms / 1000)
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  return h > 0 ? h + ":" + pad2(m) + ":" + pad2(s) : m + ":" + pad2(s)
}
