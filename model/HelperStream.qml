pragma ComponentBehavior: Bound
import QtQuick
import "../js/timing.mjs" as Timing

// Runs one streaming helper that prints JSON lines (discover-stores,
// preview-theme) on top of HelperProcess's streaming mode. Each parsed
// object line fires event(obj); the exit fires ended(exitCode, signal) once,
// unless cancel() came first. stop() closes stdin first (the helper's stop
// request), then SIGTERM, then SIGKILL after HelperProcess's stopGrace (its
// kill and stop graces are the only place those values live).
Item {
  id: root

  required property string helper
  // From js/timing.mjs: H + 5 s, or 0 = no deadline (preview-theme runs
  // until stopped).
  property int deadline: Timing.deadlineMs(root.helper)
  // Keep a pipe on stdin so closing it can ask the helper to stop.
  property bool stdinPipe: false
  // Longer lines are dropped: the helper's own line cap from
  // js/timing.mjs (discover-stores' final line can carry 500 stores, 2 MiB).
  property int maxLineBytes: Timing.cap(root.helper)

  signal event(var obj)
  // exitCode is -1 for a failed launch, 124 after the QML deadline; signal
  // (killSignal) is the signal that killed the helper, else 0 (Os.exitToError
  // takes both).
  signal ended(int exitCode, int killSignal)

  // False while a previous process is still exiting (an owner that reuses
  // its stream, like Discovery, checks it).
  function start(args) {
    if (proc.busy) return false
    proc.run(args)
    return true
  }

  // Ask the helper to stop; ended() still fires.
  function stop() {
    proc.stop()
  }

  // As stop(), but nothing fires afterwards.
  function cancel() {
    proc.cancel()
  }

  HelperProcess {
    id: proc
    helper: root.helper
    streaming: true
    deadline: root.deadline
    stdinPipe: root.stdinPipe
    maxLineBytes: root.maxLineBytes
    onLine: (text) => {
      let obj = null
      try { obj = JSON.parse(text) } catch (e) { return }
      if (obj === null || typeof obj !== "object" || Array.isArray(obj)) return
      root.event(obj)
    }
    onFinished: (r) => root.ended(r.timedOut ? 124 : r.exitCode, r.timedOut ? 0 : r.signal)
  }
}
