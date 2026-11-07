# helpers/sign-out: one `auth logout --no-input` under CI; sales access is untouched.

require_relative 'support'

with_home do |home|
  status, out, = run_one('sign-out', home: home)
  assert_eq([status, out], [0, { 'ok' => true }], 'sign-out')
  assert_eq(home.cli_log.map { |e| e['argv'] }, [%w[auth logout --no-input]], 'exactly one call: logout argv')
  assert_eq(home.cli_log.last['env']['CI'], '1', 'logout runs under CI')
  assert(home.cli_log.none? { |e| e['argv'][0, 2] == %w[store auth] }, 'store auth is never touched')

  # Already signed out: the CLI's logout still succeeds; so does the helper.
  home.scenario!('logged-out')
  status, out, = run_one('sign-out', home: home)
  assert_eq([status, out], [0, { 'ok' => true }], 'sign-out while signed out')

  home.scenario!('hang')
  status, out, = run_one('sign-out', home: home, overrides: { deadlines: { call: 0.5 } })
  assert_eq([status, out['error']['code']], [124, 'timeout'], 'a hung logout -> 124')
  home.scenario!('ok')
  status, out, = run_one('sign-out', '--store=alpha', home: home)
  assert_eq([status, out['error']['code']], [1, 'invalid_argument'], 'no flags accepted')
end

with_home(cli: false) do |home|
  status, out, = run_one('sign-out', home: home)
  assert_eq([status, out['error']['code'], out['error']['missing']], [1, 'cli_missing', 'cli'], 'no CLI -> cli_missing')
end
