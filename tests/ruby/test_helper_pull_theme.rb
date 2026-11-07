# helpers/pull-theme: --nodelete and --force always, folder safety, folder copies, link warnings, writeStarted on every line and folderCopy on failure, the re-walk before the pull, lock.

require_relative 'support'

LIVE = '160258293983'
UNPUBLISHED = '160258294001'

with_home do |home|
  folder = home.theme_folder

  # toml-env: refused before any CLI call.
  toml = home.theme_folder('toml')
  File.write(File.join(toml, 'shopify.theme.toml'), "[environments.default]\npublish = true\n")
  before = home.cli_log.size
  status, out, = run_one('pull-theme', '--store=alpha', "--folder=#{toml}", "--target=#{UNPUBLISHED}", home: home)
  assert_eq([status, out['error']['code'], out['error']['reason']], [1, 'unsafe_folder', 'theme_toml'], 'toml refused')
  assert_eq(home.cli_log.size, before, 'the fake CLI logged zero calls for the toml folder')

  # The CLI finds shopify.theme.toml in any ancestor (find-up), so a
  # toml in the folder's parent or above the state dir refuses too.
  parent = home.path('work', 'mono')
  nested = File.join(parent, 'theme')
  FileUtils.mkdir_p(File.join(nested, 'layout'))
  FileUtils.mkdir_p(File.join(nested, 'templates'))
  File.write(File.join(parent, 'shopify.theme.toml'), "[environments.default]\npublish = true\n")
  before = home.cli_log.size
  status, out, = run_one('pull-theme', '--store=alpha', "--folder=#{nested}", "--target=#{UNPUBLISHED}", home: home)
  assert_eq([status, out['error']['code'], out['error']['reason']], [1, 'unsafe_folder', 'theme_toml'], 'parent toml refused')
  home_toml = home.path('shopify.theme.toml')
  File.write(home_toml, "[environments.default]\npublish = true\n")
  status, out, = run_one('pull-theme', '--store=alpha', "--folder=#{folder}", "--target=#{UNPUBLISHED}", home: home)
  assert_eq([status, out['error']['code'], out['error']['reason']], [1, 'unsafe_folder', 'theme_toml'], 'a toml in HOME (above the folder and the state dir) refused')
  File.unlink(home_toml)
  assert_eq(home.cli_log.size, before, 'zero CLI calls with an ancestor toml')

  # Every link, special file and toml trap is refused before any CLI call.
  assert_refuses_unsafe_folders(home, 'pull-theme', '--store=alpha', "--target=#{UNPUBLISHED}")
  File.write(File.join(folder, 'AGENTS.md'), "# agents\n")
  File.write(File.join(folder, 'DESIGN.md'), "# design\n")

  # Pull into a non-empty folder: folder copy first, then pull --nodelete.
  home.scenario!('ok')
  status, out, = run_one('pull-theme', '--store=alpha', "--folder=#{folder}", '--target=live', home: home)
  assert(status.zero? && out['folderCopy'].match?(/\A\d{10}\z/) && out['backupId'].nil?, "pull with folder copy (#{out})")
  copy = File.join(home.backups_dir, 'alpha.myshopify.com', 'local', out['folderCopy'])
  assert(File.directory?(File.join(copy, 'layout')), 'copy exists')
  assert_eq(%w[AGENTS.md DESIGN.md].map { |n| File.read(File.join(copy, n)) }, ["# agents\n", "# design\n"],
            'the top-level AGENTS.md/DESIGN.md the CLI pull overwrites are in the folder copy')
  assert_eq(home.theme_calls.last['argv'], ['theme', 'pull', '--store=alpha.myshopify.com', "--theme=#{LIVE}", "--path=#{folder}", '--nodelete', '--force', '--json', '--no-input'],
            'pull argv: resolved id, --nodelete, --force (the CLI\'s own folder prompt is redundant with the check and the folder copy)')
  # A theme folder that is a git checkout with uncommitted or untracked
  # changes: the pinned CLI refuses that under --no-input unless --force,
  # and it is exactly the folder a developer pulls remote edits into.
  dirty = home.theme_folder('dirty-git')
  FileUtils.mkdir_p(File.join(dirty, '.git'))
  File.write(File.join(dirty, '.git', 'config'), "[core]\n")
  File.write(File.join(dirty, 'notes.txt'), "untracked\n")
  File.write(File.join(dirty, 'layout', 'theme.liquid'), '<html>edited</html>')
  status, out, = run_one('pull-theme', '--store=alpha', "--folder=#{dirty}", '--target=live', home: home)
  assert_eq([status, out['ok']], [0, true], "a pull into a dirty git checkout succeeds (#{out})")
  assert(home.theme_calls.last['argv'].include?('--force') && File.read(File.join(dirty, 'layout', 'theme.liquid')).include?('content_for_layout'),
         'the pull ran with --force and wrote the folder')
  assert(File.file?(File.join(dirty, 'notes.txt')) && File.file?(File.join(dirty, '.git', 'config')), 'the checkout\'s own files are untouched')
  empty = home.path('work', 'empty')
  FileUtils.mkdir_p(empty)
  status, out, = run_one('pull-theme', '--store=alpha', "--folder=#{empty}", '--target=live', home: home)
  assert(status.zero? && out['folderCopy'].nil?, 'no copy for an empty folder')
  assert(File.file?(File.join(empty, 'layout', 'theme.liquid')), 'pulled files land in the folder')

  home.scenario!('pull-symlink')
  fresh = home.path('work', 'fresh')
  FileUtils.mkdir_p(fresh)
  status, out, = run_one('pull-theme', '--store=alpha', "--folder=#{fresh}", '--target=live', home: home)
  assert(status.zero? && out['warnings'] == [{ 'kind' => 'symlink', 'path' => 'sections/escape.liquid' }], "escaping link after pull is a warning object (#{out})")
  assert(File.symlink?(File.join(fresh, 'sections', 'escape.liquid')), 'and is not deleted')

  # A pull the CLI aborts mid-download is cli_failed with the CLI's words
  # (never a "partial" result: the pinned CLI's pull has no such status).
  home.scenario!('pull-aborts')
  partial_dir = home.path('work', 'partial')
  FileUtils.mkdir_p(partial_dir)
  status, out, = run_one('pull-theme', '--store=alpha', "--folder=#{partial_dir}", '--target=live', home: home)
  assert_eq([status, out['ok'], out['error']['code'], out['error']['message']],
            [1, false, 'cli_failed', 'Error fetching assets: sections/header.liquid'], "aborted pull (#{out})")
  assert(!out.key?('partial'), 'an aborted pull reports no partial result')
  assert_eq(out.slice('writeStarted', 'folderCopy'), { 'writeStarted' => true, 'folderCopy' => nil },
            'an aborted pull into an empty folder: started, no copy')


  # The per-store lock: a held lock is store_busy.
  lock_dir = File.join(home.state_dir, 'locks')
  holder = IO.popen([RUBY, '-e', "f = File.open(ARGV[0], File::RDWR | File::CREAT, 0o600); f.flock(File::LOCK_EX); puts 'held'; $stdout.flush; sleep 30",
                     File.join(lock_dir, 'alpha.myshopify.com.lock')])
  assert_eq(holder.gets&.strip, 'held', 'lock held')
  status, out, = run_one('pull-theme', '--store=alpha', "--folder=#{folder}", '--target=live', home: home)
  Process.kill(:KILL, holder.pid)
  holder.close
  assert_eq([status, out['error']['code']], [1, 'store_busy'], 'store_busy')
  assert(out['writeStarted'] == false && out.key?('folderCopy') && out['folderCopy'].nil?, "a held lock fails before the theme list: nothing touched, no copy (#{out})")

  # Usage: a pull takes no live flags.
  [['--store=alpha', "--folder=#{folder}", '--target=live', '--allow-live'],
   ['--store=alpha', "--folder=#{folder}", '--target=live', '--confirm-live'],
   ['--action=pull', '--store=alpha', "--folder=#{folder}", '--target=live'],
   ['--store=alpha', '--target=live']].each do |args|
    status, out, = run_one('pull-theme', *args, home: home)
    assert_eq([status, out['error']['code']], [1, 'invalid_argument'], "usage #{args}")
  end
