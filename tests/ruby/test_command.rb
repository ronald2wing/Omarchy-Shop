# Shop::Command and Shop::Child: setpriv prefix, pgroup, deadlines, TERM->KILL, grandchildren, caps, run_all.

require_relative 'support'

C = Shop::Command
ENV_MIN = { 'PATH' => '/usr/bin:/bin', 'LANG' => 'C.UTF-8' }.freeze

def run(argv, **kw)
  C.run(argv, env: ENV_MIN, deadline: kw.delete(:deadline) || 5, max_stdout: kw.delete(:max_stdout) || 65_536, **kw)
end

assert_eq(Shop::Child::KILL_GRACE, 3.0, 'KILL_GRACE is 3 s')
assert_eq(C::TICK, 0.1, 'TICK is 0.1 s')

with_home do |home|
  use_home(home)

  r = run(['/usr/bin/echo', 'hi'])
  assert_eq([r.exit_code, r.stdout, r.timed_out, r.overflowed], [0, "hi\n", false, false], 'a plain run')

  # A short child costs no supervisor tick: EOF on the pipes finishes the
  # job in the same pass (running -> draining -> done) instead of sleeping
  # TICK and then scanning /proc for a group that was already empty.
  run(['/bin/true'])
  # The median of five runs; up to three rounds so a loaded machine (other
  # suites running) does not fail a 14 ms operation on scheduling noise.
  # The bound sits under TICK (100 ms): a run that slept a tick costs at
  # least TICK plus the spawn, so anything below proves no tick was spent.
  bound_ms = C::TICK * 1000 * 0.8
  medians = []
  3.times do
    times = 5.times.map do
      t0 = Shop::Deadline.now
      run(['/bin/true'])
      (Shop::Deadline.now - t0) * 1000
    end
    medians << times.sort[2]
    break if medians.last <= bound_ms
  end
  assert(medians.min <= bound_ms, "median Command.run(/bin/true) is #{medians.min.round(1)} ms (<= #{bound_ms.round} ms); rounds: #{medians.map { |t| t.round(1) }}")
  # A lone leader never pays the /proc scan: once it is reaped, kill(0,
  # -pgid) says the group is gone and ProcessGroup.members is not consulted (the
  # scan is O(number of processes on the box) and made the timing above
  # depend on the machine's load).
  scans = 0
  pg = Shop::ProcessGroup
  orig_members = pg.method(:members)
  pg.define_singleton_method(:members) { |pgid, **kw| scans += 1; orig_members.call(pgid, **kw) }
  3.times { run(['/bin/true']) }
  assert_eq(scans, 0, 'Command.run(/bin/true) performs no /proc scan')
  pg.define_singleton_method(:members, orig_members)
  # ... while the scan does tell a live non-leader member from the leader:
  # asked while a grandchild holds the group (after the leader printed its
  # pid to a file, so the stop cannot land between the fork and the echo), it lists
  # that grandchild, and the run ends with the group gone. Whether finish!
  # ever consults the scan for an orphaned grandchild depends on the
  # subreaper having reaped it first, so that is not asserted.
  seen = []
  pid_file = File.join(home.dir, 'grandchild.pid')
  r = C.run(['/bin/sh', '-c', "/usr/bin/sleep 100 & echo $! > #{pid_file}; wait"], env: ENV_MIN, deadline: 5, max_stdout: 100,
            on_tick: lambda { |jobs|
              next unless File.file?(pid_file) && File.read(pid_file).end_with?("\n")

              child = jobs.first
              members = Shop::ProcessGroup.members(child.pgid, except: child.pgid)
              next if members.empty?

              seen.concat(members)
              child.stop!(:request)
            })
  grandchild = File.read(pid_file).to_i
  assert(grandchild.positive? && seen.include?(grandchild), "ProcessGroup.members lists the live grandchild (#{seen.inspect} vs #{grandchild})")
  assert(!alive?(grandchild) && r.exit_code == 143, "the stopped group is gone (#{r.exit_code})")
  assert_eq(run(['/usr/bin/pwd']).stdout.strip, home.run_dir, 'cwd is the private run dir')
  assert_eq(run(['/usr/bin/env']).stdout.lines.map { |l| l.split('=').first }.sort, %w[LANG PATH], 'unsetenv_others: only the given env')
  assert_eq(run(['/bin/sh', '-c', 'exit 3']).exit_code, 3, 'exit status')
  assert_eq(run(['/bin/sh', '-c', 'kill -9 $$']).exit_code, 137, 'death by signal -> 128+sig')
  pgid, pid = run(['/bin/sh', '-c', 'ps -o pgid= -p $$; echo $$']).stdout.split
  assert_eq(pgid, pid, 'the child leads its own process group')
  assert_eq(run([RUBY, '-e', '$stdout.write("caf\xFF".b)']).stdout, 'caf?', 'stdout scrubbed to valid UTF-8')
  assert(Shop::Signals.registered.empty?, 'no pgid left registered')

  # Deadline: TERM then reap.
  t0 = Shop::Deadline.now
  r = run(['/usr/bin/sleep', '100'], deadline: 0.3)
  assert(r.timed_out && r.exit_code == 143, "hang -> timed_out, TERMed (#{r.exit_code})")
  assert(Shop::Deadline.now - t0 < 1.5, 'TERM stops a well-behaved child quickly')

  # A child that ignores TERM is KILLed after the grace period. The shell
  # has its trap installed within milliseconds of the spawn (SIG_IGN
  # survives the exec); a `ruby -e` child took up to half a second to reach
  # its trap on a loaded box, so the TERM landed first and the test raced
  # the scheduler.
  t0 = Shop::Deadline.now
  r = run(['/bin/sh', '-c', 'trap "" TERM; echo $$; exec /usr/bin/sleep 100'], deadline: 0.3)
  elapsed = Shop::Deadline.now - t0
  assert(r.timed_out && r.exit_code == 137, "ignore-term -> KILL (#{r.exit_code})")
  assert(elapsed >= 1.2 && elapsed < 3.0, "KILL after the grace (#{elapsed.round(2)} s)")
  assert(!alive?(r.stdout.to_i), 'the TERM-ignoring child is gone')

  # Grandchildren in the group die with it.
  r = run(['/bin/sh', '-c', '/usr/bin/sleep 100 & echo $!; wait'], deadline: 0.3)
  grandchild = r.stdout.to_i
  assert(grandchild.positive? && !alive?(grandchild), 'the grandchild is gone after a timeout')
  # ... and when the leader exits on its own while a grandchild holds the pipe.
  t0 = Shop::Deadline.now
  r = run(['/bin/sh', '-c', '/usr/bin/sleep 100 & echo $!'], deadline: 10)
  assert(r.exit_code.zero? && !r.timed_out, 'leader exit is a normal result')
  assert(!alive?(r.stdout.to_i), 'the leftover grandchild is TERMed')
  assert(Shop::Deadline.now - t0 < 4, 'and the drain is bounded')

  # Byte caps.
  r = run([RUBY, '-e', 'loop { $stdout.write("x" * 65536) }'], max_stdout: 100_000)
  assert(r.overflowed && r.stdout.bytesize == 100_000, "flood -> overflowed at the cap (#{r.stdout.bytesize})")
  r = C.run([RUBY, '-e', '$stderr.write("a" * 100_000 + "END")'], env: ENV_MIN, deadline: 5, max_stdout: 10)
  assert(r.stderr_tail.bytesize == Shop::Child::MAX_STDERR && r.stderr_tail.end_with?('END'), 'stderr is a capped tail')
  r = C.run([RUBY, '-e', '$stdout.write("b" * 200_000 + "TAIL")'], env: ENV_MIN, deadline: 5, max_stdout: 1000, stdout_mode: :tail)
  assert(!r.overflowed && r.stdout.bytesize == 1000 && r.stdout.end_with?('TAIL'), 'stdout_mode :tail keeps the last bytes')

  # run_all: concurrency, order, on_done.
  done = []
  t0 = Shop::Deadline.now
  specs = (1..4).map { |i| { argv: ['/bin/sh', '-c', "sleep 0.3; echo #{i}"], env: ENV_MIN, deadline: 5, max_stdout: 100 } }
  results = C.run_all(specs, concurrency: 2, on_done: ->(i, res) { done << [i, res.stdout.strip] })
  elapsed = Shop::Deadline.now - t0
  assert_eq(results.map { |x| x.stdout.strip }, %w[1 2 3 4], 'results in spec order')
  assert_eq(done.map(&:first).sort, [0, 1, 2, 3], 'on_done once per job')
  assert(elapsed >= 0.55 && elapsed < 2.5, "concurrency 2 runs in two waves (#{elapsed.round(2)} s)")

  # Overall deadline: running jobs time out, queued ones never start.
  specs = (1..3).map { { argv: ['/usr/bin/sleep', '5'], env: ENV_MIN, deadline: 10, max_stdout: 10 } }
  results = C.run_all(specs, concurrency: 1, overall: Shop::Deadline.new(0.4))
  assert(results.all?(&:timed_out), 'overall deadline times out everything')
  assert(results[1].exit_code.nil? && results[2].exit_code.nil?, 'queued jobs never started')
  assert(Shop::Signals.registered.empty?, 'registry empty after run_all')

  # A finished child still draining when the overall deadline expires keeps
  # its result: the leader exits 0 at once, a detached grandchild holds
  # stdout open past the deadline.
  spec = { argv: ['/bin/sh', '-c', 'echo "{}"; setsid /usr/bin/sleep 1 & exit 0'], env: ENV_MIN, deadline: 10, max_stdout: 100 }
  r = C.run_all([spec], concurrency: 1, overall: Shop::Deadline.new(0.4)).first
  assert_eq([r.exit_code, r.stdout, r.timed_out], [0, "{}\n", false], 'a draining job is not marked timed_out')

  # A child that cannot start is a classified failure, not a crash.
  Shop.override!(kill_grace: 1.0, tools: { setpriv: '/nonexistent/setpriv' })
  begin
    run(['/usr/bin/true'])
    assert(false, 'spawn failure must raise')
  rescue Shop::Failure => e
    assert_eq([e.code, e.message], ['tool_failed', 'could not start true: no such file or directory'],
              'a tool that cannot start is tool_failed, with the OS reason alone')
  end
  begin
    C.run(['/usr/bin/true'], env: ENV_MIN, deadline: 5, max_stdout: 100, cli: true)
    assert(false, 'spawn failure must raise')
  rescue Shop::Failure => e
    assert_eq(e.code, 'cli_failed', 'a CLI call that cannot start is cli_failed')
  end
end
