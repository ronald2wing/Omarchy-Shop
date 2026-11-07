# Shop::FolderCopies: the pre-pull folder copy (theme dirs and root files only, size cap, no partial left), its listing and retention.

require_relative 'support'
require 'socket'

FC = Shop::FolderCopies
DOMAIN = 'alpha.myshopify.com'

with_home do |home|
  use_home(home)

  # Local copies hold everything a pull can overwrite: the theme dirs and the
  # top-level AGENTS.md/DESIGN.md (counted in the size cap); >200 MiB refused.
  folder = home.theme_folder
  FileUtils.mkdir_p(File.join(folder, 'node_modules'))
  File.write(File.join(folder, 'AGENTS.md'), "mine\n")
  File.write(File.join(folder, 'README.md'), "not synced\n")
  report = Shop::ThemeFolder.check!(folder, mode: :pull)
  assert_eq(report['bytes'], 15 + 5, 'AGENTS.md is in the byte count')
  copy = FC.create!(DOMAIN, report)
  cdir = File.join(home.backups_dir, DOMAIN, 'local', copy)
  assert(File.file?(File.join(cdir, 'layout', 'theme.liquid')) && !File.exist?(File.join(cdir, 'node_modules')), 'theme dirs only')
  assert_eq(File.read(File.join(cdir, 'AGENTS.md')), "mine\n", 'root AGENTS.md copied')
  assert(!File.exist?(File.join(cdir, 'README.md')) && !File.exist?(File.join(cdir, 'DESIGN.md')), 'only the synced root files')
  linked = home.theme_folder('linked')
  File.symlink('../layout/theme.liquid', File.join(linked, 'snippets', 'link.liquid'))
  assert_eq(failure_code { Shop::ThemeFolder.check!(linked, mode: :pull) }, 'unsafe_folder', 'a folder with any symlink never reaches the copy')
  assert_eq(FC.list(DOMAIN).first.slice('id', 'path', 'files', 'bytes'), { 'id' => copy, 'path' => cdir, 'files' => 3, 'bytes' => 20 }, 'folder copy listed')
  assert_eq(failure_code { FC.create!(DOMAIN, report.merge('bytes' => 201 * 1024 * 1024)) }, 'folder_too_large', 'folder_too_large')
  # A copy that fails midway (a socket the walk would have refused, planted
  # after the check) removes its partial and is backup_failed.
  socky = home.theme_folder('socky')
  socket_report = Shop::ThemeFolder.check!(socky, mode: :pull)
  FileUtils.mkdir_p(File.join(socky, 'assets'))
  server = UNIXServer.new(File.join(socky, 'assets', 'live.sock'))
  assert_eq(failure_code { FC.create!(DOMAIN, socket_report) }, 'backup_failed', 'a socket in the copy is backup_failed')
  server.close
  assert(Dir.children(File.join(home.backups_dir, DOMAIN, 'local')).none? { |n| n.start_with?('.partial-') }, 'no .partial-* left in local/')
  7.times { |i| FileUtils.mkdir_p(File.join(home.backups_dir, DOMAIN, 'local', "150000000#{i}")) }
  Shop::Backups.prune!(DOMAIN)
  assert_eq(FC.list(DOMAIN).size, 5, '5 folder copies kept')

end
