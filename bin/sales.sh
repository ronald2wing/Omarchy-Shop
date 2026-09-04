#!/usr/bin/env bash
set -euo pipefail

if ! command -v shopify >/dev/null 2>&1; then
  echo "Shopify CLI (shopify) not found — install it from https://shopify.dev/docs/api/shopify-cli" >&2
  exit 127
fi

domain="${1:?usage: sales.sh <myshopify-domain> [live|historical]}"
mode="${2:-live}"
case "$mode" in
  live|historical) ;;
  *) echo "usage: sales.sh <myshopify-domain> [live|historical]" >&2; exit 64 ;;
esac

# Step 1: shop metadata (timezone drives "today", currency labels money). The
# `-j` flag returns the GraphQL result with no `data` wrapper.
meta="$(shopify store execute -j -s "$domain" -q '{ shop { ianaTimezone currencyCode } }')"
tz="$(jq -r '.shop.ianaTimezone // "UTC"' <<<"$meta")"
currency="$(jq -r '.shop.currencyCode // ""' <<<"$meta")"

# Today's local midnight in the store's timezone. `created_at:>=<this>` scopes
# the real-time orders query to the current day only.
today="$(TZ="$tz" date -d 'today 00:00' +'%Y-%m-%dT%H:%M:%S%z')"
yesterday_start="$(TZ="$tz" date -d 'yesterday 00:00' +'%Y-%m-%dT%H:%M:%S%z')"
# "yesterday at now's clock time" — the fair comparison cutoff for the trend
yesterday_cutoff="$(TZ="$tz" date -d "yesterday $(TZ="$tz" date +'%H:%M:%S')" +'%Y-%m-%dT%H:%M:%S%z')"

# Step 2: `live` fetches only what changes during the day (today's orders +
# today's sessions); `historical` fetches the completed periods (week/month/
# biweek/allTime/yesterday + their sessions + timeseries). Completed periods are
# cached in the service, so polling them every 60s would spend ~60x the GraphQL
# cost for no new data.
#
# `read -d ''` returns nonzero at EOF (no NUL terminator), so `|| true` keeps
# `set -e` from aborting on it.
#
# NOTE: the orders `created_at` search filter only honors the time-of-day when
# the timestamp is single-quoted — unquoted, Shopify's parser treats the `T` as
# a field delimiter and drops everything after it (date-only matching). That
# matters for `yesterday_cutoff` (a mid-day time); `today` is midnight, so its
# unquoted form matches the whole day either way.
if [ "$mode" = "live" ]; then
  read -r -d '' query <<EOF || true
query {
  stats: shopifyqlQuery(query: "FROM sessions SHOW sessions, online_store_visitors, conversion_rate, added_to_cart_rate, checkout_conversion_rate DURING today") { tableData { columns { name } rows } parseErrors }
  todayOrders: orders(first: 250, sortKey: CREATED_AT, reverse: true, query: "created_at:>=$today") { edges { node { name totalPriceSet { shopMoney { amount currencyCode } } customer { firstName lastName } lineItems(first: 5) { edges { node { title quantity } } } } } pageInfo { hasNextPage endCursor } }
}
EOF
else
  read -r -d '' query <<EOF || true
