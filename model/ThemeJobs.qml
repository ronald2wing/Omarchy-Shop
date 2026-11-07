pragma ComponentBehavior: Bound
import QtQuick
import "../js/os.mjs" as Os
import "../js/themejob.mjs" as ThemeJob

// One push, pull or restore job at a time per store (callers run
// Preflight first: requireStoreIdle is the gate), and its last result. Jobs
// on different stores never block each other.
Item {
  id: root

  // Bumped on every state change; read state through stateFor().
  readonly property int revision: internal.revision

  // A push, pull or restore finished (canceled ones included).
  signal jobFinished(string domain, var result)

  // { job: {action, startedAt, name, folder, restoredBackupId} | null,
  //   lastResult: ThemeJob.resultOf's result | null }
  // or null before any job ran for this store.
  function stateFor(domain) {
    return internal.states[domain] || null
  }

  function isBusy(domain) {
    const s = internal.states[domain]
    return !!(s && s.job)
  }

  // Any store's job (Preflight.requireThemesIdle).
  function busyAny() {
    const keys = Object.keys(internal.states)
    for (let i = 0; i < keys.length; i++) if (root.isBusy(keys[i])) return true
    return false
  }

  // opts: { folder, target, name, allowLive, confirmLive }. The two live
  // consents travel separately: allowLive (the store's opt-in) passes
  // --allow-live, confirmLive (a live dialog the user accepted) passes
  // --confirm-live. A live target the dialog did not confirm then fails
  // with live_not_confirmed, which the store view answers with the live
  // confirmation. name: the target's display name for the result (the
  // helper's cleaned name; helpers report the real one).
  function push(domain, opts) {
    internal.startJob(domain, "push", ThemeJob.jobCommand("push", domain, opts), opts.name, opts.folder, null)
  }

  // opts: { folder, target, name }. A pull takes no live consent.
  function pull(domain, opts) {
    internal.startJob(domain, "pull", ThemeJob.jobCommand("pull", domain, opts), opts.name, opts.folder, null)
  }

  function restore(domain, backupId, allowLive, confirmLive, name) {
    const cmd = ThemeJob.jobCommand("restore", domain, { backupId: backupId, allowLive: allowLive, confirmLive: confirmLive })
    internal.startJob(domain, "restore", cmd, name, "", backupId)
  }

  // TERM the job; its result arrives as error.code "terminated".
  function cancelJob(domain) {
    const p = internal.procs[domain]
    if (!p) return
    internal.canceling[domain] = true
    p.terminate()
  }

  function dismiss(domain) {
    const s = internal.states[domain]
    if (!s || !s.lastResult) return
    internal.setState(domain, Object.assign({}, s, { lastResult: null }))
  }

  // Clears every store's theme_session_expired result.
  function dismissSessionExpired() {
    const domains = Object.keys(internal.states)
    for (let i = 0; i < domains.length; i++) {
      const lr = internal.states[domains[i]].lastResult
      if (lr && lr.error && lr.error.code === "theme_session_expired") root.dismiss(domains[i])
    }
  }

  function forget(domain) {
    internal.stop(domain)
    delete internal.states[domain]
    delete internal.canceling[domain]
    internal.revision++
  }

  QtObject {
    id: internal
    property var states: Object.create(null)
    property var procs: Object.create(null)
    property var canceling: Object.create(null)
    property int revision: 0

    function get(domain) {
      return internal.states[domain] || { job: null, lastResult: null }
    }

    function setState(domain, s) {
      internal.states[domain] = s
      internal.revision++
    }

    function stop(domain) {
      const p = internal.procs[domain]
      if (!p) return
      p.cancel()
      p.destroy()
      delete internal.procs[domain]
    }

    // restoredBackupId: the backup a restore pushes (its result's backupId is
    // the fresh pre-restore backup, so the two are kept apart).
    // cmd: ThemeJob.jobCommand's { helper, args }.
    function startJob(domain, action, cmd, name, folder, restoredBackupId) {
      const s = Object.assign({}, internal.get(domain))
      s.job = { action: action, startedAt: Date.now(), name: name, folder: folder, restoredBackupId: restoredBackupId }
      internal.setState(domain, s)
      const p = procComponent.createObject(root, { helper: cmd.helper })
      internal.procs[domain] = p
      p.finished.connect(r => {
        delete internal.procs[domain]
        p.destroy()
        internal.handle(domain, r)
      })
      p.run(cmd.args)
    }

    function handle(domain, result) {
      const s = Object.assign({}, internal.get(domain))
      const canceled = !!internal.canceling[domain]
      delete internal.canceling[domain]
      // Arrays inside a `var` signal argument arrive as non-arrays (Os.plain).
      const out = ThemeJob.resultOf(s.job, Os.plain(result), { canceled: canceled, nowMs: Date.now() })
      s.job = null
      s.lastResult = out
      internal.setState(domain, s)
      root.jobFinished(domain, out)
    }
  }

  // `helper` has no default: every job names its own.
  Component {
    id: procComponent
    HelperProcess {}
  }
}
