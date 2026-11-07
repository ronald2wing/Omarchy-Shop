# Fills a throwaway HOME for the QML smokes with the pinned layout the Ruby
# tests use (tests/ruby/support.rb FakeHome): the fake node and fake
# Shopify CLI under mise's installs dir, the fake CLI's "ok" scenario, and
# a config.json with three stores linked to theme-shaped folders. Run with
# bash (it is not executable); tests/run calls it for every smoke:
#
#   bash tests/qml/fake-home.sh <home>                    build only
#   bash tests/qml/fake-home.sh <home> run <smoke.qml>    build, then run
#
# The caller sets the environment (tests/run passes `env -i` with HOME and
# every XDG_* and MISE_DATA_DIR under <home>). `run` picks the runtime from
# the smoke's first line: "// runner: quickshell" means `quickshell -p`
# (Service.qml needs Quickshell's modules; ui/ needs the shell's qs.Ui and
# qs.Commons, linked from $OMARCHY_PATH/shell), anything else the plain `qml`.
set -euo pipefail

home="${1:?usage: fake-home.sh <home> [run <smoke.qml>]}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixtures="$root/tests/fixtures/bin"
NODE_PIN="$(sed -n "s/^  NODE_PIN = '\([0-9.]*\)'$/\1/p" "$root/lib/shop.rb")"
CLI_PIN="$(sed -n "s/^  CLI_PIN = '\([0-9.]*\)'$/\1/p" "$root/lib/shop.rb")"
[ -n "$NODE_PIN" ] && [ -n "$CLI_PIN" ] || { echo "fake-home.sh: cannot read the pins from lib/shop.rb" >&2; exit 2; }

# Never the real home, never a relative path, and never a path the CLI's
# auto-upgrade would read as yarn, pnpm or bun (Shop::Runtime::UPGRADER_RE
# refuses the CLI there; tests/run's mktemp retries such a name).
real_home="$(getent passwd "$(id -u)" | cut -d: -f6 || true)"
case "$home" in /*) ;; *) echo "fake-home.sh: <home> must be absolute" >&2; exit 2 ;; esac
if [ "$home" = "/" ] || [ "$home" = "$real_home" ] || [ "$home" = "${real_home%/}" ]; then
  echo "fake-home.sh: refusing to use $home" >&2
  exit 2
fi
case "${home,,}" in *yarn*|*pnpm*|*bun*) echo "fake-home.sh: $home spells yarn, pnpm or bun, where Shop refuses the CLI" >&2; exit 2 ;; esac
[ -x "$fixtures/fake-shopify" ] && [ -x "$fixtures/fake-node" ] || { echo "fake-home.sh: tests/fixtures/bin fakes are missing" >&2; exit 2; }

data="${XDG_DATA_HOME:-$home/.local/share}"
installs="${MISE_DATA_DIR:-$data/mise}/installs"
mkdir -p "$home" "$home/.config/shop" "$home/.local/state" "$home/.cache" "$home/.fake-shopify" "$data"

# node + npm (a canary: Shop must never put mise's node bin dir on PATH).
mkdir -p "$installs/node/$NODE_PIN/bin"
ln -sfn "$fixtures/fake-node" "$installs/node/$NODE_PIN/bin/node"
ln -sfn "$fixtures/fake-npm" "$installs/node/$NODE_PIN/bin/npm"

# @shopify/cli as `mise install npm:@shopify/cli@<pin>` lays it out.
pkg="$installs/npm-shopify-cli/$CLI_PIN/node_modules/.mise/@shopify+cli@$CLI_PIN/node_modules/@shopify/cli"
mkdir -p "$pkg/bin"
ln -sfn "$fixtures/fake-shopify" "$pkg/bin/run.js"
printf '{"name":"@shopify/cli","version":"%s"}\n' "$CLI_PIN" > "$pkg/package.json"
printf 'ok' > "$home/.fake-shopify/scenario"

# Three stores, each linked to a theme-shaped folder.
stores=""
for name in acme beta gamma; do
  folder="$home/work/$name"
  for d in layout templates config sections snippets; do mkdir -p "$folder/$d"; done
  printf '<html></html>\n' > "$folder/layout/theme.liquid"
  printf '{}\n' > "$folder/templates/index.json"
  entry="$(printf '{ "domain": "%s.myshopify.com", "label": "%s", "showInBar": true, "theme": { "folder": "%s", "target": "live", "allowLive": false } }' "$name" "${name^}" "$folder")"
  stores="${stores:+$stores,
    }$entry"
done
cat > "$home/.config/shop/config.json" <<EOF
{
  "version": 2,
  "pollSeconds": 60,
  "alerts": { "notify": false, "sound": false },
  "bar": { "display": "stores" },
  "stores": [
    $stores
  ]
}
EOF

# Guard: mise's installs dir under the throwaway HOME holds only the fakes.
for entry in $(ls "$installs" 2>/dev/null); do
  case "$entry" in node|npm-shopify-cli) ;; *) echo "fake-home.sh: smoke HOME has a non-fake install: $entry" >&2; exit 2 ;; esac
done
for link in "$installs/node/$NODE_PIN/bin/node" \
            "$installs"/npm-shopify-cli/*/node_modules/.mise/*/node_modules/@shopify/cli/bin/run.js; do
  [ -e "$link" ] || continue
  case "$(readlink -f "$link")" in "$fixtures"/fake-*) ;; *) echo "fake-home.sh: smoke HOME links outside tests/fixtures/bin: $link" >&2; exit 2 ;; esac
done

[ "${2:-}" = run ] || exit 0
smoke="${3:?usage: fake-home.sh <home> run <smoke.qml>}"
[ -f "$smoke" ] || { echo "fake-home.sh: $smoke is missing" >&2; exit 2; }
if head -1 "$smoke" | grep -q '^// runner: quickshell$'; then
  # Quickshell loads nothing from outside its config folder, so the smoke
  # runs from a config dir inside the HOME that links the plugin as `shop`
  # (the smokes import "shop/tests/qml" for Smoke and PanelHarness) and the
  # shell's kit as `Ui` and `Commons` (what `qs.Ui` / `qs.Commons` resolve
  # to there).
  shell_dir="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
  [ -d "$shell_dir/Ui" ] && [ -d "$shell_dir/Commons" ] || { echo "fake-home.sh: $shell_dir has no Ui/Commons" >&2; exit 2; }
  mkdir -p "$home/qs"
  ln -sfn "$root" "$home/qs/shop"
  ln -sfn "$shell_dir/Ui" "$home/qs/Ui"
  ln -sfn "$shell_dir/Commons" "$home/qs/Commons"
  # A stand-in plugin tree for model_doubles_smoke.qml: links to model/ and
  # js/, plus a helpers/ of doubles (the model's HelperProcess resolves
  # ../helpers/<name> next to itself), each tests/fixtures/bin/stub-<name>.
  mkdir -p "$home/qs/stub/helpers"
  ln -sfn "$root/model" "$home/qs/stub/model"
  ln -sfn "$root/js" "$home/qs/stub/js"
  for stub in "$fixtures"/stub-*; do
    ln -sfn "$stub" "$home/qs/stub/helpers/$(basename "$stub" | sed 's/^stub-//')"
  done
  cp "$smoke" "$home/qs/"
  exec timeout 60 quickshell -p "$home/qs/$(basename "$smoke")"
else
  exec timeout 60 /usr/lib/qt6/bin/qml "$smoke"
fi
