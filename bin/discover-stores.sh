#!/usr/bin/env bash
set -euo pipefail

if ! command -v shopify >/dev/null 2>&1; then
  echo "Shopify CLI (shopify) not found — install it from https://shopify.dev/docs/api/shopify-cli" >&2
  exit 127
fi

# Merge every organization's stores into one list. On a multi-org account
# `store list` needs an explicit --organization-id, so enumerate the orgs first,
# then list each in parallel. Emits `{"stores": [...]}` on stdout for the QML
# side's `parsed.stores`. Every call is CI=1 (non-TTY).
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Organization enumeration is the only fatal step — without it there is nothing
# to list.
if ! orgs="$(CI=1 shopify organization list --json)"; then
  echo "discover-stores.sh: failed to list organizations" >&2
  exit 1
fi

# One `<slot><TAB><org-id>` line per org; the slot numbers the parallel jobs so
# each writes a stable temp filename (org ids contain `/`, so they can't be in
# the filename). A missing `.organizations` yields no jobs.
jq -r '.organizations // [] | to_entries[] | select(.value.id) | "\(.key)\t\(.value.id)"' \
  <<<"$orgs" >"$tmp/jobs" || true

if [ ! -s "$tmp/jobs" ]; then
  echo '{"stores": []}'
  exit 0
fi

# Bounded parallelism (6): each call is a separate `shopify` CLI process writing
# the shared CLI config, so keep the fan-out modest. A per-org failure degrades
# to an empty store list, so the merge never sees a missing file.
fetch_org() {
  local slot="$1" org_id="$2"
  if ! CI=1 shopify store list --organization-id "$org_id" --json >"$tmp/org-$slot.json" 2>/dev/null; then
    printf '{"stores": []}\n' >"$tmp/org-$slot.json"
  fi
}
export tmp
export -f fetch_org

# shellcheck disable=SC2016
xargs -P 6 -n 2 bash -c 'fetch_org "$1" "$2"' _ <"$tmp/jobs"

# Flatten each org's `stores` array, then dedupe by the *.myshopify.com
# subdomain (`store`). `add` would object-merge the per-org payloads and drop
# all but one org's stores, hence the explicit flatten.
jq -sc '{ stores: ([.[].stores // [] | .[]] | unique_by(.store)) }' "$tmp"/org-*.json
