pragma ComponentBehavior: Bound
import QtQuick
import "../js/results.mjs" as Results

// Shop's private state and config directories (helpers/prepare-state):
// nothing writes config.json or cache.json before `ready`.
Item {
  readonly property bool ready: internal.ready
  // {code, message} when prepare-state failed (e.g. unsafe_state_dir).
  readonly property var error: internal.error

  // Runs prepare-state unless a run is in flight.
  function prepare() {
    if (prepareProc.running) return
    prepareProc.run([])
  }

  QtObject {
    id: internal
    property bool ready: false
    property var error: null
  }

  HelperProcess {
    id: prepareProc
    helper: "prepare-state"
    onFinished: (r) => {
      if (r.ok) {
        internal.error = null
        internal.ready = true
      } else {
        internal.error = Results.fromHelper(r.error)
      }
    }
  }
}
