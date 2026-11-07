# helpers/restore-backup: completed backups only, target = the backup's theme, fresh backup (before: restore) first, live gating, backupId on failure.

require_relative 'support'

UNPUBLISHED = '160258294001'

with_home do |home|
  folder = home.theme_folder
  _, pushed, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", "--target=#{UNPUBLISHED}", home: home)
  id = pushed['backupId']
  files = File.join(home.backups_dir, 'alpha.myshopify.com', id, 'files')

  status, out, = run_one('restore-backup', '--store=alpha', "--backup=#{id}", home: home)
  assert_eq(status, 0, "restore ok (#{out})")
  assert_eq(out.keys, %w[ok theme backupId warnings partial writeStarted], 'restore keys')
  assert_eq(out.slice('theme', 'warnings', 'partial'),
            { 'theme' => { 'id' => UNPUBLISHED, 'name' => 'Dawn copy', 'role' => 'unpublished' },
              'warnings' => [], 'partial' => false }, 'restore result')
  assert(out['backupId'] != id && out['backupId'].end_with?("-#{UNPUBLISHED}"), 'a fresh backup was taken first')
  fresh_meta = JSON.parse(File.read(File.join(home.backups_dir, 'alpha.myshopify.com', out['backupId'], 'meta.json')))
  assert_eq(fresh_meta['before'], 'restore', 'the fresh backup says before: restore')
  rows = run_one('list-backups', '--store=alpha', home: home)[1]['backups']
  assert_eq(rows.map { |r| r['before'] }, %w[restore push], 'list-backups shows both kinds')
  calls = home.theme_calls.last(3).map { |e| e['argv'] }
  assert_eq(calls.map { |a| a[1] }, %w[list pull push], 'list, fresh backup, push')
  assert_eq(calls.last, ['theme', 'push', '--store=alpha.myshopify.com', "--theme=#{UNPUBLISHED}", "--path=#{files}", '--nodelete', '--json', '--no-input'],
            'pushes files/ to the source theme with --nodelete')

  # A live backup needs both flags.
  _, live_push, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", '--target=live', '--allow-live', '--confirm-live', home: home)
  live_id = live_push['backupId']
  status, out, = run_one('restore-backup', '--store=alpha', "--backup=#{live_id}", home: home)
  assert_eq([status, out['error']['code']], [1, 'live_not_allowed'], 'live restore needs --allow-live')
  status, out, = run_one('restore-backup', '--store=alpha', "--backup=#{live_id}", '--allow-live', home: home)
  assert_eq([status, out['error']['code']], [1, 'live_not_confirmed'], 'and --confirm-live')
  status, out, = run_one('restore-backup', '--store=alpha', "--backup=#{live_id}", '--allow-live', '--confirm-live', home: home)
  assert(status.zero? && home.theme_calls.last['argv'].include?('--allow-live'), 'confirmed live restore')

  # A partial restore push (the pinned CLI exits 1 with a 'partial' body) is
  # a result with per-file warnings, not cli_failed.
  home.scenario!('push-partial')
  status, out, = run_one('restore-backup', '--store=alpha', "--backup=#{id}", home: home)
  assert(status.zero? && out['partial'] == true &&
         out['warnings'] == [{ 'kind' => 'issue', 'path' => 'sections/header.liquid', 'message' => 'Liquid syntax error' }],
         "partial restore (#{out})")

  # A fresh backup pull the CLI aborts mid-download stops the restore before
  # the push: backup_failed, no backupId, the source backup untouched.
  home.scenario!('pull-aborts')
  before = home.theme_calls.size
  status, out, = run_one('restore-backup', '--store=alpha', "--backup=#{id}", home: home)
  assert_eq([status, out['error']['code'], out['backupId']], [1, 'backup_failed', nil], "an aborted fresh backup is backup_failed (#{out})")
  assert(home.theme_calls.drop(before).none? { |e| e['argv'][1] == 'push' }, 'nothing restored after a partial backup')
  assert(File.file?(File.join(files, 'layout', 'theme.liquid')), 'the source backup is intact')

  # A push that fails after the fresh backup: the failure line names that backup.
  home.scenario!('push-fails')
  status, out, = run_one('restore-backup', '--store=alpha', "--backup=#{id}", home: home)
  assert_eq([status, out['ok'], out['error']['code']], [1, false, 'cli_failed'], "failed restore push (#{out})")
  assert(out['backupId'].to_s.match?(/\A\d{10}-#{UNPUBLISHED}\z/), "the failure line carries the fresh backupId (#{out})")
  assert(File.file?(File.join(home.backups_dir, 'alpha.myshopify.com', out['backupId'], 'meta.json')), 'and that backup is complete on disk')
  assert(out['details'].first.include?('sections/a.liquid'), 'details carry the per-file reason')
  assert_eq(out['writeStarted'], true, 'a failed CLI push: writeStarted true')

  # writeStarted on every line: false until the CLI push begins.
  home.scenario!('pull-fails')
  _, out, = run_one('restore-backup', '--store=alpha', "--backup=#{id}", home: home)
  assert_eq([out['error']['code'], out['writeStarted']], ['backup_failed', false], "a failed fresh backup: writeStarted false (#{out})")
  out = term_helper(home, 'hang', 'restore-backup', '--store=alpha', "--backup=#{id}")
  assert_eq([out['error']['code'], out['writeStarted'], out['backupId']], ['terminated', false, nil], "TERM during the theme list: writeStarted false (#{out})")
  out = term_helper(home, 'hang-on:pull', 'restore-backup', '--store=alpha', "--backup=#{id}")
  assert_eq([out['error']['code'], out['writeStarted'], out['backupId']], ['terminated', false, nil], "TERM during the fresh backup: writeStarted false (#{out})")
  out = term_helper(home, 'hang-on:push', 'restore-backup', '--store=alpha', "--backup=#{id}")
  assert_eq([out['error']['code'], out['writeStarted']], ['terminated', true], "TERM during the CLI push: writeStarted true (#{out})")
  assert(out['backupId'].to_s.match?(/\A\d{10}-#{UNPUBLISHED}\z/), "and names the fresh backup (#{out})")
  home.scenario!('ok')
  # A restore push the CLI skips (status "skipped") fails after the fresh
  # backup and names it too.
  home.scenario!('push-skipped')
  status, out, = run_one('restore-backup', '--store=alpha', "--backup=#{id}", home: home)
  assert_eq([status, out['ok'], out['error']['code']], [1, false, 'cli_failed'], "skipped restore push (#{out})")
  assert(out['backupId'].to_s.match?(/\A\d{10}-#{UNPUBLISHED}\z/), "the skipped-push failure line carries the fresh backupId (#{out})")
  assert(File.file?(File.join(home.backups_dir, 'alpha.myshopify.com', out['backupId'], 'meta.json')), 'and that backup is complete on disk')
  home.scenario!('ok')

  # The source theme is gone.
  gone = '1762500000-555'
  dir = File.join(home.backups_dir, 'alpha.myshopify.com', gone)
  FileUtils.mkdir_p(File.join(dir, 'files', 'layout'))
  File.write(File.join(dir, 'meta.json'), JSON.generate({ 'schema' => 2, 'domain' => 'alpha.myshopify.com',
                                                          'themeId' => '555' }))
  status, out, = run_one('restore-backup', '--store=alpha', "--backup=#{gone}", home: home)
  assert_eq([status, out['error']['code']], [1, 'theme_not_found'], 'theme_not_found')

  status, out, = run_one('restore-backup', '--store=alpha', '--backup=1700000000-1', home: home)
  assert_eq([status, out['error']['code']], [1, 'backup_not_found'], 'unknown backup')
  status, out, = run_one('restore-backup', '--store=alpha', '--backup=1761000000', home: home)
  assert_eq([status, out['error']['code']], [1, 'invalid_argument'], 'a bare epoch is not a backup id')
  status, = run_one('restore-backup', '--store=alpha', "--backup=#{id}", '--target=live', home: home)
  assert_eq(status, 1, 'the target is always the backup\'s own theme: no --target')
  File.symlink('/etc/hostname', File.join(files, 'layout', 'evil.liquid'))
  before = home.theme_calls.size
  status, out, = run_one('restore-backup', '--store=alpha', "--backup=#{id}", home: home)
  assert_eq([status, out['error']['code']], [1, 'backup_not_found'], 'a backup with a symlink is refused')
  assert_eq(home.theme_calls.size, before, 'before any CLI call')
  File.unlink(File.join(files, 'layout', 'evil.liquid'))

  # The theme-command codes on the fresh backup pull.
  { 'admin-401-theme' => [1, 'theme_session_expired'], 'not-staff' => [1, 'cli_failed'], 'pull-fails' => [1, 'backup_failed'] }.each do |sc, (code, name)|
    home.scenario!(sc)
    status, out, = run_one('restore-backup', '--store=alpha', "--backup=#{id}", home: home)
    assert_eq([status, out['error']['code'], out['backupId']], [code, name, nil], "#{sc} before the fresh backup -> #{name}, no backupId")
  end
end

# Retention after a restore never prunes the backup it restored from, even
# when that backup is the oldest past Backups::KEEP.
with_home do |home|
  folder = home.theme_folder
  _, pushed, = run_one('push-theme', '--store=alpha', "--folder=#{folder}", "--target=#{UNPUBLISHED}", home: home)
  base = File.join(home.backups_dir, 'alpha.myshopify.com')
  # Age the source backup so KEEP others fit between it and the fresh one.
  epoch = pushed['backupId'].split('-').first.to_i - 100
  id = "#{epoch}-#{UNPUBLISHED}"
  File.rename(File.join(base, pushed['backupId']), File.join(base, id))
  newer = (1..Shop::Backups::KEEP).map do |i|
    other = "#{epoch + i}-999"
    FileUtils.mkdir_p(File.join(base, other, 'files'))
    File.write(File.join(base, other, 'meta.json'), JSON.generate({ 'schema' => 2, 'domain' => 'alpha.myshopify.com', 'themeId' => '999' }))
    other
  end
  status, out, = run_one('restore-backup', '--store=alpha', "--backup=#{id}", home: home)
  assert_eq(status, 0, "restore ok (#{out})")
  left = Dir.children(base)
  assert(left.include?(id), 'the restored-from backup survives retention')
  assert(left.include?(out['backupId']), 'the fresh backup survives retention')
  assert_eq(newer.count { |b| left.include?(b) }, Shop::Backups::KEEP - 1, 'the oldest unprotected backup was pruned')
end
