# Test launcher: runs one helper in a fresh interpreter with test overrides (tool paths, system PATH, deadlines, clock).
# usage: ruby launcher.rb <helper-name> <overrides-json> [helper args...]

require_relative '../../lib/shop'

name = ARGV.shift
overrides = JSON.parse(ARGV.shift, symbolize_names: true)
load File.join(Shop::ROOT, 'helpers', name)
Shop::Helpers.const_get(name.split('-').map(&:capitalize).join).run(ARGV, **overrides)
