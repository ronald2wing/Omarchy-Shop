# Contract checks that the canned fetch-sales results the JS tests read (tests/js/fixtures/) have the shape fetch-sales really prints against the fake CLI: the same key paths, and the same JSON type wherever both sides hold a value.

require_relative 'support'

# Every key path of a JSON value ("history.last7d.buckets[].date"), with
# the JSON type at it (nil for null). An array contributes the union of its
# elements' paths.
def shape(value, prefix = '', out = {})
  case value
  when Hash
    value.each do |k, v|
      path = prefix.empty? ? k : "#{prefix}.#{k}"
      out[path] = (out[path] || []) | [json_type(v)]
      shape(v, path, out)
    end
  when Array then value.each { |v| shape(v, "#{prefix}[]", out) }
  end
  out
end

def json_type(value)
  case value
  when nil then nil
  when Hash then 'object'
  when Array then 'array'
  when String then 'string'
  when true, false then 'boolean'
  else 'number'
  end
end

def assert_same_shape(fixture_name, real)
  fixture = shape(JSON.parse(File.read(File.join(ROOT, 'tests', 'js', 'fixtures', fixture_name))))
  real = shape(real)
  assert_eq(fixture.keys.sort - real.keys, [], "tests/js/fixtures/#{fixture_name}: key paths fetch-sales never prints")
  assert_eq(real.keys.sort - fixture.keys, [], "tests/js/fixtures/#{fixture_name}: key paths fetch-sales prints that the fixture lacks")
  (fixture.keys & real.keys).each do |path|
    a = fixture[path].compact
    b = real[path].compact
    next if a.empty? || b.empty?

    assert((a - b).empty?, "tests/js/fixtures/#{fixture_name}: #{path} is #{a.join('/')}, fetch-sales prints #{b.join('/')}")
  end
end

with_home do |home|
  args = ['--store=acme.myshopify.com', '--timezone=America/New_York', '--with-traffic']
  %w[today yesterday history].each do |range|
    status, out, = run_one('fetch-sales', "--range=#{range}", *args, home: home, overrides: { now: NOW })
    assert_eq([status, out['ok']], [0, true], "fetch-sales --range=#{range} succeeds against the fake CLI")
    assert_same_shape("#{range}.json", out)
  end
  home.scenario!('scope-denied')
  status, out, = run_one('fetch-sales', '--range=today', *args, home: home, overrides: { now: NOW })
  assert_eq([status, out.dig('error', 'code')], [1, 'sales_access_required'], 'fetch-sales without sales access')
  assert_same_shape('fetch-error.json', out)
end
