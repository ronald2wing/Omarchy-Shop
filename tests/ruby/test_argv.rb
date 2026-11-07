# Shop::Argv: the long-flag grammar, required flags and strict UTF-8.

require_relative 'support'

A = Shop::Argv

# parse: the long-flag grammar.
usage = 'usage'
assert_eq(A.parse(%w[--a=1 --b 2 --s], values: %w[a b], switches: %w[s], usage: usage), { 'a' => '1', 'b' => '2', 's' => true }, 'values and switches')
assert_eq(A.parse([], values: %w[a], switches: [], usage: usage), {}, 'nothing given')
[%w[--a], %w[--a=], %w[--a --b=1], %w[--a=1 --a=2], %w[--s=1], %w[--zz], %w[stray], %w[-a 1]].each do |argv|
  assert_eq(failure_code { A.parse(argv, values: %w[a b], switches: %w[s], usage: usage) }, 'invalid_argument', "usage error for #{argv}")
end

# required: a value flag that must be given.
assert_eq(A.parse(%w[--a=1], values: %w[a b], required: %w[a], usage: usage), { 'a' => '1' }, 'a required flag given')
begin
  A.parse(%w[--a=1], values: %w[a b], required: %w[a b], usage: usage)
  assert(false, 'a missing required flag must raise')
rescue Shop::Failure => e
  assert_eq([e.code, e.message], ['invalid_argument', 'missing --b'], 'required names the missing flag')
end
begin
  A.parse(["--z\e[1m#{'z' * 80}"], values: %w[a], usage: usage)
rescue Shop::Failure => e
  assert(e.message.start_with?('unknown flag: "--zz') && e.message.length < 60, "an unknown flag is quoted and capped (#{e.message})")
end
assert_eq(failure_code { A.utf8!("caf\xFF".b) }, 'invalid_argument', 'utf8! refuses invalid UTF-8')
assert_eq(A.utf8!('thème'.b).encoding, Encoding::UTF_8, 'utf8! reads the bytes as UTF-8')
