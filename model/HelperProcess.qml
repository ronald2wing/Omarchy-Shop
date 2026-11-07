pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../js/errors.mjs" as Errors
import "../js/os.mjs" as Os
import "../js/timing.mjs" as Timing

// Runs one helper from helpers/ under a deadline, with a SIGTERM-first kill
// and a byte cap on what is buffered. Two modes:
// - result (default): the helper prints one JSON line; exactly one
//   finished(result) per run, none after cancel(). Owners drop a tracked
//   process only by cancel() + destroy(), so a handler never sees a stale one.
// - streaming: every stdout line fires line(text) as it arrives (bounded
//   by maxLineBytes); finished({exitCode, timedOut, signal}) fires once
//   at exit.
// HelperStream composes the streaming mode.
Item {
  id: root

  // The helper's file name under helpers/, e.g. "fetch-sales".
  required property string helper
  // fetch-sales' range (today|history|yesterday): its timing row.
  property string range: ""
  // QML backstop behind the helper's own deadline: helper H + 5 s, from
  // js/timing.mjs. 0 = none (preview-theme runs until stopped).
  property int deadline: Timing.deadlineMs(root.helper, root.range)
  // Longer than the helper's own TERM -> KILL grace plus its group reap, so
  // the helper reaps its children before QML has to SIGKILL it.
  property int killGrace: 5000
  // Grace after stop() before SIGKILL (8000 ms for preview).
  property int stopGrace: 8000
  // Bytes buffered from stdout before the run counts as output_too_large
  // (the helper's own cap is authoritative; this bounds QML's buffer).
  // It defaults to the helper's cap in js/timing.mjs; an unknown helper
  // gets 0, so any output fails closed as output_too_large. Streaming
  // ignores it.
  property int maxStdoutBytes: Timing.cap(root.helper, root.range)
  // Streaming mode and its line cap (longer lines are dropped).
  property bool streaming: false
  property int maxLineBytes: 65536
  // Keep a pipe on stdin so closing it can ask the helper to stop.
  property bool stdinPipe: false
  // A run is in flight or queued behind one that is exiting.
  readonly property bool running: internal.queued !== null || (internal.live && !internal.canceled)
  // A process was launched and has not exited yet (canceled or not).
  readonly property bool busy: internal.live

  // result mode: the helper's JSON object with exitCode added, or a
  // synthetic {ok:false, error:{code, message}} with code bad_response,
  // output_too_large, timeout, terminated (killed by a signal before it
  // printed a result) or failed_to_start.
  // streaming mode: { exitCode, timedOut, signal }.
  // signal: the signal that killed the helper (Qt's CrashExit, whose exit
  // code is the signal number), else 0.
  signal finished(var result)
  // streaming mode: one parsed-or-not stdout line.
  signal line(string text)

  // One run at a time: run() while one is in flight cancels it and starts
  // the new one once the old process has exited.
  function run(args) {
    const command = [internal.helperPath].concat(args)
    if (internal.live) {
      root.cancel()
      internal.queued = command
      return
    }
    internal.start(command)
  }

  // SIGTERM now, SIGKILL after killGrace; the outcome is swallowed.
  function cancel() {
    internal.canceled = true
    internal.queued = null
    internal.termThenKill(root.killGrace)
  }

  // SIGTERM now, SIGKILL after killGrace, but still report the outcome (the
  // helper answers a TERM with {"error":{"code":"terminated"}}).
  function terminate() {
    internal.termThenKill(root.killGrace)
  }

  // Ask a streaming helper to stop: EOF on stdin, SIGTERM, SIGKILL after
  // stopGrace. finished() still fires.
  function stop() {
    if (!internal.live) return
    termTimer.stop()
    internal.closeStdin()
    internal.termThenKill(root.stopGrace)
  }

  // Every helper's TERM on teardown lives here: the kill timer dies with
  // this object, so destruction can only SIGTERM; the helper's group
  // reaping and setpriv --pdeathsig cover the rest.
  Component.onDestruction: {
    internal.canceled = true
    internal.queued = null
    if (process.running) {
      internal.closeStdin()
      process.signal(Os.SIGTERM)
    }
  }

  QtObject {
    id: internal
    readonly property string helperPath: Os.fileUrlToPath(Qt.resolvedUrl("../helpers/" + root.helper))
    // A process was launched and its exit (or failed launch) is unhandled.
    property bool live: false
    property bool started: false
    property bool canceled: false
    property bool timedOut: false
    property bool overflowed: false
    property var queued: null
    property var chunks: []
    property int bytes: 0

    function closeStdin() {
      if (process.stdinEnabled) process.stdinEnabled = false
    }

    // SIGTERM the running helper and arm the SIGKILL backstop. Before the
    // process has started this does nothing; onStarted re-checks.
    function termThenKill(grace) {
      if (process.running || (internal.started && internal.live)) {
        process.signal(Os.SIGTERM)
        killTimer.interval = Math.max(1000, grace)
        killTimer.restart()
      }
    }

    function start(command) {
      internal.queued = null
      internal.canceled = false
      internal.timedOut = false
      internal.overflowed = false
      internal.started = false
      internal.chunks = []
      internal.bytes = 0
      internal.live = true
      killTimer.stop()
      termTimer.stop()
      if (root.deadline > 0) {
        termTimer.interval = Math.max(1000, root.deadline)
        termTimer.restart()
      }
      process.stdinEnabled = root.stdinPipe
      process.exec(command)
    }

    function ended(report) {
      termTimer.stop()
      killTimer.stop()
      internal.live = false
      if (internal.canceled) {
        if (internal.queued !== null) internal.start(internal.queued)
        return
      }
      report()
    }

    // An Errors builder's {ok: false, error} with the exit code beside it.
    function synthetic(result, exitCode) {
      result.exitCode = exitCode
      return result
    }

    function append(text) {
      if (root.streaming) {
        if (internal.canceled || text.length === 0 || Os.utf8ByteLength(text) > root.maxLineBytes) return
        root.line(text)
        return
      }
      if (internal.overflowed) return
      internal.bytes += Os.utf8ByteLength(text) + 1
      if (internal.bytes > root.maxStdoutBytes) {
        internal.overflowed = true
        internal.chunks = []
        internal.termThenKill(root.killGrace)
        return
      }
      internal.chunks.push(text)
    }

    function exited(exitCode, killSignal) {
      if (root.streaming) {
        root.finished({ exitCode: exitCode, timedOut: internal.timedOut, signal: killSignal })
        return
      }
      if (internal.timedOut) { root.finished(internal.synthetic(Errors.timeout("Shop helper " + root.helper + " timed out"), exitCode)); return }
      if (internal.overflowed) { root.finished(internal.synthetic(Errors.outputTooLarge("Shop helper output exceeded " + root.maxStdoutBytes + " bytes"), exitCode)); return }
      const lines = internal.chunks.filter(l => l.trim() !== "")
      internal.chunks = []
      const text = lines.length > 0 ? lines[lines.length - 1] : ""
      let parsed = null
      try { parsed = JSON.parse(text) } catch (e) { parsed = null }
      if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
        // Killed from outside (OOM killer, pkill -9) or crashed: not
        // "Unexpected response", and not bad_response's long backoff.
        if (killSignal !== 0) { root.finished(internal.synthetic(Errors.terminated("Shop helper " + root.helper + " was killed by signal " + killSignal), exitCode)); return }
        root.finished(internal.synthetic(Errors.badResponse("Shop helper " + root.helper + " exited " + exitCode + " without a result"), exitCode))
        return
      }
      if (parsed.ok !== true && (!parsed.error || typeof parsed.error.code !== "string")) {
        parsed.ok = false
        parsed.error = Errors.badResponse("Shop helper " + root.helper + " gave no error code").error
      }
      if (parsed.ok === true && exitCode !== 0) {
        parsed.ok = false
        parsed.error = Errors.badResponse("Shop helper " + root.helper + " exited " + exitCode).error
      }
      parsed.exitCode = exitCode
      root.finished(parsed)
    }
  }

  Process {
    id: process
    stdout: SplitParser {
      onRead: (text) => internal.append(text)
    }
    onStarted: {
      internal.started = true
      if (internal.canceled) internal.termThenKill(root.killGrace)
    }
    // On a CrashExit (exitStatus 1) Qt's exit code is the signal number.
    onExited: (exitCode, exitStatus) => internal.ended(() => internal.exited(exitCode, exitStatus === 1 ? exitCode : 0))
    // A failed launch reports neither started nor exited, only running
    // turning false.
    onRunningChanged: {
      if (process.running || !internal.live || internal.started) return
      internal.ended(() => {
        if (root.streaming) root.finished({ exitCode: -1, timedOut: false, signal: 0 })
        else root.finished(internal.synthetic(Errors.failedToStart("Couldn't start Shop helper " + root.helper), -1))
      })
    }
  }

  Timer {
    id: termTimer
    onTriggered: {
      internal.timedOut = true
      internal.termThenKill(root.killGrace)
    }
  }

  Timer {
    id: killTimer
    onTriggered: { if (process.running) process.signal(Os.SIGKILL) }
  }
}
