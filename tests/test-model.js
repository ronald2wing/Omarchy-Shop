var assert = require("assert")
var M = require("../Model.js")

var raw = {
  currency: "USD",
  week: { tableData: { columns: [{ name: "total_sales" }, { name: "orders" }], rows: [{ total_sales: "890.10", orders: 95 }] }, parseErrors: [] },
  month: { tableData: { columns: [{ name: "total_sales" }, { name: "orders" }], rows: [{ total_sales: "12345.67", orders: 310 }] }, parseErrors: [] },
  yesterdayOrders: {
    edges: [
      { node: { name: "#1001", totalPriceSet: { shopMoney: { amount: "120.10", currencyCode: "USD" } }, customer: { firstName: "Alice", lastName: "Smith" }, lineItems: { edges: [] } } },
      { node: { name: "#1002", totalPriceSet: { shopMoney: { amount: "15.90", currencyCode: "USD" } }, customer: null, lineItems: null } }
    ],
    pageInfo: { hasNextPage: false }
  },
  todayOrders: {
    edges: [
      { node: { name: "#1005", totalPriceSet: { shopMoney: { amount: "35.81", currencyCode: "USD" } }, customer: { firstName: "Jane", lastName: "Doe" }, lineItems: { edges: [{ node: { title: "T-Shirt", quantity: 2 } }, { node: { title: "Hat", quantity: 1 } }] } } },
      { node: { name: "#1004", totalPriceSet: { shopMoney: { amount: "34.99", currencyCode: "USD" } }, customer: { firstName: "John", lastName: null }, lineItems: { edges: [{ node: { title: "Mug", quantity: 1 } }] } } }
    ],
    pageInfo: { hasNextPage: false }
  },
  stats: {
    tableData: {
      columns: [{ name: "sessions" }, { name: "online_store_visitors" }, { name: "conversion_rate" }, { name: "added_to_cart_rate" }, { name: "checkout_conversion_rate" }],
      rows: [{ sessions: "1621", online_store_visitors: "1584", conversion_rate: "0.004935", added_to_cart_rate: "0.07587", checkout_conversion_rate: "0.1860" }]
    },
    parseErrors: []
  },
  statsWeek: {
    tableData: {
      columns: [{ name: "sessions" }, { name: "online_store_visitors" }, { name: "conversion_rate" }, { name: "added_to_cart_rate" }, { name: "checkout_conversion_rate" }],
      rows: [{ sessions: "3446", online_store_visitors: "3232", conversion_rate: "0.007545", added_to_cart_rate: "0.09228", checkout_conversion_rate: "0.2031" }]
    },
    parseErrors: []
  },
  statsBiweek: {
    tableData: {
      columns: [{ name: "sessions" }, { name: "online_store_visitors" }, { name: "conversion_rate" }, { name: "added_to_cart_rate" }, { name: "checkout_conversion_rate" }],
      rows: [{ sessions: "5000", online_store_visitors: "4700", conversion_rate: "0.006", added_to_cart_rate: "0.08", checkout_conversion_rate: "0.2" }]
    },
    parseErrors: []
  },
  statsMonth: {
    tableData: {
      columns: [{ name: "sessions" }, { name: "online_store_visitors" }, { name: "conversion_rate" }, { name: "added_to_cart_rate" }, { name: "checkout_conversion_rate" }],
      rows: [{ sessions: "6000", online_store_visitors: "5600", conversion_rate: "0.0065", added_to_cart_rate: "0.07", checkout_conversion_rate: "0.19" }]
    },
    parseErrors: []
  },
  statsAll: {
    tableData: {
      columns: [{ name: "sessions" }, { name: "online_store_visitors" }, { name: "conversion_rate" }, { name: "added_to_cart_rate" }, { name: "checkout_conversion_rate" }],
      rows: [{ sessions: "7806", online_store_visitors: "6974", conversion_rate: "0.009096", added_to_cart_rate: "0.08417", checkout_conversion_rate: "0.2457" }]
    },
    parseErrors: []
  },
  weekSeries: {
    tableData: {
      columns: [{ name: "day" }, { name: "total_sales" }],
      rows: [
        { day: "2026-08-13", total_sales: "100.00" },
        { day: "2026-08-14", total_sales: "0.00" },
        { day: "2026-08-15", total_sales: "250.50" },
        { day: "2026-08-16", total_sales: "0.00" },
        { day: "2026-08-17", total_sales: "75.25" },
        { day: "2026-08-18", total_sales: "300.00" },
        { day: "2026-08-19", total_sales: "120.40" }
      ]
    },
    parseErrors: []
  },
  biweekSeries: {
    tableData: {
      columns: [{ name: "day" }, { name: "total_sales" }],
      rows: [
        { day: "2026-08-05", total_sales: "10.00" },
        { day: "2026-08-06", total_sales: "20.00" },
        { day: "2026-08-19", total_sales: "0.00" }
      ]
    },
    parseErrors: []
  },
  monthSeries: {
    tableData: {
      columns: [{ name: "day" }, { name: "total_sales" }],
      rows: [
        { day: "2026-07-20", total_sales: "5.00" },
        { day: "2026-08-19", total_sales: "0.00" }
      ]
    },
    parseErrors: []
  },
  allTimeSeries: {
    tableData: {
      columns: [{ name: "month" }, { name: "total_sales" }],
      rows: [
        { month: "2026-05-01", total_sales: "0" },
        { month: "2026-06-01", total_sales: "0" },
        { month: "2026-07-01", total_sales: "1013.42" },
        { month: "2026-08-01", total_sales: "2257.97" }
      ]
    },
    parseErrors: []
  },
  weekSessionsSeries: {
    tableData: {
      columns: [{ name: "day" }, { name: "sessions" }],
      rows: [
        { day: "2026-08-13", sessions: "100" },
        { day: "2026-08-14", sessions: "120" },
        { day: "2026-08-15", sessions: "80" },
        { day: "2026-08-16", sessions: "95" },
        { day: "2026-08-17", sessions: "130" },
        { day: "2026-08-18", sessions: "200" },
        { day: "2026-08-19", sessions: "150" }
      ]
    },
    parseErrors: []
  },
  biweekSessionsSeries: {
    tableData: {
      columns: [{ name: "day" }, { name: "sessions" }],
      rows: [
        { day: "2026-08-05", sessions: "50" },
        { day: "2026-08-06", sessions: "70" },
        { day: "2026-08-19", sessions: "0" }
      ]
    },
    parseErrors: []
  },
  monthSessionsSeries: {
    tableData: {
      columns: [{ name: "day" }, { name: "sessions" }],
      rows: [
        { day: "2026-07-20", sessions: "40" },
        { day: "2026-08-19", sessions: "0" }
      ]
    },
    parseErrors: []
  },
  allTimeSessionsSeries: {
    tableData: {
      columns: [{ name: "month" }, { name: "sessions" }],
      rows: [
        { month: "2026-05-01", sessions: "0" },
        { month: "2026-06-01", sessions: "0" },
        { month: "2026-07-01", sessions: "3000" },
        { month: "2026-08-01", sessions: "4000" }
      ]
    },
    parseErrors: []
  }
}

