# Shop::Queries: every GraphQL/ShopifyQL text Shop sends, as frozen constants; data goes only in --variables ($filter, $after).

module Shop
  module Queries
    SHOP_NAME = <<~'GQL'.strip.freeze
      query ShopName { shop { name } }
    GQL

    SHOP_META = <<~'GQL'.strip.freeze
      query ShopMeta { shop { ianaTimezone currencyCode } }
    GQL

    # Today so far: exact count, the newest order, and per order its time
    # and amount (paged) for the total and the hourly chart.
    TODAY = <<~'GQL'.strip.freeze
      query Today($filter: String!) {
        shop { ianaTimezone currencyCode }
        count: ordersCount(query: $filter, limit: null) { count }
        latest: orders(first: 1, sortKey: CREATED_AT, reverse: true, query: $filter) {
          nodes { id name subtotalLineItemsQuantity totalPriceSet { shopMoney { amount } } lineItems(first: 1) { nodes { title } } } }
        page: orders(first: 250, sortKey: CREATED_AT, query: $filter) {
          nodes { createdAt totalPriceSet { shopMoney { amount } } } pageInfo { hasNextPage endCursor } }
      }
    GQL

    TODAY_WITH_TRAFFIC = <<~'GQL'.strip.freeze
      query TodayTraffic($filter: String!) {
        shop { ianaTimezone currencyCode }
        count: ordersCount(query: $filter, limit: null) { count }
        latest: orders(first: 1, sortKey: CREATED_AT, reverse: true, query: $filter) {
          nodes { id name subtotalLineItemsQuantity totalPriceSet { shopMoney { amount } } lineItems(first: 1) { nodes { title } } } }
        page: orders(first: 250, sortKey: CREATED_AT, query: $filter) {
          nodes { createdAt totalPriceSet { shopMoney { amount } } } pageInfo { hasNextPage endCursor } }
        traffic: shopifyqlQuery(query: "FROM sessions SHOW sessions, sessions_with_cart_additions, sessions_that_reached_checkout, sessions_that_completed_checkout DURING today") {
          tableData { columns { name } rows } parseErrors }
        trafficHourly: shopifyqlQuery(query: "FROM sessions SHOW sessions, sessions_with_cart_additions, sessions_that_reached_checkout, sessions_that_completed_checkout TIMESERIES hour DURING today ORDER BY hour ASC") {
          tableData { columns { name } rows } parseErrors }
      }
    GQL

    # Every order page after the first, today's and yesterday's alike.
    ORDERS_PAGE = <<~'GQL'.strip.freeze
      query OrdersPage($filter: String!, $after: String!) {
        page: orders(first: 250, after: $after, sortKey: CREATED_AT, query: $filter) {
          nodes { createdAt totalPriceSet { shopMoney { amount } } } pageInfo { hasNextPage endCursor } }
      }
    GQL

    # Yesterday: the orders (paged; only for today's "this time yesterday"
    # baseline, order totals like today's figure), and the hourly
    # Analytics total sales and sessions for the chart, which match
    # the history's Yesterday headline (net total_sales, returns booked on
    # the day of the return).
    YESTERDAY = <<~'GQL'.strip.freeze
      query Yesterday($filter: String!) {
        shop { ianaTimezone currencyCode }
        page: orders(first: 250, sortKey: CREATED_AT, query: $filter) {
          nodes { createdAt totalPriceSet { shopMoney { amount } } } pageInfo { hasNextPage endCursor } }
        salesHourly: shopifyqlQuery(query: "FROM sales SHOW total_sales TIMESERIES hour DURING yesterday ORDER BY hour ASC") {
          tableData { columns { name } rows } parseErrors }
        trafficHourly: shopifyqlQuery(query: "FROM sessions SHOW sessions, sessions_with_cart_additions, sessions_that_reached_checkout, sessions_that_completed_checkout TIMESERIES hour DURING yesterday ORDER BY hour ASC") {
          tableData { columns { name } rows } parseErrors }
      }
    GQL

    # Five ShopifyQL queries; the completed periods are derived in Shop::Sales.
    # The monthly and lifetime figures end with yesterday, like the day
    # windows: `UNTIL yesterday` includes yesterday, while a relative
    # `UNTIL -Nd` is exclusive (`UNTIL -1d` stops at the start of
    # yesterday, checked live) and `UNTIL -0d` would freeze a slice of
    # today, taken at fetch time, into 12m and Lifetime. A bare UNTIL needs
    # a SINCE: lifetime starts at 2006-01-01, before any Shopify store.
    HISTORY = <<~'GQL'.strip.freeze
      query History {
        shop { ianaTimezone currencyCode }
        salesDaily: shopifyqlQuery(query: "FROM sales SHOW total_sales, orders TIMESERIES day SINCE -60d UNTIL -0d ORDER BY day ASC") {
          tableData { columns { name } rows } parseErrors }
        sessionsDaily: shopifyqlQuery(query: "FROM sessions SHOW sessions, sessions_with_cart_additions, sessions_that_reached_checkout, sessions_that_completed_checkout TIMESERIES day SINCE -60d UNTIL -0d ORDER BY day ASC") {
          tableData { columns { name } rows } parseErrors }
        salesMonthly: shopifyqlQuery(query: "FROM sales SHOW total_sales, orders TIMESERIES month SINCE -365d UNTIL yesterday ORDER BY month ASC") {
          tableData { columns { name } rows } parseErrors }
        sessionsMonthly: shopifyqlQuery(query: "FROM sessions SHOW sessions, sessions_with_cart_additions, sessions_that_reached_checkout, sessions_that_completed_checkout TIMESERIES month SINCE -365d UNTIL yesterday ORDER BY month ASC") {
          tableData { columns { name } rows } parseErrors }
        lifetime: shopifyqlQuery(query: "FROM sales SHOW total_sales, orders SINCE 2006-01-01 UNTIL yesterday") {
          tableData { columns { name } rows } parseErrors }
      }
    GQL
  end
end
