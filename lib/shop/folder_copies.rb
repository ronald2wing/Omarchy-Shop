# Shop::FolderCopies: the copy of a theme folder pull-theme takes before a pull overwrites it (backups/<domain>/local/<epoch>/), listed and pruned.

module Shop
  module FolderCopies
    KEEP = 5
    MAX_BYTES = 200 * MIB
    # A store's folder copies live in this subdir of Backups.domain_dir.
    DIR = 'local'

    module_function

    # Copy everything a pull can overwrite to backups/<domain>/local/<epoch>/
    # (staged, Backups.stage!): the theme dirs and the top-level
    # ThemeFolder::ROOT_FILES (AGENTS.md, DESIGN.md), the same set the folder
    # walk checks and counts. Links are never followed (the walk already
    # refused any). `report` is the ThemeFolder.check! report, whose lstat
    # byte count bounds the copy. A Failure (folder_too_large, terminated)
    # keeps its code; anything else is backup_failed. Returns the copy id.
    def create!(domain, report)
      raise Failure.new('folder_too_large', "folder is over #{MAX_BYTES / MIB} MiB") if report['bytes'].to_i > MAX_BYTES

      Backups.domain_dir!(domain)
      dir = Paths.ensure_private_dir!(copies_dir(domain))
      Backups.stage!(dir) { |partial| copy_into!(partial, report['folder']) }
    rescue Failure
      raise
    rescue StandardError => e
      raise Failure.new('backup_failed', "copying the folder failed: #{Text.os_error(e)}")
    end

    # Copy the theme dirs and root files of `folder` into `dest`, keeping
    # modes and times; what is not there is skipped.
    def copy_into!(dest, folder)
      ThemeFolder::THEME_DIRS.each do |name|
        src = File.join(folder, name)
        next unless File.lstat(src).directory?

        FileUtils.cp_r(src, dest, preserve: true, dereference_root: false)
      rescue Errno::ENOENT
        next
      end
      ThemeFolder::ROOT_FILES.each do |name|
        src = File.join(folder, name)
        st = File.lstat(src)
        next unless st.file? && st.nlink == 1

        FileUtils.cp(src, File.join(dest, name), preserve: true)
      rescue Errno::ENOENT
        next
      end
    end

    # The folder copy ids of `domain`, newest first: the epoch-named plain
    # dirs of backups/<domain>/local/ owned by the uid (lstat only, no walk).
    def ids(domain)
      dir = copies_dir(domain)
      return [] unless Backups.plain_dir?(dir)

      Dir.children(dir).select do |name|
        next false unless Validate.epoch?(name)

        st = File.lstat(File.join(dir, name))
        st.directory? && st.uid == Process.uid
      rescue SystemCallError
        false
      end.sort_by { |name| -name.to_i }
    end

    # The folder copies of `domain`, newest first: [{id, at, files, bytes, path}].
    def list(domain)
      dir = copies_dir(domain)
      ids(domain).map do |id|
        path = File.join(dir, id)
        files, bytes = TreeWalk.stats(path)
        { 'id' => id, 'at' => id.to_i * 1000, 'files' => files, 'bytes' => bytes, 'path' => path }
      end
    end

    # Keep the newest KEEP copies (Backups.prune! calls it under the store
    # lock); by id alone, so retention never walks a copy.
    def prune!(domain)
      dir = copies_dir(domain)
      ids(domain).drop(KEEP).each { |id| Backups.remove!(File.join(dir, id)) }
    end

    # backups/<domain>/local/.
    def copies_dir(domain) = File.join(Backups.domain_dir(domain), DIR)
  end
end
