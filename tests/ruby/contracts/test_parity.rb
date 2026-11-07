# Contract checks over the suite's shape: every helper, lib module (lib/shop.rb included) and JS module has its own test file, every panel view its own smoke, and every test file belongs to one.

require_relative '../support'

# tests/ruby/<kind>/test_<name>.rb -> <name>, per kind.
ruby_tests = ->(kind) { Dir.glob(File.join(ROOT, 'tests', 'ruby', kind, 'test_*.rb')).map { |p| File.basename(p, '.rb').delete_prefix('test_') } }
helper_test_names = ruby_tests.call('helpers')
lib_test_names = ruby_tests.call('lib')
contract_test_names = ruby_tests.call('contracts')
assert(contract_test_names.size >= 5, "tests/ruby/contracts/test_*.rb found (#{contract_test_names})")
assert_eq(Dir.glob(File.join(ROOT, 'tests', 'ruby', '*', '*.rb')).map { |p| File.basename(p) }.reject { |f| f.start_with?('test_') }, [],
          'tests/ruby/<kind>/ holds only test_*.rb (shared code sits in tests/ruby/)')
assert_eq(Dir.glob(File.join(ROOT, 'tests', 'ruby', '*/')).map { |p| File.basename(p) }.sort, %w[contracts helpers lib],
          'tests/ruby/ has the three kinds: contracts, helpers, lib')
assert_eq(Dir.glob(File.join(ROOT, 'tests', 'ruby', 'test_*.rb')), [], 'no test file at the top of tests/ruby/ (each sits under its kind)')
js_tests = Dir.glob(File.join(ROOT, 'tests', 'js', 'test_*.mjs')).map { |p| File.basename(p, '.mjs').delete_prefix('test_') }
lib_modules = Dir.glob(File.join(ROOT, 'lib', '{shop.rb,shop/*.rb}')).map { |p| File.basename(p, '.rb') }
assert(lib_modules.include?('shop') && lib_modules.size > 20, "lib/shop.rb and lib/shop/*.rb found (#{lib_modules.size})")
js_modules = Dir.glob(File.join(ROOT, 'js', '*.mjs')).map { |p| File.basename(p, '.mjs') }

# helpers/<name> -> tests/ruby/helpers/test_<name with _>.rb, and every
# file there is a helper's.
helper_tests = helper_names.map { |h| h.tr('-', '_') }
helper_tests.each { |t| assert(helper_test_names.include?(t), "helpers/#{t.tr('_', '-')} has tests/ruby/helpers/test_#{t}.rb") }
(helper_test_names - helper_tests).each { |t| assert(false, "tests/ruby/helpers/test_#{t}.rb tests no helper") }

# lib/shop.rb -> tests/ruby/lib/test_shop.rb, lib/shop/<m>.rb ->
# tests/ruby/lib/test_<m>.rb, and every file there is a module's. One
# exception: Shop::Child only runs under Shop::Command, so test_command.rb
# covers it.
LIB_TESTS = { 'child' => 'command' }.freeze
lib_tests = lib_modules.map { |m| LIB_TESTS.fetch(m, m) }.uniq
lib_modules.each { |m| assert(lib_test_names.include?(LIB_TESTS.fetch(m, m)), "lib/#{m == 'shop' ? 'shop' : "shop/#{m}"}.rb has tests/ruby/lib/test_#{LIB_TESTS.fetch(m, m)}.rb") }
assert(LIB_TESTS.keys.all? { |m| lib_modules.include?(m) }, "LIB_TESTS names only lib modules: #{LIB_TESTS.keys - lib_modules}")
assert(LIB_TESTS.keys.none? { |m| lib_test_names.include?(m) }, 'no test file under an excepted name')
(lib_test_names - lib_tests).each { |t| assert(false, "tests/ruby/lib/test_#{t}.rb tests no lib module") }

# js/<m>.mjs -> tests/js/test_<m>.mjs.
js_modules.each { |m| assert(js_tests.include?(m), "js/#{m}.mjs has tests/js/test_#{m}.mjs") }

# The other way round: a JS test is a module's or one of the checks
# across every module.
JS_CROSS = %w[copy_keys exports js_subset].freeze
(js_tests - js_modules).each do |t|
  assert(JS_CROSS.include?(t), "tests/js/test_#{t}.mjs tests no js/ module")
end

# ui/<Name>View.qml (PanelView is the frame, not a view) ->
# tests/qml/panel_<name>_smoke.qml, name being the view's name without
# StoreView or View, lower-cased (StoreView itself is store); every other
# smoke is one of OTHER_SMOKES. Each smoke's Smoke name is its file name
# upper-cased without _smoke, the <NAME>_OK token tests/run waits for.
OTHER_SMOKES = %w[js_modules consent service bar_widget dialog model_doubles].freeze
smokes = Dir.glob(File.join(ROOT, 'tests', 'qml', '*_smoke.qml')).map { |p| File.basename(p, '.qml').delete_suffix('_smoke') }
views = Dir.glob(File.join(ROOT, 'ui', '*View.qml')).map { |p| File.basename(p, '.qml') } - %w[PanelView]
assert(views.size >= 6, "ui/*View.qml found (#{views})")
view_smokes = views.map { |v| "panel_#{(v == 'StoreView' ? 'store' : v.delete_suffix('View').delete_suffix('Store')).downcase}" }
view_smokes.zip(views).each { |s, v| assert(smokes.include?(s), "ui/#{v}.qml has tests/qml/#{s}_smoke.qml") }
assert_eq((smokes - view_smokes).sort, OTHER_SMOKES.sort, 'every other smoke is one of OTHER_SMOKES, and each exists')
smokes.each do |s|
  names = source("tests/qml/#{s}_smoke.qml").scan(/^\s*name: "([A-Z_]+)"$/).flatten
  assert_eq(names, [s.upcase], "tests/qml/#{s}_smoke.qml's Smoke name is #{s.upcase} (tests/run waits for #{s.upcase}_OK)")
end
