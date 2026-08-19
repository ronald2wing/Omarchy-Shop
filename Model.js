// Pure parsing/formatting for ShopifyQL sales responses. Loaded by QML via
// Qt.include("Model.js") and required by Node for tests.

function _metric(row, name) {
  if (!row || typeof row !== "object") return null
  if (Object.prototype.hasOwnProperty.call(row, name)) return row[name]
  return null
}

// Shared numeric-cell parser: string -> Number with comma-stripping, or null
// for absent/empty/unparseable cells. Callers decide what null means — a sum
// skips it, a range/stats parser surfaces it as a null field.
function _num(v) {
  if (v === null || v === undefined || v === "") return null
  var n = Number(String(v).replace(/,/g, ""))
  return isNaN(n) ? null : n
}

function _sum(rows, name) {
  var total = null
  for (var i = 0; i < rows.length; i++) {
    var n = _num(_metric(rows[i], name))
    if (n !== null) total = (total === null ? 0 : total) + n
  }
  return total
}

function _parseRange(section) {
  if (!section) return null
  var td = section.tableData
  var rows = (td && Array.isArray(td.rows)) ? td.rows : []
  return {
    sales: _sum(rows, "total_sales"),
    orders: _sum(rows, "orders")
  }
}

function _parseToday(section) {
  if (!section || !Array.isArray(section.edges)) return null
  var total = 0
  var edges = section.edges
  for (var i = 0; i < edges.length; i++) {
    var node = edges[i] && edges[i].node
    var money = node && node.totalPriceSet && node.totalPriceSet.shopMoney
    if (!money) continue
    var n = Number(money.amount)
    if (!isNaN(n)) total += n
  }
  return { sales: Math.round(total * 100) / 100, orders: edges.length }
}

function _parseStats(section) {
  if (!section) return null
  var td = section.tableData
  var rows = (td && Array.isArray(td.rows)) ? td.rows : []
  var row = rows.length > 0 ? rows[0] : null
  function num(name) {
    return _num(_metric(row, name))
  }
  return {
    visitors: num("online_store_visitors"),
    cvr: num("conversion_rate"),
    bounce: num("bounce_rate"),
    atc: num("added_to_cart_rate"),
    checkoutCvr: num("checkout_conversion_rate")
  }
}

// Copy a parsed stats section's value fields into a clean {visitors, cvr,
// bounce, atc, checkoutCvr} shape for the range-selected KPI objects.
function _statsSummary(stats) {
  if (!stats) return null
  return { visitors: stats.visitors, cvr: stats.cvr, bounce: stats.bounce, atc: stats.atc, checkoutCvr: stats.checkoutCvr }
}

function _parseSeries(section, bucketName, dropLast) {
  if (!section) return null
  var td = section.tableData
  var rows = (td && Array.isArray(td.rows)) ? td.rows : []
  var out = []
  // Daily TIMESERIES queries (SINCE -Nd UNTIL -0d) append today's partial
  // bucket as the LAST row; ShopifyQL's FROM sales analytics lags the current
  // day, so that bucket is always $0. dropLast strips it so the sparkline
  // shows complete days. All-time monthly buckets are partial-but-nonzero
  // (the current month), so they keep the trailing bucket.
  var nRows = (dropLast && rows.length > 0) ? rows.length - 1 : rows.length
  for (var i = 0; i < nRows; i++) {
    var row = rows[i]
    if (!row || typeof row !== "object") continue
    out.push({ day: _metric(row, bucketName), sales: _num(_metric(row, "total_sales")) })
  }
  return out
}

function _parseDaySeries(section) {
  return _parseSeries(section, "day", true)
}

// All-time buckets are calendar months, so the bucket column is `month` (not
// `day`) and the current (partial) month is kept rather than dropped.
function _parseMonthSeries(section) {
  return _parseSeries(section, "month", false)
}

function parseSales(raw) {
  var data = (raw && typeof raw === "object") ? raw : {}
  var currency = (data.currency != null) ? String(data.currency) : null
  var stats = _parseStats(data.stats)
  var statsYesterday = _parseStats(data.statsYesterday)
  var statsWeek = _parseStats(data.statsWeek)
  var statsBiweek = _parseStats(data.statsBiweek)
  var statsMonth = _parseStats(data.statsMonth)
  var statsAll = _parseStats(data.statsAll)
  var out = { today: _parseToday(data.todayOrders), week: _parseRange(data.week), month: _parseRange(data.month), biweek: _parseRange(data.biweek), allTime: _parseRange(data.allTime), yesterday: _parseRange(data.yesterdayFull), yesterdaySoFar: _parseToday(data.yesterdayOrders), weekSeries: _parseDaySeries(data.weekSeries), biweekSeries: _parseDaySeries(data.biweekSeries) || [], monthSeries: _parseDaySeries(data.monthSeries) || [], allTimeSeries: _parseMonthSeries(data.allTimeSeries) || [], statsToday: _statsSummary(stats), statsYesterday: _statsSummary(statsYesterday), statsWeek: _statsSummary(statsWeek), statsBiweek: _statsSummary(statsBiweek), statsMonth: _statsSummary(statsMonth), statsAll: _statsSummary(statsAll), currency: currency }
  return out
}

