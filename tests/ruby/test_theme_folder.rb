# Shop::ThemeFolder: the report and check! over location, ancestor, ownership, link, special-file and toml rules, and the theme shape.

require_relative 'support'
require 'socket'

TF = Shop::ThemeFolder

with_home do |home|
  ENV['HOME'] = home.dir
  Shop::Paths.prepare!
  folder = home.theme_folder
  # The throwaway HOME sits under /tmp (sticky, world-writable), so without
  # the test seam every folder in it has an unsafe parent.
  assert_eq(TF.report(folder)['reason'], 'unsafe_parent', 'a folder under /tmp is refused')
  Shop.override!(trusted_parent: home.dir)
  report = TF.report(folder)
  assert(report['exists'] && report['themeShaped'] && report['safe'] && report['reason'].nil? && report['at'].nil?, "theme folder is safe: #{report}")
  assert_eq(report.keys, %w[folder exists themeShaped empty safe reason at bytes rootFiles], 'report keys')
  assert_eq(report['bytes'], 15, 'bytes counted by lstat')
  assert_eq(TF.check!(folder, mode: :push)['folder'], folder, 'check! returns the real path')

  reason = ->(path) { TF.report(path)['reason'] }
  assert_eq(reason.call('relative/path'), 'not_absolute', 'relative paths')
  assert_eq(reason.call('/'), 'root', 'root')
  assert_eq(reason.call(home.dir), 'home', 'home')
  FileUtils.mkdir_p(home.path('.config', 'x'))
  assert_eq(reason.call(home.path('.config', 'x')), 'config', 'inside ~/.config')
  assert_eq(reason.call(home.state_dir), 'state', 'the state dir')
  assert_eq(reason.call(home.path('.local')), 'state', 'an ancestor of the state dir')
  assert_eq(reason.call(Shop::ROOT), 'plugin', 'the plugin root')
  File.write(home.path('work', 'file'), 'x')
  assert_eq(reason.call(home.path('work', 'file')), 'not_directory', 'a file')
  missing = TF.report(home.path('work', 'missing'))
  assert(!missing['exists'] && missing['reason'].nil?, 'a missing folder')
  assert_eq(failure_code { TF.check!(home.path('work', 'missing'), mode: :pull) }, 'not_a_theme_folder', 'missing folder refused')

  # Ancestors other users can write to: a 0777 or 1777 parent lets them plant
  # a shopify.theme.toml or swap the folder for a symlink after the check.
  %w[0777 1777 0775].each do |mode|
    shared = home.path('work', "shared#{mode}")
    FileUtils.mkdir_p(shared)
    t = home.theme_folder("shared#{mode}/t")
    File.chmod(mode.to_i(8), shared)
    assert_eq(reason.call(t), 'unsafe_parent', "a folder under a #{mode} parent is refused")
    File.chmod(0o755, shared)
    assert(TF.report(t)['safe'], "safe again once the #{mode} parent is tightened")
  end

  ww = home.theme_folder('ww')
  File.chmod(0o777, ww)
  assert_eq(reason.call(ww), 'world_writable', 'world-writable folder')
  # Group-writable is refused with the same mask as the ancestors (0o022):
  # every member of the group could drop a file the next push uploads.
  gw = home.theme_folder('gw')
  File.chmod(0o775, gw)
  assert_eq(reason.call(gw), 'group_writable', 'a 0775 folder is refused')
  File.chmod(0o755, gw)
  File.chmod(0o775, File.join(gw, 'layout'))
  assert_eq([reason.call(gw), TF.report(gw)['at']], %w[group_writable layout], 'a 0775 theme dir is refused')
  File.chmod(0o755, File.join(gw, 'layout'))
  File.chmod(0o664, File.join(gw, 'layout', 'theme.liquid'))
  assert_eq([reason.call(gw), TF.report(gw)['at']], %w[group_writable layout/theme.liquid], 'a 0664 file is refused')
  File.chmod(0o644, File.join(gw, 'layout', 'theme.liquid'))
  assert(TF.report(gw)['safe'], 'safe again once tightened')
  assert_eq(failure_code { File.chmod(0o775, gw); TF.check!(gw, mode: :push) }, 'unsafe_folder', 'check! refuses a group-writable folder')
  File.chmod(0o755, gw)

  toml = home.theme_folder('toml')
  File.write(File.join(toml, 'Shopify.Theme.TOML'), "[environments.default]\npublish = true\n")
  assert_eq(reason.call(toml), 'theme_toml', 'shopify.theme.toml (any case) refused')
  assert_eq(failure_code { TF.check!(toml, mode: :push) }, 'unsafe_folder', 'check! raises unsafe_folder')
  begin
    TF.check!(toml, mode: :pull)
  rescue Shop::Failure => e
    assert_eq(e.to_error['reason'], 'theme_toml', 'unsafe_folder carries error.reason')
  end

  # Every symlink is refused, wherever it points: the CLI's pull writes
  # through it and its push glob follows it.
  esc = home.theme_folder('escape')
  File.symlink('/etc/passwd', File.join(esc, 'snippets', 'x.liquid'))
  ei = TF.report(esc)
  assert_eq([ei['reason'], ei['at'], ei['safe'], ei['themeShaped']], ['symlink', 'snippets/x.liquid', false, false],
            'escaping symlink refused, with where; an unsafe folder is never themeShaped')
  dangling = home.theme_folder('dangling')
  File.symlink('../../../outside', File.join(dangling, 'snippets', 'd.liquid'))
  assert_eq(reason.call(dangling), 'symlink', 'dangling escaping symlink refused')
  inside = home.theme_folder('inside')
  File.symlink('../layout/theme.liquid', File.join(inside, 'snippets', 'ok.liquid'))
  assert_eq(reason.call(inside), 'symlink', 'a symlink staying inside is refused too')
  envleak = home.theme_folder('envleak')
  File.write(File.join(envleak, '.env'), 'TOKEN=x')
  FileUtils.mkdir_p(File.join(envleak, 'assets'))
  File.symlink('../.env', File.join(envleak, 'assets', 'leak.css'))
  assert_eq(reason.call(envleak), 'symlink', 'assets/leak.css -> ../.env refused')
  # A refused entry whose name is not valid UTF-8 (a theme zip, a repo)
  # still reads as that refusal: `at` is scrubbed, so the result encodes.
  badname = home.theme_folder('badname')
  File.symlink('/etc/passwd', File.join(badname, 'snippets', "bad\xFF.liquid".b))
  bad = TF.report(badname)
  assert_eq([bad['reason'], bad['at']], ['symlink', 'snippets/bad?.liquid'], 'non-UTF-8 symlink name refused, scrubbed where')
  assert(JSON.parse(JSON.generate(bad))['reason'] == 'symlink', 'the report encodes as JSON')
  # A non-UTF-8 folder name stays raw in the result (push-theme and
  # pull-theme hand it to the CLI as --path); the helpers' emitter scrubs it
  # on output.
  rawdir = home.theme_folder("raw\xFEdir".b)
  raw = TF.report(rawdir)
  assert(raw['safe'] && raw['folder'].b == File.realpath(rawdir).b && !raw['folder'].dup.force_encoding('UTF-8').valid_encoding?, "a non-UTF-8 folder keeps its raw path: #{raw['folder'].inspect}")
  gitcfg = home.theme_folder('gitcfg')
  FileUtils.mkdir_p(File.join(gitcfg, '.git'))
  File.write(File.join(gitcfg, '.git', 'config'), "[core]\n")
  File.symlink('../.git/config', File.join(gitcfg, 'snippets', 'x.liquid'))
  assert_eq(failure_code { TF.check!(gitcfg, mode: :pull) }, 'unsafe_folder', 'pull refuses snippets/x.liquid -> ../.git/config')
  stash = home.theme_folder('stash')
  FileUtils.mkdir_p(File.join(stash, 'stash'))
  File.write(home.path('work', 'stash-secret'), 'k')
  File.link(home.path('work', 'stash-secret'), File.join(stash, 'stash', 'key'))
  FileUtils.mkdir_p(File.join(stash, 'assets'))
  File.symlink('../stash/key', File.join(stash, 'assets', 'k.css'))
  assert_eq(reason.call(stash), 'symlink', 'a link to a hardlink kept outside the theme dirs is refused')
  subdir = home.theme_folder('subdir')
  FileUtils.mkdir_p(File.join(subdir, 'notes'))
  File.symlink('/etc/hostname', File.join(subdir, 'notes', 'leak.css'))
  FileUtils.mkdir_p(File.join(subdir, 'assets'))
  File.symlink('../notes', File.join(subdir, 'assets', 'sub'))
  assert_eq(reason.call(subdir), 'symlink', 'a symlinked dir inside a theme dir (fast-glob follows it) is refused')
  topsym = home.theme_folder('topsym')
  FileUtils.rm_rf(File.join(topsym, 'snippets'))
  File.symlink(File.join(topsym, 'sections'), File.join(topsym, 'snippets'))
  assert_eq(reason.call(topsym), 'symlink', 'a symlinked top-level theme dir refused')

  # Hardlinked files: the other name may live anywhere, so the content can
  # change under Shop or a pull can rewrite a file outside the folder.
  hard = home.theme_folder('hard')
  File.link(File.join(hard, 'layout', 'theme.liquid'), home.path('work', 'outside-link'))
  assert_eq([reason.call(hard), TF.report(hard)['at']], %w[hardlink layout/theme.liquid], 'hardlinked file refused')

  # The top-level files the pinned CLI syncs (AGENTS.md, DESIGN.md).
  agents = home.theme_folder('agents')
  File.symlink('/etc/hostname', File.join(agents, 'AGENTS.md'))
  assert_eq(reason.call(agents), 'symlink', 'a symlinked root AGENTS.md is refused')
  design = home.theme_folder('design')
  File.write(home.path('work', 'design-secret'), 'x')
  File.link(home.path('work', 'design-secret'), File.join(design, 'DESIGN.md'))
  assert_eq(reason.call(design), 'hardlink', 'a hardlinked root DESIGN.md is refused')
  plain = home.theme_folder('plainroot')
  File.write(File.join(plain, 'AGENTS.md'), '12345')
  pi = TF.report(plain)
  assert(pi['safe'] && pi['bytes'] == 20 && pi['rootFiles'] == ['AGENTS.md'], "a plain AGENTS.md is counted and named (#{pi})")

  # Anything that is not a directory or a regular file: FIFOs, sockets,
  # devices. The CLI would block reading a FIFO or fail on a socket.
  fifo = home.theme_folder('fifo')
  File.mkfifo(File.join(fifo, 'assets', 'pipe.css')) if (FileUtils.mkdir_p(File.join(fifo, 'assets')) && true)
  assert_eq([reason.call(fifo), TF.report(fifo)['at']], %w[special_file assets/pipe.css], 'a FIFO is special_file')
  sock = home.theme_folder('sock')
  FileUtils.mkdir_p(File.join(sock, 'assets'))
  server = UNIXServer.new(File.join(sock, 'assets', 'live.sock'))
  assert_eq(reason.call(sock), 'special_file', 'a socket is special_file')
  server.close

  # A path the kernel refuses (past PATH_MAX) is unreadable, not a crash.
  deep = home.theme_folder('deep')
  FileUtils.mkdir_p(File.join(deep, 'assets'))
  here = Dir.pwd
  Dir.chdir(File.join(deep, 'assets'))
  begin
    230.times { |i| Dir.mkdir("d#{i.to_s.rjust(19, '0')}") && Dir.chdir("d#{i.to_s.rjust(19, '0')}") }
  ensure
    Dir.chdir(here)
  end
  di = TF.report(deep)
  assert_eq(di['reason'], 'unreadable', "a 230-level tree past PATH_MAX is unreadable (#{di['at']})")
  assert_eq(failure_code { TF.check!(deep, mode: :push) }, 'unsafe_folder', 'and check! refuses it')

  # The CLI searches ancestor folders for shopify.theme.toml, so a toml in
  # any ancestor injects flags too.
  parent = home.path('work', 'mono')
  nested = File.join(parent, 'theme')
  %w[layout templates].each { |d| FileUtils.mkdir_p(File.join(nested, d)) }
  File.write(File.join(parent, 'shopify.theme.toml'), "[environments.default]\npublish = true\n")
  assert_eq(reason.call(nested), 'theme_toml', 'a toml in the parent dir is refused')
  File.unlink(File.join(parent, 'shopify.theme.toml'))
  assert(TF.report(nested)['safe'], 'safe again without it')
  File.write(home.path('Shopify.theme.toml'), '')
  assert_eq(reason.call(nested), 'theme_toml', 'a toml in HOME is refused')
  File.unlink(home.path('Shopify.theme.toml'))

  # themeShaped needs config/, layout/ and templates/ as directories: the
  # pinned CLI's push and dev refuse a folder missing any of them under
  # --no-input, which would otherwise surface only after the backup pull.
  noconfig = home.path('work', 'noconfig')
  %w[layout templates].each { |d| FileUtils.mkdir_p(File.join(noconfig, d)) }
  nc = TF.report(noconfig)
  assert(nc['safe'] && !nc['themeShaped'] && !nc['empty'], "layout/ + templates/ without config/ is not themeShaped (#{nc})")
  %i[push preview pull].each do |mode|
    assert_eq(failure_code { TF.check!(noconfig, mode: mode) }, 'not_a_theme_folder', "#{mode} refuses a folder without config/")
  end
  File.write(File.join(noconfig, 'config'), 'not a dir')
  assert_eq(TF.report(noconfig)['themeShaped'], false, 'a config file is not a config/ dir')
  assert_eq(TF::REQUIRED_DIRS, %w[config layout templates], 'the required dirs')

  empty = home.path('work', 'empty')
  FileUtils.mkdir_p(File.join(empty, '.git'))
  e = TF.report(empty)
  assert(e['empty'] && !e['themeShaped'] && e['safe'], 'a folder with only dotfiles is empty and safe')
  assert(TF.check!(empty, mode: :pull), 'pull accepts an empty folder')
  assert_eq(failure_code { TF.check!(empty, mode: :push) }, 'not_a_theme_folder', 'push needs a theme-shaped folder')
  assert_eq(failure_code { TF.check!(empty, mode: :preview) }, 'not_a_theme_folder', 'preview needs a theme-shaped folder')
  assert_eq(failure_code { TF.check!("/tmp/a\nb", mode: :push) }, 'invalid_argument', 'control characters in paths')
  assert_eq(failure_code { TF.path!('') }, 'invalid_argument', 'empty path')
  assert_eq(failure_code { TF.path!("/#{'a' * 5000}") }, 'invalid_argument', 'over-long path')

  assert_eq(TF.theme_relative('/p/x/sections/a.liquid'), 'sections/a.liquid', 'theme_relative from the theme dir')
  assert_eq(TF.theme_relative('/p/x/README.md'), 'README.md', 'theme_relative falls back to the basename')

  # check!'s refusal reads as words, with where and the reason code.
  linked = home.theme_folder('refusal-words')
  File.symlink('/etc/hostname', File.join(linked, 'snippets', 'x.liquid'))
  begin
    TF.check!(linked, mode: :push)
    assert(false, 'a symlink must be refused')
  rescue Shop::Failure => e
    assert_eq([e.code, e.message, e.to_error['reason']], ['unsafe_folder', 'folder holds a symlink ("snippets/x.liquid")', 'symlink'], 'refusal words')
  end
  contributing = File.read(File.join(ROOT, 'CONTRIBUTING.md'))
  documented = contributing[/`error\.reason` is one of ([^|]*)\|/, 1].scan(/`([a-z_]+)`/).flatten.sort
  assert_eq(TF::REASON_TEXT.keys.sort, documented, 'every documented unsafe_folder reason has words, and no other')
end
