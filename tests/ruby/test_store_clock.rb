# Shop::StoreClock: store-local boundaries, DST, offsets, local hours.

require_relative 'support'

C = Shop::StoreClock
ENV['TZ'] = 'Asia/Tokyo'

Shop.override!(now: NOW)
b = C.boundaries('America/New_York')
assert_eq(C.iso(b[:today_start]), '2026-11-07T05:00:00Z', 'today starts at local midnight')
assert_eq(C.iso(b[:yesterday_start]), '2026-11-06T05:00:00Z', 'yesterday started at its local midnight')
assert_eq([b[:local_date], b[:yesterday_date]], %w[2026-11-07 2026-11-06], 'local dates')
assert_eq(b[:utc_offset_minutes], -300, 'EST offset')
assert_eq(b[:day_ends_at_ms], Time.utc(2026, 11, 8, 5).to_i * 1000, 'next local midnight')
assert_eq(ENV['TZ'], 'Asia/Tokyo', 'TZ restored')

Shop.override!(now: Time.utc(2026, 11, 2, 12).to_i)
dst = C.boundaries('America/New_York')
assert_eq(((dst[:today_start] - dst[:yesterday_start]) / 3600).round, 25, 'the fall-back day has 25 hours')
Shop.override!(now: Time.utc(2026, 11, 7, 16).to_i)
tokyo = C.boundaries('Asia/Tokyo')
assert_eq(tokyo[:local_date], '2026-11-08', 'Tokyo is already tomorrow')
assert_eq(tokyo[:utc_offset_minutes], 540, 'Tokyo offset')
ENV.delete('TZ')
Shop.override!(now: NOW)
C.boundaries('UTC')
assert(!ENV.key?('TZ'), 'an unset TZ stays unset')
