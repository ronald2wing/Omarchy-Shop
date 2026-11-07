# Shop::Tools: every external tool has one absolute default path, overridable only through the test seam.

require_relative 'support'

T = Shop::Tools

Shop.override!({})
assert_eq(T::PATHS.keys, %i[setpriv mise notify_send pw_play paplay wl_paste], 'the six tools')
T::PATHS.each_value { |p| assert(p.start_with?('/usr/bin/'), "#{p} is an absolute /usr/bin path") }
assert_eq(%i[setpriv mise notify_send pw_play paplay wl_paste].map { |n| T.path(n) },
          %w[/usr/bin/setpriv /usr/bin/mise /usr/bin/notify-send /usr/bin/pw-play /usr/bin/paplay /usr/bin/wl-paste], 'defaults')

Shop.override!(tools: { mise: '/x/mise' })
assert_eq([T.path(:mise), T.path(:setpriv)], %w[/x/mise /usr/bin/setpriv], 'an override replaces only the named tool')
Shop.override!({})
assert_eq(T.path(:mise), '/usr/bin/mise', 'cleared overrides restore the default')

begin
  T.path(:bash)
  assert(false, 'unknown tools must raise')
rescue KeyError
  assert(true, 'unknown tool names are a KeyError, not a PATH lookup')
end

# Every runnable tool has an env profile Env knows; setpriv only prefixes.
assert_eq(T::PROFILES.keys, %i[mise notify_send pw_play paplay wl_paste], 'runnable tools')
T::PROFILES.each_value { |kind| assert(Shop::Env.for_tool(kind, source: {}).key?('PATH'), "#{kind} is an Env profile") }
assert(!T::PROFILES.key?(:setpriv), 'setpriv is never run alone')
# available? and run, through the override seam.
with_home do |home|
  use_home(home)
  tool = File.join(FIXTURE_BIN, 'fake-tool')
  Shop.override!(default_overrides(home).merge(tools: { notify_send: tool, wl_paste: '/nonexistent/wl-paste' }))
  assert(T.available?(:notify_send) && !T.available?(:wl_paste), 'available? is an executable check')
  result = T.run(:notify_send, ['--app-name=Shop', '--', 't', 'b'], deadline: 5, max_stdout: 1024)
  assert_eq([result.exit_code, result.timed_out], [0, false], 'run runs the tool under the supervisor')
  assert(T.run(:wl_paste, [], deadline: 5, max_stdout: 1024).exit_code.positive?, 'a missing tool fails inside setpriv: a non-zero exit')
  Shop.override!(default_overrides(home).merge(tools: { notify_send: tool, setpriv: '/nonexistent/setpriv' }))
  assert_eq(failure_code { T.run(:notify_send, [], deadline: 5, max_stdout: 1024) }, 'tool_failed', 'a tool that cannot start is tool_failed')
  begin
    T.run(:setpriv, [], deadline: 5, max_stdout: 1024)
    assert(false, 'setpriv has no profile')
  rescue KeyError
    assert(true, 'only a PROFILES tool runs')
  end
  Shop.override!({})
end
