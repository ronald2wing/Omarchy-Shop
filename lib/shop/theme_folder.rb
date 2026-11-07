# Shop::ThemeFolder: what a theme folder is (shape, root files) and the rules it must pass (location, ancestors, ownership, toml, the tree walk).

module Shop
  module ThemeFolder
    # The top-level directories of a Shopify theme. Only these are walked,
    # copied and pushed.
    THEME_DIRS = %w[assets blocks config layout locales sections snippets templates].freeze
    # The directories the pinned CLI's `theme push`/`theme dev` require before
    # they run under --no-input (its required-directory check); a folder
    # without all three is not themeShaped.
    REQUIRED_DIRS = %w[config layout templates].freeze
    # Top-level files the pinned CLI (Shop::CLI_PIN) also pushes and pulls:
    # its theme glob list starts ["AGENTS.md","DESIGN.md","assets/**/*.*",…].
    # They get the same link rules as the theme dirs, are part of the local
    # copy, and the push dialogs name them.
    ROOT_FILES = %w[AGENTS.md DESIGN.md].freeze
    MAX_PATH_BYTES = 4096
    # Each refusal reason (unsafe_folder's error.reason) as the failure
    # message says it after "folder".
    REASON_TEXT = {
      'not_absolute' => 'is not an absolute path',
      'not_directory' => 'is not a directory',
      'unreadable' => 'is unreadable',
      'root' => 'is /',
      'home' => 'is your home folder',
      'config' => 'overlaps ~/.config',
      'state' => "overlaps Shop's state folder",
      'plugin' => 'overlaps the Shop plugin',
      'unsafe_parent' => 'sits in a folder others can write to or that is not yours',
      'not_owned' => 'holds an entry owned by another user',
      'world_writable' => 'holds an entry anyone can write to',
      'group_writable' => 'holds an entry its group can write to',
      'theme_toml' => 'is under a shopify.theme.toml',
      'symlink' => 'holds a symlink',
      'hardlink' => 'holds a hardlinked file',
      'special_file' => 'holds a special file',
      'too_many_files' => "holds over #{TreeWalk::MAX_ENTRIES} entries"
    }.freeze

    module_function

    # A --folder value: non-empty, at most MAX_PATH_BYTES, no control characters.
    def path!(value)
      s = value.to_s
      Validate.reject!('folder path is empty') if s.empty?
      Validate.reject!('folder path is too long') if s.bytesize > MAX_PATH_BYTES
      Validate.reject!('folder path contains control characters') if s.match?(/[\p{Cc}]/)
      s
    end

    # The report of a candidate theme folder (inspect-folder prints a subset), which states
    # folder problems instead of raising them: {folder, exists, themeShaped,
    # empty, safe, reason, at, bytes, rootFiles}. `at` is the
    # relative path the walk stopped at, or nil; rootFiles names the
    # ROOT_FILES present as regular files.
    def report(path)
      report = { 'folder' => path, 'exists' => false, 'themeShaped' => false, 'empty' => false,
                 'safe' => false, 'reason' => nil, 'at' => nil, 'bytes' => 0, 'rootFiles' => [] }
      return report.merge('reason' => 'not_absolute') unless path.start_with?('/')

      real = begin
        File.realpath(path)
      rescue Errno::ENOENT, Errno::ENOTDIR
        return report
      rescue SystemCallError
        return report.merge('exists' => true, 'reason' => 'unreadable')
      end
      report['folder'] = real
      report['exists'] = true
      st = File.stat(real)
      return report.merge('reason' => 'not_directory') unless st.directory?

      reason = location_reason(real) || ancestor_reason(real) || TreeWalk.entry_reason(st)
      return report.merge('reason' => reason) if reason

      children = Dir.children(real)
      report['empty'] = children.none? { |c| !c.start_with?('.') }
      # The CLI finds shopify.theme.toml by walking up from --path to /
      # (find-up), so a toml in any ancestor injects flags too.
      return report.merge('reason' => 'theme_toml') if ThemeToml.reachable_from?(real)

      present = THEME_DIRS.select { |d| children.include?(d) }
      shaped = REQUIRED_DIRS.all? { |d| present.include?(d) && File.lstat(File.join(real, d)).directory? }
      walked = TreeWalk.walk(real, present + (ROOT_FILES & children))
      report['rootFiles'] = ROOT_FILES.select do |name|
        File.lstat(File.join(real, name)).file?
      rescue SystemCallError
        false
      end
      report.merge('bytes' => walked[:bytes], 'reason' => walked[:reason], 'at' => walked[:at],
                   'safe' => walked[:reason].nil?, 'themeShaped' => shaped && walked[:reason].nil?)
    rescue SystemCallError
      report.merge('exists' => true, 'reason' => 'unreadable')
    end

    # Raise unless the folder suits `mode` (:push, :pull, :preview): a
    # missing folder or one that is not theme-shaped is not_a_theme_folder
    # (an empty one is a pull target), a refused one unsafe_folder. Returns
    # the report (with the real path under 'folder').
    def check!(path, mode:)
      report = ThemeFolder.report(path!(path))
      raise Failure.new('not_a_theme_folder', 'folder not found') unless report['exists'] || report['reason']
      raise refusal(report) if report['reason']

      ok = mode == :pull ? (report['themeShaped'] || report['empty']) : report['themeShaped']
      raise Failure.new('not_a_theme_folder', "no theme files (#{REQUIRED_DIRS.map { |d| "#{d}/" }.join(', ')}) in the folder") unless ok

      report
    end

    # The unsafe_folder Failure of a refused report: "folder holds a symlink
    # (snippets/x.liquid)", with the reason under error.reason.
    def refusal(report)
      reason = report['reason']
      at = report['at'].to_s.empty? ? '' : " (#{Text.quote(report['at'])})"
      Failure.new('unsafe_folder', "folder #{REASON_TEXT.fetch(reason, reason)}#{at}", reason: reason)
    end

    # The location rules: not /, $HOME, ~/.config, Shop's state dir or the
    # plugin itself; not inside the last three; not an ancestor of any of them.
    def location_reason(real)
      return 'root' if real == '/'

      home = Paths.real_or_self(Paths.home)
      return 'home' if real == home

      {
        'config' => Paths.real_or_self(File.join(Paths.home, '.config')),
        'state' => Paths.real_or_self(Paths.state_dir),
        'plugin' => Paths.real_or_self(Shop::ROOT)
      }.each do |reason, dir|
        return reason if Paths.inside?(real, dir) || Paths.inside?(dir, real)
      end
      nil
    end

    # 'unsafe_parent' when any ancestor of `real` up to / fails
    # Paths.trusted_stat? (owned by someone other than the uid or root, or
    # group- or world-writable; sticky dirs like /tmp included: others can
    # still create shopify.theme.toml there, and in a non-sticky dir they
    # can swap the folder for a symlink between this check and the CLI
    # start), else nil. The `trusted_parent:` test override ends the walk at
    # a throwaway HOME that lives under /tmp.
    def ancestor_reason(real)
      stop = Shop.overrides[:trusted_parent]
      dir = File.dirname(real)
      loop do
        return 'unsafe_parent' unless Paths.trusted_stat?(File.lstat(dir))
        return nil if dir == stop

        parent = File.dirname(dir)
        return nil if parent == dir

        dir = parent
      end
    rescue SystemCallError
      'unsafe_parent'
    end

    # A theme file path from its top-level theme directory on
    # ("/p/sections/a.liquid" -> "sections/a.liquid"), else its basename.
    def theme_relative(path)
      parts = path.split('/')
      i = parts.rindex { |p| THEME_DIRS.include?(p) }
      i ? parts[i..].join('/') : File.basename(path)
    end
  end
end
