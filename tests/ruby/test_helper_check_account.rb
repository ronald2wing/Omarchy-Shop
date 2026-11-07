# helpers/check-account: the runtime object and the account session (signed_in / signed_out / unknown) from the probe.

require_relative 'support'

with_home do |home|
  status, out, = run_one('check-account', home: home)
  assert_eq(status, 0, 'check-account exit 0')
  assert_eq(out.keys, %w[ok cli account], 'output keys')
  assert_eq(out['cli'].slice('found', 'missing', 'installs'), { 'found' => true, 'missing' => nil, 'installs' => home.installs }, 'cli found')
  assert_eq(out['account'], { 'status' => 'signed_in', 'error' => nil }, 'single-org signed in')
  call = home.cli_log.last
  assert_eq(call['argv'], %w[store list --json --no-input], 'probe argv')
  assert_eq(File.readlink(File.join(home.state_dir, 'bin', 'node')), File.join(home.installs, 'node', Shop::NODE_PIN, 'bin', 'node'), 'bin/node -> pinned node')

  account = ->(scenario) { home.scenario!(scenario); run_one('check-account', home: home)[1]['account'] }
  # An empty store list with a notice says nothing about the session.
  unknown = account.call('store-list-notice')
  assert_eq([unknown['status'], unknown['error']['code']], ['unknown', 'cli_failed'], 'notice + no stores -> unknown with the notice as error')
  assert(unknown['error']['message'].include?('No stores'), 'the notice text is the error message')
  home.scenario!('hang')
  status, out, = run_one('check-account', home: home, overrides: { deadlines: { call: 0.5 } })
  # A slow session probe is an unknown account, not a failed status: the
  # found CLI must stay found so Shop treats it as ready and sales start.
  assert_eq([status, out['ok'], out['cli']['found']], [0, true, true], 'a hung probe -> exit 0, cli still found')
  assert_eq([out['account']['status'], out['account']['error']['code']], %w[unknown timeout], 'a hung probe -> account unknown (timeout)')
  home.scenario!('ok')
  status, out, = run_one('check-account', '--store=x', home: home)
  assert_eq([status, out['error']['code']], [1, 'invalid_argument'], 'no flags accepted')
end

with_home(node: false) do |home|
  status, out, = run_one('check-account', home: home)
  assert_eq([status, out['cli']['found'], out['cli']['missing'], out['account']['status']], [0, false, 'node', 'unknown'], 'no node -> missing node, account unknown')
  assert_eq(home.cli_log, [], 'nothing ran')
end
