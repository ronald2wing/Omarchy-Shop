# Shop::Shopify: running pinned-CLI calls under the supervisor (spec, run, call, call_all) and `store execute` of a frozen query.

module Shop
  module Shopify
    # An interactive call (auth login, store auth) that times out, is stopped
    # or floods its output fails the helper at once; other failures are the
    # caller's to weigh.
    INTERACTIVE_FATAL = %w[timeout terminated output_too_large].freeze
    # The stdout cap of a CLI call: a JSON call (every listing, theme
    # command and `store execute`; the largest, an orders page or the
    # History tables, stays far below it), and a text one (`version`, `auth
    # login`, `store auth`, `auth logout`). Past it the call is stopped and
    # fails output_too_large.
    JSON_CAP = 2 * MIB
    TEXT_CAP = 64 * KIB

    module_function

    # Every CLI argv: [pinned node, run.js, *args]. No shim, no PATH lookup.
    def argv(located, *args)
      [located.node, located.run_js, *args]
    end

    # A Command spec for one CLI call. Refuses a theme command that would
    # find a shopify.theme.toml, refuses interactive calls on an upgrader
    # path, and points state/bin/node at the pinned node right before the
    # spawn (the CLI's own child node lookups find only that one).
    def spec(located, args, interactive:, deadline:, max_stdout:)
      theme_toml_guard!(args)
      Runtime.interactive_safe!(located) if interactive
      Runtime.ensure_node_link!(located)
      { argv: argv(located, *args), env: Env.for_cli(interactive: interactive), deadline: deadline,
        max_stdout: max_stdout, cli: true }
    end

    def theme?(args) = args.first == 'theme'

    # The pinned CLI's theme commands load [environments.default] flags from
    # the first shopify.theme.toml found walking up from --path (or the cwd)
    # to /. Refuse to spawn one when either chain has a toml: the one check
    # right before a theme command spawns.
    def theme_toml_guard!(args)
      return unless theme?(args)

      path = args.find { |a| a.start_with?('--path=') }&.delete_prefix('--path=')
      ThemeToml.refuse!(Paths.run_dir, path)
    end

    # Run one CLI call to completion and return its Command::Result,
    # unclassified (`command_opts` are Command.run's stdout_mode, on_tick
    # and extra_io: preview-theme's long-running `theme dev`).
    def run(located, args, interactive: false, deadline:, max_stdout:, **command_opts)
      s = spec(located, args, interactive: interactive, deadline: deadline, max_stdout: max_stdout)
      Command.run(s[:argv], env: s[:env], deadline: s[:deadline], max_stdout: s[:max_stdout], cli: true, **command_opts)
    end

    # Run one CLI call; returns the parsed stdout JSON object (or the raw
    # text with json: false). Failures are classified and raised.
    def call(located, args, interactive: false, deadline:, json: true, max_stdout: json ? JSON_CAP : TEXT_CAP)
      child_result = run(located, args, interactive: interactive, deadline: deadline, max_stdout: max_stdout)
      body!(child_result, json: json, theme: theme?(args))
    end

    # Run several JSON CLI calls under one supervisor (concurrency-bounded).
    # Returns, per call, [:ok, parsed] or [:error, Failure]: every slot is
    # filled, including the calls the supervisor never started because
    # `overall` expired first (a `timeout` Failure; on_done does not fire
    # for those, so callers that need to know get the slot, not the hook).
    def call_all(located, list, concurrency:, overall:, deadline:, max_stdout: JSON_CAP, on_done: nil)
      specs = list.map { |args| spec(located, args, interactive: false, deadline: deadline, max_stdout: max_stdout) }
      outcomes = Array.new(list.size)
      hook = lambda do |index, child_result|
        outcomes[index] = outcome(child_result, theme: theme?(list[index]))
        on_done&.call(index, outcomes[index])
      end
      child_results = Command.run_all(specs, concurrency: concurrency, overall: overall, on_done: hook)
      child_results.each_with_index { |child_result, i| outcomes[i] ||= outcome(child_result, theme: theme?(list[i])) }
      outcomes
    end

    # [:ok, body] or [:error, Failure] for one finished call.
    def outcome(child_result, theme:)
      [:ok, body!(child_result, theme: theme)]
    rescue Failure => e
      [:error, e]
    end

    # The body of a finished call: its stdout JSON object (what
    # Classify.check! returns; anything else is bad_response), or the raw
    # stdout with json: false. A failed call raises its classified Failure.
    def body!(child_result, json: true, theme:)
      body = Classify.check!(child_result, theme: theme)
      return child_result.stdout unless json

      body || raise(Failure.new('bad_response', 'CLI output is not a JSON object'))
    end

    # The argv of `store execute`: the query text is a Queries constant and
    # data only ever goes in --variables.
    def execute_args(domain, query, variables = nil)
      args = ['store', 'execute', "--store=#{domain}", '--no-input', '--json', "--version=#{API_VERSION}", "--query=#{query}"]
      args << "--variables=#{JSON.generate(variables)}" if variables
      args
    end

    # `store execute` of a frozen query: returns [data, budget] (budget:
    # Throttle.budget of the response's cost extensions, or nil).
    def execute(located, domain, query, variables: nil, deadline:)
      body = call(located, execute_args(domain, query, variables), deadline: deadline)
      data = body['data']
      raise Failure.new('bad_response', 'store execute returned no data') unless data.is_a?(Hash)

      [data, Throttle.budget(body['extensions'])]
    end
  end
end
