# Shop::ProcessGroup: exit codes, /proc membership and the group-gone check.

require_relative 'support'

PG = Shop::ProcessGroup

# The test's own process group is alive (and may not be led by this pid
# when a runner spawned it, so it is named by getpgrp, not Process.pid).
assert(PG.gone?(Process.getpgrp) == false, 'gone? is false for a live group')
assert(PG.gone?(2**21) == true, 'gone? is true for a group that does not exist')
assert(PG.members(Process.getpgrp).include?(Process.pid), 'members lists this process in its own group')
assert(!PG.members(Process.getpgrp, except: Process.pid).include?(Process.pid), 'members leaves out `except`')
assert(!PG.exited?(Process.pid), 'a running pid has not exited')
assert(PG.signal(2**21, :TERM).nil?, 'signalling a missing group is a no-op')

pid = Process.spawn('/bin/sh', '-c', 'exit 3', pgroup: true)
assert(wait_until { PG.exited?(pid) }, 'an exited child reads as exited while it is a zombie')
assert_eq(PG.exit_code(Process.waitpid2(pid).last), 3, 'exit status')
assert(PG.wait_gone(pid), 'the reaped group is gone')
pid = Process.spawn('/bin/sh', '-c', 'kill -9 $$', pgroup: true)
assert_eq(PG.exit_code(Process.waitpid2(pid).last), 137, 'death by signal -> 128 + signal')
assert(PG.exit_code(nil).nil?, 'nothing reaped -> nil')
