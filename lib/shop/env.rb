# Shop::Env: allowlisted child environments (nothing copied by default) for the CLI and the external tools.

module Shop
  module Env
    SYSTEM_PATH = '/usr/bin:/bin'
    BASE_COPY = %w[HOME USER LOGNAME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME XDG_RUNTIME_DIR].freeze
    NET_COPY = %w[HTTPS_PROXY HTTP_PROXY NO_PROXY https_proxy http_proxy no_proxy
                  NODE_EXTRA_CA_CERTS SSL_CERT_FILE SSL_CERT_DIR].freeze
    BASE_SET = { 'LANG' => 'C.UTF-8', 'NO_COLOR' => '1' }.freeze

    module_function

    def system_path
      Shop.overrides[:system_path] || SYSTEM_PATH
    end

    def copy(keys, source)
      keys.each_with_object({}) { |k, h| h[k] = source[k] if source[k] && !source[k].empty? }
    end

    def base(source)
      copy(BASE_COPY, source).merge(BASE_SET)
    end

    # The CLI's environment. PATH is the node-only bin dir plus the system
    # dirs: no mise shims and no mise node bin dir, so there is no npm next
    # to node. npm_config_dry_run turns the CLI's auto-upgrade `npm install
    # -g` into a no-op even if a system npm exists. Non-interactive calls add
    # CI=1 (no browser, no prompt, no auto-upgrade).
    def for_cli(interactive:, source: ENV)
      env = base(source)
            .merge(copy(%w[DBUS_SESSION_BUS_ADDRESS] + NET_COPY, source))
            .merge('PATH' => "#{Paths.bin_dir}:#{system_path}",
                   'FORCE_COLOR' => '0',
                   'SHOPIFY_CLI_NO_ANALYTICS' => '1',
                   'npm_config_dry_run' => 'true',
                   'npm_config_update_notifier' => 'false')
      if interactive
        env.merge!(copy(%w[WAYLAND_DISPLAY DISPLAY BROWSER], source))
      else
        env['CI'] = '1'
      end
      env
    end

    # The environment of an external tool, by profile (Tools::PROFILES names
    # each tool's): :mise, :notify, :clipboard or :sound. Any other profile
    # is a programming error, never an empty or inherited environment.
    def for_tool(kind, source: ENV)
      case kind
      when :mise
        base(source)
          .merge(copy(NET_COPY + %w[MISE_DATA_DIR MISE_CACHE_DIR MISE_CONFIG_DIR], source))
          .merge('PATH' => system_path,
                 'CI' => '1',
                 'MISE_YES' => '1',
                 'MISE_NPM_PACKAGE_MANAGER' => 'npm',
                 'MISE_HTTP_TIMEOUT' => '60s',
                 'MISE_NODE_VERIFY' => 'true',
                 'MISE_EXEC_AUTO_INSTALL' => '0',
                 'npm_config_registry' => 'https://registry.npmjs.org/',
                 'npm_config_strict_ssl' => 'true',
                 'npm_config_audit' => 'false',
                 'npm_config_fund' => 'false',
                 'npm_config_update_notifier' => 'false',
                 'SHOPIFY_CLI_NO_ANALYTICS' => '1')
      when :notify
        base(source).merge(copy(%w[DBUS_SESSION_BUS_ADDRESS WAYLAND_DISPLAY], source)).merge('PATH' => system_path)
      when :clipboard
        base(source).merge(copy(%w[WAYLAND_DISPLAY], source)).merge('PATH' => system_path)
      when :sound
        base(source).merge(copy(%w[PIPEWIRE_RUNTIME_DIR PULSE_SERVER], source)).merge('PATH' => system_path)
      else
        raise ArgumentError, "no environment profile #{kind.inspect}"
      end
    end
  end
end