end


# A link planted in the folder during `theme list` (after the first walk) is
# caught by the re-walk right before the pull: refused, and nothing is written
# through it.
with_home(scenario: 'slow-ok') do |home|
  folder = home.theme_folder
  outside = home.path('outside.txt')
  File.write(outside, 'ORIGINAL SECRET')
  th = Thread.new { run_one('pull-theme', '--store=alpha', "--folder=#{folder}", '--target=live', home: home) }
  sleep 0.6
  FileUtils.mkdir_p(File.join(folder, 'sections'))
  File.symlink(outside, File.join(folder, 'sections', 'header.liquid'))
  status, out, = th.value
  assert_eq([status, out['error']['code'], out['error']['reason']], [1, 'unsafe_folder', 'symlink'], 'pull race: link refused')
  assert_eq(File.read(outside), 'ORIGINAL SECRET', 'pull race: outside file untouched')
  assert(home.theme_calls.none? { |e| e['argv'][1] == 'pull' }, 'pull race: no theme pull spawned')
end

# A pull stopped (TERM, the panel's cancel) says whether the folder could have
# been touched: during `theme list` nothing was (writeStarted false, no copy);
# during the CLI pull the failure names the folder copy taken first.
def term_pull(home, folder, scenario)
  term_helper(home, scenario, 'pull-theme', '--store=alpha', "--folder=#{folder}", '--target=live')
end

with_home do |home|
  folder = home.theme_folder
  out = term_pull(home, folder, 'hang')
  assert_eq([out['ok'], out['error']['code']], [false, 'terminated'], "TERM during theme list (#{out})")
  assert_eq(out.slice('writeStarted', 'folderCopy'), { 'writeStarted' => false, 'folderCopy' => nil }, 'TERM during theme list: nothing touched, no copy')
  out = term_pull(home, folder, 'hang-on:pull')
  assert_eq(out['error']['code'], 'terminated', "TERM during the CLI pull (#{out})")
  assert_eq(out['writeStarted'], true, 'TERM during the CLI pull: files may be replaced')
  assert(out['folderCopy'].to_s.match?(/\A\d{10}\z/), "TERM during the CLI pull names the folder copy (#{out})")
  assert(File.directory?(File.join(home.backups_dir, 'alpha.myshopify.com', 'local', out['folderCopy'])) ||
         Dir.glob(File.join(home.backups_dir, '**', out['folderCopy'])).any?, 'and the copy is on disk')
end
