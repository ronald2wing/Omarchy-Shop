# Shop::Shopify: the CLI argv/spec builder, the toml guard, execute args, call/call_all and the JSON body rule.

require_relative 'support'

S = Shop::Shopify

with_home do |home|
  use_home(home)
  located = Shop::Runtime.locate

  assert_eq(S.argv(located, 'theme', 'list'), [located.node, located.run_js, 'theme', 'list'], 'argv = [pinned node, run.js, *args]')
  assert_eq(S.execute_args('alpha.myshopify.com', 'query X { shop { name } }'),
            ['store', 'execute', '--store=alpha.myshopify.com', '--no-input', '--json', '--version=2026-10', '--query=query X { shop { name } }'],
            'execute argv pins the API version and never --allow-mutations')
  assert_eq(S.execute_args('a.myshopify.com', 'q', { 'f' => 1 }).last, '--variables={"f":1}', 'variables go in --variables')

  # spec: the node link is made right before a spawn; theme specs are marked.
  link = File.join(home.state_dir, 'bin', 'node')
  assert(!File.symlink?(link), 'locate alone writes no link')
  spec = S.spec(located, %w[theme list --store=a.myshopify.com], interactive: false, deadline: 5, max_stdout: 100)
  assert_eq(File.readlink(link), located.node, 'spec points bin/node at the pinned node')
  assert_eq([spec[:cli], spec[:env]['CI'], spec[:argv].first(2)], [true, '1', [located.node, located.run_js]], 'a CLI spec')
  assert_eq(S.spec(located, %w[store list], interactive: true, deadline: 5, max_stdout: 100)[:env].key?('CI'), false, 'interactive spec: no CI')

  # The toml guard refuses a theme command whose --path (or the cwd) chain holds a shopify.theme.toml.
  folder = home.theme_folder
  File.write(home.path('work', 'shopify.theme.toml'), '')
  assert_eq(failure_code { S.spec(located, ['theme', 'push', "--path=#{folder}"], interactive: false, deadline: 5, max_stdout: 1) },
            'unsafe_folder', 'toml above --path refused')
  assert(S.spec(located, %w[store list], interactive: false, deadline: 5, max_stdout: 1), 'non-theme commands are not guarded')
  File.unlink(home.path('work', 'shopify.theme.toml'))

  # call: a result body, or the classified failure.
  out = S.call(located, %w[version --no-input], deadline: 5, json: false)
  assert_eq(out.strip, Shop::CLI_PIN, 'json: false returns raw stdout')
  themes = S.call(located, %w[theme list --store=a.myshopify.com --json --no-input], deadline: 5)
  assert_eq(themes['themes'].size, 3, 'json results are parsed')
  assert_eq(failure_code { S.call(located, %w[theme list --store=a.myshopify.com --json --no-input], deadline: 5, max_stdout: 10) },
            'output_too_large', 'a call past its cap fails output_too_large')
  # The caps: JSON_CAP for a JSON call, TEXT_CAP for a text one.
  assert_eq([S::JSON_CAP, S::TEXT_CAP], [2 * Shop::MIB, 64 * Shop::KIB], 'the two CLI stdout caps')

  # run: the unclassified Command::Result; body! classifies it.
  child_result = S.run(located, %w[theme list --store=a.myshopify.com --json --no-input], deadline: 5, max_stdout: S::JSON_CAP)
  assert(child_result.is_a?(Shop::Command::Result) && child_result.exit_code.zero?, 'run returns the Command::Result')
  assert_eq(S.body!(child_result, theme: true)['themes'].size, 3, 'body! parses its stdout object')
  assert_eq(S.body!(child_result, json: false, theme: true), child_result.stdout, 'body! with json: false is the raw stdout')
  home.scenario!('throttled')
  assert_eq(failure_code { S.execute(located, 'a.myshopify.com', Shop::Queries::SHOP_NAME, deadline: 5) }, 'rate_limited', 'failures are classified')
  home.scenario!('bad-json')
  assert_eq(failure_code { S.execute(located, 'a.myshopify.com', Shop::Queries::SHOP_NAME, deadline: 5) }, 'bad_response', 'bad JSON')
  home.scenario!('ok')
  data, budget = S.execute(located, 'alpha.myshopify.com', Shop::Queries::SHOP_NAME, deadline: 5)
  assert_eq([data['shop']['name'], budget], ['Alpha Apparel', nil], 'execute returns [data, budget]')

  # call_all: results per call, in order, with the hook.
  seen = []
  rs = S.call_all(located, [%w[store auth list --json --no-input], %w[theme list --store=a.myshopify.com --json --no-input]],
                  concurrency: 2, overall: Shop::Deadline.new(10), deadline: 5, on_done: ->(i, r) { seen << [i, r.first] })
  assert_eq(rs.map(&:first), %i[ok ok], 'call_all results')
  assert_eq(seen.map(&:first).sort, [0, 1], 'on_done once per call')
  # Every slot is filled when the overall deadline expires: the running
  # call times out and the queued ones, which the supervisor never starts
  # (and never reports through on_done), are timeouts too, not nil.
  home.scenario!('hang')
  seen = []
  rs = S.call_all(located, Array.new(3) { %w[store auth list --json --no-input] }, concurrency: 1, overall: Shop::Deadline.new(0.3),
                  deadline: 5, max_stdout: 1000, on_done: ->(i, _r) { seen << i })
  assert_eq(rs.map { |kind, e| [kind, e.code] }, [[:error, 'timeout']] * 3, 'call_all: timed-out and never-started calls are [:error, timeout]')
  assert_eq(seen, [0], 'on_done fires only for the call that ran')
  assert(home.pids.none? { |p| alive?(p['pid']) }, 'the hung call was reaped')
  home.scenario!('ok')
end

# body!: a successful call's stdout must be one JSON object.
ok_run = ->(out) { cli_result(out) }
assert_eq(S.body!(ok_run.call('{"a":1}'), theme: false), { 'a' => 1 }, 'body!: the JSON object')
assert_eq(failure_code { S.body!(ok_run.call('[1]'), theme: false) }, 'bad_response', 'a JSON array is not a body object')
assert_eq(failure_code { S.body!(ok_run.call('{'), theme: false) }, 'bad_response', 'invalid JSON')
assert_eq(failure_code { S.body!(ok_run.call("#{'[' * 100}#{']' * 100}"), theme: false) }, 'bad_response', 'nesting past the cap')
