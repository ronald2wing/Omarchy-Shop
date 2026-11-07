# Shop::ThemeJob: the frame and the order of a theme job (push-theme, pull-theme, restore-backup): the store lock, the target, the copy taken first, the line fields, the write and retention.

module Shop
  # One theme job, in the order every theme writer keeps:
  #
  #   ThemeJob.run(domain, helper: NAME) do |job|   # runtime, store lock
  #     theme = job.target!(target)                 # a fresh `theme list`
  #     job.push_with_backup!(theme, ...) { path }  # gate, backup, recheck, push
  #   end                                           # retention, same lock
  #
  # The line fields every line of the helper carries change only here:
  # "backupId" right after the backup (backed_up!), "folderCopy" right after
  # the folder copy (folder_copied!), and "writeStarted" true immediately
  # before the CLI call that writes (writing!).
  class ThemeJob
    attr_reader :domain, :located

    # Run the block with a job for `domain` under the store lock (held from
    # the theme list to the prune, so no other theme job or preview runs in
    # between), inside the helper's overall deadline; `helper` names the
    # TIMING row of the per-call caps. Retention runs last, under the same
    # lock: `keep` names backup ids it must not remove (the one a restore
    # read from). Returns the block's result.
    def self.run(domain, helper:, keep: [])
      located = Runtime.locate
      Lock.with(domain) do
        out = yield new(domain, helper, located)
        Backups.prune!(domain, keep: keep)
        out
      end
    end

    # A live target needs both the per-store opt-in and this job's
    # confirmation.
    def self.live_gate!(theme, allow_live:, confirm_live:)
      return unless Themes.live?(theme)
      raise Failure.new('live_not_allowed', 'changes to the live theme are off for this store') unless allow_live
      raise Failure.new('live_not_confirmed', 'a change to the live theme needs confirming') unless confirm_live
    end

    def initialize(domain, helper, located)
      @domain = domain
      @helper = helper
      @located = located
    end

    # The theme `target` ("live" or an id) names, from a fresh `theme list`.
    def target!(target)
      Themes.resolve(Themes.list(located, domain, deadline: step('list')), target)
    end

    # The push of push-theme and restore-backup: the live gate, a backup of
    # `theme`, then `theme push --nodelete` of the source path the block
    # returns. The backup can take minutes, so the block rechecks the source
    # right before the push. Every line from the backup on names it, and
    # from the push call on says the write started. Returns [backup id,
    # Themes.sync_result].
    def push_with_backup!(theme, before:, allow_live:, confirm_live:)
      ThemeJob.live_gate!(theme, allow_live: allow_live, confirm_live: confirm_live)
      id = Backups.take!(located, domain, theme, before: before, deadline: step('backup'))
      backed_up!(id)
      path = yield
      writing!
      body = Shopify.call(located, Themes.push_args(domain, theme, path), deadline: step('push'))
      # A skipped or unexpected status fails here, still after the backup.
      [id, Themes.sync_result(body)]
    end

    # The pull of pull-theme: a copy of what the pull can overwrite (none
    # for an empty folder; `report` is ThemeFolder.check!'s), then `theme
    # pull --nodelete --force` into the folder path the block returns. The
    # theme list and the copy can take over a minute, so the block rechecks
    # the folder right before the pull (the pull writer follows links).
    # Returns [folder copy id or nil, the path pulled into].
    def pull_with_copy!(theme, report)
      copy = nil
      unless report['empty']
        copy = FolderCopies.create!(domain, report)
        folder_copied!(copy)
      end
      path = yield
      writing!
      body = Shopify.call(located, Themes.pull_args(domain, theme, path), deadline: step('pull'))
      Themes.sync_result(body, pull: true)
      [copy, path]
    end

    # Every line from now on names the backup just taken.
    def backed_up!(id)
      HelperMain.set_line_fields!('backupId' => id)
    end

    # Every line from now on names the folder copy just made.
    def folder_copied!(id)
      HelperMain.set_line_fields!('folderCopy' => id)
    end

    # The write is about to start: every line from now on says the theme
    # (or the folder) may have changed.
    def writing!
      HelperMain.set_line_fields!('writeStarted' => true)
    end

    private

    # The deadline of step `name` of the helper's TIMING row, within what is
    # left of the helper's overall deadline.
    def step(name)
      HelperMain.overall_cap(Shop.seconds(:call, @helper, name))
    end
  end
end
