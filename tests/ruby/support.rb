# Shared by the Ruby tests: the library, assert, the FakeHome (fake_home.rb), and a helper launcher.

require 'open3'
require 'tmpdir'
require 'fileutils'
require 'timeout'

require_relative '../../lib/shop'
require_relative 'fake_home'

# In-process tests point HOME at a FakeHome; mise's data dir follows
# MISE_DATA_DIR / XDG_DATA_HOME first, so the user's own values would find
# the real CLI and node instead of the fakes.
%w[MISE_DATA_DIR XDG_DATA_HOME].each { |k| ENV.delete(k) }

ROOT = Shop::ROOT
LAUNCHER = File.join(__dir__, 'launcher.rb')
RUBY = '/usr/bin/ruby'
# 2026-11-07 15:00 UTC = 10:00 in America/New_York (the fixtures' store zone).
NOW = Time.utc(2026, 11, 7, 15, 0, 0).to_i

def assert(cond, msg)
  raise "FAIL: #{msg}" unless cond
end

def assert_eq(actual, expected, msg)
  raise "FAIL: #{msg}\n  expected: #{expected.inspect}\n  actual:   #{actual.inspect}" unless actual == expected
end

# What a block raises (a `klass`, Shop::Failure by default), or nil when
# it returns. Assert on the result (`raised { ... }&.code`), never inside a
# rescue, so a call that stops raising fails the test.
def raised(klass = Shop::Failure)
  yield
  nil
rescue klass => e
  e
end

# The Failure code a block raises, or nil when it returns.
def failure_code(&) = raised(&)&.code

# True when the block raises bad_response (malformed CLI output).
def bad_response?(&)
  failure_code(&) == 'bad_response'
end

# A canned CLI payload from tests/fixtures/cli/, as text or parsed.
def fixture_text(name) = File.read(File.join(FIXTURES, 'cli', name))
def fixture_json(name) = JSON.parse(fixture_text(name))

def wait_until(timeout = 5)
  deadline = Shop::Deadline.new(timeout)
  until yield
    return false if deadline.expired?

    sleep 0.05
  end
  true
end

def alive?(pid)
  !Shop::ProcessGroup.exited?(pid)
end

# A finished child as Shop::Command returns it, for the unit tests of what
# reads one (Classify, Shopify.body!).
def cli_result(stdout = '', exit_code: 0, stderr: '', timed_out: false, overflowed: false)
  Shop::Command::Result.new(exit_code: exit_code, stdout: stdout, stderr_tail: stderr, timed_out: timed_out, overflowed: overflowed)
end

# The folder traps every theme writer must refuse before any CLI call,
# name => [expected error.reason, a lambda that plants it in a fresh
# theme folder `f` of `home`]. Every symlink is refused, even one that stays
# inside the folder (push follows it, pull and theme dev write through it);
# so are a hardlinked file, a special file, and a shopify.theme.toml in the
# folder (any case) or above it.
LINK_TRAPS = {
  'leak' => ['symlink', lambda { |f, _home|
    File.write(File.join(f, '.env'), 'SHOPIFY_CLI_THEME_TOKEN=x')
    File.symlink('../.env', File.join(f, 'snippets', 'leak.liquid'))
  }],
  'hardstash' => ['symlink', lambda { |f, home|
    FileUtils.mkdir_p(File.join(f, 'stash'))
    secret = home.path('work', "secret-#{File.basename(f)}")
    File.write(secret, 'key')
    File.link(secret, File.join(f, 'stash', 'key'))
    FileUtils.mkdir_p(File.join(f, 'assets'))
    File.symlink('../stash/key', File.join(f, 'assets', 'k.css'))
  }],
  'gitcfg' => ['symlink', lambda { |f, _home|
    FileUtils.mkdir_p(File.join(f, '.git'))
    File.write(File.join(f, '.git', 'config'), "[core]\n")
    File.symlink('../.git/config', File.join(f, 'snippets', 'x.liquid'))
  }],
  'subdir' => ['symlink', lambda { |f, _home|
    FileUtils.mkdir_p(File.join(f, 'notes'))
    File.symlink('/etc/hostname', File.join(f, 'notes', 'leak.css'))
    FileUtils.mkdir_p(File.join(f, 'assets'))
    File.symlink('../notes', File.join(f, 'assets', 'sub'))
  }],
  'agents' => ['symlink', ->(f, _home) { File.symlink('/etc/hostname', File.join(f, 'AGENTS.md')) }],
  'hardlink' => ['hardlink', ->(f, home) { File.link(File.join(f, 'layout', 'theme.liquid'), home.path('work', "hard-#{File.basename(f)}")) }],
  'fifo' => ['special_file', lambda { |f, _home|
    FileUtils.mkdir_p(File.join(f, 'assets'))
    File.mkfifo(File.join(f, 'assets', 'pipe.css'))
  }],
  'toml' => ['theme_toml', ->(f, _home) { File.write(File.join(f, 'SHOPIFY.THEME.TOML'), "[environments.default]\npublish = true\n") }],
  'parent-toml' => ['theme_toml', lambda { |f, _home|
    File.write(File.join(File.dirname(f), 'shopify.theme.toml'), "[environments.default]\npublish = true\n")
  }]
}.freeze

