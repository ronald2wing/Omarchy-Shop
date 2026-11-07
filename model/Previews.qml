pragma ComponentBehavior: Bound
import QtQuick
import "../js/errors.mjs" as Errors
import "../js/os.mjs" as Os
import "../js/urls.mjs" as Urls

// One preview-theme stream per store, on the development theme only. A
// preview started from the panel opens in the browser on its first ready.
// The status is "stopping" from a stop or the helper's exited line until
// the stream has ended (the helper holds the store's lock until then), and
// only then stopped or failed.
Item {
  id: root

  readonly property int revision: internal.revision

  // { status: stopped|starting|ready|stopping|failed, url, error }
  function stateFor(domain) {
    return internal.states[domain] || null
  }

  function isRunning(domain) {
    return !!internal.streams[domain]
  }

  // Any store's preview, starting to stopping (Preflight.requireThemesIdle).
  function runningAny() {
    return Object.keys(internal.streams).length > 0
  }

  function start(domain, folder, autoOpen) {
    const s = streamComponent.createObject(root, {})
    internal.streams[domain] = s
    internal.autoOpen[domain] = !!autoOpen
    internal.set(domain, { status: "starting", url: "", error: null })
    s.event.connect(obj => internal.onEvent(domain, obj))
    s.ended.connect((code, killSignal) => internal.onEnded(domain, s, code, killSignal))
    s.start(["--store=" + domain, "--folder=" + folder])
  }

  function stop(domain) {
    const s = internal.streams[domain]
    if (!s) return
    delete internal.autoOpen[domain]
    internal.set(domain, { status: "stopping", url: internal.states[domain].url, error: null })
    s.stop()
  }

  function forget(domain) {
    const s = internal.streams[domain]
    if (s) {
      s.cancel()
      s.destroy()
      delete internal.streams[domain]
    }
    delete internal.states[domain]
    delete internal.autoOpen[domain]
    delete internal.exits[domain]
    internal.revision++
  }

  QtObject {
    id: internal
    property var states: Object.create(null)
    property var streams: Object.create(null)
    // domain -> open the browser on the first ready (cleared by it, and by
    // an exit, stop or forget, so a late ready never opens it).
    property var autoOpen: Object.create(null)
    // domain -> the outcome the helper's exited line reported ({error} or
    // null), applied once the stream ends.
    property var exits: Object.create(null)
    property int revision: 0

    function set(domain, s) {
      internal.states[domain] = s
      internal.revision++
    }

    function onEvent(domain, obj) {
      const cur = internal.states[domain]
      if (obj.event === "ready") {
        const url = typeof obj.url === "string" ? obj.url : ""
        if (!url.startsWith("http://127.0.0.1:") || !Urls.isSafeOpenUrl(url, domain, "")) return
        const open = !!internal.autoOpen[domain]
        delete internal.autoOpen[domain]
        internal.set(domain, { status: "ready", url: url, error: null })
        if (open) Qt.openUrlExternally(url)
      } else if (obj.event === "exited") {
        delete internal.autoOpen[domain]
        // A failure the user did not ask for (a stop's own exit is no failure).
        const failed = obj.ok !== true && cur.status !== "stopping"
        internal.exits[domain] = { error: failed ? Errors.fromHelper(obj.error) : null }
        internal.set(domain, { status: "stopping", url: "", error: null })
      }
    }

    function onEnded(domain, stream, code, killSignal) {
      const exit = internal.exits[domain]
      delete internal.exits[domain]
      delete internal.streams[domain]
      delete internal.autoOpen[domain]
      stream.destroy()
      const cur = internal.states[domain]
      let error = null
      // Ended without an exited line while it ran: exitToError is already
      // the {code, message} pair.
      if (cur.status === "starting" || cur.status === "ready") error = Os.exitToError(code, killSignal)
      else if (exit) error = exit.error
      internal.set(domain, { status: error ? "failed" : "stopped", url: "", error: error })
    }
  }

  Component {
    id: streamComponent
    HelperStream {
      helper: "preview-theme"
      stdinPipe: true
    }
  }
}
