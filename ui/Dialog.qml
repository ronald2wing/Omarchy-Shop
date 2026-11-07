pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

// Shop's confirm dialog: a title, a LIVE chip when spec.live, a fact grid, a
// body and two buttons. It keeps the kit ConfirmDialog's semantics (scrim,
// Esc cancels, Cancel is the default button) and adds the structure the
// kit's single `message` string cannot show.
//
// Contract:
//   show(spec) with spec = {title, facts: [{label, value}], body,
//     okText, destructive?, live?, commands?: [string],
//     origin?: "panel" | "ipc"}
//   hide()
//   opened       true while showing; `spec` is the current spec
//   selectedIndex 0 = Cancel (default), 1 = OK
//   armed        false for the first 400 ms after show(): both buttons sit
//                at 50 % opacity and ignore clicks, hover and keys, so a
//                click aimed at whatever was under the pointer can never
//                accept a dialog that just appeared. Esc always cancels.
//   keys         Left/Right/Tab/Shift+Tab move, Enter activates, Esc
//                cancels. No text keys (h/l) and no Space: a dialog that
//                takes focus while the user is typing elsewhere must not be
//                driven by ordinary typing. A key counts only once armed,
//                after some key was released since the dialog appeared
//                (a burst or a held key that began before it cannot both
//                move and activate), and never as an auto-repeat.
//   ipc          a spec with origin "ipc" (an IPC request* opened the
//                panel unasked and took the keyboard) accepts from the
//                keyboard only with Ctrl+Enter, which accepts whichever
//                button is selected (Cancel is the default); plain Enter
//                and Space do nothing, and a caption under the body says so.
//   signals      accepted(), canceled()
// `commands` renders as a monospace block, one command per line, wrapped
// (at spaces, else anywhere) so the whole command, package and pinned
// version included, is readable before accepting (the install dialog).
Item {
  id: root

  property bool opened: false
  property var spec: null
  property int selectedIndex: 0
  property bool armed: false
  // A key release arrived since show()/rearm(): keys pressed before the
  // dialog appeared (and their auto-repeats) never count.
  property bool keyReleasedSinceShow: false
  readonly property int guardMs: 400
  readonly property bool fromIpc: !!root.spec && root.spec.origin === "ipc"

  signal accepted()
  signal canceled()

  readonly property var facts: root.spec && Array.isArray(root.spec.facts) ? root.spec.facts : []
  readonly property var commands: root.spec && Array.isArray(root.spec.commands) ? root.spec.commands : []
  readonly property bool destructive: !!root.spec && root.spec.destructive === true
  // The card's height, for a host that sizes itself around the dialog.
  readonly property real cardHeight: card.height

  function show(newSpec) {
    root.spec = newSpec
    root.opened = true
    root.rearm()
    root.forceActiveFocus()
  }

  function hide() {
    guard.stop()
    root.opened = false
    root.spec = null
  }

  // The host reopened with this dialog still up: content that just
  // appeared, so the click guard starts over.
  function rearm() {
    if (!root.opened) return
    root.armed = false
    root.keyReleasedSinceShow = false
    root.selectedIndex = 0
    guard.restart()
  }

  function activate(index) {
    if (!root.opened || !root.armed) return
    if (index === 0) root.canceled()
    else root.accepted()
  }

  // A key may move the selection or activate only once the dialog is armed,
  // some key was released since it appeared, and the press is no repeat.
  function keyCounts(event) {
    return root.armed && root.keyReleasedSinceShow && event.isAutoRepeat !== true
  }

  // Also called by the host for keys that arrive while it holds focus.
  // Returns true when the key was the dialog's (also when it was swallowed
  // on purpose: nothing behind the dialog may act on it).
  function handleKey(event) {
    if (!root.opened) return false
    if (event.key === Qt.Key_Escape) { root.canceled(); return true }
    var left = event.key === Qt.Key_Left || event.key === Qt.Key_Backtab
      || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))
    var right = event.key === Qt.Key_Right || event.key === Qt.Key_Tab
    var enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
    if (!left && !right && !enter && event.key !== Qt.Key_Space) return false
    if (!root.keyCounts(event)) return true
    if (left || right) { root.selectedIndex = root.selectedIndex === 0 ? 1 : 0; return true }
    // Ctrl+Enter on an IPC dialog means "confirm", as its caption says,
    // whatever button the selection rests on.
    if (enter) {
      if (!root.fromIpc) root.activate(root.selectedIndex)
      else if (event.modifiers & Qt.ControlModifier) root.activate(1)
    }
    return true
  }

  function handleKeyRelease(event) {
    if (root.opened && event.isAutoRepeat !== true) root.keyReleasedSinceShow = true
  }

  visible: root.opened
  focus: root.opened
  Keys.onPressed: (event) => { event.accepted = root.handleKey(event) }
  Keys.onReleased: (event) => root.handleKeyRelease(event)

  Timer {
    id: guard
    interval: root.guardMs
    onTriggered: root.armed = true
  }

  Rectangle {
    anchors.fill: parent
    color: Look.scrim

    MouseArea {
      anchors.fill: parent
      onClicked: root.canceled()
    }

    BorderSurface {
      id: card
      width: Math.min(parent.width - Style.space(24), Style.space(420))
      height: cardColumn.implicitHeight + Style.spacing.panelPadding * 2
      anchors.centerIn: parent
      color: Look.surface
      borderSpec: Border.flat(root.destructive ? Look.negative : Look.accent, Style.normalBorderWidth)
      radius: Style.cornerRadius

      Accessible.role: Accessible.Dialog
      Accessible.name: root.spec ? String(root.spec.title || "") : ""

      // Clicks inside the card stay inside it.
      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: cardColumn
        x: Style.spacing.panelPadding
        y: Style.spacing.panelPadding
        width: parent.width - Style.spacing.panelPadding * 2
        spacing: Look.gapLg

        // Title row with the optional LIVE chip.
        Item {
          width: parent.width
          height: Math.max(titleLabel.implicitHeight, chip.implicitHeight)

          PlainLabel {
            id: titleLabel
            anchors.left: parent.left
            anchors.right: chip.visible ? chip.left : parent.right
            anchors.rightMargin: chip.visible ? Look.gapLg : 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.spec ? String(root.spec.title || "") : ""
            font.pixelSize: Look.title
            font.bold: true
            wrapMode: Text.WordWrap
          }

          LiveChip {
            id: chip
            visible: !!root.spec && root.spec.live === true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            filled: true
          }
        }

        // Facts: a label column (labelWidth) and wrapping values.
        Column {
          visible: root.facts.length > 0
          width: parent.width
          spacing: Look.gapSm

          Repeater {
            model: root.facts

            delegate: Item {
              id: factRow
              required property var modelData
              width: parent ? parent.width : 0
              height: Math.max(factLabel.implicitHeight, factValue.implicitHeight)

              PlainLabel {
                id: factLabel
                anchors.left: parent.left
                anchors.top: parent.top
                width: Math.min(Look.labelWidth, parent.width / 3)
                text: String(factRow.modelData.label || "")
                color: Look.muted
                font.pixelSize: Look.small
                elide: Text.ElideRight
              }

              PlainLabel {
                id: factValue
                anchors.left: factLabel.right
                anchors.leftMargin: Look.gapLg
                anchors.right: parent.right
                anchors.top: parent.top
                text: String(factRow.modelData.value || "")
                wrapMode: Text.Wrap
              }
            }
          }
        }

        // The commands block (install): every command fully visible, long
        // ones wrapped, so nothing a cautious user wants to read is off the edge.
        Rectangle {
          visible: root.commands.length > 0
          width: parent.width
          height: commandsLabel.implicitHeight + Look.gapSm * 2
          radius: Style.cornerRadius
          color: Look.softFill

          PlainLabel {
            id: commandsLabel
            x: Look.gapMd
            y: Look.gapSm
            width: parent.width - Look.gapMd * 2
            text: root.commands.join("\n")
            font.pixelSize: Look.small
            wrapMode: Text.Wrap
          }
        }

        PlainLabel {
          visible: text !== ""
          width: parent.width
          text: root.spec ? String(root.spec.body || "") : ""
          color: Look.muted
          wrapMode: Text.WordWrap
        }

        // An IPC request opened this dialog unasked: say how it is confirmed.
        PlainLabel {
          visible: root.fromIpc
          width: parent.width
          text: Copy.t("confirm.ipcHint")
          color: Look.warn
          font.pixelSize: Look.small
          wrapMode: Text.WordWrap
        }

        // Buttons: Cancel then OK; the cursor starts on Cancel.
        Row {
          anchors.right: parent.right
          spacing: Look.gapLg
          topPadding: Look.gapSm

          Button {
            text: Copy.t("action.cancel")
            bordered: true
            hasCursor: root.selectedIndex === 0
            opacity: root.armed ? 1 : 0.5
            onClicked: root.activate(0)
            onHovered: (h) => { if (h && root.armed) root.selectedIndex = 0 }
            Accessible.role: Accessible.Button
            Accessible.name: text
            Accessible.onPressAction: root.activate(0)
          }

          Button {
            text: root.spec ? String(root.spec.okText || "") : ""
            bordered: true
            foreground: root.destructive ? Look.negative : Look.fg
            accent: root.destructive ? Look.negative : Look.accent
            hasCursor: root.selectedIndex === 1
            opacity: root.armed ? 1 : 0.5
            onClicked: root.activate(1)
            onHovered: (h) => { if (h && root.armed) root.selectedIndex = 1 }
            Accessible.role: Accessible.Button
            Accessible.name: text
            Accessible.onPressAction: root.activate(1)
          }
        }
      }
    }
  }
}
