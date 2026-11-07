pragma ComponentBehavior: Bound
import QtQuick
import "../js/errors.mjs" as Errors
import "../js/os.mjs" as Os
import "../js/themes.mjs" as Themes

// Per-store read-only theme information: the themes list (cached), the
// folder inspection and the backups list. Each refresher runs one helper
// at a time per store; a new folder path replaces an inspection in flight.
// A rate-limited themes list is fetched again by itself, once, at the
// retryAfter the helper always gives (1-3600 s, capped at 15 minutes
// here); any other listThemes call replaces that
// pending retry.
Item {
  id: root

  // Bumped on every state change; read state through stateFor().
  readonly property int revision: internal.revision

  // The store's themeState (js/themes.mjs has the shape and the reducers),
  // or null before anything was asked for this store.
  function stateFor(domain) {
    return internal.states[domain] || null
  }

  // The theme the store's config `theme` pushes to and pulls from:
  // Themes.targetOf's { id, name, live } over the cached list ("" name
  // before it loads).
  function target(domain, theme) {
    return Themes.targetOf(theme, internal.states[domain])
  }

  function backupById(domain, id) {
    return Themes.backupById(internal.states[domain], id)
  }

  // Themes.restoreIsLive: the rule the panel's dialog shows and Preflight
  // gates on (taken from the live theme, or of the theme live now). A theme
  // that became live since is refused by the helper (live_not_confirmed)
  // and asked again.
  function restoreIsLive(domain, id) {
    return Themes.restoreIsLive(internal.states[domain], id)
  }

  // Lists the themes when they were never fetched or are older than
  // maxAgeMs, unless a rate-limited list already has its retry pending.
  function listThemesIfStale(domain, maxAgeMs) {
    if (root.themesRetryMs(domain) !== 0) return
    const s = internal.states[domain]
    const at = s ? s.themes.fetchedAt : 0
    if (at === 0 || Date.now() - at > maxAgeMs) root.listThemes(domain)
  }

  function listThemes(domain) {
    internal.stopRetry(domain)
    if (internal.isRunning(domain, "themes")) return
    internal.patch(domain, "themes", { status: "loading", error: null })
    internal.spawn(domain, "themes", "")
  }

  function listBackups(domain) {
    if (internal.isRunning(domain, "backups")) return
    internal.patch(domain, "backups", { status: "loading", error: null })
    internal.spawn(domain, "backups", "")
  }

  // An empty folder clears the inspection; a new folder replaces one in flight.
  function inspectFolder(domain, folder) {
    internal.stop(domain, "folder")
    if (!folder) {
      internal.set(domain, "folder", Themes.emptyFolder())
      return
    }
    internal.patch(domain, "folder", { status: "checking", requested: folder, error: null })
    internal.spawn(domain, "folder", folder)
  }

  // A theme job on this store ended (ThemeJobs.jobFinished; theme: the
  // store's config `theme`): refresh what it may have changed. A new
  // backup or folder copy relists the backups, the folder is inspected
  // again, and the themes list is fetched again when the job showed the
  // cached role of the target is stale, so the live badge, the live-lock
  // notice and the next push dialog use the real role.
  function refreshAfterJob(domain, theme, result) {
    if (result.ok || result.backupId || result.folderCopy) root.listBackups(domain)
    if (theme && theme.folder) root.inspectFolder(domain, theme.folder)
    const target = theme ? theme.target : ""
    const liveUnconfirmed = !!result.error && result.error.code === "live_not_confirmed"
    const cached = target !== "" && target !== "live" ? Themes.themeById(internal.states[domain], target) : null
    const roleChanged = !!result.ok && !!result.theme && !!result.theme.role && target !== "" && target !== "live"
      && result.theme.role !== (cached ? cached.role : "")
    if (theme && (liveUnconfirmed || roleChanged)) root.listThemes(domain)
  }

  function forget(domain) {
    const kinds = Object.keys(internal.kinds)
    for (let i = 0; i < kinds.length; i++) internal.stop(domain, kinds[i])
    internal.stopRetry(domain)
    delete internal.states[domain]
    internal.revision++
  }

  // The delay of the pending rate-limit retry of the themes list, or 0.
  function themesRetryMs(domain) {
    const t = internal.retries[domain]
    return t ? t.interval : 0
  }

  QtObject {
    id: internal
    property var states: Object.create(null)
    property var procs: Object.create(null)
    // domain -> the one-shot Timer of a rate-limited themes list.
    property var retries: Object.create(null)
    property int revision: 0
    // Per kind: the helper, its argv for (domain, folder), and the reducer
    // that turns its plain result into the next state of that part
    // (js/themes.mjs; folder is the inspected path).
    readonly property var kinds: ({
      themes: { helper: "list-themes", args: d => ["--store=" + d], reduce: (prev, r, now) => Themes.reduceThemes(prev, r, now) },
      backups: { helper: "list-backups", args: d => ["--store=" + d], reduce: (prev, r) => Themes.reduceBackups(prev, r) },
      folder: { helper: "inspect-folder", args: (d, folder) => ["--folder=" + folder], reduce: (prev, r, now, folder) => Themes.reduceFolder(folder, r) }
    })

    function get(domain) {
      return internal.states[domain] || Themes.emptyThemeState()
    }

    function set(domain, key, value) {
      const s = Object.assign({}, internal.get(domain))
      s[key] = value
      internal.states[domain] = s
      internal.revision++
    }

    function patch(domain, key, value) {
      internal.set(domain, key, Object.assign({}, internal.get(domain)[key], value))
    }

    function isRunning(domain, kind) {
      return !!internal.procs[domain + ":" + kind]
    }

    function stop(domain, kind) {
      const key = domain + ":" + kind
      const p = internal.procs[key]
      if (!p) return
      p.cancel()
      p.destroy()
      delete internal.procs[key]
    }

    function spawn(domain, kind, folder) {
      const k = internal.kinds[kind]
      const p = procComponent.createObject(root, { helper: k.helper })
      const key = domain + ":" + kind
      internal.procs[key] = p
      p.finished.connect(r => {
        delete internal.procs[key]
        p.destroy()
        internal.handle(domain, kind, r)
      })
      p.run(k.args(domain, folder))
    }

    function stopRetry(domain) {
      const t = internal.retries[domain]
      if (!t) return
      t.stop()
      t.destroy()
      delete internal.retries[domain]
    }

    function scheduleRetry(domain, error) {
      internal.stopRetry(domain)
      const t = retryComponent.createObject(root, { interval: Math.min(900000, error.retryAfter * 1000) })
      internal.retries[domain] = t
      t.triggered.connect(() => {
        delete internal.retries[domain]
        t.destroy()
        root.listThemes(domain)
      })
      t.start()
    }

    function handle(domain, kind, result) {
      // Arrays inside a `var` signal argument arrive as non-arrays (Os.plain).
      const r = Os.plain(result)
      const prev = internal.get(domain)[kind]
      const next = internal.kinds[kind].reduce(prev, r, Date.now(), prev.requested || "")
      internal.set(domain, kind, next)
      if (kind === "themes" && next.error && Errors.isRateLimit(next.error.code)) internal.scheduleRetry(domain, next.error)
    }
  }

  Component {
    id: procComponent
    HelperProcess {}
  }

  Component {
    id: retryComponent
    Timer { repeat: false }
  }
}
