# Shop::ThemeJob: the store lock from the theme list to retention, the target, the live gate before the backup, and the line fields at their moments (backupId after the backup, folderCopy after the copy, writeStarted right before the write).

require_relative 'support'

TJ = Shop::ThemeJob
HM = Shop::HelperMain
DOMAIN = 'alpha.myshopify.com'
LIVE = '160258293983'
UNPUBLISHED = '160258294001'

# Declare the theme writers' line fields in-process, as HelperMain.main
# does for push-theme/pull-theme/restore-backup, and read them back.
def declare_fields!
  HM.instance_variable_set(:@line_fields, { 'writeStarted' => false, 'backupId' => nil, 'folderCopy' => nil })
end

def fields = HM.instance_variable_get(:@line_fields).dup

with_home do |home|
  use_home(home)
  folder = home.theme_folder

  # live_gate!: a live target needs both the opt-in and the confirmation.
  live = { 'id' => LIVE, 'name' => 'Dawn', 'role' => 'live' }
  assert_eq(failure_code { TJ.live_gate!(live, allow_live: false, confirm_live: true) }, 'live_not_allowed', 'live needs the opt-in')
  assert_eq(failure_code { TJ.live_gate!(live, allow_live: true, confirm_live: false) }, 'live_not_confirmed', 'and the confirmation')
  assert(TJ.live_gate!(live, allow_live: true, confirm_live: true).nil?, 'both pass')
  assert(TJ.live_gate!(live.merge('role' => 'unpublished'), allow_live: false, confirm_live: false).nil?, 'a non-live target is never gated')

  # run: the block runs under the store lock and returns its value;
  # retention runs after it, under the same lock (an old partial goes).
  stale = File.join(home.backups_dir, DOMAIN, '.partial-1000000000-1')
  FileUtils.mkdir_p(stale)
  held = nil
  out = TJ.run(DOMAIN, helper: 'push-theme') do |job|
    held = failure_code { Shop::Lock.with(DOMAIN) { nil } }
    assert(File.directory?(stale), 'retention has not run while the block runs')
    assert_eq([job.domain, job.located.class], [DOMAIN, Shop::Runtime::Located], 'the job knows its store and runtime')
    :result
  end
  assert_eq([out, held], [:result, 'store_busy'], 'run returns the block value; the store is locked inside it')
  assert(!File.exist?(stale), 'retention ran after the block')
  assert(Shop::Lock.with(DOMAIN) { true }, 'and the lock is released')

  # target!: a fresh theme list, resolved.
  TJ.run(DOMAIN, helper: 'push-theme') do |job|
    assert_eq(job.target!('live')['id'], LIVE, 'target! resolves live')
    assert_eq(job.target!(UNPUBLISHED)['role'], 'unpublished', 'and an id')
    assert_eq(failure_code { job.target!('999') }, 'theme_not_found', 'an unknown id is theme_not_found')
  end

  # push_with_backup!: the gate comes before the backup.
  declare_fields!
  before = home.theme_calls.size
  code = failure_code do
    TJ.run(DOMAIN, helper: 'push-theme') do |job|
      job.push_with_backup!(job.target!('live'), before: 'push', allow_live: false, confirm_live: false) { raise 'never reached' }
    end
  end
  assert_eq(code, 'live_not_allowed', 'a refused live push fails at the gate')
  assert_eq(home.theme_calls.drop(before).map { |e| e['argv'][1] }, %w[list], 'only the theme list ran: no backup, no push')
  assert_eq(fields, { 'writeStarted' => false, 'backupId' => nil, 'folderCopy' => nil }, 'and no line field changed')

  # ... then the backup (backupId set before the recheck), then the push
  # (writeStarted set only after the recheck, before the push).
  declare_fields!
  seen = nil
  before = home.theme_calls.size
  id, pushed = TJ.run(DOMAIN, helper: 'push-theme') do |job|
    job.push_with_backup!(job.target!(UNPUBLISHED), before: 'push', allow_live: false, confirm_live: false) do
      seen = fields
      folder
    end
  end
  assert(id.end_with?("-#{UNPUBLISHED}") && seen['backupId'] == id && seen['writeStarted'] == false,
         "the recheck runs after the backup and before the write (#{seen})")
  assert_eq(fields.slice('writeStarted', 'backupId'), { 'writeStarted' => true, 'backupId' => id }, 'after the push both are set')
  assert_eq(pushed, { partial: false, issues: [] }, 'the push result')
  assert_eq(home.theme_calls.drop(before).map { |e| e['argv'][1] }, %w[list pull push], 'list, backup pull, push')
  assert(home.theme_calls.last['argv'].include?("--path=#{folder}"), 'the push takes the path the block returned')

  # A recheck that fails stops the job after the backup, before the write.
  declare_fields!
  code = failure_code do
    TJ.run(DOMAIN, helper: 'push-theme') do |job|
      job.push_with_backup!(job.target!(UNPUBLISHED), before: 'push', allow_live: false, confirm_live: false) do
        raise Shop::Failure.new('unsafe_folder', 'planted', reason: 'symlink')
      end
    end
  end
  assert_eq([code, fields['writeStarted']], ['unsafe_folder', false], 'a failed recheck leaves writeStarted false')
  assert(fields['backupId'], 'and names the backup it kept')

  # A push that fails after the write started keeps both fields.
  home.scenario!('push-fails')
  declare_fields!
  code = failure_code do
    TJ.run(DOMAIN, helper: 'push-theme') do |job|
      job.push_with_backup!(job.target!(UNPUBLISHED), before: 'push', allow_live: false, confirm_live: false) { folder }
    end
  end
  assert_eq([code, fields['writeStarted']], ['cli_failed', true], 'a failed push says the write started')
  assert(fields['backupId'], 'and names the backup')
  home.scenario!('ok')

  # pull_with_copy!: the folder copy (folderCopy set before the recheck),
  # then the pull; an empty folder needs no copy.
  declare_fields!
  seen = nil
  report = Shop::ThemeFolder.check!(folder, mode: :pull)
  copy, path = TJ.run(DOMAIN, helper: 'pull-theme') do |job|
    job.pull_with_copy!(job.target!(UNPUBLISHED), report) do
      seen = fields
      folder
    end
  end
  assert(copy.match?(/\A\d{10}\z/) && seen['folderCopy'] == copy && seen['writeStarted'] == false, "the copy comes first (#{seen})")
  assert_eq([path, fields['writeStarted'], fields['folderCopy']], [folder, true, copy], 'then the pull, after writeStarted')
  assert(File.directory?(File.join(home.backups_dir, DOMAIN, 'local', copy, 'layout')), 'the copy holds the theme dirs')
  empty = home.path('work', 'empty')
  FileUtils.mkdir_p(empty)
  declare_fields!
  copy, = TJ.run(DOMAIN, helper: 'pull-theme') do |job|
    job.pull_with_copy!(job.target!(UNPUBLISHED), Shop::ThemeFolder.check!(empty, mode: :pull)) { empty }
  end
  assert_eq([copy, fields['folderCopy'], fields['writeStarted']], [nil, nil, true], 'no copy of an empty folder')
end
