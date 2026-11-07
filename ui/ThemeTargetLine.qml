import QtQuick
import qs.Commons
import qs.Ui

// The Theme card's target line: the target theme's name, a LIVE chip, a
// lock while live pushes are off, the folder (elided in the middle) and a
// status dot; the folder warning wraps underneath when there is one.
//
// Contract: targetName; showLive (draw the LIVE chip); locked; folderText;
// folderTone ok | warn | error | info (the dot); folderWarning ("" hides
// the line); liveChipShown (read back).
Column {
  id: root

  property string targetName: ""
  property bool showLive: false
  property bool locked: false
  property string folderText: ""
  property string folderTone: "info"
  property string folderWarning: ""

  readonly property bool liveChipShown: liveChip.visible

  spacing: Look.gapXs

  Item {
    width: parent.width
    height: Math.max(nameLabel.implicitHeight, liveChip.height)

    PlainLabel {
      id: nameLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, parent.width * 0.4)
      text: root.targetName
      font.bold: true
      elide: Text.ElideRight
    }

    LiveChip {
      id: liveChip
      visible: root.showLive
      anchors.left: nameLabel.right
      anchors.leftMargin: Look.gapMd
      anchors.verticalCenter: parent.verticalCenter
      width: visible ? implicitWidth : 0
    }

    PlainLabel {
      id: lockGlyph
      visible: root.locked
      anchors.left: liveChip.visible ? liveChip.right : nameLabel.right
      anchors.leftMargin: Look.gapMd
      anchors.verticalCenter: parent.verticalCenter
      text: "󰌾"
      color: Look.warn
      font.pixelSize: Look.small

      HoverTip { text: Copy.t("theme.tip.locked") }
    }

    PlainLabel {
      anchors.left: lockGlyph.visible ? lockGlyph.right : (liveChip.visible ? liveChip.right : nameLabel.right)
      anchors.leftMargin: Look.gapLg
      anchors.right: statusDot.left
      anchors.rightMargin: Look.gapMd
      anchors.verticalCenter: parent.verticalCenter
      text: root.folderText
      color: Look.muted
      elide: Text.ElideMiddle
    }

    Rectangle {
      id: statusDot
      anchors.right: parent.right
      anchors.rightMargin: Look.gapSm
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(8)
      height: width
      radius: width / 2
      color: Look.toneColor(root.folderTone)
      opacity: root.folderTone === "info" ? 0.5 : 1

      // A wider hit area than the dot, but the tooltip anchors to the dot.
      MouseArea {
        id: dotArea
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
      }

      PanelToolTip {
        visible: dotArea.containsMouse
        text: root.folderWarning !== "" ? root.folderWarning : root.folderText
      }
    }
  }

  PlainLabel {
    visible: root.folderWarning !== ""
    width: parent.width
    text: root.folderWarning
    color: Look.toneColor(root.folderTone)
    font.pixelSize: Look.small
    wrapMode: Text.WordWrap
  }
}
