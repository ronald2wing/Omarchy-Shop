// runner: quickshell
import QtQuick
import Quickshell
import "shop/tests/qml"

// The panel's Edit view (PanelHarness): the text fields' keyboard and paste
// keys, the folder warning, the theme picker, a rate-limited theme list and
// config.json unreadable.
// Run alone: tests/run tests/qml/panel_edit_smoke.qml
ShellRoot {
  id: root

  // updateStore calls before a field commits.
  property int nameSaves: 0

  readonly property var listed: ({ status: "ok", items: [{ id: "1", name: "Dawn", role: "live" }, { id: "2", name: "Sense", role: "unpublished" }, { id: "3", name: "Craft", role: "development" }], fetchedAt: Date.now(), error: null })

  PanelHarness { id: h }

  Smoke {
    id: smoke
    name: "PANEL_EDIT"
    steps: [
      function() {
        // 1. Edit: Tab from Name lands in Folder and keeps the keyboard.
        h.publishAcme()
        h.panel.navigate({ view: "edit", domain: h.acme })
      },
      function() {
        smoke.check(h.panel.viewName === "edit", "edit view")
        smoke.check(h.sheetKeys().indexOf("h / l") < 0, "Edit lists no h / l (h / l do nothing there): " + h.sheetKeys().join(","))
        h.panel.view.cursorId = "name"
        h.panel.view.activate()
      },
      function() {
        smoke.check(h.panel.inputFocused === true, "Enter on Name focuses the field")
        // A real Return: unless the field accepts it, the view's Enter would
        // re-enter the field.
        root.nameSaves = h.callsNamed("updateStore ")
        h.key(Qt.Key_Z)
        h.key(Qt.Key_Return)
      },
      function() {
        smoke.check(h.panel.inputFocused === false && h.panel.view.cursorId === "name", "a real Return in Name commits, blurs and gives the keyboard back, got inputFocused " + h.panel.inputFocused)
        smoke.check(h.callsNamed("updateStore ") === root.nameSaves + 1, "Return commits the changed name once, got " + (h.callsNamed("updateStore ") - root.nameSaves))
        h.panel.view.itemFor("name").revertAndBlur()
        h.panel.view.activate()
      },
      function() {
        smoke.check(h.panel.inputFocused === true, "Enter on Name focuses the field again")
        h.panel.view.itemFor("name").leave(1)
      },
      function() {
        smoke.check(h.panel.view.cursorId === "folder", "Tab from Name moves the cursor to Folder, got " + h.panel.view.cursorId)
        smoke.check(h.panel.inputFocused === true && h.isTextInput(h.focused), "Folder keeps the keyboard after the deferred restoreFocus")
        // 2. Paste keys go through the service's capped read, never Qt's:
        //    Ctrl+V replaces the selection, Shift+Insert inserts at the
        //    caret, a failed read toasts and leaves the text alone.
        var reads = h.callsNamed("readClipboard")
        h.key(Qt.Key_V, Qt.ControlModifier)
        smoke.check(h.focusedText() === "~/pasted folder", "Ctrl+V pastes the helper's text over the selection, got " + h.focusedText())
        h.key(Qt.Key_Insert, Qt.ShiftModifier)
        smoke.check(h.focusedText() === "~/pasted folder~/pasted folder", "Shift+Insert pastes at the caret, got " + h.focusedText())
        h.service.clipboard = { ok: false, error: { code: "clipboard_too_large", message: "x" } }
        h.key(Qt.Key_V, Qt.ControlModifier)
        smoke.check(h.focusedText() === "~/pasted folder~/pasted folder" && h.panel.toastText === h.t("error.clipboard_too_large"), "a refused read toasts and pastes nothing, toast " + h.panel.toastText)
        smoke.check(h.callsNamed("readClipboard") === reads + 3, "every paste key asked the service")
        h.service.clipboard = { ok: true, text: "~/pasted folder" }
        h.panel.view.itemFor("folder").revertAndBlur()
        h.panel.view.itemFor("folder").leave(1)
        h.publishAcme({ infoState: h.infoOf(root.listed, null) })
      },
      function() {
        // 3. Edit's Folder field shows the inspection warning for the saved
        //    folder: missing, then unsafe, then nothing once it is usable.
        h.publishFolderState({ exists: false })
      },
      function() {
        smoke.check(h.panel.view.itemFor("folder").error === h.t("theme.folderMissing"), "Edit's Folder warns that the inspected folder is missing, got \"" + h.panel.view.itemFor("folder").error + "\"")
        h.publishFolderState({ exists: true, safe: false, reason: "symlink" })
      },
      function() {
        smoke.check(h.panel.view.itemFor("folder").error === h.t("theme.unsafe.symlink"), "Edit's Folder warns that the inspected folder is unsafe, got \"" + h.panel.view.itemFor("folder").error + "\"")
        h.publishFolderState({ exists: true, safe: true, themeShaped: true })
      },
      function() {
        smoke.check(h.panel.view.itemFor("folder").error === "", "a usable folder shows no warning in Edit, got \"" + h.panel.view.itemFor("folder").error + "\"")
        // 4. The theme-target picker has no native text entry: its filter
        //    is a LineEdit, so paste keys go to the capped helper read.
        h.publishAcme({ infoState: h.infoOf(root.listed, null) })
      },
      function() {
        h.panel.view.cursorId = "target"
        h.panel.view.activate()
      },
      function() {
        var picker = h.panel.view.itemFor("target").picker
        smoke.check(!!picker && picker.popupOpen === true && h.panel.inputFocused === true, "Enter on Theme target opens the picker and it takes the keys")
        smoke.check(h.isTextInput(h.focused), "the picker's filter has the keyboard")
        smoke.check(!h.findNativeTextInput(picker) && !h.findNativeTextInput(picker.popupContent), "no native TextInput anywhere in the picker")
        var bait = Qt.createQmlObject("import QtQuick; Item { TextInput {} }", h.window.contentItem)
        smoke.check(!!h.findNativeTextInput(bait), "the TextInput probe finds a real TextInput")
        bait.destroy()
        var reads = h.callsNamed("readClipboard")
        h.service.clipboard = { ok: true, text: "sen" }
        h.key(Qt.Key_V, Qt.ControlModifier)
        smoke.check(picker.filter.text === "sen" && picker.filtered.length === 1 && String(picker.filtered[0].label) === "Sense", "Ctrl+V in the picker filters through the helper's text, got " + picker.filter.text + " " + picker.filtered.length)
        h.key(Qt.Key_Insert, Qt.ShiftModifier)
        smoke.check(h.callsNamed("readClipboard") === reads + 2, "Ctrl+V and Shift+Insert in the picker both ask the service's capped read")
        h.service.clipboard = { ok: true, text: "~/pasted folder" }
        picker.filter.text = ""
        h.key(Qt.Key_C)
        smoke.check(picker.filtered.length === 1 && String(picker.filtered[0].label) === "Craft", "typing filters the list, got " + picker.filtered.length)
        h.key(Qt.Key_Return)
      },
      function() {
        var picker = h.panel.view.itemFor("target").picker
        smoke.check(picker.popupOpen === false && h.service.calls.indexOf("updateStore " + h.acme + " {\"theme\":{\"target\":\"3\"}}") >= 0, "Enter picks the filtered theme, got " + h.service.calls.slice(-2).join(" / "))
        smoke.check(h.panel.inputFocused === false, "closing the picker gives the keyboard back, focus " + h.focused + " on row " + h.panel.view.cursorId)
        // 5. A rate-limited theme list: an info line that neither repeats
        //    the banner nor retries on r / Enter.
        var limited = { status: "error", items: [], fetchedAt: 0, error: { code: "rate_limited", message: "Throttled", retryAfter: 30 } }
        h.publishAcme({ infoState: h.infoOf(limited, null) })
      },
      function() {
        smoke.check(h.panel.view.themesLimited === true, "themes rate limited")
        smoke.check(!!h.findText(h.panel.view, h.t("edit.themesWaiting")), "the line says the list loads once Shopify allows it")
        smoke.check(!h.findText(h.panel.view, h.t("edit.themesFailed") + ": " + h.t("error.rate_limited")), "no \"Couldn't load themes: Shopify is limiting requests\"")
        var before = h.callsNamed("listThemes")
        h.panel.view.textKey("r")
        smoke.check(h.panel.toastText === h.t("edit.themesWaiting"), "r on a rate-limited list says it waits for Shopify, got " + h.panel.toastText)
        h.panel.view.cursorId = "target"
        h.panel.view.activate()
        var after = h.callsNamed("listThemes")
        smoke.check(after === before, "r and Enter do not retry a rate-limited list (ThemeInfo does): " + before + " -> " + after)
        // 6. config.json breaks under a focused field whose form hides: the
        //    field lets go of the keyboard and its draft. (A fresh Edit:
        //    Enter above left the picker open on the empty list.)
        h.publishAcme()
        h.panel.navigate({ view: "home" })
      },
      function() {
        h.panel.navigate({ view: "edit", domain: h.acme })
      },
      function() {
        h.panel.view.cursorId = "name"
        h.panel.view.activate()
      },
      function() {
        smoke.check(h.isTextInput(h.focused) && h.panel.inputFocused, "Edit: Name takes the keyboard")
        if (h.focused) h.focused.text = "typed while broken"
        h.publishBroken()
        smoke.check(!h.isTextInput(h.focused) && h.panel.inputFocused === false, "Edit broken: the hidden Name gave the keyboard back, focus " + h.focused)
        h.publishAcme()
      },
      function() {
        smoke.check(h.panel.viewName === "edit" && !h.findText(h.panel.view, "typed while broken"), "Edit fixed: the draft typed into the hidden Name is gone")
        smoke.check(h.service.calls.filter(function(c) { return c.indexOf("typed while broken") >= 0 }).length === 0, "nothing typed while broken was saved")
        // 7. config.json unreadable under an open Edit above its store: one
        //    error line, the banner's keys only.
        h.panel.navigate({ view: "store", domain: h.acme })
        h.panel.push({ view: "edit", domain: h.acme })
        h.publishBroken()
      },
      function() {
        smoke.check(h.footerIs(["hints.broken"]) && !!h.findText(h.panel.view, h.t("error.config_invalid")), "broken edit: one error line, got " + h.footerKeys())
      }
    ]
  }
}
