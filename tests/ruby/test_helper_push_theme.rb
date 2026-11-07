# helpers/push-theme: live gating, backups first, --nodelete always, folder safety, warning objects, backupId on failure, lock.

require_relative 'support'

FORBIDDEN = %w[--publish --allow-mutations --theme-editor-sync --notify --open --password -e --environment -p -d --development].freeze
LIVE = '160258293983'
UNPUBLISHED = '160258294001'

def flags(argv) = argv.map { |a| a.split('=', 2).first }

with_home do |home|
  folder = home.theme_folder

  # Push to an unpublished theme: backup of the target, then push --nodelete.
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", "--target=#{UNPUBLISHED}", home: home)
  assert_eq(status, 0, "push ok (#{out})")
  assert_eq(out.keys, %w[ok theme folder backupId warnings partial writeStarted], 'result keys')
  assert_eq(out.slice('ok', 'folder', 'warnings', 'partial'),
            { 'ok' => true, 'folder' => folder, 'warnings' => [], 'partial' => false }, 'push result')
  assert_eq(out['theme'], { 'id' => UNPUBLISHED, 'name' => 'Dawn copy', 'role' => 'unpublished' }, 'resolved theme')
  assert(out['backupId'].end_with?("-#{UNPUBLISHED}"), 'backup of the target')
  meta = JSON.parse(File.read(File.join(home.backups_dir, 'alpha.myshopify.com', out['backupId'], 'meta.json')))
  assert_eq(meta['before'], 'push', 'the backup says before: push')
  calls = home.theme_calls.map { |e| e['argv'] }
  assert_eq(calls.map { |a| a[1] }, %w[list pull push], 'list, backup pull, push')
  push = calls.last
  assert_eq(push, ['theme', 'push', '--store=alpha.myshopify.com', "--theme=#{UNPUBLISHED}", "--path=#{folder}", '--nodelete', '--json', '--no-input'],
            'push argv (the CLI gets --path; no --allow-live for a non-live target)')
  assert(calls.flatten.none? { |a| FORBIDDEN.include?(a.split('=', 2).first) }, 'no forbidden flags')

  # Live gating: refused before any backup or push.
  before = home.theme_calls.size
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", '--target=live', home: home)
  assert_eq([status, out['error']['code']], [1, 'live_not_allowed'], 'live without --allow-live')
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", '--target=live', '--allow-live', home: home)
  assert_eq([status, out['error']['code']], [1, 'live_not_confirmed'], 'live without --confirm-live')
  assert_eq(home.theme_calls.size - before, 2, 'only theme list ran for the refused live pushes')
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", '--target=live', '--allow-live', '--confirm-live', home: home)
  assert(status.zero? && out['theme']['role'] == 'live', 'confirmed live push')
  assert_eq(flags(home.theme_calls.last['argv']).last(4), %w[--nodelete --json --no-input --allow-live], '--allow-live only for the live target')
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", "--target=#{LIVE}", home: home)
  assert_eq(out['error']['code'], 'live_not_allowed', 'a numeric id resolving to the live theme is gated too')

  # A failed backup aborts: nothing is pushed, no backupId on the line.
  home.scenario!('pull-fails')
  before = home.theme_calls.size
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", "--target=#{UNPUBLISHED}", home: home)
  assert_eq([status, out['error']['code'], out['backupId']], [1, 'backup_failed', nil], 'backup_failed')
  assert(home.theme_calls.drop(before).none? { |e| e['argv'][1] == 'push' }, 'no push after a failed backup')
  # ... and so does a backup pull the CLI aborts mid-download (error JSON,
  # exit 1, some files written): a half-written tree is no safety net, so
  # the push never runs and no backup is recorded.
  home.scenario!('pull-aborts')
  before = home.theme_calls.size
  listed = run_one('list-backups', '--store=alpha', home: home)[1]['backups'].size
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", "--target=#{UNPUBLISHED}", home: home)
  assert_eq([status, out['error']['code'], out['backupId']], [1, 'backup_failed', nil], "an aborted backup pull is backup_failed (#{out})")
  assert(out['error']['message'].include?('Error fetching assets: sections/header.liquid'), "the failure names the file (#{out})")
  assert(home.theme_calls.drop(before).none? { |e| e['argv'][1] == 'push' }, 'no push after an aborted backup')
  assert_eq(run_one('list-backups', '--store=alpha', home: home)[1]['backups'].size, listed, 'the incomplete backup is not listed')


  # toml-env: refused before any CLI call.
  home.scenario!('ok')
  toml = home.theme_folder('toml')
  File.write(File.join(toml, 'shopify.theme.toml'), "[environments.default]\npublish = true\n")
  before = home.cli_log.size
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{toml}", "--target=#{UNPUBLISHED}", home: home)
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
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{nested}", "--target=#{UNPUBLISHED}", home: home)
  assert_eq([status, out['error']['code'], out['error']['reason']], [1, 'unsafe_folder', 'theme_toml'], 'parent toml refused')
  home_toml = home.path('shopify.theme.toml')
  File.write(home_toml, "[environments.default]\npublish = true\n")
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", "--target=#{UNPUBLISHED}", home: home)
  assert_eq([status, out['error']['code'], out['error']['reason']], [1, 'unsafe_folder', 'theme_toml'], 'a toml in HOME (above the folder and the state dir) refused')
  File.unlink(home_toml)
  assert_eq(home.cli_log.size, before, 'zero CLI calls with an ancestor toml')

  # Every link, special file and toml trap is refused before any CLI call.
  assert_refuses_unsafe_folders(home, 'push-theme', '--store=alpha', "--target=#{UNPUBLISHED}")

  home.scenario!('push-partial')
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", "--target=#{UNPUBLISHED}", home: home)
  assert(status.zero? && out['partial'] == true &&
         out['warnings'] == [{ 'kind' => 'issue', 'path' => 'sections/header.liquid', 'message' => 'Liquid syntax error' }], "partial push (#{out})")

  # A push that fails outright keeps the CLI's per-file reasons and names the
  # backup that was taken, which is complete on disk.
  home.scenario!('push-fails')
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", "--target=#{UNPUBLISHED}", home: home)
  assert_eq([status, out['ok'], out['error']['code']], [1, false, 'cli_failed'], "failed push is cli_failed (#{out})")
  assert(out['details'].first == 'sections/a.liquid: Liquid syntax error', "failed push details carry the issue (#{out['details']})")
  assert(out['details'].include?("The theme 'Dawn' could not be pushed."), 'and the message')
  assert(out['backupId'].to_s.match?(/\A\d{10}-#{UNPUBLISHED}\z/), "the failure line carries the backupId (#{out})")
  bdir = File.join(home.backups_dir, 'alpha.myshopify.com', out['backupId'])
  assert(File.file?(File.join(bdir, 'meta.json')) && File.file?(File.join(bdir, 'files', 'layout', 'theme.liquid')),
         'the named backup is complete')
  assert_eq(run_one('list-backups', '--store=alpha', home: home)[1]['backups'].first['id'], out['backupId'], 'and listed first')

  # A push the CLI refuses (status "skipped", reason "unsafe-directory", exit 0) fails after the backup,
  # so the failure line still names the backup that was kept.
  home.scenario!('push-skipped')
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", "--target=#{UNPUBLISHED}", home: home)
  assert_eq([status, out['ok'], out['error']['code']], [1, false, 'cli_failed'], "skipped push is cli_failed (#{out})")
  assert(out['error']['message'].include?('skipped'), 'and says the CLI skipped it')
  assert(out['backupId'].to_s.match?(/\A\d{10}-#{UNPUBLISHED}\z/), "the skipped-push failure line carries the backupId (#{out})")
  sdir = File.join(home.backups_dir, 'alpha.myshopify.com', out['backupId'])
  assert(File.file?(File.join(sdir, 'meta.json')) && File.file?(File.join(sdir, 'files', 'layout', 'theme.liquid')),
         'the backup before a skipped push is complete')

  # A push that uploads nothing (status "success", changed: false) is a
  # successful push, backup and all.
  home.scenario!('push-unchanged')
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", "--target=#{UNPUBLISHED}", home: home)
  assert_eq([status, out['ok']], [0, true], "an unchanged push succeeds (#{out})")
  assert(out['backupId'].to_s.match?(/\A\d{10}-#{UNPUBLISHED}\z/) && Array(out['warnings']).empty?, "with its backupId and no issues (#{out})")

  # A failure naming templates/customers/login.liquid (in every theme) or a
  # proxy's authentication is a CLI failure, never a signed-out account.
  home.scenario!('push-login-liquid')
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", "--target=#{UNPUBLISHED}", home: home)
  assert_eq([status, out['error']['code']], [1, 'cli_failed'], "login.liquid failure is cli_failed, not signed_out (#{out})")

  { 'admin-401-theme' => [1, 'theme_session_expired'], 'not-staff' => [1, 'cli_failed'],
    'paused' => [1, 'store_unavailable'], 'throttled' => [1, 'rate_limited'] }.each do |sc, (code, name)|
    home.scenario!(sc)
    status, out, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", "--target=#{UNPUBLISHED}", home: home)
    assert_eq([status, out['error']['code']], [code, name], "#{sc} -> #{name}")
    assert(out['details'].nil? || (out['details'].is_a?(Array) && out['details'].size <= 20), 'details list, when any, is bounded')
  end

  home.scenario!('ok')
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", '--target=999', home: home)
  assert_eq([status, out['error']['code']], [1, 'theme_not_found'], 'unknown theme id')

  # The per-store lock: a held lock is store_busy.
  lock_dir = File.join(home.state_dir, 'locks')
  holder = IO.popen([RUBY, '-e', "f = File.open(ARGV[0], File::RDWR | File::CREAT, 0o600); f.flock(File::LOCK_EX); puts 'held'; $stdout.flush; sleep 30",
                     File.join(lock_dir, 'alpha.myshopify.com.lock')])
  assert_eq(holder.gets&.strip, 'held', 'lock held')
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", "--target=#{UNPUBLISHED}", home: home)
  Process.kill(:KILL, holder.pid)
  holder.close
  assert_eq([status, out['error']['code']], [1, 'store_busy'], 'store_busy')

  # Usage.
  [['--action=push', '--store=alpha', "--folder=#{folder}", '--target=live'],
   ['--store=alpha', "--folder=#{folder}", '--target=1 --allow-live'],
   ['--store=alpha', '--target=live']].each do |args|
    status, out, = run_one('push-theme', *args, home: home)
    assert_eq([status, out['error']['code']], [1, 'invalid_argument'], "usage #{args}")
  end
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{home.dir}", '--target=live', home: home)
  assert_eq([status, out['error']['reason']], [1, 'home'], '$HOME refused')
  # A UTF-8 folder under a C locale.
  utf = home.theme_folder('thème')
  status, out, = run_one('push-theme', '--store=alpha', "--folder=#{utf}", "--target=#{UNPUBLISHED}", home: home, env: { 'LANG' => 'C', 'LC_ALL' => 'C' })
  assert_eq([status, out['folder']], [0, utf], "a UTF-8 folder path works under LANG=C (#{out})")
  assert(home.theme_calls.last['argv'].include?("--path=#{utf}"), 'and reaches the CLI intact')
end

# writeStarted on every line: false while the theme is provably untouched
# (a refusal, a failed backup, a stop during the theme list or the backup
# pull), true once the CLI push has begun (a stop or failure from then on).
with_home do |home|
  folder = home.theme_folder
  args = ['--store=alpha', "--folder=#{folder}", "--target=#{UNPUBLISHED}"]
  status, out, = run_one('push-theme', '--store=alpha', home: home)
  assert_eq([status, out['error']['code'], out['writeStarted']], [1, 'invalid_argument', false], "a usage error: writeStarted false (#{out})")
  home.scenario!('pull-fails')
  _, out, = run_one('push-theme', *args, home: home)
  assert_eq([out['error']['code'], out['writeStarted']], ['backup_failed', false], "a failed backup: writeStarted false (#{out})")
  home.scenario!('push-fails')
  _, out, = run_one('push-theme', *args, home: home)
  assert_eq([out['error']['code'], out['writeStarted']], ['cli_failed', true], "a failed CLI push: writeStarted true (#{out})")
  out = term_helper(home, 'hang', 'push-theme', *args)
  assert_eq([out['error']['code'], out['writeStarted'], out['backupId']], ['terminated', false, nil], "TERM during the theme list: writeStarted false (#{out})")
  out = term_helper(home, 'hang-on:pull', 'push-theme', *args)
  assert_eq([out['error']['code'], out['writeStarted'], out['backupId']], ['terminated', false, nil], "TERM during the backup pull: writeStarted false (#{out})")
  out = term_helper(home, 'hang-on:push', 'push-theme', *args)
  assert_eq([out['error']['code'], out['writeStarted']], ['terminated', true], "TERM during the CLI push: writeStarted true (#{out})")
  assert(out['backupId'].to_s.match?(/\A\d{10}-#{UNPUBLISHED}\z/), "and names the backup (#{out})")
end
