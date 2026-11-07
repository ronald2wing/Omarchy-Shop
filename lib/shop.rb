# Shop: ROOT, the Node/CLI pins, the API version and scopes, the timing table and the test overrides; loads every Shop module.

# Helpers read paths and CLI output as UTF-8 whatever the locale; the
# assignment itself is what -w warns about, so the warning is muted for it.
verbose, $VERBOSE = $VERBOSE, nil
Encoding.default_external = Encoding::UTF_8
$VERBOSE = verbose

require 'json'
require 'time'
require 'date'

module Shop
  ROOT = File.expand_path('..', __dir__)
  # The only runtime Shop uses: this Node and this @shopify/cli,
  # both installed under mise's data dir. Nothing on PATH is ever used.
  NODE_PIN = '26.13.0'
  CLI_PIN = '5.0.1'
  # Admin API version passed to every `store execute`.
  API_VERSION = '2026-10'
  # Scopes requested by grant-sales-access (the CLI's comma-joined form): no
  # customer data.
  SCOPES = 'read_reports,read_orders'

  KIB = 1024
  MIB = 1024 * 1024

  # The single source of every helper deadline and output cap, per helper
  # (fetch-sales per range): `helper` is the helper's overall deadline H in
  # seconds (HelperMain.overall), `calls` the per-call deadlines in seconds
  # in the order they run (a lone 'call' entry is the one every call gets;
  # each is capped by what is left of H), `cap` the byte cap on each line
  # the helper prints, `pages` / `concurrency` the bounds the per-call
  # column also states. A child's own stdout cap is not here: a CLI call's
  # is Shopify::JSON_CAP or TEXT_CAP, a tool's its caller's. The QML
  # deadline is H + 5 s. `Shop.seconds` reads this table; the CONTRIBUTING
  # timing table is it written out by hand, and test_source_contracts.rb
  # compares the two.
  TIMING = {
    'prepare-state' => { helper: 5, calls: {}, cap: 4 * KIB },
    'check-account' => { helper: 20, calls: { 'call' => 20 }, cap: 64 * KIB },
    'sign-in' => { helper: 900, calls: { 'probe' => 20, 'logout' => 30, 'login' => 900 }, cap: 64 * KIB },
    'sign-out' => { helper: 30, calls: { 'call' => 30 }, cap: 4 * KIB },
    'install-cli' => { helper: 900, calls: { 'node' => 400, 'cli' => 400, 'verify' => 20 }, cap: 4 * KIB },
    'grant-sales-access' => { helper: 600, calls: { 'auth' => 600, 'verify' => 20 }, cap: 4 * KIB },
    'discover-stores' => { helper: 45, calls: { 'call' => 15 }, concurrency: 6, cap: 2 * MIB },
    'fetch-sales today' => { helper: 25, calls: { 'call' => 20 }, pages: 40, cap: 1 * MIB },
    'fetch-sales history' => { helper: 45, calls: { 'call' => 40 }, cap: 1 * MIB },
    'fetch-sales yesterday' => { helper: 45, calls: { 'call' => 20 }, pages: 40, cap: 2 * MIB },
    'list-themes' => { helper: 20, calls: { 'call' => 20 }, cap: 256 * KIB },
    # Every folder walk, in any helper, runs under inspect-folder's walk cap.
    'inspect-folder' => { helper: 15, calls: { 'walk' => 10 }, cap: 16 * KIB },
    'list-backups' => { helper: 5, calls: {}, cap: 256 * KIB },
    'push-theme' => { helper: 600, calls: { 'list' => 20, 'backup' => 240, 'push' => 300 }, cap: 32 * KIB },
    'pull-theme' => { helper: 600, calls: { 'list' => 20, 'pull' => 300 }, cap: 32 * KIB },
    'restore-backup' => { helper: 600, calls: { 'list' => 20, 'backup' => 240, 'push' => 300 }, cap: 32 * KIB },
    'notify-order' => { helper: 10, calls: { 'call' => 5 }, cap: 1 * KIB },
    # A paste: wl-paste gets 2 s and 16 KiB, so a clipboard owner that never
    # stops sending stalls only a killed child, never the shell.
    'read-clipboard' => { helper: 4, calls: { 'call' => 2 }, cap: 32 * KIB },
    # A streamer (the only row with ready:): the helper lives as long as the
    # preview (8 h), must be ready within 120 s, has no QML deadline (stop =
    # close stdin + SIGTERM, SIGKILL after 8 s) and prints lines of at most
    # 4 KiB.
    'preview-theme' => { helper: 8 * 3600, ready: 120, calls: {}, cap: 4 * KIB }
  }.freeze

  @overrides = {}.freeze

  module_function

  # Test seams set by `Helpers::X.run(argv, **overrides)`: tool paths
  # (`tools: {setpriv:, mise:, notify_send:, pw_play:, paplay:, wl_paste:}`), the system
  # PATH given to children (`system_path:`), deadlines (`deadlines: {call:,
  # helper:, ready:, walk:, recheck:, page_reserve:}` in seconds),
  # `kill_grace:`, `now:` (epoch seconds) and `trusted_parent:` (the
  # directory where the folder-safety ancestor walk stops; nil walks to /).
  # Production passes none.
  def override!(hash)
    @overrides = hash.freeze
  end

  def overrides
    @overrides
  end

  # A deadline in seconds. The `deadlines[kind]` override wins; otherwise
  # `source` is a number (the default) or a TIMING row name:
  #   Shop.seconds(:helper, 'push-theme')          -> 600
  #   Shop.seconds(:call, 'push-theme', 'list')    -> 20
  #   Shop.seconds(:ready, 'preview-theme')        -> 120
  #   Shop.seconds(:recheck, 15)                   -> 15
  def seconds(kind, source, step = nil)
    value = @overrides.dig(:deadlines, kind)
    return value if value.is_a?(Numeric) && value.positive?
    return source if source.is_a?(Numeric)

    row = TIMING.fetch(source)
    case kind
    when :helper then row.fetch(:helper)
    when :ready then row.fetch(:ready)
    else row.fetch(:calls).fetch(step || kind.to_s)
    end
  end

  def now
    value = @overrides[:now]
    value.is_a?(Numeric) ? Time.at(value) : Time.now
  end
end

require_relative 'shop/failure'
require_relative 'shop/text'
require_relative 'shop/json'
require_relative 'shop/deadline'
require_relative 'shop/paths'
require_relative 'shop/signals'
require_relative 'shop/tools'
require_relative 'shop/env'
require_relative 'shop/process_group'
require_relative 'shop/child'
require_relative 'shop/command'
require_relative 'shop/validate'
require_relative 'shop/argv'
require_relative 'shop/helper_main'
require_relative 'shop/ports'
require_relative 'shop/queries'
require_relative 'shop/runtime'
require_relative 'shop/throttle'
require_relative 'shop/classify'
require_relative 'shop/shopify'
require_relative 'shop/account'
require_relative 'shop/store_clock'
require_relative 'shop/sales'
require_relative 'shop/sales_history'
require_relative 'shop/stores'
require_relative 'shop/tree_walk'
require_relative 'shop/theme_toml'
require_relative 'shop/theme_folder'
require_relative 'shop/themes'
require_relative 'shop/lock'
require_relative 'shop/backups'
require_relative 'shop/folder_copies'
require_relative 'shop/theme_job'