// today parsed from real-time orders edges (sum of shopMoney.amount, count = edges.length)
assert.strictEqual(M.parseSales(raw).today.sales, 70.80)
assert.strictEqual(M.parseSales(raw).today.orders, 2)

// latest order details (edges[0], first row = most recent DESC)
var latest = M.parseSales(raw).today.latest
assert.strictEqual(latest.orderNumber, "#1005")
assert.strictEqual(latest.total, 35.81)
assert.strictEqual(latest.customerName, "Jane Doe")
assert.deepStrictEqual(latest.items, [{ title: "T-Shirt", quantity: 2 }, { title: "Hat", quantity: 1 }])

// week/month still parsed from ShopifyQL tableData (string cells)
assert.strictEqual(M.parseSales(raw).week.sales, 890.10)
assert.strictEqual(M.parseSales(raw).week.orders, 95)
assert.strictEqual(M.parseSales(raw).month.sales, 12345.67)
assert.strictEqual(M.parseSales(raw).month.orders, 310)

// yesterdaySoFar parsed from real-time orders edges (same shape as todayOrders)
assert.strictEqual(M.parseSales(raw).yesterdaySoFar.sales, 136.00)
assert.strictEqual(M.parseSales(raw).yesterdaySoFar.orders, 2)

// currency extracted from the top level
assert.strictEqual(M.parseSales(raw).currency, "USD")

