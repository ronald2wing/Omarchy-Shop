# Shop::Sales: payload parsing (rows keyed by column name), strict numbers, exact sums, today's and yesterday's pieces.

require_relative 'support'

S = Shop::Sales

# Numbers: plain decimals only. Float() would take hex, underscores and
# exponents; a store cannot send those, so they are malformed.
assert(bad_response? { S.money('abc') } && bad_response? { S.money('NaN') } && bad_response? { S.count('x') }, 'non-numeric cells')
%w[0x1A 1_000 1e308 Infinity -Infinity 1. .5 +3].each do |s|
  assert(bad_response? { S.money(s) }, "money(#{s.inspect}) is malformed")
end
assert_eq([S.money('12.50'), S.money('-3'), S.money(7), S.money(2.5)], [12.5, -3.0, 7.0, 2.5], 'plain decimals and numbers')
assert_eq([S.count('3'), S.count('3.0'), S.count(4), S.count(4.6)], [3, 3, 4, 5], 'counts')
assert(bad_response? { S.count('3.5') } && bad_response? { S.count('1e3') } && bad_response? { S.count(Float::NAN) }, 'non-integral or non-finite counts')
node = ->(amount) { { 'totalPriceSet' => { 'shopMoney' => { 'amount' => amount } } } }
assert(bad_response? { S.sum_amounts([node.call('0x1A')]) }, 'hex amount in a page is malformed')
assert(bad_response? { S.sum_amounts([node.call('1_000')]) }, 'underscored amount is malformed')
assert(bad_response? { S.sum_amounts([node.call('1e308'), node.call('1e308')]) }, 'exponent amounts are malformed')
huge = '1' + '0' * 308
assert(bad_response? { S.sum_amounts([node.call(huge), node.call(huge)]) }, 'a sum past the float range is malformed, not Infinity')
assert_eq(S.sum_amounts([node.call('0.1'), node.call('0.2')]), 0.3, 'exact rational sums')
assert_eq(S.cents(Rational(4095, 1000)), 4.1, 'cents rounds half up at 2 places')
assert_eq([S.cents_of('4.095'), S.cents_of(3)], [4.1, 3.0], 'cents_of: a strict amount rounded to cents')
assert(bad_response? { S.cents_of('0x10') }, 'cents_of refuses what money refuses')

# Today pieces.
live = fixture_json('today.json')['data']
assert_eq(S.order_count(live), 3, 'ordersCount')
assert(bad_response? { S.order_count({ 'count' => {} }) }, 'missing count')
nodes, more, cursor = S.page(live)
assert_eq([nodes.size, more, cursor], [3, false, nil], 'page info')
assert_eq(S.sum_amounts(nodes), 60.01, 'exact cents: 35.81 + 20.10 + 4.095')
assert_eq(S.latest_order(live), { 'id' => 'gid://shopify/Order/1005', 'number' => '#1005', 'total' => 35.81,
                                  'itemCount' => 3, 'firstItem' => 'Tee' }, 'latest order')
assert(S.latest_order({ 'latest' => { 'nodes' => [] } }).nil?, 'no orders today -> null')
assert(bad_response? { S.latest_order({ 'latest' => { 'nodes' => [{ 'id' => 'gid://shopify/Customer/1' }] } }) }, 'non-order gid refused')
assert_eq(S.traffic_from(S.table(live, 'traffic').first), { 'sessions' => 1621, 'cartAdds' => 123, 'reachedCheckout' => 30, 'completed' => 8 }, 'traffic by column name')
assert(S.table({ 'traffic' => { 'tableData' => nil, 'parseErrors' => ['x'] } }, 'traffic', required: false).nil?, 'optional table with parse errors -> nil')
assert(bad_response? { S.page({ 'page' => { 'nodes' => [], 'pageInfo' => { 'hasNextPage' => true, 'endCursor' => 'a b' } } }) }, 'invalid cursor refused')
assert_eq(S.order_points(nodes), [[Time.utc(2026, 11, 7, 14, 30).to_i * 1000, 35.81], [Time.utc(2026, 11, 7, 9, 5).to_i * 1000, 20.1],
                                  [Time.utc(2026, 11, 7, 13, 59).to_i * 1000, 4.1]], 'order_points: [ms, cents] per node')
