# Shop::Throttle: the cost budget of a response, the retryAfter it implies and the wait between order pages.

require_relative 'support'

T = Shop::Throttle

# budget: the two cost extensions in a compact form.
ext = fixture_json('today.json')['extensions']
b = T.budget(ext)
assert_eq(b['graphql'], { 'available' => 1970, 'restoreRate' => 100, 'requested' => 35 }, 'graphql budget')
assert_eq(b['shopifyql']['resetAt'], Time.utc(2026, 11, 7, 15, 1).to_i * 1000, 'resetAt in ms')
assert(T.budget(nil).nil? && T.budget({}).nil? && T.budget({ 'cost' => 'x' }).nil?, 'no cost -> nil')

# retry_after: explicit first, then the cost restore rate, then the ShopifyQL
# window, else 60 s; always 1..3600 whole seconds.
assert_eq(T.retry_after({ 'extensions' => { 'retryAfter' => 7.2 } }), 8, 'an explicit retryAfter, rounded up')
cost = { 'cost' => { 'requestedQueryCost' => 500, 'throttleStatus' => { 'currentlyAvailable' => 100, 'restoreRate' => 50 } } }
assert_eq(T.retry_after({ 'extensions' => cost }), 8, 'from the restore rate: (500-100)/50')
assert_eq(T.retry_after({}), 60, 'nothing known -> 60 s')
assert_eq(T.retry_after({ 'extensions' => { 'retryAfter' => 99_999 } }), 3600, 'capped at an hour')
assert(T.explicit_retry_after({}, [{ 'extensions' => { 'retryAfter' => 0 } }]).nil?, 'a zero retryAfter is not stated')

# page_wait: until two more pages of the last cost fit, else nil.
graphql = ->(available, requested, rate) { { 'graphql' => { 'available' => available, 'requested' => requested, 'restoreRate' => rate } } }
assert(T.page_wait(graphql.call(1990, 10, 100)).nil?, 'enough budget -> no wait')
assert_eq(T.page_wait(graphql.call(100, 100, 50)), 2.0, 'short by 100 at 50/s -> 2 s')
assert(T.page_wait(graphql.call(0, 100, 0)).nil? && T.page_wait(nil).nil?, 'no restore rate or no budget -> no wait')
assert_eq(T.page_wait(graphql.call(0, 10_000, 1)), T::MAX_PAGE_WAIT, 'a long wait is clamped to MAX_PAGE_WAIT')
