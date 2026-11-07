// runner: quickshell
import QtQuick
import Quickshell
import "shop/tests/qml"

// The panel's Settings view (PanelHarness): the CLI row, the cursor across
// rows that come and go, config.json unreadable, and the refresh stepper's
// saves.
// Run alone: tests/run tests/qml/panel_settings_smoke.qml
ShellRoot {
  id: root

  // updateSettings calls before the stepper checks.
  property int pollSaves: 0

  PanelHarness { id: h }

  Smoke {
    id: smoke
    name: "PANEL_SETTINGS"
    steps: [
      function() {
        // 1. Settings opened from the bar: the bottom of the stack.
        h.publishAcme()
        h.panel.navigate({ view: "settings" })
      },
      function() {
        smoke.check(h.panel.viewName === "settings" && h.panel.keySheetItem.canGoBack === false, "settings at the bottom")
        smoke.check(h.sheetText("Esc / Backspace", "navigate") === h.t("keys.closePanel"), "bottom Settings: Esc / Backspace close, got " + JSON.stringify(h.sheetRows("navigate")))
        smoke.check(h.sheetText("↑/↓ or j/k", "navigate") === h.t("keys.move"), "Settings: ↑/↓ move")
        // 2. A failed account check says why, not "Checking…" (nothing is
        //    running).
        var before = h.service.snapshot
        var failed = Object.assign({}, before)
        failed.cli = { status: "unknown", missing: null, error: { code: "timeout", message: "check-account took too long" } }
        h.service.snapshot = failed
        smoke.check(h.panel.view.cliText() === h.errorOf(failed.cli.error) && h.panel.view.cliText() !== h.t("status.checking"), "Settings: a failed CLI check shows its error, got " + h.panel.view.cliText())
        var checking = Object.assign({}, before)
        checking.cli = { status: "checking", missing: null, error: null }
        h.service.snapshot = checking
        smoke.check(h.panel.view.cliText() === h.t("status.checking"), "Settings: a running check reads Checking…")
        // 3. The cursor stays on its row when the Copy command row comes
        //    and goes (Enter must not land on the row that slid under the
        //    index).
        var missing = Object.assign({}, before)
        missing.cli = h.cliMissing
        h.service.snapshot = missing
        smoke.check(h.panel.view.rowIds.indexOf("copy") >= 0, "CLI missing: the Copy command row shows")
        h.panel.view.cursorId = "account"
        h.service.snapshot = before
        smoke.check(h.panel.view.cursorId === "account", "the Copy row left: the cursor stays on account, got " + h.panel.view.cursorId)
        h.service.snapshot = missing
        smoke.check(h.panel.view.cursorId === "account", "the Copy row came back: still account, got " + h.panel.view.cursorId)
        h.panel.view.cursorId = "copy"
        h.service.snapshot = before
        smoke.check(h.panel.view.cursorId === "cli", "the Copy row left under the cursor: it moves to cli, got " + h.panel.view.cursorId)
        // 4. config.json unreadable: the alert, bar and refresh rows would
        //    show Config's defaults and refuse every write, so they hide;
        //    the cursor and the sheet skip them.
        var brokenSnap = Object.assign({}, before)
        brokenSnap.configError = h.brokenConfig
        h.panel.view.cursorId = "account"
        h.service.snapshot = brokenSnap
        var bids = h.panel.view.rowIds
        smoke.check(["notify", "sound", "barShows", "poll"].every(function(id) { return bids.indexOf(id) < 0 }) && bids.indexOf("test") >= 0 && bids.indexOf("reset") >= 0, "broken Settings rows: no notify/sound/barShows/poll, got " + bids.join(","))
        smoke.check(h.panel.view.itemFor("notify").visible === false && h.panel.view.itemFor("poll").visible === false, "broken Settings hides the toggles and the refresh field")
        smoke.check(h.panel.view.cursorId === "account", "broken Settings keeps the cursor on account, got " + h.panel.view.cursorId)
        smoke.check(h.footerIs(["hints.broken"]) && h.sheetKeys().join(",") === "Enter", "broken Settings: the banner's keys, sheet only Enter, got " + h.footerKeys() + " " + h.sheetKeys().join(","))
        var settingsCalls = h.service.calls.length
        h.panel.view.toggleNotify()
        smoke.check(h.service.calls.length === settingsCalls && h.panel.toastText === h.t("error.config_invalid"), "broken Settings: a toggle never writes, the toast says why")
        h.service.snapshot = before
        smoke.check(h.panel.view.cursorId === "account", "fixed Settings: the cursor is still on account, got " + h.panel.view.cursorId)
        // 5. Enter in the poll field saves and hands the keyboard back.
        h.panel.view.cursorId = "poll"
        h.panel.view.activate()
      },
      function() {
        smoke.check(h.panel.inputFocused === true && !!h.focused, "the poll field takes the keyboard")
        // A real Return in the field (LineEdit turns it into accepted()).
        h.key(Qt.Key_Return)
      },
      function() {
        smoke.check(h.panel.inputFocused === false, "Enter in the poll field gives the keyboard back to the panel")
        // 6. Typing back to the saved value disarms the save.
        root.pollSaves = h.callsNamed("updateSettings ")
        h.panel.view.activate()
      },
      function() {
        h.key(Qt.Key_End)
        h.key(Qt.Key_9)
        smoke.check(h.focusedText() === "609", "the poll field takes typing, got " + h.focusedText())
        h.key(Qt.Key_Backspace)
      },
      // Well past the 800 ms debounce, still in the field.
      smoke.pause(800),
      function() {
        smoke.check(h.callsNamed("updateSettings ") === root.pollSaves && h.panel.inputFocused === true, "typing back to the saved interval arms no save, got " + h.service.calls.slice(-2).join(" / "))
        h.key(Qt.Key_Return)
        smoke.check(h.callsNamed("updateSettings ") === root.pollSaves && h.panel.inputFocused === false, "Enter on the saved interval saves nothing")
        // 7. Esc reverts the field, saves nothing and gives the keyboard back.
        h.panel.view.activate()
      },
      function() {
        h.key(Qt.Key_End)
        h.key(Qt.Key_0)
        h.key(Qt.Key_Escape)
        smoke.check(h.panel.inputFocused === false && !!h.findText(h.panel.view.itemFor("poll"), "60") && !h.findText(h.panel.view.itemFor("poll"), "600"), "Esc in the poll field shows the saved 60 again and lets go of the keyboard")
      },
      smoke.pause(800),
      function() {
        smoke.check(h.callsNamed("updateSettings ") === root.pollSaves && h.panel.viewName === "settings", "Esc in the poll field saves nothing, got " + h.service.calls.slice(-2).join(" / "))
        // 8. A typed value still waiting for its save is saved once when
        //    Settings closes.
        h.panel.view.activate()
      },
      function() {
        h.key(Qt.Key_End)
        h.key(Qt.Key_9)
        h.panel.navigate({ view: "home" })
        smoke.check(h.callsNamed("updateSettings ") === root.pollSaves + 1 && h.service.calls.indexOf("updateSettings {\"pollSeconds\":609}") >= 0, "leaving Settings saves the armed interval once, got " + h.service.calls.slice(-2).join(" / "))
      }
    ]
  }
}
