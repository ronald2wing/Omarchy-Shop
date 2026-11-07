# Contract checks that README.md and CONTRIBUTING.md say what the code does: the pins, the repo paths and tests/run examples they name, the pendingConfirm schema, the timing table, the V4 subset, the Troubleshooting quotes, the cache version, the helper flags, the Classify table, the smokes' OK tokens and their engine error list, the unsafe_folder reasons, the error-code table, the Layout module lists, the snapshot keys and the graces.

require_relative '../support'

readme_src = source('README.md')
contributing_src = source('CONTRIBUTING.md')
pin_js, = js_exporting('CLI_PIN')
[pin_js, 'contracts/test_helpers.rb'].each do |name|
  assert(contributing_src.include?(name), "CONTRIBUTING names #{name} as a copy of the pin (or its check)")
end
# The docs spell the pins in prose and commands (`mise install node@…`,
# `npm-shopify-cli/…/`): every Node or CLI version literal in them is the
# pinned one, and both pins appear in each file. Other dotted triples
# (loopback addresses, the Quickshell version) are not versions of ours.
docs = { 'README.md' => readme_src, 'CONTRIBUTING.md' => contributing_src }
docs.each do |doc, text|
  text.scan(/(?:[Nn]ode\s|node@|node\/)(\d+\.\d+\.\d+)/).flatten.each { |v| assert_eq(v, Shop::NODE_PIN, "#{doc}: Node version literal equals Shop::NODE_PIN") }
  text.scan(/(?:CLI\s|cli@|cli\/|cli\+)(\d+\.\d+\.\d+)/).flatten.each { |v| assert_eq(v, Shop::CLI_PIN, "#{doc}: CLI version literal equals Shop::CLI_PIN") }
  assert(text.include?(Shop::NODE_PIN) && text.include?(Shop::CLI_PIN), "#{doc} spells both pins")
