import QtQuick

// The one-line key reminder under every view: the panel's footer text (a
// view's leading keymap rows, js/keymap.mjs footerText), then a fixed "?
// keys" tail (Copy "hints.keys") that leads to the key sheet. Only the
// leading part elides, so a narrow panel or a longer translation can never
// hide the way to the rest of the keys.
// Contract: hints (the finished footer text; "" shows only the tail).
Item {
  id: root

  property string hints: ""

  implicitHeight: Math.max(lead.implicitHeight, tail.implicitHeight)

  Accessible.role: Accessible.StaticText
  Accessible.name: root.hints !== "" ? root.hints + " · " + tail.text : tail.text

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.min(parent.width, lead.implicitWidth + sep.width + tail.implicitWidth)
    spacing: 0

    PlainLabel {
      id: lead
      width: parent.width - sep.width - tail.width
      text: root.hints
      color: Look.muted
      font.pixelSize: Look.caption
      elide: Text.ElideRight
    }

    PlainLabel {
      id: sep
      text: root.hints !== "" ? " · " : ""
      color: Look.muted
      font.pixelSize: Look.caption
    }

    PlainLabel {
      id: tail
      text: Copy.t("hints.keys")
      color: Look.muted
      font.pixelSize: Look.caption
    }
  }
}