# Run `helper` with `args` (plus --folder=<trap>) once per LINK_TRAPS entry,
# each in a fresh folder under its own parent, and assert each is refused
# unsafe_folder with the trap's reason (the last line: a streamer ends with
# its last event) and that the fake CLI ran no call at all.
def assert_refuses_unsafe_folders(home, helper, *args)
  before = home.cli_log.size
  FileUtils.mkdir_p(home.path('work'))
  LINK_TRAPS.each do |name, (reason, plant)|
    parent = home.path('traps', helper, name)
    FileUtils.mkdir_p(parent)
    folder = FakeHome.scaffold_theme(File.join(parent, 'theme'))
    plant.call(folder, home)
    status, lines, = run_helper(helper, *args, "--folder=#{folder}", home: home)
    error = lines.last&.fetch('error', nil) || {}
    assert_eq([status, error['code'], error['reason']], [1, 'unsafe_folder', reason], "#{helper}: #{name} refused (#{lines.last})")
  end
  assert_eq(home.cli_log.size, before, "#{helper}: no CLI call for any refused folder")
end

def default_overrides(home)
  { system_path: home.sysbin, kill_grace: 1.0, trusted_parent: home.dir }
end

def helper_env(home, env)
  { 'HOME' => home.dir, 'PATH' => '/usr/bin:/bin', 'LANG' => 'C.UTF-8' }.merge(env)
end

def helper_argv(name, overrides, args)
  [RUBY, '--disable-gems', LAUNCHER, name, JSON.generate(overrides), *args]
end

# Run a helper to completion: [exit status, parsed stdout lines, stderr].
def run_helper(name, *args, home:, overrides: {}, env: {})
  ov = default_overrides(home).merge(overrides)
  out, err, status = Open3.capture3(helper_env(home, env), *helper_argv(name, ov, args),
                                    unsetenv_others: true, chdir: home.dir)
  lines = out.lines.map do |l|
    JSON.parse(l)
  rescue JSON::ParserError
    raise "FAIL: #{name} printed a non-JSON line: #{l.inspect}\nstderr: #{err}"
  end
  [Shop::ProcessGroup.exit_code(status), lines, err]
end

# Exactly one JSON line; returns [status, object, stderr].
def run_one(name, *args, **kw)
  status, lines, err = run_helper(name, *args, **kw)
  assert(lines.size == 1, "#{name} prints exactly one JSON line (got #{lines.size}: #{lines.inspect}; stderr #{err})")
  [status, lines.first, err]
end

# Start a helper with pipes; returns [stdin, stdout, stderr, wait_thread].
def spawn_helper(name, *args, home:, overrides: {})
  ov = default_overrides(home).merge(overrides)
  Open3.popen3(helper_env(home, {}), *helper_argv(name, ov, args), unsetenv_others: true, chdir: home.dir)
end

# Runs a helper under `scenario` until the fake CLI call it hangs in has
# started, sends it TERM (the panel's cancel) and returns its last line.
def term_helper(home, scenario, name, *args)
  home.scenario!(scenario)
  before = home.pids.size
  stdin, stdout, _stderr, thr = spawn_helper(name, *args, home: home)
  stdin.close
  assert(wait_until(20) { home.pids.size > before }, "#{name} #{scenario}: the fake CLI call started hanging")
  Process.kill(:TERM, thr.pid)
  out = JSON.parse(stdout.read.lines.last)
  thr.value
  out
end

# Point this process at `home` the way a helper sees it: HOME, the default
# test overrides and the prepared state dirs.
def use_home(home)
  ENV['HOME'] = home.dir
  Shop.override!(default_overrides(home))
  Shop::Paths.prepare!
end

def with_home(**kw)
  home = FakeHome.new(**kw)
  yield home
ensure
  home&.cleanup
end

# ----- the source contracts (tests/ruby/contracts/) -----

# A repo file's text, by repo-relative or absolute path, and the
# repo-relative spelling of a path.
def source(path) = File.read(File.expand_path(path, ROOT))
def rel(path) = path.delete_prefix("#{ROOT}/")

# Source without its comment lines (Ruby) or its comments (JS, QML: block
# comments keep their newlines, so line numbers hold; a `//` right after
# `:` (a URL) or `"` (a string) is not one). tests/js/support.mjs `strip`
# is the Node twin.
def strip_ruby_comments(src) = src.lines.reject { |l| l.lstrip.start_with?('#') }.join
def strip_js_comments(src) = src.gsub(%r{/\*.*?\*/}m) { |c| c.gsub(/[^\n]/, '') }.gsub(%r{(^|[^:"\\])//.*$}, '\\1')

# Tracked plus untracked files, minus ignored ones (what tests/run checks),
# repo-relative.
def repo_files = Dir.chdir(ROOT) { `git ls-files --cached --others --exclude-standard`.lines.map(&:chomp) }

# The js/*.mjs that exports a constant (the JS side may move it between
# modules; the checks follow it): [repo-relative path, source].
def js_exporting(name)
  Dir.glob(File.join(ROOT, 'js', '*.mjs')).sort.map { |p| [rel(p), File.read(p)] }
     .find { |_, src| src.match?(/^export const #{name} = /) } || raise("FAIL: no js/*.mjs exports #{name}")
end

# The helpers, by file name (helpers/ is extensionless).
def helper_names = Dir.children(File.join(ROOT, 'helpers')).sort
