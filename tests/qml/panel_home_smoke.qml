// runner: quickshell
import QtQuick
import Quickshell
import "shop/tests/qml"

// The panel's Home view (PanelHarness): first run, config.json unreadable,
// the hero's totals, the cursor, Reset config and a failed CLI check.
// Run alone: tests/run tests/qml/panel_home_smoke.qml
ShellRoot {
  id: root

  PanelHarness { id: h }

  Smoke {
    id: smoke
    name: "PANEL_HOME"
    steps: [
      function() {
        // 1. First run: no stores. The footer and the sheet talk about the
        //    checklist, not about store rows.
        h.publish({ stores: [] })
      },
      function() {
        smoke.check(h.panel.viewName === "home" && h.panel.view.firstRun === true, "first run shows the checklist")
        smoke.check(h.footerIs(["hints.run.step", "hints.choose", "hints.settings"]), "first-run footer, got " + h.footerKeys())
        var keys = h.sheetKeys()
        smoke.check(h.sheetText("Enter") === h.t("keys.runStep"), "setup sheet: Enter runs the step, got " + h.sheetText("Enter"))
        smoke.check(keys.indexOf("Ctrl+j / Ctrl+k") < 0 && keys.indexOf("x / Delete") < 0 && keys.indexOf("o") < 0, "setup sheet lists no store-row keys: " + keys.join(","))
        smoke.check(keys.indexOf("a") >= 0 && keys.indexOf("s") >= 0, "setup sheet keeps a and s")
        // 2. config.json unreadable: the banner's i / Shift+i are the keys.
        h.publishBroken()
      },
      function() {
        smoke.check(h.footerIs(["hints.run", "hints.choose", "hints.broken"]), "config-broken footer, got " + h.footerKeys())
        var keys = h.sheetKeys()
        smoke.check(h.sheetText("Enter") === h.t("keys.runButton"), "broken sheet: Enter runs the button")
        smoke.check(keys.indexOf("Ctrl+j / Ctrl+k") < 0 && keys.indexOf("x / Delete") < 0 && keys.indexOf("e") < 0, "broken sheet lists no store-row keys: " + keys.join(","))
        smoke.check(h.sheetKeys("panel").indexOf("i / Shift+i") >= 0, "broken sheet names the banner's i / Shift+i, got " + JSON.stringify(h.sheetRows("panel")))
        // 3. `a` on a config-broken Home opens Add, never the reset dialog.
        h.panel.view.textKey("a")
      },
      function() {
        smoke.check(h.panel.viewName === "add" && h.panel.confirmFlow.opened === false, "a opens Add with no dialog, got " + h.panel.viewName + " dialog " + h.panel.confirmFlow.opened)
        // 4. No store has sales access: nothing can be totalled.
        var sales = {}
        sales[h.acme] = h.accessState()
        sales[h.beta] = h.accessState()
        h.publish({ stores: [h.acmeLinked(), h.cfgStore(h.beta, "Beta", "/work/beta")], salesState: sales })
        h.panel.navigate({ view: "home" })
      },
      function() {
        smoke.check(h.panel.viewName === "home" && h.panel.view.periodSwitchShown === false && h.panel.view.countedOrder.length === 0, "no access anywhere: no hero, got " + JSON.stringify(h.panel.view.countedOrder))
        smoke.check(h.footerIs(["hints.open", "hints.add", "hints.settings", "hints.edit"]), "no access anywhere: no period in the footer, got " + h.footerKeys())
        smoke.check(h.sheetKeys().indexOf("h / l") < 0, "no h / l period row without a hero")
        // Home is the bottom of the stack: Esc closes, Backspace does nothing.
        smoke.check(h.panel.keySheetItem.canGoBack === false && h.sheetText("Esc", "navigate") === h.t("keys.closePanel"), "Home: Esc closes the panel, got " + JSON.stringify(h.sheetRows("navigate")))
        smoke.check(h.sheetKeys("navigate").join(",").indexOf("Backspace") < 0, "Home lists no Backspace")
        // 5. One store with access: only it is totalled.
        var sales = {}
        sales[h.acme] = h.figuresState()
        sales[h.beta] = h.accessState()
        h.publish({ stores: [h.acmeLinked(), h.cfgStore(h.beta, "Beta", "/work/beta")], salesState: sales })
      },
      function() {
        smoke.check(h.panel.view.periodSwitchShown === true && h.panel.view.countedOrder.length === 1 && h.panel.view.countedOrder[0] === h.acme, "partial access: only the granted store counts, got " + JSON.stringify(h.panel.view.countedOrder))
        smoke.check(h.panel.view.totals.storeCount === 1, "partial access: \"1 store\", got " + h.panel.view.totals.storeCount)
        // 6. A panel dialog about a store that is then removed closes.
        h.publish({ stores: [h.acmeLinked(), h.cfgStore(h.beta, "Beta", "/work/beta")], salesState: h.salesOf(h.figuresState()) })
      },
      function() {
        smoke.check(h.panel.confirm({ action: "pull", domain: h.beta }) === true && h.panel.confirmFlow.opened, "pull dialog for beta opens")
        h.publishAcme()
      },
      function() {
        smoke.check(h.panel.confirmFlow.opened === false, "the dialog for a removed store closed")
        smoke.check(h.callsNamed("pullTheme") === 0, "nothing ran for the removed store")
        // 7. Home rebuilt while config.json is unreadable keeps the cursor
        //    for when the file comes back (the third store stays selected).
        h.publish({ stores: [h.acmeLinked(), h.cfgStore(h.beta, "Beta", "/work/beta"), h.cfgStore(h.gamma, "Gamma", "/work/gamma")] })
      },
      function() {
        h.panel.view.cursorId = h.gamma
        h.publishBroken()
        h.panel.navigate({ view: "settings" })
      },
      function() {
        h.panel.navigate({ view: "home" })
      },
      function() {
        smoke.check(h.panel.viewName === "home" && h.panel.homeCursorDomain === h.gamma, "Home rebuilt while broken keeps the selected store, got " + h.panel.homeCursorDomain)
        h.publish({ stores: [h.acmeLinked(), h.cfgStore(h.beta, "Beta", "/work/beta"), h.cfgStore(h.gamma, "Gamma", "/work/gamma")] })
      },
      function() {
        smoke.check(h.panel.view.cursorId === h.gamma && h.panel.view.cursorIndex === 2, "file fixed: the third store is still selected, got " + h.panel.view.cursorId)
        // A reorder moves the selection with its store.
        h.publish({ stores: [h.cfgStore(h.gamma, "Gamma", "/work/gamma"), h.acmeLinked(), h.cfgStore(h.beta, "Beta", "/work/beta")] })
        smoke.check(h.panel.view.cursorId === h.gamma && h.panel.view.cursorIndex === 0 && h.panel.view.selectedDomain === h.gamma, "Home: the cursor follows its store to the top, got " + h.panel.view.cursorId + " at " + h.panel.view.cursorIndex)
        // 8. Reset config forgets every store and stops its helpers: refused
        //    before its dialog while a job, preview or grant runs, though a
        //    broken config.json lists no stores (the top-level keys say so).
        h.publishBroken({ themesBusy: "job" })
        smoke.check(h.panel.confirm({ action: "resetConfig" }) === false && h.panel.confirmFlow.opened === false, "reset during a job opens no dialog")
        smoke.check(h.panel.toastText === h.t("error.store_busy.anyStore"), "reset during a job says to wait for it, got " + h.panel.toastText)
        h.publishBroken({ granting: true })
        smoke.check(h.panel.confirm({ action: "resetConfig" }) === false && h.panel.confirmFlow.opened === false, "reset during a grant opens no dialog")
        smoke.check(h.panel.toastText === h.t("error.store_busy.grant"), "reset during a grant names the grant, got " + h.panel.toastText)
        h.publishBroken()
        smoke.check(h.panel.confirm({ action: "resetConfig" }) === true && h.panel.confirmFlow.opened === true, "reset with nothing running opens its dialog")
      },
      function() {
        // 9. config.json reads again while the Reset dialog is open: the
        //    dialog closes, so Enter can't wipe the now-good file.
        smoke.check(h.panel.confirmFlow.opened === true, "the reset dialog is open")
        h.publish({ stores: [h.acmeLinked()] })
      },
      function() {
        smoke.check(h.panel.confirmFlow.opened === false, "the reset dialog closed once config.json read again")
        smoke.check(h.service.calls.indexOf("resetConfig") < 0, "nothing was reset")
        // 10. The startup CLI check failed (check-account timed out): a
        //     banner says so with Retry, and the first-run checklist offers
        //     the same instead of "Checking…".
        h.publish({ stores: [], cli: { status: "unknown", missing: null, error: { code: "timeout", message: "" } } })
        h.panel.navigate({ view: "home" })
      },
      function() {
        smoke.check(!!h.panel.banner && h.panel.banner.id === "cliCheckFailed" && h.panel.banner.title === h.t("banner.cliCheckFailed.title"), "failed CLI check: banner, got " + JSON.stringify(h.panel.banner))
        var s1 = h.panel.view.setupSteps[0]
        smoke.check(s1.help === h.t("error.timeout") && s1.actions.length === 1 && s1.actions[0].id === "retryCheck", "failed CLI check: checklist step 1 says why and offers Retry, got " + JSON.stringify(s1))
        var before = h.service.calls.length
        h.panel.bannerAction("retryCheck")
        h.panel.view.setupActivate("retryCheck")
        smoke.check(h.callsSince(before).join(",") === "refresh,refresh", "Retry re-runs the check, got " + h.callsSince(before).join(","))
      }
    ]
  }
}
