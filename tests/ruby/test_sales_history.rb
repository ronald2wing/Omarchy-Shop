# Shop::SalesHistory: the completed periods from the History tables (windows, previous windows, buckets, partial months, lifetime).

require_relative 'support'

SH = Shop::SalesHistory

history_body = fixture_json('history.json')
h = SH.derive(history_body['data'], '2026-11-07')
assert_eq(h.keys, %w[yesterday last7d last14d last30d last12m lifetime], 'history period ids')
y = h['yesterday']
assert_eq([y['sales'], y['orders']], [69.0, 3], 'yesterday from the daily series')
assert_eq([y['previous']['sales'], y['previous']['orders']], [68.0, 2], 'yesterday previous is the day before')
assert_eq(y['traffic'], { 'sessions' => 159, 'cartAdds' => 10, 'reachedCheckout' => 4, 'completed' => 2 }, 'yesterday traffic')
assert(!y.key?('buckets'), 'yesterday has no buckets')
w = h['last7d']
assert_eq([w['sales'], w['orders'], w['traffic']['sessions']], [462.0, 15, 1092], 'last 7 complete days')
assert_eq(w['previous']['sales'], 413.0, 'previous 7 days')
assert_eq(w['buckets'].size, 7, '7 buckets')
assert_eq(w['buckets'].last, { 'date' => '2026-11-06', 'sales' => 69.0, 'sessions' => 159 }, 'buckets end yesterday; today dropped')
assert_eq(w['buckets'].first['date'], '2026-10-31', 'buckets start 7 days back')
assert_eq(h['last14d']['buckets'].size, 14, '14 buckets')
m = h['last30d']
assert_eq([m['sales'], m['previous']['sales']], [1635.0, 735.0], '30 days and the previous 30 from the 60-day series')
assert_eq(m['previous']['traffic']['sessions'], (100..129).sum, 'previous 30-day traffic')
yr = h['last12m']
assert_eq([yr['sales'], yr['orders'], yr.key?('previous')], [9100.0, 91, false], 'last 12 months: sums, no previous')
assert_eq(yr['buckets'].size, 13, 'monthly buckets')
assert_eq(yr['buckets'].first.slice('month', 'partial'), { 'month' => '2025-11', 'partial' => true }, 'first month partial')
assert_eq(yr['buckets'][1]['partial'], false, 'middle months complete')
assert_eq(yr['buckets'].last['partial'], true, "yesterday's month partial")
# Partial months follow the window's dates: on the 1st both end months are
# whole; on 2028-03-01 the window starts 2027-03-02 (first partial) and
# ends on 2028-02-29 (February whole).
month_rows = lambda do |from, count|
  d = Date.iso8601(from)
  Array.new(count) { |i| { 'month' => (d >> i).strftime('%Y-%m-01'), 'total_sales' => '10.00', 'orders' => '1' } }
end
partials = ->(rows, today) { SH.last12m(rows, [], Date.iso8601(today))['buckets'].select { |b| b['partial'] }.map { |b| b['month'] } }
assert_eq(partials.call(month_rows.call('2025-12-01', 12), '2026-12-01'), [], 'on the 1st no month is partial')
assert_eq(partials.call(month_rows.call('2025-12-01', 13), '2026-12-02'), %w[2025-12 2026-12], 'on the 2nd both end months are partial')
assert_eq(partials.call(month_rows.call('2027-03-01', 12), '2028-03-01'), %w[2027-03], 'leap year: first partial, February whole')
assert_eq(partials.call(month_rows.call('2026-01-01', 12), '2026-12-02'), %w[2026-12], 'a missing leading month never takes the flag')
assert_eq(h['lifetime'], { 'sales' => 15425.37, 'orders' => 444 }, 'lifetime')

# Missing days are zeros, not errors.
sparse = JSON.parse(JSON.generate(history_body['data']))
sparse['salesDaily']['tableData']['rows'].reject! { |r| r['day'] == '2026-11-06' }
assert_eq(SH.derive(sparse, '2026-11-07')['yesterday']['sales'], 0.0, 'a missing day is zero')

# Positional rows still map by column order.
positional = JSON.parse(JSON.generate(history_body['data']))
t = positional['lifetime']['tableData']
t['rows'] = t['rows'].map { |r| [r['total_sales'], r['orders']] }
assert_eq(SH.derive(positional, '2026-11-07')['lifetime'], { 'sales' => 15425.37, 'orders' => 444 }, 'positional rows')

# parseErrors on a history table is bad_response naming the field.
broken = JSON.parse(JSON.generate(history_body['data']))
broken['sessionsDaily'] = { 'tableData' => nil, 'parseErrors' => ['Column Not Found'] }
begin
  SH.derive(broken, '2026-11-07')
  assert(false, 'parse errors must fail')
rescue Shop::Failure => e
  assert(e.code == 'bad_response' && e.message.include?('sessionsDaily'), "names the field: #{e.message}")
end
assert(bad_response? { SH.derive({ 'salesDaily' => 'nope' }, '2026-11-07') }, 'a non-object field')
bad_day = JSON.parse(JSON.generate(history_body['data']))
bad_day['salesDaily']['tableData']['rows'][0]['day'] = 'yesterday'
assert(bad_response? { SH.derive(bad_day, '2026-11-07') }, 'a day that is not a date')
