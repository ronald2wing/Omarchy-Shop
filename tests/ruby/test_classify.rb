# Shop::Classify: the error-code table over the CLI's JSON error body; stderr and GraphQL text never classify a session.

require_relative 'support'

Cl = Shop::Classify

# Every case here is a finished call that failed unless it says otherwise.
def result(stdout, exit_code: 1, **rest) = cli_result(stdout, exit_code: exit_code, **rest)

def failure_of(res, theme: false)
  Cl.check!(res, theme: theme)
  nil
rescue Shop::Failure => e
  e
end

def code_of(res, theme: false) = failure_of(res, theme: theme)&.code

def body(message, try: nil, next_steps: nil)
  err = { 'type' => 'abort', 'message' => message }
  err['tryMessage'] = try if try
  err['nextSteps'] = next_steps if next_steps
  JSON.generate({ 'error' => err })
end

def gql(errors, extensions: nil)
  err = { 'type' => 'abort', 'message' => 'GraphQL operation failed.', 'details' => { 'errors' => errors } }
  err['details']['extensions'] = extensions if extensions
  JSON.generate({ 'error' => err })
end

# Timeouts and overflow come first, whatever the body says.
assert_eq(code_of(result('', timed_out: true)), 'timeout', 'timed out')
assert_eq(code_of(result('{"error":{"message":"x"}}', overflowed: true)), 'output_too_large', 'overflowed')

# Exit 0 is never a failure; a 'partial' push result with exit 1 is a result.
assert(code_of(result('{"themes":[]}', exit_code: 0)).nil?, 'exit 0 passes')
assert(code_of(result('{"status":"partial","issues":[]}', exit_code: 1)).nil?, 'partial + exit 1 is a result, not a failure')
assert_eq(code_of(result('{"status":"success"}', exit_code: 2)), 'cli_failed', 'any other non-zero exit is cli_failed')
assert_eq(code_of(result('', exit_code: 1, stderr: "warn\nboom")), 'cli_failed', 'no body -> cli_failed')
assert_eq(failure_of(result('', exit_code: 1, stderr: "warn\nboom")).message, 'boom', 'the last stderr line is the message')
assert_eq(failure_of(result('', exit_code: 1, stderr: "warn\nboom")).details, %w[warn boom], 'stderr feeds details only')
assert_eq(code_of(result('not json', exit_code: 1)), 'cli_failed', 'non-JSON stdout on failure -> cli_failed')

# ---- the table, by the CLI's own message / tryMessage ----
# Sales access: the stored app auth is gone or unusable, or the
# account may not use the CLI on that store.
sales_access = [
  'Stored app authentication for alpha.myshopify.com is no longer valid.',
  'Token refresh failed for alpha.myshopify.com (HTTP 401).',
  'Token refresh returned an invalid response for alpha.myshopify.com.',
  'No refresh token stored for alpha.myshopify.com.',
  'The preview store alpha.myshopify.com has likely been claimed, so its stored authentication is no longer valid.',
  'No stored app authentication found for alpha.myshopify.com.',
  'You are not authorized to use the CLI to develop in the provided store.',
  "You don't have the necessary permissions to perform this action."
]
sales_access.each { |m| assert_eq(code_of(result(body(m))), 'sales_access_required', "sales_access_required: #{m}") }
assert_eq(code_of(result(fixture_text('error-not-staff.json'))), 'sales_access_required', 'not-staff fixture')
assert_eq(code_of(result(fixture_text('error-store-auth-invalid.json'))), 'sales_access_required', 'store-auth-invalid fixture')
assert_eq(code_of(result(fixture_text('error-no-refresh-token.json'))), 'sales_access_required', 'no-refresh-token fixture')
assert_eq(code_of(result(fixture_text('error-not-authed.json'))), 'sales_access_required', 'not-authed fixture')
assert_eq(code_of(result(fixture_text('error-scope.json'))), 'sales_access_required', 'ACCESS_DENIED extensions code')
assert_eq(failure_of(result(fixture_text('error-scope.json'))).message,
          'Access denied for shopifyqlQuery field. Required access: `read_reports` access scope.', 'the GraphQL message is shown')
