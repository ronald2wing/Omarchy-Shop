pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../js/config.mjs" as Config
import "../js/errors.mjs" as Errors
import "../js/urls.mjs" as Urls

// ~/.config/shop/config.json (v2 only). Loading never writes: the file is
// written only by a user mutation, only after prepare-state has made the
// directories, and never while the file is unreadable or from an older Shop.
Item {
  id: root

  // Set by the Service once prepare-state has succeeded; writes wait for it.
  property bool prepared: false
  required property string home
  readonly property string path: root.home + Urls.CONFIG_REL

  // The normalized config (valid stores only), or an empty v2 config.
  readonly property var config: internal.config
  // Its valid stores, in order.
  readonly property var stores: internal.config.stores
  // The service tunables: { pollSeconds, alerts: {notify, sound}, bar: {display} }.
  readonly property var settings: ({ pollSeconds: internal.config.pollSeconds, alerts: internal.config.alerts, bar: internal.config.bar })
  readonly property var invalidStores: internal.invalidStores
  // {code: "config_invalid"|"config_unsupported", message} or null.
  readonly property var configError: internal.configError
  // {code: "config_write_failed", message} or null.
  readonly property var configWriteError: internal.configWriteError
  // The file has been read (or found missing) at least once.
  readonly property bool loaded: internal.loaded

  // The config entry for a domain, or null.
  function store(domain) {
    return Config.findStore(internal.config, String(domain || ""))
  }

  function domains() {
    return internal.config.stores.map(s => s.domain)
  }

  // Apply fn(config) -> {config, error, ...}; returns that result with ok.
  // Refused while the file is unreadable or unsupported. A refused change
  // is fn's {error} return (invalid_patch and the like, from js/config.mjs);
  // fn throwing is a bug, logged and returned as internal_error.
  function mutate(fn) {
    if (internal.configError) return Errors.configInvalid(internal.configError)
    if (!internal.loaded) return Errors.configUnavailable("config.json hasn't loaded yet")
    if (internal.resetting) return Errors.configBusy("config.json is being reset")
    if (internal.missingHold) return Errors.configBusy("config.json is being replaced")
    let r = null
    try { r = fn(internal.config) } catch (e) {
      console.log("shop: config change failed: " + String(e))
      return Errors.internalError(String(e).substring(0, 200))
    }
    if (r.error) return Object.assign({ ok: false }, r)
    internal.config = r.config
    internal.configWriteError = null
    internal.writePending = true
    internal.flush()
    return Object.assign({ ok: true }, r)
  }

  // Keep the unreadable or old file as config.json.old and start from an
  // empty v2 config. Reached only from the panel's confirmation dialog.
  function resetConfig() {
    if (!root.prepared) return Errors.configWriteFailed("Shop's folders aren't ready yet")
    if (internal.resetting) return Errors.configBusy("Already resetting")
    // Reset is for an unreadable or unsupported file. One that reads again
    // (fixed while the dialog was open) is kept: the user already has a
    // working config, so there is nothing to do.
    if (internal.loaded && internal.configError === null) return { ok: true, skipped: true }
    internal.resetting = true
    internal.configWriteError = null
    if (internal.rawText !== null && internal.rawText.trim() !== "") {
      // FileView skips a setText equal to its buffer and then reports
      // nothing; a second Reset of the same file would wait forever. oldFile
      // never loads, so its buffer is whatever was last passed to setText.
      let t = internal.rawText
      if (t === internal.oldFileText) t += "\n"
      internal.oldFileText = t
      watchdog.restart()
      oldFile.setText(t)
    } else internal.finishReset()
    return Errors.ok()
  }

  function dismissWriteError() {
    internal.configWriteError = null
  }

  onPreparedChanged: { if (root.prepared) internal.flush() }

  QtObject {
    id: internal
    property var config: Config.emptyConfig()
    property var invalidStores: []
    property var configError: null
    property var configWriteError: null
    property bool loaded: false
    // The file's text as last read or written; null when missing/unknown.
    property var rawText: null
    // The config last known to be on disk (restored on a failed save).
    property var lastGood: Config.emptyConfig()
    property bool writePending: false
    property bool writing: false
    property var inFlightText: null
    property var inFlightConfig: null
    property bool resetting: false
    // The text last passed to oldFile.setText (its buffer).
    property var oldFileText: null
    // config.json vanished after a good load: an editor or tool saving by
    // rename leaves a short gap. The known config stays (nothing is
    // forgotten, no running job is stopped) and writes wait until the
    // file is back or a re-check still finds it missing.
    property bool missingHold: false

    function endMissingHold() {
      internal.missingHold = false
      missingRecheck.stop()
    }

    // The outcome of a load (or a reset): the file's text, its error, its
    // invalid stores and the config Shop uses; the file counts as loaded.
    function adopt(o) {
      internal.rawText = o.rawText
      internal.configError = o.configError
      internal.invalidStores = o.invalidStores
      internal.config = o.config
      internal.loaded = true
    }

    function apply(text) {
      const r = Config.normalizeConfig(text)
      if (!r.error) internal.lastGood = r.config
      internal.adopt({ rawText: text, configError: r.error, invalidStores: r.error ? [] : r.invalidStores, config: r.config })
    }

    function flush() {
      if (!root.prepared || internal.writing || !internal.writePending || internal.configError || internal.missingHold) return
      internal.writePending = false
      let text = Config.serializeConfig(internal.config, internal.rawText)
      if (text === internal.rawText) return
      // FileView skips a setText equal to its buffer (which still holds the
      // text of a failed save) and emits neither saved nor saveFailed, so
      // writing would never clear. A trailing newline keeps the JSON valid
      // and forces a real write.
      if (file.text() === text) text += "\n"
      internal.writing = true
      internal.inFlightText = text
      internal.inFlightConfig = internal.config
      watchdog.restart()
      file.setText(text)
    }

    // The next queued write, started once Quickshell is done with the
    // save that just reported (see onSaved).
    function flushNext() {
      internal.writing = false
      internal.flush()
    }

    function failWrite(message) {
      internal.writing = false
      internal.writePending = false
      internal.config = internal.lastGood
      internal.configWriteError = Errors.configWriteFailed(message).error
    }

    function finishReset() {
      internal.endMissingHold()
      internal.resetting = false
      internal.adopt({ rawText: null, configError: null, invalidStores: [], config: Config.emptyConfig() })
      internal.writePending = true
      internal.flush()
    }
  }

  FileView {
    id: file
    path: root.path
    atomicWrites: true
    watchChanges: true
    printErrors: false
    // During our own write the save itself reports back; reloading then
    // would drop the write operation.
    onFileChanged: { if (!internal.writing) file.reload() }
    onLoaded: {
      const text = file.text()
      const held = internal.missingHold
      internal.endMissingHold()
      // Our own write coming back through the watcher (or the same text
      // written back after a rename-style save).
      if (held && text === internal.rawText) { Qt.callLater(internal.flush); return }
      if (internal.loaded && text === internal.rawText) return
      if (internal.writing) return
      internal.apply(text)
    }
    onLoadFailed: (error) => {
      if (internal.writing) return
      if (error === FileViewError.FileNotFound) {
        // A first run (no file yet), or still missing at the re-check:
        // the config really is empty.
        if (!internal.loaded || internal.missingHold || internal.rawText === null) {
          internal.endMissingHold()
          internal.apply(null)
          return
        }
        internal.missingHold = true
        missingRecheck.restart()
        return
      }
      internal.endMissingHold()
      internal.adopt({
        rawText: null,
        configError: Errors.error("config_invalid", "config.json couldn't be read (" + FileViewError.toString(error) + ")"),
        invalidStores: [],
        config: Config.emptyConfig()
      })
    }
    onSaved: {
      const late = !internal.writing
      if (!internal.resetting) watchdog.stop()
      internal.rawText = internal.inFlightText
      internal.lastGood = internal.inFlightConfig
      const r = Config.normalizeConfig(internal.rawText)
      internal.invalidStores = r.error ? [] : r.invalidStores
      // A save that reports after the watchdog gave up: what is on disk is
      // known again, but the reverted config stays until the next edit.
      if (late) return
      // A setText from inside saved (or loaded) is mishandled by Quickshell's
      // FileView: it reports saved for the new write at once, before the
      // file is written, and then drops the real result. A reload in that
      // window read the previous text and applied it, losing the edit. The
      // queued write starts on the next turn, and `writing` stays set until
      // then so the watcher's reload still waits.
      if (internal.writePending) Qt.callLater(internal.flushNext)
      else internal.writing = false
    }
    onSaveFailed: (error) => {
      if (!internal.resetting) watchdog.stop()
      internal.failWrite(FileViewError.toString(error))
    }
  }

  // Backstop: a write that reports neither saved nor saveFailed must not
  // leave writing/resetting stuck (every later edit would be dropped).
  Timer {
    id: watchdog
    interval: 10000
    repeat: false
    onTriggered: {
      if (internal.resetting) {
        internal.resetting = false
        internal.configWriteError = Errors.configWriteFailed("Couldn't keep config.json.old (no response)").error
      }
      if (internal.writing) internal.failWrite("config.json save didn't finish")
    }
  }

  // A rename-style save recreates config.json well inside this; if it is
  // still missing, it was deleted and the config is empty.
  Timer {
    id: missingRecheck
    interval: 1500
    repeat: false
    onTriggered: file.reload()
  }

  // Where resetConfig() keeps the previous file.
  FileView {
    id: oldFile
    path: root.path + ".old"
    preload: false
    blockLoading: false
    atomicWrites: true
    printErrors: false
    onSaved: {
      if (!internal.resetting) return
      watchdog.stop()
      internal.finishReset()
    }
    onSaveFailed: (error) => {
      if (!internal.resetting) return
      watchdog.stop()
      internal.resetting = false
      internal.configWriteError = Errors.configWriteFailed("Couldn't keep config.json.old (" + FileViewError.toString(error) + ")").error
    }
  }
}
