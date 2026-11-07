# Shop::Lock: the per-store flock (a second holder is store_busy; the lock file is 0600; a symlinked lock file is unsafe_state_dir, and only the open says so).

require_relative '../support'

DOMAIN = 'alpha.myshopify.com'

with_home do |home|
  use_home(home)

  # Lock: a held lock is store_busy.
  Shop::Lock.with(DOMAIN) do
    pid = fork do
      Shop::Lock.with(DOMAIN) { exit!(0) }
    rescue Shop::Failure => e
      exit!(e.code == 'store_busy' ? 3 : 1)
    end
    _, st = Process.wait2(pid)
    assert_eq(st.exitstatus, 3, 'a second holder is store_busy')
  end
  Shop::Lock.with(DOMAIN) { :ok }
  assert_eq(File.stat(File.join(home.state_dir, 'locks', "#{DOMAIN}.lock")).mode & 0o777, 0o600, 'lock file 0600')

  # A lock file that is a symlink is refused at the open; an ELOOP the job
  # itself hits is the job's own error, not a symlinked lock file.
  message = (raised(Errno::ELOOP) { Shop::Lock.with(DOMAIN) { raise Errno::ELOOP, 'inside the job' } }&.message).to_s
  assert(message.include?('inside the job'), "an ELOOP inside the block propagates as itself (#{message})")
  other = 'beta.myshopify.com'
  File.symlink(home.path('elsewhere'), File.join(home.state_dir, 'locks', "#{other}.lock"))
  assert_eq(failure_code { Shop::Lock.with(other) { raise 'never reached' } }, 'unsafe_state_dir', 'a symlinked lock file is unsafe_state_dir')
  assert(!File.exist?(home.path('elsewhere')), 'and nothing is created through it')
end