end
# Every repo path the docs name in backticks (`tests/run`, `js/copy.mjs`,
# `helpers/<name>`, `tests/qml/*_smoke.qml`) resolves to at least one file,
# a `<name>` or `*` matching anything; NOT_REPO_PATHS are the paths the docs
# name that are not this repo's (each still named, so the list cannot go
# stale). Every `tests/run <test>...` example in a code block names tests
# that exist.
NOT_REPO_PATHS = {
  'lib/node_modules/@shopify/cli/' => 'a layout inside the CLI install',
  'assets/ACCESS_DENIED.js' => 'a file a theme can ship'
}.freeze
named_elsewhere = []
docs.each do |doc, text|
  text.scan(/`([^`\n]+)`/).flatten.each do |code|
    code.scan(%r{(?<![\w./~-])((?:tests|js|lib|model|ui|helpers|assets)/[A-Za-z0-9_.@+<>*/-]*)}).flatten.uniq.each do |path|
      if NOT_REPO_PATHS.key?(path)
        named_elsewhere << path
        next
      end
      found = Dir.glob(File.join(ROOT, path.gsub(/<[^>]+>/, '*')))
      assert(!found.empty?, "#{doc} names `#{path}`, which is not in the repo")
    end
  end
  runs = text.scan(/^tests\/run[ \t]+([^#\n]+)/).flatten
  assert(!runs.empty?, "#{doc} shows a `tests/run <test>` example")
  runs.flat_map(&:split).each do |test|
    assert(File.file?(File.join(ROOT, test)), "#{doc}: `tests/run #{test}` names a test that is not in the repo")
  end
end
assert_eq(named_elsewhere.uniq.sort, NOT_REPO_PATHS.keys.sort, 'every NOT_REPO_PATHS entry is still named in the docs')
# The pendingConfirm schema in CONTRIBUTING names every field
# model/Consent.qml puts in the pending record (published unchanged as
# snapshot.pendingConfirm), and no other.
consent_src = source('model/Consent.qml')
pending_block = consent_src[/internal\.pending = \{(.*?)\n\s*\}/m, 1].to_s
pending_keys = pending_block.scan(/(?:\{|,|\A)\s*([a-zA-Z]+):/).flatten.sort
assert(pending_keys.include?('action'), "model/Consent.qml builds the pending record (#{pending_keys})")
schema = contributing_src[/^- `pendingConfirm`: `\{(.*?)\}`/m, 1].to_s
schema_keys = schema.split(',').map { |f| f.strip[/\A[a-zA-Z]+/] }.compact.sort
assert_eq(schema_keys, pending_keys, 'CONTRIBUTING pendingConfirm schema lists exactly the fields of Consent.pending')

# The CONTRIBUTING timing table is Shop::TIMING written out: one row per
# entry, [helper, H, per call, stdout cap, QML deadline], the preview's stop
# grace being HelperProcess.stopGrace.
helper_process = source('model/HelperProcess.qml')
kill_grace, stop_grace = %w[killGrace stopGrace].map { |p| Integer(helper_process[/readonly property int #{p}: (\d+)/, 1]) / 1000 }
bytes_text = ->(bytes) { bytes >= Shop::MIB ? "#{bytes / Shop::MIB} MiB" : "#{bytes / Shop::KIB} KiB" }
per_call_text = lambda do |row|
  calls = row[:calls]
  parts = if calls.empty? then []
          elsif calls.keys == ['call'] then ["#{calls['call']} s"]
          else calls.map { |label, s| "#{label} #{s} s" }
          end
  parts << "≤#{row[:pages]} pages" if row[:pages]
  parts << "concurrency #{row[:concurrency]}" if row[:concurrency]
  parts.empty? ? '–' : parts.join(', ')
end
timing_rows = Shop::TIMING.map do |name, row|
  if row[:ready]
    [name, "ready ≤#{row[:ready]} s, lifetime ≤#{row[:overall] / 3600} h", '–', "lines ≤#{bytes_text.call(row[:cap])}",
     "none; stop = close stdin + SIGTERM, SIGKILL after #{stop_grace} s"]
  else
    [name, "#{row[:overall]} s", per_call_text.call(row), bytes_text.call(row[:cap]), "#{row[:overall] + 5} s"]
  end
end
header = '| helper | H | per call | stdout cap | QML deadline |'
expected_table = ([header, '| --- | --- | --- | --- | --- |'] + timing_rows.map { |r| "| #{r.join(' | ')} |" }).join("\n")
start = contributing_src.index(header)
assert(start, "CONTRIBUTING.md has the timing table header #{header}")
actual_table = contributing_src[start..].lines.take_while { |l| l.start_with?('|') }.map(&:chomp).join("\n")
assert_eq(actual_table, expected_table, "CONTRIBUTING timing table equals Shop::TIMING; expected:\n#{expected_table}")
# The page caps in words: README's busy-day sentence and CONTRIBUTING's
# paging paragraph state what the timing table derives.
today_orders = Shop::TIMING.fetch('fetch-sales today')[:pages] * Shop::Sales::ORDERS_PER_PAGE
assert(readme_src.include?("Past #{today_orders} orders in\n  a day Today sums only the first #{today_orders}"), "README states Today's #{today_orders}-order cap")
paging = "#{Shop::PAGE_SECONDS} s: a fresh node and CLI start each"
assert(contributing_src.include?(paging) && contributing_src.include?("(#{Shop::PAGE_RESERVE} s, at least a page)"),
       'CONTRIBUTING states PAGE_SECONDS and PAGE_RESERVE')
pages = %w[today yesterday].map { |r| Shop::TIMING.fetch("fetch-sales #{r}")[:pages] }
assert(contributing_src.include?("That gives today #{pages[0]}\npages and yesterday #{pages[1]}"), "CONTRIBUTING states the derived caps #{pages}")

# The JS subset denylist (owned and scanned by tests/js/test_js_subset.mjs)
# is read here only for the CONTRIBUTING V4-section check.
denylist = JSON.parse(source(File.join(ROOT, 'tests', 'js', 'js_subset.json'))).map { |e| [e['note'], Regexp.new(e['pattern'])] }

# CONTRIBUTING's "The V4 subset" is the denylist in words: every note (up to
# its parenthesis) appears in the section, and no Allowed example matches a
# pattern (it once listed ?., ?? and padStart as allowed).
v4 = contributing_src[/^## The V4 subset\n(.*?)(?=^## )/m, 1].to_s
assert(!v4.empty?, 'CONTRIBUTING has a "The V4 subset" section')
v4_flat = v4.gsub(/\s+/, ' ')
denylist.each do |what, _re|
  key = what.to_s.split(' (').first.strip
  assert(v4_flat.include?(key), "CONTRIBUTING V4 subset names the denylist entry #{key.inspect}")
end
allowed = v4_flat[/\*\*Allowed:\*\*(.*)\z/, 1].to_s
examples = allowed.scan(/`([^`]+)`/).flatten
assert(examples.size >= 6, "CONTRIBUTING V4 subset Allowed lists code examples, got #{examples.inspect}")
examples.each do |ex|
  denylist.each { |what, re| assert(!ex.match?(re), "CONTRIBUTING lists `#{ex}` as allowed, but the denylist forbids #{what}") }
end

# Every string README "Troubleshooting" quotes is UI text a user can see: a
# Copy value, with "…" standing for a {placeholder}.
copy_src = source('js/copy.mjs')[/^export const STRINGS = \{\n(.*?)^\}$/m, 1].to_s
copy_values = copy_src.scan(/^\s*"[a-zA-Z0-9_.]+":\s*"((?:[^"\\]|\\.)*)"/).flatten
trouble = readme_src[/^## Troubleshooting\n(.*?)(?=^## )/m, 1].to_s
quotes = trouble.gsub(/\s+/, ' ').scan(/"([^"]+)"/).flatten
assert(!quotes.empty?, 'README Troubleshooting quotes UI text')
quotes.each do |q|
  pattern = Regexp.new("\\A#{q.split('…', -1).map { |part| Regexp.escape(part.strip) }.join('\\s*\\{[a-zA-Z]+\\}\\s*')}\\z")
  assert(copy_values.any? { |v| v.match?(pattern) }, "README Troubleshooting quotes \"#{q}\", which is no Copy string")
end

# CONTRIBUTING's Cache section names the cache version the code writes.
cache_version = js_exporting('CACHE_VERSION').last[/export const CACHE_VERSION = (\d+)/, 1]
cache_doc = contributing_src[/^### Cache .*?(?=^### )/m].to_s
assert(cache_version && cache_doc.include?(%({"version": #{cache_version},)) && cache_doc.include?("is not `#{cache_version}`") &&
       cache_doc.scan(/"version": (\d+)|is not `(\d+)`/).flatten.compact.uniq == [cache_version],
       "CONTRIBUTING Cache section says version #{cache_version} (Sales.CACHE_VERSION)")

# CONTRIBUTING's helper-flag list is exactly what each helper accepts
# (its HelperMain `values:` and `switches:`), for every helper.
flag_doc = contributing_src[/^- Helper flags.*?(?=^- )/m].to_s
assert(!flag_doc.empty?, 'CONTRIBUTING has the Helper flags bullet')
documented = {}
flag_doc.split(';').each do |segment|
  names = segment.scan(/`([a-z-]+)/).flatten.select { |n| helper_names.include?(n) }
  flags = segment.scan(/--([a-z][a-z-]*)/).flatten.uniq.sort
  names.each { |n| documented[n] = flags }
end
helper_names.each do |name|
  src = source(File.join(ROOT, 'helpers', name))
  actual = %w[values switches].flat_map { |k| src.scan(/#{k}: %w\[([^\]]*)\]/).flatten.flat_map(&:split) }.uniq.sort
  assert_eq(documented[name], actual, "CONTRIBUTING Helper flags for #{name}")
end

# The CONTRIBUTING Classify table names every phrase a Classify text
# pattern matches: each alternative's longest run of plain words (regex
# syntax and `\S+` placeholders removed) appears in it.
classify_table = contributing_src[/\| Source text or code \| code \|.*?\n\n/m].to_s.downcase
assert(!classify_table.empty?, 'CONTRIBUTING has the Classify table')
classify_res = Shop::Classify.constants.grep(/_RE\z/).map { |c| Shop::Classify.const_get(c) }
assert(classify_res.size >= 7, "Classify's text patterns found (#{classify_res.size})")
classify_res.each do |re|
  # A Regexp.union of patterns splits between its (?-mix:...) parts, a
  # plain pattern at its top-level |.
  alts = re.source.start_with?('(?') ? re.source.split(/\)\|\(\?/) : re.source.split('|')
  alts.each do |alt|
    plain = alt.sub(/\A\(?\??[mix]*-?[mix]*:/, '').sub(/\)\z/, '').gsub('\\b', '')
    group = plain[/\(\?:([^)]*)\)/, 1]
    variants = group ? group.split('|').map { |g| plain.sub(/\(\?:[^)]*\)/, g) } : [plain]
    variants.each do |v|
      text = v.gsub(/(?<=[a-z]) for\z/i, ' for <domain>').gsub('\\S+', '<domain>')
      words = text.split(/<domain>|\\s\+|[\\()\[\]?*+|^$]/).map(&:strip).max_by(&:length).to_s.downcase
      assert(words.split.length >= 2 && classify_table.include?(words), "CONTRIBUTING Classify table names #{words.inspect}")
    end
  end
end

# CONTRIBUTING names only OK tokens a smoke really prints: <name>_OK for its
# Smoke's name (tests/qml/Smoke.qml prints it).
smoke_tokens = Dir.glob(File.join(ROOT, 'tests', 'qml', '*_smoke.qml')).flat_map { |f| File.read(f).scan(/^\s*name: "([A-Z_]+)"$/).flatten.map { |n| "#{n}_OK" } }
assert(smoke_tokens.include?('SERVICE_OK'), "the smokes' Smoke names parsed: #{smoke_tokens}")
contributing_src.scan(/`([A-Z_]+_OK)`/).flatten.uniq.each do |tok|
  assert(smoke_tokens.include?(tok), "CONTRIBUTING names #{tok}, which a smoke prints")
end

# Step 7's engine error list is tests/run's ENGINE_ERRORS, word for word
# (the manual checks point at it).
engine_errors = source('tests/run')[/^ENGINE_ERRORS='([^']+)'$/, 1].to_s.split('|')
assert(engine_errors.include?('Binding loop'), "tests/run's ENGINE_ERRORS parsed: #{engine_errors}")
step7 = contributing_src[/no engine error line: (.*?) \(`ENGINE_ERRORS` in `tests\/run`\)/m, 1].to_s
assert_eq(step7.scan(/`([^`]+)`/).flatten, engine_errors, "CONTRIBUTING step 7 lists tests/run's ENGINE_ERRORS")

# The unsafe_folder row lists exactly the reasons ThemeFolder has words for.
documented_reasons = contributing_src[/`error\.reason` is one of ([^|]*)\|/, 1].to_s.scan(/`([a-z_]+)`/).flatten.sort
assert_eq(documented_reasons, Shop::ThemeFolder::REASON_TEXT.keys.sort, 'CONTRIBUTING unsafe_folder reasons are ThemeFolder::REASON_TEXT')

# The error-code table lists exactly the codes a helper can print: every
# `Failure.new('<code>'` in lib/ and helpers/ and every code Classify
# returns.
error_table = contributing_src[/^\| code \| meaning \|\n(.*?)\n\n/m, 1].to_s.scan(/^\| `([a-z_]+)` \|/).flatten
ruby_srcs = Dir.glob(File.join(ROOT, '{lib/shop.rb,lib/shop/*.rb,helpers/*}')).map { |f| File.read(f) }
raised_codes = ruby_srcs.flat_map { |src| src.scan(/Failure\.new\('([a-z_]+)'/).flatten }
classified = source('lib/shop/classify.rb').scan(/\['([a-z_]+)', \{\}\]/).flatten - %w[multi_org]
assert(raised_codes.size > 20 && classified.include?('rate_limited'), "helper error codes parsed (#{raised_codes.uniq.size}, #{classified.uniq})")
assert_eq(error_table.sort, (raised_codes + classified).uniq.sort, 'CONTRIBUTING error-code table lists exactly the codes helpers raise')

# The Layout rows for model/ and js/ name every module there, and no other;
# the helpers/ row counts them.
layout_row = ->(dir) { contributing_src[/^\| `#{dir}\/` \| (.*?) \|$/, 1].to_s }
model_named = layout_row.call('model')[/\A(.*?)\. Only /, 1].to_s.scan(/`([A-Z][A-Za-z]+)`/).flatten.uniq.sort
assert_eq(model_named, Dir.glob(File.join(ROOT, 'model', '*.qml')).map { |f| File.basename(f, '.qml') }.sort,
          'CONTRIBUTING Layout model/ row names every model/*.qml')
js_named = layout_row.call('js')[/\A(.*?)\. `copy` is/, 1].to_s.scan(/`([a-z]+)`/).flatten.uniq - %w[ok started]
assert_eq(js_named.sort, Dir.glob(File.join(ROOT, 'js', '*.mjs')).map { |f| File.basename(f, '.mjs') }.sort,
          'CONTRIBUTING Layout js/ row names every js/*.mjs')
assert(layout_row.call('helpers').include?("The #{helper_names.size} extensionless Ruby helpers"), "CONTRIBUTING Layout helpers/ row counts #{helper_names.size}")

# The Service snapshot section's key lists are buildSnapshot's and
# buildStore's object literals.
snapshot_src = source('js/snapshot.mjs')
literal_keys = ->(body) { body.to_s.scan(/^ {4}(\w+):|, (\w+):/).flatten.compact }
top_keys = literal_keys.call(snapshot_src[/^export function buildSnapshot\(.*?\n  const out = \{\n(.*?)\n  \}\n/m, 1])
store_keys = literal_keys.call(snapshot_src[/^function buildStore\(.*?\n  return \{\n(.*?)\n    themeState:/m, 1]) + %w[themeState]
assert(top_keys.include?('pins') && store_keys.include?('domain'), "js/snapshot.mjs object literals parsed (#{top_keys}, #{store_keys})")
snapshot_doc = contributing_src[/^### Service snapshot.*?(?=^### )/m].to_s
doc_list = ->(re) { snapshot_doc[re, 1].to_s.gsub(/\{[^}]*\}/, '').split(',').map(&:strip) }
assert_eq(doc_list.call(/Top-level keys: `(.*?)`/m).sort, top_keys.sort, 'CONTRIBUTING snapshot top-level keys are buildSnapshot\'s')
assert_eq(doc_list.call(/Each store carries `(.*?)`/m).sort, store_keys.sort, 'CONTRIBUTING per-store keys are buildStore\'s')

# The Timing invariant on graces is the code's: HelperProcess.killGrace
# outlasts the helper's own KILL grace plus the group-gone wait.
assert(contributing_src.include?("QML kill grace (#{kill_grace} s) >\nhelper KILL grace (#{Shop::Child::KILL_GRACE.to_i} s) + group-gone wait (≤#{Shop::ProcessGroup::GONE_WAIT.to_i} s)"),
       'CONTRIBUTING Timing states killGrace, Child::KILL_GRACE and ProcessGroup::GONE_WAIT')
assert(kill_grace > Shop::Child::KILL_GRACE + Shop::ProcessGroup::GONE_WAIT, 'QML kill grace outlasts the helper KILL grace and the group-gone wait')
