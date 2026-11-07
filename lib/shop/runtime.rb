# Shop::Runtime: locating the pinned node + @shopify/cli under mise's installs dir (pure), the node link and the status object.

module Shop
  module Runtime
    Located = Data.define(:node, :run_js)

    RUN_JS_CANDIDATES = [
      %w[lib node_modules @shopify cli],
      %w[node_modules @shopify cli],
      ['node_modules', '.mise', "@shopify+cli@#{CLI_PIN}", 'node_modules', '@shopify', 'cli']
    ].freeze

    # The pinned CLI picks its auto-upgrade package manager by substring of
    # the run.js path (and its realpath): "yarn", "pnpm" or "bun" anywhere in
    # it selects that tool from PATH, where npm_config_dry_run has no effect
    # and @latest would be installed despite the pin. Interactive calls leave
    # CI unset, so the upgrade can run; refuse them on such a path.
    UPGRADER_RE = /yarn|pnpm|bun/
    # How much of the CLI's package.json is read, and how deep it may nest.
    PACKAGE_MAX_BYTES = 1 * MIB
    PACKAGE_MAX_NESTING = 16

    module_function

    def installs_dir
      File.join(Paths.mise_data_dir, 'installs')
    end

    def node_path
      File.join(installs_dir, 'node', NODE_PIN, 'bin', 'node')
    end

    def cli_root
      File.join(installs_dir, 'npm-shopify-cli', CLI_PIN)
    end

    # A regular file (after resolving links) that passes Paths.trusted_stat?
    # (the uid's or root's, writable by nobody else), since these files are
    # executed, not just read.
    def trusted_file?(path, executable: false)
      st = File.stat(path)
      st.file? && Paths.trusted_stat?(st) && (!executable || st.executable?)
    rescue SystemCallError
      false
    end

    # The "version" of a package.json, or nil for anything that is not a
    # JSON object with one (a half-finished install can leave a truncated
    # or foreign file; that is a missing CLI, never an internal error).
    def package_version(pkg)
      Json.read_object(pkg, max_bytes: PACKAGE_MAX_BYTES, max_nesting: PACKAGE_MAX_NESTING)&.fetch('version', nil)
    end

    # [Located, nil] or [nil, "node"|"cli"]: the pinned runtime, or which
    # part is missing. Reads only.
    def find
      node = node_path
      return [nil, 'node'] unless trusted_file?(node, executable: true)

      RUN_JS_CANDIDATES.each do |parts|
        pkg_dir = File.join(cli_root, *parts)
        run_js = File.join(pkg_dir, 'bin', 'run.js')
        pkg = File.join(pkg_dir, 'package.json')
        next unless trusted_file?(run_js) && trusted_file?(pkg)

        return [Located.new(node: node, run_js: run_js), nil] if package_version(pkg) == CLI_PIN
      end
      [nil, 'cli']
    end

    # The pinned runtime or `cli_missing` (error.missing = node|cli). Pure:
    # the node link is made by ensure_node_link! right before a spawn.
    def locate
      found, missing = find
      return found if found

      what = missing == 'node' ? "node #{NODE_PIN}" : "Shopify CLI #{CLI_PIN}"
      raise Failure.new('cli_missing', "#{what} not found under mise's installs", missing: missing)
    end

    # Point bin_dir/node at the pinned node (atomic rename), so the CLI's own
    # child `node` lookups find the pinned one and nothing else. The only
    # writer of that link.
    def ensure_node_link!(located)
      link = File.join(Paths.bin_dir, 'node')
      current = File.readlink(link) rescue nil
      return if current == located.node

      tmp = File.join(Paths.bin_dir, ".node-#{Process.pid}")
      File.unlink(tmp) if File.symlink?(tmp)
      File.symlink(located.node, tmp)
      File.rename(tmp, link)
    end

    # The check-account `cli` object; `installs` is the dir the pins are
    # looked up in (the one place that resolves it for the UI).
    def status
      found, missing = find
      { 'found' => !found.nil?, 'missing' => missing, 'installs' => installs_dir }
    end

    def upgrader_path?(located)
      [located.run_js, Paths.real_or_self(located.run_js)].any? { |p| p.downcase.match?(UPGRADER_RE) }
    end

    def interactive_safe!(located)
      return located unless upgrader_path?(located)

      raise Failure.new('cli_failed', 'its install path names yarn, pnpm or bun, where its auto-upgrade could replace the pinned ' \
                                      'version, so Shop does not run it interactively')
    end
  end
end
