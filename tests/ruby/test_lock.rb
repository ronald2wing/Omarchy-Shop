# Shop::Lock: the per-store flock (a second holder is store_busy; the lock file is 0600).

require_relative 'support'

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
end
