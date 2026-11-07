// runner: quickshell
import QtQuick
import Quickshell
import "shop/ui" as Shop
import "shop/tests/qml"

// ui/Dialog.qml against the shell's real qs.Ui / qs.Commons: the keys that
// can and cannot confirm it. An IPC request* opens the panel on the focused
// monitor and takes the keyboard, so the dialog is fed exactly what a user
// typing into what they think is their terminal would send: `ls⏎`, then
// Tab/Space/Enter bursts, all after the 400 ms guard. Checks: nothing
// counts while unarmed; text keys and Space never count; a key counts only
// after a release since show() and never as an auto-repeat; a panel-origin
// dialog takes Enter on the selected button; an ipc-origin dialog takes
// Ctrl+Enter only.
// Run alone: tests/run tests/qml/dialog_smoke.qml
ShellRoot {
  id: root

  property int accepted: 0
  property int canceled: 0

  function press(key, opts) {
    var e = { key: key, text: "", modifiers: 0, isAutoRepeat: false }
    if (opts) for (var k in opts) e[k] = opts[k]
    return dlg.handleKey(e)
  }

  function release(key) {
    dlg.handleKeyRelease({ key: key, text: "", modifiers: 0, isAutoRepeat: false })
  }

  FloatingWindow {
    id: win
    implicitWidth: 480
    implicitHeight: 400
    visible: true

    // The host (ConfirmFlow.close) hides the dialog on either answer.
    Shop.Dialog {
      id: dlg
      width: win.width
      height: win.height
      onAccepted: { root.accepted++; dlg.hide() }
      onCanceled: { root.canceled++; dlg.hide() }
    }
  }

  // Each step runs 500 ms after the previous one, past the 400 ms guard.
  Smoke {
    id: smoke
    name: "DIALOG"
    interval: 500
    steps: [
      function() {
        // 1. Panel origin, just shown: nothing counts while unarmed.
        dlg.show({ title: "Push to Dawn?", body: "b", okText: "Push", origin: "panel" })
        smoke.check(dlg.opened && !dlg.armed && dlg.selectedIndex === 0, "unarmed on show")
        root.release(Qt.Key_P)
        smoke.check(root.press(Qt.Key_Right) === true && dlg.selectedIndex === 0, "Right swallowed while unarmed")
        smoke.check(root.press(Qt.Key_Return) === true && root.accepted === 0 && root.canceled === 0 && dlg.opened, "Enter swallowed while unarmed")
      },
      function() {
        // 2. Armed, no release since show (the dialog was re-armed): a held
        //    key or a burst from before it cannot move or activate.
        smoke.check(dlg.armed, "armed after the guard")
        dlg.rearm()
        smoke.check(!dlg.armed && !dlg.keyReleasedSinceShow, "rearm resets")
      },
      function() {
        smoke.check(dlg.armed, "armed again")
        smoke.check(root.press(Qt.Key_Tab) === true && dlg.selectedIndex === 0, "Tab before any release is ignored")
        smoke.check(root.press(Qt.Key_Return) === true && root.accepted === 0 && dlg.opened, "Enter before any release is ignored")
        // The burst the user typed blind: l, s, Enter. `l` is a text key and
        // moves nothing; Enter then lands on Cancel, which only declines.
        smoke.check(root.press(Qt.Key_L, { text: "l" }) === false && dlg.selectedIndex === 0, "l is not a dialog key")
        root.release(Qt.Key_L)
        smoke.check(dlg.keyReleasedSinceShow, "a release arms the keys")
        smoke.check(root.press(Qt.Key_S, { text: "s" }) === false, "s is not a dialog key")
        root.release(Qt.Key_S)
        root.press(Qt.Key_Return)
        smoke.check(root.canceled === 1 && root.accepted === 0 && !dlg.opened, "Enter on Cancel declines, never accepts")
        // Space never activates; auto-repeats never count.
        dlg.show({ title: "T", body: "b", okText: "OK", origin: "panel" })
        smoke.check(dlg.opened, "show again")
      },
      function() {
        root.release(Qt.Key_Shift)
        smoke.check(root.press(Qt.Key_Right, { isAutoRepeat: true }) === true && dlg.selectedIndex === 0, "an auto-repeated Right moves nothing")
        smoke.check(root.press(Qt.Key_Right) === true && dlg.selectedIndex === 1, "Right moves to OK once armed and released")
        smoke.check(root.press(Qt.Key_Space, { text: " " }) === true && root.accepted === 0 && dlg.opened, "Space never activates")
        smoke.check(root.press(Qt.Key_Return, { isAutoRepeat: true }) === true && root.accepted === 0 && dlg.opened, "an auto-repeated Enter never activates")
        root.press(Qt.Key_Return)
        smoke.check(root.accepted === 1 && !dlg.opened, "a deliberate Enter on OK accepts a panel-origin dialog")
        // 3. IPC origin: the dialog came unasked and took the keyboard.
        dlg.show({ title: "Pull Dawn into the folder?", body: "b", okText: "Pull", origin: "ipc" })
        smoke.check(dlg.opened, "show ipc")
        smoke.check(dlg.fromIpc, "ipc spec recognised")
      },
      function() {
        root.release(Qt.Key_L)
        smoke.check(root.press(Qt.Key_Tab) === true && dlg.selectedIndex === 1, "Tab moves to OK")
        smoke.check(root.press(Qt.Key_Space, { text: " " }) === true && root.accepted === 1 && dlg.opened, "Tab + Space does not accept an ipc dialog")
        smoke.check(root.press(Qt.Key_Return) === true && root.accepted === 1 && dlg.opened, "Tab + Enter does not accept an ipc dialog")
        smoke.check(root.press(Qt.Key_Enter) === true && root.accepted === 1 && dlg.opened, "keypad Enter neither")
        root.press(Qt.Key_Return, { modifiers: Qt.ControlModifier })
        smoke.check(root.accepted === 2 && !dlg.opened, "Ctrl+Enter accepts an ipc dialog")
        // Ctrl+Enter confirms even with Cancel selected (the default): the
        // caption says "Ctrl+Enter confirms", never "declines".
        dlg.show({ title: "Push to Dawn?", body: "b", okText: "Push", origin: "ipc" })
        smoke.check(dlg.opened, "show ipc again")
      },
      function() {
        root.release(Qt.Key_Control)
        smoke.check(dlg.selectedIndex === 0, "Cancel selected on show")
        root.press(Qt.Key_Return, { modifiers: Qt.ControlModifier })
        smoke.check(root.accepted === 3 && root.canceled === 1 && !dlg.opened, "Ctrl+Enter with Cancel selected accepts an ipc dialog")
        // Esc always cancels, armed or not.
        dlg.show({ title: "T", body: "b", okText: "OK", origin: "ipc" })
        root.press(Qt.Key_Escape)
        smoke.check(root.canceled === 2 && !dlg.opened, "Esc cancels while unarmed")
      }
    ]
  }
}
