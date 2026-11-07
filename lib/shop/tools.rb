# Shop::Tools: the external tools Shop runs, each by its absolute argv0 (the `tools:` test override replaces one) under its own environment profile.

module Shop
  module Tools
    PATHS = {
      setpriv: '/usr/bin/setpriv',
      mise: '/usr/bin/mise',
      notify_send: '/usr/bin/notify-send',
      pw_play: '/usr/bin/pw-play',
      paplay: '/usr/bin/paplay',
      wl_paste: '/usr/bin/wl-paste'
    }.freeze
    # The Env.for_tool profile each runnable tool gets. setpriv is not
    # here: it is the prefix of every child (Shop::Child), never run alone.
    PROFILES = {
      mise: :mise,
      notify_send: :notify,
      pw_play: :sound,
      paplay: :sound,
      wl_paste: :clipboard
    }.freeze

    module_function

    # The absolute path of tool `name` (a PATHS key); an unknown name is a
    # KeyError, never a PATH lookup.
    def path(name)
      Shop.overrides.dig(:tools, name) || PATHS.fetch(name)
    end

    # True when the tool is installed (its path is an executable file).
    def available?(name)
      File.executable?(path(name))
    end

    # Run tool `name` (a PROFILES key) with `args` under the supervisor, in
    # its own allowlisted environment; returns the Command::Result. A tool
    # that cannot be started is `tool_failed`.
    def run(name, args, deadline:, max_stdout:, **command_opts)
      env = Env.for_tool(PROFILES.fetch(name))
      Command.run([path(name), *args], env: env, deadline: deadline, max_stdout: max_stdout, **command_opts)
    end
  end
end
