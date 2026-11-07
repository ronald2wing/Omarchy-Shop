# Contract checks over the suite's shape: every helper, lib module and JS module has its own test file, and every test file belongs to one.

require_relative 'support'

ruby_tests = Dir.glob(File.join(ROOT, 'tests', 'ruby', 'test_*.rb')).map { |p| File.basename(p, '.rb').delete_prefix('test_') }
js_tests = Dir.glob(File.join(ROOT, 'tests', 'js', 'test_*.mjs')).map { |p| File.basename(p, '.mjs').delete_prefix('test_') }
lib_modules = Dir.glob(File.join(ROOT, 'lib', 'shop', '*.rb')).map { |p| File.basename(p, '.rb') }
js_modules = Dir.glob(File.join(ROOT, 'js', '*.mjs')).map { |p| File.basename(p, '.mjs') }

# helpers/<name> -> tests/ruby/test_helper_<name with _>.rb.
helper_tests = helper_names.to_h { |h| [h, "helper_#{h.tr('-', '_')}"] }
helper_tests.each { |h, t| assert(ruby_tests.include?(t), "helpers/#{h} has tests/ruby/test_#{t}.rb") }

# lib/shop/<m>.rb -> tests/ruby/test_<m>.rb, with two exceptions:
# Shop::Child only runs under Shop::Command, so test_command.rb covers it,
# and the test_helper_ prefix belongs to helpers/, so lib/shop/helper_main.rb
# is tested by test_main.rb.
LIB_TESTS = { 'child' => 'command', 'helper_main' => 'main' }.freeze
lib_tests = lib_modules.to_h { |m| [m, LIB_TESTS.fetch(m, m)] }
lib_tests.each { |m, t| assert(ruby_tests.include?(t), "lib/shop/#{m}.rb has tests/ruby/test_#{t}.rb") }
assert(LIB_TESTS.keys.all? { |m| lib_modules.include?(m) }, "LIB_TESTS names only lib modules: #{LIB_TESTS.keys - lib_modules}")
assert(!ruby_tests.include?('child') && !ruby_tests.include?('helper_main'), 'no test file under the excepted names')

# js/<m>.mjs -> tests/js/test_<m>.mjs.
js_modules.each { |m| assert(js_tests.include?(m), "js/#{m}.mjs has tests/js/test_#{m}.mjs") }

# The other way round: a Ruby test is a helper's, a lib module's or a
# source contract (test_contracts_*); a JS test is a module's or one of the
# two checks across every module.
JS_CROSS = %w[copy_keys js_subset].freeze
(ruby_tests - helper_tests.values - lib_tests.values).each do |t|
  assert(t.start_with?('contracts_'), "tests/ruby/test_#{t}.rb tests no helper or lib module (name it after one, or test_contracts_*)")
end
(js_tests - js_modules).each do |t|
  assert(JS_CROSS.include?(t), "tests/js/test_#{t}.mjs tests no js/ module")
end
