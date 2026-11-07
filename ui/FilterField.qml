import QtQuick
import qs.Commons

// The one-line filter at the top of a list (Add's stores): a search glyph,
// a LineEdit (append-only: the caret stays at the end, no selection) and a
// placeholder that names the `/` key until the
// field has focus. Only navigation leaves the field: ↑/↓ ask to move the
// list cursor, Enter to activate its row; Esc clears the text, or with
// nothing typed gives the keyboard back. Ordinary typing stays in the field.
//
// Contract: placeholder; text; paste (the panel's, for LineEdit);
// focusInput(); clear() (empties and blurs);
// signals moveRequested(dy), submitted(), released().
Rectangle {
  id: root

  property string placeholder: ""
  property alias text: input.text
  property var paste: null

  signal moveRequested(int dy)
  signal submitted()
  signal released()

  function focusInput() {
    input.forceActiveFocus()
  }

  function clear() {
    input.text = ""
    input.focus = false
  }

  height: input.implicitHeight + Style.spacing.inputPaddingY * 2
  radius: Style.cornerRadius
  color: Style.controlFill(input.activeFocus, false, Look.fg, Look.accent)
  border.width: 1
  border.color: input.activeFocus ? Style.focusBorderFor(Look.fg, Look.accent) : Style.normalBorderFor(Look.fg, Look.accent)

  PlainLabel {
    id: searchGlyph
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.controlPaddingX
    anchors.verticalCenter: parent.verticalCenter
    text: "󰍉"
    color: Look.muted
  }

  LineEdit {
    id: input
    focus: false
    framed: false
    appendOnly: true
    horizontalPadding: 0
    verticalPadding: 0
    maximumLength: 200
    keyHandler: keyRelay
    paste: root.paste
    anchors.left: searchGlyph.right
    anchors.leftMargin: Look.gapMd
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.controlPaddingX
    anchors.verticalCenter: parent.verticalCenter
    Accessible.name: root.placeholder
  }

  PlainLabel {
    visible: input.text === "" && !input.composing
    anchors.left: input.left
    anchors.verticalCenter: parent.verticalCenter
    text: root.placeholder + (input.activeFocus ? "" : "  /")
    color: Look.muted
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.IBeamCursor
    onClicked: root.focusInput()
  }

  // Sees the field's keys first (LineEdit's keyHandler): only
  // navigation, Enter and Esc. Keys.forwardTo skips invisible items, so this
  // stays visible at 0×0 — never `visible: false`.
  Item {
    id: keyRelay
    width: 0
    height: 0
    Keys.onPressed: (event) => {
      if (event.key === Qt.Key_Down) { root.moveRequested(1); event.accepted = true }
      else if (event.key === Qt.Key_Up) { root.moveRequested(-1); event.accepted = true }
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.submitted(); event.accepted = true }
      else if (event.key === Qt.Key_Escape) {
        if (input.text !== "") input.text = ""
        else { input.focus = false; root.released() }
        event.accepted = true
      }
    }
  }
}
