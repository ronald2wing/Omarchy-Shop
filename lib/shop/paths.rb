# Shop::Paths: the config/state dirs (0700, symlinks refused), the private empty cwd, the node bin dir and the path and ownership rules they share.

require 'fileutils'

module Shop
  module Paths
    module_function

    def home
      h = ENV['HOME'].to_s
      raise Failure.new('unsafe_state_dir', 'the home folder is not an absolute path') unless h.start_with?('/')

      h
    end

    def config_dir = File.join(home, '.config', 'shop')
    def state_dir = File.join(home, '.local', 'state', 'shop')
    def backups_dir = File.join(state_dir, 'backups')
    def locks_dir = File.join(state_dir, 'locks')
    # The cwd of every child: private, empty, 0700, so no shopify.theme.toml,
    # .env or mise.toml can be found there.
    def run_dir = File.join(state_dir, 'run')
    # Holds only `node` -> the pinned node; first on the CLI's PATH.
    def bin_dir = File.join(state_dir, 'bin')

    # mise's own order: MISE_DATA_DIR, then $XDG_DATA_HOME/mise, then
    # ~/.local/share/mise (install-cli passes XDG_DATA_HOME through to mise,
    # so the CLI must be looked for where mise put it).
    def mise_data_dir
      dir = ENV['MISE_DATA_DIR'].to_s
      return dir if dir.start_with?('/')

      xdg = ENV['XDG_DATA_HOME'].to_s
      xdg.start_with?('/') ? File.join(xdg, 'mise') : File.join(home, '.local', 'share', 'mise')
    end

    def all_dirs
      [config_dir, state_dir, backups_dir, locks_dir, run_dir, bin_dir]
    end

    # Create every dir at 0700. An existing dir is checked with lstat first: a
    # symlink, a non-directory or a dir owned by someone else is
    # `unsafe_state_dir`; chmod only happens after that check.
    def prepare!
      all_dirs.each { |dir| ensure_private_dir!(dir) }
    end

    def ensure_private_dir!(dir)
      FileUtils.mkdir_p(File.dirname(dir), mode: 0o700)
      begin
        Dir.mkdir(dir, 0o700)
      rescue Errno::EEXIST
        # checked below
      end
      st = File.lstat(dir)
      unsafe!(dir, 'is a symlink') if st.symlink?
      unsafe!(dir, 'is not a directory') unless st.directory?
      unsafe!(dir, 'is owned by another user') unless st.uid == Process.uid
      File.chmod(0o700, dir) unless (st.mode & 0o777) == 0o700
      dir
    rescue SystemCallError => e
      unsafe!(dir, "cannot be made private (#{Text.os_error(e)})")
    end

    # The service's own files, written by QML FileViews that cannot set a
    # mode: a newly created one comes out at the shell's umask (the 0700 dirs
    # already keep it private), so each prepare-state brings existing ones
    # back to 0600. Symlinks and other users' files are left alone.
    def service_files
      [File.join(config_dir, 'config.json'), File.join(config_dir, 'config.json.old'), File.join(state_dir, 'cache.json')]
    end

    def tighten_service_files!
      service_files.each do |path|
        st = File.lstat(path)
        next unless st.file? && st.uid == Process.uid && (st.mode & 0o777) != 0o600

        File.chmod(0o600, path)
      rescue SystemCallError
        nil
      end
    end

    def unsafe!(dir, why)
      raise Failure.new('unsafe_state_dir', "#{dir.sub(home, '~')} #{why}")
    end

    # Write `data` to `path` atomically at 0600 (temp file + rename).
    def write_private!(path, data)
      tmp = "#{path}.tmp-#{Process.pid}"
      File.open(tmp, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) { |f| f.write(data) }
      File.rename(tmp, path)
    ensure
      File.unlink(tmp) if tmp && File.exist?(tmp)
    end

    # A stat of something owned by the uid or root that nobody else can
    # write (group and world write bits clear): the one rule for every file
    # Shop executes (Runtime.trusted_file?) and every directory above a
    # theme folder (ThemeFolder.ancestor_reason).
    def trusted_stat?(st)
      [Process.uid, 0].include?(st.uid) && (st.mode & 0o022).zero?
    end

    # The real path of `path`, or its plain expansion when it cannot be
    # resolved (missing, unreadable).
    def real_or_self(path)
      File.realpath(path)
    rescue SystemCallError
      File.expand_path(path)
    end

    # True when `path` equals `dir` or lies inside it (both real paths).
    def inside?(path, dir)
      path == dir || path.start_with?(dir.end_with?('/') ? dir : "#{dir}/")
    end
  end
end
