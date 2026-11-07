pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

// Title row shared by every view: optional back arrow or lead icon, a
// title with a muted subtitle, and compact actions on the trailing edge.
//
// Contract: title; subtitle; icon; canGoBack; actions [{id, icon, label?,
// tooltip?}] (keep the list static: state goes in busyIds / disabledIds);
// signals back(), actionPicked(id).
Item {
  id: root

  property string title: ""
  property string subtitle: ""
  property string icon: ""
  property bool canGoBack: false
  // Reassigning the list rebuilds every button and loses a click, hover or
  // spin in progress, so changing state goes in busyIds / disabledIds.
  property var actions: []
  property var busyIds: []
  property var disabledIds: []

  signal back()
  signal actionPicked(string id)

  implicitHeight: Math.max(titleColumn.implicitHeight, actionRow.implicitHeight, backButton.implicitHeight)

  PanelActionButton {
    id: backButton
    visible: root.canGoBack
    anchors.left: parent.left
    anchors.verticalCenter: titleColumn.verticalCenter
    iconText: "󰁍"
    tooltipText: Copy.t("action.back")
    onClicked: root.back()
    Accessible.role: Accessible.Button
    Accessible.name: Copy.t("action.back")
    Accessible.onPressAction: root.back()
  }

  PlainLabel {
    id: leadIcon
    visible: !root.canGoBack && root.icon !== ""
    anchors.left: parent.left
    anchors.verticalCenter: titleColumn.verticalCenter
    text: root.icon
    font.pixelSize: Look.heading
  }

  Column {
    id: titleColumn
    anchors.left: root.canGoBack ? backButton.right : (leadIcon.visible ? leadIcon.right : parent.left)
    anchors.leftMargin: root.canGoBack || leadIcon.visible ? Look.gapLg : 0
    anchors.right: actionRow.left
    anchors.rightMargin: Look.gapLg
    anchors.top: parent.top
    spacing: Style.space(1)

    PlainLabel {
      width: parent.width
      text: root.title
      font.pixelSize: Look.title
      font.bold: true
      elide: Text.ElideRight
    }

    PlainLabel {
      visible: root.subtitle !== ""
      width: parent.width
      text: root.subtitle
      color: Look.muted
      font.pixelSize: Look.caption
      elide: Text.ElideRight
    }
  }

  Row {
    id: actionRow
    anchors.right: parent.right
    anchors.verticalCenter: titleColumn.verticalCenter
    spacing: Look.gapXs

    Repeater {
      model: root.actions

      delegate: Button {
        required property var modelData
        iconText: modelData.icon || ""
        text: modelData.label || ""
        tooltipText: modelData.tooltip || ""
        iconSpinning: root.busyIds.indexOf(String(modelData.id)) >= 0
        enabled: root.disabledIds.indexOf(String(modelData.id)) < 0
        opacity: enabled ? 1 : Look.disabledOpacity
        fontSize: Look.small
        horizontalPadding: Style.spacing.md
        verticalPadding: Style.spacing.xs
        onClicked: root.actionPicked(String(modelData.id))
        Accessible.role: Accessible.Button
        Accessible.name: modelData.tooltip || modelData.label || ""
        Accessible.onPressAction: root.actionPicked(String(modelData.id))
      }
    }
  }
}
