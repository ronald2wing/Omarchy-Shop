# helpers/fetch-sales: today/yesterday/history against canned CLI payloads; paging and budgets; errors; argv contract.

require_relative 'support'

OV = { now: NOW }.freeze
COMMON = %w[ok domain fetchedAt currency timezone localDate utcOffsetMinutes dayEndsAt truncated].freeze

with_home do |home|
  status, out, = run_one('fetch-sales', '--store=alpha', '--range=today', home: home, overrides: OV)
  assert_eq(status, 0, "today ok (#{out})")
  assert_eq(out.keys, COMMON + ['today'], 'today keys: the common fields and the range object')
  assert_eq(out.slice('domain', 'currency', 'timezone', 'localDate', 'utcOffsetMinutes', 'dayEndsAt', 'fetchedAt', 'truncated'),
            { 'domain' => 'alpha.myshopify.com', 'currency' => 'USD', 'timezone' => 'America/New_York',
              'localDate' => '2026-11-07', 'utcOffsetMinutes' => -300, 'dayEndsAt' => Time.utc(2026, 11, 8, 5).to_i * 1000,
              'fetchedAt' => NOW * 1000, 'truncated' => false }, 'common fields')
  assert_eq(out['today'].keys, %w[sales orders latestOrder traffic startEpoch orderPoints trafficHourly], 'today object keys (truncated is top-level only)')
  assert_eq(out['today'].slice('sales', 'orders', 'traffic', 'trafficHourly'), { 'sales' => 60.01, 'orders' => 3, 'traffic' => nil, 'trafficHourly' => nil }, 'today')
  assert_eq(out['today']['latestOrder']['number'], '#1005', 'latest order')
  # The hourly chart's input: the store day's window and one [ms, amount] per
  # order, in the CLI's order, amounts rounded to cents.
  assert_eq([out['today']['startEpoch'], out['dayEndsAt']], [Time.utc(2026, 11, 7, 5).to_i, Time.utc(2026, 11, 8, 5).to_i * 1000], 'today start in seconds, end in dayEndsAt')
  assert_eq(out['today']['orderPoints'], [[Time.utc(2026, 11, 7, 14, 30).to_i * 1000, 35.81], [Time.utc(2026, 11, 7, 9, 5).to_i * 1000, 20.1],
                                         [Time.utc(2026, 11, 7, 13, 59).to_i * 1000, 4.1]], 'orderPoints: [ms, amount] per order')
  assert_eq(home.queries.map { |q| q['op'] }, %w[ShopMeta Today], 'no --timezone: meta first, then Today')
  assert_eq(home.queries.last['vars'], { 'filter' => "created_at:>='2026-11-07T05:00:00Z' AND test:false" }, 'store-local today filter via --variables, test orders excluded')
  home.cli_log.each do |e|
    a = e['argv']
    assert(a.include?('--no-input') && a.include?('--json') && a.include?("--version=#{Shop::API_VERSION}") && a.include?('--store=alpha.myshopify.com'), "execute argv #{a}")
    assert(a.none? { |x| x.include?('allow-mutations') }, 'never --allow-mutations')
    assert(!a.find { |x| x.start_with?('--query=') }.include?('2026-'), 'no data inside the query text')
  end

  File.truncate(home.path('.fake-shopify', 'queries.jsonl'), 0)
  status, out, = run_one('fetch-sales', '--store=alpha', '--range=today', '--timezone=America/New_York', '--with-traffic', home: home, overrides: OV)
  assert_eq(home.queries.map { |q| q['op'] }, %w[TodayTraffic], 'with --timezone: one call')
  assert_eq(out['today']['traffic'], { 'sessions' => 1621, 'cartAdds' => 123, 'reachedCheckout' => 30, 'completed' => 8 }, 'traffic')
  assert_eq(out['today']['trafficHourly'].size, 11, 'hourly sessions so far today (one row per elapsed hour)')
  assert_eq(out['today']['trafficHourly'].first, { 'hour' => 0, 'sessions' => 100, 'cartAdds' => 8, 'reachedCheckout' => 2, 'completed' => 0 }, 'hour 0 = startEpoch')
  assert_eq(out['today']['trafficHourly'].last['hour'], 10, 'the current store hour (10:00) is the last row')

  File.truncate(home.path('.fake-shopify', 'queries.jsonl'), 0)
  status, out, = run_one('fetch-sales', '--store=alpha', '--range=today', '--timezone=Asia/Tokyo', home: home, overrides: OV)
  assert_eq(home.queries.map { |q| q['vars']['filter'] }, ["created_at:>='2026-11-07T15:00:00Z' AND test:false", "created_at:>='2026-11-07T05:00:00Z' AND test:false"],
            'a wrong --timezone is corrected with one re-query')
  assert_eq(out['timezone'], 'America/New_York', 'the shop zone wins')

  home.scenario!('hourly-unsupported')
  out = run_one('fetch-sales', '--store=alpha', '--range=today', '--timezone=America/New_York', '--with-traffic', home: home, overrides: OV)[1]
  assert(out['ok'] && out['today']['traffic'].nil? && out['today']['trafficHourly'].nil?, 'unsupported traffic -> null, not an error')

  home.scenario!('paginated')
  out = run_one('fetch-sales', '--store=alpha', '--range=today', '--timezone=America/New_York', home: home, overrides: OV)[1]
  assert_eq([out['today']['sales'], out['truncated']], [560.01, false], 'three pages summed')
  assert_eq(out['today']['orderPoints'].size, 503, 'every paged order is a chart point')
  assert(home.queries.last(2).all? { |q| q['op'] == 'OrdersPage' && q['vars']['filter'].start_with?('created_at') && q['vars']['filter'].end_with?(' AND test:false') }, 'pages 2..n use OrdersPage with the same filter (no test orders)')
  home.scenario!('paginated-endless')
  File.truncate(home.path('.fake-shopify', 'queries.jsonl'), 0)
  out = run_one('fetch-sales', '--store=alpha', '--range=today', '--timezone=America/New_York', home: home, overrides: OV.merge(deadlines: { helper: 60 }))[1]
  assert_eq(home.queries.size, Shop::Sales::MAX_PAGES, 'at most 40 pages')
  assert_eq(out['truncated'], true, 'truncated past 40 pages')

  # Slow pages (live CLI: 5-7 s each) stop at the helper budget with a partial
  # total, never a timeout that drops what was fetched.
  home.scenario!('paginated-endless,page-sleep:0.4')
  File.truncate(home.path('.fake-shopify', 'queries.jsonl'), 0)
  status, out, = run_one('fetch-sales', '--store=alpha', '--range=today', '--timezone=America/New_York', home: home,
                         overrides: OV.merge(deadlines: { helper: 3, page_reserve: 1 }))
  pages = home.queries.count { |q| q['op'] == 'OrdersPage' }
  assert_eq([status, out['ok'], out['truncated']], [0, true, true], "budget-limited paging is a truncated success (#{out})")
  assert(pages.between?(1, 6), "stopped early (#{pages} pages)")
  assert_eq(out['today']['sales'], (60.01 + 250 * pages).round(2), 'partial sum kept')
  assert_eq(out['today']['orders'], 3, 'count kept')
  # A later page that times out (per-call deadline) also ends as truncated.
  home.scenario!('paginated-endless,page-sleep:2')
  status, out, = run_one('fetch-sales', '--store=alpha', '--range=today', '--timezone=America/New_York', home: home,
                         overrides: OV.merge(deadlines: { call: 0.5, page_reserve: 0.1 }))
  assert_eq([status, out['ok'], out['truncated'], out['today']['sales']], [0, true, true, 60.01], "a timed-out page is truncated (#{out})")
  # A later page that is rate limited ends as truncated too: the first page is kept.
  home.scenario!('throttle-page-2')
  File.truncate(home.path('.fake-shopify', 'queries.jsonl'), 0)
  status, out, = run_one('fetch-sales', '--store=alpha', '--range=today', '--timezone=America/New_York', home: home, overrides: OV)
  assert_eq([status, out['ok'], out['truncated'], out['today']['sales'], out['today']['orders']], [0, true, true, 60.01, 3],
            "a throttled page 2 is a truncated success (#{out})")
  assert_eq(out.keys, COMMON + ['today'], 'throttled page 2: same keys as a full today')
  assert_eq(home.queries.map { |q| q['op'] }, %w[Today OrdersPage], 'page 2 was attempted once')
  home.scenario!('paginated,page-sleep:0.4')
  status, out, = run_one('fetch-sales', '--store=alpha', '--range=yesterday', '--timezone=America/New_York', home: home,
                         overrides: OV.merge(deadlines: { helper: 1.5, page_reserve: 1.2 }))
  assert_eq([status, out['ok'], out['truncated']], [0, true, true], "yesterday paging stops at the budget too (#{out['truncated']}, #{out['yesterday']['orderPoints'].size} orders)")

  home.scenario!('ok')
  status, out, = run_one('fetch-sales', '--store=alpha', '--range=history', home: home, overrides: OV)
  assert_eq(status, 0, 'history ok')
  assert_eq(out.keys, COMMON + ['history'], 'history keys')
  assert_eq(out['history'].keys, %w[yesterday last7d last14d last30d last12m lifetime], 'history periods')
  assert_eq(out['history']['last7d']['sales'], 462.0, 'history derived')
  assert_eq(out['localDate'], '2026-11-07', 'history local date from the shop zone')
  assert_eq(home.queries.last['op'], 'History', 'the History query')
  home.scenario!('periods-parse-error')
  status, out, = run_one('fetch-sales', '--store=alpha', '--range=history', home: home, overrides: OV)
  assert(status == 1 && out['error']['code'] == 'bad_response' && out['error']['message'].include?('sessionsDaily'), 'history parse errors -> bad_response')

  home.scenario!('ok')
  status, out, = run_one('fetch-sales', '--store=alpha', '--range=yesterday', '--timezone=America/New_York', home: home, overrides: OV)
  assert_eq(status, 0, 'yesterday ok')
  assert_eq(out.keys, COMMON + ['yesterday'], 'yesterday keys')
  y = out['yesterday']
  assert_eq(y.slice('date', 'startEpoch', 'endEpoch'),
            { 'date' => '2026-11-06', 'startEpoch' => Time.utc(2026, 11, 6, 5).to_i, 'endEpoch' => Time.utc(2026, 11, 7, 5).to_i }, 'window')
  assert_eq(y.keys, %w[date startEpoch endEpoch orderPoints salesHourly trafficHourly], 'yesterday carries only the epoch-second window')
  assert_eq(y['orderPoints'], [[Time.utc(2026, 11, 6, 13).to_i * 1000, 10.0], [Time.utc(2026, 11, 6, 20, 15).to_i * 1000, 25.5]], '[ms, amount] pairs')
  assert_eq(y['trafficHourly'].size, 24, 'hourly traffic')
  # The chart's series is Analytics total_sales (the history's Yesterday
  # headline, 69.00 over 3 orders in history.json), not the order totals
  # (35.50): one hour is a return with no order, so it is negative.
  assert_eq(y['salesHourly'].size, 24, 'hourly Analytics sales')
  assert_eq(y['salesHourly'].sum { |h| h['sales'] }.round(2), 69.0, 'hourly sales add up to the daily total_sales')
  assert_eq(y['salesHourly'][19], { 'hour' => 19, 'sales' => -5.0 }, 'a return-only hour is negative')
  assert_eq(home.queries.last['vars'], { 'filter' => "created_at:>='2026-11-06T05:00:00Z' AND created_at:<'2026-11-07T05:00:00Z' AND test:false" }, 'yesterday filter (test orders excluded)')
  history_y = run_one('fetch-sales', '--store=alpha', '--range=history', home: home, overrides: OV)[1]['history']['yesterday']
  assert_eq([history_y['sales'], history_y['orders']], [69.0, 3], 'the headline the chart matches')
  home.scenario!('hourly-unsupported')
  assert(run_one('fetch-sales', '--store=alpha', '--range=yesterday', '--timezone=America/New_York', home: home, overrides: OV)[1]['yesterday']['trafficHourly'].nil?, 'hourly null')
  home.scenario!('sales-hourly-unsupported')
  status, out, = run_one('fetch-sales', '--store=alpha', '--range=yesterday', '--timezone=America/New_York', home: home, overrides: OV)
  assert(status.zero? && out['yesterday']['salesHourly'].nil? && out['yesterday']['orderPoints'].size == 2,
         'hourly sales unavailable -> null (no chart), the baseline orders stay')

  # Errors.
  { 'scope-denied' => [1, 'sales_access_required'], 'store-not-authed' => [1, 'sales_access_required'],
    'store-auth-invalid' => [1, 'sales_access_required'], 'token-refresh-failed' => [1, 'sales_access_required'],
    'no-refresh-token' => [1, 'sales_access_required'], 'logged-out-ci' => [1, 'signed_out'], 'session-cleared' => [1, 'signed_out'],
    'throttled' => [1, 'rate_limited'], 'paused' => [1, 'store_unavailable'], 'server-error' => [1, 'cli_failed'],
    'admin-401-execute' => [1, 'cli_failed'], 'bad-json' => [1, 'bad_response'], 'flood' => [1, 'output_too_large'] }.each do |scenario, (code, name)|
    home.scenario!(scenario)
    status, out, = run_one('fetch-sales', '--store=alpha', '--range=today', '--timezone=America/New_York', home: home, overrides: OV)
    assert_eq([status, out['error']['code']], [code, name], "#{scenario} -> #{name}")
  end
  # Valid JSON of the wrong shape is bad_response, never an internal
  # TypeError/NoMethodError reported as cli_failed.
  %w[count latest page shop node price].each do |field|
    home.scenario!("wrong-shape:#{field}")
    status, out, = run_one('fetch-sales', '--store=alpha', '--range=today', '--timezone=America/New_York', home: home, overrides: OV)
    assert_eq([status, out.dig('error', 'code')], [1, 'bad_response'], "wrong-shape:#{field} -> bad_response (#{out})")
    assert(!out.dig('error', 'message').to_s.include?('internal error'), "wrong-shape:#{field}: no internal error")
  end
  home.scenario!('throttled')
  out = run_one('fetch-sales', '--store=alpha', '--range=today', '--timezone=UTC', home: home, overrides: OV)[1]
  assert(out['error']['retryAfter'].is_a?(Integer) && out['error']['retryAfter'].positive?, 'rate_limited carries retryAfter')
  home.scenario!('server-error')
  out = run_one('fetch-sales', '--store=alpha', '--range=today', '--timezone=UTC', home: home, overrides: OV)[1]
  assert_eq(out['error']['retryAfter'], 60, 'a server error asks for a 60 s retry')
  home.scenario!('hang')
  status, out, = run_one('fetch-sales', '--store=alpha', '--range=today', '--timezone=UTC', home: home, overrides: OV.merge(deadlines: { call: 0.5 }))
  assert_eq([status, out['error']['code']], [124, 'timeout'], 'hang -> 124')

  home.scenario!('ok')
  before = home.cli_log.size
  [%w[--store=alpha --range=weekly], %w[--store=alpha --range=live], %w[--store=alpha --range=today --timezone=Mars/Base], %w[--range=today],
   %w[--store=x.evil --range=today], %w[--store=alpha --range=today --range=history], %w[--store=alpha --range=today --with-traffic=1],
   %w[--store=alpha --scope=today], %w[--store=alpha]].each do |args|
    status, out, = run_one('fetch-sales', *args, home: home, overrides: OV)
    assert_eq([status, out['error']['code']], [1, 'invalid_argument'], "usage error #{args}")
  end
  assert_eq(home.cli_log.size, before, 'no CLI call on a usage error')
end