assert(bad_response? { S.order_points([node.call('1.00')]) }, 'a node without createdAt is malformed')
# Valid JSON of the wrong shape is malformed (bad_response), never a
# TypeError/NoMethodError: a string or number where an object belongs.
{
  'count is a string' => -> { S.order_count({ 'count' => 'x' }) },
  'count is an array' => -> { S.order_count({ 'count' => [1] }) },
  'latest is a string' => -> { S.latest_order({ 'latest' => 'x' }) },
  'latest.nodes is a string' => -> { S.latest_order({ 'latest' => { 'nodes' => 'x' } }) },
  'a page node is true' => -> { S.order_points([true]) },
  'a page node is 17' => -> { S.order_points([17]) },
  'a summed node is a string' => -> { S.sum_amounts(['x']) },
  'totalPriceSet is a string' => -> { S.order_points([{ 'createdAt' => '2026-11-07T14:30:00Z', 'totalPriceSet' => 'x' }]) },
  'totalPriceSet is 5' => -> { S.sum_amounts([{ 'totalPriceSet' => 5 }]) },
  'shopMoney is a string' => -> { S.sum_amounts([{ 'totalPriceSet' => { 'shopMoney' => 'x' } }]) },
  'createdAt is an object' => -> { S.order_points([{ 'createdAt' => {}, 'totalPriceSet' => { 'shopMoney' => { 'amount' => '1' } } }]) },
  'shop is a string' => -> { S.shop_meta({ 'shop' => 'x' }) },
  'page is a string' => -> { S.page({ 'page' => 'x' }) }
}.each do |label, call|
  got = begin
    call.call
    'no error'
  rescue Shop::Failure => e
    e.code
  rescue StandardError => e
    "#{e.class}: #{e.message}"
  end
  assert_eq(got, 'bad_response', label)
end
# A latest order whose lineItems is the wrong shape just has no first item.
odd = { 'id' => 'gid://shopify/Order/1', 'totalPriceSet' => { 'shopMoney' => { 'amount' => '1' } }, 'lineItems' => 'x' }
assert(S.latest_order({ 'latest' => { 'nodes' => [odd] } })['firstItem'].nil?, 'string lineItems -> no firstItem')
assert_eq(S.order_points(Array.new(10_050) { { 'createdAt' => '2026-11-07T14:30:00Z', 'totalPriceSet' => { 'shopMoney' => { 'amount' => '1' } } } }).size,
          S::MAX_ORDER_POINTS, 'capped at MAX_ORDER_POINTS')
Shop.override!(now: NOW)
tstart = Shop::StoreClock.boundaries('America/New_York')[:today_start]
today_hourly = S.traffic_hourly(live, tstart)
assert_eq([today_hourly.size, today_hourly.first['hour'], today_hourly.last['hour']], [11, 0, 10], 'today: one row per elapsed hour, 0 = today_start')
assert_eq(S.shop_meta(live), ['USD', 'America/New_York'], 'shop meta')
assert(bad_response? { S.shop_meta({ 'shop' => { 'currencyCode' => 'usd!' } }) }, 'bad currency refused')
assert_eq(S.shop_meta({ 'shop' => { 'currencyCode' => 'EUR', 'ianaTimezone' => '../../etc' } }), %w[EUR UTC], 'bad zone -> UTC')

ystart = Shop::StoreClock.boundaries('America/New_York')[:yesterday_start]
hourly = S.traffic_hourly(fixture_json('yesterday.json')['data'], ystart)
assert_eq(hourly.size, 24, '24 hours')
assert_eq(hourly.first, { 'hour' => 0, 'sessions' => 40, 'cartAdds' => 3, 'reachedCheckout' => 1, 'completed' => 0 }, 'hour 0 = startEpoch')
assert_eq(hourly.last['hour'], 23, 'hour 23 on a 24-hour day')
assert(S.traffic_hourly({ 'trafficHourly' => { 'tableData' => nil, 'parseErrors' => ['unsupported'] } }, ystart).nil?, 'unsupported hourly -> nil')

# Yesterday's hourly Analytics sales: total_sales per elapsed hour, negative
# for a return-only hour, nil when the series is unavailable.
sh = S.sales_hourly(fixture_json('yesterday.json')['data'], ystart)
assert_eq(sh.size, 24, 'sales: 24 hours')
assert_eq(sh[8], { 'hour' => 8, 'sales' => 10.0 }, 'sales hour 8')
assert_eq(sh[19], { 'hour' => 19, 'sales' => -5.0 }, 'return-only hour is negative')
assert(S.sales_hourly({}, ystart).nil?, 'missing salesHourly -> nil')
assert(S.sales_hourly({ 'salesHourly' => { 'tableData' => nil, 'parseErrors' => ['unsupported'] } }, ystart).nil?, 'unsupported sales hourly -> nil')
neg = { 'salesHourly' => { 'tableData' => { 'columns' => [{ 'name' => 'hour' }, { 'name' => 'total_sales' }],
                                             'rows' => [[(ystart + 3600).utc.iso8601, '-55']] }, 'parseErrors' => [] } }
