pragma ComponentBehavior: Bound
import QtQuick

// A keyed set of running HelperProcess instances, at most one per key (a
// store, "<store>:<kind>", a fetch's queue key): each is created for its
// run and destroyed when it finishes or is canceled, so no model holds a
// process it no longer needs. HelperProcess is still the only process
// starter; the pool only owns their lifetimes.
Item {
  id: root

  // The helper every run starts unless run()'s props name another.
  property string helper: ""
  // How many runs are live.
  readonly property int count: internal.count

  function has(key) {
    return !!internal.procs[key]
  }

  // Start `args` under `key`, a HelperProcess with `props` (helper, range,
  // ...). onFinished(result) runs once the process is gone. A key that is
  // already running is refused (false); callers check has() first.
  function run(key, props, args, onFinished) {
    if (internal.procs[key]) return false
    const p = procComponent.createObject(root, Object.assign({ helper: root.helper }, props))
    internal.procs[key] = p
    internal.count++
    p.finished.connect(r => {
      if (internal.procs[key] !== p) return
      internal.forget(key, p)
      onFinished(r)
    })
    p.run(args)
    return true
  }

  // TERM and drop the run under `key`; its outcome is swallowed (no
  // onFinished). False when nothing runs under it.
  function cancel(key) {
    const p = internal.procs[key]
    if (!p) return false
    p.cancel()
    if (internal.procs[key] === p) internal.forget(key, p)
    return true
  }

  // TERM the run under `key` but still report its outcome (the helper
  // answers with error.code "terminated").
  function terminate(key) {
    const p = internal.procs[key]
    if (p) p.terminate()
  }

  QtObject {
    id: internal
    property var procs: Object.create(null)
    property int count: 0

    function forget(key, p) {
      delete internal.procs[key]
      internal.count--
      p.destroy()
    }
  }

  Component {
    id: procComponent
    HelperProcess {}
  }
}
