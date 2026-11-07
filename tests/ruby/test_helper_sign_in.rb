# helpers/sign-in: strict probe, logout before the interactive login, re-probe; nothing is logged out on a guess.

require_relative 'support'

with_home do |home|
  calls = ->(from) { home.cli_log.drop(from).map { |e| e['argv'][0, 2] } }

  # Signed out: probe, logout (CI), login (interactive), probe.
  home.scenario!('logged-out')
  status, out, = run_one('sign-in', home: home)
  assert_eq(status, 0, "sign-in ok (#{out})")
  assert_eq(out.keys, %w[ok cli account], 'the check-account shape')
  assert_eq(out['account'], { 'status' => 'signed_in', 'error' => nil }, 'sign-in flips the session')
  login = home.cli_log.find { |e| e['argv'][0, 2] == %w[auth login] }
  assert_eq(login['argv'], ['auth', 'login', '--alias=shop'], 'login argv: --alias=shop, no --no-input')
  assert(login['env']['CI'].nil? && login['env']['npm_config_dry_run'] == 'true', 'login is interactive but upgrade-blocked')
  assert_eq(calls.call(0), [%w[store list], %w[auth logout], %w[auth login], %w[store list]], 'probe, logout, login, probe')
  logout = home.cli_log.find { |e| e['argv'][0, 2] == %w[auth logout] }
  assert_eq([logout['argv'], logout['env']['CI']], [%w[auth logout --no-input], '1'], 'the logout runs under CI')

  # An expired session is still stored: without the logout, login would stop
  # at the account picker and the browser would never open.
  home.scenario!('logged-out,stale-session')
  status, out, = run_one('sign-in', home: home)
  assert(status.zero? && out['account']['status'] == 'signed_in', "sign-in recovers from an expired session (#{out})")

  # The probe's BusinessPlatform 401 and the "cleared session" abort are
  # signed_out too: log out and open the login flow.
  %w[session-expired session-cleared].each do |sc|
    home.scenario!("#{sc},stale-session")
    before = home.cli_log.size
    status, out, = run_one('sign-in', home: home)
    assert(status.zero? && out['account']['status'] == 'signed_in', "sign-in recovers from #{sc} (#{out})")
    assert_eq(calls.call(before), [%w[store list], %w[auth logout], %w[auth login], %w[store list]], "#{sc}: probe, logout, login, probe")
  end

  # Already signed in: nothing but the probe runs.
  home.scenario!('ok')
  before = home.cli_log.size
  status, out, = run_one('sign-in', home: home)
  assert(status.zero? && out['account']['status'] == 'signed_in', 'sign-in while signed in reports the session')
  assert_eq(calls.call(before), [%w[store list]], 'no logout or login when signed in')
  home.scenario!('multi-org')
  before = home.cli_log.size
  status, out, = run_one('sign-in', home: home)
  assert_eq([status, out['account']], [0, { 'status' => 'signed_in', 'error' => nil }], 'multi-org is signed in')
  assert_eq(calls.call(before), [%w[store list]], 'and runs only the probe')

  # An unknown probe (network down, an empty list with a notice) must never
  # log out a working session: the helper fails with that error.
  %w[network-down store-list-notice].each do |sc|
    home.scenario!(sc)
    before = home.cli_log.size
    status, out, = run_one('sign-in', home: home)
    assert_eq([status, out['ok'], out['error']['code']], [1, false, 'cli_failed'], "#{sc}: sign-in fails on an unknown probe (#{out})")
    assert_eq(calls.call(before), [%w[store list]], "#{sc}: no auth logout, no login")
  end

  home.scenario!('logged-out,login-fails')
  status, out, = run_one('sign-in', home: home)
  assert_eq([status, out['error']['code']], [1, 'signed_out'], 'still signed out -> signed_out')
  assert(out['error']['message'].include?('cancelled'), 'with the login error as the message')

  home.scenario!('logged-out,hang')
  status, out, = run_one('sign-in', home: home, overrides: { deadlines: { call: 0.5 } })
  assert_eq([status, out['error']['code']], [124, 'timeout'], 'a hung probe -> 124')
end

with_home(node: false) do |home|
  status, out, = run_one('sign-in', home: home)
  assert(status == 1 && out['error']['code'] == 'cli_missing' && out['error']['missing'] == 'node', 'sign-in without runtime -> cli_missing')
end
