pragma ComponentBehavior: Bound
import QtQuick
import "../js/config.mjs" as Config
import "../js/errors.mjs" as Errors
import "../js/os.mjs" as Os
import "../js/snapshot.mjs" as Snapshot
import "../js/text.mjs" as TextUtil

// The discover-stores stream: stores on the account (all organizations) plus
// stores with a store-auth session, merged by the helper.
Item {
  id: root

  // { status: idle|running|done|failed, stores: [{domain, name}],
  //   truncated, finishedAt, error } (Snapshot.emptyDiscovery() until the
  //   first run). The account session goes to Account (sessionKnown).
  readonly property var result: internal.result

  // The helper learned the account session state. startedAt: when this
  // run began (Account drops a report older than its last sign-in/out).
  signal sessionKnown(string session, real startedAt)

  function discover() {
    if (!stream.start([])) return false
    internal.gotDone = false
    internal.startedAt = Date.now()
    internal.set({ status: "running", error: null })
    return true
  }

  function cancel() {
    stream.cancel()
    if (internal.result.status === "running") internal.set({ status: "idle" })
  }

  QtObject {
    id: internal
    property var result: Snapshot.emptyDiscovery()
    property bool gotDone: false
    property real startedAt: 0

    function set(patch) {
      internal.result = Object.assign({}, internal.result, patch)
    }

    // The helper owns domain validity, uniqueness and the 500-row cap; the
    // name is cut to a config label (a partial row has none: its subdomain).
    function cleanRows(list) {
      return list.map(r => ({ domain: r.domain, name: Config.cleanRemoteLabel(r.name) || TextUtil.subdomainLabel(r.domain) }))
    }

    function onEvent(event) {
      // Arrays inside a `var` signal argument arrive as non-arrays (Os.plain).
      const obj = Os.plain(event)
      if (obj.event === "partial") {
        internal.set({ stores: internal.cleanRows(obj.stores) })
      } else if (obj.event === "account") {
        if (obj.status !== "unknown") root.sessionKnown(obj.status, internal.startedAt)
      } else if (obj.event === "done") {
        internal.gotDone = true
        if (obj.ok === true) {
          internal.set({ status: "done", stores: internal.cleanRows(obj.stores), truncated: obj.truncated === true, finishedAt: Date.now(), error: null })
        } else {
          const e = Errors.fromHelper(obj.error)
          internal.set({ status: "failed", finishedAt: Date.now(), error: e })
          if (e.code === "signed_out") root.sessionKnown("signed_out", internal.startedAt)
        }
      }
    }
  }

  HelperStream {
    id: stream
    helper: "discover-stores"
    onEvent: (obj) => internal.onEvent(obj)
    onEnded: (exitCode, killSignal) => {
      // The stream ended without its done event (deadline, crash, flood,
      // failed launch): exitToError is already the {code, message} pair.
      if (!internal.gotDone) internal.set({ status: "failed", finishedAt: Date.now(), error: Os.exitToError(exitCode, killSignal) })
    }
  }
}
