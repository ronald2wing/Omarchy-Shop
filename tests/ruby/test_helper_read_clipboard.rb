# helpers/read-clipboard: first line cleaned and capped, empty clipboard, endless and hung clipboard owners stopped, missing wl-paste, env allowlist.

require_relative 'support'

FAKE = File.join(FIXTURE_BIN, 'fake-wl-paste')

with_home do |home|
  FileUtils.mkdir_p(home.path('bin'))
  wl_paste = home.path('bin', 'wl-paste')
  File.symlink(FAKE, wl_paste)
  tools = { wl_paste: wl_paste }
  clipboard = File.join(home.dir, '.fake-clipboard')
  paste = lambda do |content|
    content.nil? ? FileUtils.rm_f(clipboard) : File.binwrite(clipboard, content)
    run_one('read-clipboard', home: home, overrides: { tools: tools }, env: { 'WAYLAND_DISPLAY' => 'wayland-1', 'NODE_OPTIONS' => 'x' })
  end

  status, out, = paste.call("  ~/work/my  shop \u202e\u0007\nsecond line")
  assert_eq([status, out], [0, { 'ok' => true, 'text' => '~/work/my  shop' }], "first line, controls removed, inner spaces kept, trimmed (#{out})")
  log = home.tool_log('wl-paste').last
  assert_eq(log['argv'], %w[--no-newline --type text], 'wl-paste argv')
  assert_eq(log['env'], %w[HOME LANG NO_COLOR PATH WAYLAND_DISPLAY], 'clipboard env allowlist')

  assert_eq(paste.call(nil)[0, 2], [0, { 'ok' => true, 'text' => '' }], 'empty clipboard is an empty paste')
  assert_eq(paste.call("\xff\xfeok".b)[1]['text'], '??ok', 'invalid UTF-8 scrubbed')
  assert_eq(paste.call('y' * 5000)[1]['text'].length, 4096, 'capped at 4096 chars')

  started = Time.now
  status, out, = paste.call('endless')
  assert_eq([status, out.dig('error', 'code')], [1, 'clipboard_too_large'], "an endless clipboard is refused (#{out})")
  assert(Time.now - started < 3, 'refused at the byte cap, not at the deadline')

  started = Time.now
  status, out, = paste.call('hang')
  assert_eq([status, out.dig('error', 'code')], [124, 'timeout'], "a clipboard that never answers times out (#{out})")
  assert(Time.now - started < 4.5, 'stopped at the 2 s call deadline (plus grace)')
  assert(IO.popen(['pgrep', '-f', FAKE], &:read).strip.empty?, 'no wl-paste double left running')

  status, out, = run_one('read-clipboard', home: home, overrides: { tools: { wl_paste: '/nonexistent/wl-paste' } })
  assert_eq([status, out.dig('error', 'code')], [1, 'clipboard_unavailable'], 'missing wl-paste')
end
