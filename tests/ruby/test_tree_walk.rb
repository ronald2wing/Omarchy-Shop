# Shop::TreeWalk: the one lstat walk (ownership and write bits per entry, the entry cap while listing, the walk deadline, stats).

require_relative 'support'

TW = Shop::TreeWalk

with_home do |home|
  use_home(home)
  folder = home.theme_folder
  reason = ->(path) { Shop::ThemeFolder.report(path)['reason'] }

  # Ownership and world-writability apply to every walked entry.
  loose = home.theme_folder('loose')
  FileUtils.mkdir_p(File.join(loose, 'assets'))
  File.chmod(0o777, File.join(loose, 'assets'))
  assert_eq(reason.call(loose), 'world_writable', 'a world-writable assets/ refused')
  File.chmod(0o700, File.join(loose, 'assets'))
  File.write(File.join(loose, 'assets', 'a.js'), 'x')
  File.chmod(0o666, File.join(loose, 'assets', 'a.js'))
  assert_eq(reason.call(loose), 'world_writable', 'a world-writable file refused')
  assert_eq(TW.walk(File.realpath(loose))[:at], 'assets/a.js', 'walk reports where')
  File.chmod(0o600, File.join(loose, 'assets', 'a.js'))
  assert(Shop::ThemeFolder.report(loose)['safe'], 'safe again once tightened')
  # A foreign owner, simulated without root: the walk refuses the first
  # entry it sees.
  real_uid = Process.uid
  orig_owner = TW.method(:owner_uid)
  orig_entry = TW.method(:entry_reason)
  TW.define_singleton_method(:owner_uid) { real_uid + 1 }
  walk = TW.walk(File.realpath(loose), %w[assets])
  assert_eq([walk[:reason], walk[:at]], %w[not_owned assets], 'a theme dir owned by another user refused')
  TW.define_singleton_method(:owner_uid) { real_uid }
  TW.define_singleton_method(:entry_reason) { |st| st.file? ? 'not_owned' : orig_entry.call(st) }
  walk = TW.walk(File.realpath(loose), %w[assets])
  assert_eq([walk[:reason], walk[:at]], %w[not_owned assets/a.js], 'a file owned by another user refused')
  TW.define_singleton_method(:owner_uid, orig_owner)
  TW.define_singleton_method(:entry_reason, orig_entry)
  assert(Shop::ThemeFolder.report(loose)['safe'], 'stubs restored')

  # walk over the whole tree (no entries list) is what the backups use.
  whole = TW.walk(File.realpath(folder))
  assert_eq([whole[:files], whole[:bytes], whole[:reason]], [2, 15, nil], 'walk(root) counts everything under root')

  many = home.theme_folder('many')
  FileUtils.mkdir_p(File.join(many, 'assets'))
  20_001.times { |i| FileUtils.touch(File.join(many, 'assets', "a#{i}")) }
  assert_eq(reason.call(many), 'too_many_files', 'more than 20,000 entries refused')
  # The cap is checked while a directory is listed, not when its entries
  # are popped: one directory past the cap stops mid-listing (the names
  # never all sit on the stack), and its `at` is inside that directory.
  orig_cap = TW.method(:max_entries)
  TW.define_singleton_method(:max_entries) { 10 }
  wide = home.theme_folder('wide')
  FileUtils.mkdir_p(File.join(wide, 'assets'))
  50.times { |i| FileUtils.touch(File.join(wide, 'assets', format('a%02d', i))) }
  yielded = 0
  orig_each_child = Dir.method(:each_child)
  Dir.define_singleton_method(:each_child) do |path, &blk|
    next orig_each_child.call(path) unless blk

    orig_each_child.call(path) { |n| yielded += 1; blk.call(n) }
  end
  begin
    capped = TW.walk(File.realpath(wide), %w[assets])
  ensure
    Dir.define_singleton_method(:each_child, orig_each_child)
  end
  assert_eq(capped[:reason], 'too_many_files', 'a directory past the cap is refused')
  assert(capped[:at].start_with?('assets/'), "too_many_files names an entry inside the wide directory, got #{capped[:at]}")
  assert(yielded <= 11, "the listing stopped at the cap, yielded #{yielded} of 50")
  top = home.theme_folder('top')
  12.times { |i| FileUtils.touch(File.join(top, "f#{i}")) }
  assert_eq(TW.walk(File.realpath(top))[:reason], 'too_many_files', 'top-level entries alone past the cap are refused')
  TW.define_singleton_method(:max_entries, orig_cap)
  assert_eq(TW.walk(File.realpath(wide))[:reason], nil, 'cap restored')
  # The walk deadline is the inspect-folder walk budget; a tiny override times out.
  Shop.override!(trusted_parent: home.dir, deadlines: { walk: 0.0001 })
  assert_eq(failure_code { TW.walk(File.realpath(many)) }, 'timeout', 'a walk past its budget is a timeout')
  Shop.override!(trusted_parent: home.dir)
  assert_eq(TW.stats(File.realpath(folder)), [2, 15], 'stats: [files, bytes]')
end