query {
  week: shopifyqlQuery(query: "FROM sales SHOW total_sales, orders SINCE -7d UNTIL -0d") { tableData { columns { name } rows } parseErrors }
  month: shopifyqlQuery(query: "FROM sales SHOW total_sales, orders SINCE -30d UNTIL -0d") { tableData { columns { name } rows } parseErrors }
  biweek: shopifyqlQuery(query: "FROM sales SHOW total_sales, orders SINCE -14d UNTIL -0d") { tableData { columns { name } rows } parseErrors }
  allTime: shopifyqlQuery(query: "FROM sales SHOW total_sales, orders") { tableData { columns { name } rows } parseErrors }
  yesterdayFull: shopifyqlQuery(query: "FROM sales SHOW total_sales, orders SINCE -1d UNTIL -0d") { tableData { columns { name } rows } parseErrors }
  weekSeries: shopifyqlQuery(query: "FROM sales SHOW total_sales TIMESERIES day SINCE -7d UNTIL -0d ORDER BY day ASC") { tableData { columns { name } rows } parseErrors }
  biweekSeries: shopifyqlQuery(query: "FROM sales SHOW total_sales TIMESERIES day SINCE -14d UNTIL -0d ORDER BY day ASC") { tableData { columns { name } rows } parseErrors }
  monthSeries: shopifyqlQuery(query: "FROM sales SHOW total_sales TIMESERIES day SINCE -30d UNTIL -0d ORDER BY day ASC") { tableData { columns { name } rows } parseErrors }
  allTimeSeries: shopifyqlQuery(query: "FROM sales SHOW total_sales TIMESERIES month") { tableData { columns { name } rows } parseErrors }
  statsYesterday: shopifyqlQuery(query: "FROM sessions SHOW sessions, online_store_visitors, conversion_rate, added_to_cart_rate, checkout_conversion_rate SINCE -1d UNTIL -0d") { tableData { columns { name } rows } parseErrors }
  statsWeek: shopifyqlQuery(query: "FROM sessions SHOW sessions, online_store_visitors, conversion_rate, added_to_cart_rate, checkout_conversion_rate SINCE -7d UNTIL -0d") { tableData { columns { name } rows } parseErrors }
  statsBiweek: shopifyqlQuery(query: "FROM sessions SHOW sessions, online_store_visitors, conversion_rate, added_to_cart_rate, checkout_conversion_rate SINCE -14d UNTIL -0d") { tableData { columns { name } rows } parseErrors }
  statsMonth: shopifyqlQuery(query: "FROM sessions SHOW sessions, online_store_visitors, conversion_rate, added_to_cart_rate, checkout_conversion_rate SINCE -30d UNTIL -0d") { tableData { columns { name } rows } parseErrors }
  # "All" is bounded to a trailing year: an unbounded FROM sessions query costs
  # the full 1000-point shopifyqlCost budget and can never run (verified against
  # a live store — the combined query is throttled outright), so the widest
  # affordable window stands in for all-time.
  statsAll: shopifyqlQuery(query: "FROM sessions SHOW sessions, online_store_visitors, conversion_rate, added_to_cart_rate, checkout_conversion_rate SINCE -365d UNTIL -0d") { tableData { columns { name } rows } parseErrors }
  # Per-range sessions TIMESERIES, zipped against the sales series of the same
  # window so the widget can render a per-day Revenue-per-Session index. The
  # daily ones reuse the same -Nd windows as the sales series above; the
  # all-time one is bucketed by month and bounded to 365d (a no-filter sessions
  # TIMESERIES spends the full 1000-point shopifyqlCost budget and throttles).
  weekSessionsSeries: shopifyqlQuery(query: "FROM sessions SHOW sessions TIMESERIES day SINCE -7d UNTIL -0d ORDER BY day ASC") { tableData { columns { name } rows } parseErrors }
  biweekSessionsSeries: shopifyqlQuery(query: "FROM sessions SHOW sessions TIMESERIES day SINCE -14d UNTIL -0d ORDER BY day ASC") { tableData { columns { name } rows } parseErrors }
  monthSessionsSeries: shopifyqlQuery(query: "FROM sessions SHOW sessions TIMESERIES day SINCE -30d UNTIL -0d ORDER BY day ASC") { tableData { columns { name } rows } parseErrors }
  allTimeSessionsSeries: shopifyqlQuery(query: "FROM sessions SHOW sessions TIMESERIES month SINCE -365d UNTIL -0d") { tableData { columns { name } rows } parseErrors }
  yesterdayOrders: orders(first: 250, sortKey: CREATED_AT, reverse: true, query: "created_at:>='$yesterday_start' AND created_at:<='$yesterday_cutoff'") { edges { node { name totalPriceSet { shopMoney { amount currencyCode } } customer { firstName lastName } lineItems(first: 5) { edges { node { title quantity } } } } } pageInfo { hasNextPage endCursor } }
}
EOF
fi

