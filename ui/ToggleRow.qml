pragma ComponentBehavior: Bound
import QtQuick
import qs.Ui

// One settings row: a label column (Look.labelWidth), optional help text and
// a trailing ToggleSwitch. The row never flips itself: a click, Enter on the
// cursor or the accessible press action emits `toggled` and the owner
// changes the value, so the switch always shows the saved state.
//
// Contract: label; help ("" hides it); checked; selected (the keyboard
// cursor); dimmed (no effect right now, e.g. the order sound while alerts
// are off); signals toggled(), hoveredRow().
Item {
  id: root

  property string label: ""
  property string help: ""
  property bool checked: false
  property bool selected: false
  property bool dimmed: false

  signal toggled()
  signal hoveredRow()

  height: Math.max(labelText.implicitHeight, helpText.visible ? helpText.implicitHeight : 0, toggle.implicitHeight)
  opacity: root.dimmed ? 0.5 : 1

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.dimmed ? Qt.ArrowCursor : Qt.PointingHandCursor
    onEntered: root.hoveredRow()
    onClicked: root.toggled()
  }

  RowLabel {
    id: labelText
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    lit: root.selected
    wrapMode: Text.Wrap
    maximumLineCount: 2
    elide: Text.ElideRight
  }

  PlainLabel {
    id: helpText
    visible: root.help !== ""
    anchors.left: labelText.right
    anchors.leftMargin: Look.gapLg
    anchors.right: toggle.left
    anchors.rightMargin: Look.gapLg
    anchors.verticalCenter: parent.verticalCenter
    text: root.help
    color: Look.muted
    font.pixelSize: Look.caption
    wrapMode: Text.WordWrap
    // Three lines: Live pushes says what it allows and when it turns off.
    maximumLineCount: 3
    elide: Text.ElideRight
  }

  ToggleSwitch {
    id: toggle
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    checked: root.checked
    hasCursor: root.selected
    interactive: false
    cursorRing: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: root.label
    Accessible.onPressAction: root.toggled()
  }
}
