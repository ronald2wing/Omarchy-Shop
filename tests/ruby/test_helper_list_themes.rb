# helpers/list-themes: `theme list --json` parsed and cleaned; the theme-command error codes.

require_relative 'support'

with_home do |home|
  status, out, = run_one('list-themes', '--store=alpha', home: home)
  assert_eq(status, 0, 'list-themes ok')
  assert_eq(out, { 'ok' => true, 'themes' => [
    { 'id' => '160258293983', 'name' => 'Dawn', 'role' => 'live' },
    { 'id' => '160258294001', 'name' => 'Dawn copy', 'role' => 'unpublished' },
    { 'id' => '160258294002', 'name' => 'Dev (alice)', 'role' => 'development' }
  ] }, 'themes')
  assert_eq(home.cli_log.last['argv'], ['theme', 'list', '--store=alpha.myshopify.com', '--json', '--no-input'], 'theme list argv')
  home.scenario!('copy-published')
  assert_eq(run_one('list-themes', '--store=alpha', home: home)[1]['themes'].map { |t| t['role'] }, %w[unpublished live development], 'roles come from the CLI')

  { 'admin-401-theme' => [1, 'theme_session_expired'], 'not-staff' => [1, 'cli_failed'],
    'paused' => [1, 'store_unavailable'], 'throttled' => [1, 'rate_limited'], 'server-error' => [1, 'cli_failed'] }.each do |sc, (code, name)|
    home.scenario!(sc)
    status, out, = run_one('list-themes', '--store=alpha', home: home)
    assert_eq([status, out['error']['code']], [code, name], "#{sc} -> #{name}")
  end
  home.scenario!('server-error')
  assert_eq(run_one('list-themes', '--store=alpha', home: home)[1]['error']['retryAfter'], 60, 'a server error carries retryAfter 60')

  # A shopify.theme.toml above the private cwd would change the command.
  home.scenario!('ok')
  File.write(home.path('shopify.theme.toml'), "[environments.default]\npublish = true\n")
  before = home.cli_log.size
  status, out, = run_one('list-themes', '--store=alpha', home: home)
  assert_eq([status, out['error']['code'], out['error']['reason']], [1, 'unsafe_folder', 'theme_toml'], 'theme list refused under a HOME toml')
  assert_eq(home.cli_log.size, before, 'and never spawned')
  File.unlink(home.path('shopify.theme.toml'))
  status, out, = run_one('list-themes', home: home)
  assert_eq([status, out['error']['code']], [1, 'invalid_argument'], 'missing --store')
end
