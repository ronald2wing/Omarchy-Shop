pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// A calm, centred placeholder: icon, body and actions (the body
// says it all; a heading would only repeat the view's title).
//
// Contract: icon; body; actions [{id, label}] (kit buttons in a row);
// cursorIndex lights one button for the panel cursor (-1 none);
// activate() runs the lit one; signal actionPicked(id).
Column {
  id: root

  property string icon: ""
  property string body: ""
  property var actions: []
  property int cursorIndex: -1

  signal actionPicked(string id)

  function activate() {
    var a = root.actions[root.cursorIndex]
    if (!a) return
    root.actionPicked(String(a.id))
  }

  spacing: Look.gapMd
  topPadding: Look.gapLg
  bottomPadding: Look.gapLg

  PlainLabel {
    anchors.horizontalCenter: parent.horizontalCenter
    text: root.icon
    color: Look.muted
    font.pixelSize: Look.display
  }

  PlainLabel {
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    text: root.body
    color: Look.muted
    wrapMode: Text.WordWrap
  }

  ActionButtons {
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Look.gapLg
    topPadding: Look.gapSm
    actions: root.actions
    fontSize: Style.font.body
    verticalPadding: Style.spacing.controlPaddingY
    cursorIndex: root.cursorIndex
    onActionPicked: (id) => root.actionPicked(id)
  }
}
