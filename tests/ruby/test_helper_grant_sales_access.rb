# helpers/grant-sales-access: interactive `store auth` with the minimal scopes, then a verify query; refusals are per store.

require_relative 'support'

with_home(scenario: 'store-not-authed') do |home|
  status, out, = run_one('grant-sales-access', '--store=Alpha.myshopify.com', home: home)
  assert_eq([status, out], [0, { 'ok' => true, 'name' => 'Alpha Apparel' }], 'access granted; name = the shop name')
  auth, verify = home.cli_log
  assert_eq(auth['argv'], ['store', 'auth', '--store=alpha.myshopify.com', "--scopes=#{Shop::SCOPES}"], 'store auth argv (no customer scope)')
  assert(auth['env']['CI'].nil?, 'store auth is interactive')
  assert(verify['argv'].include?('--no-input') && verify['env']['CI'] == '1', 'verify is non-interactive')
  assert(verify['argv'].include?("--version=#{Shop::API_VERSION}"), 'verify pins the API version')
  assert_eq(home.queries.map { |q| q['op'] }, ['ShopName'], 'the verify query asks for the shop name only')

  { 'scope-denied' => 'sales_access_required', 'store-auth-invalid' => 'sales_access_required',
    'no-refresh-token' => 'sales_access_required' }.each do |sc, code|
    home.scenario!(sc)
    status, out, = run_one('grant-sales-access', '--store=alpha', home: home)
    assert_eq([status, out['error']['code']], [1, code], "#{sc} -> #{code}")
  end
  # A failed store auth with an older session answering the shop-name
  # query: only a session holding both scopes (alpha) counts; omega's
  # read_orders-only session does not, so the auth error stands.
  home.scenario!('store-auth-fails')
  status, out, = run_one('grant-sales-access', '--store=omega', home: home)
  assert(status != 0 && out['ok'] == false, "failed auth + narrow old session is not access, got #{status} #{out}")
  status, out, = run_one('grant-sales-access', '--store=alpha', home: home)
  assert_eq([status, out['ok']], [0, true], 'failed auth but a session already holding both scopes still verifies')
  home.scenario!('store-auth-fails,auth-list-implied')
  status, out, = run_one('grant-sales-access', '--store=kappa', home: home)
  assert_eq([status, out['ok']], [0, true], 'failed auth but a session holding write_orders + read_reports (the CLI\'s merged grant) still verifies')
  status, out, = run_one('grant-sales-access', '--store=lambda', home: home)
  assert(status != 0 && out['ok'] == false, "failed auth + write_products session is not access, got #{status} #{out}")
  home.scenario!('ok')
  run_one('grant-sales-access', '--store=omega', home: home)
  assert_eq(home.cli_log.last['argv'][0, 2], %w[store execute], 'a successful auth makes no store auth list call')
  home.scenario!('paused')
  status, out, = run_one('grant-sales-access', '--store=alpha', home: home)
  assert_eq([status, out['error']['code']], [1, 'store_unavailable'], 'a paused store -> store_unavailable')
  home.scenario!('ok')
  status, out, = run_one('grant-sales-access', '--store=alpha.myshopify.com.evil.tld', home: home)
  assert(status == 1 && out['error']['code'] == 'invalid_argument', 'bad domain -> invalid_argument')
  status, = run_one('grant-sales-access', home: home)
  assert_eq(status, 1, 'missing --store -> exit 1')
  status, = run_one('grant-sales-access', '--store', '--help-me', home: home)
  assert_eq(status, 1, 'unknown value-looking flag')
  status, out, = run_one('grant-sales-access', '--store=alpha', home: home, overrides: { deadlines: { helper: 0.5 } })
  assert(status.zero? || out['error']['code'] == 'timeout', 'the helper budget bounds the run')
end

with_home(scenario: 'hang') do |home|
  status, out, = run_one('grant-sales-access', '--store=alpha', home: home, overrides: { deadlines: { helper: 1.0, call: 0.5 } })
  assert_eq([status, out['error']['code']], [124, 'timeout'], 'a hung store auth -> 124')
  assert(home.pids.none? { |p| alive?(p['pid']) }, 'the hung CLI was reaped')
end
