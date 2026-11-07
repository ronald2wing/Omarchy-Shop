# Shop::Paths: 0700 dirs, symlinked/foreign dirs refused, private writes.

require_relative 'support'

P = Shop::Paths

with_home do |home|
  ENV['HOME'] = home.dir
  File.umask(0o077)
  P.prepare!
  P.all_dirs.each do |dir|
    st = File.lstat(dir)
    assert(st.directory? && (st.mode & 0o777) == 0o700, "#{dir} is a 0700 dir")
  end
  assert_eq(P.run_dir, File.join(home.state_dir, 'run'), 'run_dir under the state dir')
  assert_eq(P.bin_dir, File.join(home.state_dir, 'bin'), 'bin_dir under the state dir')
  assert(Dir.children(P.run_dir).empty?, 'run_dir is empty')

  File.chmod(0o755, P.backups_dir)
  P.prepare!
  assert_eq(File.stat(P.backups_dir).mode & 0o777, 0o700, 'prepare! tightens an existing dir')

  FileUtils.rm_rf(P.locks_dir)
  target = home.path('elsewhere')
  Dir.mkdir(target)
  File.symlink(target, P.locks_dir)
  begin
    P.prepare!
    assert(false, 'a symlinked state dir must be refused')
  rescue Shop::Failure => e
    assert_eq(e.code, 'unsafe_state_dir', 'symlinked dir -> unsafe_state_dir')
    assert_eq(e.exit_code, 1, 'unsafe_state_dir exits 1')
  end
  assert_eq(File.stat(target).mode & 0o777, 0o700, 'the symlink target was not chmodded') if (File.stat(target).mode & 0o777) == 0o700
  File.unlink(P.locks_dir)

  file = File.join(P.state_dir, 'x.json')
  P.write_private!(file, '{}')
  assert_eq(File.stat(file).mode & 0o777, 0o600, 'write_private writes 0600')
  assert(P.inside?('/a/b', '/a') && P.inside?('/a', '/a') && !P.inside?('/ab', '/a'), 'inside?')

  # mise's data dir: MISE_DATA_DIR, then $XDG_DATA_HOME/mise, then ~/.local/share/mise.
  saved = ENV.to_h.slice('MISE_DATA_DIR', 'XDG_DATA_HOME')
  ENV.delete('MISE_DATA_DIR')
  ENV.delete('XDG_DATA_HOME')
  assert_eq(P.mise_data_dir, File.join(ENV['HOME'], '.local', 'share', 'mise'), 'mise data dir default')
  ENV['XDG_DATA_HOME'] = '/tmp/xdg-data'
  assert_eq(P.mise_data_dir, '/tmp/xdg-data/mise', 'XDG_DATA_HOME/mise')
  assert_eq(Shop::Runtime.installs_dir, '/tmp/xdg-data/mise/installs', 'the CLI is looked for under XDG_DATA_HOME')
  ENV['XDG_DATA_HOME'] = 'relative'
  assert_eq(P.mise_data_dir, File.join(ENV['HOME'], '.local', 'share', 'mise'), 'a relative XDG_DATA_HOME is ignored')
  ENV['XDG_DATA_HOME'] = '/tmp/xdg-data'
  ENV['MISE_DATA_DIR'] = '/tmp/mise-data'
  assert_eq(P.mise_data_dir, '/tmp/mise-data', 'MISE_DATA_DIR wins')
  ENV.delete('MISE_DATA_DIR')
  ENV.delete('XDG_DATA_HOME')
  ENV.update(saved)

  ENV['HOME'] = 'relative'
  begin
    P.home
    assert(false, 'relative HOME refused')
  rescue Shop::Failure => e
    assert_eq(e.code, 'unsafe_state_dir', 'relative HOME refused')
  end
end
