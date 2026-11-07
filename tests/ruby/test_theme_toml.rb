# Shop::ThemeToml: a shopify.theme.toml (any case) in a dir or any ancestor, and refuse! over the --path and cwd chains.

require_relative 'support'

TT = Shop::ThemeToml

with_home do |home|
  use_home(home)
  folder = home.theme_folder
  nested = File.join(folder, 'sections')

  assert_eq(TT.reachable_from?(nested), false, 'reachable_from? false without a toml')
  assert(TT.refuse!(Shop::Paths.run_dir, nil, folder).nil?, 'refuse! passes without one (nil dirs skipped)')
  File.write(home.path('Shopify.theme.toml'), '')
  assert(TT.in?(home.dir) && !TT.in?(folder), 'in? looks in the dir only, any case')
  assert(TT.reachable_from?(nested), 'reachable_from? finds a toml in an ancestor')
  assert_eq(failure_code { TT.refuse!(Shop::Paths.run_dir) }, 'unsafe_folder', 'refuse! covers the run dir chain')
  begin
    TT.refuse!(folder)
  rescue Shop::Failure => e
    assert_eq(e.to_error['reason'], 'theme_toml', 'refuse! carries error.reason theme_toml')
  end
  File.unlink(home.path('Shopify.theme.toml'))
  # An unreadable but searchable dir is probed by name.
  locked = home.path('work', 'locked')
  FileUtils.mkdir_p(locked)
  File.write(File.join(locked, TT::NAME), '')
  File.chmod(0o300, locked)
  begin
    assert(TT.in?(locked), 'an unlistable dir is probed by name')
  ensure
    File.chmod(0o755, locked)
  end
end
