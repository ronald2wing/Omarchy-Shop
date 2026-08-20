#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sales_sh="$here/../bin/sales.sh"
fake_bin="$here/fake-shopify"

# Shadow the real `shopify` with the fake by symlinking it as `shopify` in a
# temp dir at the head of PATH.
bindir="$(mktemp -d)"
log="$(mktemp)"
ln -s "$fake_bin" "$bindir/shopify"
export SHOPIFY_FAKE_LOG="$log"
export PATH="$bindir:$PATH"
trap 'rm -rf "$bindir" "$log"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

live_out="$("$sales_sh" fake.myshopify.com live)"
hist_out="$("$sales_sh" fake.myshopify.com historical)"

# live emits ONLY today's fields: currency + todayOrders + today stats.
printf '%s' "$live_out" | jq -e 'has("currency") and has("todayOrders") and has("stats")' >/dev/null \
  || fail "live output missing expected top-level keys"
printf '%s' "$live_out" | jq -e '((has("week") or has("month") or has("biweek") or has("allTime") or has("yesterdayFull") or has("weekSeries") or has("biweekSeries") or has("monthSeries") or has("allTimeSeries") or has("statsYesterday") or has("statsWeek") or has("statsBiweek") or has("statsMonth") or has("statsAll") or has("yesterdayOrders")) | not)' >/dev/null \
  || fail "live output must not include historical fields"
printf '%s' "$live_out" | jq -e '.stats.tableData.rows | length >= 1' >/dev/null \
  || fail "live stats missing rows"
printf '%s' "$live_out" | jq -e '.stats.tableData.rows[0].sessions != null' >/dev/null \
  || fail "live stats missing sessions"
printf '%s' "$live_out" | jq -e '.todayOrders | has("edges")' >/dev/null \
  || fail "live todayOrders missing edges"

# historical emits ONLY completed-period fields; no todayOrders/stats.
printf '%s' "$hist_out" | jq -e 'has("currency") and has("week") and has("month") and has("biweek") and has("allTime") and has("yesterdayFull") and has("yesterdayOrders") and has("weekSeries") and has("biweekSeries") and has("monthSeries") and has("allTimeSeries") and has("weekSessionsSeries") and has("biweekSessionsSeries") and has("monthSessionsSeries") and has("allTimeSessionsSeries") and has("statsYesterday") and has("statsWeek") and has("statsBiweek") and has("statsMonth") and has("statsAll")' >/dev/null \
  || fail "historical output missing expected top-level keys"
printf '%s' "$hist_out" | jq -e '((has("todayOrders") or has("stats")) | not)' >/dev/null \
  || fail "historical output must not include today's fields"
printf '%s' "$hist_out" | jq -e '(.statsWeek.tableData.rows | length >= 1) and (.statsAll.tableData.rows | length >= 1)' >/dev/null \
  || fail "historical range stats missing rows"
printf '%s' "$hist_out" | jq -e '(.statsWeek.tableData.rows[0].sessions != null) and (.statsAll.tableData.rows[0].sessions != null)' >/dev/null \
  || fail "historical range stats missing sessions"
printf '%s' "$hist_out" | jq -e '.weekSeries.tableData.rows | length == 7' >/dev/null \
  || fail "historical weekSeries missing 7 rows"
printf '%s' "$hist_out" | jq -e '.allTimeSeries.tableData.columns[0].name == "month"' >/dev/null \
  || fail "historical allTimeSeries not bucketed by month"
printf '%s' "$hist_out" | jq -e '.weekSessionsSeries.tableData.columns[0].name == "day"' >/dev/null \
  || fail "historical weekSessionsSeries not bucketed by day"
printf '%s' "$hist_out" | jq -e '.allTimeSessionsSeries.tableData.columns[0].name == "month"' >/dev/null \
  || fail "historical allTimeSessionsSeries not bucketed by month"
printf '%s' "$hist_out" | jq -e '.yesterdayOrders | has("edges")' >/dev/null \
  || fail "historical yesterdayOrders missing edges"

printf 'PASS: sales.sh live emits today-only fields; historical emits completed-period fields\n'