app_errors = JSON.generate({ 'errors' => [{ 'message' => 'nope' }],
                             'extensions' => { 'app_errors' => { 'errors' => [{ 'category' => 'ACCESS_DENIED', 'message' => 'x' }] } } })
assert_eq(code_of(result(app_errors)), 'sales_access_required', 'app_errors category access_denied')
# A theme command's access refusal comes from the account-token exchange
# (the pinned CLI's theme commands never use `store auth`): a grant cannot fix it,
# so it is cli_failed with the CLI's own sentence, never "Sales access needed".
theme_fail = failure_of(result(fixture_text('error-not-staff.json')), theme: true)
assert_eq([theme_fail.code, theme_fail.message], ['cli_failed', 'You are not authorized to use the CLI to develop in the provided store.'], 'theme: not-staff is cli_failed with the CLI message')
sales_access.each { |m| assert_eq(code_of(result(body(m)), theme: true), 'cli_failed', "theme: #{m}") }
assert(code_of(result(app_errors), theme: true) != 'sales_access_required', 'theme: app_errors access_denied is not sales_access_required')
assert(code_of(result(fixture_text('error-scope.json')), theme: true) != 'sales_access_required', 'theme: ACCESS_DENIED is not sales_access_required')

# Multi-org (internal).
assert_eq(code_of(result(fixture_text('error-multi-org.json'))), 'multi_org', 'multi_org')

# Rate limited with retryAfter.
assert_eq(code_of(result(fixture_text('error-throttled.json'))), 'rate_limited', 'THROTTLED code')
assert_eq(code_of(result(gql([{ 'message' => 'x', 'extensions' => { 'code' => '429' } }]))), 'rate_limited', '"429" code')
assert_eq(code_of(result(body('Too Many Requests'))), 'rate_limited', 'Too Many Requests text')
explicit = failure_of(result(gql([{ 'message' => 'slow down', 'extensions' => { 'retryAfter' => 7.2 } }])))
assert_eq([explicit.code, explicit.extra[:retryAfter]], ['rate_limited', 8], 'an explicit retryAfter is used (ceil)')
cost = { 'cost' => { 'requestedQueryCost' => 500, 'throttleStatus' => { 'currentlyAvailable' => 100, 'restoreRate' => 50 } } }
budgeted = failure_of(result(gql([{ 'message' => 'Throttled', 'extensions' => { 'code' => 'THROTTLED' } }], extensions: cost)))
assert_eq(budgeted.extra[:retryAfter], 8, 'retryAfter from the cost extensions: (500-100)/50')
plain = failure_of(result(fixture_text('error-throttled.json')))
assert_eq(plain.extra[:retryAfter], 60, 'no budget info -> 60 s')

# Signed out: only the CLI's own whole phrases.
signed_out = [
  'Authorization is required to continue, but the current environment does not support interactive prompts.',
  'You are not logged in to Shopify.', 'To run this command, log in to Shopify.',
  'No authenticated account found for alias shop.',
  "We've cleared the current session because the current access token is invalid or has expired.",
  'Error validating auth session', 'Device authorization failed: expired.'
]
signed_out.each { |m| assert_eq(code_of(result(body(m))), 'signed_out', "signed_out: #{m}") }
%w[error-logged-out-ci.json error-logged-out.json error-session-cleared.json error-business-platform-401.json].each do |f|
  assert_eq(code_of(result(fixture_text(f))), 'signed_out', "#{f} -> signed_out")
end
# Negative: theme files, proxies and other "login"/"authenticat" text.
['templates/customers/login.liquid: Liquid syntax error', 'check your proxy authentication',
 'Theme 123 is locked: Blogin', 'snippets/login-form.liquid failed to upload', 'Unauthenticated proxy request',
 'customer login page', 'Authorization header missing in the request'].each do |m|
  assert_eq(code_of(result(body(m))), 'cli_failed', "not signed_out: #{m}")
end
# stderr never classifies, even with the exact phrase.
assert_eq(code_of(result('', stderr: "{\"type\":\"progress\",\"message\":\"Uploading templates/customers/login.liquid\"}\nTo run this command, log in to Shopify.\n")),
          'cli_failed', 'stderr never classifies as signed_out')