assert_eq(S.sales_hourly(neg, ystart), [{ 'hour' => 1, 'sales' => -55.0 }], 'array rows, a refund hour')
assert(bad_response? { S.sales_hourly({ 'salesHourly' => { 'tableData' => { 'columns' => [{ 'name' => 'hour' }, { 'name' => 'total_sales' }], 'rows' => [['nope', '1']] }, 'parseErrors' => [] } }, ystart) },
       'bad hour refused')
assert(bad_response? { S.sales_hourly({ 'salesHourly' => { 'tableData' => { 'columns' => [{ 'name' => 'hour' }, { 'name' => 'total_sales' }], 'rows' => [[ystart.utc.iso8601, '1e3']] }, 'parseErrors' => [] } }, ystart) },
       'bad amount refused')

# DST: 2026-11-01 in America/New_York has 25 hours (01:00 twice). `hour` is
# hours since startEpoch, so every row keeps its own index (0..24) and no
# wall-clock hour repeats.
Shop.override!(now: Time.utc(2026, 11, 2, 12).to_i)
dst = Shop::StoreClock.boundaries('America/New_York')
assert_eq(dst[:yesterday_start], Time.utc(2026, 11, 1, 4), 'fall-back day starts at 04:00Z (EDT midnight)')
rows = (0..25).map do |i|
  { 'hour' => (dst[:yesterday_start] + (i * 3600)).utc.strftime('%Y-%m-%dT%H:%M:%SZ'), 'sessions' => (i + 1).to_s,
    'sessions_with_cart_additions' => '0', 'sessions_that_reached_checkout' => '0', 'sessions_that_completed_checkout' => '0' }
end
table = { 'trafficHourly' => { 'tableData' => { 'columns' => %w[hour sessions sessions_with_cart_additions sessions_that_reached_checkout sessions_that_completed_checkout].map { |n| { 'name' => n } },
                                                'rows' => rows }, 'parseErrors' => [] } }
dh = S.traffic_hourly(table, dst[:yesterday_start])
assert_eq(dh.map { |x| x['hour'] }, (0..24).to_a, 'fall-back day: elapsed indexes 0..24, the row past 25 h dropped')
assert_eq(dh[2]['sessions'], 3, 'the repeated 01:00 wall hour is its own index (2)')

# today / yesterday: the result objects, built from the first page and
# every order fetched.
tstart_today = Shop::StoreClock.boundaries('America/New_York')[:today_start]
t = S.today(live, nodes, tstart_today, with_traffic: true)
assert_eq(t.keys, %w[sales orders latestOrder traffic startEpoch orderPoints trafficHourly], 'today keys')
assert_eq([t['sales'], t['orders'], t['startEpoch'], t['orderPoints'].size, t['traffic']['sessions']], [60.01, 3, tstart_today.to_i, 3, 1621],
          'today: the sum of every node, the exact count, the day start, one point per order, the funnel')
plain = S.today(live, nodes, tstart_today, with_traffic: false)
assert(plain['traffic'].nil? && plain['trafficHourly'].nil?, 'today without traffic has neither')
ydata = fixture_json('yesterday.json')['data']
y = S.yesterday(ydata, [], date: '2026-11-06', start: ystart, stop: ystart + 86_400)
assert_eq(y.keys, %w[date startEpoch endEpoch orderPoints salesHourly trafficHourly], 'yesterday keys')
assert_eq(y.slice('date', 'startEpoch', 'endEpoch', 'orderPoints'),
          { 'date' => '2026-11-06', 'startEpoch' => ystart.to_i, 'endEpoch' => ystart.to_i + 86_400, 'orderPoints' => [] }, 'yesterday: the day and its points')
assert_eq([y['salesHourly'], y['trafficHourly']], [S.sales_hourly(ydata, ystart), S.traffic_hourly(ydata, ystart)], 'and its hourly series')

# The page cap comes from the timing table, and every paged row states the same one.
paged = Shop::TIMING.values.filter_map { |row| row[:pages] }
assert(paged.size >= 2 && paged.uniq == [S::MAX_PAGES], "every paged TIMING row states Sales::MAX_PAGES (#{paged})")
