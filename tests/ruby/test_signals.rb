# Shop::Signals end to end: TERM/burst -> 143 + reaped group, SIGKILL -> pdeathsig, parent loss, EPIPE.

require_relative 'support'

def fake_pid(home)
  wait_until(10) { home.pids.any? } or raise 'FAIL: the fake CLI never started'
  home.pids.last['pid']
end

# TERM while a CLI call hangs: the group is reaped and the helper exits 143
# with one terminated line.
with_home(scenario: 'hang') do |home|
  stdin, stdout, stderr, thr = spawn_helper('check-account', home: home)
  stdin.close
  cli = fake_pid(home)
  assert(alive?(cli), 'the fake CLI is running')
  Process.kill(:TERM, thr.pid)
  status = thr.value
  lines = stdout.read.lines
  stderr.read
  assert_eq(status.exitstatus, 143, 'TERM -> exit 143')
  assert_eq(lines.size, 1, 'one line')
  assert_eq(JSON.parse(lines.first)['error']['code'], 'terminated', 'terminated code')
  assert(!alive?(cli), 'the CLI was reaped before the helper exited')
end

# A burst of 20 TERMs is still one clean exit.
with_home(scenario: 'hang-with-grandchild') do |home|
  stdin, stdout, stderr, thr = spawn_helper('check-account', home: home)
  stdin.close
  cli = fake_pid(home)
  child = home.pids.last['child']
  20.times { Process.kill(:TERM, thr.pid) rescue nil }
  status = thr.value
  lines = stdout.read.lines
  stderr.read
  assert_eq(status.exitstatus, 143, 'burst -> 143')
  assert_eq(lines.size, 1, 'burst -> one line')
  assert(!alive?(cli) && !alive?(child), 'leader and grandchild gone')
end

# SIGKILL of the helper: setpriv --pdeathsig KILL takes the CLI leader down.
with_home(scenario: 'hang') do |home|
  stdin, stdout, stderr, thr = spawn_helper('check-account', home: home)
  stdin.close
  cli = fake_pid(home)
  Process.kill(:KILL, thr.pid)
  thr.value
  stdout.read
  stderr.read
  assert(wait_until(1.0) { !alive?(cli) }, 'the CLI is gone within 1 s of the helper being SIGKILLed')
end

# Parent loss: the helper notices its ppid changed, reaps the CLI and exits 143.
with_home(scenario: 'hang') do |home|
  out_file = home.path('helper.out')
  ov = JSON.generate(default_overrides(home))
  script = "#{RUBY} --disable-gems #{LAUNCHER} check-account '#{ov}' > #{out_file} 2>/dev/null & echo $!; sleep 1.5"
  pid_line, = Open3.capture2(helper_env(home, {}), '/bin/sh', '-c', script, unsetenv_others: true)
  helper = pid_line.to_i
  cli = home.pids.last['pid']
  assert(wait_until(5) { !alive?(helper) }, 'the orphaned helper exits')
  assert(!alive?(cli), 'and took the CLI with it')
  line = JSON.parse(File.read(out_file).lines.last)
  assert_eq(line['error']['code'], 'terminated', 'parent loss -> terminated')
end

# EPIPE: the reader went away; the helper still reaps and exits with its code.
with_home(scenario: 'slow-ok') do |home|
  stdin, stdout, stderr, thr = spawn_helper('check-account', home: home)
  stdin.close
  stdout.close
  status = thr.value
  stderr.read
  assert_eq(status.exitstatus, 0, 'EPIPE on emit does not change the exit code')
  assert(home.cli_log.size == 1 && !alive?(home.cli_log.last['pid']), 'the CLI ran and was reaped')
end

src = File.read(File.join(ROOT, 'lib', 'shop', 'signals.rb'))
trap_body = src[/trap\(sig\) do(.*?)\n\s*end/m, 1]
assert(trap_body && trap_body.lines.map(&:strip).reject(&:empty?).size == 2, 'the trap body is two statements')
assert(trap_body && !trap_body.match?(/puts|synchronize|join|Process|raise|exit|warn|print/), 'the trap only records and writes the self-pipe')

# sleep: waits the time, and a signal ends it at once with `terminated`.
Shop::Signals.install!
t0 = Shop::Deadline.now
Shop::Signals.sleep(0.2)
assert((Shop::Deadline.now - t0).between?(0.18, 1.0), 'sleep waits its seconds')
Shop::Signals.sleep(-1)
pid = Process.pid
Process.spawn('/bin/sh', '-c', "sleep 0.2; kill -TERM #{pid}")
t0 = Shop::Deadline.now
assert_eq(failure_code { Shop::Signals.sleep(10) }, 'terminated', 'a TERM ends the sleep as terminated')
assert(Shop::Deadline.now - t0 < 2, 'at once, not after the whole wait')
Process.wait