assert_eq(code_of(result('', stderr: 'Throttled')), 'cli_failed', 'stderr never classifies as rate_limited')
# GraphQL messages are not the CLI's own message.
assert_eq(code_of(result(gql([{ 'message' => 'Please log in to Shopify' }]))), 'cli_failed', 'a GraphQL message cannot sign the account out')
assert_eq(code_of(result(gql([{ 'message' => 'The BusinessPlatform GraphQL API responded unsuccessfully with the HTTP status 401' }]))),
          'cli_failed', 'the 401 text inside a GraphQL error is not signed_out')
# ... not even when the pinned CLI copies the whole GraphQL error list into
# tryMessage, which it does for every "GraphQL operation failed." body (the
# shape seen live; the GraphQL fixtures carry it).
def gql_dump(errors)
  err = { 'type' => 'abort', 'message' => 'GraphQL operation failed.', 'tryMessage' => JSON.pretty_generate({ 'errors' => errors }),
          'details' => { 'errors' => errors } }
  JSON.generate({ 'error' => err })
end
assert_eq(code_of(result(gql_dump([{ 'message' => 'To continue, log in to Shopify.' }]))), 'cli_failed', 'a session phrase in the tryMessage dump is not signed_out')
assert_eq(code_of(result(gql_dump([{ 'message' => 'Too Many Requests' }]))), 'cli_failed', 'a throttle phrase in the tryMessage dump is not rate_limited')
assert_eq(code_of(result(gql_dump([{ 'message' => 'Error validating auth session' }]))), 'cli_failed', 'the dump never classifies the session')
assert_eq(code_of(result(gql_dump([{ 'message' => 'Too Many Requests', 'extensions' => { 'code' => 'THROTTLED' } }]))), 'rate_limited',
          'the structured code still classifies')
assert_eq(code_of(result(body('Request failed.', try: '{"error":"Too Many Requests"}'))), 'cli_failed', 'a JSON dump in tryMessage is never read as prose')
assert_eq(code_of(result(body('Request failed.', try: 'To continue, log in to Shopify.'))), 'signed_out', 'a prose tryMessage still counts')
%w[error-scope.json error-graphql.json error-throttled.json].each do |f|
  dump = JSON.parse(fixture_text(f)).dig('error', 'tryMessage').to_s
  assert(dump.start_with?('{') && JSON.parse(dump)['errors'].is_a?(Array), "#{f} carries the CLI's tryMessage dump")
end
assert_eq(code_of(result(fixture_text('error-graphql.json'))), 'cli_failed', 'an unclassified GraphQL error is cli_failed')
assert_eq(failure_of(result(fixture_text('error-graphql.json'))).details, ['GraphQL operation failed.', 'Field x does not exist'],
          'details: the message and each GraphQL error, never the JSON dump')

# Theme session: the Admin API 401/403 on a theme command only.
admin401 = fixture_text('error-admin-401.json')
assert_eq(code_of(result(admin401), theme: true), 'theme_session_expired', 'Admin 401 on a theme command')
assert_eq(code_of(result(body('The Admin GraphQL API responded unsuccessfully with the HTTP status 403.')), theme: true), 'theme_session_expired', 'Admin 403 too')
assert_eq(code_of(result(admin401), theme: false), 'cli_failed', 'the same text from store execute is a plain failure')
assert(code_of(result(body('Service is not valid for authentication (Code: 401)')), theme: true) != 'theme_session_expired',
       'a bare "(Code: 401)" is not the theme session')

# Store unavailable and server errors (cli_failed + retryAfter 60).
assert_eq(code_of(result(fixture_text('error-store-unavailable.json'))), 'store_unavailable', 'paused/frozen store')
server = failure_of(result(fixture_text('error-server-error.json')), theme: true)
assert_eq([server.code, server.extra[:retryAfter]], ['cli_failed', 60], 'a 5xx is cli_failed with retryAfter 60')
assert_eq(failure_of(result(body('The request returned a server error.'))).extra[:retryAfter], 60, '"returned a server error" too')

