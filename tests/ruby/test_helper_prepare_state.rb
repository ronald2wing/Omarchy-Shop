# helpers/prepare-state end to end, plus the shared helper CLI surface and the hardened shebang.

require_relative 'support'

HELPER = File.join(ROOT, 'helpers', 'prepare-state')

with_home do |home|
  status, out, = run_one('prepare-state', home: home)
  assert_eq([status, out], [0, { 'ok' => true }], 'prepare-state ok')
  %w[backups locks run bin].each do |d|
    assert_eq(File.stat(File.join(home.state_dir, d)).mode & 0o777, 0o700, "#{d} is 0700")
  end
  assert_eq(File.stat(home.path('.config', 'shop')).mode & 0o777, 0o700, 'config dir 0700')

  # Files the QML FileViews created at the shell's umask are brought to 0600.
  cache = File.join(home.state_dir, 'cache.json')
  config = home.path('.config', 'shop', 'config.json')
  File.write(cache, '{}')
  File.write(config, '{}')
  File.chmod(0o644, cache)
  File.chmod(0o644, config)
  File.symlink(cache, home.path('.config', 'shop', 'config.json.old'))
  status, = run_one('prepare-state', home: home)
  assert_eq(status, 0, 'prepare-state ok with service files present')
  assert_eq([File.stat(cache).mode & 0o777, File.stat(config).mode & 0o777], [0o600, 0o600], 'service files -> 0600')
  File.unlink(home.path('.config', 'shop', 'config.json.old'))

  # The shared CLI surface.
  status, out, = run_one('prepare-state', '--bogus', home: home)
  assert(status == 1 && out['error']['code'] == 'invalid_argument', 'unknown flag -> invalid_argument')
  status, out, = run_one('prepare-state', 'stray', home: home)
  assert(status == 1 && out['error']['message'].include?('unexpected argument'), 'stray argument -> exit 1')
  usage, st = Open3.capture2(helper_env(home, {}), RUBY, '--disable-gems', LAUNCHER, 'prepare-state', '{}', '--help',
                             unsetenv_others: true)
  assert(st.success? && usage.start_with?('usage: helpers/prepare-state'), '--help prints usage, exit 0')

  # Hardened shebang: interpreter variables in the caller's env are ignored.
  env = helper_env(home, 'RUBYOPT' => '-r/nonexistent/evil', 'RUBYLIB' => '/nonexistent', 'GEM_HOME' => '/x',
                         'BUNDLE_GEMFILE' => '/nonexistent/Gemfile')
  out, err, st = Open3.capture3(env, HELPER, unsetenv_others: true)
  assert(st.success? && JSON.parse(out)['ok'], "direct exec ignores RUBYOPT/RUBYLIB (#{err})")

  # A symlinked state dir is refused.
  FileUtils.rm_rf(File.join(home.state_dir, 'locks'))
  File.symlink('/tmp', File.join(home.state_dir, 'locks'))
  status, out, = run_one('prepare-state', home: home)
  assert(status == 1 && out['error']['code'] == 'unsafe_state_dir', 'symlinked locks dir -> unsafe_state_dir')
end
