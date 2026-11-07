import QtQuick
import qs.Ui

// A tooltip for a plain item: fills its parent, takes no clicks, and shows
// `text` while the pointer is over it ("" shows nothing).
MouseArea {
  id: root

  property string text: ""

  anchors.fill: parent
  hoverEnabled: true
  acceptedButtons: Qt.NoButton

  PanelToolTip {
    visible: root.containsMouse && root.text !== ""
    text: root.text
  }
}
