# Shop::Backups: atomic snapshot (files/ + meta.json with before/files/bytes), pass-through codes, find!, listing and retention.

require_relative 'support'

B = Shop::Backups
DOMAIN = 'alpha.myshopify.com'
THEME = { 'id' => '160258293983', 'name' => 'Dawn', 'role' => 'live' }.freeze

with_home do |home|
  use_home(home)
  located = Shop::Runtime.locate

  id = B.take!(located, DOMAIN, THEME, before: 'push', deadline: 20)
  assert(id.match?(/\A\d{10}-160258293983\z/), "backup id #{id}")
  dir = File.join(home.backups_dir, DOMAIN, id)
  meta = JSON.parse(File.read(File.join(dir, 'meta.json')))
  assert_eq(meta.slice('schema', 'domain', 'themeId', 'themeName', 'role', 'before'),
            { 'schema' => 2, 'domain' => DOMAIN, 'themeId' => '160258293983', 'themeName' => 'Dawn', 'role' => 'live', 'before' => 'push' },
            'meta.json')
  assert_eq([meta['files'], meta['bytes']], [4, 37 + 2 + 2 + 6], 'meta counts files and bytes')
  assert_eq(File.stat(File.join(dir, 'meta.json')).mode & 0o777, 0o600, 'meta.json is 0600')
  assert(File.file?(File.join(dir, 'files', 'layout', 'theme.liquid')) && !File.exist?(File.join(dir, 'files', 'meta.json')),
         'the pulled tree sits in files/, metadata beside it')
  pull = home.theme_calls.last['argv']
  epoch = id.split('-', 2).first # a fresh dir: the partial's start epoch is free
  assert(pull.include?('--nodelete') && pull.include?('--force') && pull.include?("--path=#{File.join(home.backups_dir, DOMAIN)}/.partial-#{epoch}-#{Process.pid}/files"),
         "pulls into the partial dir: #{pull} vs #{epoch} #{Process.pid}")
  assert(Dir.children(File.join(home.backups_dir, DOMAIN)).none? { |n| n.start_with?('.partial-') }, 'no partial left')
  assert_eq(B.find!(DOMAIN, id)[:meta]['themeId'], '160258293983', 'the snapshot passes dir!')
  restore_id = B.take!(located, DOMAIN, THEME, before: 'restore', deadline: 20)
  assert_eq(JSON.parse(File.read(File.join(home.backups_dir, DOMAIN, restore_id, 'meta.json')))['before'], 'restore', 'before: restore is recorded')
  assert(restore_id != id, 'a second snapshot in the same second gets the next epoch')

  # A failed pull aborts with backup_failed and leaves no partial.
  home.scenario!('pull-fails')
  assert_eq(failure_code { B.take!(located, DOMAIN, THEME, before: 'push', deadline: 20) }, 'backup_failed', 'backup_failed')
  assert(Dir.children(File.join(home.backups_dir, DOMAIN)).none? { |n| n.start_with?('.partial-') }, 'partial removed on failure')
  # A pull that throws mid-download (the pinned CLI prints its error and
  # exits 1 after writing some files; its pull result has no "partial"
  # status) is no backup: backup_failed, the half-written tree removed,
  # nothing listed, so the push or restore it guards never runs.
  listed = B.completed(DOMAIN).map { |b| b['id'] }
  home.scenario!('pull-aborts')
  begin
    B.take!(located, DOMAIN, THEME, before: 'push', deadline: 20)
    assert(false, 'an aborted pull must raise')
  rescue Shop::Failure => e
    assert_eq([e.code, e.exit_code], ['backup_failed', 1], 'an aborted pull is backup_failed')
    assert_eq(e.message, 'backup of Dawn failed: Error fetching assets: sections/header.liquid', 'the CLI error names the file')
  end
  assert_eq(B.completed(DOMAIN).map { |b| b['id'] }, listed, 'an aborted pull is never listed as a backup')
  assert(Dir.children(File.join(home.backups_dir, DOMAIN)).none? { |n| n.start_with?('.partial-') }, 'the half-written tree is removed')
  # Codes the user must see keep their own code (and their fields).
  home.scenario!('throttled')
  begin
    B.take!(located, DOMAIN, THEME, before: 'push', deadline: 20)
    assert(false, 'throttled must raise')
  rescue Shop::Failure => e
    assert_eq([e.code, e.extra[:retryAfter].is_a?(Integer)], ['rate_limited', true], 'rate_limited passes through with retryAfter')
  end
  { 'admin-401-theme' => 'theme_session_expired', 'not-staff' => 'backup_failed', 'paused' => 'store_unavailable' }.each do |scenario, code|
    home.scenario!(scenario)
    assert_eq(failure_code { B.take!(located, DOMAIN, THEME, before: 'push', deadline: 20) }, code, "#{scenario} -> #{code}")
  end
  home.scenario!('hang')
  assert_eq(failure_code { B.take!(located, DOMAIN, THEME, before: 'push', deadline: 0.3) }, 'timeout', 'timeout passes through')
  home.scenario!('server-error')
  assert_eq(failure_code { B.take!(located, DOMAIN, THEME, before: 'push', deadline: 20) }, 'backup_failed', 'a server error is backup_failed')
  assert(Dir.children(File.join(home.backups_dir, DOMAIN)).none? { |n| n.start_with?('.partial-') }, 'no partials after the failures')
  assert_eq(B::PASS_THROUGH.sort, %w[output_too_large rate_limited signed_out store_unavailable terminated
                                     theme_session_expired timeout unsafe_folder], 'the pass-through set')
  home.scenario!('ok')

  # Listing + retention: 12 backups -> 10 kept; stale partials go; fresh ones stay.
  base = File.join(home.backups_dir, DOMAIN)
  12.times do |i|
    bid = "17600000#{format('%02d', i)}-160258293983"
    FileUtils.mkdir_p(File.join(base, bid, 'files'))
    File.write(File.join(base, bid, 'meta.json'),
               JSON.generate({ 'schema' => 2, 'domain' => DOMAIN, 'themeId' => '160258293983',
                               'themeName' => "T#{i}", 'role' => 'unpublished', 'before' => i.even? ? 'push' : 'restore',
                               'files' => i, 'bytes' => i }))
  end
  FileUtils.mkdir_p(File.join(base, '1750000000-1', 'files')) # incomplete: no meta
  FileUtils.mkdir_p(File.join(base, '.partial-1000000000-1'))
  fresh_partial = File.join(base, ".partial-#{Time.now.to_i}-2")
  FileUtils.mkdir_p(fresh_partial)
  listed = B.completed(DOMAIN)
  assert_eq(listed.size, 14, 'all completed backups listed')
  assert_eq(listed.first['id'], restore_id, 'newest first')
  assert(listed.none? { |b| b['id'] == '1750000000-1' }, 'incomplete backups are not listed')
  assert_eq(listed.last, { 'id' => '1760000000-160258293983', 'at' => 1_760_000_000_000,
                                    'theme' => { 'id' => '160258293983', 'name' => 'T0', 'role' => 'unpublished' },
                                    'before' => 'push', 'files' => 0, 'bytes' => 0 }, 'backup row shape')
  assert_eq(listed[-2]['before'], 'restore', 'before: restore listed')
  odd = { 'schema' => 2, 'domain' => DOMAIN, 'themeId' => '1', 'themeName' => '', 'role' => 'LIVE', 'before' => 'x', 'files' => 'a' }
  assert_eq(B.row('1700000000-1', odd), { 'id' => '1700000000-1', 'at' => 1_700_000_000_000, 'theme' => { 'id' => '1', 'name' => 'Theme 1', 'role' => 'unknown' },
                                            'before' => 'push', 'files' => 0, 'bytes' => 0 }, 'row defaults for odd meta')
  keep = '1760000000-160258293983'
  B.prune!(DOMAIN, keep: [keep])
  left = B.completed(DOMAIN).map { |b| b['id'] }
  assert_eq(left.size, 11, '10 newest kept plus the protected one')
  assert(left.include?(keep) && left.include?(id), 'the protected and the newest survive')
  assert(!File.exist?(File.join(base, '1760000001-160258293983')), 'old backups pruned')
  assert(!File.exist?(File.join(base, '.partial-1000000000-1')) && File.exist?(fresh_partial), 'only stale partials pruned')

  # find!: a completed backup of this store with a clean tree.
  assert_eq(B.find!(DOMAIN, id)[:files], File.join(base, id, 'files'), 'a complete backup validates')
  assert_eq(failure_code { B.find!(DOMAIN, '1762500001-160258293983') }, 'backup_not_found', 'missing backup')
  assert_eq(failure_code { B.find!('beta.myshopify.com', id) }, 'backup_not_found', 'another store')
  assert_eq(failure_code { B.find!(DOMAIN, '../x') }, 'invalid_argument', 'bad id')
  File.symlink('/etc/hostname', File.join(base, id, 'files', 'layout', 'evil.liquid'))
  assert_eq(failure_code { B.find!(DOMAIN, id) }, 'backup_not_found', 'a backup containing a symlink is refused')
  File.unlink(File.join(base, id, 'files', 'layout', 'evil.liquid'))
  File.write(File.join(base, id, 'files', 'shopify.theme.toml'), '')
  assert_eq(failure_code { B.find!(DOMAIN, id) }, 'backup_not_found', 'a backup with a shopify.theme.toml is refused')
  File.unlink(File.join(base, id, 'files', 'shopify.theme.toml'))
  assert_eq(B.tree_reason(File.join(base, id, 'files')), nil, 'tree_reason nil for a clean tree')

  # stage!: the block fills a partial that becomes "<epoch><suffix>" only
  # when it returns; any exception removes it and propagates.
  stage_dir = home.path('stage')
  FileUtils.mkdir_p(stage_dir)
  staged = B.stage!(stage_dir, suffix: '-7') { |partial| File.write(File.join(partial, 'f'), 'x') }
  assert(staged.match?(/\A\d{10}-7\z/) && File.file?(File.join(stage_dir, staged, 'f')), "stage! renames the filled partial (#{staged})")
  [Shop::Failure.new('terminated', 'stop'), RuntimeError.new('crash'), Interrupt.new].each do |error|
    begin
      B.stage!(stage_dir) { |partial| File.write(File.join(partial, 'f'), 'x'); raise error }
    rescue Exception => e # rubocop:disable Lint/RescueException
      assert(e.equal?(error), "stage! propagates #{error.class}")
    end
    assert(Dir.children(stage_dir).none? { |n| n.start_with?('.partial-') }, "no partial left after #{error.class}")
  end
  again = B.stage!(stage_dir, suffix: '-7') { |_| nil }
  assert(again != staged && again.end_with?('-7'), 'a taken name moves to the next free epoch')
end
