# Shop::Env: allowlisted child environments, plus end-to-end: the fake CLI sees no leaked keys and no npm.

require_relative 'support'

E = Shop::Env

dirty = {
  'HOME' => '/home/u', 'USER' => 'u', 'XDG_RUNTIME_DIR' => '/run/user/1000', 'DBUS_SESSION_BUS_ADDRESS' => 'unix:path=/x',
  'WAYLAND_DISPLAY' => 'wayland-1', 'BROWSER' => 'firefox', 'HTTPS_PROXY' => 'http://proxy:3128', 'NODE_EXTRA_CA_CERTS' => '/ca.pem',
  'NODE_OPTIONS' => '--require /tmp/evil.js', 'NODE_PATH' => '/tmp', 'NODE_TLS_REJECT_UNAUTHORIZED' => '0',
  'npm_config_registry' => 'http://evil', 'SHOPIFY_FLAG_STORE' => 'evil.myshopify.com', 'SHOPIFY_FLAG_PUBLISH' => '1',
  'SHOPIFY_CLI_PARTNERS_TOKEN' => 'tok', 'SHOPIFY_CLI_FORCE_AUTO_UPGRADE' => '1', 'RUBYOPT' => '-rx', 'GEM_HOME' => '/g',
  'BUNDLE_GEMFILE' => '/g', 'MISE_DATA_DIR' => '/m', 'PATH' => '/evil/bin:/usr/bin', 'CI' => '', 'LD_PRELOAD' => '/evil.so',
  'PIPEWIRE_RUNTIME_DIR' => '/run/pw', 'PULSE_SERVER' => 'unix:/p'
}
forbidden = /\A(?:NODE_OPTIONS|NODE_PATH|NODE_TLS_REJECT_UNAUTHORIZED|SHOPIFY_FLAG_.*|SHOPIFY_CLI_.*TOKEN.*|SHOPIFY_CLI_FORCE_AUTO_UPGRADE|RUBY.*|GEM_.*|BUNDLE_.*|MISE_.*|LD_PRELOAD)\z/

