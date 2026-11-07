# Shop::Themes: theme list parsing, target resolution, the live gate, push/pull argv and the push/pull result mapping.

require_relative 'support'

T = Shop::Themes

themes = T.parse_list({ 'themes' => [
                        { 'id' => 160_258_293_983, 'name' => 'Dawn', 'role' => 'live' },
                        { 'id' => '160258294001', 'name' => "Dawn\u0007 copy", 'role' => 'unpublished' },
                        { 'id' => 'x', 'name' => 'bad id' }, 'junk', { 'id' => '7', 'name' => '', 'role' => 'development' }
                      ] })
assert_eq(themes, [
  { 'id' => '160258293983', 'name' => 'Dawn', 'role' => 'live' },
  { 'id' => '160258294001', 'name' => 'Dawn copy', 'role' => 'unpublished' },
  { 'id' => '7', 'name' => 'Theme 7', 'role' => 'development' }
], 'parse_list: ids as strings, names cleaned, bad rows dropped, empty name -> Theme <id>')
assert_eq(T.theme_hash(7, nil, 'odd role!'), { 'id' => '7', 'name' => 'Theme 7', 'role' => 'unknown' }, 'theme_hash: the one theme shape (Backups.row uses it too)')
assert_eq(failure_code { T.parse_list({ 'themes' => 'x' }) }, 'bad_response', 'no themes array -> bad_response')
assert_eq(T.parse_list({ 'themes' => (1..300).map { |i| { 'id' => i, 'name' => "T#{i}" } } }).size, T::MAX_THEMES, 'capped at MAX_THEMES')

assert_eq(T.resolve(themes, 'live')['id'], '160258293983', 'resolve live')
assert_eq(T.resolve(themes, 160_258_294_001)['name'], 'Dawn copy', 'resolve by id')
assert_eq(failure_code { T.resolve(themes, '999') }, 'theme_not_found', 'unknown id')
begin
  T.resolve(themes.drop(1), 'live')
rescue Shop::Failure => e
  assert_eq(e.message, 'the store has no live theme', 'the live target reads as words, not "theme live"')
end
assert_eq(failure_code { T.resolve(themes.drop(1), 'live') }, 'theme_not_found', 'no live theme')

live = themes[0]

assert_eq(T.push_args('a.myshopify.com', live, '/p'),
          ['theme', 'push', '--store=a.myshopify.com', '--theme=160258293983', '--path=/p', '--nodelete', '--json', '--no-input', '--allow-live'],
          'push argv: --nodelete always, --allow-live for the live target')
assert(!T.push_args('a.myshopify.com', themes[1], '/p').include?('--allow-live'), 'no --allow-live for an unpublished target')
assert_eq(T.pull_args('a.myshopify.com', live, '/p'),
          ['theme', 'pull', '--store=a.myshopify.com', '--theme=160258293983', '--path=/p', '--nodelete', '--force', '--json', '--no-input'],
          'pull argv: --nodelete and --force (the CLI\'s folder/git prompt throws under --no-input)')

# sync_result: the CLI's {status, issues} -> {partial, issues: [{kind, path, message}]}.
assert_eq(T.sync_result({ 'status' => 'success' }), { partial: false, issues: [] }, 'success without issues')
res = T.sync_result({ 'status' => 'partial', 'issues' => [
                      { 'filePath' => '/p/sections/header.liquid', 'message' => "Liquid\u0007 syntax error" },
                      'junk', { 'filePath' => 'assets/x.js', 'message' => 'm' * 500 },
                      { 'filePath' => '/p/AGENTS.md', 'message' => 'm' }
                    ] })
assert_eq(res[:partial], true, 'partial')
assert_eq(res[:issues].map { |i| i['kind'] }, %w[issue issue issue], 'issue rows only (non-hash rows dropped)')
assert_eq(res[:issues][0], { 'kind' => 'issue', 'path' => 'sections/header.liquid', 'message' => 'Liquid syntax error' }, 'path relative to the theme dir (ThemeFolder.theme_relative), message cleaned')
assert_eq(res[:issues][1]['path'], 'assets/x.js', 'a relative path stays')
assert_eq(res[:issues][2]['path'], 'AGENTS.md', 'a root file keeps its basename')
assert(res[:issues][1]['message'].length <= 160, 'messages are capped')
many = (1..40).map { |i| { 'filePath' => "a#{i}", 'message' => 'm' } }
assert_eq(T.sync_result({ 'status' => 'success', 'issues' => many })[:issues].size, T::MAX_ISSUES, 'issues capped at MAX_ISSUES')
begin
  T.sync_result({ 'status' => 'skipped', 'reason' => 'unsafe-directory' })
  assert(false, 'skipped must raise')
rescue Shop::Failure => e
  assert_eq(e.code, 'cli_failed', 'skipped -> cli_failed')
  assert(e.message.include?('skipped') && e.message.include?('unsafe-directory'), "the reason is in the message (#{e.message})")
end
# A push that uploads nothing (the pinned CLI: success, changed: false) is a success.
assert_eq(T.sync_result({ 'status' => 'success', 'changed' => false, 'issues' => [] }), { partial: false, issues: [] }, 'an unchanged push is a success')
assert_eq(failure_code { T.sync_result({ 'status' => 'weird' }) }, 'bad_response', 'unknown status -> bad_response')
assert_eq(failure_code { T.sync_result({}) }, 'bad_response', 'no status -> bad_response')
# A pull (the backup pull included) accepts only 'success': an incomplete tree is no backup.
assert_eq(T.sync_result({ 'status' => 'success' }, pull: true), { partial: false, issues: [] }, 'a success pull')
assert_eq(failure_code { T.sync_result({ 'status' => 'partial', 'issues' => [] }, pull: true) }, 'bad_response', 'a partial pull -> bad_response')
assert_eq(failure_code { T.sync_result({}, pull: true) }, 'bad_response', 'a pull with no status -> bad_response')
assert_eq(failure_code { T.sync_result({ 'status' => 'skipped' }, pull: true) }, 'cli_failed', 'a skipped pull -> cli_failed')


# issues: the CLI's {filePath, message} list as warning rows; anything else
# is skipped, and the count is of the whole list.
raw = [{ 'filePath' => '/p/x/sections/a.liquid', 'message' => 'bad' }, 'junk', nil, { 'filePath' => 'b.json', 'message' => 'm' }]
assert_eq(T.issues(raw), [{ 'kind' => 'issue', 'path' => 'sections/a.liquid', 'message' => 'bad' },
                          { 'kind' => 'issue', 'path' => 'b.json', 'message' => 'm' }], 'issues: objects only, theme-relative paths')
assert_eq([T.issues(nil), T.issues('x'), T.issue_count(raw), T.issue_count(nil)], [[], [], 2, 0], 'issues of a non-list; issue_count')
begin
  T.sync_result({ 'status' => 'skipped', 'reason' => 'unsafe-directory' })
rescue Shop::Failure => e
  assert_eq(e.message, 'folder skipped: "unsafe-directory"', 'a skipped run never starts with "Shopify CLI"')
end
