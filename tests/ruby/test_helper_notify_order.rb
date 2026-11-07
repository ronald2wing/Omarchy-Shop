# helpers/notify-order: verbatim title, neutralised body, capped text, `--` before positionals, sound fallback, missing tools skipped.

require_relative 'support'

# The one tool double, linked under each tool's name (the log file is named after argv0).
TOOL = File.join(FIXTURE_BIN, 'fake-tool')
SOUND = File.join(ROOT, 'assets', 'sounds', 'new-order.oga')

with_home do |home|
  FileUtils.mkdir_p(home.path('bin'))
  notify = home.path('bin', 'notify-send')
  player = home.path('bin', 'pw-play')
  File.symlink(TOOL, notify)
  File.symlink(TOOL, player)
  tools = { notify_send: notify, pw_play: player, paplay: '/nonexistent/paplay' }
  status, out, = run_one('notify-order', '--title=New order · <b>Acme</b> & Co', "--body=#1005 · $35.81 · Tee & Mug\u0007\n3 today <i>",
                         '--sound', home: home, overrides: { tools: tools }, env: { 'DBUS_SESSION_BUS_ADDRESS' => 'unix:x', 'NODE_OPTIONS' => 'x' })
  assert_eq(out, { 'ok' => true, 'notified' => true, 'sound' => true }, "notified (#{out})")
  assert_eq(status, 0, 'exit 0')
  n = home.tool_log('notify-send').last
  assert_eq(n['argv'], ['--app-name=Shop', '--', 'New order · <b>Acme</b> & Co', "#1005 · $35.81 · Tee \uFF06 Mug\n3 today \u2039i\u203A"],
            'title verbatim (controls stripped); body neutralised (‹ › ＆), controls stripped, newline kept; -- before positionals')
  # A product title carrying a link (or an escaped one) never reaches the
  # daemon as markup.
  run_one('notify-order', '--title=T', '--body=1 · &lt;a href="https://evil.example"&gt;Open&lt;/a&gt; <b>x</b>', home: home, overrides: { tools: tools })
  assert(!home.tool_log('notify-send').last['argv'].last.match?(/[<>&]/), 'no markup character in the body argv')
  assert_eq(n['env'], %w[DBUS_SESSION_BUS_ADDRESS HOME LANG NO_COLOR PATH], 'notify env allowlist')
  p = home.tool_log('pw-play').last
  assert_eq(p['argv'], [SOUND], 'pw-play gets the fixed sound path')

  # The zero-width joiner survives in both: emoji sequences stay whole.
  run_one('notify-order', "--title=👩‍💻 ordered", "--body=👨‍👩‍👧 ​ x", home: home, overrides: { tools: tools })
  n = home.tool_log('notify-send').last
  assert_eq(n['argv'].last(2), ["👩‍💻 ordered", "👨‍👩‍👧  x"], 'U+200D kept, other format characters stripped')

  # Fallback to paplay; nothing requested -> sound null.
  home_tools = { notify_send: notify, pw_play: '/nonexistent/pw-play', paplay: player }
  out = run_one('notify-order', '--title=T', '--body=B', '--sound', home: home, overrides: { tools: home_tools })[1]
  assert_eq(out['sound'], true, 'paplay fallback')
  out = run_one('notify-order', '--title=T', '--body=B', home: home, overrides: { tools: tools })[1]
  assert_eq(out['sound'], nil, 'sound not requested -> null')

  # pw-play exists but fails (PulseAudio-only system): paplay is tried next.
  failing = home.path('bin', 'pw-play-fail')
  paplay = home.path('bin', 'paplay')
  File.symlink(TOOL, failing)
  File.symlink(TOOL, paplay)
  out = run_one('notify-order', '--title=T', '--body=B', '--sound', home: home,
                                                                   overrides: { tools: { notify_send: notify, pw_play: failing, paplay: paplay } })[1]
  assert_eq(out['sound'], true, "failing pw-play falls back to paplay (#{out})")
  assert_eq([home.tool_log('pw-play-fail').size, home.tool_log('paplay').size], [1, 1], 'both players were tried, in order')

  # Missing tools are skipped.
  none = { notify_send: '/nonexistent/notify-send', pw_play: '/nonexistent/pw-play', paplay: '/nonexistent/paplay' }
  status, out, = run_one('notify-order', '--title=T', '--body=B', '--sound', home: home, overrides: { tools: none })
  assert_eq([status, out], [0, { 'ok' => true, 'notified' => false, 'sound' => false }], 'missing tools')

  long = run_one('notify-order', "--title=#{'x' * 1000}", "--body=#{'<' * 1000}", home: home, overrides: { tools: tools })[1]
  argv = home.tool_log('notify-send').last['argv']
  assert(long['notified'] && argv[2].length == 300 && argv[3] == ("\u2039" * 299) + '…', 'title and body capped at 300 chars, then the body neutralised')
  status, out, = run_one('notify-order', '--title=T', home: home, overrides: { tools: tools })
  assert_eq([status, out['error']['code']], [1, 'invalid_argument'], 'missing --body')
  status, = run_one('notify-order', "--title=\u0007", '--body=b', home: home, overrides: { tools: tools })
  assert_eq(status, 1, 'an empty title after cleaning')
  status, = run_one('notify-order', '--title=T', '--body=b', '--sound=1', home: home, overrides: { tools: tools })
  assert_eq(status, 1, '--sound takes no value')
end
