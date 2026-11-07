# Shop::Queries: named constants, no customer fields, no mutations, no count precision (frozen and no-interpolation: test_source_contracts.rb section 4).

require_relative 'support'

Q = Shop::Queries
source = File.read(File.join(ROOT, 'lib', 'shop', 'queries.rb'))
all = Q.constants.sort.to_h { |c| [Q.const_get(c)[/\Aquery (\w+)/, 1], Q.const_get(c)] }
assert_eq(all.keys.sort, %w[History OrdersPage ShopMeta ShopName Today TodayTraffic Yesterday], 'the seven queries')
assert_eq(Q.constants.sort, %i[HISTORY ORDERS_PAGE SHOP_META SHOP_NAME TODAY TODAY_WITH_TRAFFIC YESTERDAY], 'Queries holds only queries')
all.each do |name, text|
  assert(text.start_with?("query #{name}"), "#{name} is a named query")
  assert(!text.match?(/customer|email|phone|address|mutation/i), "#{name} fetches no customer data and mutates nothing")
end
assert_eq([Q::TODAY, Q::TODAY_WITH_TRAFFIC, Q::HISTORY], [all['Today'], all['TodayTraffic'], all['History']], 'constants match the names')
assert(Q::TODAY_WITH_TRAFFIC.include?('DURING today'), 'today traffic is today')
assert(Q::TODAY_WITH_TRAFFIC.include?('TIMESERIES hour DURING today ORDER BY hour ASC'), 'hourly sessions so far today, for the chart')
assert(!Q::TODAY.include?('traffic') && !Q::TODAY.include?('shopifyqlQuery'), 'the plain today query has no ShopifyQL')
assert([Q::TODAY, Q::TODAY_WITH_TRAFFIC, Q::ORDERS_PAGE, Q::YESTERDAY].all? { |q| q.include?('nodes { createdAt totalPriceSet') },
       'every order page carries createdAt: the hourly charts bin by it')
assert(Q::HISTORY.scan('shopifyqlQuery').size == 5, 'five ShopifyQL queries for the history')
assert(Q::YESTERDAY.include?('salesHourly: shopifyqlQuery(query: "FROM sales SHOW total_sales TIMESERIES hour DURING yesterday'),
       "yesterday's chart reads the history's measure (total_sales) per hour")
assert(Q::HISTORY.include?('FROM sessions SHOW sessions, sessions_with_cart_additions, sessions_that_reached_checkout, sessions_that_completed_checkout TIMESERIES day SINCE -60d UNTIL -0d'), 'sessionsDaily spans 60 days')
# Every history figure past the day windows ends yesterday: no frozen
# slice of today in 12m or Lifetime.
# A relative `UNTIL -Nd` is exclusive (-1d stops at the start of
# yesterday, dropping the day the Yesterday headline shows): the named
# `UNTIL yesterday` includes it.
assert_eq(Q::HISTORY.scan(/TIMESERIES month SINCE -365d UNTIL yesterday ORDER BY month ASC/).size, 2, 'salesMonthly and sessionsMonthly end with yesterday')
assert(Q::HISTORY.include?('lifetime: shopifyqlQuery(query: "FROM sales SHOW total_sales, orders SINCE 2006-01-01 UNTIL yesterday")'), 'lifetime ends with yesterday')
assert(!Q::HISTORY.match?(/UNTIL -[1-9]\d*d/), 'no exclusive relative UNTIL -Nd in the history')
assert(!Q::HISTORY.match?(/TIMESERIES month[^"]*UNTIL -0d/), 'no monthly query includes today')
# The heredocs cannot interpolate, so the sessions column list is written
# out per query: every copy must be the same list.
sessions_columns = 'sessions, sessions_with_cart_additions, sessions_that_reached_checkout, sessions_that_completed_checkout'
shows = source.scan(/FROM sessions SHOW (.*?) (?:TIMESERIES|DURING|SINCE)/).flatten
assert(shows.size >= 4, "found the FROM sessions clauses (#{shows.size})")
shows.each { |cols| assert_eq(cols, sessions_columns, 'every FROM sessions SHOW lists the same columns') }
assert(Q::YESTERDAY.include?('TIMESERIES hour DURING yesterday'), 'hourly yesterday traffic')
assert(Q::ORDERS_PAGE.include?('$after: String!'), 'cursors are variables')
assert([Q::TODAY, Q::TODAY_WITH_TRAFFIC, Q::ORDERS_PAGE, Q::YESTERDAY].all? { |q| q.include?('$filter: String!') && !q.match?(/\$(?!filter\b|after\b)\w/) },
       'every orders query takes the one $filter variable (and $after for a page)')
assert([Q::TODAY, Q::TODAY_WITH_TRAFFIC].all? { |q| q.include?('ordersCount(query: $filter, limit: null) { count }') && !q.include?('precision') },
       'ordersCount asks for the exact count only (no precision field)')
assert([Q::TODAY, Q::TODAY_WITH_TRAFFIC, Q::ORDERS_PAGE, Q::YESTERDAY].all? { |q| q.include?('first: 250') }, 'pages of 250')
assert_eq(Shop::SCOPES, 'read_reports,read_orders', 'scopes: no customer access')
