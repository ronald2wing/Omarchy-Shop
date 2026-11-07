import QtQuick
import qs.Ui

// The base of every selectable list row (StoreRow, BackupRow,
// DiscoveredStoreRow): the kit's cursor surface, lit while `selected`; hovering
// moves the view's cursor here (hoveredRow) and a click or the accessible
// press action emits activated(). The row draws its own content on top.
//
// Contract: selected; signals activated(), hoveredRow().
CursorSurface {
  id: root

  property bool selected: false

  signal activated()
  signal hoveredRow()

  hasCursor: root.selected

  Accessible.role: Accessible.ListItem
  Accessible.onPressAction: root.activated()

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: root.hoveredRow()
    onClicked: root.activated()
  }
}