// today's stats parsed into the statsToday object
assert.strictEqual(M.parseSales(raw).statsToday.visitors, 1584)
assert.strictEqual(M.parseSales(raw).statsToday.sessions, 1621)
assert.strictEqual(M.parseSales(raw).statsToday.cvr, 0.004935)
assert.strictEqual(M.parseSales(raw).statsToday.atc, 0.07587)
assert.strictEqual(M.parseSales(raw).statsToday.checkoutCvr, 0.1860)

// range-selected stats objects parsed from statsWeek/statsBiweek/statsMonth/statsAll
assert.strictEqual(M.parseSales(raw).statsWeek.visitors, 3232)
assert.strictEqual(M.parseSales(raw).statsWeek.sessions, 3446)
assert.strictEqual(M.parseSales(raw).statsWeek.cvr, 0.007545)
assert.strictEqual(M.parseSales(raw).statsBiweek.visitors, 4700)
assert.strictEqual(M.parseSales(raw).statsMonth.atc, 0.07)
assert.strictEqual(M.parseSales(raw).statsAll.checkoutCvr, 0.2457)
assert.strictEqual(M.parseSales(raw).statsAll.sessions, 7806)

// weekSeries parsed from weekSeries.tableData.rows (day + per-day total_sales);
// the LAST row (today's partial bucket, always $0 due to analytics lag) is dropped.
var ws = M.parseSales(raw).weekSeries
assert.strictEqual(ws.length, 6)
assert.strictEqual(ws[0].day, "2026-08-13")
assert.strictEqual(ws[0].sales, 100)
assert.strictEqual(ws[2].sales, 250.5)
assert.strictEqual(ws[3].sales, 0)
assert.strictEqual(ws[5].sales, 300)

// biweekSeries/monthSeries use the same daily parser (drop the trailing $0 bucket).
var bs = M.parseSales(raw).biweekSeries
assert.strictEqual(bs.length, 2)
assert.strictEqual(bs[0].day, "2026-08-05")
assert.strictEqual(bs[0].sales, 10)
assert.strictEqual(bs[1].sales, 20)

var ms = M.parseSales(raw).monthSeries
assert.strictEqual(ms.length, 1)
assert.strictEqual(ms[0].day, "2026-07-20")
assert.strictEqual(ms[0].sales, 5)

// allTimeSeries is bucketed by `month` (not `day`) and KEEPS the current
// partial month.
var ats = M.parseSales(raw).allTimeSeries
assert.strictEqual(ats.length, 4)
assert.strictEqual(ats[0].day, "2026-05-01")
assert.strictEqual(ats[0].sales, 0)
assert.strictEqual(ats[2].sales, 1013.42)
assert.strictEqual(ats[3].day, "2026-08-01")
assert.strictEqual(ats[3].sales, 2257.97)

// sessions series: daily ones reuse the daily parser with `sessions` as the
// value column (trailing partial bucket dropped); the monthly one keeps the
// current month.
var wss = M.parseSales(raw).weekSessionsSeries
assert.strictEqual(wss.length, 6)
assert.strictEqual(wss[0].day, "2026-08-13")
assert.strictEqual(wss[0].sessions, 100)
assert.strictEqual(wss[5].sessions, 200)

var bss = M.parseSales(raw).biweekSessionsSeries
assert.strictEqual(bss.length, 2)
assert.strictEqual(bss[0].sessions, 50)
assert.strictEqual(bss[1].sessions, 70)

var mss = M.parseSales(raw).monthSessionsSeries
assert.strictEqual(mss.length, 1)
assert.strictEqual(mss[0].sessions, 40)

var atss = M.parseSales(raw).allTimeSessionsSeries
assert.strictEqual(atss.length, 4)
assert.strictEqual(atss[0].sessions, 0)
assert.strictEqual(atss[3].sessions, 4000)

// statsToday/weekSeries = null when absent
assert.strictEqual(M.parseSales({ currency: "USD" }).statsToday, null)
assert.strictEqual(M.parseSales({ currency: "USD" }).weekSeries, null)

// range-selected stats objects = null when absent
assert.strictEqual(M.parseSales({ currency: "USD" }).statsWeek, null)
assert.strictEqual(M.parseSales({ currency: "USD" }).statsBiweek, null)
assert.strictEqual(M.parseSales({ currency: "USD" }).statsMonth, null)
assert.strictEqual(M.parseSales({ currency: "USD" }).statsAll, null)

// biweekSeries/monthSeries/allTimeSeries = [] when absent (never null)
assert.deepStrictEqual(M.parseSales({ currency: "USD" }).biweekSeries, [])
assert.deepStrictEqual(M.parseSales({ currency: "USD" }).monthSeries, [])
assert.deepStrictEqual(M.parseSales({ currency: "USD" }).allTimeSeries, [])