function _fmt(n) {
  if (n === null || n === undefined || isNaN(n)) return "—"
  var neg = n < 0
  var abs = Math.abs(n)
  var s = abs.toFixed(abs >= 1000 ? 0 : 2)
  if (s.slice(-3) === ".00") s = s.slice(0, -3)
  var parts = s.split(".")
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  return (neg ? "-" : "") + parts.join(".")
}

function symbolFor(code) {
  if (!code) return "$"
  var map = { USD: "$", EUR: "€", GBP: "£", CAD: "C$", AUD: "A$", JPY: "¥", CNY: "¥", HKD: "HK$", SGD: "S$", NZD: "NZ$", INR: "₹", KRW: "₩", BRL: "R$", MXN: "MX$", SEK: "kr", NOK: "kr", DKK: "kr", PLN: "zł", AED: "AED", ZAR: "R", CHF: "CHF" }
  return map[String(code).toUpperCase()] || code
}

function formatMoney(value, currency) {
  var n = Number(value)
  if (value === null || value === undefined || value === "" || isNaN(n)) return "—"
  return symbolFor(currency) + _fmt(n)
}

function formatCount(value) {
  var n = Number(value)
  if (value === null || value === undefined || value === "" || isNaN(n)) return "—"
  return _fmt(n)
}

// Format a conversion-rate fraction (e.g. 0.005034...) as a percentage with
// two decimals ("0.50%"). Returns "—" for null/NaN.
function formatPercent(fraction) {
  var n = Number(fraction)
  if (fraction === null || fraction === undefined || fraction === "" || isNaN(n)) return "—"
  return (n * 100).toFixed(2) + "%"
}

// Strip ANSI control sequences from CLI output. The theme CLI overwrites its
// "Downloading files [X%]" progress line in place with CSI sequences; captured
// verbatim those render as raw garbage (a stuck-looking "93%"). OSC sequences
// are stripped defensively even though the theme CLI doesn't emit them today.
function stripAnsi(text) {
  if (text === null || text === undefined) return ""
  return String(text)
    .replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "")
    .replace(/\x1b\][^\x07\x1b]*(\x07|\x1b\\)/g, "")
    .replace(/\r/g, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim()
}

// Case-insensitive natural sort: numeric runs compare numerically so "01" <
// "10" and "00" < "01"; the rest compares as lowercased text.
function naturalCompare(a, b) {
  a = String(a == null ? "" : a).toLowerCase()
  b = String(b == null ? "" : b).toLowerCase()
  var re = /(\d+|\D+)/g
  var aa = a.match(re) || []
  var bb = b.match(re) || []
  var n = Math.max(aa.length, bb.length)
  for (var i = 0; i < n; i++) {
    var pa = i < aa.length ? aa[i] : ""
    var pb = i < bb.length ? bb[i] : ""
    if (pa === pb) continue
    if (/^\d+$/.test(pa) && /^\d+$/.test(pb)) return parseInt(pa, 10) - parseInt(pb, 10)
    return pa < pb ? -1 : 1
  }
  return 0
}

// Format a unix-seconds epoch (theme.sh backups are `date +%s`) as a compact
// local "Mon D HH:MM" (e.g. "Aug 19 16:03").
function formatEpoch(epochSeconds) {
  var n = Number(epochSeconds)
  if (!isFinite(n) || n <= 0) return ""
  var d = new Date(n * 1000)
  if (isNaN(d.getTime())) return ""
  var m = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  function pad(x) { return (x < 10 ? "0" : "") + x }
  return m[d.getMonth()] + " " + d.getDate() + " " + pad(d.getHours()) + ":" + pad(d.getMinutes())
}

if (typeof module !== "undefined") {
  module.exports = { parseSales: parseSales, formatMoney: formatMoney, formatCount: formatCount, formatPercent: formatPercent, symbolFor: symbolFor, stripAnsi: stripAnsi, naturalCompare: naturalCompare, formatEpoch: formatEpoch }
}
