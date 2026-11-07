# Shop::Validate: domains, targets, ids, roles, zones, labels and preview URLs (scalars only).

require_relative 'support'

V = Shop::Validate

# Domains.
{ 'acme' => 'acme.myshopify.com', 'ACME.myshopify.com' => 'acme.myshopify.com', 'a-1.myshopify.com' => 'a-1.myshopify.com',
  'fen0iz-91' => 'fen0iz-91.myshopify.com' }.each do |input, expected|
  assert_eq(V.normalize_domain(input), expected, "domain #{input.inspect}")
end
['a.myshopify.com.evil.tld', '--x', '../..', "аlpha", '1 --allow-live', "a.myshopify.com\nx", '-acme', 'acme-',
 'acme.myshopify.com/x', '', 'a' * 64, "acme​", 'acme.shopify.com',
 ' https://acme.myshopify.com/admin/themes ', 'http://a-1.myshopify.com/', ' acme'].each do |bad|
  assert(V.normalize_domain(bad).nil?, "rejects domain #{bad.inspect}")
end
assert_eq(failure_code { V.domain!('evil.tld') }, 'invalid_argument', 'domain! raises invalid_argument')
begin
  V.domain!("evil\e[31m.tld#{'x' * 100}")
rescue Shop::Failure => e
  assert(e.message.start_with?('not a .myshopify.com domain: "evil.tld') && e.message.length < 80, "the echo is cleaned, quoted and capped (#{e.message})")
end

# Push and pull targets (live or a theme id), ids, cursors.
%w[live 1 160258293983].each { |t| assert_eq(V.target!(t), t, "target #{t}") }
['0', '01', 'Live', '1 --allow-live', '-1', '1' * 21, ''].each do |t|
  assert_eq(failure_code { V.target!(t) }, 'invalid_argument', "rejects target #{t.inspect}")
end
assert(V.theme_id?('160258293983') && !V.theme_id?('0') && !V.theme_id?('live'), 'theme ids are 1-20 digits, no leading zero')
assert(V.backup_id?('1762500000-160258293983') && !V.backup_id?('1762500000') && !V.backup_id?('../1762500000-1'), 'backup ids')
assert_eq(V.backup_id!('1762500000-160258293983'), '1762500000-160258293983', 'backup_id! returns the id')
assert_eq(failure_code { V.backup_id!('1762500000') }, 'invalid_argument', 'a bare epoch is not a backup id')
assert(V.epoch?('1762500000') && !V.epoch?('0762500000') && !V.epoch?('176250000'), 'epochs')
assert(V.org_id?('123') && !V.org_id?('gid://shopify/Organization/42') && !V.org_id?('1;rm') && !V.org_id?('1' * 21), 'org ids: 1-20 digits')
assert(V.cursor?('eyJsYXN0X2lkIjo1fQ==') && !V.cursor?('a b') && !V.cursor?('') && !V.cursor?('x' * 1025), 'cursors')

# Theme roles: the CLI's lowercase words, anything else is 'unknown'.
%w[live unpublished development demo].each { |r| assert_eq(V.role(r), r, "role #{r}") }
["Live", "main\e[1m", '', nil, 42, 'x' * 40].each { |r| assert_eq(V.role(r), 'unknown', "role #{r.inspect} -> unknown") }

# Timezones: a real zone from the system database, else UTC.
assert_eq(V.timezone('America/Toronto'), 'America/Toronto', 'real zone')
assert_eq(V.timezone('America/Argentina/Buenos_Aires'), 'America/Argentina/Buenos_Aires', 'three-part zone')
['../../etc/passwd', 'Nope/Zone', 'America/../../etc', '', nil, 'UTC; rm', 'a/b/c/d/e', "Europe/Paris\n"].each do |tz|
  assert_eq(V.timezone(tz), 'UTC', "bad zone #{tz.inspect} falls back to UTC")
end
assert_eq(failure_code { V.timezone!('Nope/Zone') }, 'invalid_argument', 'timezone! rejects unknown zones')
assert_eq(V.timezone!('UTC'), 'UTC', 'timezone! accepts UTC')

# Labels (user-visible names from remote data).
assert_eq(V.label("  Acme‮ Apparel "), 'Acme Apparel', 'label cleaned')
assert(V.label('   ').nil? && V.label(nil).nil? && V.label(42).nil?, 'empty or non-string labels are nil')
assert_eq(V.label('x' * 100).length, V::LABEL_MAX, "labels are capped at #{V::LABEL_MAX}")

# DOMAIN is built from the one DNS label rule.
assert(V::DOMAIN.source.include?(V::DNS_LABEL.source), 'DOMAIN embeds DNS_LABEL')
assert(V.normalize_domain('a' * 63).end_with?(V::DOMAIN_SUFFIX) && V.normalize_domain('a' * 64).nil?, 'a bare label is 1-63 chars')

# reject! is the one invalid_argument raiser.
assert_eq(failure_code { V.reject!('nope') }, 'invalid_argument', 'reject!')
