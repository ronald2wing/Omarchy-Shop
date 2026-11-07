# Shop::Account: the session probe over `store list --json` (signed_in, multi_org, signed_out, unknown; strict), status_of and the account object.

require_relative 'support'

A = Shop::Account

with_home do |home|
  use_home(home)
  located = Shop::Runtime.locate

  # probe: [status, error].
  assert_eq(A.probe(located, deadline: 5), ['signed_in', nil], 'signed in')
  home.scenario!('multi-org')
  assert_eq(A.probe(located, deadline: 5), ['multi_org', nil], 'multi org')
  %w[logged-out logged-out-ci session-expired session-cleared].each do |sc|
    home.scenario!(sc)
    assert_eq(A.probe(located, deadline: 5), ['signed_out', nil], "#{sc} -> signed_out")
  end
  home.scenario!('store-list-notice')
  status, err = A.probe(located, deadline: 5)
  assert_eq([status, err.code], %w[unknown cli_failed], 'an empty store list with a notice is unknown, with the notice')
  assert_eq(failure_code { A.probe(located, deadline: 5, strict: true) }, 'cli_failed', 'strict: the notice raises')
  home.scenario!('network-down')
  status, err = A.probe(located, deadline: 5)
  assert_eq([status, err.code], %w[unknown cli_failed], 'network down -> unknown')
  assert_eq(failure_code { A.probe(located, deadline: 5, strict: true) }, 'cli_failed', 'strict: network down raises')
  home.scenario!('hang')
  status, err = A.probe(located, deadline: 0.3)
  assert_eq([status, err.code], %w[unknown timeout], 'a timeout is unknown, with the timeout')
  assert_eq(failure_code { A.probe(located, deadline: 0.3, strict: true) }, 'timeout', 'strict: a timeout raises')
  assert_eq(A.object('multi_org'), { 'status' => 'signed_in', 'error' => nil }, 'account object for multi_org')
  assert_eq(A.object('unknown', Shop::Failure.new('cli_failed', 'x'))['error'], { 'code' => 'cli_failed', 'message' => 'x' }, 'account object carries the error')
  assert_eq(A.status_of(Shop::Failure.new('rate_limited', 'x')), 'unknown', 'a failure that is no session answer is unknown')
  assert_eq(A.status_of({ 'stores' => [] }), 'signed_in', 'an empty list without a notice is signed in')
end

assert_eq(A.status_of({}), 'unknown', 'status_of never raises: a body with no listing is unknown')
assert_eq([A.public_status('multi_org'), A.public_status('signed_out')], %w[signed_in signed_out], 'public_status folds multi_org into signed_in')
assert_eq(A.unknown_error({}).code, 'bad_response', 'the error behind a body with no listing is bad_response')
