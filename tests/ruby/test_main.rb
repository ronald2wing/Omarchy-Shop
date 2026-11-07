# Shop::HelperMain: the env scrub, UTF-8 argv through main, the emitter's cap and the exit-code contract.

require_relative 'support'

HM = Shop::HelperMain

# Run HelperMain.main in a fresh interpreter with `body` as the block (it
# sees `o`, the options, and `overall`) and `main_opts` as main's keywords
# (Ruby source; default `values: ['x']`): [exit status, stdout lines].
def run_main(body, helper: "'prepare-state'", argv: [], env: {}, main_opts: "values: ['x']")
  script = <<~RUBY
    require #{File.join(ROOT, 'lib', 'shop').inspect}
    Shop::HelperMain.main(ARGV, {}, helper: #{helper}, usage: 'usage', prepare: false, #{main_opts}) { |o, overall| #{body} }
  RUBY
  out, err, status = Open3.capture3({ 'PATH' => '/usr/bin:/bin' }.merge(env), RUBY, '--disable-gems', '-e', script, '--', *argv, unsetenv_others: true)
  raise "FAIL: main printed nothing (stderr: #{err})" if out.empty?

  [status.exitstatus, out.lines.map { |l| JSON.parse(l) }]
end

# The scrub is the first statement of main, and it works in-process.
src = File.read(File.join(ROOT, 'lib', 'shop', 'helper_main.rb'))
body = src[/def main\(.*?\n(.*?)\n\s*rescue Failure/m, 1]
assert_eq(body.lines.map(&:strip).reject { |l| l.empty? || l.start_with?('#') }.first, 'scrub_interpreter_env!', 'scrub_interpreter_env! is the first statement of HelperMain.main')
status, lines = run_main("{ 'ok' => true, 'rubyopt' => ENV.key?('RUBYOPT'), 'bundle' => ENV.keys.grep(/\\ABUNDLE_/).size }",
                   env: { 'RUBYOPT' => '-W0', 'BUNDLE_GEMFILE' => '/x', 'GEM_HOME' => '/g' })
assert_eq([status, lines], [0, [{ 'ok' => true, 'rubyopt' => false, 'bundle' => 0 }]], 'main scrubs RUBYOPT, GEM_* and BUNDLE_* before the block')

status, lines = run_main("{ 'ok' => true, 'x' => 'y' }")
assert_eq([status, lines], [0, [{ 'ok' => true, 'x' => 'y' }]], 'a result under the cap exits 0')
status, lines = run_main("{ 'ok' => true, 'x' => 'y' * 2000 }", helper: "'notify-order'")
assert_eq(status, 1, 'an over-cap result exits 1 (output_too_large)')
assert_eq(lines.map { |l| [l['ok'], l.dig('error', 'code')] }, [[false, 'output_too_large']], 'and prints the output_too_large line')
# `line_fields:` ride on every line (a success's own value wins);
# set_line_fields! changes a declared one, never adds one.
LINE_FIELDS = "line_fields: { 'writeStarted' => false, 'backupId' => nil }"
def run_fields(body, helper: "'prepare-state'")
  status, lines = run_main(body, helper: helper, main_opts: LINE_FIELDS)
  [status, lines.last]
end
assert_eq(run_fields("{ 'ok' => true }"), [0, { 'writeStarted' => false, 'backupId' => nil, 'ok' => true }], 'line fields join a result')
assert_eq(run_fields("{ 'ok' => true, 'backupId' => '1-2' }")[1]['backupId'], '1-2', "a result's own value wins")
assert_eq(run_fields("Shop::HelperMain.set_line_fields!('writeStarted' => true, 'other' => 1); { 'ok' => true }")[1], { 'writeStarted' => true, 'backupId' => nil, 'ok' => true }, 'set_line_fields! sets a declared field only')
assert_eq(run_fields("raise Shop::Failure.new('timeout', 'slow')"), [124, { 'ok' => false, 'error' => { 'code' => 'timeout', 'message' => 'slow' }, 'writeStarted' => false, 'backupId' => nil }], 'line fields join a failure line')
assert_eq(run_fields("Shop::HelperMain.set_line_fields!('writeStarted' => true, 'backupId' => '1-2'); raise 'boom'")[1].slice('writeStarted', 'backupId'), { 'writeStarted' => true, 'backupId' => '1-2' }, 'and an internal error line')
status, line = run_fields("Shop::HelperMain.set_line_fields!('writeStarted' => true, 'backupId' => '1-2'); { 'ok' => true, 'x' => 'y' * 2000 }", helper: "'notify-order'")
assert_eq([status, line.dig('error', 'code'), line['writeStarted'], line['backupId']], [1, 'output_too_large', true, '1-2'], 'and the output_too_large line')
assert_eq(run_main("{ 'ok' => true }")[1], [{ 'ok' => true }], 'no line fields: no extra fields')

status, lines = run_main("raise Shop::Failure.new('store_busy', 'held')")
assert_eq([status, lines.first.dig('error', 'code')], [1, 'store_busy'], 'a Failure exits 1')
status, lines = run_main("raise Shop::Failure.new('cli_failed', 'x', details: ['a'])")
assert_eq(lines.first['details'], ['a'], 'details land on the failure line')
status, lines = run_main('raise ArgumentError, "boom"')
assert_eq([status, lines.first['error']], [1, { 'code' => 'internal_error', 'message' => 'unexpected ArgumentError: boom' }],
          'an unexpected exception is internal_error naming the class, exit 1')
status, lines = run_main("File.read('/nonexistent/x')")
assert_eq(lines.first['error']['message'], 'unexpected Errno::ENOENT: no such file or directory', 'an OS error is its reason, without the path noise')

# The overall deadline starts before the block, from the helper's row
# (H of prepare-state is 5 s), and caps every step through overall_cap.
status, lines = run_main("{ 'ok' => true, 'left' => overall.remaining, 'same' => overall.equal?(Shop::HelperMain.overall), 'cap' => Shop::HelperMain.overall_cap(60) }")
assert(status.zero? && lines.first['left'].between?(4, 5) && lines.first['same'] && lines.first['cap'] <= 5, "the block gets the overall deadline (#{lines})")
assert_eq(HM.overall_cap(7), 7, 'outside a helper overall_cap is the step itself')
# required: a value flag left out is a usage error.
status, lines = run_main("{ 'ok' => true }", main_opts: "values: %w[x y], required: %w[y]", argv: ['--x=1'])
assert_eq([status, lines.first['error']], [1, { 'code' => 'invalid_argument', 'message' => 'missing --y' }], 'required: a missing flag is invalid_argument')
# A lambda helper picks its row after the parse; a usage error it raises
# fails under the default cap, before any row applies.
status, lines = run_main("{ 'ok' => true, 'cap' => Shop::HelperMain.stdout_cap, 'left' => overall.remaining }",
                         helper: "->(opts) { opts['x'] == 'n' ? 'notify-order' : Shop::Validate.reject!('bad row') }", argv: ['--x=n'])
assert(status.zero? && lines.first['cap'] == Shop::TIMING['notify-order'][:cap] && lines.first['left'] <= 10, "a lambda names the row (#{lines})")
status, lines = run_main("{ 'ok' => true }", helper: "->(_) { Shop::Validate.reject!('bad row') }")
assert_eq([status, lines.first['error']['message']], [1, 'bad row'], 'the lambda can reject the argv')
# last_event: a streamer's failure line is its last event, without details.
status, lines = run_main("raise Shop::Failure.new('timeout', 'slow', details: ['d'])", main_opts: "last_event: 'exited'")
assert_eq([status, lines], [124, [{ 'event' => 'exited', 'ok' => false, 'error' => { 'code' => 'timeout', 'message' => 'slow' } }]], 'last_event shapes the failure line')

# argv is read as UTF-8 whatever the locale; invalid bytes are a usage error.
status, lines = run_main("{ 'ok' => true, 'x' => o['x'], 'enc' => o['x'].encoding.to_s }", argv: ['--x=thème'], env: { 'LANG' => 'C', 'LC_ALL' => 'C' })
assert_eq([status, lines.first.slice('x', 'enc')], [0, { 'x' => 'thème', 'enc' => 'UTF-8' }], 'a UTF-8 value under LANG=C is read as UTF-8')
status, lines = run_main("{ 'ok' => true }", argv: ["--x=caf\xFF".b])
assert_eq([status, lines.first['error']['code']], [1, 'invalid_argument'], 'invalid UTF-8 in argv -> invalid_argument')
assert(lines.first['error']['message'].include?('UTF-8'), 'and says so')

# emit: a closed reader never raises.
r, w = IO.pipe
r.close
saved = $stdout
$stdout = w
begin
  assert_eq(HM.emit({ 'ok' => true }), nil, 'EPIPE -> nil, no exception')
ensure
  $stdout = saved
  w.close
end

# emit: a string that is not valid UTF-8 (a realpath, a refused name) is
# scrubbed, never a JSON::GeneratorError that loses the result.
r, w = IO.pipe
saved = $stdout
$stdout = w
begin
  HM.emit({ 'ok' => true, 'folder' => "/w/raw\xFE".b, 'warnings' => [{ 'at' => "a\xFF".b, 'n' => 1 }], "k\xFF".b => 'v', 'name' => 'Café' })
ensure
  $stdout = saved
  w.close
end
line = r.read
r.close
out = JSON.parse(line)
assert_eq([out['ok'], out['folder'], out['warnings'], out['k?'], out['name']], [true, '/w/raw?', [{ 'at' => 'a?', 'n' => 1 }], 'v', 'Café'], "emit scrubs invalid UTF-8, keeps the rest: #{line}")
