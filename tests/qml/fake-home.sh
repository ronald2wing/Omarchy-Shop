# Fills a throwaway HOME for the QML smokes with the layout the Ruby tests
# use (tests/ruby/fake_home.rb builds it: the fake node and fake Shopify CLI
# under mise's installs dir, the fake CLI's "ok" scenario, and a
# config.json with three stores linked to theme-shaped folders), then
# checks that mise's installs dir holds only the fakes. Run with bash (it is
# not executable); tests/run calls it for every smoke:
#
#   bash tests/qml/fake-home.sh <home>                              build only
#   bash tests/qml/fake-home.sh <home> run <smoke.qml> quickshell   build, then run
#   bash tests/qml/fake-home.sh <home> run <smoke.qml> <qml binary>
#
# The caller sets the environment (tests/run passes `env -i` with HOME and
# every XDG_* and MISE_DATA_DIR under <home>, and its OMARCHY_PATH) and
# picks the runner from the smoke's first line: `quickshell -p` for
# "// runner: quickshell" (Service.qml needs Quickshell's modules; ui/
# needs the shell's qs.Ui and qs.Commons, linked from $OMARCHY_PATH/shell),
# the plain `qml` binary it names for any other.
set -euo pipefail

home="${1:?usage: fake-home.sh <home> [run <smoke.qml> quickshell|<qml binary>]}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixtures="$root/tests/fixtures/bin"

# Never the real home and never a relative path (fake_home.rb refuses a
# path that spells yarn, pnpm or bun, and mise dirs outside <home>).
real_home="$(getent passwd "$(id -u)" | cut -d: -f6 || true)"
case "$home" in /*) ;; *) echo "fake-home.sh: <home> must be absolute" >&2; exit 2 ;; esac
if [ "$home" = "/" ] || [ "$home" = "$real_home" ] || [ "$home" = "${real_home%/}" ]; then
  echo "fake-home.sh: refusing to use $home" >&2
  exit 2
fi
/usr/bin/ruby --disable-gems "$root/tests/ruby/fake_home.rb" "$home"

# Guard: mise's installs dir under the throwaway HOME holds only the fakes.
installs="$home/.local/share/mise/installs"
for entry in $(ls "$installs" 2>/dev/null); do
  case "$entry" in node|npm-shopify-cli) ;; *) echo "fake-home.sh: smoke HOME has a non-fake install: $entry" >&2; exit 2 ;; esac
done
for link in "$installs"/node/*/bin/node \
            "$installs"/npm-shopify-cli/*/node_modules/.mise/*/node_modules/@shopify/cli/bin/run.js; do
  [ -e "$link" ] || continue
  case "$(readlink -f "$link")" in "$fixtures"/fake-*) ;; *) echo "fake-home.sh: smoke HOME links outside tests/fixtures/bin: $link" >&2; exit 2 ;; esac
done

[ "${2:-}" = run ] || exit 0
smoke="${3:?usage: fake-home.sh <home> run <smoke.qml> quickshell|<qml binary>}"
runner="${4:?usage: fake-home.sh <home> run <smoke.qml> quickshell|<qml binary>}"
[ -f "$smoke" ] || { echo "fake-home.sh: $smoke is missing" >&2; exit 2; }
if [ "$runner" = quickshell ]; then
  # Quickshell loads nothing from outside its config folder, so the smoke
  # runs from a config dir inside the HOME that links the plugin as `shop`
  # (the smokes import "shop/tests/qml" for Smoke and PanelHarness) and the
  # shell's kit as `Ui` and `Commons` (what `qs.Ui` / `qs.Commons` resolve
  # to there).
  shell_dir="${OMARCHY_PATH:?fake-home.sh: OMARCHY_PATH is not set}/shell"
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
  exec timeout 60 "$runner" "$smoke"
fi
