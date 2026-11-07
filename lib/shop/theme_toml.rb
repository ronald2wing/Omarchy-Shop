# Shop::ThemeToml: finding a shopify.theme.toml the CLI would read (in a folder or any ancestor) and refusing to run a theme command over one.

module Shop
  module ThemeToml
    NAME = 'shopify.theme.toml'

    module_function

    # True when `dir` holds an entry named shopify.theme.toml (any case).
    # An unreadable but searchable dir is probed by name. A sibling whose
    # name is not valid UTF-8 is compared scrubbed (casecmp? raises on it,
    # and it can't be the toml anyway).
    def in?(dir)
      Dir.children(dir).any? { |c| Text.scrub(c).casecmp?(NAME) }
    rescue Errno::EACCES
      File.exist?(File.join(dir, NAME)) || File.symlink?(File.join(dir, NAME))
    rescue SystemCallError
      false
    end

    # True when a theme command started at `start` would find a
    # shopify.theme.toml: in `start` or any of its ancestors up to /, the
    # pinned CLI's lookup, which loads [environments.default] flags from the
    # first one it finds.
    def reachable_from?(start)
      dir = start
      loop do
        return true if in?(dir)

        parent = File.dirname(dir)
        return false if parent == dir

        dir = parent
      end
    end

    # Raise unsafe_folder (reason theme_toml) when the CLI would find a
    # shopify.theme.toml from any of `dirs` (each is checked up to /).
    # Theme commands get --path=<dir> and run with cwd Paths.run_dir, so
    # both chains are checked before any theme command is spawned.
    def refuse!(*dirs)
      dirs.compact.each do |d|
        start = Paths.real_or_self(d)
        next unless reachable_from?(start)

        raise Failure.new('unsafe_folder', "a shopify.theme.toml in or above #{Text.clean(start, 120)} would change the theme command",
                          reason: 'theme_toml')
      end
      nil
    end
  end
end
