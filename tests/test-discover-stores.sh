#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
discover_sh="$here/../bin/discover-stores.sh"
fake_bin="$here/fake-shopify"

# Shadow the real `shopify` with the fake by symlinking it as `shopify` in a
# temp dir at the head of PATH. `empty` is a PATH with no `shopify` for the
# missing-CLI guard (bash is invoked by absolute path so it survives it).
bindir="$(mktemp -d)"
empty="$(mktemp -d)"
log="$(mktemp)"
ln -s "$fake_bin" "$bindir/shopify"
export SHOPIFY_FAKE_LOG="$log"
export PATH="$bindir:$PATH"
trap 'rm -rf "$bindir" "$empty" "$log"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# Assert the merged output has <count> stores whose sorted domains equal
# <domains> (a JSON array).
assert_stores() {
  local out="$1" count="$2" domains="$3"
  printf '%s' "$out" | jq -e ".stores | length == $count" >/dev/null \
    || fail "expected $count stores, got: $out"
  printf '%s' "$out" | jq -e "[.stores[].store] | sort == $domains" >/dev/null \
    || fail "unexpected store domains: $out"
}

# (a) stores from both organizations are merged and deduped by domain.
assert_stores "$("$discover_sh")" 3 \
  '["alpha.myshopify.com", "beta.myshopify.com", "shared.myshopify.com"]'
printf 'PASS: discover-stores.sh merges orgs and dedupes by domain\n'

# (b) a failing organization is tolerated: the surviving stores are returned.
assert_stores "$(SHOPIFY_FAKE_FAIL_ORG_ID=200 "$discover_sh")" 2 \
  '["alpha.myshopify.com", "shared.myshopify.com"]'
printf 'PASS: discover-stores.sh tolerates a failing organization\n'

# (c) an empty organization list yields an empty store list.
out="$(SHOPIFY_FAKE_ORGS='{"organizations":[]}' "$discover_sh")"
[ "$out" = '{"stores": []}' ] || fail "empty org list produced: $out"
printf 'PASS: discover-stores.sh emits an empty list for no organizations\n'

# (d) a missing `shopify` CLI exits 127 with the install hint.
bash_bin="$(command -v bash)"
set +e
msg="$(PATH="$empty" "$bash_bin" "$discover_sh" 2>&1)"
rc=$?
set -e
[ "$rc" -eq 127 ] || fail "missing CLI exited $rc (want 127)"
printf '%s' "$msg" | grep -q "install it from https://shopify.dev/docs/api/shopify-cli" \
  || fail "missing CLI did not print the install hint"
printf 'PASS: discover-stores.sh exits 127 with install hint when shopify is missing\n'
