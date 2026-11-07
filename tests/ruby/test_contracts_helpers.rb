# Contract checks over the Ruby source: the helpers' shape, lib/ layout, the process and network rules, the pins, Command's callers and the queries.

require_relative 'support'

SHEBANG = '#!/usr/bin/env -S -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_PATH -u BUNDLE_BIN_PATH -u GEM_HOME -u GEM_PATH /usr/bin/ruby --disable-gems'
HELPERS = %w[prepare-state check-account sign-in sign-out install-cli grant-sales-access discover-stores fetch-sales list-themes
             inspect-folder push-theme pull-theme restore-backup list-backups preview-theme notify-order read-clipboard].freeze
# Every TIMING row names a helper (fetch-sales has one row per range).
assert_eq(Shop::TIMING.keys.map { |k| k.split(' ').first }.uniq.sort, HELPERS.sort, 'Shop::TIMING covers exactly the helpers')

helper_files = helper_names
lib_files = Dir.glob(File.join(ROOT, 'lib', '**', '*.rb')).sort
ruby_sources = lib_files + helper_files.map { |h| File.join(ROOT, 'helpers', h) }

# 1. Helpers: the exact set, the hardened shebang, mode 755, the require as
# the first statement, the module/run shape, HelperMain (which sets the
# umask once for every helper) and the $PROGRAM_NAME guard.
assert_eq(helper_files, HELPERS.sort, 'helpers/ holds exactly the 17 helpers (extensionless)')
HELPERS.each do |name|
  path = File.join(ROOT, 'helpers', name)
  src = source(path)
  lines = src.lines.map(&:chomp)
  assert_eq(lines.first, SHEBANG, "#{name}: hardened shebang")
  assert_eq(File.stat(path).mode & 0o777, 0o755, "#{name}: mode 755")
  assert(lines[1].start_with?('# Helper: '), "#{name}: a one-line purpose comment follows the shebang")
  code = lines.reject { |l| l.strip.empty? || l.lstrip.start_with?('#') }
  assert_eq(code[0, 1], ["require_relative '../lib/shop'"], "#{name}: the require is the first statement")
  assert(!src.include?('umask'), "#{name}: no umask of its own (HelperMain.main sets 077 for every helper)")
  mod = name.split('-').map(&:capitalize).join
  assert(src.include?("module #{mod}") && src.include?('def run(argv, **overrides)'), "#{name}: Shop::Helpers::#{mod}.run(argv, **overrides)")
  assert(lines.last == "Shop::Helpers::#{mod}.run(ARGV) if $PROGRAM_NAME == __FILE__", "#{name}: $PROGRAM_NAME guard")
  assert(src.include?('HelperMain.main(') && src.include?("NAME = '#{name}'"), "#{name}: runs through Shop::HelperMain.main under its own NAME")
  # fetch-sales picks its row from --range: a lambda building "NAME <range>".
  assert(src.match?(/helper: (?:NAME\b|->\(options\) \{ "\#\{NAME\} )/), "#{name}: names its TIMING row")
  # A bound that lives in lib/ reaches the usage text by interpolation
  # (`#{Stores::MAX_DISCOVERED}`, `#{TreeWalk::MAX_ENTRIES}`, ...), so
  # changing the constant cannot leave the helper's own help wrong. The
  # folder cap is the one large enough to be unambiguous as a number.
  usage = src[/USAGE = <<~TEXT\n(.*?)^\s*TEXT$/m, 1].to_s
  assert(!usage.empty?, "#{name}: has a USAGE heredoc")
  cap = Shop::TreeWalk::MAX_ENTRIES
  [cap.to_s, cap.to_s.reverse.scan(/\d{1,3}/).join(',').reverse, cap.to_s.reverse.scan(/\d{1,3}/).join('_').reverse].uniq.each do |s|
    assert(!usage.include?(s), "#{name}: USAGE spells #{s} literally (interpolate TreeWalk::MAX_ENTRIES)")
  end
end
%w[push-theme pull-theme].each do |name|
  assert(source(File.join(ROOT, 'helpers', name)).include?('#{TreeWalk::MAX_ENTRIES}'), "#{name} usage interpolates TreeWalk::MAX_ENTRIES")
end
lib_files.each do |path|
  first = source(path).lines.first.to_s
  assert(first.start_with?('# Shop'), "#{rel(path)}: starts with a one-line purpose comment")
end
main_src = source(File.join(ROOT, 'lib', 'shop', 'helper_main.rb'))
assert_eq(main_src.scan('File.umask(0o077)').size, 1, 'HelperMain.main sets the umask exactly once')
# Each lib file holds the module or class its name says (lib/shop/tree_walk.rb
# defines Shop::TreeWalk), and every lib file is required by lib/shop.rb.
shop_rb = source(File.join(ROOT, 'lib', 'shop.rb'))
Dir.glob(File.join(ROOT, 'lib', 'shop', '*.rb')).each do |path|
  base = File.basename(path, '.rb')
  const = base.split('_').map(&:capitalize).join
  assert(source(path).match?(/^  (?:module|class) #{const}\b/), "#{rel(path)} defines Shop::#{const}")
  assert(shop_rb.include?("require_relative 'shop/#{base}'"), "lib/shop.rb requires #{rel(path)}")
end

# 2. Process and network rules in lib/ and helpers/.
ruby_sources.each do |path|
  code = strip_ruby_comments(source(path))
  name = rel(path)
  assert(!code.match?(/\b(Thread|Mutex|Queue|ConditionVariable|Monitor)\b/), "#{name}: no Thread/Mutex")
  assert(!code.match?(%r{Net::HTTP|open-uri|require 'net/|URI\.open}), "#{name}: no HTTP client")
  assert(!code.match?(/\b(?:TCPServer|TCPSocket|UDPSocket|Socket\.)/), "#{name}: sockets only in ports.rb") unless name == 'lib/shop/ports.rb'
  unless name == 'lib/shop/child.rb'
    assert(!code.match?(/Process\.spawn|\bspawn\(|\bsystem\(|\bexec\(|%x|IO\.popen|Open3|Kernel\.fork|\bfork\b/), "#{name}: children only through Shop::Command (Shop::Child spawns)")
  end
  assert(!code.match?(/execDetached|bash -c|sh -c|sudo/), "#{name}: no shell, no sudo")
  assert(!code.match?(/@latest/), "#{name}: no @latest installs")
  assert(!code.match?(/['"]--(?:publish|allow-mutations|theme-editor-sync|notify|open|password|environment)\b/), "#{name}: no forbidden CLI flags")
  assert(!code.match?(/['"]-(?:e|p|d|t|a|n|s|j|q|v)['"]/), "#{name}: no short CLI flags")
  assert(!code.match?(/\buse\b['"]|['"]use['"]|['"]-g['"]|--global/), "#{name}: never `mise use`, never -g")
  # The pin lives in one constant; prose and code refer to Shop::CLI_PIN.
  unless name == 'lib/shop.rb'
    assert(!source(path).include?(Shop::CLI_PIN), "#{name}: no literal CLI version (use Shop::CLI_PIN)")
  end
end
pin_js, state_src = js_exporting('CLI_PIN')
# The pins are constants in two places (lib/shop.rb and the JS module above;
# tests/run and tests/qml/fake-home.sh read lib/shop.rb), plus prose in
# README.md and CONTRIBUTING.md (test_contracts_docs.rb); CONTRIBUTING "Pins"
# names them and this keeps them equal, so bumping Shop::CLI_PIN alone cannot
# leave the UI on the old one.
assert_eq(state_src[/^export const CLI_PIN = "([^"]+)"/, 1], Shop::CLI_PIN, "#{pin_js} CLI_PIN equals Shop::CLI_PIN")
assert_eq(state_src[/^export const NODE_PIN = "([^"]+)"/, 1], Shop::NODE_PIN, "#{pin_js} NODE_PIN equals Shop::NODE_PIN")
# No other tracked file spells a pin: tests build their expectations from
# Snapshot.CLI_PIN / Shop::CLI_PIN, so a bump really is the four files above.
pin_owners = ['lib/shop.rb', pin_js, 'README.md', 'CONTRIBUTING.md']
pin_re = /(?<![\d.])(?:#{Regexp.escape(Shop::CLI_PIN)}|#{Regexp.escape(Shop::NODE_PIN)})(?![\d.])/
repo_files.each do |f|
  next if pin_owners.include?(f) || !File.file?(File.join(ROOT, f)) || f.end_with?('.png')

  text = File.binread(File.join(ROOT, f))
  next if text.include?("\0")

  assert(!text.force_encoding(Encoding::UTF_8).scrub.match?(pin_re), "#{f} spells a pin literal (build it from the pin constants)")
end
# CLI-derived JSON is walked with Json.dig (nil on a non-Hash step),
# never Hash#dig, which raises TypeError on valid JSON of the wrong shape;
# only Shop's own overrides hash is dug.
Dir.glob(File.join(ROOT, '{lib/shop.rb,lib/shop/*.rb,helpers/*}')).each do |path|
  source(path).each_line.with_index(1) do |line, n|
    next if line.lstrip.start_with?('#')

    rest = line.gsub(/\b(?:Json|overrides)\.dig\(/, '')
    assert(!rest.include?('.dig('), "#{rel(path)}:#{n} uses Hash#dig on CLI data (use Json.dig)")
  end
end

# Helpers never read manifest.json at require time: nothing in Ruby uses
# the version, and a missing or broken manifest would kill every helper
# before it could print its JSON line (Service.version is the one reader).
Dir.glob(File.join(ROOT, '{lib/**/*.rb,helpers/*}')).each do |path|
  assert(!source(path).include?('manifest.json'), "#{rel(path)}: no manifest.json read in Ruby (Service.version is the one reader)")
end

child_src = source(File.join(ROOT, 'lib', 'shop', 'child.rb'))
assert(child_src.include?("[Tools.path(:setpriv), '--pdeathsig', 'KILL', '--', *@spec.fetch(:argv)]"), 'every child runs under setpriv --pdeathsig KILL')
%w[pgroup:\ true unsetenv_others:\ true close_others:\ true chdir:\ Paths.run_dir].each do |opt|
  assert(child_src.include?(opt.delete('\\')), "spawn uses #{opt.delete('\\')}")
end
assert_eq(strip_ruby_comments(child_src).scan('Process.spawn(').size, 1, 'Shop::Child holds the one Process.spawn')
runtime_src = source(File.join(ROOT, 'lib', 'shop', 'runtime.rb'))
assert(ruby_sources.one? { |p| strip_ruby_comments(source(p)).include?("File.join(Paths.bin_dir, 'node')") } && runtime_src.include?('def ensure_node_link!'),
       'Runtime.ensure_node_link! is the only writer of state/bin/node')

# 3. Every child has an absolute argv0. Command.run is called only by
# Shopify (argv from Shopify.spec: [pinned node, run.js, *args]) and by
# Tools.run (argv0 Tools.path(name)); everything else spawns through
# Shopify.run/call/call_all or Tools.run, and Tools.run names its tool
# with a symbol literal, so no path or string reaches argv0.
command_sites = {}
ruby_sources.each do |path|
  next if path.end_with?('lib/shop/command.rb', 'lib/shop/child.rb')

  src = strip_ruby_comments(source(path))
  src.scan(/Command\.run(?:_all)?\(\s*([^,\n]+)/).flatten.each { |first| (command_sites[rel(path)] ||= []) << first }
  src.scan(/Tools\.run\(\s*([^,\n]+)/).flatten.each do |first|
    assert(first.match?(/\A:[a-z_]+\z/) || (path.end_with?('helpers/notify-order') && first == 'name'),
           "#{rel(path)}: Tools.run names its tool with a symbol: #{first}")
  end
end
assert_eq(command_sites.keys.sort, %w[lib/shop/shopify.rb lib/shop/tools.rb], 'only Shopify and Tools call Command')
assert(command_sites['lib/shop/shopify.rb'].all? { |first| %w[s[:argv] specs].include?(first) }, "Shopify runs Shopify.spec argv only: #{command_sites['lib/shop/shopify.rb']}")
assert_eq(command_sites['lib/shop/tools.rb'], ['[path(name)'], 'Tools.run runs [Tools.path(name), *args]')
assert(source(File.join(ROOT, 'lib', 'shop', 'shopify.rb')).match?(/def spec\(.*?argv: argv\(located, \*args\)/m), 'Shopify.spec builds the argv')
Shop::Tools::PATHS.each { |name, tool_path| assert(tool_path.start_with?('/'), "Tools::PATHS[#{name}] is absolute") }
assert_eq(Shop::Tools::PROFILES.keys - Shop::Tools::PATHS.keys, [], 'every runnable tool has a path')
shopify_src = source(File.join(ROOT, 'lib', 'shop', 'shopify.rb'))
assert(shopify_src.include?('[located.node, located.run_js, *args]'), 'CLI argv is [pinned node, run.js, *args]')
assert(shopify_src.include?('Runtime.ensure_node_link!(located)'), 'Shopify.spec links the pinned node before a spawn')
classify_src = strip_ruby_comments(source(File.join(ROOT, 'lib', 'shop', 'classify.rb')))
assert(!classify_src.match?(/stderr_tail\s*\)?\s*(?:=~|\.match|\.include\?|\.start_with\?)|when .*stderr/), 'the classifier never classifies stderr text')

# 4. Queries: frozen, no interpolation, no customer fields, no mutations.
queries = source(File.join(ROOT, 'lib', 'shop', 'queries.rb'))
assert(!queries.include?('#{') && !queries.match?(/customer|--allow-mutations|mutation/i), 'queries.rb: no interpolation, customers or mutations')
assert(queries.scan(/<<~'GQL'\.strip\.freeze/).size == Shop::Queries.constants.size, 'every query is a frozen literal heredoc')
