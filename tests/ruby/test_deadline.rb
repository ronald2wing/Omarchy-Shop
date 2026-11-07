# Shop::Deadline: a monotonic budget (remaining, expired?) and cap, which never hands a child less than a small floor.

require_relative 'support'

D = Shop::Deadline

d = D.new(10)
assert(d.remaining > 9.5 && d.remaining <= 10 && !d.expired?, 'a fresh budget')
assert_eq(d.cap(3), 3, 'cap: the smaller of the step and what is left')
assert(d.cap(60) <= 10, 'cap never exceeds the budget')
spent = D.new(0)
assert(spent.expired?, 'a zero budget is expired')
assert_eq(spent.cap(5), 0.05, 'a spent budget still yields the 50 ms floor')

assert_eq(D::MIN_SECONDS, 0.05, 'the floor is MIN_SECONDS')
