# FakeHome: the throwaway HOME every test runs Shop in. support.rb loads it
# for the Ruby tests; tests/qml/fake-home.sh runs it (`ruby --disable-gems
# tests/ruby/fake_home.rb <home>`) to fill a smoke's HOME the same way.

require 'tmpdir'
require 'fileutils'
require 'json'

require_relative '../../lib/shop'

FIXTURES = File.join(Shop::ROOT, 'tests', 'fixtures')
FIXTURE_BIN = File.join(FIXTURES, 'bin')

# A throwaway HOME holding the pinned layout (fake node + fake CLI under
# mise's installs dir), a canary npm next to the node and an empty system
# PATH dir, plus the fakes' logs. `dir:` fills an existing dir instead of
# a fresh mktemp one.
class FakeHome
  attr_reader :dir

  # The dirs a theme-shaped folder holds (the CLI needs config, layout and
  # templates; sections and snippets make it look like a real theme).
  THEME_DIRS = %w[layout templates config sections snippets].freeze

  # Make `folder` theme-shaped, with a layout and an index template.
  def self.scaffold_theme(folder)
    THEME_DIRS.each { |d| FileUtils.mkdir_p(File.join(folder, d)) }
    File.write(File.join(folder, 'layout', 'theme.liquid'), '<html></html>')
    File.write(File.join(folder, 'templates', 'index.json'), '{}')
    folder
  end

  def initialize(scenario: 'ok', node: true, cli: true, dir: nil)
    @dir = dir ? existing_dir(dir) : fresh_dir
    FileUtils.mkdir_p(sysbin)
    install_node if node
    install_cli if cli
    scenario!(scenario)
  end

  def path(*parts) = File.join(@dir, *parts)
  def sysbin = path('sysbin')
  def installs = @installs || path('.local', 'share', 'mise', 'installs')

  # Re-install node + CLI under another mise data dir (MISE_DATA_DIR).
  def reinstall_under!(data_dir)
    @installs = File.join(data_dir, 'installs')
    install_node
    install_cli
  end
  def state_dir = path('.local', 'state', 'shop')
  def backups_dir = File.join(state_dir, 'backups')
  def run_dir = File.join(state_dir, 'run')

  def install_node
    bin = File.join(installs, 'node', Shop::NODE_PIN, 'bin')
    FileUtils.mkdir_p(bin)
    File.symlink(File.join(FIXTURE_BIN, 'fake-node'), File.join(bin, 'node'))
    # mise's node bin dir also holds npm; Shop must never put it on PATH.
    File.symlink(File.join(FIXTURE_BIN, 'fake-npm'), File.join(bin, 'npm'))
  end

  # @shopify/cli as `mise install npm:@shopify/cli@<pin>` lays it out.
  def install_cli(version: Shop::CLI_PIN)
    pkg = File.join(installs, 'npm-shopify-cli', Shop::CLI_PIN, 'node_modules', '.mise', "@shopify+cli@#{Shop::CLI_PIN}",
                    'node_modules', '@shopify', 'cli')
    FileUtils.mkdir_p(File.join(pkg, 'bin'))
    File.symlink(File.join(FIXTURE_BIN, 'fake-shopify'), File.join(pkg, 'bin', 'run.js'))
    File.write(File.join(pkg, 'package.json'), JSON.generate({ 'name' => '@shopify/cli', 'version' => version }))
  end

  def scenario!(value)
    FileUtils.mkdir_p(path('.fake-shopify'))
    File.write(path('.fake-shopify', 'scenario'), value)
  end

  # Write config.json (version 2, alerts off) with `stores`, each
  # {domain, label, showInBar[, theme]}.
  def write_config!(stores, poll_seconds: 60)
    FileUtils.mkdir_p(path('.config', 'shop'))
    config = { 'version' => 2, 'pollSeconds' => poll_seconds, 'alerts' => { 'notify' => false, 'sound' => false },
               'bar' => { 'display' => 'stores' }, 'stores' => stores }
    File.write(path('.config', 'shop', 'config.json'), "#{JSON.pretty_generate(config)}\n")
  end

  # The smokes' HOME: the dirs Shop expects, and three stores in the bar,
  # each linked to a theme-shaped folder (live target, live changes off).
  def fill_for_smokes!
    [path('.config', 'shop'), path('.local', 'state'), path('.cache')].each { |d| FileUtils.mkdir_p(d) }
    write_config!(%w[acme beta gamma].map do |name|
      { 'domain' => "#{name}.myshopify.com", 'label' => name.capitalize, 'showInBar' => true,
        'theme' => { 'folder' => theme_folder(name), 'target' => 'live', 'allowLive' => false } }
    end)
  end

  def jsonl(*parts)
    file = path(*parts)
    File.exist?(file) ? File.readlines(file).map { |l| JSON.parse(l) } : []
  end

  def cli_log = jsonl('.fake-shopify', 'log.jsonl')
  def queries = jsonl('.fake-shopify', 'queries.jsonl')
  def pids = jsonl('.fake-shopify', 'pids')
  def upgrades = jsonl('.fake-shopify', 'upgrade.jsonl')
  def npm_log = jsonl('.fake-npm.log')
  def mise_log = jsonl('.fake-mise', 'log.jsonl')
  def tool_log(name) = jsonl('.fake-tools', "#{name}.jsonl")

  def theme_calls
    cli_log.select { |e| e['argv'].first == 'theme' }
  end

  # A theme-shaped folder outside the plugin, state and config dirs.
  def theme_folder(name = 'theme') = FakeHome.scaffold_theme(path('work', name))

  def cleanup
    pids.each do |entry|
      entry.each_value do |pid|
        Process.kill(:KILL, pid)
      rescue SystemCallError
        nil
      end
    end
    FileUtils.rm_rf(@dir)
  end

  private

  # Never a path the CLI's auto-upgrade would read as yarn/pnpm/bun.
  def fresh_dir
    loop do
      dir = File.realpath(Dir.mktmpdir('shop-test-'))
      return dir unless dir.downcase.match?(Shop::Runtime::UPGRADER_RE)

      FileUtils.rm_rf(dir)
    end
  end

  def existing_dir(dir)
    FileUtils.mkdir_p(dir)
    real = File.realpath(dir)
    raise ArgumentError, "#{real} spells yarn, pnpm or bun, where Shop refuses the CLI" if real.downcase.match?(Shop::Runtime::UPGRADER_RE)

    real
  end
end

# `ruby --disable-gems tests/ruby/fake_home.rb <home>`: fill <home> for a
# smoke. mise's data dir must be the one under <home> (the caller sets
# MISE_DATA_DIR and XDG_DATA_HOME there, or leaves them unset), so the
# links never land in a real mise install.
if $PROGRAM_NAME == __FILE__
  home = ARGV.fetch(0) { abort 'usage: fake_home.rb <home>' }
  abort "fake_home.rb: #{home} must be absolute" unless home.start_with?('/')
  data = File.join(home, '.local', 'share')
  { 'XDG_DATA_HOME' => data, 'MISE_DATA_DIR' => File.join(data, 'mise') }.each do |key, want|
    abort "fake_home.rb: #{key} must be #{want} or unset" unless ENV.fetch(key, want) == want
  end
  begin
    FakeHome.new(dir: home).fill_for_smokes!
  rescue ArgumentError => e
    abort "fake_home.rb: #{e.message}"
  end
end
