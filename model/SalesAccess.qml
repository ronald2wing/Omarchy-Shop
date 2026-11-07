pragma ComponentBehavior: Bound
import QtQuick
import "../js/config.mjs" as Config
import "../js/results.mjs" as Results

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
    return procs.has(domain)
  }

  // Any store's grant (Preflight.requireResetIdle).
  function grantingAny() {
    return procs.count > 0
  }

  function grant(domain, origin) {
    if (procs.has(domain)) return Results.storeBusy("grant")
    // Fails closed: only an explicit "panel" may relabel the store.
    const o = origin === "panel" ? "panel" : "ipc"
    procs.run(domain, {}, ["--store=" + domain], r => internal.done(domain, r, o))
    internal.revision++
    return Results.started()
  }

  function cancel(domain) {
    if (procs.cancel(domain)) internal.revision++
  }

  QtObject {
    id: internal
    property int revision: 0

    function done(domain, r, origin) {
      internal.revision++
      if (r.ok) {
        // The shop name the grant verified ({ shop { name } }).
        const raw = typeof r.name === "string" ? r.name : ""
        const name = Config.cleanRemoteLabel(raw)
        root.finished(domain, { ok: true, name: name, origin: origin })
      } else {
        root.finished(domain, Results.refused(Results.fromHelper(r.error)))
      }
    }
  }

  // One grant per store.
  HelperPool {
    id: procs
    helper: "grant-sales-access"
  }
}
