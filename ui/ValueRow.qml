import QtQuick

// One labelled row of a form (Settings): the label column (RowLabel, lit
// while the row holds the keyboard cursor), then either a value text that
// runs up to the trailing controls, or controls placed right after the
// label (children of the row). Everything is centred vertically. An empty
// label keeps its column, so a lone button lines up with the values above.
//
// Contract: label; lit; value ("" hides it); valueColor; valueElide;
// valueWraps (word-wrap, at most valueMaxLines lines); children are the
// leading controls; trailing: [items] on the right edge; minHeight (keeps
// the row's height while a control is hidden).
Item {
  id: root

  property string label: ""
  property bool lit: false
  property string value: ""
  property color valueColor: Look.fg
  property int valueElide: Text.ElideRight
  property bool valueWraps: false
  property int valueMaxLines: 1000
  property real minHeight: 0
  default property alias controls: controlRow.data
  property alias trailing: trailingRow.data

  height: Math.max(root.minHeight, root.label !== "" ? labelText.implicitHeight : 0,
                   valueText.visible ? valueText.implicitHeight : 0,
                   controlRow.implicitHeight, trailingRow.implicitHeight)

  RowLabel {
    id: labelText
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    lit: root.lit
  }

  Row {
    id: controlRow
    anchors.left: labelText.right
    anchors.leftMargin: Look.gapLg
    anchors.verticalCenter: parent.verticalCenter
    spacing: Look.gapMd
  }

  PlainLabel {
    id: valueText
    visible: root.value !== ""
    anchors.left: labelText.right
    anchors.leftMargin: Look.gapLg
    anchors.right: trailingRow.left
    anchors.rightMargin: trailingRow.children.length > 0 ? Look.gapLg : 0
    anchors.verticalCenter: parent.verticalCenter
    text: root.value
    color: root.valueColor
    wrapMode: root.valueWraps ? Text.WordWrap : Text.NoWrap
    maximumLineCount: root.valueMaxLines
    elide: root.valueElide
  }

  Row {
    id: trailingRow
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Look.gapMd
  }
}
