import QtQuick
import qs.Commons

// A store found on the Shopify account: its name, its domain, and Add. A
// store already in Shop offers Open instead, so the list never dead-ends.
//
// Contract: row; inShop; selected, activated() and hoveredRow() come from
// ListRow; a click or the button emits activated() (the view adds the
// store, or opens it when it is already in Shop).
ListRow {
  id: root

  // {domain, name}
  property var row: null
  // The store is already in Shop: the row opens it instead of adding it.
  property bool inShop: false

  readonly property string nameText: root.row && root.row.name ? String(root.row.name) : ""
  readonly property string domainText: root.row ? String(root.row.domain || "") : ""

  implicitHeight: Math.max(nameLabel.implicitHeight, actionButton.implicitHeight) + Style.spacing.md * 2

  Accessible.name: root.nameText + ", " + root.domainText

  PlainLabel {
    id: nameLabel
    anchors.left: parent.left
    anchors.leftMargin: Look.rowPadX
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(implicitWidth, (parent.width - Look.rowPadX * 2) * 0.45)
    text: root.nameText !== "" ? root.nameText : root.domainText
    font.bold: root.selected
    elide: Text.ElideRight
  }

  PlainLabel {
    anchors.left: nameLabel.right
    anchors.leftMargin: Look.gapLg
    anchors.right: actionButton.left
    anchors.rightMargin: Look.gapLg
    anchors.verticalCenter: parent.verticalCenter
    visible: root.nameText !== ""
    text: root.domainText
    color: Look.muted
    font.pixelSize: Look.small
    elide: Text.ElideMiddle
  }

  SmallButton {
    id: actionButton
    anchors.right: parent.right
    anchors.rightMargin: Look.rowPadX
    anchors.verticalCenter: parent.verticalCenter
    text: root.inShop ? Copy.t("action.open") : Copy.t("add.add")
    bordered: !root.inShop
    verticalPadding: Style.spacing.xxs
    onClicked: root.activated()
  }
}
