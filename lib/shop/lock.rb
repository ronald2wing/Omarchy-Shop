# Shop::Lock: the per-store flock that serialises theme operations (push, pull, restore, preview) and the prune they end with.

module Shop
  module Lock
    module_function

    # Run the block holding locks_dir/<domain>.lock (LOCK_EX|LOCK_NB); a held
    # lock is `store_busy`. The domain is validated by the caller.
    def with(domain)
      path = File.join(Paths.locks_dir, "#{domain}.lock")
      file = File.open(path, File::RDWR | File::CREAT | File::NOFOLLOW, 0o600)
      raise Failure.new('store_busy', 'another theme action is running for this store') unless file.flock(File::LOCK_EX | File::LOCK_NB)

      yield
    rescue Errno::ELOOP
      raise Failure.new('unsafe_state_dir', 'lock file is a symlink')
    ensure
      file&.close
    end
  end
end
