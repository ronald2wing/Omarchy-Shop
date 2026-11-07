pragma ComponentBehavior: Bound
import QtQuick
import "../js/config.mjs" as Config
import "../js/errors.mjs" as Errors

// The browser grant of a store's sales access (helpers/grant-sales-access),
// one at a time per store. SalesData keeps the resulting access state.
Item {
  id: root

  // Bumped when a grant starts or ends.
  readonly property int revision: internal.revision

  // result: { ok: true, name (null when Shopify gave none), origin (the
  // grant's: "panel" | "ipc") } or { ok: false, error: {code, message} }.
  signal finished(string domain, var result)

  function isGranting(domain) {
    return !!internal.procs[domain]
  }

  // Any store's grant (Preflight.requireResetIdle).
  function grantingAny() {
    return Object.keys(internal.procs).length > 0
  }

  function grant(domain, origin) {
    if (internal.procs[domain]) return Errors.storeBusy("grant")
    const o = origin === "ipc" ? "ipc" : "panel"
    const p = procComponent.createObject(root, {})
    internal.procs[domain] = p
    internal.revision++
    p.finished.connect(r => internal.done(domain, p, r, o))
    p.run(["--store=" + domain])
    return Errors.started()
  }

  function cancel(domain) {
    const p = internal.procs[domain]
    if (!p) return
    p.cancel()
    p.destroy()
    delete internal.procs[domain]
    internal.revision++
  }

  QtObject {
    id: internal
    property var procs: Object.create(null)
    property int revision: 0

    function done(domain, p, r, origin) {
      delete internal.procs[domain]
      p.destroy()
      internal.revision++
      if (r.ok) {
        // The shop name the grant verified ({ shop { name } }).
        const raw = typeof r.name === "string" ? r.name : ""
        const name = Config.cleanRemoteLabel(raw)
        root.finished(domain, { ok: true, name: name, origin: origin })
      } else {
        root.finished(domain, { ok: false, error: Errors.fromHelper(r.error) })
      }
    }
  }

  Component {
    id: procComponent
    HelperProcess {
      helper: "grant-sales-access"
    }
  }
}
