pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../js/sales.mjs" as Sales
import "../js/urls.mjs" as Urls

// ~/.local/state/shop/cache.json: the warm-start copy of each store's
// history, yesterday baseline and last-seen order. A file from another
// record version is ignored, never migrated. Writes are coalesced to one
// per 2 s and wait for prepare-state.
Item {
  id: root

  property bool prepared: false
  required property string home
  readonly property string path: root.home + Urls.STATE_REL + "/cache.json"
  readonly property bool loaded: internal.loaded

  // The cached record for a domain, or null.
  function entry(domain) {
    const s = internal.stores
    return Object.prototype.hasOwnProperty.call(s, domain) ? s[domain] : null
  }

  // Replace a domain's record and schedule a write.
  function put(domain, record) {
    const next = Object.assign(Object.create(null), internal.stores)
    next[domain] = record
    internal.stores = next
    internal.schedule()
  }

  // Drop one domain's record (no write if absent).
  function forget(domain) {
    root.retain(Object.keys(internal.stores).filter(d => d !== domain))
  }

  // Drop records for domains not in `domains`.
  function retain(domains) {
    const keep = Object.create(null)
    for (let i = 0; i < domains.length; i++) keep[domains[i]] = true
    const keys = Object.keys(internal.stores)
    let changed = false
    const next = Object.create(null)
    for (let i = 0; i < keys.length; i++) {
      if (keep[keys[i]]) next[keys[i]] = internal.stores[keys[i]]
      else changed = true
    }
    if (!changed) return
    internal.stores = next
    internal.schedule()
  }

  onPreparedChanged: { if (root.prepared && internal.dirty) writeTimer.restart() }

  QtObject {
    id: internal
    property var stores: Object.create(null)
    property bool loaded: false
    property bool dirty: false
    property var lastText: null

    function schedule() {
      internal.dirty = true
      if (root.prepared && !writeTimer.running) writeTimer.start()
    }

    function load(text) {
      let parsed = null
      try { parsed = JSON.parse(String(text || "")) } catch (e) { parsed = null }
      const stores = Object.create(null)
      if (parsed && typeof parsed === "object" && parsed.version === Sales.CACHE_VERSION && parsed.stores && typeof parsed.stores === "object" && !Array.isArray(parsed.stores)) {
        const keys = Object.keys(parsed.stores)
        for (let i = 0; i < keys.length && i < 500; i++) {
          const rec = parsed.stores[keys[i]]
          if (rec && typeof rec === "object" && !Array.isArray(rec)) stores[keys[i]] = rec
        }
      }
      internal.stores = stores
      internal.lastText = text
      internal.loaded = true
    }

    function write() {
      if (!root.prepared || !internal.dirty) return
      internal.dirty = false
      const plain = {}
      const keys = Object.keys(internal.stores)
      for (let i = 0; i < keys.length; i++) plain[keys[i]] = internal.stores[keys[i]]
      const text = JSON.stringify({ version: Sales.CACHE_VERSION, stores: plain }) + "\n"
      if (text === internal.lastText) return
      internal.lastText = text
      file.setText(text)
    }
  }

  Timer {
    id: writeTimer
    interval: 2000
    onTriggered: internal.write()
  }

  // Read once at startup; the cache is Shop's own file, so it is not watched.
  FileView {
    id: file
    path: root.path
    atomicWrites: true
    printErrors: false
    onLoaded: { if (!internal.loaded) internal.load(file.text()) }
    onLoadFailed: (error) => { if (!internal.loaded) internal.load("") }
    onSaveFailed: (error) => internal.lastText = null
  }
}
