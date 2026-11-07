// runner: quickshell
import QtQuick
import Quickshell
import "shop/tests/qml"

// The panel's Add view (PanelHarness): config.json unreadable, the filter's
// keyboard, and what Enter, the footer and the sheet offer on each row.
// Run alone: tests/run tests/qml/panel_add_smoke.qml
ShellRoot {
  id: root

  PanelHarness { id: h }

  Smoke {
    id: smoke
    name: "PANEL_ADD"
    steps: [
      function() {
        // 1. config.json unreadable: the discovered rows hide, and the
        //    banner's keys are the only ones.
        h.publishBroken({ discovery: { status: "done", stores: [{ domain: h.acme, name: "Acme" }, { domain: h.beta, name: "Beta" }], truncated: false, finishedAt: Date.now() } })
        h.panel.navigate({ view: "add" })
      },
      function() {
        smoke.check(h.panel.viewName === "add" && h.footerIs(["hints.broken"]), "Add with a broken config, got " + h.footerKeys())
        smoke.check(h.panel.keySheetItem.viewRows.length === 0, "broken Add sheet has no view rows: " + JSON.stringify(h.sheetRows()))
        smoke.check(h.panel.view.configInvalid === true && h.panel.view.discoveredDomains.length === 2, "the discovered rows are hidden, not offered as dead rows")
        var before = h.service.calls.length
        h.panel.view.activate()
        h.panel.view.moveCursor(0, 1)
        smoke.check(h.service.calls.length === before && h.panel.view.cursorIndex === 0, "Enter and j do nothing on the hidden list")
        smoke.check(h.service.calls.indexOf("discoverStores") < 0, "no discovery while the config is unusable")
        // 2. config.json breaks while the filter has the keyboard: the
        //    hidden filter lets go and drops its text.
        h.publishAcme()
      },
      function() {
        h.panel.view.focusFilter()
        if (h.focused) h.focused.text = "ac"
        smoke.check(h.panel.view.filterText === "ac" && h.panel.inputFocused, "Add: the filter takes the keyboard")
        h.publishBroken()
        smoke.check(!h.isTextInput(h.focused) && h.panel.inputFocused === false && h.panel.view.filterText === "", "Add broken: the hidden filter let go and dropped its text, focus " + h.focused + " filter " + h.panel.view.filterText)
        // 3. The footer and the sheet say what Enter does on the cursor's
        //    row (open a store already in Shop, add, or open the domain
        //    field).
        h.publish({ stores: [h.acmeLinked()],
                    discovery: { status: "done", stores: [{ domain: h.acme, name: "Acme" }, { domain: "fresh.myshopify.com", name: "Fresh" }], finishedAt: Date.now() } })
        h.panel.navigate({ view: "add" })
      },
      function() {
        h.panel.view.cursorId = h.acme
        smoke.check(h.footerIs(["hints.open", "hints.filter", "hints.add.byDomain"]) && h.sheetText("Enter") === h.t("keys.viewStore"), "Add on a store in Shop: Enter opens it, got " + h.footerKeys() + " " + h.sheetText("Enter"))
        h.panel.view.cursorId = "fresh.myshopify.com"
        smoke.check(h.footerIs(["hints.add", "hints.filter", "hints.add.byDomain"]) && h.sheetText("Enter") === h.t("keys.addSelected") && h.sheetKeys().indexOf("r") >= 0, "Add on a new store: Enter adds, r listed, got " + h.footerKeys() + " " + h.sheetKeys().join(","))
        h.panel.view.cursorId = h.panel.view.manualId
        var mk = h.sheetKeys()
        smoke.check(h.footerIs(["hints.add.byDomain", "hints.filter"]) && h.sheetText("Enter") === h.t("keys.addByDomain") && mk.indexOf("m") < 0, "Add on the manual row: Enter opens the domain field, no m, got " + h.footerKeys() + " " + mk.join(","))
        // 4. No CLI, nothing discovered: the manual row is the only row, and
        //    r (refused without the CLI) is not offered.
        h.publish({ stores: [], cli: h.cliMissing })
      },
      function() {
        var nk = h.sheetKeys()
        smoke.check(h.footerIs(["hints.add.byDomain"]) && h.sheetText("Enter") === h.t("keys.addByDomain") && nk.indexOf("r") < 0 && nk.indexOf("/") < 0, "Add without the CLI: Enter opens the domain field only, got " + h.footerKeys() + " " + nk.join(","))
        smoke.check(h.footerKeys()[0] === "hints.add.byDomain", "Add without the CLI: the footer names what Enter does first, got " + h.footerKeys())
      }
    ]
  }
}
