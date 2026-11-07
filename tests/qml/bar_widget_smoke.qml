// runner: quickshell
import QtQuick
import Quickshell
import Quickshell.Io
import "shop/tests/qml"

// BarWidget's contract with the real Service (fake CLI, throwaway HOME
// built by tests/qml/fake-home.sh). BarWidget itself needs a PanelWindow
// backend, which offscreen Quickshell lacks, so this reads its source: every
// handler in its `Connections { target: root.service }` must name a signal
// the Service has (a stale name there is silently dead, and the pills stop
// following showInBar or labels and an IPC request* never opens its
// dialog). Then snapshotChanged must fire for what the widget tracks: a
// showInBar change, a rename and an IPC request* (pendingConfirm).
// Run alone: tests/run tests/qml/bar_widget_smoke.qml
ShellRoot {
  id: root

  readonly property var domains: ["acme.myshopify.com", "beta.myshopify.com", "gamma.myshopify.com"]
  property var service: null
  property var handlers: []
  property int snapshots: 0

  // The handler names (onFooChanged -> fooChanged) in BarWidget's service
  // Connections block.
  function serviceHandlers(src) {
    const start = src.indexOf("target: root.service")
    if (start < 0) return []
    const end = src.indexOf("\n  }\n", start)
    const block = src.slice(start, end < 0 ? src.length : end)
    const out = []
    const re = /function on([A-Z]\w*)\s*\(/g
    let m
    while ((m = re.exec(block)) !== null) out.push(m[1].charAt(0).toLowerCase() + m[1].slice(1))
    return out
  }

  FileView {
    id: widgetSource
    path: Quickshell.env("HOME") + "/qs/shop/BarWidget.qml"
    blockLoading: true
    printErrors: false
  }

  Connections {
    target: root.service
    function onSnapshotChanged() { root.snapshots++ }
  }

  Smoke {
    id: smoke
    name: "BAR_WIDGET"
    steps: [
      function() {
        const c = Qt.createComponent(Qt.resolvedUrl("shop/Service.qml"), Component.PreferSynchronous)
        if (c.status !== Component.Ready) {
          smoke.check(false, "cannot load shop/Service.qml: " + c.errorString())
          smoke.finish()
          return
        }
        root.service = c.createObject(root, { manifest: { id: "shop", version: "9.9.9" } })
        root.handlers = root.serviceHandlers(widgetSource.text())
        smoke.check(root.handlers.indexOf("snapshotChanged") >= 0, "BarWidget follows the snapshot, handlers " + JSON.stringify(root.handlers))
        for (let i = 0; i < root.handlers.length; i++)
          smoke.check(typeof root.service[root.handlers[i]] === "function", "BarWidget handles " + root.handlers[i] + ", which Service has no signal for")
      },
      smoke.waitFor(() => root.service.storeOrder.length === 3 && !!root.service.snapshot.stores[root.domains[2]], "the three stores of config.json"),
      function() {
        root.snapshots = 0
        const hide = root.service.updateStore(root.domains[2], JSON.stringify({ showInBar: false }))
        smoke.check(hide.ok === true, "updateStore showInBar:false, got " + JSON.stringify(hide))
      },
      smoke.waitFor(() => root.service.snapshot.stores[root.domains[2]].showInBar === false, "the snapshot hides the store from the bar"),
      function() {
        smoke.check(root.snapshots > 0, "showInBar:false fires snapshotChanged")
        root.snapshots = 0
        const rename = root.service.updateStore(root.domains[0], JSON.stringify({ label: "Zed Store" }))
        smoke.check(rename.ok === true, "updateStore label, got " + JSON.stringify(rename))
      },
      smoke.waitFor(() => root.service.snapshot.stores[root.domains[0]].label === "Zed Store", "the snapshot carries the new label"),
      function() {
        smoke.check(root.snapshots > 0, "a rename fires snapshotChanged")
        root.snapshots = 0
        const r = root.service.requestPull(root.domains[1])
        smoke.check(r.ok === true, "IPC requestPull, got " + JSON.stringify(r))
      },
      smoke.waitFor(() => !!root.service.snapshot.pendingConfirm, "requestPull publishes pendingConfirm"),
      function() {
        const pc = root.service.snapshot.pendingConfirm
        smoke.check(!!pc.id, "pendingConfirm has an id, got " + JSON.stringify(pc))
        smoke.check(root.snapshots > 0, "an IPC request fires snapshotChanged")
        root.service.resolvePending(pc.id, false)
      }
    ]
  }
}