// sessions series = [] when absent (never null)
assert.deepStrictEqual(M.parseSales({ currency: "USD" }).weekSessionsSeries, [])
assert.deepStrictEqual(M.parseSales({ currency: "USD" }).biweekSessionsSeries, [])
assert.deepStrictEqual(M.parseSales({ currency: "USD" }).monthSessionsSeries, [])
assert.deepStrictEqual(M.parseSales({ currency: "USD" }).allTimeSessionsSeries, [])

// today = null when todayOrders absent (or edges not an array)
assert.strictEqual(M.parseSales({ currency: "USD", week: raw.week, month: raw.month }).today, null)
assert.strictEqual(M.parseSales({ currency: "USD", todayOrders: {} }).today, null)
assert.strictEqual(M.parseSales({ currency: "USD", todayOrders: { edges: "nope" } }).today, null)

// yesterdaySoFar = null when yesterdayOrders absent (or edges not an array)
assert.strictEqual(M.parseSales({ currency: "USD", yesterdayOrders: {} }).yesterdaySoFar, null)
assert.strictEqual(M.parseSales({ currency: "USD", yesterdayOrders: { edges: "nope" } }).yesterdaySoFar, null)

// currency null when absent
assert.strictEqual(M.parseSales({ week: raw.week, month: raw.month }).currency, null)

// missing range → null
assert.strictEqual(M.parseSales({ currency: "USD", week: raw.week }).month, null)
assert.strictEqual(M.parseSales({ currency: "USD", week: raw.week }).yesterday, null)
assert.strictEqual(M.parseSales({ currency: "USD", week: raw.week }).yesterdaySoFar, null)

// live-only payload (todayOrders + stats; no historical fields) parses without
// throwing: today + today-stats populated, historical ranges null / series [].
var liveOnly = M.parseSales({
  currency: "USD",
  todayOrders: raw.todayOrders,
  stats: raw.stats
})
assert.strictEqual(liveOnly.today.sales, 70.80)
assert.strictEqual(liveOnly.today.orders, 2)
assert.strictEqual(liveOnly.statsToday.visitors, 1584)
assert.strictEqual(liveOnly.statsToday.cvr, 0.004935)
assert.strictEqual(liveOnly.week, null)
assert.strictEqual(liveOnly.month, null)
assert.strictEqual(liveOnly.yesterday, null)
assert.strictEqual(liveOnly.yesterdaySoFar, null)
assert.strictEqual(liveOnly.statsWeek, null)
assert.strictEqual(liveOnly.weekSeries, null)
assert.deepStrictEqual(liveOnly.biweekSeries, [])
assert.deepStrictEqual(liveOnly.allTimeSeries, [])

// historical-only payload (completed periods; no todayOrders/stats) parses
// without throwing: ranges + yesterday + range-stats populated, today + today
// stats null.
var histOnly = M.parseSales({
  currency: "USD",
  week: raw.week,
  month: raw.month,
  biweek: { tableData: { columns: [{ name: "total_sales" }, { name: "orders" }], rows: [{ total_sales: "50.00", orders: 12 }] }, parseErrors: [] },
  allTime: { tableData: { columns: [{ name: "total_sales" }, { name: "orders" }], rows: [{ total_sales: "999.99", orders: 1 }] }, parseErrors: [] },
  yesterdayFull: { tableData: { columns: [{ name: "total_sales" }, { name: "orders" }], rows: [{ total_sales: "77.00", orders: 3 }] }, parseErrors: [] },
  yesterdayOrders: raw.yesterdayOrders,
  weekSeries: raw.weekSeries,
  biweekSeries: raw.biweekSeries,
  monthSeries: raw.monthSeries,
  allTimeSeries: raw.allTimeSeries,
  statsYesterday: { tableData: { columns: [{ name: "online_store_visitors" }, { name: "conversion_rate" }, { name: "added_to_cart_rate" }, { name: "checkout_conversion_rate" }], rows: [{ online_store_visitors: "1234", conversion_rate: "0.005", added_to_cart_rate: "0.08", checkout_conversion_rate: "0.2" }] }, parseErrors: [] },
  statsWeek: raw.statsWeek,
  statsBiweek: raw.statsBiweek,
  statsMonth: raw.statsMonth,
  statsAll: raw.statsAll
})
assert.strictEqual(histOnly.week.sales, 890.10)
assert.strictEqual(histOnly.biweek.sales, 50.00)
assert.strictEqual(histOnly.allTime.sales, 999.99)
assert.strictEqual(histOnly.yesterday.orders, 3)
assert.strictEqual(histOnly.yesterdaySoFar.sales, 136.00)
assert.strictEqual(histOnly.statsYesterday.visitors, 1234)
assert.strictEqual(histOnly.statsWeek.visitors, 3232)
assert.strictEqual(histOnly.allTimeSeries.length, 4)
assert.strictEqual(histOnly.today, null)
assert.strictEqual(histOnly.statsToday, null)

