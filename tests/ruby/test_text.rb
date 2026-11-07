# Shop::Text: cleaning, details tails, natural sort and notification text (URLs defanged in both fields, body markup neutralised, ZWJ kept).

require_relative 'support'
require 'open3'

T = Shop::Text

assert_eq(T.clean("  a\e[31mred\e[0m\tb\n c  "), 'ared b c', 'clean strips ANSI, collapses whitespace')
assert_eq(T.clean("a\u0000b​c‮d"), 'a b c d', 'clean replaces control and format characters')
assert_eq(T.clean("Dawn  Target: dev"), 'Dawn Target: dev', 'clean folds U+2028 LINE SEPARATOR')
assert_eq(T.clean("Dawn Not live"), 'Dawn Not live', 'clean folds U+2029 PARAGRAPH SEPARATOR')
assert_eq(T.clean("a 　b"), 'a b', 'clean collapses Unicode spaces')
assert_eq(T.clean("caf\xFF".b), 'caf?', 'clean scrubs invalid UTF-8')
raw = T.as_utf8("caf\xFF".b)
assert_eq([raw.encoding, raw.valid_encoding?, T.scrub(raw)], [Encoding::UTF_8, false, 'caf?'], 'as_utf8 reinterprets without scrubbing; scrub builds on it')
assert_eq(T.clean('x' * 300, 10), "#{'x' * 9}…", 'clean truncates with an ellipsis')
assert_eq(T.clean(nil), '', 'clean(nil) is empty')
# The zero-width joiner holds emoji sequences together and is kept.
assert_eq(T.clean("👩‍💻 dev"), "👩‍💻 dev", 'clean keeps U+200D')

# js/text.mjs mirrors CONTROL_RE through tests/fixtures/control-codepoints.json;
# a Ruby Unicode upgrade that changes the set must regenerate that fixture.
require 'json'
fixture = JSON.parse(File.read(File.join(FIXTURES, 'control-codepoints.json')))
ruby_ranges = []
(0..0x10FFFF).each do |cp|
  next if cp.between?(0xD800, 0xDFFF)
  next unless [cp].pack('U').match?(T::CONTROL_RE)
  if ruby_ranges.last && ruby_ranges.last[1] == cp - 1 then ruby_ranges.last[1] = cp else ruby_ranges << [cp, cp] end
end
ruby_text = ruby_ranges.map { |a, b| a == b ? format('%04X', a) : format('%04X-%04X', a, b) }.join(' ')
assert_eq(ruby_text, fixture['ranges'], 'Text::CONTROL_RE matches tests/fixtures/control-codepoints.json')

tail = [
  '{"type":"progress","status":"started","message":"Downloading"}',
  "\e[31mError:\e[0m something broke",
  '',
  '{"type":"diagnostic","level":"error","message":"x"}',
  'last line'
].join("\n")
assert_eq(T.details(tail), ['Error: something broke', 'last line'], 'details drops progress/diagnostic NDJSON and blanks')
assert_eq(T.details((1..30).map { |i| "line #{i}" }.join("\n")).size, 20, 'details keeps at most 20 lines')
assert(T.details('y' * 500).first.length <= 200, 'details lines are at most 200 chars')

sorted = ['Store 10', 'store 9', 'Alpha', 'store 9b', 'Store 1'].sort { |a, b| T.natural_compare(a, b) }
assert_eq(sorted, ['Alpha', 'Store 1', 'store 9', 'store 9b', 'Store 10'], 'natural_compare: digit runs numeric, case-insensitive')
assert_eq(T.natural_compare('a', 'a'), 0, 'equal strings compare 0')

# Notifications: the body is markup to notification daemons, and Omarchy's
# decodes entities (three passes) before it restores b/i/u/s/em/strong and
# <a href>, so `< > &` are neutralised to ‹ › ＆, never escaped; the title is
# shown verbatim. Controls go, newlines and the zero-width joiner stay.
assert_eq(T.notification("<b>Tee</b> & co\u0007\nline2", neutralise: true), "\u2039b\u203ATee\u2039/b\u203A \uFF06 co\nline2",
          'body: neutralised, controls stripped, newline kept')
