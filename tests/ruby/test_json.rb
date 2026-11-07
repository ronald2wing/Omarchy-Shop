# Shop::Json: the nil-safe dig, bounded parses to an object or nil, and the bounded file read.

require_relative 'support'

J = Shop::Json

# dig: the nil-safe walk into outside JSON; any non-Hash step gives nil.
assert_eq(J.dig({ 'a' => { 'b' => 1 } }, 'a', 'b'), 1, 'dig walks hashes')
assert(J.dig({ 'a' => 'x' }, 'a', 'b').nil? && J.dig({ 'a' => [1] }, 'a', 'b').nil? && J.dig('x', 'a').nil? && J.dig(nil, 'a').nil?,
       'dig: a string, array or nil on the way is nil, never a TypeError')
assert_eq(J.dig({ 'a' => 1 }), { 'a' => 1 }, 'dig with no keys is the object')

# object: a JSON object or nil.
assert_eq(J.object('{"a":1}'), { 'a' => 1 }, 'an object')
['[1]', '"x"', '{', '', nil].each do |text|
  assert(J.object(text).nil?, "not an object: #{text.inspect}")
end
assert(J.object("#{'[' * 100}#{']' * 100}").nil?, 'nesting past MAX_NESTING')
assert(J.object('{"a":{"b":{}}}', max_nesting: 2).nil? && J.object('{"a":{}}', max_nesting: 2), 'max_nesting is the caller\'s')

# read_object: the first max_bytes of a file, parsed.
Dir.mktmpdir do |dir|
  file = File.join(dir, 'p.json')
  File.write(file, '{"version":"1"}')
  assert_eq(J.read_object(file, max_bytes: 100, max_nesting: 4), { 'version' => '1' }, 'reads a small object')
  assert(J.read_object(file, max_bytes: 5, max_nesting: 4).nil?, 'a file past max_bytes reads truncated: nil')
  File.write(file, '')
  assert(J.read_object(file, max_bytes: 100, max_nesting: 4).nil?, 'an empty file is nil')
  assert(J.read_object(File.join(dir, 'missing'), max_bytes: 100, max_nesting: 4).nil?, 'a missing file is nil')
end
