# helpers/list-backups: completed backups and folder copies, newest first, with before/files/bytes per row; read-only.

require_relative 'support'

with_home do |home|
  status, out, = run_one('list-backups', '--store=alpha', home: home)
  assert_eq([status, out], [0, { 'ok' => true, 'backups' => [], 'folderCopies' => [] }], 'no backups yet')
  base = File.join(home.backups_dir, 'alpha.myshopify.com')
  FileUtils.mkdir_p(File.join(base, '1762500000-160258293983', 'files'))
  File.write(File.join(base, '1762500000-160258293983', 'meta.json'),
             JSON.generate({ 'schema' => 2, 'domain' => 'alpha.myshopify.com', 'themeId' => '160258293983',
                             'themeName' => "Dawn\e[1m", 'role' => 'live', 'before' => 'restore', 'files' => 312, 'bytes' => 4_718_123 }))
  FileUtils.mkdir_p(File.join(base, '1762600000-160258294001', 'files'))
  File.write(File.join(base, '1762600000-160258294001', 'meta.json'),
             JSON.generate({ 'schema' => 2, 'domain' => 'alpha.myshopify.com', 'themeId' => '160258294001',
                             'themeName' => 'Dawn copy', 'role' => 'unpublished' }))
  FileUtils.mkdir_p(File.join(base, '1761000000')) # not a backup id: not listed
  FileUtils.mkdir_p(File.join(base, 'local', '1762400000', 'layout'))
  File.write(File.join(base, 'local', '1762400000', 'layout', 'theme.liquid'), 'abc')
  status, out, = run_one('list-backups', '--store=alpha', home: home)
  assert_eq(out['backups'], [
    { 'id' => '1762600000-160258294001', 'at' => 1_762_600_000_000, 'theme' => { 'id' => '160258294001', 'name' => 'Dawn copy', 'role' => 'unpublished' },
      'before' => 'push', 'files' => 0, 'bytes' => 0 },
    { 'id' => '1762500000-160258293983', 'at' => 1_762_500_000_000, 'theme' => { 'id' => '160258293983', 'name' => 'Dawn', 'role' => 'live' },
      'before' => 'restore', 'files' => 312, 'bytes' => 4_718_123 }
  ], 'backup rows: newest first, names cleaned, before defaults to push')
  assert_eq(out['folderCopies'], [{ 'id' => '1762400000', 'at' => 1_762_400_000_000, 'files' => 1, 'bytes' => 3,
                                   'path' => File.join(base, 'local', '1762400000') }], 'folder copies')
  assert_eq(home.cli_log, [], 'no CLI call')
  status, out, = run_one('list-backups', '--store=beta', home: home)
  assert_eq([status, out['backups'], out['folderCopies']], [0, [], []], 'another store: empty')
  status, out, = run_one('list-backups', home: home)
  assert_eq([status, out['error']['code']], [1, 'invalid_argument'], 'missing --store')
  status, out, = run_one('list-backups', '--store=alpha.myshopify.com.evil.tld', home: home)
  assert_eq([status, out['error']['code']], [1, 'invalid_argument'], 'bad domain')
end

with_home(cli: false) do |home|
  status, out, = run_one('list-backups', '--store=alpha', home: home)
  assert_eq([status, out['backups']], [0, []], 'listing needs no CLI')
end
