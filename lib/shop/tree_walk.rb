# Shop::TreeWalk: the one lstat walk of a theme folder or backup tree, refusing links, special files and foreign or writable entries.

module Shop
  module TreeWalk
    MAX_ENTRIES = 20_000
    # Refusal reasons that name a link (pull-theme reports one a pull left behind).
    LINK_REASONS = %w[symlink hardlink].freeze
    # How often (in entries) a walk checks for a stop or its deadline.
    CHECK_EVERY = 256

    module_function

    # Walk the tree under `root` by lstat; `entries` are the top-level names
    # to visit (default: everything in it). Refuses any symlink (the CLI's
    # pull writer follows a link wherever it points and its fast-glob
    # follows symlinked dirs on push), any regular file with nlink > 1, any
    # entry owned by another user or group- or world-writable (another
    # local user could drop or rewrite content Shop then pushes, or plant a
    # link after the walk), anything that is not a dir or a regular file
    # (FIFO, socket, device: `special_file`), more than MAX_ENTRIES entries
    # or more than the inspect-folder walk cap (Shop::TIMING; the same cap
    # in every helper, and never past the helper's overall deadline). A
    # system error while reading (permission, a path
    # past PATH_MAX, a vanished entry) is `unreadable`. Returns {files:,
    # bytes:, reason:, at:} where `at` is the relative path of the refused
    # entry.
    def walk(root, entries = nil)
      deadline = Deadline.new(HelperMain.overall_cap(Shop.seconds(:walk, 'inspect-folder')))
      cap = max_entries
      files = 0
      bytes = 0
      count = 0
      pops = 0
      full = nil
      prefix = "#{root}/"
      # `at` is display-only, so it is scrubbed here: a name that is not
      # valid UTF-8 must still reach the panel as this refusal.
      refused = ->(reason, path) { { files: files, bytes: bytes, reason: reason, at: Text.scrub(path.delete_prefix(prefix)) } }
      checkpoint = lambda do
        Signals.check!
        raise Failure.new('timeout', 'folder walk took too long') if deadline.expired?
      end
      # Counted while listing, not when popped: one huge directory is
      # refused (and stays interruptible) as its names come in, before
      # they all sit on the stack.
      stack = []
      push = lambda do |path|
        count += 1
        return false if count > cap

        checkpoint.call if (count % CHECK_EVERY).zero?
        stack << path
        true
      end
      (entries || Dir.each_child(root)).each do |name|
        path = File.join(root, name)
        return refused.call('too_many_files', path) unless push.call(path)
      end
      stack.reverse!
      until stack.empty?
        full = stack.pop
        # A deep tree of small directories is interrupted too.
        pops += 1
        checkpoint.call if (pops % CHECK_EVERY).zero?
        st = File.lstat(full)
        return refused.call('symlink', full) if st.symlink?
        return refused.call(entry_reason(st), full) if entry_reason(st)

        if st.directory?
          Dir.each_child(full) do |name|
            path = File.join(full, name)
            return refused.call('too_many_files', path) unless push.call(path)
          end
        elsif st.file?
          return refused.call('hardlink', full) if st.nlink > 1

          files += 1
          bytes += st.size
        else
          return refused.call('special_file', full)
        end
      end
      { files: files, bytes: bytes, reason: nil, at: nil }
    rescue SystemCallError
      { files: files, bytes: bytes, reason: 'unreadable', at: full && Text.scrub(full.delete_prefix(prefix)) }
    end

    # [regular files, bytes] of a tree (links are not followed).
    def stats(root)
      walked = walk(root)
      [walked[:files], walked[:bytes]]
    end

    # 'not_owned', 'world_writable' or 'group_writable' for a folder or a
    # walked entry (dir or file), else nil. The same mask as
    # ThemeFolder.ancestor_reason: a group-writable folder lets every member
    # of that group drop a file the next push uploads, or plant a link
    # between the pre-push walk and the CLI's read.
    def entry_reason(st)
      return 'not_owned' unless st.uid == owner_uid
      return nil unless st.directory? || st.file?
      return 'world_writable' if (st.mode & 0o002).nonzero?
      return 'group_writable' if (st.mode & 0o020).nonzero?

      nil
    end

    # The entry cap of a walk (a method so tests can lower it).
    def max_entries
      MAX_ENTRIES
    end

    # The uid every entry must belong to (a method so tests can simulate a
    # foreign owner without root).
    def owner_uid
      Process.uid
    end
  end
end
