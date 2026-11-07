# Shop::Stores: auth sessions, store/org listings (with truncation) and the merge (dedupe, names, natural sort, cap).

require_relative 'support'

St = Shop::Stores

auth = St.from_auth_sessions(fixture_json('store-auth-list.json'))
assert_eq(auth, %w[alpha.myshopify.com beta.myshopify.com], 'sessions with both scopes; bad domains and missing scopes dropped')
assert_eq(St.from_auth_sessions(fixture_json('store-auth-list-implied.json')), %w[kappa.myshopify.com], 'write_orders + read_reports counts; write_products + read_reports does not')
# A write scope implies its read scope, as the pinned CLI's
# expandImpliedStoreAuthScopes says (its grant merge drops read_orders when
# write_orders is held, so such a session is stored without read_orders).
session = ->(scopes) { St.from_auth_sessions({ 'sessions' => [{ 'store' => 'a.myshopify.com', 'scopes' => scopes }] }) }
assert_eq(session.call(%w[write_orders read_reports]), %w[a.myshopify.com], 'write_orders + read_reports is access')
assert_eq(session.call(%w[write_orders write_reports]), %w[a.myshopify.com], 'write_orders + write_reports is access')
assert_eq(session.call(%w[write_products read_reports]), [], 'write_products implies nothing Shop needs')
assert_eq(session.call(%w[unauthenticated_write_orders read_reports]), [], 'unauthenticated_write_orders implies only unauthenticated_read_orders')
assert_eq(St.implied_scopes(%w[write_orders unauthenticated_write_x]), %w[write_orders unauthenticated_write_x read_orders unauthenticated_read_x], 'implied_scopes adds read_X for write_X')
assert_eq(failure_code { St.from_auth_sessions({}) }, 'bad_response', 'no sessions array -> bad_response')

rows, truncated = St.from_store_list(fixture_json('store-list.json'))
assert_eq(rows, [{ 'domain' => 'alpha.myshopify.com', 'name' => 'Alpha Apparel' }, { 'domain' => 'gamma.myshopify.com', 'name' => 'Gamma 10' }], 'store rows')
assert_eq(truncated, false, 'a plain listing is complete')
rows, truncated = St.from_store_list(fixture_json('store-list-truncated.json'))
assert_eq([rows.size, truncated], [2, true], 'a notice next to rows means the listing was cut')
rows, truncated = St.from_store_list(fixture_json('store-list-notice.json'))
assert_eq([rows, truncated], [[], false], 'a notice with no rows is not truncation (the caller treats it as unknown)')
assert_eq(St.from_store_list({ 'stores' => [], 'truncated' => true })[1], true, 'an explicit truncated flag')
assert_eq(failure_code { St.from_store_list({ 'stores' => 'x' }) }, 'bad_response', 'no stores array -> bad_response')

assert_eq(St.org_ids(fixture_json('organization-list.json')), %w[100 200], 'orgs with shops only')
assert_eq(failure_code { St.org_ids({ 'organizations' => 'x' }) }, 'bad_response', 'bad org list -> bad_response')

stores, truncated = St.merge(session_domains: auth, rows: rows.empty? ? St.from_store_list(fixture_json('store-list.json'))[0] + [{ 'domain' => 'gamma2.myshopify.com', 'name' => 'Gamma 9' }] : [],
                             names: { 'beta.myshopify.com' => "Beta\u0007 Goods" })
assert_eq(stores, [
  { 'domain' => 'alpha.myshopify.com', 'name' => 'Alpha Apparel' },
  { 'domain' => 'beta.myshopify.com', 'name' => 'Beta Goods' },
  { 'domain' => 'gamma2.myshopify.com', 'name' => 'Gamma 9' },
  { 'domain' => 'gamma.myshopify.com', 'name' => 'Gamma 10' }
], 'merged, deduped, cleaned, natural order; a row is exactly {domain, name}')
assert(!truncated, 'not truncated')
stores, = St.merge(session_domains: ['zeta.myshopify.com'], rows: [], names: {})
assert_eq(stores.first['name'], 'zeta', 'no name -> the subdomain')
assert_eq(St.subdomain_label('a-1.myshopify.com'), 'a-1', 'subdomain_label')

many = (1..520).map { |i| { 'domain' => "s#{i}.myshopify.com", 'name' => "S #{i}" } }
stores, truncated = St.merge(session_domains: [], rows: many, names: {})
assert(stores.size == 500 && truncated && stores.last['name'] == 'S 500', 'capped at 500 in natural order')

# Every listing argv is JSON, CI and here.
[St::LIST_ARGS, St::AUTH_LIST_ARGS, St::ORG_LIST_ARGS].each { |args| assert(args.frozen? && args.last(2) == %w[--json --no-input], "#{args.join(' ')}: --json --no-input") }
assert_eq(St.org_store_list_args('100'), %w[store list --organization-id=100 --json --no-input], 'one organization listing')
assert_eq(St.subdomain_label('alpha.myshopify.com'), 'alpha', 'the label drops Validate::DOMAIN_SUFFIX')
