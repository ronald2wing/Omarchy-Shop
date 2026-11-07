# helpers/inspect-folder: local only (no child processes, no state written), the output keys, root files, UTF-8 paths (the reasons are test_theme_folder.rb's).

require_relative 'support'

with_home do |home|
  folder = home.theme_folder
  status, out, = run_one('inspect-folder', "--folder=#{folder}", home: home)
  assert_eq([status, out], [0, { 'ok' => true, 'exists' => true, 'themeShaped' => true, 'empty' => false,
                                 'safe' => true, 'reason' => nil, 'rootFiles' => [] }], 'a theme folder')
  # The top-level files the pinned CLI pushes too are named, so the push dialogs can say so.
  File.write(File.join(folder, 'AGENTS.md'), "private notes\n")
  status, out, = run_one('inspect-folder', "--folder=#{folder}", home: home)
  assert_eq([status, out['rootFiles']], [0, ['AGENTS.md']], 'rootFiles lists AGENTS.md')
  File.write(File.join(folder, 'DESIGN.md'), "d\n")
  assert_eq(run_one('inspect-folder', "--folder=#{folder}", home: home)[1]['rootFiles'], %w[AGENTS.md DESIGN.md], 'both root files')
  File.delete(File.join(folder, 'AGENTS.md'), File.join(folder, 'DESIGN.md'))
  # A UTF-8 folder name under a C locale.
  utf = home.theme_folder('thème')
  status, out, = run_one('inspect-folder', "--folder=#{utf}", home: home, env: { 'LANG' => 'C', 'LC_ALL' => 'C' })
  assert_eq([status, out['exists'], out['safe']], [0, true, true], 'a UTF-8 path is read as UTF-8 under LANG=C')
  status, out, = run_one('inspect-folder', home: home)
  assert_eq([status, out['error']['code']], [1, 'invalid_argument'], 'missing --folder')
  assert_eq(home.cli_log, [], 'no CLI call')
  assert(!File.exist?(home.state_dir), 'no state written')
end
