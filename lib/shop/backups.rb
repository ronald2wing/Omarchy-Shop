# Shop::Backups: the remote-theme backups taken before a push or restore (files/ + meta.json): taking one atomically, finding, listing and pruning them, and the staging both kinds of copy are built in.

require 'fileutils'

module Shop
  module Backups
    KEEP = 10
    # A .partial-<epoch>-<pid> dir older than this is a crashed run's leftover.
    PARTIAL_MAX_AGE = 3600
    PARTIAL_RE = /\A\.partial-(\d{10})-\d+\z/
    META_SCHEMA = 2
    META_MAX_BYTES = 64 * KIB
    META_MAX_NESTING = 8
    BEFORE = %w[push restore].freeze
    # Failures of the backup pull that keep their own code: the user needs
    # the real reason (and the remedy it names), not a generic backup_failed.
    # The pull is a theme command, so sales_access_required cannot occur
    # (Classify maps those messages to cli_failed on theme commands).
    PASS_THROUGH = %w[terminated unsafe_folder signed_out theme_session_expired rate_limited
                      timeout output_too_large store_unavailable].freeze

    module_function

    # backups/<domain>/, created private when missing.
    def domain_dir!(domain)
      Paths.ensure_private_dir!(File.join(Paths.backups_dir, domain))
    end

    # The first epoch from `start` on whose "<epoch><suffix>" is free in `dir`.
    def free_epoch(dir, suffix = '', start:)
      epoch = start
      epoch += 1 while File.exist?(File.join(dir, "#{epoch}#{suffix}"))
      epoch
    end

    # Build a new entry of `dir` out of sight: the block fills
    # .partial-<epoch>-<pid>, which is then renamed to the first free
    # "<epoch><suffix>" and that name returned. Any exception (a failure, a
    # stop, a crash) removes the partial and propagates, so an incomplete
    # copy is never listed; a partial left by a killed process is pruned
    # after PARTIAL_MAX_AGE.
    def stage!(dir, suffix: '')
      epoch = Shop.now.to_i
      path = File.join(dir, ".partial-#{epoch}-#{Process.pid}")
      Dir.mkdir(path, 0o700)
      partial = path
      yield partial
      id = "#{free_epoch(dir, suffix, start: epoch)}#{suffix}"
      File.rename(partial, File.join(dir, id))
      partial = nil
      id
    ensure
      remove!(partial) if partial
    end

    # Back up `theme` (the push/restore target) of `domain` before `before`
    # (push|restore): pull it into a staged files/, write meta.json beside
    # it, and name it <epoch>-<themeId>. Any failure raises backup_failed,
    # except the PASS_THROUGH codes, which keep their own. A pull status
    # other than 'success' fails too: an incomplete tree is no safety net,
    # and a later restore of it with --nodelete could never bring the
    # missing files back. Returns the id.
    def take!(located, domain, theme, before:, deadline:)
      stage!(domain_dir!(domain), suffix: "-#{theme['id']}") do |partial|
        files = File.join(partial, 'files')
        Dir.mkdir(files, 0o700)
        Themes.sync_result(Shopify.call(located, Themes.pull_args(domain, theme, files), deadline: deadline), pull: true)
        count, bytes = TreeWalk.stats(files)
        meta = { 'schema' => META_SCHEMA, 'domain' => domain, 'themeId' => theme['id'], 'themeName' => theme['name'],
                 'role' => theme['role'], 'before' => before, 'files' => count, 'bytes' => bytes }
        Paths.write_private!(File.join(partial, 'meta.json'), "#{JSON.generate(meta)}\n")
      end
    rescue StandardError => e
      failure = e.is_a?(Failure) ? e : nil
      raise if failure && PASS_THROUGH.include?(failure.code)

      raise Failure.new('backup_failed', "backup of #{theme['name']} failed: #{Text.os_error(e)}", details: failure&.details)
    end

    # A refused entry inside a backup tree (symlink, hardlink, special_file,
    # not_owned, world_writable, unreadable, too_many_files), a
    # shopify.theme.toml at its top, or nil.
    def tree_reason(root)
      reason = TreeWalk.walk(root)[:reason]
      return reason if reason
      return 'theme_toml' if ThemeToml.in?(root)

      nil
    end

    # A completed remote backup of `domain`: the dir is a real (non-symlink)
    # dir owned by the uid, `files/` resolves to exactly where it should,
    # meta.json is valid (read_meta) for this store and the id's
    # theme, and nothing inside is refused by the folder walk. Anything else
    # is backup_not_found. Returns {dir:, files:, meta:}.
    def find!(domain, id)
      Validate.backup_id!(id)
      base = File.join(Paths.backups_dir, domain)
      dir = File.join(base, id)
      files = File.join(dir, 'files')
      not_found = ->(why) { raise Failure.new('backup_not_found', "backup #{id}: #{why}") }
      begin
        [base, dir, files].each do |p|
          st = File.lstat(p)
          not_found.call('not a plain directory') if st.symlink? || !st.directory?
          not_found.call('owned by another user') unless st.uid == Process.uid
        end
        not_found.call('path escapes the backups dir') unless File.realpath(files) == File.join(File.realpath(Paths.backups_dir), domain, id, 'files')
      rescue SystemCallError => e
        not_found.call(Text.os_error(e))
      end
      meta = read_meta(File.join(dir, 'meta.json'))
      not_found.call('meta.json missing, invalid or not yours') unless meta
      not_found.call('belongs to another store') unless meta['domain'] == domain
      not_found.call('theme id mismatch') unless id_matches_meta?(id, meta)
      reason = tree_reason(files)
      not_found.call("contains a #{reason}") if reason
      { dir: dir, files: files, meta: meta }
    end

    # The parsed meta.json of a completed backup (a plain file of the uid's,
    # at most META_MAX_BYTES, schema META_SCHEMA), else nil.
    def read_meta(path)
      st = File.lstat(path)
      return nil unless st.file? && st.uid == Process.uid

      meta = Json.read_object(path, max_bytes: META_MAX_BYTES, max_nesting: META_MAX_NESTING)
      meta && meta['schema'] == META_SCHEMA ? meta : nil
    rescue SystemCallError
      nil
    end

    # The <epoch>-<themeId> id names the theme the meta was taken from.
    def id_matches_meta?(id, meta)
      meta['themeId'].to_s == id.split('-', 2).last
    end

    # The list-backups row of a backup's meta.
    def row(id, meta)
      epoch = id.split('-', 2).first.to_i
      { 'id' => id, 'at' => epoch * 1000,
        'theme' => Themes.theme_hash(meta['themeId'], meta['themeName'], meta['role']),
        'before' => BEFORE.include?(meta['before']) ? meta['before'] : 'push',
        'files' => meta['files'].is_a?(Integer) ? meta['files'] : 0,
        'bytes' => meta['bytes'].is_a?(Integer) ? meta['bytes'] : 0 }
    end

    # A directory that is not a symlink: the only kind Shop lists or prunes.
    def plain_dir?(path) = File.directory?(path) && !File.symlink?(path)

    # Completed backups of `domain`, newest first: [{id, at, theme{id, name,
    # role}, before, files, bytes}].
    def completed(domain)
      dir = File.join(Paths.backups_dir, domain)
      return [] unless plain_dir?(dir)

      Dir.children(dir).filter_map do |name|
        next unless Validate.backup_id?(name)

        path = File.join(dir, name)
        next if File.symlink?(path)

        meta = read_meta(File.join(path, 'meta.json'))
        next unless meta && meta['domain'] == domain && id_matches_meta?(name, meta)

        row(name, meta)
      end.sort_by { |b| -b['at'] }
    end

    # Retention, only under Lock.with(domain): KEEP backups and
    # FolderCopies::KEEP folder copies, and stale partials removed. `keep`
    # names backup ids that are never pruned in this pass (the one just
    # restored from).
    def prune!(domain, keep: [])
      dir = File.join(Paths.backups_dir, domain)
      return unless plain_dir?(dir)

      completed(domain).drop(KEEP).each { |b| remove!(File.join(dir, b['id'])) unless keep.include?(b['id']) }
      FolderCopies.prune!(domain)
      [dir, File.join(dir, 'local')].each { |d| prune_partials!(d) }
    end

    # Remove the stage! leftovers in `dir` older than PARTIAL_MAX_AGE (a
    # fresh one may belong to a job still running).
    def prune_partials!(dir)
      return unless plain_dir?(dir)

      cutoff = Shop.now.to_i - PARTIAL_MAX_AGE
      Dir.children(dir).each do |name|
        m = PARTIAL_RE.match(name)
        next unless m && m[1].to_i < cutoff

        remove!(File.join(dir, name))
      end
    end

    def remove!(path)
      FileUtils.rm_r(path, secure: true, force: true)
    end
  end
end