assert_eq(T.notification("New order · <b>Acme</b>\u0007"), 'New order · <b>Acme</b>', 'title: verbatim, controls stripped')
assert(!T.notification('see https://x.example').include?('://'), 'title: URL scheme defanged')
assert(!T.notification('see https://x.example', neutralise: true).include?('://'), 'body: URL scheme defanged')
assert_eq(T.notification('a https://b'), "a https:\u2044\u2044b", 'defang keeps the text readable and the length')
assert_eq(T.notification('x' * 298 + '://').length, 300, 'defang happens before the cap')
assert_eq(T.notification("a\u2028b\u2029c"), "a\nb\nc", 'notification maps line/paragraph separators to newlines')
assert_eq(T.notification("👩‍💻 ordered", neutralise: true), "👩‍💻 ordered", 'U+200D survives the notification strip')
assert_eq(T.notification("a\u200Bb\u202Ec"), 'abc', 'other format characters are stripped')
assert(T.notification('z' * 1000).length <= 300, 'notification is capped at 300 chars')
assert_eq(T.notification('<' * 1000, neutralise: true).length, 300, 'neutralising never lengthens the capped body')
# Payloads that survive entity escaping on the daemon: none keeps a markup
# character, so no tag and no entity can form however often it is decoded.
MARKUP_PAYLOADS = [
  '<a href="https://evil.example/login">Open order in Shopify admin</a> <b>URGENT</b>',
  '&lt;a href="https://evil.example/login"&gt;Open&lt;/a&gt; &lt;b&gt;x&lt;/b&gt;',
  '&#60;b&#62;bold&#60;/b&#62; &#x3c;i&#x3e;it&#x3c;/i&#x3e;',
  '&amp;lt;b&amp;gt;double&amp;lt;/b&amp;gt;'
].freeze
MARKUP_PAYLOADS.each do |payload|
  body = T.notification(payload, neutralise: true)
  assert(!body.match?(/[<>&]/), "no markup character survives: #{body}")
