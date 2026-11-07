# Contract checks over the QML and JS source: no ad-hoc processes, property names, PlainLabel, the IpcHandler, atomic writes, js/timing.mjs against Shop::TIMING, Copy keys, ViewHeader actions, no native text entry or clipboard read, the qmldirs and the panel's scroll gutter.

require_relative 'support'

qml_files = Dir.glob(File.join(ROOT, '{*.qml,model/*.qml,ui/*.qml}')).sort
js_files = Dir.glob(File.join(ROOT, 'js', '*.mjs')).sort
assert(!qml_files.empty? && !js_files.empty?, 'the QML and JS sources are present')
helpers = helper_names

# No shells or ad-hoc processes; no stderr parsing.
(qml_files + js_files).each do |path|
  code = strip_js_comments(source(path))
  name = rel(path)
  assert(!code.match?(/execDetached|"bash"|'bash'|"sh"|"shopify"|xdg-open|wl-copy|"ls"|"mkdir"|"rm"|"git"/), "#{name}: no ad-hoc processes")
  assert(!code.match?(/stderr[^\n]*\.(?:match|test|search|replace)\(|\.(?:match|test)\([^\n]*stderr/i), "#{name}: no stderr regexes")
end

# Properties: lowercase names, never `state`.
qml_files.each do |path|
  source(path).each_line.with_index do |line, i|
    next unless (m = line.match(/^\s*(?:readonly\s+|required\s+|default\s+)*property\s+[\w.<>]+\s+(\w+)/))

    assert(m[1].match?(/\A[a-z_]/), "#{rel(path)}:#{i + 1}: property names start lowercase (#{m[1]})")
    assert(m[1] != 'state', "#{rel(path)}:#{i + 1}: never a property named state")
  end
end

# Every piece of text in ui/ and BarWidget.qml goes through PlainLabel, which
# is the one PlainText Text. No bare `Text {` or `Label {` anywhere else.
Dir.glob(File.join(ROOT, '{BarWidget.qml,ui/*.qml}')).sort.each do |path|
  next if path.end_with?('/ui/PlainLabel.qml')

  code = strip_js_comments(source(path))
  code.each_line.with_index do |line, i|
    assert(!line.match?(/(?<![\w.])(?:Text|Label)\s*\{/), "#{rel(path)}:#{i + 1}: use PlainLabel, not a bare Text/Label")
  end
end
plain = source(File.join(ROOT, 'ui', 'PlainLabel.qml'))
assert(plain.match?(/(?<![\w.])Text\s*\{/) && plain.include?('textFormat: Text.PlainText'), 'ui/PlainLabel.qml is a PlainText Text')

# The IpcHandler names no state-changing operation: IPC only opens dialogs.
block_of = lambda do |src, start|
  depth = 0
  src[start..].each_char.with_index do |c, i|
    depth += 1 if c == '{'
    depth -= 1 if c == '}'
    return src[start, i + 1] if depth.zero? && c == '}'
  end
  src[start..]
end
service = source(File.join(ROOT, 'Service.qml'))
ipc_start = service.index(/IpcHandler\s*\{/)
assert(ipc_start, 'Service.qml has an IpcHandler')
ipc = block_of.call(service, service.index('{', ipc_start))
%w[addStore updateStore moveStore updateSettings pushTheme pullTheme restoreBackup installCli signOut removeStore resolvePending allowLive].each do |name|
  assert(!ipc.match?(/\b#{name}\b/), "IpcHandler does not reference #{name}")
end

# Atomic writes in every FileView-backed store.
Dir.glob(File.join(ROOT, 'model', '*.qml')).each do |path|
  src = source(path)
  next unless src.match?(/\bFileView\s*\{/)

  assert(src.include?('atomicWrites: true'), "#{rel(path)} uses atomicWrites: true")
end

# Helper names and QML timing: js/timing.mjs's HELPERS table is
# Shop::TIMING for QML (deadline = H + 5 s, 0 for the preview stream; the
# stdout or line cap), every `helper: "<name>"` literal is a real helper,
# every helper is used, and no QML file spells a deadline or a cap (the
# models take them from the table through HelperProcess/HelperStream).
timing_src = source(File.join(ROOT, 'js', 'timing.mjs'))
size_of = lambda do |expr|
  assert(expr.match?(/\A\s*\d+(?:\s*\*\s*(?:KIB|MIB))?\s*\z/), "js/timing.mjs: cap #{expr.inspect} is N, N * KIB or N * MIB")
  n, unit = expr.split('*').map(&:strip)
  n.to_i * { nil => 1, 'KIB' => 1024, 'MIB' => 1024 * 1024 }.fetch(unit)
end
js_timing = {}
timing_src.scan(/^\s*"([a-z -]+)": (row|stream)\(([^)]*)\),?\s*$/).each do |name, kind, args|
  parts = args.split(',').map(&:strip)
  js_timing[name] =
    if kind == 'row'
      { deadline_ms: (Integer(parts[0]) + 5) * 1000, cap: size_of.call(parts[1]) }
    else
      { deadline_ms: 0, cap: size_of.call(parts[0]) }
    end
end
assert(timing_src.include?('const GRACE_S = 5'), 'js/timing.mjs: QML deadline = H + 5 s')
expected_timing = Shop::TIMING.to_h do |name, row|
  [name, { deadline_ms: row[:ready] ? 0 : (row[:helper] + 5) * 1000, cap: row[:cap] }]
end
assert_eq(js_timing, expected_timing, 'js/timing.mjs HELPERS = Shop::TIMING (deadline H + 5 s, cap)')
referenced = []
qml_files.each do |path|
  src = source(path)
  src.to_enum(:scan, /helper:\s*"([a-z-]+)"/).each { referenced << Regexp.last_match(1) }
  next if path.end_with?('model/HelperProcess.qml', 'model/HelperStream.qml')

  src.each_line.with_index(1) do |line, n|
    next unless line.match?(/\b(?:deadline|maxStdoutBytes|maxLineBytes)\s*:\s*\d/)

    assert(false, "#{rel(path)}:#{n}: a deadline or cap literal (js/timing.mjs is the one table)")
  end
  referenced.concat(src.scan(/"([a-z]+(?:-[a-z]+)+)"/).flatten & helpers)
end
# The theme jobs' helpers are named where their argv is built.
referenced.concat(source(File.join(ROOT, 'js', 'themejob.mjs')).scan(/"([a-z]+(?:-[a-z]+)+)"/).flatten & helpers)
unknown = referenced.uniq - helpers
assert(unknown.empty?, "QML references unknown helpers: #{unknown}")
missing = helpers - referenced.uniq
assert(missing.empty?, "every helper is used by the QML or js/themejob.mjs (helper literal set == helpers/): unused #{missing}")

# Every literal Copy.t("key") used by the UI exists in the copy deck
# (js/copy.mjs STRINGS; ui/Copy.qml only forwards to it).
copy_src = source(File.join(ROOT, 'js', 'copy.mjs'))[/^export const STRINGS = \{\n(.*?)^\}$/m, 1].to_s
copy_keys = copy_src.scan(/^\s*"([a-zA-Z0-9_.]+)":/).flatten
assert(copy_keys.size > 300, "js/copy.mjs STRINGS parsed: #{copy_keys.size}")
assert(!source(File.join(ROOT, 'ui', 'Copy.qml')).match?(/^\s*"[a-z]+\.[a-zA-Z0-9_.]+":/), 'ui/Copy.qml holds no strings (js/copy.mjs is their home)')
Dir.glob(File.join(ROOT, '{BarWidget.qml,ui/*.qml,model/*.qml}')).each do |path|
  source(path).scan(/Copy\.t\("([a-zA-Z0-9_.]+)"\s*[,)]/).flatten.uniq.each do |key|
    assert(copy_keys.include?(key), "#{rel(path)}: Copy key #{key} exists")
  end
end

# Delegate stability: ViewHeader action lists carry no reactive state
# (spinning/enabled go in busyIds/disabledIds).
Dir.glob(File.join(ROOT, 'ui', '*.qml')).each do |path|
  src = source(path)
  src.to_enum(:scan, /ViewHeader\s*\{/).each do
    block = src[Regexp.last_match.end(0), 1200].split(/\n  \}/).first.to_s
    list = block[/actions:\s*\[(.*?)\]\s*$/m, 1].to_s
    assert(!list.match?(/\b(?:spinning|enabled)\s*:/), "#{rel(path)}: ViewHeader actions carry no reactive state")
  end
end

# No clipboard read in the shell. Qt reads Wayland clipboard data with no
# size or time bound: a TextInput (TextField, SpinBox, the kit's
# FilterInput and NumberField) reads the whole clipboard whenever it changes
# and on every native paste, and Quickshell.clipboardText reads it too. Text
# entry is ui/LineEdit.qml (TextEdit, paste keys routed to the capped
# helpers/read-clipboard); the only clipboard use left is a write.
# The forbidden set is derived from the shell's kit: Qt's native text
# entry types, plus every kit component (Ui/*.qml) that instantiates one of
# them or, transitively, another kit component that does (SearchableDropdown
# embeds a TextField in its popup). The fixed list is the fallback when the
# kit is not installed.
NATIVE_TEXT_ENTRY = %w[TextInput TextField TextArea SpinBox ComboBox].freeze
KIT_TEXT_ENTRY_FALLBACK = %w[TextField FilterInput NumberField MultiSelect SearchableDropdown].freeze
qml_code = ->(src) { src.gsub(%r{/\*.*?\*/}m, '').gsub(%r{(^|[^:"\\])//.*$}, '\\1') }
instantiated = ->(code) { code.scan(/(?:^|[^A-Za-z0-9_.])(?:[A-Za-z]+\.)?([A-Z][A-Za-z0-9_]*)\s*\{/).flatten.uniq }
kit_dir = File.join(ENV.fetch('OMARCHY_PATH', '/usr/share/omarchy'), 'shell', 'Ui')
kit_text_entry =
  if Dir.exist?(kit_dir)
    uses = Dir.glob(File.join(kit_dir, '*.qml')).to_h { |f| [File.basename(f, '.qml'), instantiated.call(qml_code.call(File.read(f)))] }
    found = []
    loop do
      added = uses.keys.select { |k| !found.include?(k) && !(uses[k] & (NATIVE_TEXT_ENTRY + found)).empty? }
      break if added.empty?

      found.concat(added)
    end
    found.sort
  else
    KIT_TEXT_ENTRY_FALLBACK
  end
assert(kit_text_entry.include?('SearchableDropdown') && kit_text_entry.include?('TextField'), "kit text-entry set derived from #{kit_dir}: #{kit_text_entry}")
forbidden_types = (NATIVE_TEXT_ENTRY + kit_text_entry).uniq
shell_qml = Dir.glob(File.join(ROOT, '{ui,model}', '*.qml')) + %w[Service.qml BarWidget.qml].map { |f| File.join(ROOT, f) }
shell_qml.each do |path|
  code = qml_code.call(source(path))
  bad = instantiated.call(code) & forbidden_types
  assert(bad.empty?, "#{rel(path)}: instantiates #{bad.join(', ')}, which embeds native text entry (LineEdit instead)")
  code.scan(/clipboardText\b(?!\s*=[^=])/) { assert(false, "#{rel(path)}: reads Quickshell.clipboardText") }
  code.scan(/\b(?:edit|root)\.paste\(\)/) { assert(false, "#{rel(path)}: native paste()") }
end
line_edit = source(File.join(ROOT, 'ui', 'LineEdit.qml'))
assert(line_edit.match?(/TextEdit \{\s*\n\s*id: edit/) && line_edit.include?('textFormat: TextEdit.PlainText'), 'LineEdit is a PlainText TextEdit')
assert(line_edit.include?('event.matches(StandardKey.Paste)') && line_edit.include?('Qt.Key_Insert'), 'LineEdit routes every paste key to paste(done)')
assert(line_edit.include?('acceptedButtons: Qt.MiddleButton') && line_edit.include?('DropArea'), 'LineEdit swallows middle-click paste and drops')

# qmldirs: list every .qml, no `module` line.
Dir.glob(File.join(ROOT, '**', 'qmldir')).each do |qmldir|
  text = source(qmldir)
  assert(text.lines.none? { |l| l.match?(/\A\s*module\b/) }, "#{rel(qmldir)}: no module line")
  Dir.glob(File.join(File.dirname(qmldir), '*.qml')).each do |qml|
    assert(text.match?(/\b#{Regexp.escape(File.basename(qml))}\b/), "#{rel(qmldir)} lists #{File.basename(qml)}")
  end
end

# The panel body: the scroll gutter is always reserved (the layout never
# shifts when content starts to overflow) and the bar's handle shows
# whenever it does (the only cue that more sits below the fold).
panel_src = source(File.join(ROOT, 'ui', 'ShopPanel.qml'))
body_width = panel_src[/id: bodyColumn.*?\n\s*width: ([^\n]*)/m, 1].to_s
assert(!body_width.empty? && !body_width.include?('interactive'), "ShopPanel bodyColumn width ignores flick.interactive: #{body_width}")
assert(panel_src.include?('policy: flick.interactive ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff'), 'ShopPanel scroll bar visible whenever the body overflows')
