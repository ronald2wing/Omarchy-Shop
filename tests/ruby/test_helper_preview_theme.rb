# helpers/preview-theme: dev theme only, loopback, readiness proves group ownership, the store lock for its lifetime, stdin EOF stops, TERM reaps.

require_relative 'support'

FORBIDDEN = %w[--theme -t --allow-live -a --theme-editor-sync --notify --open --password -e --environment].freeze

def read_event(io, timeout = 10)
  Timeout.timeout(timeout) { JSON.parse(io.gets || raise('FAIL: stream closed')) }
end

with_home do |home|
  folder = home.theme_folder
  stdin, stdout, stderr, thr = spawn_helper('preview-theme', '--store=alpha', "--folder=#{folder}", home: home)
  ready = read_event(stdout)
  assert_eq(ready['event'], 'ready', 'ready is the first event')
  dev = home.cli_log.last
  port = dev['argv'].find { |a| a.start_with?('--port=') }.delete_prefix('--port=').to_i
  assert_eq(ready['url'], "http://127.0.0.1:#{port}/", 'ready url on loopback')
  assert_eq(dev['argv'], ['theme', 'dev', '--store=alpha.myshopify.com', "--path=#{folder}", '--host=127.0.0.1', "--port=#{port}",
                          '--nodelete', '--live-reload=hot-reload', '--no-input'], 'theme dev argv: development theme, --nodelete, the CLI still gets --path')
  assert(dev['argv'].none? { |a| FORBIDDEN.include?(a.split('=', 2).first) }, 'no forbidden flags')
  assert_eq(dev['env']['CI'], '1', 'CI=1')
  server = home.pids.last['pid']

  # The store lock is held for the preview's lifetime: a push waits its turn (store_busy).
  st, out, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", '--target=160258294001', home: home)
  assert_eq([st, out['error']['code']], [1, 'store_busy'], "a push during the preview is store_busy (#{out})")
  assert(home.theme_calls.none? { |e| e['argv'][1] == 'push' }, 'and nothing was pushed')
  st, out, = run_one('restore-backup', '--store=alpha', '--backup=1762500000-160258294001', home: home)
  assert_eq([st, out['error']['code']], [1, 'store_busy'], 'a restore during the preview is store_busy')
  st, = run_one('list-themes', '--store=alpha', home: home)
  assert_eq(st, 0, 'read-only helpers are not blocked by the lock')

  stdin.close # EOF = stop
  rest = stdout.read.lines.map { |l| JSON.parse(l) }
  status = thr.value
  stderr.read
  assert_eq(rest.last, { 'event' => 'exited', 'ok' => true, 'error' => nil }, 'stdin EOF -> exited ok')
  assert_eq(status.exitstatus, 0, 'exit 0')
  assert(!alive?(server), 'the dev server is gone')
  st, out, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", '--target=160258294001', home: home)
  assert_eq(st, 0, "the lock is released when the preview ends (#{out})")

  # TERM: exited terminated, 143, group reaped.
  stdin, stdout, stderr, thr = spawn_helper('preview-theme', '--store=alpha', "--folder=#{folder}", home: home)
  read_event(stdout)
  server = home.pids.last['pid']
  Process.kill(:TERM, thr.pid)
  last = JSON.parse(stdout.read.lines.last)
  status = thr.value
  stdin.close
  stderr.read
  assert_eq([status.exitstatus, last['event'], last['error']['code']], [143, 'exited', 'terminated'], 'TERM -> exited terminated')
  assert(!alive?(server), 'dev server reaped on TERM')

  # The folder is re-checked while theme dev runs: a symlink added mid-run
  # (a checkout of a malicious branch) stops the preview.
  live = home.theme_folder('live-recheck')
  stdin, stdout, stderr, thr = spawn_helper('preview-theme', '--store=alpha', "--folder=#{live}", home: home,
                                                                                                overrides: { deadlines: { recheck: 0.3 } })
  read_event(stdout)
  server = home.pids.last['pid']
  File.symlink('/etc/hostname', File.join(live, 'snippets', 'late.liquid'))
  last = Timeout.timeout(15) { stdout.read.lines.map { |l| JSON.parse(l) }.last }
  status = thr.value
  stdin.close
  stderr.read
  assert_eq([status.exitstatus, last['event'], last['ok'], last['error']['code'], last['error']['reason']],
            [1, 'exited', false, 'unsafe_folder', 'symlink'], "a mid-run symlink stops the preview (#{last})")
  assert(!alive?(server), 'dev server reaped after the unsafe stop')
  # ... and so does a hardlink.
  hard = home.theme_folder('live-hard')
  stdin, stdout, stderr, thr = spawn_helper('preview-theme', '--store=alpha', "--folder=#{hard}", home: home,
                                                                                                overrides: { deadlines: { recheck: 0.3 } })
  read_event(stdout)
  File.link(File.join(hard, 'layout', 'theme.liquid'), home.path('work', 'hard-other'))
  last = Timeout.timeout(15) { stdout.read.lines.map { |l| JSON.parse(l) }.last }
  thr.value
  stdin.close
  stderr.read
  assert_eq([last['error']['code'], last['error']['reason']], %w[unsafe_folder hardlink], 'a mid-run hardlink stops the preview')
  # ... and so does the folder going away (a branch switch or a clean that
  # removes it): theme dev would keep serving the last upload.
  gone = home.theme_folder('live-gone')
  stdin, stdout, stderr, thr = spawn_helper('preview-theme', '--store=alpha', "--folder=#{gone}", home: home,
                                                                                                overrides: { deadlines: { recheck: 0.3 } })
  read_event(stdout)
  server = home.pids.last['pid']
  FileUtils.rm_rf(gone)
  last = Timeout.timeout(15) { stdout.read.lines.map { |l| JSON.parse(l) }.last }
  status = thr.value
  stdin.close
  stderr.read
  assert_eq([status.exitstatus, last['event'], last['ok'], last['error']['code'], last['error']['message']],
            [1, 'exited', false, 'not_a_theme_folder', 'folder not found'], "a folder that vanishes mid-run stops the preview (#{last})")
  assert(!alive?(server), 'dev server reaped after the folder vanished')

  # A foreign listener on the port is never "ready".
  home.scenario!('foreign-listener')
  stdin, stdout, stderr, thr = spawn_helper('preview-theme', '--store=alpha', "--folder=#{folder}", home: home, overrides: { deadlines: { ready: 1.5 } })
  lines = stdout.read.lines.map { |l| JSON.parse(l) }
  status = thr.value
  stdin.close
  stderr.read
  assert(lines.none? { |l| l['event'] == 'ready' }, 'never ready')
  assert_eq([status.exitstatus, lines.last['event'], lines.last['ok'], lines.last['error']['code']], [124, 'exited', false, 'timeout'], 'not ready -> timeout')

  # The CLI exiting on its own.
  home.scenario!('dev-exits')
  stdin, stdout, stderr, thr = spawn_helper('preview-theme', '--store=alpha', "--folder=#{folder}", home: home)
  lines = stdout.read.lines.map { |l| JSON.parse(l) }
  status = thr.value
  stdin.close
  stderr.read
  assert_eq(lines.last.slice('event', 'ok'), { 'event' => 'exited', 'ok' => false }, 'CLI exit -> exited not ok')
  assert_eq([status.exitstatus, lines.last['error']['code']], [1, 'cli_failed'], 'cli_failed')
  # (stdin stays open: closing it is the stop request and would win the race.)
  home.scenario!('admin-401-theme')
  stdin, stdout, stderr, thr = spawn_helper('preview-theme', '--store=alpha', "--folder=#{folder}", home: home)
  lines = stdout.read.lines.map { |l| JSON.parse(l) }
  status = thr.value
  stdin.close
  stderr.read
  assert_eq([status.exitstatus, lines.last['error']['code']], [1, 'theme_session_expired'], 'an Admin 401 from theme dev is the theme session')

  # Every link, special file and toml trap is refused before the CLI runs.
  home.scenario!('ok')
  assert_refuses_unsafe_folders(home, 'preview-theme', '--store=alpha')
  toml = home.theme_folder('toml')
  File.write(File.join(toml, 'SHOPIFY.THEME.TOML'), "[environments.default]\npublish = true\n")
  before = home.cli_log.size
  status, lines, = run_helper('preview-theme', '--store=alpha', "--folder=#{toml}", home: home)
  assert_eq([status, lines.last['event'], lines.last['error']['code'], lines.last['error']['reason']], [1, 'exited', 'unsafe_folder', 'theme_toml'], 'toml refused')
  assert_eq(home.cli_log.size, before, 'zero theme calls for the toml folder')
  status, lines, = run_helper('preview-theme', '--store=alpha', "--folder=#{folder}", '--theme=1', home: home)
  assert_eq([status, lines.last['error']['code']], [1, 'invalid_argument'], 'there is no --theme')
end
