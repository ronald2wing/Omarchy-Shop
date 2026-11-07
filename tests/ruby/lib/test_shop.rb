# lib/shop.rb: Shop.seconds (a deadline from Shop::TIMING, a number, or the
# deadlines override), Shop.now and the override seam behind both.

require_relative '../support'

push = Shop::TIMING.fetch('push-theme')
Shop.override!({})
assert_eq(Shop.overrides, {}, 'no overrides by default')

# Each kind reads its own field of the row; a number is its own deadline.
assert_eq(Shop.seconds(:overall, 'push-theme'), push[:overall], 'overall: the row H')
assert_eq(Shop.seconds(:call, 'push-theme', 'list'), push[:calls]['list'], 'a named step of the row')
assert_eq(Shop.seconds(:call, 'notify-order'), Shop::TIMING.fetch('notify-order')[:calls]['call'], 'no step: the kind names the call')
assert_eq(Shop.seconds(:ready, 'preview-theme'), Shop::TIMING.fetch('preview-theme')[:ready], 'ready: the streamer row')
assert_eq(Shop.seconds(:recheck, 15), 15, 'a numeric source is the default')
assert_eq(raised(KeyError) { Shop.seconds(:overall, 'no-such-helper') }.class, KeyError, 'an unknown row is a KeyError')
assert_eq(raised(KeyError) { Shop.seconds(:call, 'push-theme', 'nope') }.class, KeyError, 'an unknown step is a KeyError')

# The deadlines override wins for its kind only, and only as a positive number.
Shop.override!(deadlines: { overall: 3, call: 0.5 })
assert(Shop.overrides.frozen?, 'override! freezes what it keeps')
assert_eq(Shop.seconds(:overall, 'push-theme'), 3, 'the overall override wins')
assert_eq(Shop.seconds(:call, 'push-theme', 'list'), 0.5, 'the call override wins over a named step')
assert_eq(Shop.seconds(:recheck, 15), 15, 'another kind keeps its default')
[0, -1, '5', nil].each do |bad|
  Shop.override!(deadlines: { overall: bad })
  assert_eq(Shop.seconds(:overall, 'push-theme'), push[:overall], "a #{bad.inspect} override is ignored")
end

# now: the override (epoch seconds) as a Time, else the clock.
Shop.override!(now: 1_762_500_000)
assert_eq(Shop.now, Time.at(1_762_500_000), 'the now override')
Shop.override!(now: 'soon')
assert((Shop.now - Time.now).abs < 5, 'a non-numeric now override is ignored')
Shop.override!({})
assert((Shop.now - Time.now).abs < 5, 'no override: the clock')
