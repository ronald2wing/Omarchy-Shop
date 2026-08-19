#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
theme_sh="$here/../bin/theme.sh"
fake_bin="$here/fake-shopify"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

bindir="$(mktemp -d)"
log="$(mktemp)"
err_file="$(mktemp)"
tmpdir="$(mktemp -d)"          # themeDir for push/pull
home="$(mktemp -d)"            # HOME so backups land somewhere disposable
ln -s "$fake_bin" "$bindir/shopify"
export SHOPIFY_FAKE_LOG="$log"
export PATH="$bindir:$PATH"
export HOME="$home"
trap 'rm -rf "$bindir" "$log" "$err_file" "$tmpdir" "$home"' EXIT

# (a) pull resolves the live theme id and forwards it via --theme
unset SHOPIFY_FAKE_AUTH_FAIL
"$theme_sh" pull fake.myshopify.com "$tmpdir" >/dev/null
grep -q -- '--theme 160258293983' "$log" || fail "pull did not forward --theme <live id>"
printf 'PASS: pull forwards --theme 160258293983\n'

# (b) a 401 from `theme list` exits 3 with the auth fix hint on stderr
: > "$log"
set +e
SHOPIFY_FAKE_AUTH_FAIL=1 "$theme_sh" pull fake.myshopify.com "$tmpdir" >/dev/null 2>"$err_file"
rc=$?
set -e
[ "$rc" -eq 3 ] || fail "401 variant exited $rc (want 3)"
grep -q "Fix: run 'shopify auth logout'" "$err_file" || fail "401 variant missing auth fix hint"
printf 'PASS: 401 exits 3 with auth fix hint\n'

# (c) a missing themeDir exits 2
set +e
"$theme_sh" pull fake.myshopify.com /nonexistent/theme-dir >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "missing themeDir exited $rc (want 2)"
printf 'PASS: missing themeDir exits 2\n'

# (d) push with the default (live) theme: backs up the live theme first, then
# pushes with --theme <live id> --allow-live
: > "$log"
out="$(unset SHOPIFY_FAKE_AUTH_FAIL; "$theme_sh" push fake.myshopify.com "$tmpdir")"
grep -q 'theme pull --store fake.myshopify.com --theme 160258293983 --path' "$log" \
  || fail "push did not snapshot the live theme before pushing"
grep -q -- '--theme 160258293983 --allow-live' "$log" \
  || fail "push did not forward --theme <live id> --allow-live"
printf '%s' "$out" | grep -q "Pushed theme 'BEETLEJUICER'" || fail "push summary missing live theme name"
printf '%s' "$out" | grep -q "(backed up to" || fail "push summary missing backup note"
printf 'PASS: push (live) backs up then pushes with --allow-live\n'

# (e) push with a specific dev theme id: no --allow-live, resolves the name
: > "$log"
out="$(unset SHOPIFY_FAKE_AUTH_FAIL; "$theme_sh" push fake.myshopify.com "$tmpdir" 424242)"
push_line="$(grep 'theme push --no-color' "$log" || true)"
printf '%s' "$push_line" | grep -q -- '--theme 424242' || fail "push did not forward --theme 424242"
printf '%s' "$push_line" | grep -q -- '--allow-live' && fail "specific-id push must not add --allow-live"
printf '%s' "$out" | grep -q "Pushed theme 'DEV-THEME'" || fail "specific-id push summary missing theme name"
printf 'PASS: push (specific id) forwards --theme 424242 without --allow-live\n'

# (e2) push with the LIVE theme selected by its specific id: still adds
# --allow-live (the theme picker can store the live theme's numeric id, not the
# "live" keyword, and that id still needs the flag to skip the confirmation)
: > "$log"
out="$(unset SHOPIFY_FAKE_AUTH_FAIL; "$theme_sh" push fake.myshopify.com "$tmpdir" 160258293983)"
push_line="$(grep 'theme push --no-color' "$log" || true)"
printf '%s' "$push_line" | grep -q -- '--theme 160258293983 --allow-live' \
  || fail "live-by-id push did not add --allow-live"
printf '%s' "$out" | grep -q "Pushed theme 'BEETLEJUICER'" || fail "live-by-id push summary missing theme name"
printf 'PASS: push (live by id) forwards --theme <live id> --allow-live\n'

# (f) pull with a specific dev theme id resolves its name
: > "$log"
out="$(unset SHOPIFY_FAKE_AUTH_FAIL; "$theme_sh" pull fake.myshopify.com "$tmpdir" 424242)"
printf '%s' "$out" | grep -q "Pulled theme 'DEV-THEME'" || fail "specific-id pull summary missing theme name"
printf 'PASS: pull (specific id) resolves theme name\n'
