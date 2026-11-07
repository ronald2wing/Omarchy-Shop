# helpers/discover-stores: JSON lines (partial, account, done), multi-org fan-out, failed orgs, names, truncation, errors.

require_relative 'support'

def events(lines) = lines.map { |l| l['event'] }

with_home do |home|
  status, lines, = run_helper('discover-stores', home: home)
  assert_eq(status, 0, 'exit 0')
  assert_eq(events(lines), %w[partial account done], 'event order')
  assert_eq(lines[0]['stores'], [{ 'domain' => 'alpha.myshopify.com' }, { 'domain' => 'beta.myshopify.com' }],
            'partial = the store-auth session domains')
  assert_eq(lines[1], { 'event' => 'account', 'status' => 'signed_in' }, 'account line')
  done = lines[2]
  assert_eq(done.keys, %w[event ok stores truncated], 'done keys (the account line carries the account)')
  assert_eq(done['stores'], [
    { 'domain' => 'alpha.myshopify.com', 'name' => 'Alpha Apparel' },
    { 'domain' => 'beta.myshopify.com', 'name' => 'Beta Goods' },
    { 'domain' => 'gamma.myshopify.com', 'name' => 'Gamma 10' }
  ], 'merged stores: {domain, name} rows')
  assert_eq([done['ok'], done['truncated']], [true, false], 'done ok')
  assert_eq(home.queries.map { |q| [q['op'], q['store']] }, [['ShopName', 'beta.myshopify.com']], 'names looked up only for unnamed authorized stores')
  assert(home.cli_log.all? { |e| e['argv'].include?('--no-input') && e['env']['CI'] == '1' }, 'every call is non-interactive')
end

with_home(scenario: 'multi-org,org-fails:200') do |home|
  status, lines, = run_helper('discover-stores', home: home)
  assert_eq(status, 0, 'multi-org exit 0')
  assert_eq(lines[1]['status'], 'signed_in', 'multi-org account')
  org_calls = home.cli_log.map { |e| e['argv'] }.select { |a| a.any? { |x| x.start_with?('--organization-id=') } }
  assert_eq(org_calls.map { |a| a.find { |x| x.start_with?('--organization-id=') } }.sort, %w[--organization-id=100 --organization-id=200],
            'orgs with shopCount 0 are skipped')
  assert_eq(lines.last['stores'].map { |s| s['domain'] }, %w[alpha.myshopify.com beta.myshopify.com gamma.myshopify.com],
            'a failed org contributes nothing')
end

with_home(scenario: 'multi-org') do |home|
  lines = run_helper('discover-stores', home: home)[1]
  assert_eq(lines.last['stores'].map { |s| s['name'] }, ['Alpha Apparel', 'Beta Goods', 'Gamma 9', 'Gamma 10'], 'all orgs merged, natural order')
end

# An organization listing that times out is missing from the merged list:
# the done line says the list is cut, and the other organizations' stores
# are still there.
with_home(scenario: 'multi-org,org-hangs:200') do |home|
  status, lines, = run_helper('discover-stores', home: home, overrides: { deadlines: { helper: 8.0, call: 0.5 } })
  assert_eq([status, lines.last['event'], lines.last['ok']], [0, 'done', true], 'a hung organization still ends in done')
  assert_eq(lines.last['truncated'], true, 'a timed-out organization listing marks the list truncated')
  assert_eq(lines.last['stores'].map { |s| s['domain'] }, %w[alpha.myshopify.com beta.myshopify.com gamma.myshopify.com],
            'the organizations that answered are merged')
  assert(home.pids.none? { |p| alive?(p['pid']) }, 'the hung listing was reaped')
end

%w[logged-out session-expired session-cleared].each do |sc|
  with_home(scenario: sc) do |home|
    lines = run_helper('discover-stores', home: home)[1]
    assert_eq(lines[1]['status'], 'signed_out', "#{sc} -> signed_out account")
    assert_eq(lines.last['stores'].map { |s| s['domain'] }, %w[alpha.myshopify.com beta.myshopify.com], "#{sc}: authorized stores still listed")
  end
end

# A store list cut by the CLI (a notice next to rows) marks done.truncated;
# an empty list with a notice says nothing about the account.
with_home(scenario: 'store-list-truncated') do |home|
  lines = run_helper('discover-stores', home: home)[1]
  assert_eq([lines.last['ok'], lines.last['truncated']], [true, true], 'a cut store list -> truncated')
  assert_eq(lines.last['stores'].size, 3, 'the rows it did return are merged')
end
with_home(scenario: 'store-list-notice') do |home|
  lines = run_helper('discover-stores', home: home)[1]
  assert_eq(lines[1], { 'event' => 'account', 'status' => 'unknown' }, 'notice + no stores -> unknown account')
  assert_eq([lines.last['truncated'], lines.last['stores'].map { |s| s['domain'] }], [false, %w[alpha.myshopify.com beta.myshopify.com]],
            'not truncated; authorized stores listed')
end
with_home(scenario: 'network-down') do |home|
  lines = run_helper('discover-stores', home: home)[1]
  assert_eq([lines[1]['status'], lines.last['ok']], ['unknown', true], 'network down -> unknown account, still a done line')
end

with_home(scenario: 'invalid-utf8') do |home|
  lines = run_helper('discover-stores', home: home)[1]
  beta = lines.last['stores'].find { |s| s['domain'] == 'beta.myshopify.com' }
  assert_eq(beta['name'], 'Caf? Shop', 'names scrubbed and stripped of ANSI/control characters')
end

with_home(cli: false) do |home|
  status, lines, = run_helper('discover-stores', home: home)
  assert_eq(status, 1, 'no CLI -> exit 1')
  assert_eq(lines, [{ 'event' => 'done', 'ok' => false,
                      'error' => { 'code' => 'cli_missing', 'message' => "Shopify CLI #{Shop::CLI_PIN} not found under mise's installs", 'missing' => 'cli' } }],
            'done failure line')
end

with_home(scenario: 'hang') do |home|
  t0 = Shop::Deadline.now
  status, lines, = run_helper('discover-stores', home: home, overrides: { deadlines: { helper: 1.0, call: 0.5 } })
  assert(Shop::Deadline.now - t0 < 6, 'hung calls are bounded by the deadlines')
  assert_eq([status, lines.last['event'], lines.last['ok']], [0, 'done', true], 'timeouts degrade to an empty done')
  assert(home.pids.none? { |p| alive?(p['pid']) }, 'every hung CLI was reaped')
end
