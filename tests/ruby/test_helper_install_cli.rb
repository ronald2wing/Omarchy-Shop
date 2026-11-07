# helpers/install-cli with fake-mise: consent, no `mise use`, no -g, forced registry env, verification.

require_relative 'support'

MISE = File.join(FIXTURE_BIN, 'fake-mise')

with_home(node: false, cli: false) do |home|
  ov = { tools: { mise: MISE } }
  status, out, = run_one('install-cli', home: home, overrides: ov)
  assert(status == 1 && out['error']['code'] == 'consent_required', 'no --consent -> consent_required')
  status, out, = run_one('install-cli', '--consent=yes', home: home, overrides: ov)
  assert(status == 1 && out['error']['code'] == 'consent_required', 'wrong consent -> consent_required')
  status, out, = run_one('install-cli', '--consent=install', home: home, overrides: { tools: { mise: '/nonexistent/mise' } })
  assert(status == 1 && out['error']['code'] == 'mise_missing', 'no mise -> mise_missing')
  assert_eq(home.mise_log, [], 'nothing ran without consent')

  FileUtils.mkdir_p(home.path('.fake-mise'))
  File.write(home.path('.fake-mise', 'scenario'), "fail:node@#{Shop::NODE_PIN}")
  status, out, = run_one('install-cli', '--consent=install', home: home, overrides: ov)
  assert(status == 1 && out['error']['code'] == 'tool_failed' && out['error']['message'] == "mise install failed: mise ERROR failed to install node@#{Shop::NODE_PIN}",
         "a failing mise step is tool_failed (never the CLI's), naming the last mise line (#{out})")
  assert_eq(out['details'], ["mise ERROR failed to install node@#{Shop::NODE_PIN}"], "and mise's lines are its details")
  File.write(home.path('.fake-mise', 'scenario'), 'ok')
  File.truncate(home.path('.fake-mise', 'log.jsonl'), 0)

  status, out, = run_one('install-cli', '--consent=install', home: home, overrides: ov)
  assert_eq(status, 0, "install succeeds (#{out})")
  assert_eq(out, { 'ok' => true }, 'install output')
  argvs = home.mise_log.map { |e| e['argv'] }
  node_spec = "node@#{Shop::NODE_PIN}"
  cli_spec = "npm:@shopify/cli@#{Shop::CLI_PIN}"
  assert_eq(argvs, [['install', node_spec], ['exec', node_spec, '--', MISE, 'install', cli_spec], ['install', cli_spec]], 'exactly the two documented commands (exec runs the inner install)')
  assert(argvs.flatten.none? { |a| %w[use -g --global].include?(a) }, 'never `use`, never -g')
  env = home.mise_log.first['env']
  assert_eq(env.slice('npm_config_registry', 'npm_config_strict_ssl', 'MISE_YES', 'MISE_NPM_PACKAGE_MANAGER', 'CI', 'MISE_EXEC_AUTO_INSTALL'),
            { 'npm_config_registry' => 'https://registry.npmjs.org/', 'npm_config_strict_ssl' => 'true', 'MISE_YES' => '1',
              'MISE_NPM_PACKAGE_MANAGER' => 'npm', 'CI' => '1', 'MISE_EXEC_AUTO_INSTALL' => '0' }, 'forced install env')
  assert(!File.exist?(home.path('.config', 'mise')), '~/.config/mise was never created')
  assert_eq(home.cli_log.last['argv'], %w[version --no-input], 'verification runs `version`')
end