# Details of a failed push: the per-file issues first, then the message.
push = failure_of(result(fixture_text('error-push-failed.json')), theme: true)
assert_eq([push.code, push.details.first(2)], ['cli_failed', ["sections/a.liquid: Liquid syntax error", "The theme 'Dawn' could not be pushed."]],
          'push failure details')
# The summary of a push rejected with per-file issues names the cause
# (first issue, theme-relative) instead of the CLI's "could not be pushed"
# sentence, which stays in details; several issues add "(+N more)".
assert_eq(push.message, 'sections/a.liquid: Liquid syntax error', 'a failed push summary is its first issue')
many = JSON.parse(fixture_text('error-push-failed.json'))
many['error']['details']['issues'] += [{ 'filePath' => '/p/snippets/b.liquid', 'message' => 'Unknown tag' }, 'junk',
                                       { 'filePath' => '/p/assets/c.js', 'message' => 'Too big' }]
many_failure = failure_of(result(JSON.generate(many)), theme: true)
assert_eq(many_failure.message, 'sections/a.liquid: Liquid syntax error (+2 more)', 'several issues: first + "(+N more)", non-objects skipped')
assert_eq(many_failure.details.first(4), ['sections/a.liquid: Liquid syntax error', 'snippets/b.liquid: Unknown tag', 'assets/c.js: Too big',
                                          "The theme 'Dawn' could not be pushed."], 'details keep every issue and the CLI sentence')
no_issues = JSON.parse(fixture_text('error-push-failed.json'))
no_issues['error']['details']['issues'] = 'x'
assert_eq(failure_of(result(JSON.generate(no_issues)), theme: true).message, "The theme 'Dawn' could not be pushed.", 'no issue objects: the CLI message')
# A stderr-only failure still summarises with the LAST stderr line (the
# first is often a node/npm warning).
stderr_only = failure_of(result('not json', stderr: "npm warn something\nError: the real cause\n"))
assert_eq([stderr_only.code, stderr_only.message], ['cli_failed', 'Error: the real cause'], 'stderr-only cli_failed keeps details.last')

# Valid JSON of the wrong shape never raises TypeError/NoMethodError
# (Validate.hdig): a non-object part is ignored and classification runs on
# the rest, so a THROTTLED code still gives rate_limited.
throttled = { 'extensions' => { 'code' => 'THROTTLED' } }
{
  'string error next to THROTTLED' => [{ 'error' => 'x', 'errors' => [throttled] }, 'rate_limited'],
  'string error.details next to THROTTLED' => [{ 'error' => { 'message' => 'm', 'details' => 'str' }, 'errors' => [throttled] }, 'rate_limited'],
  'string body extensions next to THROTTLED' => [{ 'extensions' => 'x', 'errors' => [throttled] }, 'rate_limited'],
  'string errors[].extensions' => [{ 'errors' => [{ 'message' => 'x', 'extensions' => 'y' }] }, 'cli_failed'],
  'string error.details.extensions, THROTTLED' => [{ 'error' => { 'message' => 'm', 'details' => { 'extensions' => 's', 'errors' => [throttled] } } }, 'rate_limited'],
  'string app_errors' => [{ 'errors' => [{ 'message' => 'x' }], 'extensions' => { 'app_errors' => 'y' } }, 'cli_failed'],
  'string first GraphQL error' => [{ 'errors' => ['x', { 'message' => 'y' }] }, 'cli_failed'],
  'string cost throttleStatus' => [{ 'errors' => [throttled], 'extensions' => { 'cost' => { 'throttleStatus' => 's', 'requestedQueryCost' => 5 } } }, 'rate_limited']
}.each do |label, (shape, code)|
  got = begin
    failure_of(result(JSON.generate(shape)))&.code
  rescue StandardError => e
    "#{e.class}: #{e.message}"
  end
  assert_eq(got, code, label)
end
assert_eq(failure_of(result(JSON.generate({ 'error' => 'x', 'errors' => [throttled] }))).extra[:retryAfter], 60, 'malformed throttled body: default retryAfter')

steps = failure_of(result(body('Stored app authentication for alpha.myshopify.com is no longer valid.',
                               next_steps: ['Run shopify store auth --store alpha.myshopify.com'])))
assert(steps.details.nil?, 'classified codes carry stderr details only when there is stderr')