end
# Through the daemon's own renderer (when the shell and node are here): no
# link and no allowed tag comes out of a neutralised body.
markup_js = '/usr/share/omarchy/shell/plugins/notifications/Markup.js'
node = ENV.fetch('PATH', '').split(':').map { |d| File.join(d, 'node') }.find { |f| File.executable?(f) }
if File.file?(markup_js) && node
  loader = <<~JS
    const fs = require("fs"), vm = require("vm"), dir = process.argv[1]
    const load = (f, ctx) => vm.runInContext(fs.readFileSync(dir + "/" + f, "utf8").replace(/^\.(pragma|import).*$/gm, ""), ctx)
    const sec = vm.createContext({}); load("Security.js", sec)
    const mk = vm.createContext({ Security: sec }); load("Markup.js", mk)
    const bodies = JSON.parse(fs.readFileSync(0, "utf8"))
    process.stdout.write(JSON.stringify(bodies.map(b => mk.render(b))))
  JS
  bodies = MARKUP_PAYLOADS.map { |p| T.notification(p, neutralise: true) }
  rendered, = Open3.capture2(node, '-e', loader, File.dirname(markup_js), stdin_data: JSON.generate(bodies))
  rendered = JSON.parse(rendered)
  assert_eq(rendered.size, bodies.size, 'the daemon renderer ran')
  rendered.each do |html|
    assert(!html.match?(%r{<\s*/?\s*(?:a|b|i|u|s|em|strong)\b}i), "the daemon renders no tag or link: #{html}")
  end
  # Control: the old entity escaping came back as a live link there.
  escaped = MARKUP_PAYLOADS.first.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  control, = Open3.capture2(node, '-e', loader, File.dirname(markup_js), stdin_data: JSON.generate([escaped]))
  assert(JSON.parse(control).first.include?('<a href="https://evil.example/login">'), 'control: an escaped body is a live link on the daemon')
  # URLs in either field (a product title, a store name) are defanged: the
  # daemon's Detect.scan offers no click link and render() linkifies nothing.
  toast_loader = <<~JS
    const fs = require("fs"), vm = require("vm"), dir = process.argv[1]
    const load = (f, ctx) => vm.runInContext(fs.readFileSync(dir + "/" + f, "utf8").replace(/^\.(pragma|import).*$/gm, ""), ctx)
    const sec = vm.createContext({}); load("Security.js", sec)
    const mk = vm.createContext({ Security: sec }); load("Markup.js", mk)
    const dt = vm.createContext({ Security: sec }); load("Detect.js", dt)
    const rows = JSON.parse(fs.readFileSync(0, "utf8"))
    process.stdout.write(JSON.stringify(rows.map(r => {
      const id = mk.identify({ app: "Shop", summary: r.title, body: r.body })
      return { link: dt.scan(id.summary, id.body).link, html: mk.render(id.body) }
    })))
  JS
  toasts = [
    ['New order · Acme', "#1001 · $12.00 · Mug - refund at https://evil.example/shopify-login?s=acme\n3 today"],
    ['New order · https://evil.example/x', "#1002 · $5.00 · Mug\n1 today"],
    ['New order · Acme', "#1003 · HTTPS://evil.example/caps http://plain.example"]
  ]
  rows = toasts.map { |t, b| { 'title' => T.notification(t), 'body' => T.notification(b, neutralise: true) } }
  out, = Open3.capture2(node, '-e', toast_loader, File.dirname(markup_js), stdin_data: JSON.generate(rows))
  out = JSON.parse(out)
  assert_eq(out.size, rows.size, 'the daemon detector ran')
  out.each_with_index do |r, i|
    assert_eq(r['link'], '', "the daemon offers no click link for toast #{i}")
    assert(!r['html'].match?(/<a\b/i), "the daemon linkifies nothing in toast #{i}: #{r['html']}")
  end
  # Control: an undefanged body is a click link there.
  raw, = Open3.capture2(node, '-e', toast_loader, File.dirname(markup_js),
                        stdin_data: JSON.generate([{ 'title' => 'New order', 'body' => toasts.first[1] }]))
  assert_eq(JSON.parse(raw).first['link'], 'https://evil.example/shopify-login?s=acme', 'control: a raw URL is the click link')
else
  warn 'test_text.rb: no Omarchy notification Markup.js or node; daemon render check skipped'
end

themes = Shop::Themes.parse_list({ 'themes' => [{ 'id' => '1', 'name' => "Dawn Not live", 'role' => 'live' }] })
assert_eq(themes.first['name'], 'Dawn Not live', 'theme names cannot carry line separators')

# quote: an echoed value, quoted, cleaned and capped at ECHO_MAX.
assert_eq(Shop::Text.quote('abc'), '"abc"', 'quote wraps the value')
assert_eq(Shop::Text.quote("a\e[31mb"), '"ab"', 'quote cleans control characters')
assert(Shop::Text.quote('x' * 100).length <= Shop::Text::ECHO_MAX + 2, 'quote caps the value at ECHO_MAX')
assert_eq(Shop::Text.quote(nil), '""', 'quote of nil is empty')
# os_error: the reason of a SystemCallError, without Ruby's location and path.
begin
  File.read('/nonexistent/x')
rescue SystemCallError => e
  assert_eq(Shop::Text.os_error(e), 'no such file or directory', 'os_error drops " @ rb_sysopen - <path>"')
end
assert_eq(Shop::Text.os_error(Errno::EACCES.new('/p')), 'permission denied', 'os_error drops " - <path>"')
assert_eq(Shop::Text.os_error(RuntimeError.new('Boom')), 'Boom', 'any other error keeps its message')