with_home do |home|
  ENV['HOME'] = home.dir
  cli = E.for_cli(interactive: false, source: dirty)
  assert(cli.keys.none? { |k| k.match?(forbidden) }, "for_cli leaks nothing: #{cli.keys}")
  assert(cli.keys.select { |k| k.start_with?('npm_config_') }.sort == %w[npm_config_dry_run npm_config_update_notifier], 'only the two npm_config keys')
  assert_eq(cli['CI'], '1', 'non-interactive sets CI=1')
  assert_eq(cli['npm_config_dry_run'], 'true', 'npm_config_dry_run=true')
  assert_eq(cli['PATH'], "#{Shop::Paths.bin_dir}:/usr/bin:/bin", 'PATH is the node-only bin dir plus the system dirs')
  assert_eq([cli['NO_COLOR'], cli['FORCE_COLOR'], cli['LANG'], cli['SHOPIFY_CLI_NO_ANALYTICS']], ['1', '0', 'C.UTF-8', '1'], 'fixed keys')
  assert(cli['HTTPS_PROXY'] && cli['NODE_EXTRA_CA_CERTS'] && cli['DBUS_SESSION_BUS_ADDRESS'], 'proxy/CA/dbus copied')
  assert(!cli.key?('WAYLAND_DISPLAY') && !cli.key?('BROWSER'), 'non-interactive has no display/browser')

  inter = E.for_cli(interactive: true, source: dirty)
  assert(!inter.key?('CI'), 'interactive leaves CI unset')
  assert(inter['WAYLAND_DISPLAY'] && inter['BROWSER'], 'interactive copies display and browser')
  assert_eq(inter['npm_config_dry_run'], 'true', 'interactive still blocks the auto-upgrade')

  mise = E.for_tool(:mise, source: dirty)
  assert_eq(mise['npm_config_registry'], 'https://registry.npmjs.org/', 'install forces the https registry')
  assert_eq(mise['npm_config_strict_ssl'], 'true', 'install forces strict-ssl')
  assert_eq([mise['MISE_YES'], mise['MISE_NPM_PACKAGE_MANAGER'], mise['CI'], mise['PATH']], ['1', 'npm', '1', '/usr/bin:/bin'], 'mise env')
  assert_eq(mise['MISE_DATA_DIR'], '/m', 'mise env keeps MISE_DATA_DIR')
  assert(!mise.key?('NODE_OPTIONS') && !mise.key?('SHOPIFY_FLAG_STORE') && !mise.key?('LD_PRELOAD'), 'mise env leaks nothing')

  notify = E.for_tool(:notify, source: dirty)
  assert_eq(notify.keys.sort, %w[DBUS_SESSION_BUS_ADDRESS HOME LANG NO_COLOR PATH USER WAYLAND_DISPLAY XDG_RUNTIME_DIR], 'notify env')
  clipboard = E.for_tool(:clipboard, source: dirty)
  assert_eq(clipboard.keys.sort, %w[HOME LANG NO_COLOR PATH USER WAYLAND_DISPLAY XDG_RUNTIME_DIR], 'clipboard env')
  begin
    E.for_tool(:shell, source: dirty)
    assert(false, 'an unknown profile must raise')
  rescue ArgumentError
    assert(true, 'an unknown profile is an ArgumentError, never an empty or inherited env')
  end
  sound = E.for_tool(:sound, source: dirty)
  assert_eq(sound.keys.sort, %w[HOME LANG NO_COLOR PATH PIPEWIRE_RUNTIME_DIR PULSE_SERVER USER XDG_RUNTIME_DIR], 'sound env')

  # End to end: a dirty parent env reaches the helper; the fake CLI logs what it saw.
  # Interpreter variables are the shebang's job (test_source_contracts); here
  # the helper's own env carries everything the CLI must not see.
  leak_env = dirty.reject { |k, _| %w[HOME PATH RUBYOPT GEM_HOME BUNDLE_GEMFILE LD_PRELOAD MISE_DATA_DIR].include?(k) }.merge('LEAK_CANARY' => '1')
  status, out, = run_one('check-account', home: home, env: leak_env)
  assert(status.zero? && out['account']['status'] == 'signed_in', 'check-account works with a dirty env')
  entry = home.cli_log.last
  assert_eq(entry['leaked'], [], 'the fake CLI sees no forbidden keys')
  assert_eq(entry['env']['CI'], '1', 'the CLI got CI=1')
  assert_eq(entry['cwd'], home.run_dir, 'the CLI cwd is the private run dir')

  # Canary: sign-in and grant-sales-access are interactive (no CI) and the
  # fake CLI tries `npm install -g` from PATH like the real auto-upgrade.
  # (Signed out first: sign-in only logs in when the probe says it must.)
  home.scenario!('auto-upgrade,logged-out')
  status, = run_one('sign-in', home: home, env: leak_env)
  assert(status.zero?, 'sign-in succeeds')
  status, = run_one('grant-sales-access', '--store=alpha', home: home, env: leak_env)
  assert(status.zero?, 'grant-sales-access succeeds')
  ups = home.upgrades
  assert_eq(ups.size, 2, 'the fake attempted the upgrade on both interactive commands')
  assert(ups.all? { |u| u['npm'].nil? && u['dry_run'] == 'true' && u['ci'].nil? }, "no npm on PATH, dry-run set: #{ups}")
  assert_eq(home.npm_log, [], 'the npm canary was never run')
  assert(home.cli_log.all? { |e| e['leaked'].empty? }, 'no call leaked keys')

  # Fake-bun canary: the CLI picks its upgrader by run.js path substring, so
  # an install under a "bun" path would run `bun install -g @latest` (where
  # npm_config_dry_run does nothing). Interactive calls are refused there.
  File.symlink(File.join(FIXTURE_BIN, 'fake-npm'), File.join(home.sysbin, 'bun'))
  bunny = home.path('bunny', 'mise')
  home.reinstall_under!(bunny)
  bun_env = leak_env.merge('MISE_DATA_DIR' => bunny)
  before = home.cli_log.size
  %w[sign-in grant-sales-access].each do |name|
    args = name == 'grant-sales-access' ? ['--store=alpha'] : []
    status, out, = run_one(name, *args, home: home, env: bun_env)
    assert_eq([status, out['error']['code']], [1, 'cli_failed'], "#{name} refused under a bun path (#{out})")
    assert(out['error']['message'].include?('auto-upgrade'), "#{name} says why")
  end
  assert_eq(home.cli_log.size, before, 'no CLI call ran under the bun path')
  assert_eq(home.npm_log, [], 'the bun canary was never run')
  status, out, = run_one('check-account', home: home, env: bun_env)
  assert(status.zero? && out['account']['status'] == 'signed_in', 'non-interactive calls (CI=1, no upgrade) still work there')
end