assert.strictEqual(M.formatMoney("123.45", "USD"), "$123.45")
assert.strictEqual(M.formatMoney("1234567.89", "USD"), "$1,234,568")
assert.strictEqual(M.formatMoney(null, "USD"), "—")
assert.strictEqual(M.formatCount(12), "12")
assert.strictEqual(M.formatCount(null), "—")
assert.strictEqual(M.formatPercent(0.005), "0.50%")
assert.strictEqual(M.formatPercent(0.005034612964128383), "0.50%")
assert.strictEqual(M.formatPercent(0), "0.00%")
assert.strictEqual(M.formatPercent(null), "—")
assert.strictEqual(M.formatPercent(undefined), "—")
assert.strictEqual(M.formatPercent("abc"), "—")
assert.strictEqual(M.symbolFor("EUR"), "€")
assert.strictEqual(M.symbolFor("$"), "$")

// rsi(): Revenue/Session Index = (sales/sessions) / (baseSales/baseSessions) * 100
assert.strictEqual(M.rsi(100, 10, 100, 10), 100)   // baseline-equal → 100
assert.strictEqual(M.rsi(200, 10, 100, 10), 200)   // above → >100
assert.strictEqual(M.rsi(50, 10, 100, 10), 50)     // below → <100
assert.strictEqual(M.rsi(0, 10, 100, 10), 0)       // zero sales → 0
assert.strictEqual(M.rsi(null, 10, 100, 10), null)      // null sales → null
assert.strictEqual(M.rsi(undefined, 10, 100, 10), null) // undefined sales → null
assert.strictEqual(M.rsi(100, 0, 100, 10), null)   // zero sessions → null
assert.strictEqual(M.rsi(100, 10, 0, 10), null)    // zero baseline sales → null
assert.strictEqual(M.rsi(100, 10, 100, 0), null)   // zero baseline sessions → null

// stripAnsi: exact output captured from a real `shopify theme pull`
var dirty = "Downloading files from remote theme [0%] ...\n\u001b[2K\u001b[1A\u001b[2K\u001b[GDownloading files from remote theme [93%] ...\n\u001b[2K\u001b[1A\u001b[2K\u001b[G"
assert.strictEqual(M.stripAnsi(dirty), "Downloading files from remote theme [0%] ...\nDownloading files from remote theme [93%] ...")
assert.strictEqual(M.stripAnsi("\u001b[31mred\u001b[0m text"), "red text")
assert.strictEqual(M.stripAnsi(null), "")
assert.strictEqual(M.stripAnsi("  plain  \n"), "plain")

// naturalCompare: case-insensitive + numeric-aware natural sort
assert.strictEqual(M.naturalCompare("store01", "store00") > 0, true)
assert.strictEqual(M.naturalCompare("store10", "store01") > 0, true)
assert.strictEqual(M.naturalCompare("Store 9", "store 10") < 0, true)
assert.strictEqual(M.naturalCompare("BEETLEJUICER", "purrtal") < 0, true)
assert.strictEqual(M.naturalCompare("Crochet", "crochet"), 0)

// formatEpoch: unix-seconds -> compact local "Mon D HH:MM" (shape only; TZ-dependent)
assert.ok(/^[A-Z][a-z]{2} \d{1,2} \d{2}:\d{2}$/.test(M.formatEpoch(1787176202)), "formatEpoch shape")
assert.strictEqual(M.formatEpoch(0), "")
assert.strictEqual(M.formatEpoch(-5), "")
assert.strictEqual(M.formatEpoch("abc"), "")
assert.strictEqual(M.formatEpoch(null), "")
assert.strictEqual(M.formatEpoch(undefined), "")

console.log("all model tests passed")
