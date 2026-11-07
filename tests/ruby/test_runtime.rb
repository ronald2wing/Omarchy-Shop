# Shop::Runtime: the pinned node + CLI lookup under mise's installs dir (pure), the node link, status and the upgrader-path refusal.

require_relative 'support'

R = Shop::Runtime

with_home do |home|
  ENV['HOME'] = home.dir
  Shop.override!(trusted_parent: home.dir)
  Shop::Paths.prepare!
  %w[MISE_DATA_DIR XDG_DATA_HOME].each { |k| ENV.delete(k) }

  assert_eq(R.installs_dir, home.installs, 'installs dir under ~/.local/share/mise')
  assert_eq(R.node_path, File.join(home.installs, 'node', Shop::NODE_PIN, 'bin', 'node'), 'pinned node path')
  located = R.locate
  assert_eq(located.node, R.node_path, 'locate finds the pinned pair')
  assert(located.run_js.end_with?("@shopify+cli@#{Shop::CLI_PIN}/node_modules/@shopify/cli/bin/run.js"), 'run.js under the .mise layout')
  assert_eq(R.status, { 'found' => true, 'missing' => nil, 'installs' => home.installs }, 'status object')
  link = File.join(home.state_dir, 'bin', 'node')
  assert(!File.exist?(link) && !File.symlink?(link), 'locate and status write nothing')

  R.ensure_node_link!(located)
  assert_eq(File.readlink(link), located.node, 'ensure_node_link! points bin/node at the pinned node')
  File.unlink(link)
  File.symlink('/usr/bin/false', link)
  R.ensure_node_link!(located)
  assert_eq(File.readlink(link), located.node, 'a wrong link is replaced atomically')
  assert_eq(Dir.children(File.join(home.state_dir, 'bin')), ['node'], 'no temp link left')

  # Trusted files: regular, owned by the uid or root, not world-writable.
  assert(R.trusted_file?(located.run_js) && R.trusted_file?(located.node, executable: true), 'the fakes are trusted')
  assert(!R.trusted_file?('/nonexistent'), 'missing -> untrusted')
  ww = home.path('ww.js')
  File.write(ww, '')
  File.chmod(0o666, ww)
  assert(!R.trusted_file?(ww), 'world-writable -> untrusted')
  assert(!R.trusted_file?(home.dir), 'a directory is not a file')
  assert(!R.trusted_file?(ww, executable: true) && R.trusted_file?('/usr/bin/true', executable: true), 'executable: needs the x bit')
  # Group-writable code is refused like a group-writable theme ancestor
  # (ThemeFolder.ancestor_reason uses the same 0o022 mask).
  gw = home.path('gw.js')
  File.write(gw, '')
  File.chmod(0o664, gw)
  assert(!R.trusted_file?(gw), 'group-writable -> untrusted')
  File.chmod(0o644, gw)
  assert(R.trusted_file?(gw), 'owner-writable only -> trusted')

  # The upgrader-path rule.
  assert(!R.upgrader_path?(located), 'the test layout is not an upgrader path')
  assert_eq(R.interactive_safe!(located), located, 'interactive_safe! returns the runtime')
  bunny = Shop::Runtime::Located.new(node: located.node, run_js: home.path('bunny', 'run.js'))
  assert(R.upgrader_path?(bunny), '"bun" in the path')
  assert_eq(failure_code { R.interactive_safe!(bunny) }, 'cli_failed', 'interactive calls refused on an upgrader path')
  FileUtils.mkdir_p(home.path('real-pnpm'))
  File.write(home.path('real-pnpm', 'run.js'), '')
  linked = Shop::Runtime::Located.new(node: located.node, run_js: home.path('clean', 'run.js'))
  FileUtils.mkdir_p(home.path('clean'))
  File.symlink(home.path('real-pnpm', 'run.js'), home.path('clean', 'run.js'))
  assert(R.upgrader_path?(linked), 'the realpath counts too')

  # The data dir follows MISE_DATA_DIR.
  other = home.path('other-mise')
  home.reinstall_under!(other)
  ENV['MISE_DATA_DIR'] = other
  assert_eq(R.locate.node, File.join(other, 'installs', 'node', Shop::NODE_PIN, 'bin', 'node'), 'MISE_DATA_DIR wins')
  assert_eq(R.status['installs'], File.join(other, 'installs'), 'status names the installs dir it searched')
  ENV.delete('MISE_DATA_DIR')
end

with_home(node: false) do |home|
  ENV['HOME'] = home.dir
  assert_eq(R.find, [nil, 'node'], 'no node -> missing node')
  assert_eq(R.status, { 'found' => false, 'missing' => 'node', 'installs' => home.installs }, 'status without node')
  begin
    R.locate
    assert(false, 'locate must raise')
  rescue Shop::Failure => e
    assert_eq([e.code, e.exit_code, e.to_error['missing']], ['cli_missing', 1, 'node'], 'cli_missing names the part')
    assert_eq(e.message, "node #{Shop::NODE_PIN} not found under mise's installs", 'the message names the missing pin')
  end
end

# A corrupt or loosely held runtime is a missing CLI (the Install
# call to action), never an internal error: a package.json that is not a
# JSON object with the pinned version, a group-writable run.js or node.
with_home do |home|
  ENV['HOME'] = home.dir
  run_js = R.locate.run_js
  pkg = File.join(File.dirname(File.dirname(run_js)), 'package.json')
  ['[1, 2]', JSON.generate(Shop::CLI_PIN), '42', 'null', 'true', '{"version": ', '', "\xFF\xFE{}".b,
   "#{'[' * 20}#{']' * 20}", JSON.generate({ 'version' => [Shop::CLI_PIN] })].each do |body|
    File.binwrite(pkg, body)
    assert_eq(R.find, [nil, 'cli'], "package.json #{body.inspect[0, 24]} -> missing cli")
    assert_eq(failure_code { R.locate }, 'cli_missing', "package.json #{body.inspect[0, 24]} -> locate raises cli_missing")
  end
  assert_eq(R.status.slice('found', 'missing'), { 'found' => false, 'missing' => 'cli' }, 'status names the cli')
  File.write(pkg, JSON.generate({ 'name' => '@shopify/cli', 'version' => Shop::CLI_PIN }))
  assert_eq(R.find[1], nil, 'a well-formed package.json is found again')

  File.unlink(run_js)
  FileUtils.cp(File.join(FIXTURE_BIN, 'fake-shopify'), run_js)
  File.chmod(0o774, run_js)
  assert_eq(R.find, [nil, 'cli'], 'a group-writable run.js -> missing cli')
  File.chmod(0o755, run_js)
  assert_eq(R.find[1], nil, 'the same run.js at 0755 is found')
  node = R.node_path
  File.unlink(node)
  FileUtils.cp(File.join(FIXTURE_BIN, 'fake-node'), node)
  File.chmod(0o775, node)
  assert_eq(R.find, [nil, 'node'], 'a group-writable node -> missing node')
  File.chmod(0o755, node)
  assert_eq(R.find[1], nil, 'the same node at 0755 is found')
end

with_home(cli: false) do |home|
  ENV['HOME'] = home.dir
  assert_eq(R.find, [nil, 'cli'], 'no cli -> missing cli')
  home.install_cli(version: '4.7.0')
  assert_eq(R.find, [nil, 'cli'], 'wrong version -> missing cli')
  # A shopify on PATH is never used.
  File.symlink(File.join(FIXTURE_BIN, 'fake-shopify'), File.join(home.sysbin, 'shopify'))
  assert_eq(R.status['found'], false, 'PATH shopify ignored')
  assert_eq(home.cli_log, [], 'nothing ran')
end