result="$(shopify store execute -j -s "$domain" -q "$query")"
# Paginate an orders connection past the 250-per-page cap. Emits the accumulated
# edges array (single-line JSON) on stdout. Args: <domain> <created_at filter>
# <result JSON> <jq field prefix (".todayOrders" / ".yesterdayOrders")>. Each
# extra page is a separate `orders(first: 250, after: <cursor>)` query; edges
# accumulate with `jq -s`, which slurps the accumulated array + the new page into
# one array. `// []`/`// false` keep jq from failing on a null page. The loop is
# guarded against spinning: it stops as soon as the page says `hasNextPage` is
# false or returns no `endCursor`.
paginate_orders() {
  local domain="$1" filter="$2" result_json="$3" prefix="$4"
  local edges cursor has_next page
  edges="$(jq -c "$prefix.edges // []" <<<"$result_json")"
  cursor="$(jq -r "$prefix.pageInfo.endCursor // \"\"" <<<"$result_json")"
  has_next="$(jq -r "$prefix.pageInfo.hasNextPage // false" <<<"$result_json")"
  while [[ "$has_next" == "true" && -n "$cursor" ]]; do
    page="$(shopify store execute -j -s "$domain" -q "query { orders(first: 250, sortKey: CREATED_AT, reverse: true, after: \"$cursor\", query: \"$filter\") { edges { node { name totalPriceSet { shopMoney { amount currencyCode } } customer { firstName lastName } lineItems(first: 5) { edges { node { title quantity } } } } pageInfo { hasNextPage endCursor } } }")"
    edges="$(printf '%s\n%s\n' "$edges" "$page" | jq -s -c '[.[0][], (.[1].orders.edges // [])[]]')"
    cursor="$(jq -r '.orders.pageInfo.endCursor // ""' <<<"$page")"
    has_next="$(jq -r '.orders.pageInfo.hasNextPage // false' <<<"$page")"
  done
  echo "$edges"
}

# stdout is the JSON contract consumed by Model.js.parseSales; progress/log
# lines from the CLI go to stderr and are left alone. `pageInfo` is dropped —
# Model.js only reads `todayOrders.edges` / `yesterdayOrders.edges`.
if [ "$mode" = "live" ]; then
  today_edges="$(paginate_orders "$domain" "created_at:>=$today" "$result" ".todayOrders")"
  jq --arg c "$currency" --argjson edges "$today_edges" \
    '{ currency: (if $c == "" then null else $c end), todayOrders: { edges: $edges }, stats: .stats }' \
    <<<"$result"
else
  yest_edges="$(paginate_orders "$domain" "created_at:>='$yesterday_start' AND created_at:<='$yesterday_cutoff'" "$result" ".yesterdayOrders")"
  jq --arg c "$currency" --argjson yest_edges "$yest_edges" \
    '{ currency: (if $c == "" then null else $c end), week: .week, month: .month, biweek: .biweek, allTime: .allTime, yesterdayFull: .yesterdayFull, weekSeries: .weekSeries, biweekSeries: .biweekSeries, monthSeries: .monthSeries, allTimeSeries: .allTimeSeries, weekSessionsSeries: .weekSessionsSeries, biweekSessionsSeries: .biweekSessionsSeries, monthSessionsSeries: .monthSessionsSeries, allTimeSessionsSeries: .allTimeSessionsSeries, statsYesterday: .statsYesterday, statsWeek: .statsWeek, statsBiweek: .statsBiweek, statsMonth: .statsMonth, statsAll: .statsAll, yesterdayOrders: { edges: $yest_edges } }' \
    <<<"$result"
fi
