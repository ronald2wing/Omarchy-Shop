#!/usr/bin/env bash
set -euo pipefail

if ! command -v shopify >/dev/null 2>&1; then
  echo "Shopify CLI (shopify) not found — install it from https://shopify.dev/docs/api/shopify-cli" >&2
  exit 127
fi

action="${1:?usage: theme.sh <push|pull> <myshopify-domain> <themeDir> [theme]}"
domain="${2:?missing domain}"
dir="${3:?missing themeDir}"
theme_sel="${4:-live}"

if [ "$action" != "push" ] && [ "$action" != "pull" ]; then
  echo "theme.sh: action must be push or pull (got '$action')" >&2
  exit 2
fi

if [ ! -d "$dir" ]; then
  echo "theme.sh: themeDir does not exist: $dir" >&2
  exit 2
fi

cd "$dir"

# Resolve the store's theme list (and the live theme id) up front. Without
# `--theme` (and with no shopify.toml in the theme dir) push/pull falls into an
# interactive "select a theme" prompt that fails when run non-interactively.
# Capture both stdout and stderr so an auth failure can be surfaced clearly (the
# theme CLI's OAuth session can expire independently of the sales `store auth`
# session).
list_out="$(shopify theme list --store "$domain" --json 2>&1 || true)"
if echo "$list_out" | grep -qi "not valid for authentication\|(Code: 401)\|not authenticated"; then
  echo "Theme CLI authentication failed for $domain." >&2
  echo "Fix: run 'shopify auth logout' then 'shopify auth login' in a terminal," >&2
  echo "and complete the browser approval." >&2
  exit 3
fi

live_id="$(echo "$list_out" | jq -r '.[] | select(.role == "live") | .id' 2>/dev/null | head -1 || true)"

if [ "$theme_sel" = "live" ]; then
  # Target the store's live theme. Resolve its id (and name, for a clean summary).
  theme_id="$live_id"
  theme_name="$(echo "$list_out" | jq -r '.[] | select(.role == "live") | .name' 2>/dev/null | head -1 || true)"
else
  # Target a specific (dev/draft) theme by id; resolve its name for the summary.
  theme_id="$theme_sel"
  theme_name="$(echo "$list_out" | jq -r --arg id "$theme_sel" '.[] | select((.id | tostring) == $id) | .name' 2>/dev/null | head -1 || true)"
fi

if [ -n "$theme_id" ] && [ "$theme_id" != "null" ]; then
  label="theme '${theme_name:-$theme_id}'"
  theme_args=(--theme "$theme_id")
else
  label="the development theme"
  theme_args=(--development)
fi

# Before pushing, snapshot the live theme to a timestamped backup dir so a bad
# push can be rolled back. A failed backup only warns — it never blocks the push.
backup_note=""
if [ "$action" = push ] && [ -n "$live_id" ] && [ "$live_id" != "null" ]; then
  backup_dir="$HOME/.local/state/shop/backups/$domain/$(date +%s)"
  mkdir -p "$backup_dir"
  if shopify theme pull --store "$domain" --theme "$live_id" --path "$backup_dir" >/dev/null 2>&1; then
    backup_note=" (backed up to $backup_dir)"
  else
    echo "theme.sh: warning: live-theme backup failed; continuing push" >&2
  fi
fi

# Pushing to the live theme prompts "Push theme files to the live theme?" which
# fails non-interactively; --allow-live opts out of that confirmation (the plugin
# already surfaces the operation clearly, so the CLI's extra guard is redundant).
# Detect the live theme by comparing the resolved id (not the "live" keyword):
# the theme picker may have selected the live theme by its numeric id, which
# still needs the flag. Non-live themes don't prompt, so no flag for those.
if [ "$action" = push ] && [ -n "$theme_id" ] && [ "$theme_id" != "null" ] && [ "$theme_id" = "$live_id" ]; then
  theme_args+=(--allow-live)
fi

# Run the theme command and reduce its noisy TTY output to a clean summary.
# The CLI prints an ANSI progress spinner plus a box-drawing "success" banner
# (U+2500–257F); neither belongs in a small panel caption.
set +e
out="$(shopify theme "$action" --no-color --store "$domain" "${theme_args[@]}" 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  if [ "$action" = push ]; then
    echo "Pushed $label$backup_note"
  else
    echo "Pulled $label"
  fi
  exit 0
fi

# Error path: strip ANSI + box-drawing chars + carriage returns, drop blank
# lines, then print the meaningful remainder.
clean="$(printf '%s\n' "$out" \
  | perl -pe 's/\x1b\[[0-9;?]*[A-Za-z]//g; s/[\x{2500}-\x{257F}]//g; s/\r//g' \
  | grep -v '^[[:space:]]*$' || true)"
if [ -n "$clean" ]; then
  printf '%s\n' "$clean" >&2
else
  echo "Theme $action failed (exit $status)" >&2
fi
exit "$status"
