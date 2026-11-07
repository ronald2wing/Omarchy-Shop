# Contract checks that README.md and CONTRIBUTING.md say what the code does: the pins, the scripts they run, the pendingConfirm schema, the timing table, the V4 subset, the Troubleshooting quotes, the cache version, the helper flags, the Classify table and the smokes' OK tokens.

require_relative 'support'

readme_src = source('README.md')
contributing_src = source('CONTRIBUTING.md')
pin_js, = js_exporting('CLI_PIN')
[pin_js, 'test_contracts_helpers.rb'].each do |name|
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
# Every script the docs tell a contributor to run (`ruby x.rb`, `node
# x.mjs`, `bash x.sh`) is in the repo; a `<name>` placeholder needs a
# matching file. Local harnesses are described, never named as files.
docs.each do |doc, text|
  text.scan(%r{\b(?:ruby|node|bash|sh)(?:\s+--?[a-z-]+)*\s+([A-Za-z0-9_./<>-]+\.(?:rb|mjs|sh))\b}).flatten.uniq.each do |script|
    found = Dir.glob(File.join(ROOT, script.gsub(/<[^>]+>/, '*')))
    assert(!found.empty?, "#{doc} runs #{script}, which is not in the repo")
  end
end
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

# 5. The CONTRIBUTING timing table is Shop::TIMING written out: one row per
# entry, [helper, H, per call, stdout cap, QML deadline].
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
    [name, "ready ≤#{row[:ready]} s, lifetime ≤#{row[:helper] / 3600} h", '–', "lines ≤#{bytes_text.call(row[:cap])}",
     'none; stop = close stdin + SIGTERM, SIGKILL after 8 s']
  else
    [name, "#{row[:helper]} s", per_call_text.call(row), bytes_text.call(row[:cap]), "#{row[:helper] + 5} s"]
  end
end
header = '| helper | H | per call | stdout cap | QML deadline |'
expected_table = ([header, '| --- | --- | --- | --- | --- |'] + timing_rows.map { |r| "| #{r.join(' | ')} |" }).join("\n")
start = contributing_src.index(header)
assert(start, "CONTRIBUTING.md has the timing table header #{header}")
actual_table = contributing_src[start..].lines.take_while { |l| l.start_with?('|') }.map(&:chomp).join("\n")
assert_eq(actual_table, expected_table, "CONTRIBUTING timing table equals Shop::TIMING; expected:\n#{expected_table}")

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

# The CONTRIBUTING Classify table names every phrase the signed_out and
# sales_access_required patterns match: each alternative's longest run of
# plain words (regex syntax and `\S+` placeholders removed) appears in it.
classify_table = contributing_src[/\| Source text or code \| code \|.*?\n\n/m].to_s.downcase
assert(!classify_table.empty?, 'CONTRIBUTING has the Classify table')
[Shop::Classify::SIGNED_OUT_RE, Shop::Classify::SALES_ACCESS_RE].each do |union|
  union.source.split(/\)\|\(\?/).each do |alt|
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
