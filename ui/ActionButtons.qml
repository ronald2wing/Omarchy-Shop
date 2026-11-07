pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// SmallButtons for an [{id, label}] list, in a row that wraps when given a
// width (a Flow without one stays a row). cursorIndex lights one button
// for the panel cursor (-1 none); the owner's sizes pass through.
//
// Contract: actions; cursorIndex; fontSize, horizontalPadding,
// verticalPadding (SmallButton's defaults); signal actionPicked(id).
Flow {
  id: root

  property var actions: []
  property int cursorIndex: -1
  property real fontSize: Look.small
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.xs

  signal actionPicked(string id)

  spacing: Look.gapMd

  Repeater {
    model: root.actions

    delegate: SmallButton {
      required property var modelData
      required property int index
      text: String(modelData.label)
      fontSize: root.fontSize
      horizontalPadding: root.horizontalPadding
      verticalPadding: root.verticalPadding
      hasCursor: root.cursorIndex === index
      onClicked: root.actionPicked(String(modelData.id))
      Accessible.role: Accessible.Button
      Accessible.name: String(modelData.label)
      Accessible.onPressAction: root.actionPicked(String(modelData.id))
    }
  }
}
